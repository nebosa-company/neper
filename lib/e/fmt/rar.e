// RAR5 archive reader (L120): decode only, over an archive held in memory. `open` walks
// the block headers (each CRC-32 checked), lists the files and `extract` returns one file:
// stored as it is, compressed by decoding the LZ77 + Huffman stream (the RAR5 "unpack 5"
// format: a block header per block, 20-symbol bit-length code, then the main, distance,
// low-distance and length codes, four repeat distances, a length that grows with the
// distance) and checking the file's CRC-32. A solid chain (files marked as continuing the
// previous one) is decoded as one stream into one buffer, so a match may reach back into
// an earlier file, and the whole chain is cached.
//
// Bounded before allocation: each declared unpacked size and the sum over a solid chain
// are checked against `Limits`, a block never reads past its declared size, a distance
// past the bytes produced or past the dictionary is `Invalid`, and a stream that produces
// more or less than the header declared is `Invalid`. Names with an absolute path, a
// drive, a NUL or a `..` segment are `Unsafe`. The first cut stops at: RAR 1.5-4.x
// archives (a different format), encrypted headers or files, the E8/E8E9/ARM/delta
// filters (symbol 256 of the main code), the version 7 dictionary extension, multi-volume
// archives and recovery records -- each `Unsupported`.

use e.algo.hash as hash
use e.mem

type Limits = struct { entries: usize, name_bytes: usize, file_bytes: usize, chain_bytes: usize }
type Entry = struct { name: str, size: u64, crc32: u32, has_crc: bool, directory: bool, method: u8, solid: bool, dict_log: u32, data_offset: usize, packed: usize }
type Archive = struct { state: *void }
type Huff = struct { count: [16]u16, symbol: [306]u16 }
type Bits = struct { data: []const u8, pos: usize, end: usize, bad: bool }
type State = struct { a: *mem.Arena, data: []const u8, limits: Limits, entries: []Entry, count: usize, name_budget: usize, chain_start: usize, chain_end: usize, chain: []u8, chain_has: bool, chain_offsets: []u64 }

error Invalid
error Unsupported
error Checksum
error TooLarge
error Unsafe

const NC: usize = 306usize
const DC: usize = 64usize
const LDC: usize = 16usize
const RC: usize = 44usize
const BC: usize = 20usize

fn default_limits() -> Limits {
    ret Limits { entries: 100000usize, name_bytes: 4194304usize, file_bytes: 268435456usize, chain_bytes: 268435456usize }
}

// ---- header cursor ----------------------------------------------------------------------

type Cur = struct { data: []const u8, at: usize, bad: bool }

fn rd_vint(c: *Cur) -> u64 {
    var value = 0u64
    var shift = 0u32
    while true {
        if c.at >= c.data.len || shift > 63u32 {
            c.bad = true
            ret 0u64
        }
        let b = c.data[c.at]
        c.at += 1usize
        value = value | (u64(b & 127u8) << shift)
        if (b & 128u8) == 0u8 { break }
        shift += 7u32
    }
    ret value
}

fn rd_u32(c: *Cur) -> u32 {
    if c.at + 4usize > c.data.len {
        c.bad = true
        c.at = c.data.len
        ret 0u32
    }
    let v = u32(c.data[c.at]) | (u32(c.data[c.at + 1usize]) << 8u32) | (u32(c.data[c.at + 2usize]) << 16u32) | (u32(c.data[c.at + 3usize]) << 24u32)
    c.at += 4usize
    ret v
}

fn unsafe_name(name: str) -> bool {
    if name.len == 0usize { ret false }
    if name[0] == 47u8 || name[0] == 92u8 { ret true }
    if name.len >= 2usize && name[1] == 58u8 { ret true }
    var start = 0usize
    var i = 0usize
    while i <= name.len {
        if i == name.len || name[i] == 47u8 || name[i] == 92u8 {
            if i - start == 2usize && name[start] == 46u8 && name[start + 1usize] == 46u8 { ret true }
            start = i + 1usize
        }
        if i < name.len && name[i] == 0u8 { ret true }
        i += 1usize
    }
    ret false
}

