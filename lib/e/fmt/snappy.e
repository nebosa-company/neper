// Snappy, both the raw block format and the framing format, over caller
// storage. Raw: a varint uncompressed length, then elements tagged 00
// (literal, 1-5 length bytes), 01 (copy, 1-byte offset: length 4-11, 11-bit
// offset), 10 (copy, 2-byte LE offset, length 1-64) and 11 (copy, 4-byte
// offset). The encoder is the reference block encoder: the input is cut into
// 64 KiB blocks, each compressed against a fresh hash table of `u16`
// positions (`table_required()` entries); a match is four bytes or more,
// copies are cut at 64 as the reference does, so a reference decoder reads
// the output. The decoder is strict: a bad tag, an offset before the start,
// or more or less output than the preamble promises is `Invalid`; a `dst`
// shorter than the preamble is `TooSmall`.
//
// Framing: the stream identifier chunk `ff 06 00 00 sNaPpY`, then compressed
// (0x00) or uncompressed (0x01) chunks of at most 65536 bytes of data, each
// prefixed by a masked CRC32C of the uncompressed data
// (`((crc >> 15) | (crc << 17)) + 0xa282ead8`). A chunk is written
// uncompressed when compression saves less than an eighth, as the reference
// does; an empty input is an empty stream, as the reference writes.
// Skippable chunks (0x80-0xfe) are skipped; reserved unskippable chunks
// (0x02-0x7f) are `Invalid`; a CRC mismatch is `Checksum`.

error Invalid
error TooSmall
error Checksum

fn block_size() -> usize { ret 65536usize }
fn table_bits() -> u32 { ret 14u32 }

// Entries of the `u16` hash table `encode` needs.
fn table_required() -> usize { ret 1usize << table_bits() }

// The most bytes `encode` writes for `n` input bytes.
fn bound(n: usize) -> usize { ret 32usize + n + n / 6usize }

// The most bytes `encode_framed` writes for `n` input bytes.
fn bound_framed(n: usize) -> usize {
    let chunks = (n + block_size() - 1usize) / block_size()
    ret 10usize + chunks * 41usize + n + n / 6usize
}

fn load32(src: []const u8, at: usize) -> u32 {
    ret u32(src[at]) | (u32(src[at + 1usize]) << 8u32) | (u32(src[at + 2usize]) << 16u32) | (u32(src[at + 3usize]) << 24u32)
}

fn hash(v: u32, shift: u32) -> u32 { ret (v *% 506832829u32) >> shift }

fn put_varint(dst: []u8, v: usize) -> (usize, err) {
    var x = v
    var at = 0usize
    while x >= 128usize {
        if at >= dst.len { ret (0usize, TooSmall) }
        dst[at] = u8((x & 127usize) | 128usize)
        x = x >> 7u32
        at += 1usize
    }
    if at >= dst.len { ret (0usize, TooSmall) }
    dst[at] = u8(x)
    ret (at + 1usize, ok)
}

// Writes the literal `lit` at `dst[d..]`; answers the new `d`.
fn emit_literal(dst: []u8, d: usize, lit: []const u8) -> (usize, err) {
    if lit.len == 0usize { ret (d, ok) }
    let n = lit.len - 1usize
    var at = d
    if n < 60usize {
        if at + 1usize > dst.len { ret (d, TooSmall) }
        dst[at] = u8(n << 2u32)
        at += 1usize
    } else if n < 256usize {
        if at + 2usize > dst.len { ret (d, TooSmall) }
        dst[at] = 240u8
        dst[at + 1usize] = u8(n)
        at += 2usize
    } else {
        if at + 3usize > dst.len { ret (d, TooSmall) }
        dst[at] = 244u8
        dst[at + 1usize] = u8(n & 255usize)
        dst[at + 2usize] = u8((n >> 8u32) & 255usize)
        at += 3usize
    }
    if at + lit.len > dst.len { ret (d, TooSmall) }
    var i = 0usize
    while i < lit.len {
        dst[at + i] = lit[i]
        i += 1usize
    }
    ret (at + lit.len, ok)
}

