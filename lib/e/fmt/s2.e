// S2, the Snappy extension of the klauspost/compress library, as raw blocks and as
// the framing format, over caller storage and beside `e.fmt.snappy` (whose
// varint, literal, hash and CRC helpers it reuses).
//
// A block is a varint uncompressed length and tagged elements. Literals are
// Snappy's (tag 00). The copy tags change: 01 is a copy of 4-11 bytes with an
// 11-bit offset, *except* that offset zero means "the previous offset again"
// and the length codes 5, 6 and 7 then take 1, 2 or 3 extra bytes
// (length = byte + 8, u16 + 260, u24 + 65540); 10 is a copy of 1-64 bytes with a
// 2-byte offset; 11 a copy of 1-64 bytes with a 4-byte offset. The decoder is
// strict: a bad tag, an offset of zero before any copy set one, an offset before
// the start of the output, or more or less output than the preamble promises is
// `Invalid`; a `dst` shorter than the preamble is `TooSmall`.
//
// The encoder cuts the input into 64 KiB blocks, each against a fresh hash table
// of `u16` positions (`table_required()` entries), finds matches of four bytes or
// more as Snappy's does and writes a match at the previous offset as a repeat, so
// the reference decoder reads its output. A match is one 01 copy when it is 4-11
// bytes at an offset below 2048, otherwise 10 copies of up to 64 bytes and a
// repeat for the rest.
//
// Framing: the stream identifier chunk `ff 06 00 00 S2sTwO`, then compressed
// (0x00) or uncompressed (0x01) chunks of at most 4 MiB of data, each prefixed by
// the masked CRC32C Snappy uses. The decoder also takes a Snappy stream
// (`sNaPpY`), skips the skippable chunks (0x80-0xfe) and refuses the reserved
// unskippable ones (0x02-0x7f) as `Invalid`; a CRC mismatch is `Checksum`.

use e.fmt.snappy as snappy

error Invalid
error TooSmall
error Checksum

fn block_size() -> usize { ret 65536usize }

// The largest data a chunk of the framing format carries.
fn max_chunk() -> usize { ret 4194304usize }

// Entries of the `u16` hash table `encode` needs.
fn table_required() -> usize { ret snappy.table_required() }

// The most bytes `encode` writes for `n` input bytes.
fn bound(n: usize) -> usize { ret 32usize + n + n / 6usize }

// The most bytes `encode_framed` writes for `n` input bytes.
fn bound_framed(n: usize) -> usize {
    let chunks = (n + block_size() - 1usize) / block_size()
    ret 10usize + chunks * 41usize + n + n / 6usize
}

// A repeat of the previous offset, `length` >= 4 and at most 65795 bytes.
fn emit_repeat(dst: []u8, d: usize, length: usize) -> (usize, err) {
    if length <= 8usize {
        if d + 2usize > dst.len { ret (d, TooSmall) }
        dst[d] = u8(((length - 4usize) << 2u32) | 1usize)
        dst[d + 1usize] = 0u8
        ret (d + 2usize, ok)
    }
    if length < 264usize {
        if d + 3usize > dst.len { ret (d, TooSmall) }
        dst[d] = 21u8
        dst[d + 1usize] = 0u8
        dst[d + 2usize] = u8(length - 8usize)
        ret (d + 3usize, ok)
    }
    if d + 4usize > dst.len { ret (d, TooSmall) }
    let n = length - 260usize
    dst[d] = 25u8
    dst[d + 1usize] = 0u8
    dst[d + 2usize] = u8(n & 255usize)
    dst[d + 3usize] = u8((n >> 8u32) & 255usize)
    ret (d + 4usize, ok)
}

fn emit_copy2(dst: []u8, d: usize, offset: usize, length: usize) -> (usize, err) {
    if d + 3usize > dst.len { ret (d, TooSmall) }
    dst[d] = u8(((length - 1usize) << 2u32) | 2usize)
    dst[d + 1usize] = u8(offset & 255usize)
    dst[d + 2usize] = u8((offset >> 8u32) & 255usize)
    ret (d + 3usize, ok)
}