fn open(a: *mem.Arena, data: []const u8, limits: Limits) -> (Archive, err) {
    var archive: Archive = zero
    if data.len < 8usize { ret (archive, Invalid) }
    let sig = [7]u8{ 82u8, 97u8, 114u8, 33u8, 26u8, 7u8, 1u8 }
    var i = 0usize
    while i < 7usize {
        if data[i] != sig[i] {
            // "Rar!" 1A 07 00 is the RAR 1.5-4.x format
            if i == 6usize && data[6] == 0u8 { ret (archive, Unsupported) }
            ret (archive, Invalid)
        }
        i += 1usize
    }
    if data[7] != 0u8 { ret (archive, Invalid) }
    let (holder, holder_error) = mem.alloc[State](a, 1usize)
    if holder_error != ok { ret (archive, holder_error) }
    let st = &holder[0usize]
    let blank: State = zero
    *st = blank
    st.a = a
    st.data = data
    st.limits = limits
    st.name_budget = limits.name_bytes
    archive.state = mem.cast[*void](st)
    let (table, table_error) = mem.alloc[Entry](a, 16usize)
    if table_error != ok { ret (archive, table_error) }
    st.entries = table
    var at = 8usize
    var seen_end = false
    while at < data.len && !seen_end {
        if at + 4usize > data.len { ret (archive, Invalid) }
        let want_crc = u32(data[at]) | (u32(data[at + 1usize]) << 8u32) | (u32(data[at + 2usize]) << 16u32) | (u32(data[at + 3usize]) << 24u32)
        var c = Cur { data: data, at: at + 4usize, bad: false }
        let size = rd_vint(&c)
        if c.bad || size > u64(data.len - c.at) { ret (archive, Invalid) }
        let head_start = at + 4usize
        let head_end = c.at + usize(size)
        if hash.crc32(data[head_start..head_end]) != want_crc { ret (archive, Checksum) }
        let kind = rd_vint(&c)
        let flags = rd_vint(&c)
        if c.bad { ret (archive, Invalid) }
        var extra = 0u64
        var data_size = 0u64
        if (flags & 1u64) != 0u64 { extra = rd_vint(&c) }
        if (flags & 2u64) != 0u64 { data_size = rd_vint(&c) }
        if c.bad || c.at > head_end { ret (archive, Invalid) }
        let after = head_end
        if data_size > u64(data.len - after) { ret (archive, Invalid) }
        if kind == 4u64 { ret (archive, Unsupported) }
        if kind == 5u64 { seen_end = true }
        if kind == 1u64 {
            let archive_flags = rd_vint(&c)
            if c.bad { ret (archive, Invalid) }
            if (archive_flags & 1u64) != 0u64 { ret (archive, Unsupported) }
        }
        if kind == 2u64 {
            if st.count >= limits.entries { ret (archive, TooLarge) }
            let file_flags = rd_vint(&c)
            let unpacked = rd_vint(&c)
            let attributes = rd_vint(&c)
            var crc = 0u32
            var has_crc = false
            if (file_flags & 2u64) != 0u64 { let mtime = rd_u32(&c) }
            if (file_flags & 4u64) != 0u64 {
                crc = rd_u32(&c)
                has_crc = true
            }
            let info = rd_vint(&c)
            let host = rd_vint(&c)
            let name_length = rd_vint(&c)
            if c.bad || name_length > u64(head_end - c.at) { ret (archive, Invalid) }
            if (file_flags & 8u64) != 0u64 { ret (archive, Unsupported) }
            if (info & 63u64) != 0u64 { ret (archive, Unsupported) }
            if usize(name_length) > st.name_budget { ret (archive, TooLarge) }
            st.name_budget = st.name_budget - usize(name_length)
            let name = data[c.at..c.at + usize(name_length)]
            if unsafe_name(name) { ret (archive, Unsafe) }
            if st.count == st.entries.len {
                let (bigger, bigger_error) = mem.alloc[Entry](a, st.entries.len * 2usize)
                if bigger_error != ok { ret (archive, bigger_error) }
                var k = 0usize
                while k < st.count {
                    bigger[k] = st.entries[k]
                    k += 1usize
                }
                st.entries = bigger
            }
            var e: Entry = zero
            e.name = name
            e.size = unpacked
            e.crc32 = crc
            e.has_crc = has_crc
            e.directory = (file_flags & 1u64) != 0u64
            e.method = u8((info >> 7u32) & 7u64)
            e.solid = (info & 64u64) != 0u64
            e.dict_log = u32((info >> 10u32) & 15u64)
            e.data_offset = after
            e.packed = usize(data_size)
            st.entries[st.count] = e
            st.count += 1usize
        }
        at = after + usize(data_size)
    }
    ret (archive, ok)
}