fn emit_copy2(dst: []u8, d: usize, offset: usize, length: usize) -> (usize, err) {
    if d + 3usize > dst.len { ret (d, TooSmall) }
    dst[d] = u8(((length - 1usize) << 2u32) | 2usize)
    dst[d + 1usize] = u8(offset & 255usize)
    dst[d + 2usize] = u8((offset >> 8u32) & 255usize)
    ret (d + 3usize, ok)
}

// Writes a copy of `length` bytes from `offset` back, cut as the reference does.
fn emit_copy(dst: []u8, d: usize, offset: usize, length: usize) -> (usize, err) {
    var at = d
    var left = length
    while left >= 68usize {
        let (next_at, e) = emit_copy2(dst, at, offset, 64usize)
        if e != ok { ret (d, e) }
        at = next_at
        left -= 64usize
    }
    if left > 64usize {
        let (next_at, e) = emit_copy2(dst, at, offset, 60usize)
        if e != ok { ret (d, e) }
        at = next_at
        left -= 60usize
    }
    if left >= 12usize || offset >= 2048usize {
        let (next_at, e) = emit_copy2(dst, at, offset, left)
        ret (next_at, e)
    }
    if at + 2usize > dst.len { ret (d, TooSmall) }
    dst[at] = u8(((offset >> 8u32) << 5u32) | ((left - 4usize) << 2u32) | 1usize)
    dst[at + 1usize] = u8(offset & 255usize)
    ret (at + 2usize, ok)
}

// One block of at most 64 KiB: the reference `encodeBlock`.
fn encode_block(src: []const u8, dst: []u8, d0: usize, table: []u16) -> (usize, err) {
    var d = d0
    if src.len < 17usize {
        let (end, e) = emit_literal(dst, d, src)
        ret (end, e)
    }
    var shift = 24u32
    var table_size = 256usize
    while table_size < table_required() && table_size < src.len {
        shift -= 1u32
        table_size = table_size << 1u32
    }
    var i = 0usize
    while i < table_size {
        table[i] = 0u16
        i += 1usize
    }
    let mask = u32(table_size - 1usize)
    let s_limit = src.len - 15usize
    var next_emit = 0usize
    var s = 1usize
    var next_hash = hash(load32(src, s), shift)
    var candidate = 0usize
    var searching = true
    while searching {
        var skip = 32usize
        var next_s = s
        var found = false
        while !found {
            s = next_s
            let between = skip >> 5u32
            next_s = s + between
            skip += between
            if next_s > s_limit {
                searching = false
                found = true
            } else {
                candidate = usize(table[usize(next_hash & mask)])
                table[usize(next_hash & mask)] = u16(s)
                next_hash = hash(load32(src, next_s), shift)
                if load32(src, s) == load32(src, candidate) { found = true }
            }
        }
        if !searching { continue }
        let (after_lit, lit_error) = emit_literal(dst, d, src[next_emit..s])
        if lit_error != ok { ret (d0, lit_error) }
        d = after_lit
        var extending = true
        while extending {
            let base = s
            s += 4usize
            var c = candidate + 4usize
            while s < src.len && src[c] == src[s] {
                c += 1usize
                s += 1usize
            }
            let (after_copy, copy_error) = emit_copy(dst, d, base - candidate, s - base)
            if copy_error != ok { ret (d0, copy_error) }
            d = after_copy
            next_emit = s
            if s >= s_limit {
                searching = false
                extending = false
            } else {
                let prev = load32(src, s - 1usize)
                let cur = load32(src, s)
                table[usize(hash(prev, shift) & mask)] = u16(s - 1usize)
                let cur_hash = hash(cur, shift)
                candidate = usize(table[usize(cur_hash & mask)])
                table[usize(cur_hash & mask)] = u16(s)
                if cur != load32(src, candidate) {
                    next_hash = hash(load32(src, s + 1usize), shift)
                    s += 1usize
                    extending = false
                }
            }
        }
    }
    if next_emit < src.len {
        let (end, e) = emit_literal(dst, d, src[next_emit..])
        if e != ok { ret (d0, e) }
        d = end
    }
    ret (d, ok)
}

