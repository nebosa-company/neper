// LZMA decompression over caller storage, after the LZMA SDK's reference decoder
// (LzmaSpec.cpp): the 13-byte "alone" header (properties byte lc/lp/pb, 4-byte LE
// dictionary size, 8-byte LE uncompressed size or all-ones for "end marker"), the
// range decoder (5 init bytes, 11-bit probabilities moving by shift 5, direct
// bits), the probability model (is_match/is_rep/is_rep_g0/g1/g2/is_rep0_long over
// 12 states x 16 position states, two length coders with low/mid/high trees, pos
// slot trees per length state, the special-position and align reverse trees, and
// 0x300 literal probabilities per literal state), the state machine with its four
// rep distances, and the output buffer `dst` as the dictionary. The probabilities
// live in the caller's `probs: []u16`, `probs_required(lc, lp)` entries.
//
// Also the .xz container: stream header and footer, block headers with the single
// LZMA2 filter, LZMA2 chunk framing (uncompressed chunks, LZMA chunks with the
// state/props/dictionary reset bits), block padding, the CRC32, CRC64 or SHA-256
// check and the index (record count, total uncompressed size and its CRC32).
// Compression is not written.
//
// ponytail: the .xz reader takes one filter (LZMA2) per block and does not verify
// the optional compressed/uncompressed sizes in a block header nor each index
// record against its block, only the count, the total and the index CRC; add BCJ
// or delta filters and per-record checks when a producer other than xz/liblzma
// defaults shows up.
use e.algo.hash as hash
use e.crypto.hash as chash

error Invalid
error Malformed
error TooSmall
error Checksum
error Unsupported

type Props = struct { lc: u32, lp: u32, pb: u32, dict_size: u32, unpacked: u64, has_size: bool }

// Decoder: the range coder over `src[at..end]`, the state machine and the output
// window `dst[start..pos]` (a dictionary reset moves `start`).
type Lz = struct { src: []const u8, at: usize, end: usize, range: u32, code: u32, bad: bool, state: u32, rep0: u32, rep1: u32, rep2: u32, rep3: u32, pos: usize, start: usize, lc: u32, lp: u32, pb: u32, dict_size: u32 }

// Probability layout (LzmaDec's 1846 base entries, then the literal coders).
const IS_MATCH: usize = 0usize
const IS_REP: usize = 192usize
const IS_REP_G0: usize = 204usize
const IS_REP_G1: usize = 216usize
const IS_REP_G2: usize = 228usize
const IS_REP0_LONG: usize = 240usize
const POS_SLOT: usize = 432usize
const SPEC_POS: usize = 688usize
const ALIGN: usize = 802usize
const LEN: usize = 818usize
const REP_LEN: usize = 1332usize
const LITERAL: usize = 1846usize
const MARKER: u32 = 4294967295u32

// Entries the `probs` slice must hold for a stream with these lc and lp.
fn probs_required(lc: u32, lp: u32) -> usize { ret LITERAL + (768usize << (lc + lp)) }

fn le32(src: []const u8, at: usize) -> u32 {
    ret u32(src[at]) | (u32(src[at + 1usize]) << 8u32) | (u32(src[at + 2usize]) << 16u32) | (u32(src[at + 3usize]) << 24u32)
}

fn le64(src: []const u8, at: usize) -> u64 {
    ret u64(le32(src, at)) | (u64(le32(src, at + 4usize)) << 32u32)
}

fn set_props_byte(p: *Props, b: u8) -> err {
    var v = u32(b)
    if v >= 225u32 { ret Invalid }
    p.lc = v % 9u32
    v = v / 9u32
    p.lp = v % 5u32
    p.pb = v / 5u32
    if p.lc + p.lp > 4u32 { ret Invalid }
    ret ok
}

// The 13-byte alone header. `has_size` is false when the size field is all ones.
fn header(src: []const u8) -> (Props, err) {
    var p: Props = zero
    if src.len < 13usize { ret (p, Malformed) }
    let e = set_props_byte(&p, src[0])
    if e != ok { ret (p, e) }
    p.dict_size = le32(src, 1usize)
    if p.dict_size < 4096u32 { p.dict_size = 4096u32 }
    p.unpacked = le64(src, 5usize)
    p.has_size = p.unpacked != 18446744073709551615u64
    ret (p, ok)
}