// A copy of `length` >= 4 bytes from `offset` (< 65536) back; `last` is the offset the
// decoder holds (0 before any copy).
fn emit_copy(dst: []u8, d: usize, offset: usize, length: usize, last: usize) -> (usize, err) {
    if offset == last {
        let (rep_at, rep_error) = emit_repeat(dst, d, length)
        ret (rep_at, rep_error)
    }
    if length <= 11usize && offset < 2048usize {
        if d + 2usize > dst.len { ret (d, TooSmall) }
        dst[d] = u8(((offset >> 8u32) << 5u32) | ((length - 4usize) << 2u32) | 1usize)
        dst[d + 1usize] = u8(offset & 255usize)
        ret (d + 2usize, ok)
    }
    var piece = length
    if piece > 64usize { piece = 64usize }
    let (after, e) = emit_copy2(dst, d, offset, piece)
    if e != ok { ret (d, e) }
    let rest = length - piece
    if rest == 0usize { ret (after, ok) }
    if rest >= 4usize {
        let (rep_at, rep_error) = emit_repeat(dst, after, rest)
        ret (rep_at, rep_error)
    }
    let (tail_at, tail_error) = emit_copy2(dst, after, offset, rest)
    ret (tail_at, tail_error)
}

// One block of at most 64 KiB.
fn encode_block(src: []const u8, dst: []u8, d0: usize, table: []u16) -> (usize, err) {
    var d = d0
    if src.len < 17usize {
        let (end, e) = snappy.emit_literal(dst, d, src)
        if e != ok { ret (d0, TooSmall) }
        ret (end, ok)
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
    var last = 0usize
    var s = 1usize
    var next_hash = snappy.hash(snappy.load32(src, s), shift)
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
                next_hash = snappy.hash(snappy.load32(src, next_s), shift)
                if snappy.load32(src, s) == snappy.load32(src, candidate) { found = true }
            }
        }
        if !searching { continue }
        let (after_lit, lit_error) = snappy.emit_literal(dst, d, src[next_emit..s])
        if lit_error != ok { ret (d0, TooSmall) }
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
            let (after_copy, copy_error) = emit_copy(dst, d, base - candidate, s - base, last)
            if copy_error != ok { ret (d0, copy_error) }
            last = base - candidate
            d = after_copy
            next_emit = s
            if s >= s_limit {
                searching = false
                extending = false
            } else {
                let prev = snappy.load32(src, s - 1usize)
                let cur = snappy.load32(src, s)
                table[usize(snappy.hash(prev, shift) & mask)] = u16(s - 1usize)
                let cur_hash = snappy.hash(cur, shift)
                candidate = usize(table[usize(cur_hash & mask)])
                table[usize(cur_hash & mask)] = u16(s)
                if cur != snappy.load32(src, candidate) {
                    next_hash = snappy.hash(snappy.load32(src, s + 1usize), shift)
                    s += 1usize
                    extending = false
                }
            }
        }
    }
    if next_emit < src.len {
        let (end, e) = snappy.emit_literal(dst, d, src[next_emit..])
        if e != ok { ret (d0, TooSmall) }
        d = end
    }
    ret (d, ok)
}