// Compresses `src` into `dst` (at least `bound(src.len)` bytes to be safe)
// with `table` of `table_required()` entries; answers the bytes written.
fn encode(src: []const u8, dst: []u8, table: []u16) -> (usize, err) {
    if table.len < table_required() { ret (0usize, TooSmall) }
    let (head, head_error) = put_varint(dst, src.len)
    if head_error != ok { ret (0usize, head_error) }
    var d = head
    var at = 0usize
    while at < src.len {
        var end = at + block_size()
        if end > src.len { end = src.len }
        let (next_d, e) = encode_block(src[at..end], dst, d, table)
        if e != ok { ret (0usize, e) }
        d = next_d
        at = end
    }
    ret (d, ok)
}

fn get_varint(src: []const u8) -> (usize, usize, err) {
    var v = 0usize
    var at = 0usize
    var shift = 0u32
    while at < src.len && at < 5usize {
        let b = usize(src[at])
        v = v | ((b & 127usize) << shift)
        at += 1usize
        if b < 128usize {
            if v > 4294967295usize { ret (0usize, 0usize, Invalid) }
            ret (v, at, ok)
        }
        shift += 7u32
    }
    ret (0usize, 0usize, Invalid)
}

// The uncompressed length a raw stream promises.
fn decoded_length(src: []const u8) -> (usize, err) {
    let (n, _, e) = get_varint(src)
    ret (n, e)
}

// Decompresses a raw stream into `dst`; answers the bytes written.
fn decode(src: []const u8, dst: []u8) -> (usize, err) {
    let (n, head, head_error) = get_varint(src)
    if head_error != ok { ret (0usize, head_error) }
    if n > dst.len { ret (0usize, TooSmall) }
    var s = head
    var d = 0usize
    while s < src.len {
        let tag = usize(src[s])
        var length = 0usize
        var offset = 0usize
        if (tag & 3usize) == 0usize {
            var x = tag >> 2u32
            if x < 60usize {
                s += 1usize
            } else {
                let extra = x - 59usize
                if s + 1usize + extra > src.len { ret (d, Invalid) }
                x = 0usize
                var k = extra
                while k > 0usize {
                    x = (x << 8u32) | usize(src[s + k])
                    k -= 1usize
                }
                s += 1usize + extra
            }
            length = x + 1usize
            if length > n - d || length > src.len - s { ret (d, Invalid) }
            var i = 0usize
            while i < length {
                dst[d + i] = src[s + i]
                i += 1usize
            }
            d += length
            s += length
            continue
        } else if (tag & 3usize) == 1usize {
            if s + 2usize > src.len { ret (d, Invalid) }
            length = 4usize + ((tag >> 2u32) & 7usize)
            offset = ((tag & 224usize) << 3u32) | usize(src[s + 1usize])
            s += 2usize
        } else if (tag & 3usize) == 2usize {
            if s + 3usize > src.len { ret (d, Invalid) }
            length = 1usize + (tag >> 2u32)
            offset = usize(src[s + 1usize]) | (usize(src[s + 2usize]) << 8u32)
            s += 3usize
        } else {
            if s + 5usize > src.len { ret (d, Invalid) }
            length = 1usize + (tag >> 2u32)
            offset = usize(load32(src, s + 1usize))
            s += 5usize
        }
        if offset == 0usize || d < offset || length > n - d { ret (d, Invalid) }
        var i = 0usize
        while i < length {
            dst[d + i] = dst[d + i - offset]
            i += 1usize
        }
        d += length
    }
    if d != n { ret (d, Invalid) }
    ret (d, ok)
}

// CRC-32C (Castagnoli, reflected polynomial 0x82F63B78).
fn crc32c(data: []const u8) -> u32 {
    var c = 4294967295u32
    var at = 0usize
    while at < data.len {
        c = c ^ u32(data[at])
        var bit = 0usize
        while bit < 8usize {
            let low = c & 1u32
            c = c >> 1u32
            if low != 0u32 { c = c ^ 2197175160u32 }
            bit += 1usize
        }
        at += 1usize
    }
    ret c ^ 4294967295u32
}

fn masked_crc(data: []const u8) -> u32 {
    let c = crc32c(data)
    ret ((c >> 15u32) | (c << 17u32)) +% 2726488792u32
}