// --- Range decoder.

fn rc_init(d: *Lz) -> err {
    if d.at + 5usize > d.end { ret Malformed }
    if d.src[d.at] != 0u8 { ret Malformed }
    d.range = MARKER
    d.code = (u32(d.src[d.at + 1usize]) << 24u32) | (u32(d.src[d.at + 2usize]) << 16u32) | (u32(d.src[d.at + 3usize]) << 8u32) | u32(d.src[d.at + 4usize])
    d.at += 5usize
    d.bad = false
    if d.code == d.range { ret Malformed }
    ret ok
}

fn rc_byte(d: *Lz) -> u32 {
    if d.at >= d.end {
        d.bad = true
        ret 0u32
    }
    let b = u32(d.src[d.at])
    d.at += 1usize
    ret b
}

fn rc_normalize(d: *Lz) {
    if d.range < 16777216u32 {
        d.range = d.range << 8u32
        d.code = (d.code << 8u32) | rc_byte(d)
    }
}

fn rc_bit(d: *Lz, probs: []u16, i: usize) -> u32 {
    let v = u32(probs[i])
    let bound = (d.range >> 11u32) * v
    if d.code < bound {
        probs[i] = u16(v + ((2048u32 - v) >> 5u32))
        d.range = bound
        rc_normalize(d)
        ret 0u32
    }
    probs[i] = u16(v - (v >> 5u32))
    d.code -= bound
    d.range -= bound
    rc_normalize(d)
    ret 1u32
}

fn rc_direct(d: *Lz, n: u32) -> u32 {
    var res = 0u32
    var i = 0u32
    while i < n {
        d.range = d.range >> 1u32
        d.code = d.code -% d.range
        let t = 0u32 -% (d.code >> 31u32)
        d.code = d.code +% (d.range & t)
        if d.code == d.range { d.bad = true }
        rc_normalize(d)
        res = ((res << 1u32) +% t) +% 1u32
        i += 1u32
    }
    ret res
}

fn tree(d: *Lz, probs: []u16, base: usize, bits: u32) -> u32 {
    var m = 1u32
    var i = 0u32
    while i < bits {
        m = (m << 1u32) + rc_bit(d, probs, base + usize(m))
        i += 1u32
    }
    ret m - (1u32 << bits)
}

fn tree_reverse(d: *Lz, probs: []u16, base: usize, bits: u32) -> u32 {
    var m = 1u32
    var sym = 0u32
    var i = 0u32
    while i < bits {
        let b = rc_bit(d, probs, base + usize(m))
        m = (m << 1u32) + b
        sym = sym | (b << i)
        i += 1u32
    }
    ret sym
}

// A length coder at `base`: choice, choice2, 16 low trees (3 bits), 16 mid trees
// (3 bits), one high tree (8 bits); 514 entries.
fn length(d: *Lz, probs: []u16, base: usize, pos_state: usize) -> u32 {
    if rc_bit(d, probs, base) == 0u32 { ret tree(d, probs, base + 2usize + pos_state * 8usize, 3u32) }
    if rc_bit(d, probs, base + 1usize) == 0u32 { ret 8u32 + tree(d, probs, base + 130usize + pos_state * 8usize, 3u32) }
    ret 16u32 + tree(d, probs, base + 258usize, 8u32)
}

fn distance(d: *Lz, probs: []u16, len: u32) -> u32 {
    var len_state = len
    if len_state > 3u32 { len_state = 3u32 }
    let slot = tree(d, probs, POS_SLOT + usize(len_state) * 64usize, 6u32)
    if slot < 4u32 { ret slot }
    let nbits = (slot >> 1u32) - 1u32
    var dist = (2u32 | (slot & 1u32)) << nbits
    if slot < 14u32 {
        dist += tree_reverse(d, probs, SPEC_POS + usize(dist) - usize(slot) - 1usize, nbits)
    } else {
        dist = dist +% (rc_direct(d, nbits - 4u32) << 4u32)
        dist = dist +% tree_reverse(d, probs, ALIGN, 4u32)
    }
    ret dist
}