// Compresses `src` into `dst` (at least `bound(src.len)` bytes to be safe) with
// `table` of `table_required()` entries; answers the bytes written.
fn encode(src: []const u8, dst: []u8, table: []u16) -> (usize, err) {
    if table.len < table_required() { ret (0usize, TooSmall) }
    let (head, head_error) = snappy.put_varint(dst, src.len)
    if head_error != ok { ret (0usize, TooSmall) }
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

// The uncompressed length a block promises.
fn decoded_length(src: []const u8) -> (usize, err) {
    let (n, _, e) = snappy.get_varint(src)
    if e != ok { ret (0usize, Invalid) }
    ret (n, ok)
}

// Decompresses a block into `dst`; answers the bytes written.
fn decode(src: []const u8, dst: []u8) -> (usize, err) {
    let (n, head, head_error) = snappy.get_varint(src)
    if head_error != ok { ret (0usize, Invalid) }
    if n > dst.len { ret (0usize, TooSmall) }
    var s = head
    var d = 0usize
    var offset = 0usize
    while s < src.len {
        let tag = usize(src[s])
        var length = 0usize
        let kind = tag & 3usize
        if kind == 0usize {
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
        } else if kind == 1usize {
            if s + 2usize > src.len { ret (d, Invalid) }
            length = (tag >> 2u32) & 7usize
            let near = ((tag & 224usize) << 3u32) | usize(src[s + 1usize])
            s += 2usize
            if near == 0usize {
                if length == 5usize {
                    if s + 1usize > src.len { ret (d, Invalid) }
                    length = usize(src[s]) + 4usize
                    s += 1usize
                } else if length == 6usize {
                    if s + 2usize > src.len { ret (d, Invalid) }
                    length = (usize(src[s]) | (usize(src[s + 1usize]) << 8u32)) + 256usize
                    s += 2usize
                } else if length == 7usize {
                    if s + 3usize > src.len { ret (d, Invalid) }
                    length = (usize(src[s]) | (usize(src[s + 1usize]) << 8u32) | (usize(src[s + 2usize]) << 16u32)) + 65536usize
                    s += 3usize
                }
            } else {
                offset = near
            }
            length += 4usize
        } else if kind == 2usize {
            if s + 3usize > src.len { ret (d, Invalid) }
            length = 1usize + (tag >> 2u32)
            offset = usize(src[s + 1usize]) | (usize(src[s + 2usize]) << 8u32)
            s += 3usize
        } else {
            if s + 5usize > src.len { ret (d, Invalid) }
            length = 1usize + (tag >> 2u32)
            offset = usize(snappy.load32(src, s + 1usize))
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

// Writes `src` as a framed stream into `dst` (`bound_framed(src.len)` bytes to be
// safe); answers the bytes written. An empty input is the stream identifier alone.
fn encode_framed(src: []const u8, dst: []u8, table: []u16) -> (usize, err) {
    if dst.len < 10usize { ret (0usize, TooSmall) }
    let ident: [10]u8 = [10]u8{ 255, 6, 0, 0, 83, 50, 115, 84, 119, 79 }
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
        let crc = snappy.masked_crc(chunk)
        let (packed, e) = encode(chunk, dst[d + 8usize..], table)
        if e != ok { ret (0usize, e) }
        if packed >= chunk.len - chunk.len / 8usize {
            snappy.put_chunk_head(dst, d, 1u8, chunk.len + 4usize, crc)
            i = 0usize
            while i < chunk.len {
                dst[d + 8usize + i] = chunk[i]
                i += 1usize
            }
            d += 8usize + chunk.len
        } else {
            snappy.put_chunk_head(dst, d, 0u8, packed + 4usize, crc)
            d += 8usize + packed
        }
        at = end
    }
    ret (d, ok)
}

// Reads a framed S2 or Snappy stream into `dst`; answers the bytes written.
fn decode_framed(src: []const u8, dst: []u8) -> (usize, err) {
    if src.len == 0usize { ret (0usize, ok) }
    let ident: [10]u8 = [10]u8{ 255, 6, 0, 0, 83, 50, 115, 84, 119, 79 }
    let snappy_ident: [6]u8 = [6]u8{ 115, 78, 97, 80, 112, 89 }
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
            var same_s2 = true
            var same_snappy = true
            var i = 0usize
            while i < 6usize {
                if body[i] != ident[4usize + i] { same_s2 = false }
                if body[i] != snappy_ident[i] { same_snappy = false }
                i += 1usize
            }
            if !same_s2 && !same_snappy { ret (d, Invalid) }
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
        if produced > max_chunk() { ret (d, Invalid) }
        if snappy.masked_crc(dst[d..d + produced]) != crc { ret (d, Checksum) }
        d += produced
    }
    ret (d, ok)
}