fn entries(archive: *const Archive) -> []const Entry {
    let st = mem.cast[*State](archive.state)
    ret st.entries[..st.count]
}

// ---- bit reader and Huffman codes -------------------------------------------------------

// `n` (at most 16) bits, most significant first; past the end reads zeros and marks the reader bad.
fn take(b: *Bits, n: u32) -> u32 {
    var value = 0u32
    var k = 0u32
    while k < n {
        let byte_index = b.pos >> 3u32
        if byte_index >= b.data.len || b.pos >= b.end {
            b.bad = true
            value = value << 1u32
        } else {
            let bit = (b.data[byte_index] >> u32(7u32 - u32(b.pos & 7usize))) & 1u8
            value = (value << 1u32) | u32(bit)
        }
        b.pos += 1usize
        k += 1u32
    }
    ret value
}

fn huff_build(h: *Huff, lengths: []const u8) -> err {
    var i = 0usize
    while i < 16usize {
        h.count[i] = 0u16
        i += 1usize
    }
    i = 0usize
    while i < lengths.len {
        h.count[usize(lengths[i])] += 1u16
        i += 1usize
    }
    var left = 1i32
    var len = 1usize
    while len < 16usize {
        left = left * 2i32 - i32(h.count[len])
        if left < 0i32 { ret Invalid }
        len += 1usize
    }
    var offsets: [16]u16 = zero
    len = 1usize
    while len < 15usize {
        offsets[len + 1usize] = offsets[len] + h.count[len]
        len += 1usize
    }
    i = 0usize
    while i < lengths.len {
        if lengths[i] != 0u8 {
            h.symbol[usize(offsets[usize(lengths[i])])] = u16(i)
            offsets[usize(lengths[i])] += 1u16
        }
        i += 1usize
    }
    ret ok
}

// One symbol, or 65535 when no code matches.
fn huff_decode(h: *Huff, b: *Bits) -> u32 {
    var code = 0i32
    var first = 0i32
    var index = 0i32
    var len = 1usize
    while len < 16usize {
        code = code | i32(take(b, 1u32))
        let count = i32(h.count[len])
        if code - count < first { ret u32(h.symbol[usize(index + (code - first))]) }
        index += count
        first += count
        first = first << 1u32
        code = code << 1u32
        len += 1usize
    }
    b.bad = true
    ret 65535u32
}

// The code-length tables of a block: 20 four-bit lengths, then 430 lengths coded with them.
fn read_tables(b: *Bits, main: *Huff, dist: *Huff, low: *Huff, lens: *Huff) -> err {
    var bl: [20]u8 = zero
    var i = 0usize
    while i < BC {
        let v = take(b, 4u32)
        if v == 15u32 {
            let zeros = take(b, 4u32)
            if zeros == 0u32 {
                bl[i] = 15u8
                i += 1usize
            } else {
                var n = usize(zeros) + 2usize
                while n > 0usize && i < BC {
                    bl[i] = 0u8
                    i += 1usize
                    n -= 1usize
                }
            }
        } else {
            bl[i] = u8(v)
            i += 1usize
        }
        if b.bad { ret Invalid }
    }
    var bd: Huff = zero
    let bd_error = huff_build(&bd, bl[0..])
    if bd_error != ok { ret bd_error }
    var table: [430]u8 = zero
    i = 0usize
    while i < 430usize {
        let sym = huff_decode(&bd, b)
        if b.bad { ret Invalid }
        if sym < 16u32 {
            table[i] = u8(sym)
            i += 1usize
        } else if sym < 18u32 {
            var n = 0usize
            if sym == 16u32 { n = usize(take(b, 3u32)) + 3usize } else { n = usize(take(b, 7u32)) + 11usize }
            if i == 0usize { ret Invalid }
            while n > 0usize && i < 430usize {
                table[i] = table[i - 1usize]
                i += 1usize
                n -= 1usize
            }
        } else {
            var n = 0usize
            if sym == 18u32 { n = usize(take(b, 3u32)) + 3usize } else { n = usize(take(b, 7u32)) + 11usize }
            while n > 0usize && i < 430usize {
                table[i] = 0u8
                i += 1usize
                n -= 1usize
            }
        }
        if b.bad { ret Invalid }
    }
    let m = huff_build(main, table[..NC])
    if m != ok { ret m }
    let d = huff_build(dist, table[NC..NC + DC])
    if d != ok { ret d }
    let l = huff_build(low, table[NC + DC..NC + DC + LDC])
    if l != ok { ret l }
    ret huff_build(lens, table[NC + DC + LDC..430usize])
}

