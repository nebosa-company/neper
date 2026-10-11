// 7z archive reader (L120): decode only, over an archive held in memory. `open` verifies the
// signature header's CRCs, reads the (possibly LZMA-encoded) header and lists the entries;
// `extract` decodes one file by running its folder's coder chain -- Copy, LZMA, LZMA2,
// Deflate, BZip2, Delta and the x86 BCJ filter, each coder one input and one output -- and
// checks the CRC-32 of the file (and of the whole folder when the header records one). A
// solid folder is decoded once and cached, so entries of one block are extracted in a
// sweep without decoding it again.
//
// Hostile archives are bounded before any allocation: every count is checked against the
// bytes left in the header and against `Limits`, a declared unpacked size above
// `folder_bytes` is `TooLarge`, a header above `header_bytes` is refused, names with an
// absolute path, a drive, a NUL or a `..` segment are `Unsafe`, and a coder whose output
// is not exactly the size the header declared is `Invalid`. Encrypted folders (AES),
// PPMd, BCJ2, other branch filters, multi-volume archives and external property streams
// are `Unsupported`. Nothing is freed: the folder cache and the header live in the
// caller's arena, so a caller extracting many solid blocks resets the arena between them.

use e.algo.deflate as deflate
use e.algo.hash as hash
use e.fmt.bzip2 as bzip2
use e.fmt.lzma as lzma
use e.io
use e.mem

type Limits = struct { entries: usize, name_bytes: usize, header_bytes: usize, folder_bytes: usize }
type Entry = struct { name: str, size: u64, crc32: u32, has_crc: bool, directory: bool, has_stream: bool, folder: usize, offset: u64 }
type Coder = struct { id: u64, props: [8]u8, props_len: usize }
type Folder = struct { coders: [4]Coder, ncoders: usize, bind_in: [3]usize, bind_out: [3]usize, nbind: usize, main_out: usize, sizes: [4]u64, crc: u32, has_crc: bool, nsub: usize, first_sub: usize }
type Cur = struct { data: []const u8, at: usize, bad: bool }
type State = struct { a: *mem.Arena, data: []const u8, limits: Limits, folders: []Folder, pack_pos: []u64, pack_size: []u64, sub_size: []u64, sub_crc: []u32, sub_has: []bool, entries: []Entry, cache_folder: usize, cache: []u8, cached: bool }
type Archive = struct { state: *void }

error Invalid
error Unsupported
error Checksum
error TooLarge
error Unsafe

fn default_limits() -> Limits {
    ret Limits { entries: 100000usize, name_bytes: 4194304usize, header_bytes: 16777216usize, folder_bytes: 268435456usize }
}

// ---- cursor ----------------------------------------------------------------------------