// A chunk header: the type, the 3-byte LE length of CRC and data, the masked CRC.
fn put_chunk_head(dst: []u8, at: usize, kind: u8, size: usize, crc: u32) {
    dst[at] = kind
    dst[at + 1usize] = u8(size & 255usize)
    dst[at + 2usize] = u8((size >> 8u32) & 255usize)
    dst[at + 3usize] = u8((size >> 16u32) & 255usize)
    dst[at + 4usize] = u8(crc & 255u32)
    dst[at + 5usize] = u8((crc >> 8u32) & 255u32)
    dst[at + 6usize] = u8((crc >> 16u32) & 255u32)
    dst[at + 7usize] = u8(crc >> 24u32)
}

// Writes `src` as a framed stream into `dst` (`bound_framed(src.len)` bytes
// to be safe); answers the bytes written. An empty input is an empty stream.
fn encode_framed(src: []const u8, dst: []u8, table: []u16) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    if dst.len < 10usize { ret (0usize, TooSmall) }
    let ident: [10]u8 = [10]u8{ 255, 6, 0, 0, 115, 78, 97, 80, 112, 89 }
    var i = 0usize
    while i < 10usize {
        dst[i] = ident[i]
        i += 1usize
    }
    var d = 10usize
    var at = 0usize
    while at < src.len {
        var end = at + block_size()
        if end > src.len { end = src.len }
        let chunk = src[at..end]
        if d + 8usize + bound(chunk.len) > dst.len { ret (0usize, TooSmall) }
        let crc = masked_crc(chunk)
        let (packed, e) = encode(chunk, dst[d + 8usize..], table)
        if e != ok { ret (0usize, e) }
        if packed >= chunk.len - chunk.len / 8usize {
            put_chunk_head(dst, d, 1u8, chunk.len + 4usize, crc)
            i = 0usize
            while i < chunk.len {
                dst[d + 8usize + i] = chunk[i]
                i += 1usize
            }
            d += 8usize + chunk.len
        } else {
            put_chunk_head(dst, d, 0u8, packed + 4usize, crc)
            d += 8usize + packed
        }
        at = end
    }
    ret (d, ok)
}

// Reads a framed stream into `dst`; answers the bytes written.
fn decode_framed(src: []const u8, dst: []u8) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    let ident: [10]u8 = [10]u8{ 255, 6, 0, 0, 115, 78, 97, 80, 112, 89 }
    var s = 0usize
    var d = 0usize
    var first = true
    while s < src.len {
        if s + 4usize > src.len { ret (d, Invalid) }
        let kind = src[s]
        let size = usize(src[s + 1usize]) | (usize(src[s + 2usize]) << 8u32) | (usize(src[s + 3usize]) << 16u32)
        s += 4usize
        if size > src.len - s { ret (d, Invalid) }
        let body = src[s..s + size]
        s += size
        if kind == 255u8 {
            if size != 6usize { ret (d, Invalid) }
            var i = 0usize
            while i < 6usize {
                if body[i] != ident[4usize + i] { ret (d, Invalid) }
                i += 1usize
            }
            first = false
            continue
        }
        if first { ret (d, Invalid) }
        if kind >= 128u8 { continue }
        if kind > 1u8 { ret (d, Invalid) }
        if size < 4usize { ret (d, Invalid) }
        let crc = u32(body[0]) | (u32(body[1]) << 8u32) | (u32(body[2]) << 16u32) | (u32(body[3]) << 24u32)
        let data = body[4usize..]
        var produced = 0usize
        if kind == 0u8 {
            let (n, e) = decode(data, dst[d..])
            if e != ok { ret (d, e) }
            produced = n
        } else {
            if data.len > dst.len - d { ret (d, TooSmall) }
            var i = 0usize
            while i < data.len {
                dst[d + i] = data[i]
                i += 1usize
            }
            produced = data.len
        }
        if produced > block_size() { ret (d, Invalid) }
        if masked_crc(dst[d..d + produced]) != crc { ret (d, Checksum) }
        d += produced
    }
    ret (d, ok)
}