fn literal(d: *Lz, probs: []u16, dst: []u8) {
    var prev = 0u32
    if d.pos > d.start { prev = u32(dst[d.pos - 1usize]) }
    let rel = d.pos - d.start
    let lit_state = ((rel & ((1usize << d.lp) - 1usize)) << d.lc) + usize(prev >> (8u32 - d.lc))
    let base = LITERAL + 768usize * lit_state
    var sym = 1u32
    if d.state >= 7u32 {
        var mb = u32(dst[d.pos - usize(d.rep0) - 1usize])
        var go = true
        while go && sym < 256u32 {
            let match_bit = (mb >> 7u32) & 1u32
            mb = (mb << 1u32) & 255u32
            let bit = rc_bit(d, probs, base + usize(((1u32 + match_bit) << 8u32) + sym))
            sym = (sym << 1u32) | bit
            if match_bit != bit { go = false }
        }
    }
    while sym < 256u32 { sym = (sym << 1u32) | rc_bit(d, probs, base + usize(sym)) }
    dst[d.pos] = u8(sym - 256u32)
    d.pos += 1usize
}

fn reset_probs(probs: []u16, lc: u32, lp: u32) {
    let n = probs_required(lc, lp)
    var i = 0usize
    while i < n {
        probs[i] = 1024u16
        i += 1usize
    }
}

// Decodes symbols until `end_pos` is reached (with `has_size`, exactly, allowing a
// trailing end marker) or until the end marker (without, `end_pos` is the buffer
// end and running past it is TooSmall).
fn run(d: *Lz, probs: []u16, dst: []u8, end_pos: usize, has_size: bool) -> err {
    while true {
        if d.bad { ret Malformed }
        if has_size && d.pos == end_pos && d.code == 0u32 { ret ok }
        let pos_state = (d.pos - d.start) & ((1usize << d.pb) - 1usize)
        if rc_bit(d, probs, IS_MATCH + usize(d.state) * 16usize + pos_state) == 0u32 {
            if d.pos == end_pos {
                if has_size { ret Malformed }
                ret TooSmall
            }
            literal(d, probs, dst)
            if d.state < 4u32 {
                d.state = 0u32
            } else if d.state < 10u32 {
                d.state -= 3u32
            } else {
                d.state -= 6u32
            }
            continue
        }
        var len = 0u32
        if rc_bit(d, probs, IS_REP + usize(d.state)) != 0u32 {
            if d.pos == end_pos {
                if has_size { ret Malformed }
                ret TooSmall
            }
            if d.pos == d.start { ret Malformed }
            if rc_bit(d, probs, IS_REP_G0 + usize(d.state)) == 0u32 {
                if rc_bit(d, probs, IS_REP0_LONG + usize(d.state) * 16usize + pos_state) == 0u32 {
                    if d.state < 7u32 { d.state = 9u32 } else { d.state = 11u32 }
                    dst[d.pos] = dst[d.pos - usize(d.rep0) - 1usize]
                    d.pos += 1usize
                    continue
                }
            } else {
                var dist = 0u32
                if rc_bit(d, probs, IS_REP_G1 + usize(d.state)) == 0u32 {
                    dist = d.rep1
                } else {
                    if rc_bit(d, probs, IS_REP_G2 + usize(d.state)) == 0u32 {
                        dist = d.rep2
                    } else {
                        dist = d.rep3
                        d.rep3 = d.rep2
                    }
                    d.rep2 = d.rep1
                }
                d.rep1 = d.rep0
                d.rep0 = dist
            }
            len = length(d, probs, REP_LEN, pos_state)
            if d.state < 7u32 { d.state = 8u32 } else { d.state = 11u32 }
        } else {
            d.rep3 = d.rep2
            d.rep2 = d.rep1
            d.rep1 = d.rep0
            len = length(d, probs, LEN, pos_state)
            if d.state < 7u32 { d.state = 7u32 } else { d.state = 10u32 }
            d.rep0 = distance(d, probs, len)
            if d.rep0 == MARKER {
                if d.code == 0u32 && !d.bad { ret ok }
                ret Malformed
            }
            if d.pos == end_pos {
                if has_size { ret Malformed }
                ret TooSmall
            }
            if d.rep0 >= d.dict_size || usize(d.rep0) >= d.pos - d.start { ret Malformed }
        }
        let n = usize(len) + 2usize
        if d.pos + n > end_pos {
            if has_size { ret Malformed }
            ret TooSmall
        }
        let from = d.pos - usize(d.rep0) - 1usize
        var k = 0usize
        while k < n {
            dst[d.pos + k] = dst[from + k]
            k += 1usize
        }
        d.pos += n
    }
    ret Malformed
}