fn code_length(b: *Bits, slot: u32) -> u32 {
    if slot < 8u32 { ret slot + 2u32 }
    let lbits = slot / 4u32 - 1u32
    let base = 2u32 + ((4u32 | (slot & 3u32)) << lbits)
    ret base + take(b, lbits)
}

// Decodes one file's stream `src` to `out[start .. start + size]`; `out[..start]` is the
// window already produced by earlier files of the chain.
fn unpack(src: []const u8, out: []u8, start: usize, size: usize, dict: u64) -> err {
    var b = Bits { data: src, pos: 0usize, end: src.len * 8usize, bad: false }
    var main: Huff = zero
    var dist: Huff = zero
    var low: Huff = zero
    var lens: Huff = zero
    var have_tables = false
    var cache: [4]usize = zero
    var last_len = 0usize
    var at = start
    let stop = start + size
    var last_block = false
    while !last_block {
        // a block header starts on a byte boundary
        b.end = src.len * 8usize
        b.pos = (b.pos + 7usize) & (0usize -% 8usize)
        let flags = take(&b, 8u32)
        let sum = take(&b, 8u32)
        if b.bad { ret Invalid }
        let size_bytes = usize((flags >> 3u32) & 3u32) + 1usize
        var block_size = 0usize
        var s = 0usize
        var check = 90u32 ^ flags
        while s < size_bytes {
            let v = take(&b, 8u32)
            check = check ^ v
            block_size = block_size | (usize(v) << u32(8usize * s))
            s += 1usize
        }
        if b.bad || (check & 255u32) != sum { ret Invalid }
        let data_start = b.pos >> 3u32
        if block_size == 0usize || block_size > src.len - data_start { ret Invalid }
        let block_end = (data_start + block_size - 1usize) * 8usize + usize(flags & 7u32) + 1usize
        last_block = (flags & 64u32) != 0u32
        b.end = block_end
        if (flags & 128u32) != 0u32 {
            let t = read_tables(&b, &main, &dist, &low, &lens)
            if t != ok { ret t }
            have_tables = true
        }
        if !have_tables { ret Invalid }
        while b.pos < block_end {
            let sym = huff_decode(&main, &b)
            if b.bad { ret Invalid }
            if sym < 256u32 {
                if at >= stop { ret Invalid }
                out[at] = u8(sym)
                at += 1usize
                continue
            }
            if sym == 256u32 { ret Unsupported }
            var length = 0usize
            var distance = 0usize
            if sym == 257u32 {
                if last_len == 0usize { ret Invalid }
                length = last_len
                distance = cache[0]
            } else if sym < 262u32 {
                let index = usize(sym - 258u32)
                distance = cache[index]
                var k = index
                while k > 0usize {
                    cache[k] = cache[k - 1usize]
                    k -= 1usize
                }
                cache[0] = distance
                let slot = huff_decode(&lens, &b)
                if b.bad { ret Invalid }
                length = usize(code_length(&b, slot))
                last_len = length
            } else {
                length = usize(code_length(&b, sym - 262u32))
                let ds = huff_decode(&dist, &b)
                if b.bad { ret Invalid }
                var d = 1u64
                if ds < 4u32 {
                    d += u64(ds)
                } else {
                    let dbits = ds / 2u32 - 1u32
                    if dbits > 30u32 { ret Invalid }
                    d += u64(2u32 | (ds & 1u32)) << dbits
                    if dbits >= 4u32 {
                        if dbits > 4u32 {
                            d += u64(take(&b, dbits - 4u32)) << 4u32
                        }
                        let lo = huff_decode(&low, &b)
                        if b.bad { ret Invalid }
                        d += u64(lo)
                    } else {
                        d += u64(take(&b, dbits))
                    }
                }
                if d > 256u64 { length += 1usize }
                if d > 8192u64 { length += 1usize }
                if d > 262144u64 { length += 1usize }
                if d > dict { ret Invalid }
                distance = usize(d)
                cache[3] = cache[2]
                cache[2] = cache[1]
                cache[1] = cache[0]
                cache[0] = distance
                last_len = length
            }
            if distance == 0usize || distance > at { ret Invalid }
            if length > stop - at { ret Invalid }
            var k = 0usize
            while k < length {
                out[at] = out[at - distance]
                at += 1usize
                k += 1usize
            }
        }
        if b.pos != block_end || b.bad { ret Invalid }
        b.pos = block_end
    }
    if at != stop { ret Invalid }
    ret ok
}