fn rd_byte(c: *Cur) -> u8 {
    if c.at >= c.data.len {
        c.bad = true
        ret 0u8
    }
    let b = c.data[c.at]
    c.at += 1usize
    ret b
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

// The 7z NUMBER: the leading one bits of the first byte count the extra little-endian bytes.
fn rd_number(c: *Cur) -> u64 {
    let first = rd_byte(c)
    var mask = 128u8
    var value = 0u64
    var i = 0u32
    while i < 8u32 {
        if (first & mask) == 0u8 {
            let high = u64(first & (mask - 1u8))
            ret value + (high << (8u32 * i))
        }
        let next = rd_byte(c)
        value = value | (u64(next) << (8u32 * i))
        mask = mask >> 1u32
        i += 1u32
    }
    ret value
}

fn left(c: *Cur) -> usize { ret c.data.len - c.at }

// A count that must fit what is left of the header (each item takes at least a byte) and
// the caller's limit.
fn rd_count(c: *Cur, limit: usize) -> usize {
    let n = rd_number(c)
    if n > u64(limit) || n > u64(left(c)) {
        c.bad = true
        ret 0usize
    }
    ret usize(n)
}

fn rd_bits(c: *Cur, n: usize, out: []bool) {
    var i = 0usize
    var b = 0u8
    while i < n {
        if i % 8usize == 0usize { b = rd_byte(c) }
        out[i] = (b & (128u8 >> u32(i % 8usize))) != 0u8
        i += 1usize
    }
}

// An optional-defined vector of CRCs: an "all defined" byte, else a bit vector.
fn rd_digests(a: *mem.Arena, c: *Cur, n: usize, has: []bool, crc: []u32) -> err {
    let all = rd_byte(c)
    if all != 0u8 {
        var i = 0usize
        while i < n {
            has[i] = true
            i += 1usize
        }
    } else {
        rd_bits(c, n, has)
    }
    var j = 0usize
    while j < n {
        if has[j] { crc[j] = rd_u32(c) }
        j += 1usize
    }
    if c.bad { ret Invalid }
    ret ok
}

// ---- header ----------------------------------------------------------------------------

fn parse_pack_info(c: *Cur, st: *State) -> err {
    let base = rd_number(c)
    let n = rd_count(c, st.limits.entries)
    if c.bad { ret Invalid }
    let (pos, pos_error) = mem.alloc[u64](st.a, n + 1usize)
    if pos_error != ok { ret pos_error }
    let (size, size_error) = mem.alloc[u64](st.a, n + 1usize)
    if size_error != ok { ret size_error }
    var i = 0usize
    while i < n {
        size[i] = 0u64
        pos[i] = 0u64
        i += 1usize
    }
    while true {
        let id = rd_number(c)
        if c.bad { ret Invalid }
        if id == 0u64 { break }
        if id == 9u64 {
            var at = 32u64 + base
            i = 0usize
            while i < n {
                let s = rd_number(c)
                if c.bad || s > u64(st.data.len) || at > u64(st.data.len) { ret Invalid }
                pos[i] = at
                size[i] = s
                at += s
                i += 1usize
            }
        } else if id == 10u64 {
            let ignored_has = [1]bool{ false }
            var has: [1]bool = zero
            let (hv, hv_error) = mem.alloc[bool](st.a, n + 1usize)
            if hv_error != ok { ret hv_error }
            let (cv, cv_error) = mem.alloc[u32](st.a, n + 1usize)
            if cv_error != ok { ret cv_error }
            let digest_error = rd_digests(st.a, c, n, hv, cv)
            if digest_error != ok { ret digest_error }
        } else {
            ret Invalid
        }
    }
    st.pack_pos = pos[..n]
    st.pack_size = size[..n]
    ret ok
}

fn parse_folder(c: *Cur, f: *Folder) -> err {
    let n = rd_number(c)
    if c.bad || n == 0u64 { ret Invalid }
    if n > 4u64 { ret Unsupported }
    f.ncoders = usize(n)
    var k = 0usize
    while k < f.ncoders {
        let flags = rd_byte(c)
        if c.bad { ret Invalid }
        let id_size = usize(flags & 15u8)
        if id_size > 8usize || (flags & 128u8) != 0u8 { ret Unsupported }
        var id = 0u64
        var i = 0usize
        while i < id_size {
            id = (id << 8u32) | u64(rd_byte(c))
            i += 1usize
        }
        f.coders[k].id = id
        if (flags & 16u8) != 0u8 {
            let nin = rd_number(c)
            let nout = rd_number(c)
            if c.bad { ret Invalid }
            if nin != 1u64 || nout != 1u64 { ret Unsupported }
        }
        f.coders[k].props_len = 0usize
        if (flags & 32u8) != 0u8 {
            let plen = rd_number(c)
            if c.bad || plen > u64(left(c)) { ret Invalid }
            if plen > 8u64 { ret Unsupported }
            f.coders[k].props_len = usize(plen)
            i = 0usize
            while i < f.coders[k].props_len {
                f.coders[k].props[i] = rd_byte(c)
                i += 1usize
            }
        }
        k += 1usize
    }
    f.nbind = f.ncoders - 1usize
    var in_used: [4]bool = zero
    var out_used: [4]bool = zero
    k = 0usize
    while k < f.nbind {
        let in_index = rd_number(c)
        let out_index = rd_number(c)
        if c.bad || in_index >= u64(f.ncoders) || out_index >= u64(f.ncoders) { ret Invalid }
        if in_used[usize(in_index)] || out_used[usize(out_index)] { ret Invalid }
        in_used[usize(in_index)] = true
        out_used[usize(out_index)] = true
        f.bind_in[k] = usize(in_index)
        f.bind_out[k] = usize(out_index)
        k += 1usize
    }
    // one packed stream: the single in stream no pair feeds
    var unbound = 0usize
    var count = 0usize
    k = 0usize
    while k < f.ncoders {
        if !in_used[k] {
            unbound = k
            count += 1usize
        }
        k += 1usize
    }
    if count != 1usize { ret Unsupported }
    k = 0usize
    var mains = 0usize
    while k < f.ncoders {
        if !out_used[k] {
            f.main_out = k
            mains += 1usize
        }
        k += 1usize
    }
    if mains != 1usize { ret Invalid }
    // the folder's packed stream index is its position: record the unbound coder in `first_sub`'s
    // sibling field by convention of `chain_input`
    f.first_sub = unbound
    ret ok
}

fn parse_unpack_info(c: *Cur, st: *State) -> err {
    let id = rd_number(c)
    if c.bad || id != 11u64 { ret Invalid }
    let n = rd_count(c, st.limits.entries)
    let external = rd_byte(c)
    if c.bad || external != 0u8 { ret Unsupported }
    let (folders, folders_error) = mem.alloc[Folder](st.a, n + 1usize)
    if folders_error != ok { ret folders_error }
    var i = 0usize
    while i < n {
        let blank: Folder = zero
        folders[i] = blank
        let folder_error = parse_folder(c, &folders[i])
        if folder_error != ok { ret folder_error }
        i += 1usize
    }
    let sizes_id = rd_number(c)
    if c.bad || sizes_id != 12u64 { ret Invalid }
    i = 0usize
    while i < n {
        var k = 0usize
        while k < folders[i].ncoders {
            folders[i].sizes[k] = rd_number(c)
            if c.bad { ret Invalid }
            if folders[i].sizes[k] > u64(st.limits.folder_bytes) { ret TooLarge }
            k += 1usize
        }
        folders[i].nsub = 1usize
        i += 1usize
    }
    while true {
        let next = rd_number(c)
        if c.bad { ret Invalid }
        if next == 0u64 { break }
        if next == 10u64 {
            let (hv, hv_error) = mem.alloc[bool](st.a, n + 1usize)
            if hv_error != ok { ret hv_error }
            let (cv, cv_error) = mem.alloc[u32](st.a, n + 1usize)
            if cv_error != ok { ret cv_error }
            i = 0usize
            while i < n {
                hv[i] = false
                i += 1usize
            }
            let digest_error = rd_digests(st.a, c, n, hv, cv)
            if digest_error != ok { ret digest_error }
            i = 0usize
            while i < n {
                folders[i].has_crc = hv[i]
                folders[i].crc = cv[i]
                i += 1usize
            }
        } else {
            ret Invalid
        }
    }
    st.folders = folders[..n]
    ret ok
}

fn folder_size(f: *Folder) -> u64 { ret f.sizes[f.main_out] }

// One substream per folder, sized and checked as the folder is.
fn default_substreams(st: *State) -> err {
    let n = st.folders.len
    let (sizes, sizes_error) = mem.alloc[u64](st.a, n + 1usize)
    if sizes_error != ok { ret sizes_error }
    let (crcs, crcs_error) = mem.alloc[u32](st.a, n + 1usize)
    if crcs_error != ok { ret crcs_error }
    let (has, has_error) = mem.alloc[bool](st.a, n + 1usize)
    if has_error != ok { ret has_error }
    var i = 0usize
    while i < n {
        sizes[i] = folder_size(&st.folders[i])
        crcs[i] = st.folders[i].crc
        has[i] = st.folders[i].has_crc
        st.folders[i].nsub = 1usize
        i += 1usize
    }
    st.sub_size = sizes[..n]
    st.sub_crc = crcs[..n]
    st.sub_has = has[..n]
    ret ok
}

fn parse_substreams(c: *Cur, st: *State) -> err {
    let n = st.folders.len
    var total = n
    var next = rd_number(c)
    if c.bad { ret Invalid }
    if next == 13u64 {
        total = 0usize
        var i = 0usize
        while i < n {
            let count = rd_number(c)
            if c.bad || count > u64(st.limits.entries) { ret Invalid }
            st.folders[i].nsub = usize(count)
            total += usize(count)
            if total > st.limits.entries { ret TooLarge }
            i += 1usize
        }
        next = rd_number(c)
        if c.bad { ret Invalid }
    }
    let (sizes, sizes_error) = mem.alloc[u64](st.a, total + 1usize)
    if sizes_error != ok { ret sizes_error }
    let (crcs, crcs_error) = mem.alloc[u32](st.a, total + 1usize)
    if crcs_error != ok { ret crcs_error }
    let (has, has_error) = mem.alloc[bool](st.a, total + 1usize)
    if has_error != ok { ret has_error }
    var at = 0usize
    var f = 0usize
    while f < n {
        st.folders[f].first_sub = at
        at += st.folders[f].nsub
        f += 1usize
    }
    // sizes: the last substream of a folder is what the others leave
    if next == 9u64 {
        f = 0usize
        while f < n {
            let nsub = st.folders[f].nsub
            if nsub > 0usize {
                var sum = 0u64
                var k = 0usize
                while k + 1usize < nsub {
                    let s = rd_number(c)
                    if c.bad { ret Invalid }
                    sizes[st.folders[f].first_sub + k] = s
                    sum += s
                    if sum < s { ret Invalid }
                    k += 1usize
                }
                if sum > folder_size(&st.folders[f]) { ret Invalid }
                sizes[st.folders[f].first_sub + nsub - 1usize] = folder_size(&st.folders[f]) - sum
            }
            f += 1usize
        }
        next = rd_number(c)
        if c.bad { ret Invalid }
    } else {
        f = 0usize
        while f < n {
            if st.folders[f].nsub > 1usize { ret Invalid }
            if st.folders[f].nsub == 1usize { sizes[st.folders[f].first_sub] = folder_size(&st.folders[f]) }
            f += 1usize
        }
    }
    // checks: a lone substream of a folder with a CRC inherits it; the rest are listed
    var unknown = 0usize
    f = 0usize
    while f < n {
        let inherit = st.folders[f].nsub == 1usize && st.folders[f].has_crc
        if inherit {
            has[st.folders[f].first_sub] = true
            crcs[st.folders[f].first_sub] = st.folders[f].crc
        } else {
            unknown += st.folders[f].nsub
        }
        f += 1usize
    }
    while next != 0u64 {
        if next == 10u64 {
            let (hv, hv_error) = mem.alloc[bool](st.a, unknown + 1usize)
            if hv_error != ok { ret hv_error }
            let (cv, cv_error) = mem.alloc[u32](st.a, unknown + 1usize)
            if cv_error != ok { ret cv_error }
            var j = 0usize
            while j < unknown {
                hv[j] = false
                j += 1usize
            }
            let digest_error = rd_digests(st.a, c, unknown, hv, cv)
            if digest_error != ok { ret digest_error }
            var taken = 0usize
            f = 0usize
            while f < n {
                let inherit = st.folders[f].nsub == 1usize && st.folders[f].has_crc
                if !inherit {
                    var k = 0usize
                    while k < st.folders[f].nsub {
                        has[st.folders[f].first_sub + k] = hv[taken]
                        crcs[st.folders[f].first_sub + k] = cv[taken]
                        taken += 1usize
                        k += 1usize
                    }
                }
                f += 1usize
            }
        } else {
            ret Invalid
        }
        next = rd_number(c)
        if c.bad { ret Invalid }
    }
    st.sub_size = sizes[..total]
    st.sub_crc = crcs[..total]
    st.sub_has = has[..total]
    ret ok
}

fn parse_streams_info(c: *Cur, st: *State) -> err {
    var have_unpack = false
    var have_sub = false
    while true {
        let id = rd_number(c)
        if c.bad { ret Invalid }
        if id == 0u64 { break }
        if id == 6u64 {
            let e = parse_pack_info(c, st)
            if e != ok { ret e }
        } else if id == 7u64 {
            let e = parse_unpack_info(c, st)
            if e != ok { ret e }
            have_unpack = true
            let d = default_substreams(st)
            if d != ok { ret d }
        } else if id == 8u64 {
            if !have_unpack { ret Invalid }
            let e = parse_substreams(c, st)
            if e != ok { ret e }
            have_sub = true
        } else {
            ret Invalid
        }
    }
    if have_unpack && st.folders.len > st.pack_pos.len { ret Invalid }
    ret ok
}

// ---- coders ----------------------------------------------------------------------------

fn bcj_x86(buf: []u8) {
    if buf.len < 5usize { ret }
    let allowed: [8]bool = [8]bool{ true, true, true, false, true, false, false, false }
    let bits: [8]u32 = [8]u32{ 0u32, 1u32, 2u32, 2u32, 3u32, 3u32, 3u32, 3u32 }
    var prev_mask = 0u32
    var prev_pos = 0usize -% 1usize
    var pos = 0usize
    let limit = buf.len - 4usize
    while true {
        while pos < limit && (buf[pos] & 254u8) != 232u8 { pos += 1usize }
        if pos >= limit { break }
        let gap = pos -% prev_pos
        if gap > 3usize {
            prev_mask = 0u32
        } else {
            prev_mask = (prev_mask << u32(gap - 1usize)) & 7u32
            if prev_mask != 0u32 {
                let b = buf[pos + 4usize - usize(bits[usize(prev_mask)])]
                if !allowed[usize(prev_mask)] || b == 0u8 || b == 255u8 {
                    prev_pos = pos
                    prev_mask = ((prev_mask << 1u32) & 7u32) | 1u32
                    pos += 1usize
                    continue
                }
            }
        }
        prev_pos = pos
        if buf[pos + 4usize] == 0u8 || buf[pos + 4usize] == 255u8 {
            var src = (u32(buf[pos + 4usize]) << 24u32) | (u32(buf[pos + 3usize]) << 16u32) | (u32(buf[pos + 2usize]) << 8u32) | u32(buf[pos + 1usize])
            var dest = 0u32
            while true {
                dest = src -% (u32(pos) +% 5u32)
                if prev_mask == 0u32 { break }
                let index = bits[usize(prev_mask)] * 8u32
                let b = u8((dest >> (24u32 - index)) & 255u32)
                if b != 0u8 && b != 255u8 { break }
                src = dest ^ ((1u32 << (32u32 - index)) - 1u32)
            }
            buf[pos + 4usize] = u8((0u32 -% ((dest >> 24u32) & 1u32)) & 255u32)
            buf[pos + 3usize] = u8((dest >> 16u32) & 255u32)
            buf[pos + 2usize] = u8((dest >> 8u32) & 255u32)
            buf[pos + 1usize] = u8(dest & 255u32)
            pos += 5usize
        } else {
            prev_mask = ((prev_mask << 1u32) & 7u32) | 1u32
            pos += 1usize
        }
    }
}

fn run_deflate(a: *mem.Arena, input: []const u8, out_size: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let (storage_size, storage_error) = deflate.decoder_storage(32768usize)
    if storage_error != ok { ret (nothing, storage_error) }
    let (storage, alloc_error) = mem.alloc[u8](a, storage_size)
    if alloc_error != ok { ret (nothing, alloc_error) }
    let (d, d_error) = deflate.decoder(storage, 32768usize)
    if d_error != ok { ret (nothing, d_error) }
    var decoder = d
    let (out, out_error) = mem.alloc[u8](a, out_size + 1usize)
    if out_error != ok { ret (nothing, out_error) }
    let (consumed, written, status, decode_error) = deflate.decode(&decoder, input, out[..out_size + 1usize], true)
    if decode_error != ok { ret (nothing, Invalid) }
    if written != out_size { ret (nothing, Invalid) }
    ret (out[..out_size], ok)
}

fn run_bzip2(a: *mem.Arena, input: []const u8, out_size: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let (storage_size, size_error) = bzip2.storage_required(900000usize)
    if size_error != ok { ret (nothing, size_error) }
    let (storage, alloc_error) = mem.alloc[u8](a, storage_size)
    if alloc_error != ok { ret (nothing, alloc_error) }
    var scripted = io.SliceReader { data: input, off: 0usize }
    let (r, r_error) = bzip2.reader(storage, io.slice_reader(&scripted), u64(out_size))
    if r_error != ok { ret (nothing, Invalid) }
    var reader = r
    let (out, out_error) = mem.alloc[u8](a, out_size + 1usize)
    if out_error != ok { ret (nothing, out_error) }
    var got = 0usize
    while got <= out_size {
        let (n, read_error) = bzip2.read(&reader, out[got..out_size + 1usize])
        if read_error == io.End { break }
        if read_error != ok { ret (nothing, Invalid) }
        if n == 0usize { break }
        got += n
    }
    if got != out_size { ret (nothing, Invalid) }
    ret (out[..out_size], ok)
}

fn run_coder(a: *mem.Arena, coder: Coder, input: []const u8, out_size: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let id = coder.id
    if id == 0u64 {
        if input.len != out_size { ret (nothing, Invalid) }
        let (out, out_error) = mem.alloc[u8](a, out_size + 1usize)
        if out_error != ok { ret (nothing, out_error) }
        mem.copy[u8](out[..out_size], input)
        ret (out[..out_size], ok)
    }
    if id == 196865u64 {
        // 03 01 01: LZMA, five property bytes
        if coder.props_len != 5usize { ret (nothing, Invalid) }
        var p: lzma.Props = zero
        let props_error = lzma.set_props_byte(&p, coder.props[0])
        if props_error != ok { ret (nothing, Invalid) }
        p.dict_size = u32(coder.props[1]) | (u32(coder.props[2]) << 8u32) | (u32(coder.props[3]) << 16u32) | (u32(coder.props[4]) << 24u32)
        p.unpacked = u64(out_size)
        p.has_size = true
        let (probs, probs_error) = mem.alloc[u16](a, lzma.probs_required(p.lc, p.lp))
        if probs_error != ok { ret (nothing, probs_error) }
        let (out, out_error) = mem.alloc[u8](a, out_size + 1usize)
        if out_error != ok { ret (nothing, out_error) }
        let (n, decode_error) = lzma.decode_raw(p, input, out[..out_size], probs)
        if decode_error != ok || n != out_size { ret (nothing, Invalid) }
        ret (out[..out_size], ok)
    }
    if id == 33u64 {
        // 21: LZMA2, one property byte for the dictionary
        if coder.props_len != 1usize { ret (nothing, Invalid) }
        let (dict, dict_error) = lzma.lzma2_dict_size(coder.props[0])
        if dict_error != ok { ret (nothing, Invalid) }
        let (probs, probs_error) = mem.alloc[u16](a, lzma.probs_required(4u32, 0u32))
        if probs_error != ok { ret (nothing, probs_error) }
        let (out, out_error) = mem.alloc[u8](a, out_size + 1usize)
        if out_error != ok { ret (nothing, out_error) }
        let (at, written, decode_error) = lzma.lzma2(input, 0usize, out[..out_size], 0usize, probs, dict)
        if decode_error != ok || written != out_size { ret (nothing, Invalid) }
        ret (out[..out_size], ok)
    }
    if id == 3u64 {
        // 03: Delta, property = distance - 1
        if coder.props_len != 1usize || input.len != out_size { ret (nothing, Invalid) }
        let distance = usize(coder.props[0]) + 1usize
        let (out, out_error) = mem.alloc[u8](a, out_size + 1usize)
        if out_error != ok { ret (nothing, out_error) }
        var i = 0usize
        while i < out_size {
            if i >= distance {
                out[i] = input[i] +% out[i - distance]
            } else {
                out[i] = input[i]
            }
            i += 1usize
        }
        ret (out[..out_size], ok)
    }
    if id == 50528515u64 || id == 4u64 {
        // 03 03 01 03 (and the newer 04): the x86 branch converter
        if input.len != out_size { ret (nothing, Invalid) }
        let (out, out_error) = mem.alloc[u8](a, out_size + 1usize)
        if out_error != ok { ret (nothing, out_error) }
        mem.copy[u8](out[..out_size], input)
        bcj_x86(out[..out_size])
        ret (out[..out_size], ok)
    }
    if id == 262408u64 {
        let (out, failure) = run_deflate(a, input, out_size)
        ret (out, failure)
    }
    if id == 262658u64 {
        let (out, failure) = run_bzip2(a, input, out_size)
        ret (out, failure)
    }
    ret (nothing, Unsupported)
}

// The decoded output of coder `out_index`, recursively through the folder's bind pairs.
fn decode_out(st: *State, f: *Folder, folder_index: usize, out_index: usize, depth: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    if depth > 4usize { ret (nothing, Invalid) }
    let size = f.sizes[out_index]
    if size > u64(st.limits.folder_bytes) { ret (nothing, TooLarge) }
    var input: []const u8 = zero
    var fed = false
    var k = 0usize
    while k < f.nbind {
        if f.bind_in[k] == out_index {
            let (inner, inner_error) = decode_out(st, f, folder_index, f.bind_out[k], depth + 1usize)
            if inner_error != ok { ret (nothing, inner_error) }
            input = inner
            fed = true
        }
        k += 1usize
    }
    if !fed {
        // the packed stream of this folder (one per folder: the folder's own index)
        if folder_index >= st.pack_pos.len { ret (nothing, Invalid) }
        let start = st.pack_pos[folder_index]
        let length = st.pack_size[folder_index]
        if start > u64(st.data.len) || length > u64(st.data.len) - start { ret (nothing, Invalid) }
        input = st.data[usize(start)..usize(start + length)]
    }
    let (out, failure) = run_coder(st.a, f.coders[out_index], input, usize(size))
    ret (out, failure)
}

fn decode_folder(st: *State, index: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    if st.cached && st.cache_folder == index { ret (st.cache, ok) }
    let (out, failure) = decode_out(st, &st.folders[index], index, st.folders[index].main_out, 0usize)
    if failure != ok { ret (nothing, failure) }
    if st.folders[index].has_crc && hash.crc32(out) != st.folders[index].crc { ret (nothing, Checksum) }
    st.cache = out
    st.cache_folder = index
    st.cached = true
    ret (out, ok)
}

// ---- names and entries -----------------------------------------------------------------

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

// UTF-16LE up to a NUL unit, to UTF-8 in the arena; the cursor ends after the terminator.
fn rd_name(a: *mem.Arena, c: *Cur, end: usize, budget: *usize) -> (str, err) {
    let begin = c.at
    var units = 0usize
    while true {
        if c.at + 2usize > end { ret ("", Invalid) }
        let u = u32(c.data[c.at]) | (u32(c.data[c.at + 1usize]) << 8u32)
        c.at += 2usize
        if u == 0u32 { break }
        units += 1usize
    }
    if units * 3usize > *budget { ret ("", TooLarge) }
    *budget = *budget - units * 3usize
    let (out, out_error) = mem.alloc[u8](a, units * 3usize + 1usize)
    if out_error != ok { ret ("", out_error) }
    var n = 0usize
    var i = 0usize
    while i < units {
        var u = u32(c.data[begin + i * 2usize]) | (u32(c.data[begin + i * 2usize + 1usize]) << 8u32)
        i += 1usize
        if u >= 55296u32 && u < 56320u32 {
            if i >= units { ret ("", Invalid) }
            let low = u32(c.data[begin + i * 2usize]) | (u32(c.data[begin + i * 2usize + 1usize]) << 8u32)
            if low < 56320u32 || low >= 57344u32 { ret ("", Invalid) }
            i += 1usize
            u = 65536u32 + ((u - 55296u32) << 10u32) + (low - 56320u32)
        } else if u >= 56320u32 && u < 57344u32 {
            ret ("", Invalid)
        }
        if u < 128u32 {
            out[n] = u8(u)
            n += 1usize
        } else if u < 2048u32 {
            out[n] = u8(192u32 | (u >> 6u32))
            out[n + 1usize] = u8(128u32 | (u & 63u32))
            n += 2usize
        } else if u < 65536u32 {
            out[n] = u8(224u32 | (u >> 12u32))
            out[n + 1usize] = u8(128u32 | ((u >> 6u32) & 63u32))
            out[n + 2usize] = u8(128u32 | (u & 63u32))
            n += 3usize
        } else {
            out[n] = u8(240u32 | (u >> 18u32))
            out[n + 1usize] = u8(128u32 | ((u >> 12u32) & 63u32))
            out[n + 2usize] = u8(128u32 | ((u >> 6u32) & 63u32))
            out[n + 3usize] = u8(128u32 | (u & 63u32))
            n += 4usize
        }
    }
    ret (out[..n], ok)
}

fn parse_files_info(c: *Cur, st: *State) -> err {
    let n = rd_count(c, st.limits.entries)
    if c.bad { ret Invalid }
    let (listed, listed_error) = mem.alloc[Entry](st.a, n + 1usize)
    if listed_error != ok { ret listed_error }
    let (empty, empty_error) = mem.alloc[bool](st.a, n + 1usize)
    if empty_error != ok { ret empty_error }
    let (empty_file, empty_file_error) = mem.alloc[bool](st.a, n + 1usize)
    if empty_file_error != ok { ret empty_file_error }
    var i = 0usize
    while i < n {
        empty[i] = false
        empty_file[i] = false
        let blank: Entry = zero
        listed[i] = blank
        i += 1usize
    }
    var budget = st.limits.name_bytes
    var empties = 0usize
    var named = false
    while true {
        let kind = rd_number(c)
        if c.bad { ret Invalid }
        if kind == 0u64 { break }
        let size = rd_number(c)
        if c.bad || size > u64(left(c)) { ret Invalid }
        let end = c.at + usize(size)
        if kind == 14u64 {
            rd_bits(c, n, empty)
            i = 0usize
            while i < n {
                if empty[i] { empties += 1usize }
                i += 1usize
            }
        } else if kind == 15u64 {
            var which = 0usize
            var k = 0usize
            var b = 0u8
            while which < empties {
                if which % 8usize == 0usize { b = rd_byte(c) }
                let bit = (b & (128u8 >> u32(which % 8usize))) != 0u8
                // the bit belongs to the which-th empty-stream file
                var seen = 0usize
                k = 0usize
                while k < n {
                    if empty[k] {
                        if seen == which { empty_file[k] = bit }
                        seen += 1usize
                    }
                    k += 1usize
                }
                which += 1usize
            }
        } else if kind == 17u64 {
            let external = rd_byte(c)
            if c.bad || external != 0u8 { ret Unsupported }
            i = 0usize
            while i < n {
                let (name, name_error) = rd_name(st.a, c, end, &budget)
                if name_error != ok { ret name_error }
                if unsafe_name(name) { ret Unsafe }
                listed[i].name = name
                i += 1usize
            }
            named = true
        }
        if c.bad { ret Invalid }
        c.at = end
    }
    if !named { ret Invalid }
    // streams are handed to the files that have one, in order, folder by folder
    var folder = 0usize
    var within = 0usize
    var offset = 0u64
    var stream = 0usize
    i = 0usize
    while i < n {
        if !empty[i] {
            while folder < st.folders.len && within >= st.folders[folder].nsub {
                folder += 1usize
                within = 0usize
                offset = 0u64
            }
            if folder >= st.folders.len { ret Invalid }
            let index = st.folders[folder].first_sub + within
            listed[i].has_stream = true
            listed[i].folder = folder
            listed[i].offset = offset
            listed[i].size = st.sub_size[index]
            listed[i].crc32 = st.sub_crc[index]
            listed[i].has_crc = st.sub_has[index]
            offset += st.sub_size[index]
            within += 1usize
            stream += 1usize
        } else {
            listed[i].directory = !empty_file[i]
        }
        i += 1usize
    }
    if stream != st.sub_size.len { ret Invalid }
    st.entries = listed[..n]
    ret ok
}

fn parse_header(c: *Cur, st: *State) -> err {
    while true {
        let id = rd_number(c)
        if c.bad { ret Invalid }
        if id == 0u64 { break }
        if id == 2u64 {
            while true {
                let kind = rd_number(c)
                if c.bad { ret Invalid }
                if kind == 0u64 { break }
                let size = rd_number(c)
                if c.bad || size > u64(left(c)) { ret Invalid }
                c.at += usize(size)
            }
        } else if id == 3u64 {
            ret Unsupported
        } else if id == 4u64 {
            let e = parse_streams_info(c, st)
            if e != ok { ret e }
        } else if id == 5u64 {
            let e = parse_files_info(c, st)
            if e != ok { ret e }
        } else {
            ret Invalid
        }
    }
    ret ok
}

fn le32_at(data: []const u8, at: usize) -> u32 {
    ret u32(data[at]) | (u32(data[at + 1usize]) << 8u32) | (u32(data[at + 2usize]) << 16u32) | (u32(data[at + 3usize]) << 24u32)
}

fn le64_at(data: []const u8, at: usize) -> u64 {
    ret u64(le32_at(data, at)) | (u64(le32_at(data, at + 4usize)) << 32u32)
}

fn open(a: *mem.Arena, data: []const u8, limits: Limits) -> (Archive, err) {
    var archive: Archive = zero
    if data.len < 32usize { ret (archive, Invalid) }
    let sig = [6]u8{ 55u8, 122u8, 188u8, 175u8, 39u8, 28u8 }
    var i = 0usize
    while i < 6usize {
        if data[i] != sig[i] { ret (archive, Invalid) }
        i += 1usize
    }
    if data[6] != 0u8 { ret (archive, Unsupported) }
    if hash.crc32(data[12..32]) != le32_at(data, 8usize) { ret (archive, Checksum) }
    let next_offset = le64_at(data, 12usize)
    let next_size = le64_at(data, 20usize)
    let next_crc = le32_at(data, 28usize)
    let (holder, holder_error) = mem.alloc[State](a, 1usize)
    if holder_error != ok { ret (archive, holder_error) }
    let st = &holder[0usize]
    let blank: State = zero
    *st = blank
    st.a = a
    st.data = data
    st.limits = limits
    archive.state = mem.cast[*void](st)
    if next_size == 0u64 { ret (archive, ok) }
    if next_size > u64(limits.header_bytes) { ret (archive, TooLarge) }
    if next_offset > u64(data.len) - 32u64 || next_size > u64(data.len) - 32u64 - next_offset { ret (archive, Invalid) }
    let start = 32usize + usize(next_offset)
    var header = data[start..start + usize(next_size)]
    if hash.crc32(header) != next_crc { ret (archive, Checksum) }
    var rounds = 0usize
    while true {
        var c = Cur { data: header, at: 0usize, bad: false }
        let id = rd_number(&c)
        if c.bad { ret (archive, Invalid) }
        if id == 1u64 {
            let e = parse_header(&c, st)
            if e != ok { ret (archive, e) }
            break
        }
        if id != 23u64 || rounds >= 4usize { ret (archive, Invalid) }
        // an encoded header: streams info for one folder whose output is the real header
        var encoded: State = zero
        encoded.a = st.a
        encoded.data = data
        encoded.limits = limits
        let e = parse_streams_info(&c, &encoded)
        if e != ok { ret (archive, e) }
        if encoded.folders.len == 0usize { ret (archive, Invalid) }
        let (plain, plain_error) = decode_folder(&encoded, 0usize)
        if plain_error != ok { ret (archive, plain_error) }
        header = plain
        rounds += 1usize
    }
    ret (archive, ok)
}

fn entries(archive: *const Archive) -> []const Entry {
    let st = mem.cast[*State](archive.state)
    ret st.entries[0..]
}

// One file's bytes. A directory is `Invalid`; an empty file is an empty slice.
fn extract(a: *mem.Arena, archive: *Archive, index: usize) -> ([]u8, err) {
    var nothing: []u8 = zero
    let st = mem.cast[*State](archive.state)
    if index >= st.entries.len { ret (nothing, Invalid) }
    let entry = st.entries[index]
    if entry.directory { ret (nothing, Invalid) }
    if !entry.has_stream { ret (nothing, ok) }
    let (whole, failure) = decode_folder(st, entry.folder)
    if failure != ok { ret (nothing, failure) }
    if entry.offset > u64(whole.len) || entry.size > u64(whole.len) - entry.offset { ret (nothing, Invalid) }
    let piece = whole[usize(entry.offset)..usize(entry.offset + entry.size)]
    if entry.has_crc && hash.crc32(piece) != entry.crc32 { ret (nothing, Checksum) }
    if piece.len == 0usize { ret (nothing, ok) }
    let (out, out_error) = mem.alloc[u8](a, piece.len)
    if out_error != ok { ret (nothing, out_error) }
    mem.copy[u8](out, piece)
    ret (out, ok)
}