fn set_lz_props(d: *Lz, p: Props) {
    d.lc = p.lc
    d.lp = p.lp
    d.pb = p.pb
    d.dict_size = p.dict_size
    if d.dict_size == 0u32 { d.dict_size = MARKER }
}

// The raw LZMA stream (what follows the alone header), decoded with `props`.
// TooSmall when `dst` or `probs` is short, Malformed on a bad stream or a missing
// end marker when the size is unknown, Invalid for unusable properties.
fn decode_raw(p: Props, src: []const u8, dst: []u8, probs: []u16) -> (usize, err) {
    if p.lc > 8u32 || p.lp > 4u32 || p.pb > 4u32 || p.lc + p.lp > 4u32 { ret (0usize, Invalid) }
    if probs.len < probs_required(p.lc, p.lp) { ret (0usize, TooSmall) }
    if p.has_size && p.unpacked > u64(dst.len) { ret (0usize, TooSmall) }
    reset_probs(probs, p.lc, p.lp)
    var d: Lz = zero
    d.src = src
    d.at = 0usize
    d.end = src.len
    set_lz_props(&d, p)
    let e = rc_init(&d)
    if e != ok { ret (0usize, e) }
    var end_pos = dst.len
    if p.has_size { end_pos = usize(p.unpacked) }
    let e2 = run(&d, probs, dst, end_pos, p.has_size)
    ret (d.pos, e2)
}

// The alone format: header then stream.
fn decode(src: []const u8, dst: []u8, probs: []u16) -> (usize, err) {
    let (p, e) = header(src)
    if e != ok { ret (0usize, e) }
    let (n, e2) = decode_raw(p, src[13..], dst, probs)
    ret (n, e2)
}

// --- .xz

fn vli(src: []const u8, at: *usize) -> (u64, err) {
    var v = 0u64
    var i = 0u32
    while i < 9u32 {
        if *at >= src.len { ret (0u64, Malformed) }
        let b = u64(src[*at])
        *at += 1usize
        v = v | ((b & 127u64) << (7u32 * i))
        if (b & 128u64) == 0u64 { ret (v, ok) }
        i += 1u32
    }
    ret (0u64, Malformed)
}

fn crc64(data: []const u8) -> u64 {
    var c = 18446744073709551615u64
    var at = 0usize
    while at < data.len {
        c = c ^ u64(data[at])
        var bit = 0usize
        while bit < 8usize {
            let shifted = c >> 1u32
            if (c & 1u64) != 0u64 {
                c = shifted ^ 14514072000185962306u64
            } else {
                c = shifted
            }
            bit += 1usize
        }
        at += 1usize
    }
    ret ~c
}

fn lzma2_dict_size(b: u8) -> (u32, err) {
    if b > 40u8 { ret (0u32, Invalid) }
    if b == 40u8 { ret (MARKER, ok) }
    let v = u32(b)
    ret ((2u32 | (v & 1u32)) << (v / 2u32 + 11u32), ok)
}