// ---- extraction -------------------------------------------------------------------------

fn compressed(e: Entry) -> bool { ret !e.directory && e.method != 0u8 }

fn decode_chain(st: *State, index: usize) -> err {
    // the chain's first file is the nearest compressed one at or before `index` that does
    // not continue its predecessor
    var first = index
    while first > 0usize && st.entries[first].solid {
        first -= 1usize
        while first > 0usize && !compressed(st.entries[first]) { first -= 1usize }
    }
    if !compressed(st.entries[first]) { ret Invalid }
    var last = first
    var k = first + 1usize
    while k < st.count {
        if compressed(st.entries[k]) {
            if !st.entries[k].solid { break }
            last = k
        }
        k += 1usize
    }
    if st.chain_has && st.chain_start == first { ret ok }
    var total = 0u64
    k = first
    while k <= last {
        if compressed(st.entries[k]) {
            if st.entries[k].size > u64(st.limits.file_bytes) { ret TooLarge }
            total += st.entries[k].size
            if total > u64(st.limits.chain_bytes) { ret TooLarge }
        }
        k += 1usize
    }
    let (buffer, buffer_error) = mem.alloc[u8](st.a, usize(total) + 1usize)
    if buffer_error != ok { ret buffer_error }
    let (offsets, offsets_error) = mem.alloc[u64](st.a, st.count + 1usize)
    if offsets_error != ok { ret offsets_error }
    var at = 0usize
    k = first
    while k <= last {
        if compressed(st.entries[k]) {
            let e = st.entries[k]
            offsets[k] = u64(at)
            let dict = u64(131072u64) << e.dict_log
            let failure = unpack(st.data[e.data_offset..e.data_offset + e.packed], buffer, at, usize(e.size), dict)
            if failure != ok { ret failure }
            at += usize(e.size)
        }
        k += 1usize
    }
    st.chain = buffer[..at]
    st.chain_offsets = offsets
    st.chain_start = first
    st.chain_end = last
    st.chain_has = true
    ret ok
}

// One file's bytes. A directory is `Invalid`.
fn extract(a: *mem.Arena, archive: *Archive, index: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let st = mem.cast[*State](archive.state)
    if index >= st.count { ret (nothing, Invalid) }
    let e = st.entries[index]
    if e.directory { ret (nothing, Invalid) }
    if e.size > u64(st.limits.file_bytes) { ret (nothing, TooLarge) }
    let size = usize(e.size)
    var piece: []const u8 = zero
    if e.method == 0u8 {
        if e.packed != size { ret (nothing, Invalid) }
        piece = st.data[e.data_offset..e.data_offset + e.packed]
    } else {
        let failure = decode_chain(st, index)
        if failure != ok { ret (nothing, failure) }
        if index < st.chain_start || index > st.chain_end { ret (nothing, Invalid) }
        let begin = usize(st.chain_offsets[index])
        piece = st.chain[begin..begin + size]
    }
    if e.has_crc && hash.crc32(piece) != e.crc32 { ret (nothing, Checksum) }
    if size == 0usize { ret (nothing, ok) }
    let (out, out_error) = mem.alloc[u8](a, size)
    if out_error != ok { ret (nothing, out_error) }
    mem.copy[u8](out, piece)
    ret (out, ok)
}