// LZMA2 chunks from `src[at..]` into `dst[out..]`; answers the position after the
// end chunk and the output position.
fn lzma2(src: []const u8, at0: usize, dst: []u8, out: usize, probs: []u16, dict_size: u32) -> (usize, usize, err) {
    var at = at0
    var d: Lz = zero
    d.src = src
    d.end = src.len
    d.dict_size = dict_size
    d.pos = out
    d.start = out
    var need_dict = true
    var need_props = true
    var going = true
    while going {
        if at >= src.len { ret (at, d.pos, Malformed) }
        let c = u32(src[at])
        at += 1usize
        if c == 0u32 {
            going = false
        } else if c <= 2u32 {
            if c == 1u32 {
                d.start = d.pos
                need_dict = false
            } else if need_dict {
                ret (at, d.pos, Malformed)
            }
            if at + 2usize > src.len { ret (at, d.pos, Malformed) }
            let size = ((usize(src[at]) << 8u32) | usize(src[at + 1usize])) + 1usize
            at += 2usize
            if at + size > src.len { ret (at, d.pos, Malformed) }
            if d.pos + size > dst.len { ret (at, d.pos, TooSmall) }
            var k = 0usize
            while k < size {
                dst[d.pos + k] = src[at + k]
                k += 1usize
            }
            d.pos += size
            at += size
        } else if c < 128u32 {
            ret (at, d.pos, Malformed)
        } else {
            if at + 4usize > src.len { ret (at, d.pos, Malformed) }
            let mode = (c >> 5u32) & 3u32
            let unpacked = ((usize(c & 31u32) << 16u32) | (usize(src[at]) << 8u32) | usize(src[at + 1usize])) + 1usize
            let packed = ((usize(src[at + 2usize]) << 8u32) | usize(src[at + 3usize])) + 1usize
            at += 4usize
            if mode == 3u32 {
                d.start = d.pos
                need_dict = false
            } else if need_dict {
                ret (at, d.pos, Malformed)
            }
            if mode >= 2u32 {
                if at >= src.len { ret (at, d.pos, Malformed) }
                var p: Props = zero
                let e = set_props_byte(&p, src[at])
                if e != ok { ret (at, d.pos, e) }
                at += 1usize
                p.dict_size = dict_size
                set_lz_props(&d, p)
                if probs.len < probs_required(d.lc, d.lp) { ret (at, d.pos, TooSmall) }
                need_props = false
            } else if need_props {
                ret (at, d.pos, Malformed)
            }
            if mode >= 1u32 {
                reset_probs(probs, d.lc, d.lp)
                d.state = 0u32
                d.rep0 = 0u32
                d.rep1 = 0u32
                d.rep2 = 0u32
                d.rep3 = 0u32
            }
            if at + packed > src.len { ret (at, d.pos, Malformed) }
            if d.pos + unpacked > dst.len { ret (at, d.pos, TooSmall) }
            d.at = at
            d.end = at + packed
            let e2 = rc_init(&d)
            if e2 != ok { ret (at, d.pos, e2) }
            let e3 = run(&d, probs, dst, d.pos + unpacked, true)
            if e3 != ok { ret (at, d.pos, e3) }
            if d.at != d.end { ret (at, d.pos, Malformed) }
            at = d.end
        }
    }
    ret (at, d.pos, ok)
}

fn check_size(kind: u32) -> usize {
    if kind == 0u32 { ret 0usize }
    if kind <= 3u32 { ret 4usize }
    if kind <= 6u32 { ret 8usize }
    if kind <= 9u32 { ret 16usize }
    if kind <= 12u32 { ret 32usize }
    ret 64usize
}

// A .xz stream: every block (single LZMA2 filter) decoded into `dst`, each block's
// check verified (CRC32, CRC64, SHA-256; none accepted; other kinds Unsupported),
// then the index and the footer. Answers the bytes written.
fn decode_xz(src: []const u8, dst: []u8, probs: []u16) -> (usize, err) {
    if src.len < 32usize { ret (0usize, Malformed) }
    if src[0] != 253u8 || src[1] != 55u8 || src[2] != 122u8 || src[3] != 88u8 || src[4] != 90u8 || src[5] != 0u8 { ret (0usize, Malformed) }
    if src[6] != 0u8 || src[7] > 15u8 { ret (0usize, Malformed) }
    if hash.crc32(src[6..8]) != le32(src, 8usize) { ret (0usize, Checksum) }
    let kind = u32(src[7])
    let clen = check_size(kind)
    var at = 12usize
    var out = 0usize
    var blocks = 0u64
    var in_blocks = true
    while in_blocks {
        if at >= src.len { ret (out, Malformed) }
        if src[at] == 0u8 {
            in_blocks = false
        } else {
            let hlen = (usize(src[at]) + 1usize) * 4usize
            if at + hlen > src.len { ret (out, Malformed) }
            if hash.crc32(src[at..at + hlen - 4usize]) != le32(src, at + hlen - 4usize) { ret (out, Checksum) }
            let flags = u32(src[at + 1usize])
            if (flags & 3u32) != 0u32 { ret (out, Unsupported) }
            if (flags & 60u32) != 0u32 { ret (out, Malformed) }
            var h = at + 2usize
            if (flags & 64u32) != 0u32 {
                let (_, e) = vli(src, &h)
                if e != ok { ret (out, e) }
            }
            if (flags & 128u32) != 0u32 {
                let (_, e) = vli(src, &h)
                if e != ok { ret (out, e) }
            }
            let (id, e1) = vli(src, &h)
            if e1 != ok { ret (out, e1) }
            if id != 33u64 { ret (out, Unsupported) }
            let (plen, e2) = vli(src, &h)
            if e2 != ok { ret (out, e2) }
            if plen != 1u64 || h >= at + hlen - 4usize { ret (out, Malformed) }
            let (dict_size, e3) = lzma2_dict_size(src[h])
            if e3 != ok { ret (out, e3) }
            at += hlen
            let block_start = at
            let block_out = out
            let (at2, out2, e4) = lzma2(src, at, dst, out, probs, dict_size)
            if e4 != ok { ret (out2, e4) }
            at = at2
            out = out2
            while ((at - block_start) & 3usize) != 0usize {
                if at >= src.len || src[at] != 0u8 { ret (out, Malformed) }
                at += 1usize
            }
            if at + clen > src.len { ret (out, Malformed) }
            if kind == 1u32 {
                if hash.crc32(dst[block_out..out]) != le32(src, at) { ret (out, Checksum) }
            } else if kind == 4u32 {
                if crc64(dst[block_out..out]) != le64(src, at) { ret (out, Checksum) }
            } else if kind == 10u32 {
                let digest = chash.sha256(dst[block_out..out])
                var i = 0usize
                while i < 32usize {
                    if digest[i] != src[at + i] { ret (out, Checksum) }
                    i += 1usize
                }
            } else if kind != 0u32 {
                ret (out, Unsupported)
            }
            at += clen
            blocks += 1u64
        }
    }
    // Index: indicator, record count, (unpadded size, uncompressed size) pairs,
    // padding, CRC32.
    let index_start = at
    at += 1usize
    let (count, e5) = vli(src, &at)
    if e5 != ok { ret (out, e5) }
    if count != blocks { ret (out, Malformed) }
    var total = 0u64
    var r = 0u64
    while r < count {
        let (_, e6) = vli(src, &at)
        if e6 != ok { ret (out, e6) }
        let (unpacked, e7) = vli(src, &at)
        if e7 != ok { ret (out, e7) }
        total += unpacked
        r += 1u64
    }
    if total != u64(out) { ret (out, Malformed) }
    while ((at - index_start) & 3usize) != 0usize {
        if at >= src.len || src[at] != 0u8 { ret (out, Malformed) }
        at += 1usize
    }
    if at + 4usize > src.len { ret (out, Malformed) }
    if hash.crc32(src[index_start..at]) != le32(src, at) { ret (out, Checksum) }
    at += 4usize
    // Footer: CRC32, backward size, stream flags, "YZ".
    if at + 12usize > src.len { ret (out, Malformed) }
    if hash.crc32(src[at + 4usize..at + 10usize]) != le32(src, at) { ret (out, Checksum) }
    if (usize(le32(src, at + 4usize)) + 1usize) * 4usize != at - index_start { ret (out, Malformed) }
    if src[at + 8usize] != 0u8 || src[at + 9usize] != src[7] || src[at + 10usize] != 89u8 || src[at + 11usize] != 90u8 { ret (out, Malformed) }
    ret (out, ok)
}
