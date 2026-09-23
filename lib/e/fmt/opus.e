// Opus decoding (RFC 6716): packet framing (section 3), the range decoder
// (section 4.1), the SILK layer (section 4.2) and the CELT layer (section 4.3).
//
// `packet_parse` splits a raw Opus packet into its frames for all four codes,
// including the code 3 padding rule, and the section 3.4 refusals answer
// `Malformed`.  `packet_mode`, `packet_bandwidth`, `packet_frame_size_us`,
// `packet_channels` and `packet_samples` read the TOC byte.  The range decoder
// is the one both layers share: `range_init`, `range_decode`/`range_update`,
// `range_decode_bit_logp`, `range_decode_icdf`, `range_decode_raw_bits`,
// `range_decode_uint` and the two bit counters `range_tell`/`range_tell_frac`.
//
// `decoder` opens a decoder over an arena and `decode` decodes one whole packet
// into interleaved `f32`, in mono or stereo, for all three modes:
//
//   * CELT-only, at 48 kHz, 2.5/5/10/20 ms.  The CELT layer has no decimator, so
//     another output rate answers `Unsupported`.
//   * SILK-only, at 8, 12, 16, 24 or 48 kHz, 10/20/40/60 ms.  The LP layer is
//     integer arithmetic end to end and `resamp_process` is the reference's own
//     integer resampler, so these are bit-exact against libopus.
//   * hybrid, at 48 kHz, 10/20 ms: the LP layer decodes at 16 kHz from the
//     packet's range decoder, `celt_decode_frame` runs on that same decoder from
//     band 17, and the resampled, delay-matched SILK part is added to it.
//
// Where the CELT layer is involved the worst sample is within 1.53e-5 of full
// scale of libopus, which is half a step of the fixture's 16-bit reference.
//
// Section 4.5 is not here: packet loss concealment, redundancy frames (a hybrid
// packet that signals one answers `Unsupported`) and the cross-faded mode
// transitions.  A mid-stream mode or bandwidth change re-initialises the LP
// state instead, so the first frame after a switch is not bit-exact.
//
// Every static table is generated from the RFC's own tables by the fixture's
// reference script and emitted below as a byte string.

use e.math
use e.mem

type Mode = enum u8 { Silk, Hybrid, Celt }
type Bandwidth = enum u8 { Narrow, Medium, Wide, SuperWide, Full }
type Frame = struct { data: []const u8 }
type Range = struct { data: []const u8, pos: usize, value: u32, rng: u32, rem: i32, ext: u32, end_pos: usize, end_window: u32, end_bits: i32, total_bits: i32 }

error Invalid
error Malformed
error Unsupported
error TooSmall

const MAX_FRAME_BYTES: usize = 1275usize
const MAX_FRAMES: usize = 48usize

// ------------------------------------------------------------------ TOC, section 3.1

fn packet_mode(toc: u8) -> Mode {
    let config = toc >> 3u32
    if config < 12u8 { ret .Silk }
    if config < 16u8 { ret .Hybrid }
    ret .Celt
}

fn packet_bandwidth(toc: u8) -> Bandwidth {
    let config = toc >> 3u32
    if config < 4u8 { ret .Narrow }
    if config < 8u8 { ret .Medium }
    if config < 12u8 { ret .Wide }
    if config < 14u8 { ret .SuperWide }
    if config < 16u8 { ret .Full }
    let c = (config - 16u8) >> 2u32
    if c == 0u8 { ret .Narrow }
    if c == 1u8 { ret .Wide }
    if c == 2u8 { ret .SuperWide }
    ret .Full
}

fn packet_frame_size_us(toc: u8) -> u32 {
    let config = toc >> 3u32
    if config < 12u8 {
        let k = u32(config & 3u8)
        if k == 0u32 { ret 10000u32 }
        if k == 1u32 { ret 20000u32 }
        if k == 2u32 { ret 40000u32 }
        ret 60000u32
    }
    if config < 16u8 {
        if (config & 1u8) == 0u8 { ret 10000u32 }
        ret 20000u32
    }
    let k = u32(config & 3u8)
    if k == 0u32 { ret 2500u32 }
    if k == 1u32 { ret 5000u32 }
    if k == 2u32 { ret 10000u32 }
    ret 20000u32
}

fn packet_channels(toc: u8) -> u32 {
    if (toc & 4u8) != 0u8 { ret 2u32 }
    ret 1u32
}

// ------------------------------------------------------------------ framing, section 3.2

fn frame_length(packet: []const u8, from: usize) -> (usize, usize, err) {
    if from >= packet.len { ret (0usize, 0usize, Malformed) }
    let b = usize(packet[from])
    if b < 252usize { ret (b, from + 1usize, ok) }
    if from + 1usize >= packet.len { ret (0usize, 0usize, Malformed) }
    ret (b + 4usize * usize(packet[from + 1usize]), from + 2usize, ok)
}

fn packet_parse(packet: []const u8, frames: []Frame) -> (usize, err) {
    if packet.len < 1usize { ret (0usize, Malformed) }
    let toc = packet[0usize]
    let code = toc & 3u8
    let total = packet.len
    if code == 0u8 {
        let size = total - 1usize
        if size > MAX_FRAME_BYTES { ret (0usize, Malformed) }
        if frames.len < 1usize { ret (0usize, TooSmall) }
        frames[0usize] = Frame { data: packet[1usize..total] }
        ret (1usize, ok)
    }
    if code == 1u8 {
        let size = total - 1usize
        if (size & 1usize) != 0usize { ret (0usize, Malformed) }
        let half = size >> 1u32
        if half > MAX_FRAME_BYTES { ret (0usize, Malformed) }
        if frames.len < 2usize { ret (0usize, TooSmall) }
        frames[0usize] = Frame { data: packet[1usize..1usize + half] }
        frames[1usize] = Frame { data: packet[1usize + half..total] }
        ret (2usize, ok)
    }
    if code == 2u8 {
        let (first, after, length_error) = frame_length(packet, 1usize)
        if length_error != ok { ret (0usize, length_error) }
        if first > MAX_FRAME_BYTES { ret (0usize, Malformed) }
        if after + first > total { ret (0usize, Malformed) }
        let second = total - after - first
        if second > MAX_FRAME_BYTES { ret (0usize, Malformed) }
        if frames.len < 2usize { ret (0usize, TooSmall) }
        frames[0usize] = Frame { data: packet[after..after + first] }
        frames[1usize] = Frame { data: packet[after + first..total] }
        ret (2usize, ok)
    }
    if total < 2usize { ret (0usize, Malformed) }
    let control = packet[1usize]
    var pos = 2usize
    let vbr = (control & 128u8) != 0u8
    let padded = (control & 64u8) != 0u8
    let count = usize(control & 63u8)
    if count < 1usize || count > MAX_FRAMES { ret (0usize, Malformed) }
    if usize(packet_frame_size_us(toc)) * count > 120000usize { ret (0usize, Malformed) }
    var padding = 0usize
    if padded {
        while true {
            if pos >= total { ret (0usize, Malformed) }
            let p = usize(packet[pos])
            pos += 1usize
            if p == 255usize {
                padding += 254usize
            } else {
                padding += p
                break
            }
        }
    }
    if pos + padding > total { ret (0usize, Malformed) }
    let body_end = total - padding
    if frames.len < count { ret (0usize, TooSmall) }
    if vbr {
        var sum = 0usize
        var i = 0usize
        var sizes: [48]usize = zero
        while i + 1usize < count {
            let (size, after, length_error) = frame_length(packet, pos)
            if length_error != ok { ret (0usize, length_error) }
            if size > MAX_FRAME_BYTES { ret (0usize, Malformed) }
            sizes[i] = size
            sum += size
            pos = after
            i += 1usize
        }
        if pos > body_end || sum > body_end - pos { ret (0usize, Malformed) }
        let last = body_end - pos - sum
        if last > MAX_FRAME_BYTES { ret (0usize, Malformed) }
        sizes[count - 1usize] = last
        i = 0usize
        while i < count {
            frames[i] = Frame { data: packet[pos..pos + sizes[i]] }
            pos += sizes[i]
            i += 1usize
        }
        ret (count, ok)
    }
    if pos > body_end { ret (0usize, Malformed) }
    let rest = body_end - pos
    if rest % count != 0usize { ret (0usize, Malformed) }
    let each = rest / count
    if each > MAX_FRAME_BYTES { ret (0usize, Malformed) }
    var i = 0usize
    while i < count {
        frames[i] = Frame { data: packet[pos..pos + each] }
        pos += each
        i += 1usize
    }
    ret (count, ok)
}

fn packet_samples(packet: []const u8, rate: u32) -> (usize, err) {
    var frames: [48]Frame = zero
    let (count, parse_error) = packet_parse(packet, frames[..])
    if parse_error != ok { ret (0usize, parse_error) }
    let per = usize(packet_frame_size_us(packet[0usize])) * usize(rate) / 1000000usize
    ret (count * per, ok)
}

// ------------------------------------------------------------------ range decoder, section 4.1

const EC_SYM_BITS: u32 = 8u32
const EC_CODE_BITS: u32 = 32u32
const EC_SYM_MAX: u32 = 255u32
const EC_CODE_TOP: u32 = 2147483648u32
const EC_CODE_BOT: u32 = 8388608u32
const EC_CODE_EXTRA: u32 = 7u32
const EC_UINT_BITS: u32 = 8u32
const EC_WINDOW_SIZE: i32 = 32i32
const BITRES: i32 = 3i32

fn ilog32(v: u32) -> i32 {
    var x = v
    var n = 0i32
    while x != 0u32 {
        x >>= 1u32
        n += 1i32
    }
    ret n
}

fn read_byte(r: *Range) -> u32 {
    if r.pos < r.data.len {
        let b = u32(r.data[r.pos])
        r.pos += 1usize
        ret b
    }
    ret 0u32
}

fn read_byte_from_end(r: *Range) -> u32 {
    if r.end_pos < r.data.len {
        r.end_pos += 1usize
        ret u32(r.data[r.data.len - r.end_pos])
    }
    ret 0u32
}

fn normalize(r: *Range) {
    while r.rng <= EC_CODE_BOT {
        r.total_bits += i32(EC_SYM_BITS)
        r.rng = r.rng << EC_SYM_BITS
        var sym = u32(r.rem)
        r.rem = i32(read_byte(r))
        sym = ((sym << EC_SYM_BITS) | u32(r.rem)) >> (EC_SYM_BITS - EC_CODE_EXTRA)
        let add = EC_SYM_MAX & (~sym) & 255u32
        let v = (u64(r.value) << EC_SYM_BITS) + u64(add)
        r.value = u32(v & u64(EC_CODE_TOP - 1u32))
    }
}

fn range_init(data: []const u8) -> Range {
    var r = Range { data: data, pos: 0usize, value: 0u32, rng: 1u32 << EC_CODE_EXTRA, rem: 0i32, ext: 0u32, end_pos: 0usize, end_window: 0u32, end_bits: 0i32, total_bits: 0i32 }
    r.total_bits = i32(EC_CODE_BITS) + 1i32 - i32((EC_CODE_BITS - EC_CODE_EXTRA) / EC_SYM_BITS) * i32(EC_SYM_BITS)
    r.rem = i32(read_byte(&r))
    r.value = r.rng - 1u32 - (u32(r.rem) >> (EC_SYM_BITS - EC_CODE_EXTRA))
    normalize(&r)
    ret r
}

fn range_decode(r: *Range, ft: u32) -> u32 {
    r.ext = r.rng / ft
    let s = r.value / r.ext
    var t = s + 1u32
    if t > ft { t = ft }
    ret ft - t
}

fn range_decode_bin(r: *Range, bits: u32) -> u32 {
    r.ext = r.rng >> bits
    let s = r.value / r.ext
    let ft = 1u32 << bits
    var t = s + 1u32
    if t > ft { t = ft }
    ret ft - t
}

fn range_update(r: *Range, fl: u32, fh: u32, ft: u32) {
    let s = u32((u64(r.ext) * u64(ft - fh)) & 4294967295u64)
    r.value = r.value -% s
    if fl > 0u32 {
        r.rng = u32((u64(r.ext) * u64(fh - fl)) & 4294967295u64)
    } else {
        r.rng = r.rng -% s
    }
    normalize(r)
}

fn range_decode_bit_logp(r: *Range, logp: u32) -> u32 {
    let rr = r.rng
    let d = r.value
    let s = rr >> logp
    var got = 0u32
    if d < s { got = 1u32 }
    if got == 0u32 {
        r.value = d - s
        r.rng = rr - s
    } else {
        r.rng = s
    }
    normalize(r)
    ret got
}

fn range_decode_icdf(r: *Range, icdf: []const u8, ftb: u32) -> u32 {
    var s = r.rng
    let d = r.value
    let rr = r.rng >> ftb
    var t = s
    var got = 0i32
    got = 0i32 - 1i32
    while true {
        t = s
        got += 1i32
        s = u32((u64(rr) * u64(icdf[usize(got)])) & 4294967295u64)
        if d >= s { break }
    }
    r.value = d - s
    r.rng = t - s
    normalize(r)
    ret u32(got)
}

fn range_decode_raw_bits(r: *Range, bits: u32) -> u32 {
    var window = u64(r.end_window)
    var available = r.end_bits
    if available < i32(bits) {
        while true {
            window |= u64(read_byte_from_end(r)) << u32(available)
            available += i32(EC_SYM_BITS)
            if available > EC_WINDOW_SIZE - i32(EC_SYM_BITS) { break }
        }
    }
    let got = u32(window & ((1u64 << bits) - 1u64))
    window >>= bits
    available -= i32(bits)
    r.end_window = u32(window & 4294967295u64)
    r.end_bits = available
    r.total_bits += i32(bits)
    ret got
}

fn range_decode_uint(r: *Range, ft_in: u32) -> u32 {
    var ft = ft_in - 1u32
    let ftb = ilog32(ft)
    if ftb > i32(EC_UINT_BITS) {
        let shift = u32(ftb - i32(EC_UINT_BITS))
        let small = (ft >> shift) + 1u32
        let s = range_decode(r, small)
        range_update(r, s, s + 1u32, small)
        let t = (s << shift) | range_decode_raw_bits(r, shift)
        if t <= ft { ret t }
        ret ft
    }
    ft += 1u32
    let s = range_decode(r, ft)
    range_update(r, s, s + 1u32, ft)
    ret s
}

fn range_tell(r: *const Range) -> i32 {
    ret r.total_bits - ilog32(r.rng)
}

fn range_tell_frac(r: *const Range) -> i32 {
    let nbits = r.total_bits << u32(BITRES)
    var l = ilog32(r.rng)
    var rr = u64(r.rng >> u32(l - 16i32))
    var i = 0i32
    while i < BITRES {
        rr = (rr * rr) >> 15u32
        let b = i32(rr >> 16u32)
        l = (l << 1u32) | b
        rr >>= u32(b)
        i += 1i32
    }
    ret nbits - l
}

// ------------------------------------------------------------------ CELT tables (generated)

fn t_ebands() -> str { ret "\x00\x01\x02\x03\x04\x05\x06\x07\x08\x0a\x0c\x0e\x10\x14\x18\x1c\"(0<Nd" }
fn t_band_alloc() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00ZPKE?81(\"\x1d\x14\x12\x0a\x00\x00\x00\x00\x00\x00\x00\x00ndZTNGA:3-' \x1a\x14\x0c\x00\x00\x00\x00\x00\x00vng]VPKFA;5/(\x1f\x17\x0f\x04\x00\x00\x00\x00~wph_YSNHB<6/' \x19\x11\x0c\x01\x00\x00\x86\x7fxrga[UNHB<6/)#\x1d\x17\x10\x0a\x01\x90\x89\x82|qke_XRLF@93-'!\x1a\x0f\x01\x98\x91\x8a\x84{uoib\\VPJC=71+$\x14\x01\xa2\x9b\x94\x8e\x85\x7fyslf`ZTMGA;5.\x1e\x01\xac\xa5\x9e\x98\x8f\x89\x83}vpjd^WQKE?8-\x14\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc8\xc6\xc1\xbc\xb7\xb2\xad\xa8\xa3\x9e\x99\x94\x81h" }
fn t_logn() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x08\x08\x08\x08\x10\x10\x10\x15\x15\x18\x1d\"$" }
fn t_cache_index() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x00\x01\x01\x01\x01***SS|\xa5\xc9\xdf\x01\x01\x01\x01\x01\x01\x01\x01****|||\xa5\xa5\xf1\x0b\x1c(********||||\xf1\xf1\xf1\x0b\x0b2?IQ||||||||\xf1\xf1\xf1\xf1222??X`gm\xf1\xf1\xf1\xf1\xf1\xf1\xf1\xf12222XXX``sy\x7f\x84\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x01\x01\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01\x01" }
fn t_cache_bits() -> str { ret "(\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07\x07(\x0f\x17\x1c\x1f\"$&')*+,-.//123456779:;<=>??ABCDEFGG(\x14!)059=@BEGIKLNPRUWY[\\^`begiklnpruwy{|~\x80(\x17'3<CIOSW[^adfikosvy|~\x81\x83\x87\x8b\x8e\x91\x94\x96\x99\x9b\x9f\xa3\xa6\xa9\xac\xae\xb1\xb3#\x1c1ANYckrx~\x84\x88\x8d\x91\x95\x99\x9f\xa5\xab\xb0\xb4\xb9\xbd\xc0\xc7\xcd\xd3\xd8\xdc\xe1\xe5\xe8\xef\xf5\xfb\x15!:Oap}\x89\x94\x9d\xa6\xae\xb6\xbd\xc3\xc9\xcf\xd9\xe3\xeb\xf3\xfb\x11#?Vj{\x8b\x98\xa5\xb1\xbb\xc5\xce\xd6\xde\xe6\xed\xfa\x19\x1f7K[iu\x80\x8a\x92\x9a\xa1\xa8\xae\xb4\xb9\xbe\xc8\xd0\xd7\xde\xe5\xeb\xf0\xf5\xff\x10$AYn\x80\x90\x9f\xad\xb9\xc4\xcf\xd9\xe2\xea\xf2\xfa\x0b)Jg\x80\x97\xac\xbf\xd1\xe1\xf1\xff\x09+On\x8a\xa3\xba\xcf\xe3\xf6\x0c'Gc{\x90\xa4\xb6\xc6\xd6\xe4\xf1\xfd\x09,Qq\x8e\xa8\xc0\xd6\xeb\xff\x071Z\x7f\xa0\xbf\xdc\xf7\x063_\x86\xaa\xcb\xea\x07/W{\x9b\xb8\xd4\xed\x064a\x89\xae\xd0\xf0\x059j\x97\xc0\xe7\x05;o\x9e\xca\xf3\x057g\x93\xbb\xe0\x05<q\xa1\xce\xf8\x04Az\xaf\xe0\x04C\x7f\xb6\xea" }
fn t_cache_caps() -> str { ret "\xe0\xe0\xe0\xe0\xe0\xe0\xe0\xe0\xa0\xa0\xa0\xa0\xb9\xb9\xb9\xb2\xb2\xa8\x86=%\xe0\xe0\xe0\xe0\xe0\xe0\xe0\xe0\xf0\xf0\xf0\xf0\xcf\xcf\xcf\xc6\xc6\xb7\x90B(\xa0\xa0\xa0\xa0\xa0\xa0\xa0\xa0\xb9\xb9\xb9\xb9\xc1\xc1\xc1\xb7\xb7\xac\x8a@&\xf0\xf0\xf0\xf0\xf0\xf0\xf0\xf0\xcf\xcf\xcf\xcf\xcc\xcc\xcc\xc1\xc1\xb4\x8fB(\xb9\xb9\xb9\xb9\xb9\xb9\xb9\xb9\xc1\xc1\xc1\xc1\xc1\xc1\xc1\xb7\xb7\xac\x8aA'\xcf\xcf\xcf\xcf\xcf\xcf\xcf\xcf\xcc\xcc\xcc\xcc\xc9\xc9\xc9\xbc\xbc\xb0\x8dB(\xc1\xc1\xc1\xc1\xc1\xc1\xc1\xc1\xc1\xc1\xc1\xc1\xc2\xc2\xc2\xb8\xb8\xad\x8bA'\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xcc\xc9\xc9\xc9\xc9\xc6\xc6\xc6\xbb\xbb\xaf\x8cB(" }
fn t_e_prob() -> str { ret "H\x7fA\x81B\x80A\x80@\x80>\x80@\x80@\x80\\N\\O\\NZOt)s(r(\x84\x1a\x84\x1a\x91\x11\xa1\x0c\xb0\x0a\xb1\x0b\x18\xb30\x8a6\x876\x845\x868\x857\x847\x84=rF`JXKXWJYB[Cd;l2x(z%a+N2SNTQXKVJWGZI]J]Jm(r$u\"u\"\x8f\x11\x91\x12\x92\x13\xa2\x0c\xa5\x0a\xb2\x07\xbd\x06\xbe\x08\xb1\x09\x17\xb26s?fBbEcJYG[I[NYVP\\B]@f;g<h<u4{,\x8a#\x85\x1fa&M-=Z]<i*k)n-t&q&p&|\x1a\x84\x1b\x88\x13\x8c\x14\x9b\x0e\x9f\x10\x9e\x12\xaa\x0d\xb1\x0a\xbb\x08\xc0\x06\xaf\x09\x9f\x0a\x15\xb2;nGVKUTS[BXIWH\\KbHi:k6s4r7p8\x813\x84(\x96!\x8c\x1db#M**y`Bl+o(u,{ x$w!\x7f!\x86\"\x8b\x15\x93\x17\x98\x14\x9e\x19\x9a\x1a\xa6\x15\xad\x10\xb8\x0d\xb8\x0a\x96\x0d\x8b\x0f\x16\xb2?rJRTS\\Rg>`H`CeIkHq7v4}4v4u7\x871\x89'\x9d \x91\x1da!M(" }
fn t_emeans() -> str { ret "gd\\UQMHFNKIGNJEHFJLG<" }
fn t_tf_select() -> str { ret "\x08\x07\x08\x07\x08\x07\x08\x07\x08\x07\x08\x06\x09\x08\x09\x07\x08\x06\x08\x05\x0a\x08\x09\x07\x08\x06\x08\x05\x0b\x08\x09\x07" }
fn t_trim_icdf() -> str { ret "~|wmW)\x13\x09\x04\x02\x00" }
fn t_spread_icdf() -> str { ret "\x19\x17\x02\x00" }
fn t_tapset_icdf() -> str { ret "\x02\x01\x00" }
fn t_small_icdf() -> str { ret "\x02\x01\x00" }
fn t_log2_frac() -> str { ret "\x00\x08\x0d\x10\x13\x15\x17\x18\x1a\x1b\x1c\x1d\x1e\x1f  !\"\"#$$%%" }
fn t_ordery() -> str { ret "\x01\x00\x03\x00\x02\x01\x07\x00\x04\x03\x06\x01\x05\x02\x0f\x00\x08\x07\x0c\x03\x0b\x04\x0e\x01\x09\x06\x0d\x02\x0a\x05" }
fn t_bit_interleave() -> str { ret "\x00\x01\x01\x01\x02\x03\x03\x03\x02\x03\x03\x03\x02\x03\x03\x03" }
fn t_bit_deinterleave() -> str { ret "\x00\x03\x0c\x0f03<?\xc0\xc3\xcc\xcf\xf0\xf3\xfc\xff" }
fn t_exp2_8() -> str { ret "\x00\xca\x1b\xff\x82\xb3\xa2`@ELRZbku" }
fn t_q15() -> str { ret "\x00\x00\x00\x00\xc3\x0a\\\x9a3@\xc8\x98`P\x00`\xd0\x00sfS@uW/\x19\x13'\x1b\x10;\"\x00f\x0c\x00" }

const NBANDS: usize = 21usize
const OVERLAP: usize = 120usize
const SHORT_SIZE: usize = 120usize
const MAXLM: i32 = 3i32
const DECODE_BUFFER: usize = 2048usize
const MAX_PERIOD: usize = 1024usize
const COMB_MIN_PERIOD: i32 = 15i32
const MAX_FINE_BITS: i32 = 8i32
const FINE_OFFSET: i32 = 21i32
const QTHETA_OFFSET: i32 = 4i32
const QTHETA_TWOPHASE: i32 = 16i32
const SPREAD_NONE: u32 = 0u32
const SPREAD_NORMAL: u32 = 2u32
const SPREAD_AGGRESSIVE: u32 = 3u32
const NBALLOC: usize = 11usize

fn eband(i: usize) -> usize { ret usize(t_ebands()[i]) }
fn logn(i: usize) -> i32 { ret i32(t_logn()[i]) }
fn cache_at(lm: usize, band: usize) -> usize {
    let t = t_cache_index()
    let v = i32(t[lm * NBANDS + band]) | (i32(t[105usize + lm * NBANDS + band]) << 8u32)
    ret usize(v - 1i32)
}
fn cache_bits(i: usize) -> i32 { ret i32(t_cache_bits()[i]) }
fn band_alloc(row: usize, j: usize) -> i32 { ret i32(t_band_alloc()[row * NBANDS + j]) }
fn e_prob(lm: i32, intra: u32, i: usize) -> i32 { ret i32(t_e_prob()[(usize(lm) * 2usize + usize(intra)) * 42usize + i]) }
fn emeans(i: usize) -> f32 { ret f32(t_emeans()[i]) * 0.0625f32 }
fn tf_select_at(lm: i32, k: usize) -> i32 { ret i32(t_tf_select()[usize(lm) * 8usize + k]) - 8i32 }
fn log2_frac(i: usize) -> i32 { ret i32(t_log2_frac()[i]) }
fn exp2_8(i: usize) -> i32 {
    let t = t_exp2_8()
    ret i32(t[i]) | (i32(t[8usize + i]) << 8u32)
}
fn q15(i: usize) -> f32 {
    let t = t_q15()
    let v = i32(t[i]) | (i32(t[18usize + i]) << 8u32)
    ret f32(v) * 0.000030517578125f32
}
fn pred_coef(lm: i32) -> f32 { ret q15(usize(lm)) }
fn beta_coef(lm: i32) -> f32 { ret q15(4usize + usize(lm)) }
fn beta_intra() -> f32 { ret q15(8usize) }
fn comb_gain(tapset: usize, k: usize) -> f32 { ret q15(9usize + tapset * 3usize + k) }

// ------------------------------------------------------------------ small integer helpers

fn imin(a: i32, b: i32) -> i32 {
    if a < b { ret a }
    ret b
}
fn imax(a: i32, b: i32) -> i32 {
    if a > b { ret a }
    ret b
}
fn cdiv(a: i32, b: i32) -> i32 {
    // C integer division: truncates toward zero, unlike a floor-dividing shift.
    var x = a
    var negative = false
    if x < 0i32 {
        x = 0i32 - x
        negative = true
    }
    var y = b
    if y < 0i32 {
        y = 0i32 - y
        negative = !negative
    }
    let q = x / y
    if negative { ret 0i32 - q }
    ret q
}
fn sign16(v: i32) -> i32 {
    var x = v & 65535i32
    if x >= 32768i32 { x -= 65536i32 }
    ret x
}
fn frac_mul16(a: i32, b: i32) -> i32 { ret (16384i32 + sign16(a) * sign16(b)) >> 15u32 }
fn bitexact_cos(x: i32) -> i32 {
    let tmp = (4096i32 + x * x) >> 13u32
    let x2 = (32767i32 - tmp) + frac_mul16(tmp, 0i32 - 7651i32 + frac_mul16(tmp, 8277i32 + frac_mul16(0i32 - 626i32, tmp)))
    ret 1i32 + x2
}
fn bitexact_log2tan(isin: i32, icos: i32) -> i32 {
    let lc = ilog32(u32(icos))
    let ls = ilog32(u32(isin))
    let c = icos << u32(15i32 - lc)
    let s = isin << u32(15i32 - ls)
    ret (ls - lc) * 2048i32 + frac_mul16(s, frac_mul16(s, 0i32 - 2597i32) + 7932i32) - frac_mul16(c, frac_mul16(c, 0i32 - 2597i32) + 7932i32)
}
fn isqrt32(v: u32) -> u32 {
    if v == 0u32 { ret 0u32 }
    var g = u32(math.sqrt[f64](f64(v)))
    while g > 0u32 && u64(g) * u64(g) > u64(v) { g -= 1u32 }
    while u64(g + 1u32) * u64(g + 1u32) <= u64(v) { g += 1u32 }
    ret g
}
fn lcg_rand(seed: u32) -> u32 { ret 1664525u32 *% seed +% 1013904223u32 }
fn get_pulses(i: i32) -> i32 {
    if i < 8i32 { ret i }
    ret (8i32 + (i & 7i32)) << u32((i >> 3u32) - 1i32)
}
fn bits2pulses(band: usize, lm: i32, bits_in: i32) -> i32 {
    let base = cache_at(usize(lm + 1i32), band)
    var lo = 0i32
    var hi = cache_bits(base)
    let bits = bits_in - 1i32
    var i = 0i32
    while i < 6i32 {
        let mid = (lo + hi + 1i32) >> 1u32
        if cache_bits(base + usize(mid)) >= bits { hi = mid } else { lo = mid }
        i += 1i32
    }
    var low = 0i32 - 1i32
    if lo != 0i32 { low = cache_bits(base + usize(lo)) }
    if bits - low <= cache_bits(base + usize(hi)) - bits { ret lo }
    ret hi
}
fn pulses2bits(band: usize, lm: i32, pulses: i32) -> i32 {
    if pulses == 0i32 { ret 0i32 }
    ret cache_bits(cache_at(usize(lm + 1i32), band) + usize(pulses)) + 1i32
}

// ------------------------------------------------------------------ Laplace, section 4.3.2.1

fn laplace_decode(r: *Range, fs_in: i32, decay: i32) -> i32 {
    var value = 0i32
    var fs = fs_in
    let fm = i32(range_decode_bin(r, 15u32))
    var fl = 0i32
    if fm >= fs {
        value += 1i32
        fl = fs
        fs = (((32768i32 - 32i32 - fs) * (16384i32 - decay)) >> 15u32) + 1i32
        while fs > 1i32 && fm >= fl + 2i32 * fs {
            fs *= 2i32
            fl += fs
            fs = (((fs - 2i32) * decay) >> 15u32) + 1i32
            value += 1i32
        }
        if fs <= 1i32 {
            let di = (fm - fl) >> 1u32
            value += di
            fl += 2i32 * di
        }
        if fm < fl + fs { value = 0i32 - value } else { fl += fs }
    }
    var fh = fl + fs
    if fh > 32768i32 { fh = 32768i32 }
    range_update(r, u32(fl), u32(fh), 32768u32)
    ret value
}

// ------------------------------------------------------------------ PVQ, section 4.3.4

fn urow_next(u: []u32, ln: usize, first: u32) {
    var u0 = first
    var j = 1usize
    while j < ln {
        let u1 = u[j] +% u[j - 1usize] +% u0
        u[j - 1usize] = u0
        u0 = u1
        j += 1usize
    }
    u[j - 1usize] = u0
}
fn urow_prev(u: []u32, n: usize, first: u32) {
    var u0 = first
    var j = 1usize
    while j < n {
        let u1 = u[j] -% u[j - 1usize] -% u0
        u[j - 1usize] = u0
        u0 = u1
        j += 1usize
    }
    u[j - 1usize] = u0
}
fn ncwrs_urow(n: usize, k: usize, u: []u32) -> u32 {
    u[0usize] = 0u32
    u[1usize] = 1u32
    var j = 2usize
    while j < k + 2usize {
        u[j] = u32(j * 2usize - 1usize)
        j += 1usize
    }
    var i = 2usize
    while i < n {
        urow_next(u[1usize..], k + 1usize, 1u32)
        i += 1usize
    }
    ret u[k] +% u[k + 1usize]
}
fn cwrsi(n: usize, k_in: usize, index: u32, y: []i32, u: []u32) {
    var k = k_in
    var i = index
    var j = 0usize
    while true {
        var p = u[k + 1usize]
        var s = 0i32
        if i >= p {
            s = 0i32 - 1i32
            i -= p
        }
        var yj = i32(k)
        p = u[k]
        while p > i {
            k -= 1usize
            p = u[k]
        }
        i -= p
        yj -= i32(k)
        y[j] = (yj + s) ^ s
        urow_prev(u, k + 2usize, 0u32)
        j += 1usize
        if j >= n { break }
    }
}
fn decode_pulses(y: []i32, n: usize, k: usize, r: *Range, u: []u32) {
    let nc = ncwrs_urow(n, k, u)
    let index = range_decode_uint(r, nc)
    cwrsi(n, k, index, y, u)
}

fn exp_rotation1(x: []f32, length: usize, stride: usize, c: f32, s: f32) {
    var i = 0usize
    while i + stride < length {
        let x1 = x[i]
        let x2 = x[i + stride]
        x[i + stride] = c * x2 + s * x1
        x[i] = c * x1 - s * x2
        i += 1usize
    }
    if length < 2usize * stride + 1usize { ret }
    var j = i32(length) - 2i32 * i32(stride) - 1i32
    while j >= 0i32 {
        let at = usize(j)
        let x1 = x[at]
        let x2 = x[at + stride]
        x[at + stride] = c * x2 + s * x1
        x[at] = c * x1 - s * x2
        j -= 1i32
    }
}
fn exp_rotation(x: []f32, length_in: usize, direction: i32, stride: usize, k: usize, spread: u32) {
    if 2usize * k >= length_in || spread == SPREAD_NONE { ret }
    var factor = 15usize
    if spread == 2u32 { factor = 10usize }
    if spread == 3u32 { factor = 5usize }
    let gain = f32(length_in) / f32(length_in + factor * k)
    let theta = 0.5f32 * gain * gain
    let c = f32(math.cos[f64](1.5707963267948966 * f64(theta)))
    let s = f32(math.cos[f64](1.5707963267948966 * (1.0 - f64(theta))))
    var stride2 = 0usize
    if length_in >= 8usize * stride {
        stride2 = 1usize
        while (stride2 * stride2 + stride2) * stride + (stride >> 2u32) < length_in { stride2 += 1usize }
    }
    let length = length_in / stride
    var i = 0usize
    while i < stride {
        let sub = x[i * length..]
        if direction < 0i32 {
            if stride2 != 0usize { exp_rotation1(sub, length, stride2, s, c) }
            exp_rotation1(sub, length, 1usize, c, s)
        } else {
            exp_rotation1(sub, length, 1usize, c, 0.0f32 - s)
            if stride2 != 0usize { exp_rotation1(sub, length, stride2, s, 0.0f32 - c) }
        }
        i += 1usize
    }
}
fn extract_collapse_mask(y: []const i32, n: usize, blocks: usize) -> u32 {
    if blocks <= 1usize { ret 1u32 }
    let n0 = n / blocks
    var cm = 0u32
    var i = 0usize
    while i < blocks {
        var j = 0usize
        while j < n0 {
            if y[i * n0 + j] != 0i32 { cm |= 1u32 << u32(i) }
            j += 1usize
        }
        i += 1usize
    }
    ret cm
}
fn renormalise_vector(x: []f32, n: usize, gain: f32) {
    var e = 1.0e-15f64
    var i = 0usize
    while i < n {
        e += f64(x[i]) * f64(x[i])
        i += 1usize
    }
    let g = f32(f64(gain) / math.sqrt[f64](e))
    i = 0usize
    while i < n {
        x[i] = x[i] * g
        i += 1usize
    }
}
fn alg_unquant(x: []f32, n: usize, k: usize, spread: u32, blocks: usize, r: *Range, gain: f32, y: []i32, u: []u32) -> u32 {
    decode_pulses(y, n, k, r, u)
    var ryy = 0.0f64
    var i = 0usize
    while i < n {
        ryy += f64(y[i]) * f64(y[i])
        i += 1usize
    }
    let g = f32(f64(gain) / math.sqrt[f64](ryy))
    i = 0usize
    while i < n {
        x[i] = g * f32(y[i])
        i += 1usize
    }
    exp_rotation(x, n, 0i32 - 1i32, blocks, k, spread)
    ret extract_collapse_mask(y, n, blocks)
}

fn haar1(x: []f32, n0_in: usize, stride: usize) {
    let n0 = n0_in >> 1u32
    let root = 0.70710678f32
    var i = 0usize
    while i < stride {
        var j = 0usize
        while j < n0 {
            let a = stride * 2usize * j + i
            let b = stride * (2usize * j + 1usize) + i
            let t1 = root * x[a]
            let t2 = root * x[b]
            x[a] = t1 + t2
            x[b] = t1 - t2
            j += 1usize
        }
        i += 1usize
    }
}
fn deinterleave_hadamard(x: []f32, tmp: []f32, n0: usize, stride: usize, hadamard: bool) {
    let n = n0 * stride
    var i = 0usize
    while i < stride {
        var dest = i
        if hadamard { dest = usize(t_ordery()[stride - 2usize + i]) }
        var j = 0usize
        while j < n0 {
            tmp[dest * n0 + j] = x[j * stride + i]
            j += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < n {
        x[j] = tmp[j]
        j += 1usize
    }
}
fn interleave_hadamard(x: []f32, tmp: []f32, n0: usize, stride: usize, hadamard: bool) {
    let n = n0 * stride
    var i = 0usize
    while i < stride {
        var src = i
        if hadamard { src = usize(t_ordery()[stride - 2usize + i]) }
        var j = 0usize
        while j < n0 {
            tmp[j * stride + i] = x[src * n0 + j]
            j += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < n {
        x[j] = tmp[j]
        j += 1usize
    }
}
fn compute_qn(n: i32, b: i32, offset: i32, pulse_cap: i32, stereo: bool) -> i32 {
    var n2 = 2i32 * n - 1i32
    if stereo && n == 2i32 { n2 -= 1i32 }
    var qb = imin(b - pulse_cap - 32i32, cdiv(b + n2 * offset, n2))
    qb = imin(64i32, qb)
    if qb < 4i32 { ret 1i32 }
    let qn = exp2_8(usize(qb & 7i32)) >> u32(14i32 - (qb >> 3u32))
    ret ((qn + 1i32) >> 1u32) << 1u32
}
fn stereo_merge(x: []f32, y: []f32, mid: f32, n: usize) {
    var xp = 0.0f64
    var side = 0.0f64
    var j = 0usize
    while j < n {
        xp += f64(x[j]) * f64(y[j])
        side += f64(y[j]) * f64(y[j])
        j += 1usize
    }
    xp = xp * f64(mid)
    let m2 = f64(mid) * f64(mid)
    let el = m2 + side - 2.0 * xp
    let er = m2 + side + 2.0 * xp
    if er < 6.0e-4 || el < 6.0e-4 {
        j = 0usize
        while j < n {
            y[j] = x[j]
            j += 1usize
        }
        ret
    }
    let lgain = f32(1.0 / math.sqrt[f64](el))
    let rgain = f32(1.0 / math.sqrt[f64](er))
    j = 0usize
    while j < n {
        let l = mid * x[j]
        let rr = y[j]
        x[j] = lgain * (l - rr)
        y[j] = rgain * (l + rr)
        j += 1usize
    }
}

// ------------------------------------------------------------------ band decoding, section 4.3.4

type Ctx = struct { r: *Range, seed: u32, remaining: i32, spread: u32, intensity: usize, y: []i32, u: []u32, tmp: []f32 }

fn quant_band(ctx: *Ctx, band: usize, x: []f32, yv: []f32, n_in: usize, b_in: i32, blocks_in: i32, tf_change_in: i32, lowband_in: []f32, lowband_out: []f32, lm_in: i32, level: i32, gain: f32, lowband_scratch: []f32, fill_in: u32) -> u32 {
    var n = n_in
    var b = b_in
    var blocks = blocks_in
    var tf_change = tf_change_in
    var lm = lm_in
    var fill = fill_in
    var lowband = lowband_in
    var y = yv
    let n0 = n
    var nb = n
    var b0 = blocks
    var time_divide = 0i32
    var recombine = 0i32
    var inv = 0u32
    var mid = 0.0f32
    var side = 0.0f32
    let long_blocks = b0 == 1i32
    var cm = 0u32
    nb = nb / usize(blocks)
    var nb0 = nb
    let stereo = y.len > 0usize
    var split = stereo

    if n == 1usize {
        var chans = 1usize
        if stereo { chans = 2usize }
        var c = 0usize
        while c < chans {
            var sign = 0u32
            if ctx.remaining >= 8i32 {
                sign = range_decode_raw_bits(ctx.r, 1u32)
                ctx.remaining -= 8i32
                b -= 8i32
            }
            var v = 1.0f32
            if sign != 0u32 { v = 0.0f32 - 1.0f32 }
            if c == 0usize { x[0usize] = v } else { y[0usize] = v }
            c += 1usize
        }
        if lowband_out.len > 0usize { lowband_out[0usize] = x[0usize] }
        ret 1u32
    }

    if !stereo && level == 0i32 {
        if tf_change > 0i32 { recombine = tf_change }
        if lowband.len > 0usize && (recombine != 0i32 || ((nb & 1usize) == 0usize && tf_change < 0i32) || b0 > 1i32) {
            var j = 0usize
            while j < n {
                lowband_scratch[j] = lowband[j]
                j += 1usize
            }
            lowband = lowband_scratch
        }
        var k = 0i32
        while k < recombine {
            if lowband.len > 0usize { haar1(lowband, n >> u32(k), 1usize << u32(k)) }
            let bi = t_bit_interleave()
            fill = u32(bi[usize(fill & 15u32)]) | (u32(bi[usize(fill >> 4u32)]) << 2u32)
            k += 1i32
        }
        blocks >>= u32(recombine)
        nb <<= u32(recombine)
        while (nb & 1usize) == 0usize && tf_change < 0i32 {
            if lowband.len > 0usize { haar1(lowband, nb, usize(blocks)) }
            fill |= fill << u32(blocks)
            blocks <<= 1u32
            nb >>= 1u32
            time_divide += 1i32
            tf_change += 1i32
        }
        b0 = blocks
        nb0 = nb
        if b0 > 1i32 && lowband.len > 0usize {
            deinterleave_hadamard(lowband, ctx.tmp, nb >> u32(recombine), usize(b0) << u32(recombine), long_blocks)
        }
    }

    let base = cache_at(usize(lm + 1i32), band)
    if !stereo && lm != 0i32 - 1i32 && b > cache_bits(base + usize(cache_bits(base))) + 12i32 && n > 2usize {
        n >>= 1u32
        y = x[n..]
        split = true
        lm -= 1i32
        if blocks == 1i32 { fill = (fill & 1u32) | (fill << 1u32) }
        blocks = (blocks + 1i32) >> 1u32
    }

    if split {
        var itheta = 0i32
        let pulse_cap = logn(band) + lm * 8i32
        var offset = (pulse_cap >> 1u32) - QTHETA_OFFSET
        if stereo && n == 2usize { offset = (pulse_cap >> 1u32) - QTHETA_TWOPHASE }
        var qn = compute_qn(i32(n), b, offset, pulse_cap, stereo)
        if stereo && band >= ctx.intensity { qn = 1i32 }
        let tell = range_tell_frac(ctx.r)
        if qn != 1i32 {
            if stereo && n > 2usize {
                let p0 = 3i32
                let x0 = qn / 2i32
                let ft = u32(p0 * (x0 + 1i32) + x0)
                let fs = i32(range_decode(ctx.r, ft))
                var xv = 0i32
                if fs < (x0 + 1i32) * p0 { xv = fs / p0 } else { xv = x0 + 1i32 + (fs - (x0 + 1i32) * p0) }
                var lo = 0i32
                var hi = 0i32
                if xv <= x0 {
                    lo = p0 * xv
                    hi = p0 * (xv + 1i32)
                } else {
                    lo = (xv - 1i32 - x0) + (x0 + 1i32) * p0
                    hi = (xv - x0) + (x0 + 1i32) * p0
                }
                range_update(ctx.r, u32(lo), u32(hi), ft)
                itheta = xv
            } else if b0 > 1i32 || stereo {
                itheta = i32(range_decode_uint(ctx.r, u32(qn + 1i32)))
            } else {
                let half = qn >> 1u32
                let ft = u32((half + 1i32) * (half + 1i32))
                let fm = i32(range_decode(ctx.r, ft))
                var fs = 1i32
                var fl = 0i32
                if fm < (half * (half + 1i32)) >> 1u32 {
                    itheta = (i32(isqrt32(u32(8i32 * fm + 1i32))) - 1i32) >> 1u32
                    fs = itheta + 1i32
                    fl = (itheta * (itheta + 1i32)) >> 1u32
                } else {
                    itheta = (2i32 * (qn + 1i32) - i32(isqrt32(u32(8i32 * (i32(ft) - fm - 1i32) + 1i32)))) >> 1u32
                    fs = qn + 1i32 - itheta
                    fl = i32(ft) - (((qn + 1i32 - itheta) * (qn + 2i32 - itheta)) >> 1u32)
                }
                range_update(ctx.r, u32(fl), u32(fl + fs), ft)
            }
            itheta = cdiv(itheta * 16384i32, qn)
        } else if stereo {
            if b > 16i32 && ctx.remaining > 16i32 {
                inv = range_decode_bit_logp(ctx.r, 2u32)
            } else {
                inv = 0u32
            }
            itheta = 0i32
        }
        let qalloc = range_tell_frac(ctx.r) - tell
        b -= qalloc
        let orig_fill = fill
        var imid = 0i32
        var iside = 0i32
        var delta = 0i32
        if itheta == 0i32 {
            imid = 32767i32
            iside = 0i32
            fill &= (1u32 << u32(blocks)) - 1u32
            delta = 0i32 - 16384i32
        } else if itheta == 16384i32 {
            imid = 0i32
            iside = 32767i32
            fill &= ((1u32 << u32(blocks)) - 1u32) << u32(blocks)
            delta = 16384i32
        } else {
            imid = bitexact_cos(itheta)
            iside = bitexact_cos(16384i32 - itheta)
            delta = frac_mul16((i32(n) - 1i32) << 7u32, bitexact_log2tan(iside, imid))
        }
        mid = f32(imid) * 0.000030517578125f32
        side = f32(iside) * 0.000030517578125f32

        if n == 2usize && stereo {
            var mbits = b
            var sbits = 0i32
            if itheta != 0i32 && itheta != 16384i32 { sbits = 8i32 }
            mbits -= sbits
            let swap = itheta > 8192i32
            ctx.remaining -= qalloc + sbits
            var sign = 0u32
            if sbits != 0i32 { sign = range_decode_raw_bits(ctx.r, 1u32) }
            var sgn = 1.0f32
            if sign != 0u32 { sgn = 0.0f32 - 1.0f32 }
            var none: []f32 = x[0usize..0usize]
            if swap {
                cm = quant_band(ctx, band, y, none, n, mbits, blocks, tf_change, lowband, lowband_out, lm, level, gain, lowband_scratch, orig_fill)
                x[0usize] = (0.0f32 - sgn) * y[1usize]
                x[1usize] = sgn * y[0usize]
            } else {
                cm = quant_band(ctx, band, x, none, n, mbits, blocks, tf_change, lowband, lowband_out, lm, level, gain, lowband_scratch, orig_fill)
                y[0usize] = (0.0f32 - sgn) * x[1usize]
                y[1usize] = sgn * x[0usize]
            }
            x[0usize] = mid * x[0usize]
            x[1usize] = mid * x[1usize]
            y[0usize] = side * y[0usize]
            y[1usize] = side * y[1usize]
            var t = x[0usize]
            x[0usize] = t - y[0usize]
            y[0usize] = t + y[0usize]
            t = x[1usize]
            x[1usize] = t - y[1usize]
            y[1usize] = t + y[1usize]
        } else {
            var next_low2: []f32 = x[0usize..0usize]
            var next_out1: []f32 = x[0usize..0usize]
            var next_level = 0i32
            if b0 > 1i32 && !stereo && (itheta & 16383i32) != 0i32 {
                if itheta > 8192i32 {
                    delta -= delta >> u32(4i32 - lm)
                } else {
                    delta = imin(0i32, delta + ((i32(n) << 3u32) >> u32(5i32 - lm)))
                }
            }
            var mbits = imax(0i32, imin(b, cdiv(b - delta, 2i32)))
            var sbits = b - mbits
            ctx.remaining -= qalloc
            if lowband.len > 0usize && !stereo { next_low2 = lowband[n..] }
            if stereo { next_out1 = lowband_out } else { next_level = level + 1i32 }
            var rebalance = ctx.remaining
            var mgain = gain * mid
            var sgain = gain * side
            if stereo { mgain = 1.0f32 }
            var none: []f32 = x[0usize..0usize]
            var noscratch: []f32 = x[0usize..0usize]
            var shift = 0u32
            if !stereo { shift = u32(b0 >> 1u32) }
            if mbits >= sbits {
                cm = quant_band(ctx, band, x, none, n, mbits, blocks, tf_change, lowband, next_out1, lm, next_level, mgain, lowband_scratch, fill)
                rebalance = mbits - (rebalance - ctx.remaining)
                if rebalance > 24i32 && itheta != 0i32 { sbits += rebalance - 24i32 }
                cm |= quant_band(ctx, band, y, none, n, sbits, blocks, tf_change, next_low2, none, lm, next_level, sgain, noscratch, fill >> u32(blocks)) << shift
            } else {
                cm = quant_band(ctx, band, y, none, n, sbits, blocks, tf_change, next_low2, none, lm, next_level, sgain, noscratch, fill >> u32(blocks)) << shift
                rebalance = sbits - (rebalance - ctx.remaining)
                if rebalance > 24i32 && itheta != 16384i32 { mbits += rebalance - 24i32 }
                cm |= quant_band(ctx, band, x, none, n, mbits, blocks, tf_change, lowband, next_out1, lm, next_level, mgain, lowband_scratch, fill)
            }
        }
    } else {
        var q = bits2pulses(band, lm, b)
        var curr = pulses2bits(band, lm, q)
        ctx.remaining -= curr
        while ctx.remaining < 0i32 && q > 0i32 {
            ctx.remaining += curr
            q -= 1i32
            curr = pulses2bits(band, lm, q)
            ctx.remaining -= curr
        }
        if q != 0i32 {
            let k = usize(get_pulses(q))
            cm = alg_unquant(x, n, k, ctx.spread, usize(blocks), ctx.r, gain, ctx.y, ctx.u)
        } else {
            let cm_mask = (1u32 << u32(blocks)) - 1u32
            fill &= cm_mask
            if fill == 0u32 {
                var j = 0usize
                while j < n {
                    x[j] = 0.0f32
                    j += 1usize
                }
            } else {
                if lowband.len == 0usize {
                    var j = 0usize
                    while j < n {
                        ctx.seed = lcg_rand(ctx.seed)
                        var sv = i64(ctx.seed)
                        if sv >= 2147483648i64 { sv -= 4294967296i64 }
                        x[j] = f32(sv >> 20u32)
                        j += 1usize
                    }
                    cm = cm_mask
                } else {
                    var j = 0usize
                    while j < n {
                        ctx.seed = lcg_rand(ctx.seed)
                        var t = 0.00390625f32
                        if (ctx.seed & 32768u32) == 0u32 { t = 0.0f32 - 0.00390625f32 }
                        x[j] = lowband[j] + t
                        j += 1usize
                    }
                    cm = fill
                }
                renormalise_vector(x, n, gain)
            }
        }
    }

    if stereo {
        if n != 2usize { stereo_merge(x, y, mid, n) }
        if inv != 0u32 {
            var j = 0usize
            while j < n {
                y[j] = 0.0f32 - y[j]
                j += 1usize
            }
        }
    } else if level == 0i32 {
        if b0 > 1i32 { interleave_hadamard(x, ctx.tmp, nb >> u32(recombine), usize(b0) << u32(recombine), long_blocks) }
        nb = nb0
        blocks = b0
        var k = 0i32
        while k < time_divide {
            blocks >>= 1u32
            nb <<= 1u32
            cm |= cm >> u32(blocks)
            haar1(x, nb, usize(blocks))
            k += 1i32
        }
        k = 0i32
        while k < recombine {
            cm = u32(t_bit_deinterleave()[usize(cm & 15u32)])
            haar1(x, n0 >> u32(k), 1usize << u32(k))
            k += 1i32
        }
        blocks <<= u32(recombine)
        if lowband_out.len > 0usize {
            let scale = f32(math.sqrt[f64](f64(n0)))
            var j = 0usize
            while j < n0 {
                lowband_out[j] = scale * x[j]
                j += 1usize
            }
        }
        cm &= (1u32 << u32(blocks)) - 1u32
    }
    ret cm
}

// ------------------------------------------------------------------ allocation, section 4.3.3

type Alloc = struct { coded_bands: usize, balance: i32, intensity: usize, dual_stereo: bool }

fn init_caps(caps: []i32, lm: i32, c: usize) {
    let t = t_cache_caps()
    var i = 0usize
    while i < NBANDS {
        let n = (eband(i + 1usize) - eband(i)) << u32(lm)
        caps[i] = ((i32(t[NBANDS * (2usize * usize(lm) + c - 1usize) + i]) + 64i32) * i32(c) * i32(n)) >> 2u32
        i += 1usize
    }
}

fn interp_bits2pulses(d: *Decoder, r: *Range, start: usize, bend: usize, skip_start_in: usize, total_in: i32, skip_rsv: i32, intensity_rsv_in: i32, dual_rsv_in: i32, c: usize, lm: i32) -> Alloc {
    var total = total_in
    var intensity_rsv = intensity_rsv_in
    var dual_rsv = dual_rsv_in
    let alloc_floor = i32(c) * 8i32
    var stereo_shift = 0u32
    if c > 1usize { stereo_shift = 1u32 }
    let log_m = lm * 8i32
    let bits1 = d.bits1
    let bits2 = d.bits2
    let thresh = d.thresh
    let caps = d.caps
    let bits = d.alloc_b
    let ebits = d.fine
    let prio = d.prio
    var lo = 0i32
    var hi = 64i32
    var step = 0i32
    while step < 6i32 {
        let mid = (lo + hi) >> 1u32
        var psum = 0i32
        var done = false
        var j = bend
        while j > start {
            j -= 1usize
            let tmp = bits1[j] + ((mid * bits2[j]) >> 6u32)
            if tmp >= thresh[j] || done {
                done = true
                psum += imin(tmp, caps[j])
            } else if tmp >= alloc_floor {
                psum += alloc_floor
            }
        }
        if psum > total { hi = mid } else { lo = mid }
        step += 1i32
    }
    var psum = 0i32
    var done = false
    var j = bend
    while j > start {
        j -= 1usize
        var tmp = bits1[j] + ((lo * bits2[j]) >> 6u32)
        if tmp < thresh[j] && !done {
            if tmp >= alloc_floor { tmp = alloc_floor } else { tmp = 0i32 }
        } else {
            done = true
        }
        tmp = imin(tmp, caps[j])
        bits[j] = tmp
        psum += tmp
    }
    var coded_bands = bend
    while true {
        let k = coded_bands - 1usize
        if k <= skip_start_in {
            total += skip_rsv
            break
        }
        var left = total - psum
        let width_all = i32(eband(coded_bands) - eband(start))
        let percoeff = cdiv(left, width_all)
        left -= width_all * percoeff
        let rem = imax(left - i32(eband(k) - eband(start)), 0i32)
        let band_width = i32(eband(coded_bands) - eband(k))
        var band_bits = bits[k] + percoeff * band_width + rem
        if band_bits >= imax(thresh[k], alloc_floor + 8i32) {
            if range_decode_bit_logp(r, 1u32) != 0u32 { break }
            psum += 8i32
            band_bits -= 8i32
        }
        psum -= bits[k] + intensity_rsv
        if intensity_rsv > 0i32 { intensity_rsv = log2_frac(k - start) }
        psum += intensity_rsv
        if band_bits >= alloc_floor {
            psum += alloc_floor
            bits[k] = alloc_floor
        } else {
            bits[k] = 0i32
        }
        coded_bands -= 1usize
    }
    var intensity = 0usize
    if intensity_rsv > 0i32 {
        intensity = start + usize(range_decode_uint(r, u32(coded_bands + 1usize - start)))
    }
    if intensity <= start {
        total += dual_rsv
        dual_rsv = 0i32
    }
    var dual_stereo = false
    if dual_rsv > 0i32 { dual_stereo = range_decode_bit_logp(r, 1u32) != 0u32 }

    var left = total - psum
    let width_all = i32(eband(coded_bands) - eband(start))
    let percoeff = cdiv(left, width_all)
    left -= width_all * percoeff
    j = start
    while j < coded_bands {
        bits[j] += percoeff * i32(eband(j + 1usize) - eband(j))
        j += 1usize
    }
    j = start
    while j < coded_bands {
        let tmp = imin(left, i32(eband(j + 1usize) - eband(j)))
        bits[j] += tmp
        left -= tmp
        j += 1usize
    }
    var balance = 0i32
    j = start
    while j < coded_bands {
        let n0 = i32(eband(j + 1usize) - eband(j))
        let n = n0 << u32(lm)
        bits[j] += balance
        var excess = 0i32
        if n > 1i32 {
            excess = imax(bits[j] - caps[j], 0i32)
            bits[j] -= excess
            var den = i32(c) * n
            if c == 2usize && n > 2i32 && !dual_stereo && j < intensity { den += 1i32 }
            let nclogn = den * (logn(j) + log_m)
            var offset = (nclogn >> 1u32) - den * FINE_OFFSET
            if n == 2i32 { offset += (den << 3u32) >> 2u32 }
            if bits[j] + offset < (den * 2i32) << 3u32 {
                offset += nclogn >> 2u32
            } else if bits[j] + offset < (den * 3i32) << 3u32 {
                offset += nclogn >> 3u32
            }
            ebits[j] = imax(0i32, cdiv(bits[j] + offset + (den << 2u32), den << 3u32))
            if i32(c) * ebits[j] > (bits[j] >> 3u32) { ebits[j] = (bits[j] >> stereo_shift) >> 3u32 }
            ebits[j] = imin(ebits[j], MAX_FINE_BITS)
            prio[j] = 0i32
            if ebits[j] * (den << 3u32) >= bits[j] + offset { prio[j] = 1i32 }
            bits[j] -= (i32(c) * ebits[j]) << 3u32
        } else {
            excess = imax(0i32, bits[j] - (i32(c) << 3u32))
            bits[j] -= excess
            ebits[j] = 0i32
            prio[j] = 1i32
        }
        if excess > 0i32 {
            let extra_fine = imin(excess >> (stereo_shift + 3u32), MAX_FINE_BITS - ebits[j])
            ebits[j] += extra_fine
            let extra_bits = (extra_fine * i32(c)) << 3u32
            prio[j] = 0i32
            if extra_bits >= excess - balance { prio[j] = 1i32 }
            excess -= extra_bits
        }
        balance = excess
        j += 1usize
    }
    while j < bend {
        ebits[j] = (bits[j] >> stereo_shift) >> 3u32
        bits[j] = 0i32
        prio[j] = 0i32
        if ebits[j] < 1i32 { prio[j] = 1i32 }
        j += 1usize
    }
    ret Alloc { coded_bands: coded_bands, balance: balance, intensity: intensity, dual_stereo: dual_stereo }
}

fn compute_allocation(d: *Decoder, r: *Range, start: usize, bend: usize, total_in: i32, alloc_trim: i32, c: usize, lm: i32) -> Alloc {
    var total = imax(total_in, 0i32)
    var skip_start = start
    var skip_rsv = 0i32
    if total >= 8i32 { skip_rsv = 8i32 }
    total -= skip_rsv
    var intensity_rsv = 0i32
    var dual_rsv = 0i32
    if c == 2usize {
        intensity_rsv = log2_frac(bend - start)
        if intensity_rsv > total {
            intensity_rsv = 0i32
        } else {
            total -= intensity_rsv
            if total >= 8i32 { dual_rsv = 8i32 }
            total -= dual_rsv
        }
    }
    let thresh = d.thresh
    let trim_off = d.trim_off
    let offsets = d.offsets
    let caps = d.caps
    var j = start
    while j < bend {
        let width = i32(eband(j + 1usize) - eband(j))
        thresh[j] = imax(i32(c) << 3u32, ((3i32 * width) << u32(lm + 3i32)) >> 4u32)
        trim_off[j] = (i32(c) * width * (alloc_trim - 5i32 - lm) * i32(bend - j - 1usize) * (1i32 << u32(lm + 3i32))) >> 6u32
        if (width << u32(lm)) == 1i32 { trim_off[j] -= i32(c) << 3u32 }
        j += 1usize
    }
    var lo = 1i32
    var hi = i32(NBALLOC) - 1i32
    while lo <= hi {
        var done = false
        var psum = 0i32
        let mid = (lo + hi) >> 1u32
        var k = bend
        while k > start {
            k -= 1usize
            let width = i32(eband(k + 1usize) - eband(k))
            var bitsj = ((i32(c) * width * band_alloc(usize(mid), k)) << u32(lm)) >> 2u32
            if bitsj > 0i32 { bitsj = imax(0i32, bitsj + trim_off[k]) }
            bitsj += offsets[k]
            if bitsj >= thresh[k] || done {
                done = true
                psum += imin(bitsj, caps[k])
            } else if bitsj >= (i32(c) << 3u32) {
                psum += i32(c) << 3u32
            }
        }
        if psum > total { hi = mid - 1i32 } else { lo = mid + 1i32 }
    }
    hi = lo
    lo -= 1i32
    let bits1 = d.bits1
    let bits2 = d.bits2
    j = start
    while j < bend {
        let width = i32(eband(j + 1usize) - eband(j))
        var b1 = ((i32(c) * width * band_alloc(usize(lo), j)) << u32(lm)) >> 2u32
        var b2 = 0i32
        if hi >= i32(NBALLOC) {
            b2 = caps[j]
        } else {
            b2 = ((i32(c) * width * band_alloc(usize(hi), j)) << u32(lm)) >> 2u32
        }
        if b1 > 0i32 { b1 = imax(0i32, b1 + trim_off[j]) }
        if b2 > 0i32 { b2 = imax(0i32, b2 + trim_off[j]) }
        if lo > 0i32 { b1 += offsets[j] }
        b2 += offsets[j]
        if offsets[j] > 0i32 { skip_start = j }
        b2 = imax(0i32, b2 - b1)
        bits1[j] = b1
        bits2[j] = b2
        j += 1usize
    }
    ret interp_bits2pulses(d, r, start, bend, skip_start, total, skip_rsv, intensity_rsv, dual_rsv, c, lm)
}

// ------------------------------------------------------------------ energy, section 4.3.2

fn unquant_coarse_energy(d: *Decoder, r: *Range, start: usize, bend: usize, intra: u32, c: usize, lm: i32) {
    var coef = pred_coef(lm)
    var beta = beta_coef(lm)
    if intra != 0u32 {
        coef = 0.0f32
        beta = beta_intra()
    }
    let budget = i32(r.data.len) * 8i32
    var prev0 = 0.0f32
    var prev1 = 0.0f32
    let old = d.old_band_e
    var i = start
    while i < bend {
        var ch = 0usize
        while ch < c {
            let tell = range_tell(r)
            var qi = 0i32
            if budget - tell >= 15i32 {
                var pi = 2usize * i
                if i > 20usize { pi = 40usize }
                qi = laplace_decode(r, e_prob(lm, intra, pi) << 7u32, e_prob(lm, intra, pi + 1usize) << 6u32)
            } else if budget - tell >= 2i32 {
                let v = i32(range_decode_icdf(r, t_small_icdf(), 2u32))
                qi = (v >> 1u32) ^ (0i32 - (v & 1i32))
            } else if budget - tell >= 1i32 {
                qi = 0i32 - i32(range_decode_bit_logp(r, 1u32))
            } else {
                qi = 0i32 - 1i32
            }
            let q = f32(qi)
            let at = i + ch * NBANDS
            var oldv = old[at]
            if oldv < 0.0f32 - 9.0f32 { oldv = 0.0f32 - 9.0f32 }
            var prev = prev0
            if ch == 1usize { prev = prev1 }
            old[at] = coef * oldv + prev + q
            prev = prev + q - beta * q
            if ch == 1usize { prev1 = prev } else { prev0 = prev }
            ch += 1usize
        }
        i += 1usize
    }
}

fn unquant_fine_energy(d: *Decoder, r: *Range, start: usize, bend: usize, c: usize) {
    let old = d.old_band_e
    let fine = d.fine
    var i = start
    while i < bend {
        if fine[i] > 0i32 {
            var ch = 0usize
            while ch < c {
                let q2 = i32(range_decode_raw_bits(r, u32(fine[i])))
                let offset = (f32(q2) + 0.5f32) * f32(1i32 << u32(14i32 - fine[i])) * 0.00006103515625f32 - 0.5f32
                old[i + ch * NBANDS] += offset
                ch += 1usize
            }
        }
        i += 1usize
    }
}

fn unquant_energy_finalise(d: *Decoder, r: *Range, start: usize, bend: usize, bits_left_in: i32, c: usize) {
    var bits_left = bits_left_in
    let old = d.old_band_e
    let fine = d.fine
    let prio = d.prio
    var p = 0i32
    while p < 2i32 {
        var i = start
        while i < bend && bits_left >= i32(c) {
            if fine[i] < MAX_FINE_BITS && prio[i] == p {
                var ch = 0usize
                while ch < c {
                    let q2 = i32(range_decode_raw_bits(r, 1u32))
                    let offset = (f32(q2) - 0.5f32) * f32(1i32 << u32(14i32 - fine[i] - 1i32)) * 0.00006103515625f32
                    old[i + ch * NBANDS] += offset
                    bits_left -= 1i32
                    ch += 1usize
                }
            }
            i += 1usize
        }
        p += 1i32
    }
}

fn anti_collapse(d: *Decoder, xs: []f32, lm: i32, c: usize, size: usize, start: usize, bend: usize) {
    let masks = d.masks
    let pulses = d.alloc_b
    let old = d.old_band_e
    let log1 = d.old_log_e
    let log2 = d.old_log_e2
    var i = start
    while i < bend {
        let n0 = eband(i + 1usize) - eband(i)
        let depth = (1i32 + pulses[i]) / (i32(n0) << u32(lm))
        let thresh = 0.5f32 * f32(math.exp2[f64](0.0 - 0.125 * f64(depth)))
        let sqrt_1 = f32(1.0 / math.sqrt[f64](f64(n0 << u32(lm))))
        var ch = 0usize
        while ch < c {
            var p1 = log1[ch * NBANDS + i]
            var p2 = log2[ch * NBANDS + i]
            if c == 1usize {
                if log1[NBANDS + i] > p1 { p1 = log1[NBANDS + i] }
                if log2[NBANDS + i] > p2 { p2 = log2[NBANDS + i] }
            }
            var pm = p1
            if p2 < pm { pm = p2 }
            var ediff = old[ch * NBANDS + i] - pm
            if ediff < 0.0f32 { ediff = 0.0f32 }
            var rv = 2.0f32 * f32(math.exp2[f64](0.0 - f64(ediff)))
            if lm == 3i32 { rv = rv * 1.41421356f32 }
            if rv > thresh { rv = thresh }
            rv = rv * sqrt_1
            let off = ch * size + (eband(i) << u32(lm))
            let x = xs[off..]
            var renorm = false
            var k = 0usize
            while k < (1usize << u32(lm)) {
                if (u32(masks[i * c + ch]) & (1u32 << u32(k))) == 0u32 {
                    var j = 0usize
                    while j < n0 {
                        d.rng = lcg_rand(d.rng)
                        var v = 0.0f32 - rv
                        if (d.rng & 32768u32) != 0u32 { v = rv }
                        x[(j << u32(lm)) + k] = v
                        j += 1usize
                    }
                    renorm = true
                }
                k += 1usize
            }
            if renorm { renormalise_vector(x, n0 << u32(lm), 1.0f32) }
            ch += 1usize
        }
        i += 1usize
    }
}

// ------------------------------------------------------------------ inverse MDCT, section 4.3.7

// ponytail: the inverse MDCT is the direct O(N^2) DFT of clt_mdct_backward's
// N/4-point complex transform, with the twiddles tabulated once.  CELT's sizes
// are 60, 120, 240 and 480 points, none of them a power of two, so `e.math.fft`
// does not apply; a mixed-radix (2/3/4/5) FFT would make this O(N log N).
fn imdct_backward(d: *Decoder, spec: []const f32, stride: usize, out: []f32, n_mdct: usize, overlap: usize) {
    let n2 = n_mdct >> 1u32
    let n4 = n_mdct >> 2u32
    let tw = 480usize / n4
    let window = d.window
    let tcos = d.tw_cos
    let tsin = d.tw_sin
    let pcos = d.phi_cos
    let psin = d.phi_sin
    let zr = d.zr
    let zi = d.zi
    let gi = d.gi
    let f2 = d.f2
    var i = 0usize
    while i < n4 {
        let ang = 6.283185307179586 * (f64(i) + 0.125) / f64(n_mdct)
        pcos[i] = f32(math.cos[f64](ang))
        psin[i] = f32(math.sin[f64](ang))
        i += 1usize
    }
    var m = 0usize
    while m < n4 {
        let xp1 = spec[2usize * m * stride]
        let xp2 = spec[stride * (n2 - 1usize - 2usize * m)]
        let re = 0.0f32 - xp2
        let im = 0.0f32 - xp1
        zr[m] = re * pcos[m] - im * psin[m]
        zi[m] = re * psin[m] + im * pcos[m]
        m += 1usize
    }
    i = 0usize
    while i < n4 {
        var sr = 0.0f64
        var si = 0.0f64
        var k = 0usize
        m = 0usize
        while m < n4 {
            let cc = f64(tcos[k * tw])
            let ss = f64(tsin[k * tw])
            sr += f64(zr[m]) * cc - f64(zi[m]) * ss
            si += f64(zr[m]) * ss + f64(zi[m]) * cc
            k += i
            if k >= n4 { k -= n4 }
            m += 1usize
        }
        let cr = f64(pcos[i])
        let ci = f64(psin[i])
        f2[2usize * i] = f32(0.0 - (sr * cr - si * ci))
        gi[i] = f32(sr * ci + si * cr)
        i += 1usize
    }
    i = 0usize
    while i < n4 {
        f2[2usize * i + 1usize] = gi[n4 - 1usize - i]
        i += 1usize
    }
    let a = n4 - (overlap >> 1u32)
    i = 0usize
    while i < n4 {
        let x1 = f2[n4 - 1usize - i]
        if i < a {
            out[n2 - 1usize - i - a] = x1
        } else {
            let j = i - a
            out[j] -= window[j] * x1
            out[n2 - 1usize - i - a] += window[overlap - 1usize - j] * x1
        }
        i += 1usize
    }
    i = 0usize
    while i < n4 {
        let x2 = f2[n4 + i]
        if i < a {
            out[n2 + i - a] = x2
        } else {
            let j = i - a
            out[n_mdct - 1usize - 2usize * a - j] = window[j] * x2
            out[n2 + i - a] = window[overlap - 1usize - j] * x2
        }
        i += 1usize
    }
}

fn comb_filter(buf: []f32, at: usize, t0_in: i32, t1_in: i32, n: usize, g0: f32, g1: f32, tap0: usize, tap1: usize, window: []const f32, overlap: usize) {
    if g0 == 0.0f32 && g1 == 0.0f32 { ret }
    let t0 = usize(t0_in)
    let t1 = usize(t1_in)
    let g00 = g0 * comb_gain(tap0, 0usize)
    let g01 = g0 * comb_gain(tap0, 1usize)
    let g02 = g0 * comb_gain(tap0, 2usize)
    let g10 = g1 * comb_gain(tap1, 0usize)
    let g11 = g1 * comb_gain(tap1, 1usize)
    let g12 = g1 * comb_gain(tap1, 2usize)
    var i = 0usize
    while i < overlap && i < n {
        let f = window[i] * window[i]
        let w = 1.0f32 - f
        let p = at + i
        var acc = buf[p]
        acc += w * g00 * buf[p - t0]
        acc += w * g01 * buf[p - t0 - 1usize]
        acc += w * g01 * buf[p - t0 + 1usize]
        acc += w * g02 * buf[p - t0 - 2usize]
        acc += w * g02 * buf[p - t0 + 2usize]
        acc += f * g10 * buf[p - t1]
        acc += f * g11 * buf[p - t1 - 1usize]
        acc += f * g11 * buf[p - t1 + 1usize]
        acc += f * g12 * buf[p - t1 - 2usize]
        acc += f * g12 * buf[p - t1 + 2usize]
        buf[p] = acc
        i += 1usize
    }
    while i < n {
        let p = at + i
        var acc = buf[p]
        acc += g10 * buf[p - t1]
        acc += g11 * buf[p - t1 - 1usize]
        acc += g11 * buf[p - t1 + 1usize]
        acc += g12 * buf[p - t1 - 2usize]
        acc += g12 * buf[p - t1 + 2usize]
        buf[p] = acc
        i += 1usize
    }
}

// ------------------------------------------------------------------ all bands, section 4.3.4

fn quant_all_bands(d: *Decoder, r: *Range, start: usize, bend: usize, c: usize, short_blocks: i32, spread: u32, dual_stereo_in: bool, intensity: usize, total_bits: i32, balance_in: i32, lm: i32, coded_bands: usize) {
    let m = 1usize << u32(lm)
    var blocks = 1i32
    if short_blocks != 0i32 { blocks = short_blocks }
    let n_total = 960usize   // the X array always uses a 960-sample stride per channel
    let nlen = m * eband(NBANDS)
    let xs = d.xs
    let norm = d.norm
    let masks = d.masks
    let pulses = d.alloc_b
    var dual_stereo = dual_stereo_in
    var balance = balance_in
    var ctx = Ctx { r: r, seed: d.rng, remaining: 0i32, spread: spread, intensity: intensity, y: d.iy, u: d.uu, tmp: d.htmp }
    var lowband_offset = 0usize
    var update_lowband = true
    var x_cm = 0u32
    var y_cm = 0u32
    var i = start
    while i < bend {
        let xo = m * eband(i)
        let n = m * eband(i + 1usize) - xo
        let tell = range_tell_frac(r)
        if i != start { balance -= tell }
        ctx.remaining = total_bits - tell - 1i32
        var b = 0i32
        if i + 1usize <= coded_bands {
            let curr = cdiv(balance, imin(3i32, i32(coded_bands - i)))
            b = imax(0i32, imin(16383i32, imin(ctx.remaining + 1i32, pulses[i] + curr)))
        }
        if (xo >= n + m * eband(start) || i == start + 1usize) && (update_lowband || lowband_offset == 0usize) { lowband_offset = i }
        // special_hybrid_folding: the second coded band is wider than the first,
        // so duplicate enough of the first band's normalised data to fold from.
        // Copies nothing when the CELT layer starts at band 0.
        if i == start + 1usize {
            let base = m * eband(start)
            let n1 = m * (eband(start + 1usize) - eband(start))
            let n2 = m * (eband(start + 2usize) - eband(start + 1usize))
            var j = n1
            while j < n2 {
                norm[base + j] = norm[base + 2usize * n1 - n2 + j - n1]
                if dual_stereo { norm[nlen + base + j] = norm[nlen + base + 2usize * n1 - n2 + j - n1] }
                j += 1usize
            }
        }
        let tf_change = d.tf_res[i]
        var eff_low = 0usize
        var has_low = false
        if lowband_offset != 0usize && (spread != SPREAD_AGGRESSIVE || blocks > 1i32 || tf_change < 0i32) {
            eff_low = m * eband(start)
            if m * eband(lowband_offset) > n + eff_low { eff_low = m * eband(lowband_offset) - n }
            has_low = true
            var fold_start = lowband_offset
            while true {
                fold_start -= 1usize
                if m * eband(fold_start) <= eff_low { break }
            }
            var fold_end = lowband_offset - 1usize
            while true {
                fold_end += 1usize
                if fold_end >= i { break }
                if m * eband(fold_end) >= eff_low + n { break }
            }
            x_cm = 0u32
            y_cm = 0u32
            var fi = fold_start
            while true {
                x_cm |= u32(masks[fi * c + 0usize])
                y_cm |= u32(masks[fi * c + c - 1usize])
                fi += 1usize
                if fi >= fold_end { break }
            }
        } else {
            x_cm = (1u32 << u32(blocks)) - 1u32
            y_cm = x_cm
        }
        if dual_stereo && i == intensity {
            dual_stereo = false
            var j = m * eband(start)
            while j < m * eband(i) {
                norm[j] = 0.5f32 * (norm[j] + norm[nlen + j])
                j += 1usize
            }
        }
        var none: []f32 = xs[0usize..0usize]
        if dual_stereo {
            var low0: []f32 = none
            var low1: []f32 = none
            if has_low {
                low0 = norm[eff_low..nlen]
                low1 = norm[nlen + eff_low..]
            }
            x_cm = quant_band(&ctx, i, xs[xo..], none, n, b / 2i32, blocks, tf_change, low0, norm[xo..nlen], lm, 0i32, 1.0f32, d.lbscratch, x_cm)
            y_cm = quant_band(&ctx, i, xs[n_total + xo..], none, n, b / 2i32, blocks, tf_change, low1, norm[nlen + xo..], lm, 0i32, 1.0f32, d.lbscratch, y_cm)
        } else {
            var low0: []f32 = none
            if has_low { low0 = norm[eff_low..nlen] }
            var yslice: []f32 = none
            if c == 2usize { yslice = xs[n_total + xo..] }
            x_cm = quant_band(&ctx, i, xs[xo..], yslice, n, b, blocks, tf_change, low0, norm[xo..nlen], lm, 0i32, 1.0f32, d.lbscratch, x_cm | y_cm)
            y_cm = x_cm
        }
        masks[i * c + 0usize] = u8(x_cm & 255u32)
        masks[i * c + c - 1usize] = u8(y_cm & 255u32)
        balance += pulses[i] + tell
        update_lowband = b > (i32(n) << 3u32)
        i += 1usize
    }
    d.rng = ctx.seed
}

// ------------------------------------------------------------------ decoder

type Decoder = struct { sdec: []Silk, rsmp: []Resamp, pcm16: []i16, ch16: []i16, rs16: []i16, silk_fs: i64, silk_ch: i64, silk_rate: i64, lp_mode: i64, channels: usize, band_start: usize, band_end: usize, rng: u32, pf_period: i32, pf_period_old: i32, pf_gain: f32, pf_gain_old: f32, pf_tapset: usize, pf_tapset_old: usize, dmem: []f32, old_band_e: []f32, old_log_e: []f32, old_log_e2: []f32, bg_log_e: []f32, preemph_mem: []f32, xs: []f32, freq: []f32, norm: []f32, lbscratch: []f32, xbuf: []f32, band_e: []f32, window: []f32, tw_cos: []f32, tw_sin: []f32, phi_cos: []f32, phi_sin: []f32, gi: []f32, f2: []f32, zr: []f32, zi: []f32, htmp: []f32, caps: []i32, offsets: []i32, tf_res: []i32, bits1: []i32, bits2: []i32, thresh: []i32, trim_off: []i32, alloc_b: []i32, fine: []i32, prio: []i32, iy: []i32, uu: []u32, masks: []u8 }

fn fslice(a: *mem.Arena, n: usize) -> ([]f32, err) {
    let (s, e) = mem.alloc[f32](a, n)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < n {
        s[i] = 0.0f32
        i += 1usize
    }
    ret (s, ok)
}
fn islice(a: *mem.Arena, n: usize) -> ([]i32, err) {
    let (s, e) = mem.alloc[i32](a, n)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < n {
        s[i] = 0i32
        i += 1usize
    }
    ret (s, ok)
}

fn decoder(a: *mem.Arena, channels: usize) -> (Decoder, err) {
    if channels < 1usize || channels > 2usize { ret (zero, Unsupported) }
    var d: Decoder = zero
    let (dmem, e1) = fslice(a, channels * (DECODE_BUFFER + OVERLAP))
    if e1 != ok { ret (zero, e1) }
    let (obe, e2) = fslice(a, 2usize * NBANDS)
    if e2 != ok { ret (zero, e2) }
    let (ole, e3) = fslice(a, 2usize * NBANDS)
    if e3 != ok { ret (zero, e3) }
    let (ol2, e4) = fslice(a, 2usize * NBANDS)
    if e4 != ok { ret (zero, e4) }
    let (bge, e5) = fslice(a, 2usize * NBANDS)
    if e5 != ok { ret (zero, e5) }
    let (pre, e6) = fslice(a, 2usize)
    if e6 != ok { ret (zero, e6) }
    let (xs, e7) = fslice(a, 2usize * 960usize)
    if e7 != ok { ret (zero, e7) }
    let (freq, e8) = fslice(a, 2usize * 960usize)
    if e8 != ok { ret (zero, e8) }
    let (norm, e9) = fslice(a, 2usize * 800usize)
    if e9 != ok { ret (zero, e9) }
    let (lbs, e10) = fslice(a, 256usize)
    if e10 != ok { ret (zero, e10) }
    let (xbuf, e11) = fslice(a, 1200usize)
    if e11 != ok { ret (zero, e11) }
    let (be, e12) = fslice(a, 2usize * NBANDS)
    if e12 != ok { ret (zero, e12) }
    let (win, e13) = fslice(a, OVERLAP)
    if e13 != ok { ret (zero, e13) }
    let (tc, e14) = fslice(a, 480usize)
    if e14 != ok { ret (zero, e14) }
    let (ts, e15) = fslice(a, 480usize)
    if e15 != ok { ret (zero, e15) }
    let (pc, e16) = fslice(a, 480usize)
    if e16 != ok { ret (zero, e16) }
    let (ps, e17) = fslice(a, 480usize)
    if e17 != ok { ret (zero, e17) }
    let (gi, e18) = fslice(a, 480usize)
    if e18 != ok { ret (zero, e18) }
    let (f2, e19) = fslice(a, 960usize)
    if e19 != ok { ret (zero, e19) }
    let (zr, e20) = fslice(a, 480usize)
    if e20 != ok { ret (zero, e20) }
    let (zi, e21) = fslice(a, 480usize)
    if e21 != ok { ret (zero, e21) }
    let (ht, e22) = fslice(a, 256usize)
    if e22 != ok { ret (zero, e22) }
    let (caps, q1) = islice(a, NBANDS)
    if q1 != ok { ret (zero, q1) }
    let (offs, q2) = islice(a, NBANDS)
    if q2 != ok { ret (zero, q2) }
    let (tfr, q3) = islice(a, NBANDS)
    if q3 != ok { ret (zero, q3) }
    let (b1, q4) = islice(a, NBANDS)
    if q4 != ok { ret (zero, q4) }
    let (b2, q5) = islice(a, NBANDS)
    if q5 != ok { ret (zero, q5) }
    let (th, q6) = islice(a, NBANDS)
    if q6 != ok { ret (zero, q6) }
    let (tro, q7) = islice(a, NBANDS)
    if q7 != ok { ret (zero, q7) }
    let (ab, q8) = islice(a, NBANDS)
    if q8 != ok { ret (zero, q8) }
    let (fq, q9) = islice(a, NBANDS)
    if q9 != ok { ret (zero, q9) }
    let (pr, q10) = islice(a, NBANDS)
    if q10 != ok { ret (zero, q10) }
    let (iy, q11) = islice(a, 256usize)
    if q11 != ok { ret (zero, q11) }
    let (uu, q12) = mem.alloc[u32](a, 320usize)
    if q12 != ok { ret (zero, q12) }
    let (masks, q13) = mem.alloc[u8](a, 2usize * NBANDS)
    if q13 != ok { ret (zero, q13) }
    let (sdec, u1) = mem.alloc[Silk](a, 1usize)
    if u1 != ok { ret (zero, u1) }
    let blank: Silk = zero
    sdec[0usize] = blank
    let (rsmp, u2) = mem.alloc[Resamp](a, 2usize)
    if u2 != ok { ret (zero, u2) }
    let (pcm16, u3) = mem.alloc[i16](a, 1920usize)
    if u3 != ok { ret (zero, u3) }
    let (ch16, u4) = mem.alloc[i16](a, 320usize)
    if u4 != ok { ret (zero, u4) }
    let (rs16, u5) = mem.alloc[i16](a, 960usize)
    if u5 != ok { ret (zero, u5) }
    var i = 0usize
    while i < OVERLAP {
        let inner = math.sin[f64](1.5707963267948966 * (f64(i) + 0.5) / 120.0)
        win[i] = f32(math.sin[f64](1.5707963267948966 * inner * inner))
        i += 1usize
    }
    i = 0usize
    while i < 480usize {
        let ang = 6.283185307179586 * f64(i) / 480.0
        tc[i] = f32(math.cos[f64](ang))
        ts[i] = f32(math.sin[f64](ang))
        i += 1usize
    }
    i = 0usize
    while i < 2usize * NBANDS {
        ole[i] = 0.0f32 - 28.0f32
        ol2[i] = 0.0f32 - 28.0f32
        i += 1usize
    }
    d = Decoder { sdec: sdec, rsmp: rsmp, pcm16: pcm16, ch16: ch16, rs16: rs16, silk_fs: 0i64, silk_ch: 0i64, silk_rate: 0i64, lp_mode: 0i64, channels: channels, band_start: 0usize, band_end: NBANDS, rng: 0u32, pf_period: 0i32, pf_period_old: 0i32, pf_gain: 0.0f32, pf_gain_old: 0.0f32, pf_tapset: 0usize, pf_tapset_old: 0usize, dmem: dmem, old_band_e: obe, old_log_e: ole, old_log_e2: ol2, bg_log_e: bge, preemph_mem: pre, xs: xs, freq: freq, norm: norm, lbscratch: lbs, xbuf: xbuf, band_e: be, window: win, tw_cos: tc, tw_sin: ts, phi_cos: pc, phi_sin: ps, gi: gi, f2: f2, zr: zr, zi: zi, htmp: ht, caps: caps, offsets: offs, tf_res: tfr, bits1: b1, bits2: b2, thresh: th, trim_off: tro, alloc_b: ab, fine: fq, prio: pr, iy: iy, uu: uu, masks: masks }
    ret (d, ok)
}

fn band_end_for(bw: Bandwidth) -> usize {
    if bw == .Narrow { ret 13usize }
    if bw == .Medium { ret 17usize }
    if bw == .Wide { ret 17usize }
    if bw == .SuperWide { ret 19usize }
    ret 21usize
}

fn decode_frame(d: *Decoder, data: []const u8, out: []f32, lm: i32, c: usize) -> err {
    var r = range_init(data)
    ret celt_decode_frame(d, &r, out, lm, c)
}

// The CELT layer over a range decoder the caller already owns, so a hybrid
// packet can decode its LP layer from the same stream first and then start the
// CELT layer at `d.band_start` (band 17 for hybrid, 0 for CELT-only).
fn celt_decode_frame(d: *Decoder, r: *Range, out: []f32, lm: i32, c: usize) -> err {
    let cc = d.channels
    let m = 1usize << u32(lm)
    let n = m * SHORT_SIZE
    let start = d.band_start
    let bend = d.band_end
    let length = r.data.len
    let xs = d.xs
    let freq = d.freq
    let old = d.old_band_e
    var i = 0usize
    while i < 2usize * 960usize {
        xs[i] = 0.0f32
        i += 1usize
    }
    if c == 1usize {
        i = 0usize
        while i < NBANDS {
            if old[NBANDS + i] > old[i] { old[i] = old[NBANDS + i] }
            i += 1usize
        }
    }
    var total_bits = i32(length) * 8i32
    var tell = range_tell(r)
    var silence = false
    if tell >= total_bits {
        silence = true
    } else if tell == 1i32 {
        silence = range_decode_bit_logp(r, 15u32) != 0u32
    }
    if silence {
        tell = i32(length) * 8i32
        r.total_bits += tell - range_tell(r)
    }
    var pf_gain = 0.0f32
    var pf_pitch = 0i32
    var pf_tapset = 0usize
    if start == 0usize && tell + 16i32 <= total_bits {
        if range_decode_bit_logp(r, 1u32) != 0u32 {
            let octave = range_decode_uint(r, 6u32)
            pf_pitch = i32(16u32 << octave) + i32(range_decode_raw_bits(r, 4u32 + octave)) - 1i32
            let qg = i32(range_decode_raw_bits(r, 3u32))
            if range_tell(r) + 2i32 <= total_bits { pf_tapset = usize(range_decode_icdf(r, t_tapset_icdf(), 2u32)) }
            pf_gain = 0.09375f32 * f32(qg + 1i32)
        }
        tell = range_tell(r)
    }
    var is_transient = false
    if lm > 0i32 && tell + 3i32 <= total_bits {
        is_transient = range_decode_bit_logp(r, 3u32) != 0u32
        tell = range_tell(r)
    }
    var short_blocks = 0i32
    if is_transient { short_blocks = i32(m) }
    var intra = 0u32
    if tell + 3i32 <= total_bits { intra = range_decode_bit_logp(r, 3u32) }
    unquant_coarse_energy(d, r, start, bend, intra, c, lm)

    // tf_change and tf_select, section 4.3.1
    let tf_res = d.tf_res
    var budget = i32(length) * 8i32
    tell = range_tell(r)
    var logp = 4i32
    if is_transient { logp = 2i32 }
    var tf_rsv = 0i32
    if lm > 0i32 && tell + logp + 1i32 <= budget { tf_rsv = 1i32 }
    budget -= tf_rsv
    var tf_changed = 0i32
    var curr = 0i32
    i = start
    while i < bend {
        if tell + logp <= budget {
            curr ^= i32(range_decode_bit_logp(r, u32(logp)))
            tell = range_tell(r)
            tf_changed |= curr
        }
        tf_res[i] = curr
        logp = 5i32
        if is_transient { logp = 4i32 }
        i += 1usize
    }
    var tf_select = 0i32
    var trans = 0i32
    if is_transient { trans = 1i32 }
    if tf_rsv != 0i32 && tf_select_at(lm, usize(4i32 * trans + tf_changed)) != tf_select_at(lm, usize(4i32 * trans + 2i32 + tf_changed)) {
        tf_select = i32(range_decode_bit_logp(r, 1u32))
    }
    i = start
    while i < bend {
        tf_res[i] = tf_select_at(lm, usize(4i32 * trans + 2i32 * tf_select + tf_res[i]))
        i += 1usize
    }

    tell = range_tell(r)
    var spread = SPREAD_NORMAL
    if tell + 4i32 <= total_bits { spread = range_decode_icdf(r, t_spread_icdf(), 5u32) }

    init_caps(d.caps, lm, c)
    let offsets = d.offsets
    i = 0usize
    while i < NBANDS {
        offsets[i] = 0i32
        i += 1usize
    }
    var dynalloc_logp = 6i32
    total_bits <<= 3u32
    var tellf = range_tell_frac(r)
    i = start
    while i < bend {
        let width = i32(c) * i32((eband(i + 1usize) - eband(i)) << u32(lm))
        var quanta = imin(width << 3u32, imax(48i32, width))
        var loop_logp = dynalloc_logp
        var boost = 0i32
        while tellf + (loop_logp << 3u32) < total_bits && boost < d.caps[i] {
            let flag = range_decode_bit_logp(r, u32(loop_logp))
            tellf = range_tell_frac(r)
            if flag == 0u32 { break }
            boost += quanta
            total_bits -= quanta
            loop_logp = 1i32
        }
        offsets[i] = boost
        if boost > 0i32 { dynalloc_logp = imax(2i32, dynalloc_logp - 1i32) }
        i += 1usize
    }
    var alloc_trim = 5i32
    if tellf + 48i32 <= total_bits { alloc_trim = i32(range_decode_icdf(r, t_trim_icdf(), 7u32)) }
    var abits = ((i32(length) * 8i32) << 3u32) - range_tell_frac(r) - 1i32
    var anti_rsv = 0i32
    if is_transient && lm >= 2i32 && abits >= ((lm + 2i32) << 3u32) { anti_rsv = 8i32 }
    abits -= anti_rsv
    let alloc = compute_allocation(d, r, start, bend, abits, alloc_trim, c, lm)

    unquant_fine_energy(d, r, start, bend, c)

    let masks = d.masks
    i = 0usize
    while i < 2usize * NBANDS {
        masks[i] = 0u8
        i += 1usize
    }
    quant_all_bands(d, r, start, bend, c, short_blocks, spread, alloc.dual_stereo, alloc.intensity, (i32(length) * 64i32) - anti_rsv, alloc.balance, lm, alloc.coded_bands)

    var anti_on = 0u32
    if anti_rsv > 0i32 { anti_on = range_decode_raw_bits(r, 1u32) }
    unquant_energy_finalise(d, r, start, bend, i32(length) * 8i32 - range_tell(r), c)
    if anti_on != 0u32 { anti_collapse(d, xs, lm, c, 960usize, start, bend) }

    let band_e = d.band_e
    var ch = 0usize
    while ch < c {
        i = 0usize
        while i < NBANDS {
            var v = 0.0f32
            if i >= start && i < bend { v = f32(math.exp2[f64](f64(old[i + ch * NBANDS] + emeans(i)))) }
            band_e[i + ch * NBANDS] = v
            i += 1usize
        }
        ch += 1usize
    }
    if silence {
        i = 0usize
        while i < c * NBANDS {
            band_e[i] = 0.0f32
            old[i] = 0.0f32 - 28.0f32
            i += 1usize
        }
    }
    // denormalise
    ch = 0usize
    while ch < c {
        i = 0usize
        while i < n {
            freq[ch * 960usize + i] = 0.0f32
            i += 1usize
        }
        var bi = 0usize
        while bi < bend {
            let g = band_e[bi + ch * NBANDS]
            var j = m * eband(bi)
            while j < m * eband(bi + 1usize) {
                freq[ch * 960usize + j] = xs[ch * 960usize + j] * g
                j += 1usize
            }
            bi += 1usize
        }
        ch += 1usize
    }
    if cc == 2usize && c == 1usize {
        i = 0usize
        while i < n {
            freq[960usize + i] = freq[i]
            i += 1usize
        }
    }
    if cc == 1usize && c == 2usize {
        i = 0usize
        while i < n {
            freq[i] = 0.5f32 * (freq[i] + freq[960usize + i])
            i += 1usize
        }
    }
    // shift the history, then the inverse MDCT with overlap-add
    let dmem = d.dmem
    let stride_mem = DECODE_BUFFER + OVERLAP
    ch = 0usize
    while ch < cc {
        let base = ch * stride_mem
        i = 0usize
        while i < DECODE_BUFFER - n {
            dmem[base + i] = dmem[base + i + n]
            i += 1usize
        }
        ch += 1usize
    }
    let out_at = DECODE_BUFFER - n
    let xbuf = d.xbuf
    ch = 0usize
    while ch < cc {
        let base = ch * stride_mem
        i = 0usize
        while i < n + OVERLAP {
            xbuf[i] = 0.0f32
            i += 1usize
        }
        var n2 = n
        var nb = 1usize
        var shift = usize(MAXLM - lm)
        if short_blocks != 0i32 {
            n2 = SHORT_SIZE
            nb = usize(short_blocks)
            shift = usize(MAXLM)
        }
        let n_mdct = 1920usize >> u32(shift)
        var b = 0usize
        while b < nb {
            imdct_backward(d, freq[ch * 960usize + b..], nb, xbuf[n2 * b..], n_mdct, OVERLAP)
            b += 1usize
        }
        i = 0usize
        while i < OVERLAP {
            dmem[base + out_at + i] = xbuf[i] + dmem[base + DECODE_BUFFER + i]
            i += 1usize
        }
        while i < n {
            dmem[base + out_at + i] = xbuf[i]
            i += 1usize
        }
        i = 0usize
        while i < OVERLAP {
            dmem[base + DECODE_BUFFER + i] = xbuf[n + i]
            i += 1usize
        }
        ch += 1usize
    }
    // comb post-filter
    if d.pf_period < COMB_MIN_PERIOD { d.pf_period = COMB_MIN_PERIOD }
    if d.pf_period_old < COMB_MIN_PERIOD { d.pf_period_old = COMB_MIN_PERIOD }
    ch = 0usize
    while ch < cc {
        let base = ch * stride_mem
        comb_filter(dmem[base..], out_at, d.pf_period_old, d.pf_period, SHORT_SIZE, d.pf_gain_old, d.pf_gain, d.pf_tapset_old, d.pf_tapset, d.window, OVERLAP)
        if lm != 0i32 {
            comb_filter(dmem[base..], out_at + SHORT_SIZE, d.pf_period, pf_pitch, n - SHORT_SIZE, d.pf_gain, pf_gain, d.pf_tapset, pf_tapset, d.window, OVERLAP)
        }
        ch += 1usize
    }
    d.pf_period_old = d.pf_period
    d.pf_gain_old = d.pf_gain
    d.pf_tapset_old = d.pf_tapset
    d.pf_period = pf_pitch
    d.pf_gain = pf_gain
    d.pf_tapset = pf_tapset
    if lm != 0i32 {
        d.pf_period_old = d.pf_period
        d.pf_gain_old = d.pf_gain
        d.pf_tapset_old = d.pf_tapset
    }
    if c == 1usize {
        i = 0usize
        while i < NBANDS {
            old[NBANDS + i] = old[i]
            i += 1usize
        }
    }
    let ole = d.old_log_e
    let ol2 = d.old_log_e2
    let bge = d.bg_log_e
    if !is_transient {
        i = 0usize
        while i < 2usize * NBANDS {
            ol2[i] = ole[i]
            i += 1usize
        }
        i = 0usize
        while i < 2usize * NBANDS {
            ole[i] = old[i]
            i += 1usize
        }
        i = 0usize
        while i < 2usize * NBANDS {
            var v = bge[i] + f32(m) * 0.001f32
            if old[i] < v { v = old[i] }
            bge[i] = v
            i += 1usize
        }
    } else {
        i = 0usize
        while i < 2usize * NBANDS {
            if old[i] < ole[i] { ole[i] = old[i] }
            i += 1usize
        }
    }
    ch = 0usize
    while ch < 2usize {
        i = 0usize
        while i < start {
            old[ch * NBANDS + i] = 0.0f32
            ole[ch * NBANDS + i] = 0.0f32 - 28.0f32
            ol2[ch * NBANDS + i] = 0.0f32 - 28.0f32
            i += 1usize
        }
        i = bend
        while i < NBANDS {
            old[ch * NBANDS + i] = 0.0f32
            ole[ch * NBANDS + i] = 0.0f32 - 28.0f32
            ol2[ch * NBANDS + i] = 0.0f32 - 28.0f32
            i += 1usize
        }
        ch += 1usize
    }
    d.rng = r.rng
    // de-emphasis and the interleaved answer
    ch = 0usize
    while ch < cc {
        let base = ch * stride_mem
        var memd = d.preemph_mem[ch]
        i = 0usize
        while i < n {
            let tmp = dmem[base + out_at + i] + memd
            memd = 0.85000610f32 * tmp
            out[i * cc + ch] = tmp * 0.000030517578125f32
            i += 1usize
        }
        d.preemph_mem[ch] = memd
        ch += 1usize
    }
    ret ok
}

// decode answers one whole packet as interleaved f32, samples per channel.
// CELT-only packets need 48 kHz (the CELT layer has no decimator); SILK-only
// packets answer at 8, 12, 16, 24 or 48 kHz; hybrid packets need 48 kHz.
fn decode(d: *Decoder, packet: []const u8, rate: u32, out: []f32) -> (usize, err) {
    if packet.len < 1usize { ret (0usize, Malformed) }
    if rate != 8000u32 && rate != 12000u32 && rate != 16000u32 && rate != 24000u32 && rate != 48000u32 {
        ret (0usize, Unsupported)
    }
    let toc = packet[0usize]
    var frames: [48]Frame = zero
    let (count, parse_error) = packet_parse(packet, frames[..])
    if parse_error != ok { ret (0usize, parse_error) }
    let us = packet_frame_size_us(toc)
    let per = usize(us) * usize(rate) / 1000000usize
    if out.len < count * per * d.channels { ret (0usize, TooSmall) }
    if packet_mode(toc) != .Celt {
        let (got, lp_error) = decode_lp(d, frames[..], count, toc, rate, out)
        ret (got, lp_error)
    }
    if rate != 48000u32 { ret (0usize, Unsupported) }
    var lm = 0i32
    if us == 5000u32 { lm = 1i32 }
    if us == 10000u32 { lm = 2i32 }
    if us == 20000u32 { lm = 3i32 }
    if us != 2500u32 && us != 5000u32 && us != 10000u32 && us != 20000u32 { ret (0usize, Unsupported) }
    let c = usize(packet_channels(toc))
    d.band_start = 0usize
    d.band_end = band_end_for(packet_bandwidth(toc))
    let n = SHORT_SIZE << u32(lm)
    var i = 0usize
    while i < count {
        let e = decode_frame(d, frames[i].data, out[i * n * d.channels..], lm, c)
        if e != ok { ret (i * n, e) }
        i += 1usize
    }
    d.lp_mode = 3i64
    ret (count * n, ok)
}

// The SILK-only and hybrid paths.  SILK-only zeroes the answer and writes the
// resampled LP layer into it; a hybrid frame decodes the LP layer at 16 kHz from
// the packet's own range decoder, reads the one redundancy flag `opus_decode`
// reads next, runs the CELT layer from band 17 on that same range decoder, and
// adds the SILK part -- resampled to 48 kHz and delayed by the reference's
// decoder delay -- to what CELT wrote, sample for sample.
//
// ponytail: section 4.5's packet loss concealment, redundancy frames and mode
// transitions are not here.  A hybrid frame that signals redundancy answers
// `Unsupported`; a mid-stream mode change re-initialises the LP state instead of
// cross-fading, so the first frame after a switch is not bit-exact.
fn decode_lp(d: *Decoder, frames: []Frame, count: usize, toc: u8, rate: u32, out: []f32) -> (usize, err) {
    let mode = packet_mode(toc)
    let bw = packet_bandwidth(toc)
    if mode == .Hybrid && rate != 48000u32 { ret (0usize, Unsupported) }
    var fs_khz = 16i64
    if mode == .Silk {
        if bw == .Narrow { fs_khz = 8i64 }
        if bw == .Medium { fs_khz = 12i64 }
    }
    let nch = usize(packet_channels(toc))
    let cc = d.channels
    let us = packet_frame_size_us(toc)
    let ms = i64(us) / 1000i64
    var sf_ms = 20i64
    if ms == 10i64 { sf_ms = 10i64 }
    let nsilk = usize(ms / sf_ms)
    let sflen = usize(fs_khz * sf_ms)
    let per = usize(us) * usize(rate) / 1000000usize
    let sfout = per / nsilk
    let sd = &d.sdec[0usize]
    if d.silk_fs != fs_khz || d.silk_ch != i64(nch) || d.silk_rate != i64(rate) || d.lp_mode == 3i64 {
        let ie = silk_init(sd, fs_khz, i64(nch))
        if ie != ok { ret (0usize, ie) }
        let e0 = resamp_init(&d.rsmp[0usize], fs_khz * 1000i64, i64(rate))
        if e0 != ok { ret (0usize, e0) }
        let e1 = resamp_init(&d.rsmp[1usize], fs_khz * 1000i64, i64(rate))
        if e1 != ok { ret (0usize, e1) }
        d.silk_fs = fs_khz
        d.silk_ch = i64(nch)
        d.silk_rate = i64(rate)
    }
    d.lp_mode = 1i64
    if mode == .Hybrid { d.lp_mode = 2i64 }
    var lm = 3i32
    if ms == 10i64 { lm = 2i32 }
    var base = 0usize
    var fi = 0usize
    while fi < count {
        var r = range_init(frames[fi].data)
        let (got, se) = silk_decode(sd, &r, ms, d.pcm16)
        if se != ok { ret (base, se) }
        if got != nsilk * sflen { ret (base, Malformed) }
        if mode == .Hybrid {
            if range_tell(&r) + 37i32 <= i32(frames[fi].data.len) * 8i32 {
                if range_decode_bit_logp(&r, 12u32) != 0u32 { ret (base, Unsupported) }
            }
            d.band_start = 17usize
            d.band_end = band_end_for(bw)
            let ce = celt_decode_frame(d, &r, out[base * cc..], lm, nch)
            d.band_start = 0usize
            if ce != ok { ret (base, ce) }
        } else {
            var z = 0usize
            while z < per * cc {
                out[base * cc + z] = 0.0f32
                z = z + 1usize
            }
        }
        var f = 0usize
        while f < nsilk {
            var ch = 0usize
            while ch < nch && ch < cc {
                var j = 0usize
                while j < sflen {
                    d.ch16[j] = d.pcm16[(f * sflen + j) * nch + ch]
                    j = j + 1usize
                }
                let (no, pe) = resamp_process(&d.rsmp[ch], d.ch16[0usize..sflen], d.rs16)
                if pe != ok { ret (base, pe) }
                j = 0usize
                while j < no {
                    let v = f32(d.rs16[j]) * 0.000030517578125f32
                    let k = (base + f * sfout + j) * cc + ch
                    out[k] = out[k] + v
                    if nch == 1usize && cc == 2usize { out[k + 1usize] = out[k + 1usize] + v }
                    j = j + 1usize
                }
                ch = ch + 1usize
            }
            f = f + 1usize
        }
        base = base + per
        fi = fi + 1usize
    }
    ret (base, ok)
}

// ---------------------------------------------------------------------------
// The SILK layer (RFC 6716 section 4.2). Integer arithmetic throughout, as the
// specification defines it, so a SILK frame decodes bit-exactly.
// ---------------------------------------------------------------------------
type SilkChan = struct { out_buf: [480]i64, s_lpc_q14: [16]i64, prev_nlsf_q15: [16]i64, exc_q14: [320]i64, last_gain_index: i64, prev_gain_q16: i64, lag_prev: i64, ec_prev_type: i64, ec_prev_lag: i64, first_frame: i64, frames_decoded: i64, vad: [3]i64, lbrr_flag: i64, lbrr: [3]i64 }

type SilkIdx = struct { signal_type: i64, quant_offset: i64, gains: [4]i64, nlsf: [17]i64, interp_q2: i64, lag_index: i64, contour_index: i64, per_index: i64, ltp_index: [4]i64, ltp_scale_index: i64, seed: i64 }

type Silk = struct { fs_khz: i64, channels: i64, lpc_order: i64, subfr_length: i64, ltp_mem_length: i64, ch: [2]SilkChan, s_mid: [2]i64, s_side: [2]i64, pred_prev_q13: [2]i64, pred_q13: [2]i64, prev_only_mid: i64, idx: SilkIdx, pulses: [320]i64, sum_pulses: [20]i64, n_lshifts: [20]i64, gain_q16: [4]i64, a0_q12: [16]i64, a1_q12: [16]i64, pitch_l: [4]i64, ltp_q14: [20]i64, ltp_scale_q14: i64, interp: i64, nlsf_q15: [16]i64, nlsf0_q15: [16]i64, res_q10: [16]i64, ec_ix: [16]i64, pred_q8: [16]i64, s_ltp: [320]i64, s_ltp_q15: [640]i64, s_lpc: [96]i64, res: [80]i64, xq: [320]i64, tmp0: [326]i64, tmp1: [326]i64 }

// ---- fixed-point helpers, the reference decoder's macros ----

fn silk_w32(x: i64) -> i64 {
    let m = x & 4294967295i64
    if m >= 2147483648i64 { ret m - 4294967296i64 }
    ret m
}

fn silk_w16(x: i64) -> i64 {
    let m = x & 65535i64
    if m >= 32768i64 { ret m - 65536i64 }
    ret m
}

fn silk_sat16(x: i64) -> i64 {
    if x > 32767i64 { ret 32767i64 }
    if x < 0i64 - 32768i64 { ret 0i64 - 32768i64 }
    ret x
}

fn silk_sat32(x: i64) -> i64 {
    if x > 2147483647i64 { ret 2147483647i64 }
    if x < 0i64 - 2147483648i64 { ret 0i64 - 2147483648i64 }
    ret x
}

fn silk_abs(x: i64) -> i64 {
    if x < 0i64 { ret 0i64 - x }
    ret x
}

fn silk_min(a: i64, b: i64) -> i64 {
    if a < b { ret a }
    ret b
}

fn silk_limit(a: i64, lo: i64, hi: i64) -> i64 {
    if a < lo { ret lo }
    if a > hi { ret hi }
    ret a
}

// silk_RSHIFT_ROUND: round half away from -inf, as the reference spells it.
fn silk_rrsh(a: i64, s: u32) -> i64 {
    if s == 1u32 { ret (a >> 1u32) + (a & 1i64) }
    ret ((a >> (s - 1u32)) + 1i64) >> 1u32
}

fn silk_smulwb(a: i64, b: i64) -> i64 {
    ret silk_w32((a * silk_w16(b)) >> 16u32)
}

fn silk_smlawb(a: i64, b: i64, c: i64) -> i64 {
    ret silk_w32(a + ((b * silk_w16(c)) >> 16u32))
}

fn silk_smulww(a: i64, b: i64) -> i64 {
    ret silk_w32((a * b) >> 16u32)
}

fn silk_smlaww(a: i64, b: i64, c: i64) -> i64 {
    ret silk_w32(a + ((b * c) >> 16u32))
}

fn silk_smmul(a: i64, b: i64) -> i64 {
    ret silk_w32((a * b) >> 32u32)
}

fn silk_clz32(x: i64) -> u32 {
    var v = x & 4294967295i64
    if v == 0i64 { ret 32u32 }
    var n = 0u32
    while v < 2147483648i64 {
        v = v << 1u32
        n = n + 1u32
    }
    ret n
}

fn silk_lshift_sat32(a: i64, s: u32) -> i64 {
    let lo = (0i64 - 2147483648i64) >> s
    let hi = 2147483647i64 >> s
    ret silk_limit(a, lo, hi) << s
}

fn silk_inv32_varq(b32: i64, qres: u32) -> i64 {
    let hr = silk_clz32(silk_abs(b32)) - 1u32
    let bn = silk_w32(b32 << hr)
    let binv = 536870911i64 / (bn >> 16u32)
    var result = silk_w32(binv << 16u32)
    let e = silk_w32((536870912i64 - silk_smulwb(bn, binv)) << 3u32)
    result = silk_smlaww(result, e, binv)
    let ls = 61i64 - i64(hr) - i64(qres)
    if ls <= 0i64 { ret silk_lshift_sat32(result, u32(0i64 - ls)) }
    if ls < 32i64 { ret result >> u32(ls) }
    ret 0i64
}

fn silk_div32_varq(a32: i64, b32: i64, qres: u32) -> i64 {
    let ah = silk_clz32(silk_abs(a32)) - 1u32
    var an = silk_w32(a32 << ah)
    let bh = silk_clz32(silk_abs(b32)) - 1u32
    let bn = silk_w32(b32 << bh)
    let binv = 536870911i64 / (bn >> 16u32)
    var result = silk_smulwb(an, binv)
    an = silk_w32(an - silk_w32(silk_smmul(bn, result) << 3u32))
    result = silk_smlawb(result, an, binv)
    let ls = 29i64 + i64(ah) - i64(bh) - i64(qres)
    if ls < 0i64 { ret silk_lshift_sat32(result, u32(0i64 - ls)) }
    if ls < 32i64 { ret result >> u32(ls) }
    ret 0i64
}

// silk_log2lin: the piecewise parabolic 2^x the gain dequantizer uses.
fn silk_log2lin(x: i64) -> i64 {
    if x < 0i64 { ret 0i64 }
    if x >= 3967i64 { ret 2147483647i64 }
    let out = 1i64 << u32(x >> 7u32)
    let frac = x & 127i64
    let adj = silk_smlawb(frac, silk_w16(frac) * silk_w16(128i64 - frac), 0i64 - 174i64)
    if x < 2048i64 { ret silk_w32(out + ((out * adj) >> 7u32)) }
    ret silk_w32(out + (out >> 7u32) * adj)
}

// ---- table readers ----

fn silk_tb(t: str, i: usize) -> i64 {
    ret i64(t[i])
}

fn silk_t8(t: str, i: usize) -> i64 {
    let v = i64(t[i])
    if v >= 128i64 { ret v - 256i64 }
    ret v
}

fn silk_t16(t: str, i: usize) -> i64 {
    let v = i64(t[2usize * i]) | (i64(t[2usize * i + 1usize]) << 8u32)
    if v >= 32768i64 { ret v - 65536i64 }
    ret v
}

// ---- table selection ----

fn silk_cb1_q8(order: i64) -> str {
    if order == 10i64 { ret silk_tbl_nlsf_cb1_nb_q8() }
    ret silk_tbl_nlsf_cb1_wb_q8()
}

fn silk_cb1_wght(order: i64) -> str {
    if order == 10i64 { ret silk_tbl_nlsf_wght_nb_q9() }
    ret silk_tbl_nlsf_wght_wb_q9()
}

fn silk_cb1_icdf(order: i64) -> str {
    if order == 10i64 { ret silk_tbl_nlsf_cb1_icdf_nb() }
    ret silk_tbl_nlsf_cb1_icdf_wb()
}

fn silk_nlsf_pred(order: i64) -> str {
    if order == 10i64 { ret silk_tbl_nlsf_pred_nb_q8() }
    ret silk_tbl_nlsf_pred_wb_q8()
}

fn silk_nlsf_sel(order: i64) -> str {
    if order == 10i64 { ret silk_tbl_nlsf_sel_nb() }
    ret silk_tbl_nlsf_sel_wb()
}

fn silk_cb2_icdf(order: i64) -> str {
    if order == 10i64 { ret silk_tbl_nlsf_cb2_icdf_nb() }
    ret silk_tbl_nlsf_cb2_icdf_wb()
}

fn silk_nlsf_dmin(order: i64) -> str {
    if order == 10i64 { ret silk_tbl_nlsf_dmin_nb_q15() }
    ret silk_tbl_nlsf_dmin_wb_q15()
}

fn silk_nlsf_step(order: i64) -> i64 {
    if order == 10i64 { ret 11796i64 }
    ret 9830i64
}

fn silk_nlsf2a_perm(order: i64, i: usize) -> usize {
    if order == 10i64 { ret usize(silk_tb(silk_tbl_order10(), i)) }
    ret usize(silk_tb(silk_tbl_order16(), i))
}

fn silk_lag_low_icdf(fs_khz: i64) -> str {
    if fs_khz == 8i64 { ret silk_tbl_uniform4_icdf() }
    if fs_khz == 12i64 { ret silk_tbl_uniform6_icdf() }
    ret silk_tbl_uniform8_icdf()
}

fn silk_contour_icdf(fs_khz: i64, nb_subfr: i64) -> str {
    if fs_khz == 8i64 {
        if nb_subfr == 4i64 { ret silk_tbl_contour_icdf_nb_4() }
        ret silk_tbl_contour_icdf_nb_2()
    }
    if nb_subfr == 4i64 { ret silk_tbl_contour_icdf_4() }
    ret silk_tbl_contour_icdf_2()
}

fn silk_lag_cb(fs_khz: i64, nb_subfr: i64) -> str {
    if fs_khz == 8i64 {
        if nb_subfr == 4i64 { ret silk_tbl_lag_cb_nb_4() }
        ret silk_tbl_lag_cb_nb_2()
    }
    if nb_subfr == 4i64 { ret silk_tbl_lag_cb_4() }
    ret silk_tbl_lag_cb_2()
}

fn silk_lag_cb_size(fs_khz: i64, nb_subfr: i64) -> usize {
    if fs_khz == 8i64 {
        if nb_subfr == 4i64 { ret 11usize }
        ret 3usize
    }
    if nb_subfr == 4i64 { ret 34usize }
    ret 12usize
}

fn silk_ltp_icdf(per: i64) -> str {
    if per == 0i64 { ret silk_tbl_ltp_icdf0() }
    if per == 1i64 { ret silk_tbl_ltp_icdf1() }
    ret silk_tbl_ltp_icdf2()
}

fn silk_ltp_vq(per: i64) -> str {
    if per == 0i64 { ret silk_tbl_ltp_vq0() }
    if per == 1i64 { ret silk_tbl_ltp_vq1() }
    ret silk_tbl_ltp_vq2()
}

fn silk_shell_tbl(level: i64) -> str {
    if level == 0i64 { ret silk_tbl_shell0() }
    if level == 1i64 { ret silk_tbl_shell1() }
    if level == 2i64 { ret silk_tbl_shell2() }
    ret silk_tbl_shell3()
}

fn silk_qoffset(sig: i64, qo: i64) -> i64 {
    if (sig >> 1u32) == 0i64 {
        if qo == 0i64 { ret 100i64 }
        ret 240i64
    }
    if qo == 0i64 { ret 32i64 }
    ret 100i64
}

// ---- decoder state ----

fn silk_reset_chan(d: *Silk, ci: usize) {
    var i = 0usize
    while i < 480usize {
        d.ch[ci].out_buf[i] = 0i64
        i = i + 1usize
    }
    i = 0usize
    while i < 16usize {
        d.ch[ci].s_lpc_q14[i] = 0i64
        d.ch[ci].prev_nlsf_q15[i] = 0i64
        i = i + 1usize
    }
    i = 0usize
    while i < 320usize {
        d.ch[ci].exc_q14[i] = 0i64
        i = i + 1usize
    }
    i = 0usize
    while i < 3usize {
        d.ch[ci].vad[i] = 0i64
        d.ch[ci].lbrr[i] = 0i64
        i = i + 1usize
    }
    d.ch[ci].last_gain_index = 10i64
    d.ch[ci].prev_gain_q16 = 65536i64
    d.ch[ci].lag_prev = 100i64
    d.ch[ci].ec_prev_type = 0i64
    d.ch[ci].ec_prev_lag = 0i64
    d.ch[ci].first_frame = 1i64
    d.ch[ci].frames_decoded = 0i64
    d.ch[ci].lbrr_flag = 0i64
}

// silk_init prepares a decoder for one internal rate and channel count.  Changing
// either mid-stream means calling it again: the reference resets the same state.
fn silk_init(d: *Silk, fs_khz: i64, channels: i64) -> err {
    if fs_khz != 8i64 && fs_khz != 12i64 && fs_khz != 16i64 { ret Unsupported }
    if channels != 1i64 && channels != 2i64 { ret Unsupported }
    d.fs_khz = fs_khz
    d.channels = channels
    d.lpc_order = 10i64
    if fs_khz == 16i64 { d.lpc_order = 16i64 }
    d.subfr_length = 5i64 * fs_khz
    d.ltp_mem_length = 20i64 * fs_khz
    silk_reset_chan(d, 0usize)
    silk_reset_chan(d, 1usize)
    var i = 0usize
    while i < 2usize {
        d.s_mid[i] = 0i64
        d.s_side[i] = 0i64
        d.pred_prev_q13[i] = 0i64
        d.pred_q13[i] = 0i64
        i = i + 1usize
    }
    d.prev_only_mid = 0i64
    ret ok
}

// silk_samples: samples per channel one SILK payload of this length decodes to.
fn silk_samples(fs_khz: i64, payload_ms: i64) -> usize {
    ret usize(fs_khz * payload_ms)
}

// ---- side information ----

fn silk_nlsf_unpack(d: *Silk, cb1: i64, order: i64) {
    let ou = usize(order)
    let base = usize(cb1) * ou / 2usize
    var i = 0usize
    while i < ou {
        let e = silk_tb(silk_nlsf_sel(order), base + i / 2usize)
        d.ec_ix[i] = ((e >> 1u32) & 7i64) * 9i64
        d.pred_q8[i] = silk_tb(silk_nlsf_pred(order), i + usize(e & 1i64) * (ou - 1usize))
        d.ec_ix[i + 1usize] = ((e >> 5u32) & 7i64) * 9i64
        d.pred_q8[i + 1usize] = silk_tb(silk_nlsf_pred(order), i + usize((e >> 4u32) & 1i64) * (ou - 1usize) + 1usize)
        i = i + 2usize
    }
}

fn silk_decode_indices(d: *Silk, r: *Range, ci: usize, nb_subfr: i64, fidx: usize, lbrr: i64, cond: i64) {
    var t = 0i64
    if lbrr != 0i64 || d.ch[ci].vad[fidx] != 0i64 {
        t = i64(range_decode_icdf(r, silk_tbl_type_offset_vad_icdf(), 8u32)) + 2i64
    }
    if lbrr == 0i64 && d.ch[ci].vad[fidx] == 0i64 {
        t = i64(range_decode_icdf(r, silk_tbl_type_offset_no_vad_icdf(), 8u32))
    }
    d.idx.signal_type = t >> 1u32
    d.idx.quant_offset = t & 1i64
    if cond == 2i64 {
        d.idx.gains[0] = i64(range_decode_icdf(r, silk_tbl_delta_gain_icdf(), 8u32))
    }
    if cond != 2i64 {
        let gi = usize(d.idx.signal_type) * 8usize
        let hi = i64(range_decode_icdf(r, silk_tbl_gain_icdf()[gi..gi + 8usize], 8u32))
        d.idx.gains[0] = (hi << 3u32) + i64(range_decode_icdf(r, silk_tbl_uniform8_icdf(), 8u32))
    }
    var k = 1usize
    while k < usize(nb_subfr) {
        d.idx.gains[k] = i64(range_decode_icdf(r, silk_tbl_delta_gain_icdf(), 8u32))
        k = k + 1usize
    }
    let order = d.lpc_order
    let ou = usize(order)
    let ci1 = usize(d.idx.signal_type >> 1u32) * 32usize
    d.idx.nlsf[0] = i64(range_decode_icdf(r, silk_cb1_icdf(order)[ci1..ci1 + 32usize], 8u32))
    silk_nlsf_unpack(d, d.idx.nlsf[0], order)
    var i = 0usize
    while i < ou {
        let base = usize(d.ec_ix[i])
        var v = i64(range_decode_icdf(r, silk_cb2_icdf(order)[base..base + 9usize], 8u32))
        if v == 0i64 { v = v - i64(range_decode_icdf(r, silk_tbl_nlsf_ext_icdf(), 8u32)) }
        if v == 8i64 { v = v + i64(range_decode_icdf(r, silk_tbl_nlsf_ext_icdf(), 8u32)) }
        d.idx.nlsf[i + 1usize] = v - 4i64
        i = i + 1usize
    }
    d.idx.interp_q2 = 4i64
    if nb_subfr == 4i64 {
        d.idx.interp_q2 = i64(range_decode_icdf(r, silk_tbl_nlsf_interp_icdf(), 8u32))
    }
    d.idx.lag_index = 0i64
    d.idx.contour_index = 0i64
    d.idx.per_index = 0i64
    d.idx.ltp_scale_index = 0i64
    var z = 0usize
    while z < 4usize {
        d.idx.ltp_index[z] = 0i64
        z = z + 1usize
    }
    if d.idx.signal_type == 2i64 {
        var absolute = 1i64
        if cond == 2i64 && d.ch[ci].ec_prev_type == 2i64 {
            let delta = i64(range_decode_icdf(r, silk_tbl_pitch_delta_icdf(), 8u32))
            if delta > 0i64 {
                d.idx.lag_index = d.ch[ci].ec_prev_lag + delta - 9i64
                absolute = 0i64
            }
        }
        if absolute == 1i64 {
            let high = i64(range_decode_icdf(r, silk_tbl_pitch_lag_icdf(), 8u32))
            let low = i64(range_decode_icdf(r, silk_lag_low_icdf(d.fs_khz), 8u32))
            d.idx.lag_index = high * (d.fs_khz >> 1u32) + low
        }
        d.ch[ci].ec_prev_lag = d.idx.lag_index
        d.idx.contour_index = i64(range_decode_icdf(r, silk_contour_icdf(d.fs_khz, nb_subfr), 8u32))
        d.idx.per_index = i64(range_decode_icdf(r, silk_tbl_ltp_per_icdf(), 8u32))
        var k2 = 0usize
        while k2 < usize(nb_subfr) {
            d.idx.ltp_index[k2] = i64(range_decode_icdf(r, silk_ltp_icdf(d.idx.per_index), 8u32))
            k2 = k2 + 1usize
        }
        if cond == 0i64 {
            d.idx.ltp_scale_index = i64(range_decode_icdf(r, silk_tbl_ltp_scale_icdf(), 8u32))
        }
    }
    d.ch[ci].ec_prev_type = d.idx.signal_type
    d.idx.seed = i64(range_decode_icdf(r, silk_tbl_uniform4_icdf(), 8u32))
}

// ---- excitation ----

fn silk_shell_split(r: *Range, p: i64, level: i64) -> i64 {
    if p > 0i64 {
        let off = usize(silk_tb(silk_tbl_shell_off(), usize(p)))
        ret i64(range_decode_icdf(r, silk_shell_tbl(level)[off..], 8u32))
    }
    ret 0i64
}

fn silk_shell_decode(d: *Silk, r: *Range, off: usize, total: i64) {
    var p3: [2]i64 = zero
    var p2: [4]i64 = zero
    var p1: [8]i64 = zero
    p3[0] = silk_shell_split(r, total, 3i64)
    p3[1] = total - p3[0]
    p2[0] = silk_shell_split(r, p3[0], 2i64)
    p2[1] = p3[0] - p2[0]
    p1[0] = silk_shell_split(r, p2[0], 1i64)
    p1[1] = p2[0] - p1[0]
    d.pulses[off] = silk_shell_split(r, p1[0], 0i64)
    d.pulses[off + 1usize] = p1[0] - d.pulses[off]
    d.pulses[off + 2usize] = silk_shell_split(r, p1[1], 0i64)
    d.pulses[off + 3usize] = p1[1] - d.pulses[off + 2usize]
    p1[2] = silk_shell_split(r, p2[1], 1i64)
    p1[3] = p2[1] - p1[2]
    d.pulses[off + 4usize] = silk_shell_split(r, p1[2], 0i64)
    d.pulses[off + 5usize] = p1[2] - d.pulses[off + 4usize]
    d.pulses[off + 6usize] = silk_shell_split(r, p1[3], 0i64)
    d.pulses[off + 7usize] = p1[3] - d.pulses[off + 6usize]
    p2[2] = silk_shell_split(r, p3[1], 2i64)
    p2[3] = p3[1] - p2[2]
    p1[4] = silk_shell_split(r, p2[2], 1i64)
    p1[5] = p2[2] - p1[4]
    d.pulses[off + 8usize] = silk_shell_split(r, p1[4], 0i64)
    d.pulses[off + 9usize] = p1[4] - d.pulses[off + 8usize]
    d.pulses[off + 10usize] = silk_shell_split(r, p1[5], 0i64)
    d.pulses[off + 11usize] = p1[5] - d.pulses[off + 10usize]
    p1[6] = silk_shell_split(r, p2[3], 1i64)
    p1[7] = p2[3] - p1[6]
    d.pulses[off + 12usize] = silk_shell_split(r, p1[6], 0i64)
    d.pulses[off + 13usize] = p1[6] - d.pulses[off + 12usize]
    d.pulses[off + 14usize] = silk_shell_split(r, p1[7], 0i64)
    d.pulses[off + 15usize] = p1[7] - d.pulses[off + 14usize]
}

fn silk_decode_pulses(d: *Silk, r: *Range, nb_subfr: i64) {
    let flen = usize(nb_subfr * d.subfr_length)
    let lv = usize(d.idx.signal_type >> 1u32) * 9usize
    let lvl = usize(range_decode_icdf(r, silk_tbl_rate_level_icdf()[lv..lv + 9usize], 8u32))
    var it = flen / 16usize
    if it * 16usize < flen { it = it + 1usize }
    var i = 0usize
    while i < it {
        d.n_lshifts[i] = 0i64
        let row = lvl * 18usize
        d.sum_pulses[i] = i64(range_decode_icdf(r, silk_tbl_pulses_icdf()[row..row + 18usize], 8u32))
        while d.sum_pulses[i] == 17i64 {
            d.n_lshifts[i] = d.n_lshifts[i] + 1i64
            var extra = 162usize
            if d.n_lshifts[i] == 10i64 { extra = 163usize }
            d.sum_pulses[i] = i64(range_decode_icdf(r, silk_tbl_pulses_icdf()[extra..180usize], 8u32))
        }
        i = i + 1usize
    }
    i = 0usize
    while i < it {
        if d.sum_pulses[i] > 0i64 { silk_shell_decode(d, r, i * 16usize, d.sum_pulses[i]) }
        if d.sum_pulses[i] <= 0i64 {
            var z = 0usize
            while z < 16usize {
                d.pulses[i * 16usize + z] = 0i64
                z = z + 1usize
            }
        }
        i = i + 1usize
    }
    i = 0usize
    while i < it {
        if d.n_lshifts[i] > 0i64 {
            var k = 0usize
            while k < 16usize {
                var q = d.pulses[i * 16usize + k]
                var j = 0i64
                while j < d.n_lshifts[i] {
                    q = (q << 1u32) + i64(range_decode_icdf(r, silk_tbl_lsb_icdf(), 8u32))
                    j = j + 1i64
                }
                d.pulses[i * 16usize + k] = q
                k = k + 1usize
            }
            d.sum_pulses[i] = d.sum_pulses[i] | (d.n_lshifts[i] << 5u32)
        }
        i = i + 1usize
    }
    let sbase = usize(7i64 * (d.idx.quant_offset + (d.idx.signal_type << 1u32)))
    let nblocks = (flen + 8usize) >> 4u32
    i = 0usize
    while i < nblocks {
        if d.sum_pulses[i] > 0i64 {
            var m = d.sum_pulses[i] & 31i64
            if m > 6i64 { m = 6i64 }
            var ic: [2]u8 = zero
            ic[0] = u8(silk_tb(silk_tbl_sign_icdf(), sbase + usize(m)))
            ic[1] = 0u8
            var j2 = 0usize
            while j2 < 16usize {
                if d.pulses[i * 16usize + j2] > 0i64 {
                    let sb = i64(range_decode_icdf(r, ic[0..2], 8u32))
                    d.pulses[i * 16usize + j2] = d.pulses[i * 16usize + j2] * ((sb << 1u32) - 1i64)
                }
                j2 = j2 + 1usize
            }
        }
        i = i + 1usize
    }
}

// ---- gains, NLSFs, LPC ----

fn silk_gains_dequant(d: *Silk, ci: usize, conditional: i64, nb_subfr: i64) {
    var k = 0usize
    while k < usize(nb_subfr) {
        if k == 0usize && conditional == 0i64 {
            var v = d.idx.gains[0]
            if d.ch[ci].last_gain_index - 16i64 > v { v = d.ch[ci].last_gain_index - 16i64 }
            d.ch[ci].last_gain_index = v
        }
        if k > 0usize || conditional != 0i64 {
            let t = d.idx.gains[k] - 4i64
            let thr = 8i64 + d.ch[ci].last_gain_index
            if t > thr { d.ch[ci].last_gain_index = d.ch[ci].last_gain_index + (t << 1u32) - thr }
            if t <= thr { d.ch[ci].last_gain_index = d.ch[ci].last_gain_index + t }
        }
        d.ch[ci].last_gain_index = silk_limit(d.ch[ci].last_gain_index, 0i64, 63i64)
        let lg = silk_min(silk_smulwb(1907825i64, d.ch[ci].last_gain_index) + 2090i64, 3967i64)
        d.gain_q16[k] = silk_log2lin(lg)
        k = k + 1usize
    }
}

fn silk_nlsf_residual_dequant(d: *Silk, order: i64, step: i64) {
    var outv = 0i64
    var i = order - 1i64
    while i >= 0i64 {
        let iu = usize(i)
        let pred = (outv * silk_w16(d.pred_q8[iu])) >> 8u32
        outv = d.idx.nlsf[iu + 1usize] << 10u32
        if outv > 0i64 { outv = outv - 102i64 }
        if outv < 0i64 { outv = outv + 102i64 }
        outv = silk_smlawb(pred, outv, step)
        d.res_q10[iu] = silk_w16(outv)
        i = i - 1i64
    }
}

fn silk_nlsf_stabilize(d: *Silk, order: i64) {
    let big = usize(order)
    let dm = silk_nlsf_dmin(order)
    var loops = 0i64
    var done = 0i64
    while loops < 20i64 && done == 0i64 {
        var mind = d.nlsf_q15[0] - silk_t16(dm, 0usize)
        var im = 0usize
        var i = 1usize
        while i < big {
            let diff = d.nlsf_q15[i] - (d.nlsf_q15[i - 1usize] + silk_t16(dm, i))
            if diff < mind {
                mind = diff
                im = i
            }
            i = i + 1usize
        }
        let dlast = 32768i64 - (d.nlsf_q15[big - 1usize] + silk_t16(dm, big))
        if dlast < mind {
            mind = dlast
            im = big
        }
        if mind >= 0i64 { done = 1i64 }
        if done == 0i64 {
            if im == 0usize { d.nlsf_q15[0] = silk_t16(dm, 0usize) }
            if im == big { d.nlsf_q15[big - 1usize] = 32768i64 - silk_t16(dm, big) }
            if im > 0usize && im < big {
                var lo = 0i64
                var k = 0usize
                while k < im {
                    lo = lo + silk_t16(dm, k)
                    k = k + 1usize
                }
                lo = lo + (silk_t16(dm, im) >> 1u32)
                var hi = 32768i64
                var k2 = big
                while k2 > im {
                    hi = hi - silk_t16(dm, k2)
                    k2 = k2 - 1usize
                }
                hi = hi - (silk_t16(dm, im) >> 1u32)
                let mid = silk_rrsh(d.nlsf_q15[im - 1usize] + d.nlsf_q15[im], 1u32)
                let cf = silk_w16(silk_limit(mid, lo, hi))
                d.nlsf_q15[im - 1usize] = cf - (silk_t16(dm, im) >> 1u32)
                d.nlsf_q15[im] = d.nlsf_q15[im - 1usize] + silk_t16(dm, im)
            }
            loops = loops + 1i64
        }
    }
    if done == 0i64 {
        var i3 = 1usize
        while i3 < big {
            let v = d.nlsf_q15[i3]
            var j = i3
            while j > 0usize && d.nlsf_q15[j - 1usize] > v {
                d.nlsf_q15[j] = d.nlsf_q15[j - 1usize]
                j = j - 1usize
            }
            d.nlsf_q15[j] = v
            i3 = i3 + 1usize
        }
        if d.nlsf_q15[0] < silk_t16(dm, 0usize) { d.nlsf_q15[0] = silk_t16(dm, 0usize) }
        var i4 = 1usize
        while i4 < big {
            let lim = silk_sat16(d.nlsf_q15[i4 - 1usize] + silk_t16(dm, i4))
            if d.nlsf_q15[i4] < lim { d.nlsf_q15[i4] = lim }
            i4 = i4 + 1usize
        }
        let top = 32768i64 - silk_t16(dm, big)
        if d.nlsf_q15[big - 1usize] > top { d.nlsf_q15[big - 1usize] = top }
        var i5 = big - 1usize
        while i5 > 0usize {
            i5 = i5 - 1usize
            let lim2 = d.nlsf_q15[i5 + 1usize] - silk_t16(dm, i5 + 1usize)
            if d.nlsf_q15[i5] > lim2 { d.nlsf_q15[i5] = lim2 }
        }
    }
}

fn silk_nlsf_decode(d: *Silk, order: i64) {
    silk_nlsf_unpack(d, d.idx.nlsf[0], order)
    silk_nlsf_residual_dequant(d, order, silk_nlsf_step(order))
    let ou = usize(order)
    let base = usize(d.idx.nlsf[0]) * ou
    var i = 0usize
    while i < ou {
        let w = silk_t16(silk_cb1_wght(order), base + i)
        let v = ((d.res_q10[i] << 14u32) / w) + (silk_tb(silk_cb1_q8(order), base + i) << 7u32)
        d.nlsf_q15[i] = silk_limit(v, 0i64, 32767i64)
        i = i + 1usize
    }
    silk_nlsf_stabilize(d, order)
}

fn silk_bwexpander32(ar: []i64, dd: usize, chirp0: i64) {
    var chirp = chirp0
    let cm1 = chirp0 - 65536i64
    var i = 0usize
    while i + 1usize < dd {
        ar[i] = silk_smulww(chirp, ar[i])
        chirp = chirp + silk_rrsh(silk_w32(chirp * cm1), 16u32)
        i = i + 1usize
    }
    ar[dd - 1usize] = silk_smulww(chirp, ar[dd - 1usize])
}

fn silk_inv_pred_gain(a12: []const i64, dd: usize) -> i64 {
    var dc = 0i64
    var aa: [16]i64 = zero
    var k = 0usize
    while k < dd {
        dc = dc + a12[k]
        aa[k] = a12[k] << 12u32
        k = k + 1usize
    }
    if dc >= 4096i64 { ret 0i64 }
    var inv = 1073741824i64
    var kk = i64(dd) - 1i64
    while kk > 0i64 {
        let ku = usize(kk)
        if aa[ku] > 16773022i64 || aa[ku] < 0i64 - 16773022i64 { ret 0i64 }
        let rc = silk_w32(0i64 - (aa[ku] << 7u32))
        let m1 = 1073741824i64 - silk_smmul(rc, rc)
        inv = silk_w32(silk_smmul(inv, m1) << 2u32)
        if inv < 107374i64 { ret 0i64 }
        let m2q = 32u32 - silk_clz32(silk_abs(m1))
        let rcm2 = silk_inv32_varq(m1, m2q + 30u32)
        var n = 0usize
        while n < (ku + 1usize) / 2usize {
            let t1 = aa[n]
            let t2 = aa[ku - n - 1usize]
            let v1 = silk_rrsh(silk_sat32(t1 - silk_rrsh(t2 * rc, 31u32)) * rcm2, m2q)
            if v1 > 2147483647i64 || v1 < 0i64 - 2147483648i64 { ret 0i64 }
            let v2 = silk_rrsh(silk_sat32(t2 - silk_rrsh(t1 * rc, 31u32)) * rcm2, m2q)
            if v2 > 2147483647i64 || v2 < 0i64 - 2147483648i64 { ret 0i64 }
            aa[n] = v1
            aa[ku - n - 1usize] = v2
            n = n + 1usize
        }
        kk = kk - 1i64
    }
    if aa[0] > 16773022i64 || aa[0] < 0i64 - 16773022i64 { ret 0i64 }
    let rc0 = silk_w32(0i64 - (aa[0] << 7u32))
    let m10 = 1073741824i64 - silk_smmul(rc0, rc0)
    inv = silk_w32(silk_smmul(inv, m10) << 2u32)
    if inv < 107374i64 { ret 0i64 }
    ret inv
}

fn silk_lpc_fit(aout: []i64, ain: []i64, shift: u32, dd: usize) {
    var i = 0i64
    var clipped = 1i64
    while i < 10i64 {
        var maxabs = 0i64
        var idx = 0usize
        var k = 0usize
        while k < dd {
            let v = silk_abs(ain[k])
            if v > maxabs {
                maxabs = v
                idx = k
            }
            k = k + 1usize
        }
        maxabs = silk_rrsh(maxabs, shift)
        if maxabs > 32767i64 {
            if maxabs > 163838i64 { maxabs = 163838i64 }
            let den = (maxabs * (i64(idx) + 1i64)) >> 2u32
            let chirp = 65536i64 - (((maxabs - 32767i64) << 14u32) / den)
            silk_bwexpander32(ain, dd, chirp)
            i = i + 1i64
        }
        if maxabs <= 32767i64 {
            clipped = 0i64
            i = 10i64
        }
    }
    var k2 = 0usize
    while k2 < dd {
        if clipped == 1i64 {
            aout[k2] = silk_sat16(silk_rrsh(ain[k2], shift))
            ain[k2] = aout[k2] << shift
        }
        if clipped == 0i64 { aout[k2] = silk_rrsh(ain[k2], shift) }
        k2 = k2 + 1usize
    }
}

fn silk_find_poly(outp: []i64, cl: []const i64, start: usize, dd: usize) {
    outp[0] = 65536i64
    outp[1] = silk_w32(0i64 - cl[start])
    var k = 1usize
    while k < dd {
        let ft = cl[start + 2usize * k]
        outp[k + 1usize] = silk_w32((outp[k - 1usize] << 1u32) - silk_rrsh(ft * outp[k], 16u32))
        var n = k
        while n > 1usize {
            outp[n] = silk_w32(outp[n] + outp[n - 2usize] - silk_rrsh(ft * outp[n - 1usize], 16u32))
            n = n - 1usize
        }
        outp[1] = silk_w32(outp[1] - ft)
        k = k + 1usize
    }
}

// silk_nlsf2a: normalized LSFs (Q15) to the monic LPC coefficients (Q12), with the
// reference's reordering, its piecewise-linear 2*cos() table and the bandwidth
// expansion that runs until the prediction gain is finite.
fn silk_nlsf2a(nlsf: []const i64, a12: []i64, order: i64) {
    let ou = usize(order)
    var cos_qa: [16]i64 = zero
    var i = 0usize
    while i < ou {
        let fi = usize(nlsf[i] >> 8u32)
        let ff = nlsf[i] - (i64(fi) << 8u32)
        let cv = silk_t16(silk_tbl_cos_q12(), fi)
        let dl = silk_t16(silk_tbl_cos_q12(), fi + 1usize) - cv
        cos_qa[silk_nlsf2a_perm(order, i)] = silk_rrsh((cv << 8u32) + dl * ff, 4u32)
        i = i + 1usize
    }
    let dd = ou / 2usize
    var pp: [9]i64 = zero
    var qq: [9]i64 = zero
    silk_find_poly(pp[0..dd + 1usize], cos_qa[0..ou], 0usize, dd)
    silk_find_poly(qq[0..dd + 1usize], cos_qa[0..ou], 1usize, dd)
    var a32: [16]i64 = zero
    var k = 0usize
    while k < dd {
        let pt = silk_w32(pp[k + 1usize] + pp[k])
        let qt = silk_w32(qq[k + 1usize] - qq[k])
        a32[k] = silk_w32(0i64 - qt - pt)
        a32[ou - k - 1usize] = silk_w32(qt - pt)
        k = k + 1usize
    }
    silk_lpc_fit(a12, a32[0..ou], 5u32, ou)
    var it = 0i64
    while it < 16i64 && silk_inv_pred_gain(a12, ou) == 0i64 {
        silk_bwexpander32(a32[0..ou], ou, 65536i64 - (2i64 << u32(it)))
        var k2 = 0usize
        while k2 < ou {
            a12[k2] = silk_rrsh(a32[k2], 5u32)
            k2 = k2 + 1usize
        }
        it = it + 1i64
    }
}

// ---- LTP and the frame parameters ----

fn silk_decode_pitch(d: *Silk, nb_subfr: i64) {
    let cb = silk_lag_cb(d.fs_khz, nb_subfr)
    let size = silk_lag_cb_size(d.fs_khz, nb_subfr)
    let lo = 2i64 * d.fs_khz
    let hi = 18i64 * d.fs_khz
    let lag = lo + d.idx.lag_index
    var k = 0usize
    while k < usize(nb_subfr) {
        let off = silk_t8(cb, k * size + usize(d.idx.contour_index))
        d.pitch_l[k] = silk_limit(lag + off, lo, hi)
        k = k + 1usize
    }
}

fn silk_decode_parameters(d: *Silk, ci: usize, nb_subfr: i64, cond: i64) {
    var conditional = 0i64
    if cond == 2i64 { conditional = 1i64 }
    silk_gains_dequant(d, ci, conditional, nb_subfr)
    let order = d.lpc_order
    let ou = usize(order)
    silk_nlsf_decode(d, order)
    silk_nlsf2a(d.nlsf_q15[0..ou], d.a1_q12[0..ou], order)
    var interp = d.idx.interp_q2
    if d.ch[ci].first_frame == 1i64 { interp = 4i64 }
    if interp < 4i64 {
        var i = 0usize
        while i < ou {
            let prev = d.ch[ci].prev_nlsf_q15[i]
            d.nlsf0_q15[i] = silk_w16(prev + ((interp * (d.nlsf_q15[i] - prev)) >> 2u32))
            i = i + 1usize
        }
        silk_nlsf2a(d.nlsf0_q15[0..ou], d.a0_q12[0..ou], order)
    }
    if interp >= 4i64 {
        var i2 = 0usize
        while i2 < ou {
            d.a0_q12[i2] = d.a1_q12[i2]
            i2 = i2 + 1usize
        }
    }
    var i3 = 0usize
    while i3 < ou {
        d.ch[ci].prev_nlsf_q15[i3] = d.nlsf_q15[i3]
        i3 = i3 + 1usize
    }
    d.interp = interp
    if d.idx.signal_type == 2i64 {
        silk_decode_pitch(d, nb_subfr)
        let vq = silk_ltp_vq(d.idx.per_index)
        var k = 0usize
        while k < usize(nb_subfr) {
            var j = 0usize
            while j < 5usize {
                d.ltp_q14[k * 5usize + j] = silk_t8(vq, usize(d.idx.ltp_index[k]) * 5usize + j) << 7u32
                j = j + 1usize
            }
            k = k + 1usize
        }
        d.ltp_scale_q14 = silk_t16(silk_tbl_ltp_scale_q14(), usize(d.idx.ltp_scale_index))
    }
    if d.idx.signal_type != 2i64 {
        var k2 = 0usize
        while k2 < 4usize {
            d.pitch_l[k2] = 0i64
            k2 = k2 + 1usize
        }
        var j2 = 0usize
        while j2 < 20usize {
            d.ltp_q14[j2] = 0i64
            j2 = j2 + 1usize
        }
        d.ltp_scale_q14 = 0i64
    }
}

// ---- synthesis ----

// The whitening filter that re-derives the LTP history from the output buffer with
// the current frame's LPC coefficients.
fn silk_lpc_analysis(d: *Silk, ci: usize, out_off: usize, in_shift: usize, length: usize, ou: usize, use_a1: i64) {
    let in_off = out_off + in_shift
    var ix = ou
    while ix < length {
        var acc = 0i64
        var j = 0usize
        while j < ou {
            var av = d.a0_q12[j]
            if use_a1 == 1i64 { av = d.a1_q12[j] }
            acc = silk_w32(acc + silk_w16(d.ch[ci].out_buf[in_off + ix - 1usize - j]) * silk_w16(av))
            j = j + 1usize
        }
        acc = silk_w32((d.ch[ci].out_buf[in_off + ix] << 12u32) - acc)
        d.s_ltp[out_off + ix] = silk_sat16(silk_rrsh(acc, 12u32))
        ix = ix + 1usize
    }
    var z = 0usize
    while z < ou {
        d.s_ltp[out_off + z] = 0i64
        z = z + 1usize
    }
}

fn silk_decode_core(d: *Silk, ci: usize, nb_subfr: i64) {
    let sl = usize(d.subfr_length)
    let flen = usize(nb_subfr) * sl
    let ml = usize(d.ltp_mem_length)
    let ou = usize(d.lpc_order)
    let off10 = silk_qoffset(d.idx.signal_type, d.idx.quant_offset)
    var interp_flag = 0i64
    if d.interp < 4i64 { interp_flag = 1i64 }
    var seed = d.idx.seed
    var i = 0usize
    while i < flen {
        seed = silk_w32(907633515i64 + silk_w32(seed * 196314165i64))
        var e = d.pulses[i] << 14u32
        if e > 0i64 { e = e - 1280i64 }
        if e < 0i64 { e = e + 1280i64 }
        e = e + (off10 << 4u32)
        if seed < 0i64 { e = 0i64 - e }
        d.ch[ci].exc_q14[i] = e
        seed = silk_w32(seed + d.pulses[i])
        i = i + 1usize
    }
    var c = 0usize
    while c < 16usize {
        d.s_lpc[c] = d.ch[ci].s_lpc_q14[c]
        c = c + 1usize
    }
    var sbi = ml
    var lag = 0i64
    var ks = 0usize
    while ks < usize(nb_subfr) {
        let g = d.gain_q16[ks]
        let gain10 = g >> 6u32
        var invg = silk_inv32_varq(g, 47u32)
        var gadj = 65536i64
        if g != d.ch[ci].prev_gain_q16 {
            gadj = silk_div32_varq(d.ch[ci].prev_gain_q16, g, 16u32)
            var z = 0usize
            while z < 16usize {
                d.s_lpc[z] = silk_smulww(gadj, d.s_lpc[z])
                z = z + 1usize
            }
        }
        d.ch[ci].prev_gain_q16 = g
        var use_a1 = 1i64
        if ks < 2usize { use_a1 = 0i64 }
        if d.idx.signal_type == 2i64 {
            lag = d.pitch_l[ks]
            var rewhiten = 0i64
            if ks == 0usize { rewhiten = 1i64 }
            if ks == 2usize && interp_flag == 1i64 { rewhiten = 1i64 }
            if rewhiten == 1i64 {
                let start = ml - usize(lag) - ou - 2usize
                if ks == 2usize {
                    var cp = 0usize
                    while cp < 2usize * sl {
                        d.ch[ci].out_buf[ml + cp] = d.xq[cp]
                        cp = cp + 1usize
                    }
                }
                silk_lpc_analysis(d, ci, start, ks * sl, ml - start, ou, use_a1)
                if ks == 0usize { invg = silk_w32(silk_smulwb(invg, d.ltp_scale_q14) << 2u32) }
                var q = 0usize
                while q < usize(lag) + 2usize {
                    d.s_ltp_q15[sbi - q - 1usize] = silk_smulwb(invg, d.s_ltp[ml - q - 1usize])
                    q = q + 1usize
                }
            }
            if rewhiten == 0i64 && gadj != 65536i64 {
                var q2 = 0usize
                while q2 < usize(lag) + 2usize {
                    d.s_ltp_q15[sbi - q2 - 1usize] = silk_smulww(gadj, d.s_ltp_q15[sbi - q2 - 1usize])
                    q2 = q2 + 1usize
                }
            }
            var p = sbi - usize(lag) + 2usize
            var n = 0usize
            while n < sl {
                var acc = 2i64
                var j = 0usize
                while j < 5usize {
                    acc = silk_smlawb(acc, d.s_ltp_q15[p - j], d.ltp_q14[ks * 5usize + j])
                    j = j + 1usize
                }
                p = p + 1usize
                d.res[n] = silk_w32(d.ch[ci].exc_q14[ks * sl + n] + (acc << 1u32))
                d.s_ltp_q15[sbi] = silk_w32(d.res[n] << 1u32)
                sbi = sbi + 1usize
                n = n + 1usize
            }
        }
        var n2 = 0usize
        while n2 < sl {
            var pacc = i64(ou) >> 1u32
            var j2 = 0usize
            while j2 < ou {
                var av = d.a0_q12[j2]
                if use_a1 == 1i64 { av = d.a1_q12[j2] }
                pacc = silk_smlawb(pacc, d.s_lpc[16usize + n2 - 1usize - j2], av)
                j2 = j2 + 1usize
            }
            var pv = d.ch[ci].exc_q14[ks * sl + n2]
            if d.idx.signal_type == 2i64 { pv = d.res[n2] }
            d.s_lpc[16usize + n2] = silk_sat32(pv + (silk_limit(pacc, 0i64 - 134217728i64, 134217727i64) << 4u32))
            d.xq[ks * sl + n2] = silk_sat16(silk_rrsh(silk_smulww(d.s_lpc[16usize + n2], gain10), 8u32))
            n2 = n2 + 1usize
        }
        var mv = 0usize
        while mv < 16usize {
            d.s_lpc[mv] = d.s_lpc[sl + mv]
            mv = mv + 1usize
        }
        ks = ks + 1usize
    }
    var sv = 0usize
    while sv < 16usize {
        d.ch[ci].s_lpc_q14[sv] = d.s_lpc[sv]
        sv = sv + 1usize
    }
}

fn silk_decode_frame(d: *Silk, r: *Range, ci: usize, nb_subfr: i64, fidx: usize, cond: i64) {
    silk_decode_indices(d, r, ci, nb_subfr, fidx, 0i64, cond)
    silk_decode_pulses(d, r, nb_subfr)
    silk_decode_parameters(d, ci, nb_subfr, cond)
    silk_decode_core(d, ci, nb_subfr)
    d.ch[ci].first_frame = 0i64
    let flen = usize(nb_subfr * d.subfr_length)
    let ml = usize(d.ltp_mem_length)
    let mv = ml - flen
    var i = 0usize
    while i < mv {
        d.ch[ci].out_buf[i] = d.ch[ci].out_buf[flen + i]
        i = i + 1usize
    }
    var j = 0usize
    while j < flen {
        d.ch[ci].out_buf[mv + j] = d.xq[j]
        j = j + 1usize
    }
    d.ch[ci].lag_prev = d.pitch_l[usize(nb_subfr) - 1usize]
}

// ---- stereo ----

fn silk_stereo_level(a: i64, b: i64) -> i64 {
    let q = silk_tbl_stereo_quant_q13()
    let low = silk_t16(q, usize(a))
    let step = silk_smulwb(silk_t16(q, usize(a) + 1usize) - low, 6554i64)
    ret low + silk_w16(step) * silk_w16(2i64 * b + 1i64)
}

fn silk_stereo_pred(d: *Silk, r: *Range) {
    let nj = i64(range_decode_icdf(r, silk_tbl_stereo_joint_icdf(), 8u32))
    let hi0 = nj / 5i64
    let hi1 = nj - 5i64 * hi0
    let a0 = i64(range_decode_icdf(r, silk_tbl_uniform3_icdf(), 8u32))
    let a1 = i64(range_decode_icdf(r, silk_tbl_uniform5_icdf(), 8u32))
    let b0 = i64(range_decode_icdf(r, silk_tbl_uniform3_icdf(), 8u32))
    let b1 = i64(range_decode_icdf(r, silk_tbl_uniform5_icdf(), 8u32))
    let pa = silk_stereo_level(a0 + 3i64 * hi0, a1)
    let pb = silk_stereo_level(b0 + 3i64 * hi1, b1)
    d.pred_q13[0] = pa - pb
    d.pred_q13[1] = pb
}

fn silk_stereo_ms_to_lr(d: *Silk, pred0: i64, pred1: i64, n: usize) {
    d.tmp0[0] = d.s_mid[0]
    d.tmp0[1] = d.s_mid[1]
    d.tmp1[0] = d.s_side[0]
    d.tmp1[1] = d.s_side[1]
    d.s_mid[0] = d.tmp0[n]
    d.s_mid[1] = d.tmp0[n + 1usize]
    d.s_side[0] = d.tmp1[n]
    d.s_side[1] = d.tmp1[n + 1usize]
    var p0 = d.pred_prev_q13[0]
    var p1 = d.pred_prev_q13[1]
    let denom = 65536i64 / (8i64 * d.fs_khz)
    let dl0 = silk_rrsh(silk_w16(pred0 - d.pred_prev_q13[0]) * silk_w16(denom), 16u32)
    let dl1 = silk_rrsh(silk_w16(pred1 - d.pred_prev_q13[1]) * silk_w16(denom), 16u32)
    let span = usize(8i64 * d.fs_khz)
    var m = 0usize
    while m < n {
        var q0 = pred0
        var q1 = pred1
        if m < span {
            p0 = p0 + dl0
            p1 = p1 + dl1
            q0 = p0
            q1 = p1
        }
        var sum = silk_w32((d.tmp0[m] + d.tmp0[m + 2usize] + (d.tmp0[m + 1usize] << 1u32)) << 9u32)
        sum = silk_smlawb(d.tmp1[m + 1usize] << 8u32, sum, q0)
        sum = silk_smlawb(sum, d.tmp0[m + 1usize] << 11u32, q1)
        d.tmp1[m + 1usize] = silk_sat16(silk_rrsh(sum, 8u32))
        m = m + 1usize
    }
    d.pred_prev_q13[0] = pred0
    d.pred_prev_q13[1] = pred1
    var m2 = 0usize
    while m2 < n {
        let a = d.tmp0[m2 + 1usize] + d.tmp1[m2 + 1usize]
        let b = d.tmp0[m2 + 1usize] - d.tmp1[m2 + 1usize]
        d.tmp0[m2 + 1usize] = silk_sat16(a)
        d.tmp1[m2 + 1usize] = silk_sat16(b)
        m2 = m2 + 1usize
    }
}

// ---- the payload ----

// silk_decode reads one SILK payload -- the range coder is positioned just past the
// Opus TOC and framing -- and writes `channels`-interleaved 16-bit samples at the
// internal rate.  `payload_ms` is 10, 20, 40 or 60; the last two are two and three
// SILK frames sharing one header.  Answers the samples per channel written.
fn silk_decode(d: *Silk, r: *Range, payload_ms: i64, out: []i16) -> (usize, err) {
    if payload_ms != 10i64 && payload_ms != 20i64 && payload_ms != 40i64 && payload_ms != 60i64 {
        ret (0usize, Invalid)
    }
    var nframes = 1i64
    if payload_ms == 40i64 { nframes = 2i64 }
    if payload_ms == 60i64 { nframes = 3i64 }
    var nb_subfr = 4i64
    if payload_ms == 10i64 { nb_subfr = 2i64 }
    if d.fs_khz != 8i64 && d.fs_khz != 12i64 && d.fs_khz != 16i64 { ret (0usize, Invalid) }
    let flen = usize(nb_subfr * d.subfr_length)
    let total = usize(nframes) * flen
    let nch = usize(d.channels)
    if out.len < total * nch { ret (0usize, Invalid) }
    var n = 0usize
    while n < nch {
        d.ch[n].frames_decoded = 0i64
        var i = 0usize
        while i < usize(nframes) {
            d.ch[n].vad[i] = i64(range_decode_bit_logp(r, 1u32))
            i = i + 1usize
        }
        d.ch[n].lbrr_flag = i64(range_decode_bit_logp(r, 1u32))
        n = n + 1usize
    }
    n = 0usize
    while n < nch {
        var i = 0usize
        while i < 3usize {
            d.ch[n].lbrr[i] = 0i64
            i = i + 1usize
        }
        if d.ch[n].lbrr_flag != 0i64 {
            if nframes == 1i64 { d.ch[n].lbrr[0] = 1i64 }
            if nframes > 1i64 {
                var tb = silk_tbl_lbrr2_icdf()
                if nframes == 3i64 { tb = silk_tbl_lbrr3_icdf() }
                let sym = i64(range_decode_icdf(r, tb, 8u32)) + 1i64
                var j = 0usize
                while j < usize(nframes) {
                    d.ch[n].lbrr[j] = (sym >> u32(j)) & 1i64
                    j = j + 1usize
                }
            }
        }
        n = n + 1usize
    }
    var fi = 0usize
    while fi < usize(nframes) {
        var nl = 0usize
        while nl < nch {
            if d.ch[nl].lbrr[fi] != 0i64 {
                if nch == 2usize && nl == 0usize {
                    silk_stereo_pred(d, r)
                    if d.ch[1].lbrr[fi] == 0i64 {
                        let _ = range_decode_icdf(r, silk_tbl_stereo_mid_icdf(), 8u32)
                    }
                }
                var cond = 0i64
                if fi > 0usize && d.ch[nl].lbrr[fi - 1usize] != 0i64 { cond = 2i64 }
                silk_decode_indices(d, r, nl, nb_subfr, fi, 1i64, cond)
                silk_decode_pulses(d, r, nb_subfr)
            }
            nl = nl + 1usize
        }
        fi = fi + 1usize
    }
    var outn = 0usize
    var f = 0usize
    while f < usize(nframes) {
        var pred0 = 0i64
        var pred1 = 0i64
        var only_mid = 0i64
        if nch == 2usize {
            silk_stereo_pred(d, r)
            pred0 = d.pred_q13[0]
            pred1 = d.pred_q13[1]
            if d.ch[1].vad[f] == 0i64 {
                only_mid = i64(range_decode_icdf(r, silk_tbl_stereo_mid_icdf(), 8u32))
            }
        }
        if nch == 2usize && only_mid == 0i64 && d.prev_only_mid == 1i64 {
            silk_reset_chan(d, 1usize)
        }
        var nn = 0usize
        while nn < nch {
            var live = 0i64
            if nn == 0usize || only_mid == 0i64 { live = 1i64 }
            if live == 1i64 {
                let fidx = d.ch[0].frames_decoded - i64(nn)
                var cond = 2i64
                if fidx <= 0i64 { cond = 0i64 }
                if fidx > 0i64 && nn > 0usize && d.prev_only_mid == 1i64 { cond = 1i64 }
                silk_decode_frame(d, r, nn, nb_subfr, f, cond)
                var i = 0usize
                while i < flen {
                    if nn == 0usize { d.tmp0[2usize + i] = d.xq[i] }
                    if nn == 1usize { d.tmp1[2usize + i] = d.xq[i] }
                    i = i + 1usize
                }
            }
            if live == 0i64 {
                var i2 = 0usize
                while i2 < flen {
                    d.tmp1[2usize + i2] = 0i64
                    i2 = i2 + 1usize
                }
            }
            d.ch[nn].frames_decoded = d.ch[nn].frames_decoded + 1i64
            nn = nn + 1usize
        }
        if nch == 2usize { silk_stereo_ms_to_lr(d, pred0, pred1, flen) }
        if nch == 1usize {
            d.tmp0[0] = d.s_mid[0]
            d.tmp0[1] = d.s_mid[1]
            d.s_mid[0] = d.tmp0[flen]
            d.s_mid[1] = d.tmp0[flen + 1usize]
        }
        d.prev_only_mid = only_mid
        var i3 = 0usize
        while i3 < flen {
            out[outn] = i16(d.tmp0[1usize + i3])
            outn = outn + 1usize
            if nch == 2usize {
                out[outn] = i16(d.tmp1[1usize + i3])
                outn = outn + 1usize
            }
            i3 = i3 + 1usize
        }
        f = f + 1usize
    }
    ret (total, ok)
}

// ---------------------------------------------------------------------------
// The SILK decoder-side resampler (silk/resampler*.c), which is what turns the
// internal 8/12/16 kHz frames into the rate the caller asked for.  A copy at
// equal rates, a 2nd-order allpass 2x upsampler at 1:2, that upsampler followed
// by a 12-phase FIR for the other upward ratios, and a 2nd-order AR filter
// followed by a polyphase FIR downward (3:4, 2:3 and 1:2).  The reference also
// holds back `delay_matrix_dec[fs_in][fs_out]` input samples in a per-call delay
// buffer, so the output lags the raw SILK frames by that much; the hybrid sum
// with the CELT layer only lands on the right sample because of it.
//
// The reference resamples one SILK frame per call and the delay buffer makes
// that split observable, so `resamp_process` takes exactly one frame.
// ---------------------------------------------------------------------------

const RS_FIR0: usize = 18usize
const RS_FIR1: usize = 24usize
const RS_FIR12: usize = 8usize

type Resamp = struct { kind: i64, in_khz: i64, out_khz: i64, batch: i64, inv_q16: i64, fir_order: i64, fir_fracs: i64, coefs: i64, in_delay: i64, s_iir: [6]i64, s_fir: [36]i64, dbuf: [48]i64 }

fn rs_up2c(i: usize) -> i64 { ret silk_t16(silk_tbl_rs_up2(), i) }

fn rs_frac(row: usize, k: usize) -> i64 { ret silk_t16(silk_tbl_rs_frac12(), row * 4usize + k) }

fn rs_coef(r: *Resamp, i: usize) -> i64 {
    if r.coefs == 0i64 { ret silk_t16(silk_tbl_rs_3_4(), i) }
    if r.coefs == 1i64 { ret silk_t16(silk_tbl_rs_2_3(), i) }
    ret silk_t16(silk_tbl_rs_1_2(), i)
}

fn rs_rate_id(hz: i64) -> i64 {
    if hz == 8000i64 { ret 0i64 }
    if hz == 12000i64 { ret 1i64 }
    if hz == 16000i64 { ret 2i64 }
    if hz == 24000i64 { ret 3i64 }
    if hz == 48000i64 { ret 4i64 }
    ret 0i64 - 1i64
}

// resamp_init prepares one resampler: the input rate is a SILK internal rate
// (8, 12 or 16 kHz) and the output any rate `decode` answers.
fn resamp_init(r: *Resamp, fs_in_hz: i64, fs_out_hz: i64) -> err {
    let ii = rs_rate_id(fs_in_hz)
    let oi = rs_rate_id(fs_out_hz)
    if ii < 0i64 || ii > 2i64 || oi < 0i64 { ret Unsupported }
    var i = 0usize
    while i < 6usize {
        r.s_iir[i] = 0i64
        i = i + 1usize
    }
    i = 0usize
    while i < 36usize {
        r.s_fir[i] = 0i64
        i = i + 1usize
    }
    i = 0usize
    while i < 48usize {
        r.dbuf[i] = 0i64
        i = i + 1usize
    }
    r.in_delay = silk_tb(silk_tbl_rs_delay(), usize(ii) * 5usize + usize(oi))
    r.in_khz = fs_in_hz / 1000i64
    r.out_khz = fs_out_hz / 1000i64
    r.batch = r.in_khz * 10i64
    r.fir_order = 0i64
    r.fir_fracs = 0i64
    r.coefs = 0i64
    var up2x = 0u32
    if fs_out_hz > fs_in_hz {
        r.kind = 2i64
        up2x = 1u32
        if fs_out_hz == 2i64 * fs_in_hz {
            r.kind = 1i64
            up2x = 0u32
        }
    } else if fs_out_hz < fs_in_hz {
        r.kind = 3i64
        if fs_out_hz * 4i64 == fs_in_hz * 3i64 {
            r.fir_fracs = 3i64
            r.fir_order = i64(RS_FIR0)
            r.coefs = 0i64
        } else if fs_out_hz * 3i64 == fs_in_hz * 2i64 {
            r.fir_fracs = 2i64
            r.fir_order = i64(RS_FIR0)
            r.coefs = 1i64
        } else if fs_out_hz * 2i64 == fs_in_hz {
            r.fir_fracs = 1i64
            r.fir_order = i64(RS_FIR1)
            r.coefs = 2i64
        } else {
            ret Unsupported
        }
    } else {
        r.kind = 0i64
    }
    r.inv_q16 = ((fs_in_hz << (14u32 + up2x)) / fs_out_hz) << 2u32
    while silk_smulww(r.inv_q16, fs_out_hz) < (fs_in_hz << up2x) {
        r.inv_q16 = r.inv_q16 + 1i64
    }
    ret ok
}

// Three second-order allpass sections per output phase, the high-quality 2x
// upsampler; state and arithmetic are Q10, as the reference has them.
fn rs_up2(r: *Resamp, src: []const i64, off: usize, n: usize, dst: []i64, dat: usize) {
    let c0 = rs_up2c(0usize)
    let c1 = rs_up2c(1usize)
    let c2 = rs_up2c(2usize)
    let c3 = rs_up2c(3usize)
    let c4 = rs_up2c(4usize)
    let c5 = rs_up2c(5usize)
    var k = 0usize
    while k < n {
        let in32 = src[off + k] << 10u32
        var y = silk_w32(in32 - r.s_iir[0])
        var x = silk_smulwb(y, c0)
        var o1 = silk_w32(r.s_iir[0] + x)
        r.s_iir[0] = silk_w32(in32 + x)
        y = silk_w32(o1 - r.s_iir[1])
        x = silk_smulwb(y, c1)
        var o2 = silk_w32(r.s_iir[1] + x)
        r.s_iir[1] = silk_w32(o1 + x)
        y = silk_w32(o2 - r.s_iir[2])
        x = silk_smlawb(y, y, c2)
        o1 = silk_w32(r.s_iir[2] + x)
        r.s_iir[2] = silk_w32(o2 + x)
        dst[dat + 2usize * k] = silk_sat16(silk_rrsh(o1, 10u32))
        y = silk_w32(in32 - r.s_iir[3])
        x = silk_smulwb(y, c3)
        o1 = silk_w32(r.s_iir[3] + x)
        r.s_iir[3] = silk_w32(in32 + x)
        y = silk_w32(o1 - r.s_iir[4])
        x = silk_smulwb(y, c4)
        o2 = silk_w32(r.s_iir[4] + x)
        r.s_iir[4] = silk_w32(o1 + x)
        y = silk_w32(o2 - r.s_iir[5])
        x = silk_smlawb(y, y, c5)
        o1 = silk_w32(r.s_iir[5] + x)
        r.s_iir[5] = silk_w32(o2 + x)
        dst[dat + 2usize * k + 1usize] = silk_sat16(silk_rrsh(o1, 10u32))
        k = k + 1usize
    }
}

// The second-order AR filter in front of every downsampler; answers Q8.
fn rs_ar2(r: *Resamp, src: []const i64, off: usize, n: usize, dst: []i64, dat: usize) {
    let a0 = rs_coef(r, 0usize)
    let a1 = rs_coef(r, 1usize)
    var k = 0usize
    while k < n {
        var o = silk_w32(r.s_iir[0] + (src[off + k] << 8u32))
        dst[dat + k] = o
        o = silk_w32(o << 2u32)
        r.s_iir[0] = silk_smlawb(r.s_iir[1], o, a0)
        r.s_iir[1] = silk_smulwb(o, a1)
        k = k + 1usize
    }
}

// 2x upsampling followed by the 12-phase interpolating FIR.  The batching is
// the reference's and is observable: the phase accumulator restarts at zero for
// every batch of `batch` input samples.
fn rs_iir_fir(r: *Resamp, src: []const i64, off_in: usize, n_in: usize, dst: []i64, dat: usize) -> usize {
    var buf: [328]i64 = zero
    var j = 0usize
    while j < RS_FIR12 {
        buf[j] = r.s_fir[j]
        j = j + 1usize
    }
    var off = off_in
    var n = n_in
    var o = dat
    var m = 0usize
    while true {
        m = n
        if usize(r.batch) < m { m = usize(r.batch) }
        rs_up2(r, src, off, m, buf[..], RS_FIR12)
        let top = i64(m) << 17u32
        var idx = 0i64
        while idx < top {
            let ti = usize(silk_smulwb(idx & 65535i64, 12i64))
            let p = usize(idx >> 16u32)
            let q = 11usize - ti
            var res = buf[p] * rs_frac(ti, 0usize)
            res = res + buf[p + 1usize] * rs_frac(ti, 1usize)
            res = res + buf[p + 2usize] * rs_frac(ti, 2usize)
            res = res + buf[p + 3usize] * rs_frac(ti, 3usize)
            res = res + buf[p + 4usize] * rs_frac(q, 3usize)
            res = res + buf[p + 5usize] * rs_frac(q, 2usize)
            res = res + buf[p + 6usize] * rs_frac(q, 1usize)
            res = res + buf[p + 7usize] * rs_frac(q, 0usize)
            dst[o] = silk_sat16(silk_rrsh(silk_w32(res), 15u32))
            o = o + 1usize
            idx = idx + r.inv_q16
        }
        off = off + m
        n = n - m
        if n == 0usize { break }
        j = 0usize
        while j < RS_FIR12 {
            buf[j] = buf[2usize * m + j]
            j = j + 1usize
        }
    }
    j = 0usize
    while j < RS_FIR12 {
        r.s_fir[j] = buf[2usize * m + j]
        j = j + 1usize
    }
    ret o
}

// The AR filter followed by the polyphase decimating FIR.  Order 18 carries
// `fir_fracs` phases, order 24 is the symmetric half-rate filter.
fn rs_down_fir(r: *Resamp, src: []const i64, off_in: usize, n_in: usize, dst: []i64, dat: usize) -> usize {
    var buf: [200]i64 = zero
    let order = usize(r.fir_order)
    let fracs = usize(r.fir_fracs)
    var j = 0usize
    while j < order {
        buf[j] = r.s_fir[j]
        j = j + 1usize
    }
    var off = off_in
    var n = n_in
    var o = dat
    var m = 0usize
    while true {
        m = n
        if usize(r.batch) < m { m = usize(r.batch) }
        rs_ar2(r, src, off, m, buf[..], order)
        let top = i64(m) << 16u32
        var idx = 0i64
        while idx < top {
            let p = usize(idx >> 16u32)
            var res = 0i64
            if order == RS_FIR0 {
                let ph = usize(silk_smulwb(idx & 65535i64, i64(fracs)))
                let lo = 2usize + 9usize * ph
                let hi = 2usize + 9usize * (fracs - 1usize - ph)
                res = silk_smulwb(buf[p], rs_coef(r, lo))
                var k = 1usize
                while k < 9usize {
                    res = silk_smlawb(res, buf[p + k], rs_coef(r, lo + k))
                    k = k + 1usize
                }
                k = 0usize
                while k < 9usize {
                    res = silk_smlawb(res, buf[p + 17usize - k], rs_coef(r, hi + k))
                    k = k + 1usize
                }
            } else {
                res = silk_smulwb(silk_w32(buf[p] + buf[p + 23usize]), rs_coef(r, 2usize))
                var k = 1usize
                while k < 12usize {
                    res = silk_smlawb(res, silk_w32(buf[p + k] + buf[p + 23usize - k]), rs_coef(r, 2usize + k))
                    k = k + 1usize
                }
            }
            dst[o] = silk_sat16(silk_rrsh(res, 6u32))
            o = o + 1usize
            idx = idx + r.inv_q16
        }
        off = off + m
        n = n - m
        if n <= 1usize { break }
        j = 0usize
        while j < order {
            buf[j] = buf[m + j]
            j = j + 1usize
        }
    }
    j = 0usize
    while j < order {
        r.s_fir[j] = buf[m + j]
        j = j + 1usize
    }
    ret o
}

// resamp_process converts one SILK frame to the output rate.  The first
// `in_delay` input samples of each call come from the previous call's tail, so
// the answer lags the SILK frames by that many input samples.
fn resamp_process(r: *Resamp, src: []const i16, out: []i16) -> (usize, err) {
    let n = src.len
    let k = usize(r.in_khz)
    let dl = usize(r.in_delay)
    if n < k || n > 320usize { ret (0usize, Invalid) }
    let nout = n * usize(r.out_khz) / k
    if out.len < nout { ret (0usize, TooSmall) }
    var inbuf: [320]i64 = zero
    var obuf: [960]i64 = zero
    var i = 0usize
    while i < dl {
        inbuf[i] = r.dbuf[i]
        i = i + 1usize
    }
    i = 0usize
    while i + dl < n {
        inbuf[dl + i] = i64(src[i])
        i = i + 1usize
    }
    if r.kind == 0i64 {
        i = 0usize
        while i < n {
            obuf[i] = inbuf[i]
            i = i + 1usize
        }
    } else if r.kind == 1i64 {
        rs_up2(r, inbuf[..], 0usize, k, obuf[..], 0usize)
        rs_up2(r, inbuf[..], k, n - k, obuf[..], 2usize * k)
    } else if r.kind == 2i64 {
        let o1 = rs_iir_fir(r, inbuf[..], 0usize, k, obuf[..], 0usize)
        let _ = rs_iir_fir(r, inbuf[..], k, n - k, obuf[..], o1)
    } else {
        let o1 = rs_down_fir(r, inbuf[..], 0usize, k, obuf[..], 0usize)
        let _ = rs_down_fir(r, inbuf[..], k, n - k, obuf[..], o1)
    }
    i = 0usize
    while i < dl {
        r.dbuf[i] = i64(src[n - dl + i])
        i = i + 1usize
    }
    i = 0usize
    while i < nout {
        out[i] = i16(obuf[i])
        i = i + 1usize
    }
    ret (nout, ok)
}

// ---- tables, emitted by tests/selfhost/fixtures/link/fmt_opus_silk's generator ----

fn silk_tbl_nlsf_cb1_nb_q8() -> str { ret "\x0c#<Sl\x84\x9d\xb4\xce\xe4\x0f 7Me}\x97\xaf\xc9\xe1\x13*BYr\x89\xa2\xb8\xd1\xe6\x0c\x19\x32Hax\x93\xac\xc8\xdf\x1a,EZr\x87\x9f\xb4\xcd\xe1\x0d\x16\x35Pj\x82\x9c\xb4\xcd\xe4\x0f\x19,@Zs\x8e\xa8\xc4\xde\x13\x18>Rdx\x91\xa8\xbe\xd6\x16\x1f\x32Ogx\x97\xaa\xcb\xe3\x15\x1d-Aj|\x96\xab\xc4\xe0\x1e\x31Kay\x8e\xa5\xba\xd1\xe5\x13\x19\x34\x46]t\x8f\xa6\xc0\xdb\x1a\">Kav\x91\xa7\xc2\xd9\x19!8F[q\x8f\xa5\xc4\xdf\x15\"3Hau\x91\xab\xc4\xde\x14\x1d\x32\x43Zu\x90\xa8\xc5\xdd\x16\x1f\x30\x42_u\x92\xa8\xc4\xde\x18!3Mt\x86\x9e\xb4\xc8\xe0\x15\x1c\x46Wj|\x95\xaa\xc2\xd9\x1a!5@Su\x98\xad\xcc\xe1\x1b\"A_l\x81\x9b\xae\xd2\xe1\x14\x1aHcq\x83\x9a\xb0\xc8\xdb\"+=N]r\x9b\xb1\xcd\xe5\x17\x1d\x36\x61|\x8a\xa3\xb3\xd1\xe5\x1e&8Yv\x81\x9e\xb2\xc8\xe7\x15\x1d\x31?Uo\x8e\xa3\xc1\xde\x1b\x30Mg\x85\x9e\xb3\xc4\xd7\xe8\x1d/Jc|\x97\xb0\xc6\xdc\xed!*=L]y\x9b\xae\xcf\xe1\x1d\x35Wp\x88\x9a\xaa\xbc\xd0\xe3\x18\x1e\x34T\x83\x96\xa6\xba\xcb\xe5%0@Thv\x9c\xb1\xc9\xe6" }   // NB/MB stage-1 codebook, 32 x 10, Q8

fn silk_tbl_nlsf_cb1_wb_q8() -> str { ret "\x07\x17&6EUdt\x83\x93\xa2\xb2\xc1\xd0\xdf\xef\x0d\x19)7ESbp\x7f\x8e\x9d\xab\xbb\xcb\xdc\xec\x0f\x15\"3=N\\j~\x88\x98\xa7\xb9\xcd\xe1\xf0\x0a\x15$2?O_n~\x8d\x9d\xad\xbd\xcd\xdd\xed\x11\x14%3;NYk{\x86\x96\xa4\xb8\xcd\xe0\xf0\x0a\x0f 3CQ`p\x81\x8e\x9e\xad\xbd\xcc\xdc\xec\x08\x15%3AObq~\x8a\x9b\xa8\xb3\xc0\xd1\xda\x0c\x0f\"7?NWlv\x83\x94\xa7\xb9\xcb\xdb\xec\x10\x13 $8O[lv\x88\x9a\xab\xba\xcc\xdc\xed\x0b\x1c+:JYix\x87\x96\xa5\xb4\xc4\xd3\xe2\xf1\x06\x10!.<K\\k{\x89\x9c\xa9\xb9\xc7\xd6\xe1\x0b\x13\x1e,9JYiy\x87\x98\xa9\xba\xca\xda\xea\x0c\x13\x1d.9GXdx\x84\x94\xa5\xb6\xc7\xd8\xe9\x11\x17#.8M\\j{\x86\x98\xa7\xb9\xcc\xde\xed\x0e\x11-5?KYks\x84\x97\xab\xbc\xce\xdd\xf0\x09\x10\x1d(8GXgw\x89\x9a\xab\xbd\xcd\xde\xed\x10\x13$09LWiv\x84\x96\xa7\xb9\xca\xda\xec\x0c\x11\x1d\x36GQ^h~\x88\x95\xa4\xb6\xc9\xdd\xed\x0f\x1c/>Oas\x81\x8e\x9b\xa8\xb4\xc2\xd0\xdf\xee\x08\x0e\x1e->N^o\x7f\x8f\x9f\xaf\xc0\xcf\xdf\xef\x11\x1e\x31>O\\kw\x84\x91\xa0\xae\xbe\xcc\xdc\xeb\x0e\x13$-=L[ly\x8a\x9a\xac\xbd\xcd\xde\xee\x0c\x12\x1f-<L[k{\x8a\x9a\xab\xbb\xcc\xdd\xec\x0d\x11\x1f+5FSgr\x83\x95\xa7\xb9\xcb\xdc\xed\x11\x16#*:N]n}\x8b\x9b\xaa\xbc\xce\xe0\xf0\x08\x0f\"2CScs\x83\x92\xa2\xb2\xc1\xd1\xe0\xef\x0d\x10)BIV_o\x80\x89\x96\xa3\xb7\xce\xe1\xf1\x11\x19%4?K\\fw\x84\x90\xa0\xaf\xbf\xd4\xe7\x13\x1f\x31\x41Sdu\x85\x93\xa1\xae\xbb\xc8\xd5\xe3\xf2\x12\x1f\x34\x44Xgu~\x8a\x95\xa3\xb1\xc0\xcf\xdf\xef\x10\x1d/=LZjw\x85\x93\xa1\xb0\xc1\xd1\xe0\xf0\x0f\x15#2=IVanw\x81\x8d\xaf\xc6\xda\xed" }   // WB stage-1 codebook, 32 x 16, Q8

fn silk_tbl_nlsf_cb1_icdf_nb() -> str { ret "\xd4\xb2\x94\x81l`UROM=;98310-*)(&$\"\x1f\x1e\x15\x0c\x0a\x03\x01\x00\xff\xf5\xf4\xec\xe9\xe1\xd9\xcb\xbe\xb0\xaf\xa1\x95\x88}rf[QG<4+#\x1c\x14\x13\x12\x0c\x0b\x05\x00" }   // NB/MB stage-1 index iCDF, 2 x 32

fn silk_tbl_nlsf_cb1_icdf_wb() -> str { ret "\xe1\xcc\xc9\xb8\xb7\xaf\x9e\x9a\x99\x87wsqnmcb_OD420-+ \x1f\x1b\x12\x0a\x03\x00\xff\xfb\xeb\xe6\xd4\xc9\xc4\xb6\xa7\xa6\xa3\x97\x8a|nhZNLFE9-\"\x18\x15\x0b\x06\x05\x04\x03\x00" }   // WB stage-1 index iCDF, 2 x 32

fn silk_tbl_nlsf_pred_nb_q8() -> str { ret "\xb3\x8a\x8c\x94\x97\x95\x99\x97\xa3tCR;\\HdY\\" }   // NB/MB backward predictor weights, Q8

fn silk_tbl_nlsf_pred_wb_q8() -> str { ret "\xaf\x94\xa0\xb0\xb2\xad\xae\xa4\xb1\xae\xc4\xb6\xc6\xc0\xb6\x44>B<HuUZv\x88\x97\x8e\xa0\x8e\x9b" }   // WB backward predictor weights, Q8

fn silk_tbl_nlsf_sel_nb() -> str { ret "\x10\x00\x00\x00\x00\x63\x42$$\"$\"\"\"\"SE$4\"tfFDD\xb0\x66\x44\x44\"AUDT$t\x8d\x98\x8b\xaa\x84\xbb\xb8\xd8\x89\x84\xf9\xa8\xb9\x8bhfdDD\xb2\xda\xb9\xb9\xaa\xf4\xd8\xbb\xbb\xaa\xf4\xbb\xbb\xdb\x8ag\x9b\xb8\xb9\x89t\xb7\x9b\x98\x88\x84\xd9\xb8\xb8\xaa\xa4\xd9\xab\x9b\x8b\xf4\xa9\xb8\xb9\xaa\xa4\xd8\xdf\xda\x8a\xd6\x8f\xbc\xda\xa8\xf4\x8d\x88\x9b\xaa\xa8\x8a\xdc\xdb\x8b\xa4\xdb\xca\xd8\x89\xa8\xba\xf6\xb9\x8bt\xb9\xdb\xb9\x8a\x64\x64\x86\x64\x66\"DDdD\xa8\xcb\xdd\xda\xa8\xa7\x9a\x88hF\xa4\xf6\xab\x89\x8b\x89\x9b\xda\xdb\x8b" }   // NB/MB stage-2 table/predictor selectors

fn silk_tbl_nlsf_sel_wb() -> str { ret "\x00\x00\x00\x00\x00\x00\x00\x01\x64\x66\x66\x44\x44$\"`\xa4k\x9e\xb9\xb4\xb9\x8b\x66@B$\"\"\x00\x01 \xd0\x8b\x8d\xbf\x98\xb9\x9bh`\xabh\xa6\x66\x66\x66\x84\x01\x00\x00\x00\x00\x10\x10\x00PmNk\xb9\x8bge\xd0\xd4\x8d\x8b\xad\x99{g$\x00\x00\x00\x00\x00\x00\x01\x30\x00\x00\x00\x00\x00\x00 D\x87{wwgEbDgxvvfGb\x86\x88\x9d\xb8\xb6\x99\x8b\x86\xd0\xa8\xf8K\xbd\x8fyk 1\"\"\"\x00\x11\x02\xd2\xeb\x8b{\xb9\x89i\x86\x62\x87h\xb6\x64\xb7\xab\x86\x64\x46\x44\x46\x42\x42\"\x83@\xa6\x66\x44$\x02\x01\x00\x86\xa6\x66\x44\"\"B\x84\xd4\xf6\x9e\x8bkkWfd\xdb}z\x89vg\x84r\x87\x89i\xabj2\"\xa4\xd6\x8d\x8f\xb9\x97yg\xc0\"\x00\x00\x00\x00\x00\x01\xd0mJ\xbb\x86\xf9\x9f\x89\x66n\x9avWewe\x00\x02\x00$$BD#`\xa4\x66\x64$\x00\x02!\xa7\x8a\xae\x66\x64T\x02\x02\x64kxw$\xc5\x18\x00" }   // WB stage-2 table/predictor selectors

fn silk_tbl_nlsf_cb2_icdf_nb() -> str { ret "\xff\xfe\xfd\xee\x0e\x03\x02\x01\x00\xff\xfe\xfc\xda#\x03\x02\x01\x00\xff\xfe\xfa\xd0;\x04\x02\x01\x00\xff\xfe\xf6\xc2G\x0a\x02\x01\x00\xff\xfc\xec\xb7R\x08\x02\x01\x00\xff\xfc\xeb\xb4Z\x11\x02\x01\x00\xff\xf8\xe0\xab\x61\x1e\x04\x01\x00\xff\xfe\xec\xad_%\x07\x01\x00" }   // NB/MB stage-2 residual iCDFs, 8 x 9

fn silk_tbl_nlsf_cb2_icdf_wb() -> str { ret "\xff\xfe\xfd\xf4\x0c\x03\x02\x01\x00\xff\xfe\xfc\xe0&\x03\x02\x01\x00\xff\xfe\xfb\xd1\x39\x04\x02\x01\x00\xff\xfe\xf4\xc3\x45\x04\x02\x01\x00\xff\xfb\xe8\xb8T\x07\x02\x01\x00\xff\xfe\xf0\xbaV\x0e\x02\x01\x00\xff\xfe\xef\xb2[\x1e\x05\x01\x00\xff\xf8\xe3\xb1\x64\x13\x02\x01\x00" }   // WB stage-2 residual iCDFs, 8 x 9

fn silk_tbl_nlsf_ext_icdf() -> str { ret "d(\x10\x07\x03\x01\x00" }   // stage-2 extension iCDF

fn silk_tbl_nlsf_interp_icdf() -> str { ret "\xf3\xdd\xc0\xb5\x00" }   // NLSF interpolation factor iCDF

fn silk_tbl_ltp_per_icdf() -> str { ret "\xb3\x63\x00" }   // LTP periodicity index iCDF

fn silk_tbl_ltp_icdf0() -> str { ret "G8+\x1e\x15\x0c\x06\x00" }   // LTP filter index iCDF, periodicity 0

fn silk_tbl_ltp_icdf1() -> str { ret "\xc7\xa5\x90|m`TG=3* \x17\x0f\x08\x00" }   // LTP filter index iCDF, periodicity 1

fn silk_tbl_ltp_icdf2() -> str { ret "\xf1\xe1\xd3\xc7\xbb\xaf\xa4\x99\x8e\x84{ri`XPH@92,&!\x1d\x18\x14\x10\x0c\x09\x05\x02\x00" }   // LTP filter index iCDF, periodicity 2

fn silk_tbl_ltp_scale_icdf() -> str { ret "\x80@\x00" }   // LTP scaling iCDF

fn silk_tbl_pitch_lag_icdf() -> str { ret "\xfd\xfa\xf4\xe9\xd4\xb6\x96\x83xnbUH<1( \x19\x13\x0f\x0d\x0b\x09\x08\x07\x06\x05\x04\x03\x02\x01\x00" }   // primary pitch lag high part iCDF

fn silk_tbl_pitch_delta_icdf() -> str { ret "\xd2\xd0\xce\xcb\xc7\xc1\xb7\xa8\x8ehJ4%\x1b\x14\x0e\x0a\x06\x04\x02\x00" }   // pitch lag delta iCDF

fn silk_tbl_contour_icdf_nb_4() -> str { ret "\xbc\xb0\x9b\x8awaC+\x1a\x0a\x00" }   // pitch contour iCDF, NB 20 ms

fn silk_tbl_contour_icdf_nb_2() -> str { ret "q?\x00" }   // pitch contour iCDF, NB 10 ms

fn silk_tbl_contour_icdf_4() -> str { ret "\xdf\xc9\xb7\xa7\x98\x8a|obXOF>82,'#\x1f\x1b\x18\x15\x12\x10\x0e\x0c\x0a\x08\x06\x04\x03\x02\x01\x00" }   // pitch contour iCDF, MB/WB 20 ms

fn silk_tbl_contour_icdf_2() -> str { ret "\xa5wP=/#\x1b\x14\x0e\x09\x04\x00" }   // pitch contour iCDF, MB/WB 10 ms

fn silk_tbl_gain_icdf() -> str { ret "\xe0p,\x0f\x03\x02\x01\x00\xfe\xed\xc0\x84\x46\x17\x04\x00\xff\xfc\xe2\x9b=\x0b\x02\x00" }   // independent gain MSB iCDFs, 3 x 8

fn silk_tbl_delta_gain_icdf() -> str { ret "\xfa\xf5\xea\xcbG2*&#!\x1f\x1d\x1c\x1b\x1a\x19\x18\x17\x16\x15\x14\x13\x12\x11\x10\x0f\x0e\x0d\x0c\x0b\x0a\x09\x08\x07\x06\x05\x04\x03\x02\x01\x00" }   // delta gain iCDF

fn silk_tbl_rate_level_icdf() -> str { ret "\xf1\xbe\xb2\x84WJ)\x0e\x00\xdf\xc1\x9d\x8cj9'\x12\x00" }   // rate level iCDFs, 2 x 9

fn silk_tbl_pulses_icdf() -> str { ret "}3\x1a\x12\x0f\x0c\x0b\x0a\x09\x08\x07\x06\x05\x04\x03\x02\x01\x00\xc6i-\x16\x0f\x0c\x0b\x0a\x09\x08\x07\x06\x05\x04\x03\x02\x01\x00\xd5\xa2tS;+ \x18\x12\x0f\x0c\x09\x07\x06\x05\x03\x02\x00\xef\xbbt;\x1c\x10\x0b\x0a\x09\x08\x07\x06\x05\x04\x03\x02\x01\x00\xfa\xe5\xbc\x87V3\x1e\x13\x0d\x0a\x08\x06\x05\x04\x03\x02\x01\x00\xf9\xeb\xd5\xb9\x9c\x80gSB5*!\x1a\x15\x11\x0d\x0a\x00\xfe\xf9\xeb\xce\xa4vM.\x1b\x10\x0a\x07\x05\x04\x03\x02\x01\x00\xff\xfd\xf9\xef\xdc\xbf\x9cwU9%\x17\x0f\x0a\x06\x04\x02\x00\xff\xfd\xfb\xf6\xed\xdf\xcb\xb3\x98|bK7(\x1d\x15\x0f\x00\xff\xfe\xfd\xf7\xdc\xa2jC*\x1c\x12\x0c\x09\x06\x04\x03\x02\x00" }   // pulse count iCDFs, 10 x 18

fn silk_tbl_shell0() -> str { ret "\x80\x00\xd6*\x00\xeb\x80\x15\x00\xf4\xb8H\x0b\x00\xf8\xd6\x80*\x07\x00\xf8\xe1\xaaP\x19\x05\x00\xfb\xec\xc6~6\x12\x03\x00\xfa\xee\xd3\x9fR#\x0f\x05\x00\xfa\xe7\xcb\xa8\x80X5\x19\x06\x00\xfc\xee\xd8\xb9\x94lG(\x12\x04\x00\xfd\xf3\xe1\xc7\xa6\x80Z9\x1f\x0d\x03\x00\xfe\xf6\xe9\xd4\xb7\x93mI,\x17\x0a\x02\x00\xff\xfa\xf0\xdf\xc6\xa6\x80Z:!\x10\x06\x01\x00\xff\xfb\xf4\xe7\xd2\xb5\x92nK.\x19\x0c\x05\x01\x00\xff\xfd\xf8\xee\xdd\xc4\xa4\x80\\<#\x12\x08\x03\x01\x00\xff\xfd\xf9\xf2\xe5\xd0\xb4\x92nL0\x1b\x0e\x07\x03\x01\x00" }   // shell split iCDFs, level 0

fn silk_tbl_shell1() -> str { ret "\x81\x00\xcf\x32\x00\xec\x81\x14\x00\xf5\xb9H\x0a\x00\xf9\xd5\x81*\x06\x00\xfa\xe2\xa9W\x1b\x04\x00\xfb\xe9\xc2\x82>\x14\x04\x00\xfa\xec\xcf\xa0\x63/\x11\x03\x00\xff\xf0\xd9\xb6\x83Q)\x0b\x01\x00\xff\xfe\xe9\xc9\x9fk=\x14\x02\x01\x00\xff\xf9\xe9\xce\xaa\x80V2\x17\x07\x01\x00\xff\xfa\xee\xd9\xba\x94lF'\x12\x06\x01\x00\xff\xfc\xf3\xe2\xc8\xa6\x80Z8\x1e\x0d\x04\x01\x00\xff\xfc\xf5\xe7\xd1\xb4\x92nL/\x19\x0b\x04\x01\x00\xff\xfd\xf8\xed\xdb\xc2\xa3\x80]>%\x13\x08\x03\x01\x00\xff\xfe\xfa\xf1\xe2\xcd\xb1\x91oO3\x1e\x0f\x06\x02\x01\x00" }   // shell split iCDFs, level 1

fn silk_tbl_shell2() -> str { ret "\x81\x00\xcb\x36\x00\xea\x81\x17\x00\xf5\xb8I\x0a\x00\xfa\xd7\x81)\x05\x00\xfc\xe8\xadV\x18\x03\x00\xfd\xf0\xc8\x81\x38\x0f\x02\x00\xfd\xf4\xd9\xa4^&\x0a\x01\x00\xfd\xf5\xe2\xbd\x84G\x1b\x07\x01\x00\xfd\xf6\xe7\xcb\x9fi8\x17\x06\x01\x00\xff\xf8\xeb\xd5\xb3\x85U/\x13\x05\x01\x00\xff\xfe\xf3\xdd\xc2\x9fuF%\x0c\x02\x01\x00\xff\xfe\xf8\xea\xd0\xab\x80U0\x16\x08\x02\x01\x00\xff\xfe\xfa\xf0\xdc\xbd\x95kC$\x10\x06\x02\x01\x00\xff\xfe\xfb\xf3\xe3\xc9\xa6\x80Z7\x1d\x0d\x05\x02\x01\x00\xff\xfe\xfc\xf6\xea\xd5\xb7\x93mI+\x16\x0a\x04\x02\x01\x00" }   // shell split iCDFs, level 2

fn silk_tbl_shell3() -> str { ret "\x82\x00\xc8:\x00\xe7\x82\x1a\x00\xf4\xb8L\x0c\x00\xf9\xd6\x82+\x06\x00\xfc\xe8\xadW\x18\x03\x00\xfd\xf1\xcb\x83\x38\x0e\x02\x00\xfe\xf6\xdd\xa7^#\x08\x01\x00\xfe\xf9\xe8\xc1\x82\x41\x17\x05\x01\x00\xff\xfb\xef\xd3\xa2\x63-\x0f\x04\x01\x00\xff\xfb\xf3\xdf\xba\x83J!\x0b\x03\x01\x00\xff\xfc\xf5\xe6\xca\x9ei9\x18\x08\x02\x01\x00\xff\xfd\xf7\xeb\xd6\xb3\x84T,\x13\x07\x02\x01\x00\xff\xfe\xfa\xf0\xdf\xc4\x9fpE$\x0f\x06\x02\x01\x00\xff\xfe\xfd\xf5\xe7\xd1\xb0\x88]7\x1b\x0b\x03\x02\x01\x00\xff\xfe\xfd\xfc\xef\xdd\xc2\x9euL*\x12\x04\x03\x02\x01\x00" }   // shell split iCDFs, level 3

fn silk_tbl_shell_off() -> str { ret "\x00\x00\x02\x05\x09\x0e\x14\x1b#,6AMZhw\x87" }   // offset of each pulse count in the shell tables

fn silk_tbl_sign_icdf() -> str { ret "\xfe\x31\x43MR]c\xc6\x0b\x12\x18\x1f$-\xff.BNW^h\xd0\x0e\x15 *3B\xff^hmpsv\xf8\x35\x45PX_f" }   // excitation sign iCDFs, 6 x 7

fn silk_tbl_lsb_icdf() -> str { ret "x\x00" }   // excitation LSB iCDF

fn silk_tbl_type_offset_vad_icdf() -> str { ret "\xe8\x9e\x0a\x00" }   // frame type iCDF, VAD active

fn silk_tbl_type_offset_no_vad_icdf() -> str { ret "\xe6\x00" }   // frame type iCDF, VAD inactive

fn silk_tbl_uniform3_icdf() -> str { ret "\xabU\x00" }   // uniform 3 iCDF

fn silk_tbl_uniform4_icdf() -> str { ret "\xc0\x80@\x00" }   // uniform 4 iCDF

fn silk_tbl_uniform5_icdf() -> str { ret "\xcd\x9a\x66\x33\x00" }   // uniform 5 iCDF

fn silk_tbl_uniform6_icdf() -> str { ret "\xd5\xab\x80U+\x00" }   // uniform 6 iCDF

fn silk_tbl_uniform8_icdf() -> str { ret "\xe0\xc0\xa0\x80`@ \x00" }   // uniform 8 iCDF

fn silk_tbl_stereo_joint_icdf() -> str { ret "\xf9\xf7\xf6\xf5\xf4\xea\xd2\xca\xc9\xc8\xc5\xaeR;876.\x16\x0c\x0b\x0a\x09\x07\x00" }   // stereo weight joint index iCDF

fn silk_tbl_stereo_mid_icdf() -> str { ret "@\x00" }   // mid-only flag iCDF

fn silk_tbl_lbrr2_icdf() -> str { ret "\xcb\x96\x00" }   // LBRR flag iCDF, 2 SILK frames

fn silk_tbl_lbrr3_icdf() -> str { ret "\xd7\xc3\xa6}nR\x00" }   // LBRR flag iCDF, 3 SILK frames

fn silk_tbl_order10() -> str { ret "\x00\x09\x06\x03\x04\x05\x08\x01\x02\x07" }   // NLSF to LPC reordering, order 10

fn silk_tbl_order16() -> str { ret "\x00\x0f\x08\x07\x04\x0b\x0c\x03\x02\x0d\x0a\x05\x06\x09\x0e\x01" }   // NLSF to LPC reordering, order 16

fn silk_tbl_ltp_vq0() -> str { ret "\x04\x06\x18\x07\x05\x00\x00\x02\x00\x00\x0c\x1c)\x0d\xfc\xf7\x0f*\x19\x0e\x01\xfe>)\xf7\xf6%A\xfc\x03\xfa\x04\x42\x07\xf8\x10\x0e&\xfd!" }   // LTP filter codebook, periodicity 0, 8 x 5, Q7, signed

fn silk_tbl_ltp_vq1() -> str { ret "\x0d\x16'\x17\x0c\xff$@\x1b\xfa\xf9\x0a\x37+\x11\x01\x01\x08\x01\x01\x06\xf5J5\xf7\xf4\x37L\xf4\x08\xfd\x03]\x1b\xfc\x1a';\x03\xf8\x02\x00M\x0b\x09\xf8\x16,\xfa\x07(\x09\x1a\x03\x09\xf9\x14\x65\xf9\x04\x03\xf8*\x1a\x00\xf1!D\x02\x17\xfe\x37.\xfe\x0f\x03\xff\x15\x10)" }   // LTP filter codebook, periodicity 1, 16 x 5, Q7, signed

fn silk_tbl_ltp_vq2() -> str { ret "\xfa\x1b='\x05\xf5*X\x04\x01\xfe<A\x06\xfc\xff\xfbI8\x01\xf7\x13^\x1d\xf7\x00\x0c\x63\x06\x04\x08\xed\x66.\xf3\x03\x02\x0d\x03\x02\x09\xebTH\xee\xf5.h\xea\x08\x12&0\x17\x00\xf0\x46S\xeb\x0b\x05\xf5u\x16\xf8\xfa\x17u\xf4\x03\x03\xf8_\x1c\x04\xf6\x0fM<\xf1\xff\x04|\x02\xfc\x03&T\x18\xe7\x02\x0d*\x0d\x1f\x15\xfc\x38.\xff\xff#O\xf3\x13\xf9\x41X\xf7\xf2\x14\x04Q1\xe3\x14\x00K\x03\xef\x05\xf7,\\\xf8\x01\xfd\x16\x45\x1f\xfa_)\xf4\x05'C\x10\xfc\x01\x00\xfax7\xdc\xf3,z\x04\xe8Q\x05\x0b\x03\x07\x02\x00\x09\x0aX" }   // LTP filter codebook, periodicity 2, 32 x 5, Q7, signed

fn silk_tbl_lag_cb_nb_4() -> str { ret "\x00\x02\xff\xff\xff\x00\x00\x01\x01\x00\x01\x00\x01\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\xff\x02\x01\x00\x01\x01\x00\x00\xff\xff" }   // pitch contour codebook, NB 20 ms, 4 x 11, signed

fn silk_tbl_lag_cb_nb_2() -> str { ret "\x00\x01\x00\x00\x00\x01" }   // pitch contour codebook, NB 10 ms, 2 x 3, signed

fn silk_tbl_lag_cb_4() -> str { ret "\x00\x00\x01\xff\x00\x01\xff\x00\xff\x01\xfe\x02\xfe\xfe\x02\xfd\x02\x03\xfd\xfc\x03\xfc\x04\x04\xfb\x05\xfa\xfb\x06\xf9\x06\x05\x08\xf7\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\xff\x01\x00\x00\x01\xff\x00\x01\xff\xff\x01\xff\x02\x01\xff\x02\xfe\xfe\x02\xfe\x02\x02\x03\xfd\x00\x01\x00\x00\x00\x00\x00\x00\x01\x00\x01\x00\x00\x01\xff\x01\x00\x00\x02\x01\xff\x02\xff\xff\x02\xff\x02\x02\xff\x03\xfe\xfe\xfe\x03\x00\x01\x00\x00\x01\x00\x01\xff\x02\xff\x02\xff\x02\x03\xfe\x03\xfe\xfe\x04\x04\xfd\x05\xfd\xfc\x06\xfc\x06\x05\xfb\x08\xfa\xfb\xf9\x09" }   // pitch contour codebook, MB/WB 20 ms, 4 x 34, signed

fn silk_tbl_lag_cb_2() -> str { ret "\x00\x00\x01\xff\x01\xff\x02\xfe\x02\xfe\x03\xfd\x00\x01\x00\x01\xff\x02\xff\x02\xfe\x03\xfe\x03" }   // pitch contour codebook, MB/WB 10 ms, 2 x 12, signed

fn silk_tbl_nlsf_wght_nb_q9() -> str { ret "Q\x0b\x0a\x09\x0a\x09\x0a\x09\xef\x08\xef\x08\x0a\x09\xfc\x08\x17\x09\xef\x08H\x0b\x14\x0aZ\x09?\x09\x0a\x09\xe2\x08\xe2\x08\xe2\x08\xe2\x08\x92\x08\xb7\x09$\x09$\x09\x0a\x09\x0a\x09\x0a\x09$\x09$\x09?\x09\x32\x09\x90\x0c\xce\x0a$\x09$\x09\x0a\x09\xe2\x08\xad\x08\x9f\x08\xd5\x08\x92\x08\x9c\x09\xaa\x09?\x09Z\x09Z\x09Z\x09Z\x09?\x09g\x09\x0a\x09\x97\x0d\xf0\x0bO\x08\x9f\x08\xe2\x08\xe2\x08\xe2\x08\xef\x08\x0a\x09\xd5\x08\xd2\x0c\x45\x0c\x14\x0aZ\x09\xc7\x08\xad\x08\x9f\x08\x92\x08\x92\x08\x42\x08\x00\x10\x05\x0f\xad\x08<\x0a<\x0ag\x09\x0a\x09Z\x09?\x09\x1a\x08j\x0c\xac\x0c?\x09\xad\x08\xf9\x09\x82\x09$\x09\x0a\x09w\x08\xad\x08\x0a\x0d\xa0\x0d\xa6\x0a\x92\x08\xd5\x08\x9c\x09\x32\x09?\x09\x9f\x08\x35\x08\x32\x09t\x09\x17\x09?\x09Z\x09t\x09t\x09t\x09\x9c\x09?\x09\xc3\x0e-\x0e\x82\x09\xdf\x09?\x09\xe2\x08\xe2\x08\xfc\x08\x9f\x08\x00\x08\xb6\x0c\x99\x0c\x99\x0a\x1e\x0b\x8f\x09\x17\x09\xfc\x08\xfc\x08\xe2\x08O\x08\xbf\x0c\xe4\x0c\xc1\x0a\xf6\x0a\x8f\x09\xd5\x08\xd5\x08\xc7\x08O\x08\x35\x08\x39\x0b\xa5\x0bI\x0a?\x09g\x09\x32\x09\x92\x08\xc7\x08\xc7\x08\x42\x08\x99\x0c}\x0cI\x0a\x14\x0a\xe2\x08\x85\x08\xc7\x08\xad\x08\xad\x08]\x08j\x0c\xee\x0c\xb4\x0ag\x09\xe2\x08\xe2\x08\xe2\x08\xef\x08\x92\x08\x42\x08\x45\x0c\xc8\x0c\x9c\x09\x0d\x08\xef\x08\xc4\x09?\x09\xb7\x09\x82\x09\x85\x08\xb3\x0d\xd2\x0c\x0a\x09\x8c\x0aW\x0a\xaa\x09?\x09Z\x09$\x09O\x08_\x0d\xcf\x0d\xde\x0b\xf0\x0b\xfc\x08\x9e\x07\xad\x08\xe2\x08\xe2\x08\xe2\x08L\x0d&\x0d'\x08\x7f\x0a\x39\x0b\x32\x09t\x09\xe2\x08\xaa\x09\xec\x09\xb0\x0e\xa0\x0d\x9e\x07\x64\x0aQ\x0b\xdf\x09Z\x09?\x09\x9c\x09\xd5\x08\xd4\x0b\xc8\x0c\xb4\x0aH\x0b\xb4\x0aj\x08O\x08\xef\x08\xba\x08\xc7\x08o\x0eI\x0e\xe9\x07\xb1\x07\x64\x0a\x8c\x0a\x14\x0a\xc4\x09\x17\x09?\x09\x87\x0cU\x0d\x32\x09\x1a\x08H\x0bH\x0b$\x09\xb7\x09\xc7\x08w\x08\x0a\x0d&\x0d\x1e\x0b\xdc\x0a\x17\x09j\x08\xe2\x08\xef\x08\x42\x08\x0d\x08\x17\x09\xfc\x08\x85\x08w\x08\x85\x08?\x09I\x0a\x8c\x0a\x8c\x0a\xf9\x09g\x09\x82\x09\xad\x08\xd5\x08\xad\x08\xad\x08$\x09t\x09/\x0a\x8c\x0a\xde\x0b\xac\x0c\xf6\x0aH\x0b\xaa\x09\x1a\x08\xfc\x08\x0a\x09\x32\x09L\x09\xad\x08j\x08O\x08\xef\x08\xc4\x09\xe9\x0a\xe9\x0a<\x0a\x14\x0a?\x09\\\x0e\x81\x0e\xba\x08.\x07\x85\x08\xc1\x0a\xa6\x0aq\x0a\xd1\x09\x9f\x08\xe9\x0aX\x0c\xa6\x0a\xf9\x09\x1e\x0b\xd1\x09\x85\x08Z\x09\xad\x08\x85\x08" }   // NB/MB stage-1 weights, 32 x 10, Q9, little-endian pairs

fn silk_tbl_nlsf_wght_wb_q9() -> str { ret "I\x0em\x0bm\x0bm\x0bm\x0bm\x0bm\x0bm\x0bm\x0bm\x0bm\x0bm\x0b\x93\x0b\x93\x0bm\x0b\x1e\x0b\x90\x0c\x0d\x0c\x9c\x0b\xf0\x0b\xf0\x0b\xc2\x0b\xc2\x0b\xc2\x0b\x93\x0b\x93\x0b\xc2\x0b\x9c\x0bH\x0b\x1e\x0b\x1e\x0b\xa6\x0aP\x0f\xae\x0f\xa5\x0b\x87\x0c\x87\x0cv\x0b\xf0\x0b\x1e\x0b\x32\x0c\xac\x0cm\x0b\x1e\x0b<\x0a\xf9\x09\xdc\x0am\x0b\xbc\x0d}\x0c\xc2\x0b\x1f\x0c\xcb\x0bH\x0bm\x0bm\x0bm\x0bm\x0bH\x0bH\x0bH\x0bH\x0bH\x0b\xc1\x0a\xbe\x13\xbe\x13v\x0b\xf5\x0d\x39\x0d\xf0\x0b\x0d\x0c\xe9\x0aX\x0cX\x0c\x9c\x0b\x1e\x0b\xd1\x09\xec\x09\xc1\x0aH\x0bL\x11\x35\x10\x8c\x0a\xc1\x0a\x9c\x0b\xc2\x0bm\x0b\x1e\x0b\xa5\x0b\xcb\x0bm\x0bm\x0bm\x0bm\x0bH\x0b\xa6\x0a$\x0e\xcb\x0b\x9c\x0b\xf0\x0b\xf0\x0b\x39\x0b\xf6\x0a\xf0\x0b\x90\x0c\xe7\x0b\xa5\x0b\xdb\x0c\xdb\x0c\xa5\x0b\xee\x0c\xaf\x0bk\x14\x96\x13\xec\x09\x0a\x0d\xc6\x0d\x39\x0d}\x0c\x16\x0c\x30\x0d\xa5\x0b\x8c\x0aW\x0a\x7f\x0a\xe9\x0a\x1e\x0bq\x0a\xd9\x13\x36\x14\x07\x12L\x11\x9c\x09Q\x0b\xe7\x0b\x87\x0c\x61\x0c\x7f\x0a\xb4\x0aH\x0b\x1e\x0b\xe9\x0a\x1e\x0b\x8c\x0a\x32\x0cH\x0b\x93\x0bm\x0bm\x0bm\x0bm\x0b\x93\x0b\x93\x0b\x93\x0b\x93\x0bm\x0bm\x0b\x93\x0b\x93\x0b\x93\x0bj\x10\x87\x0c\xa5\x0b\x1f\x0c\xc2\x0bH\x0bH\x0bm\x0b\x9c\x0b\x39\x0b\x64\x0b\xcb\x0b\x9c\x0b\xc2\x0b}\x0c\x39\x0b\xb0\x0e\xb0\x0e\xac\x0c\x1f\x0c\xa5\x0bH\x0bm\x0bH\x0b\x9c\x0bv\x0b\xe9\x0a\xe9\x0a\x1e\x0bH\x0bH\x0b\x64\x0a\x0e\x0f\xae\x0f\x87\x0c\x32\x0c\xac\x0cv\x0b\xe7\x0b\x93\x0b\x93\x0b\x0d\x0c\x1e\x0b\xe9\x0a\xe9\x0a\xe9\x0a\xe9\x0a\x14\x0a\x05\x0f\xf0\x0f\x1d\x0d\xbc\x0d\x16\x0c\xb4\x0a\xc2\x0bv\x0b\x32\x0c\x0d\x0c\x1e\x0b\x1e\x0bW\x0aW\x0a\x1e\x0b\xf6\x0a\x1b\x14\x1e\x13\x99\x0c\x05\x0fq\x0d\x61\x0cQ\x0bU\x0d{\x0d\x8c\x0a\x14\x0aq\x0a\xb4\x0a\x1e\x0b\xf6\x0a\xc1\x0a\x0d\x10\xcd\x0e\xdb\x0cX\x0cm\x0bH\x0bH\x0bm\x0b\xe9\x0a\xb4\x0a\xe9\x0a\xb4\x0a\xe9\x0a\x1e\x0bH\x0b\xf6\x0a\xd9\x13\xbe\x13\xe7\x0b\xd9\x0d\xac\x0c\xf0\x0b\x0d\x0c\x80\x0b\x1f\x0cQ\x0b\xb4\x0a\xb4\x0a\xb4\x0a\x1e\x0b\xe9\x0a<\x0a\xd5\x10\xd5\x10,\x0b\xdf\x09\x87\x0c\x30\x0d\x30\x0d\x03\x0c\x03\x0c\x30\x0d\xf0\x0b\x1e\x0bW\x0a\x14\x0a\xa6\x0a\xc1\x0a\xf0\x0b\x64\x0b\xf6\x0aH\x0b\xb4\x0a\x7f\x0aQ\x0b\x1f\x0cN\x0cN\x0c\x90\x0c\x61\x0c\xf0\x0b\xc2\x0b\x93\x0b\x1e\x0b\x17\x11*\x0fm\x0bH\x0b\x1e\x0bH\x0b\x1e\x0b\x1e\x0bH\x0bH\x0bH\x0b\x1e\x0bH\x0bm\x0bH\x0b\x1e\x0b\xa5\x0b\x64\x0b\x64\x0b\xa5\x0b\xa5\x0b\xf0\x0b\x32\x0c\x90\x0cN\x0c\xf0\x0b\xc2\x0b\x9c\x0b\x9c\x0b\x9c\x0bm\x0b\xb4\x0a\x85\x10\x35\x10\xee\x0c\x13\x0dm\x0b\x93\x0bH\x0b\xa5\x0b\xa5\x0b\x1e\x0b\xe9\x0a\xb4\x0a\x1e\x0b\x1e\x0b\x1e\x0b\xe9\x0a\xf0\x0f\xae\x0f\x1f\x0c\xc2\x0bm\x0bm\x0bm\x0bH\x0bm\x0bm\x0b\x1e\x0b\x1e\x0b\x1e\x0b\xe9\x0aH\x0b\xdc\x0a\x07\x12\xdf\x11\x61\x0cq\x0d\x87\x0c\xa5\x0bQ\x0b\xde\x0b\x32\x0c\xb4\x0a\x7f\x0a\x7f\x0a\x7f\x0a\xb4\x0a\xe9\x0a\x8c\x0a\x35\x10\xad\x10\xcd\x0eI\x0e\xa6\x0a\xdc\x0aH\x0bH\x0b\xc2\x0b\x9c\x0bm\x0b\x1e\x0b\x7f\x0a\x7f\x0a\xe9\x0aH\x0bw\x10\xe2\x0d\xc1\x0a\x1e\x0b\x1e\x0bH\x0bH\x0bH\x0bm\x0bm\x0bH\x0bm\x0bm\x0bm\x0b\x93\x0bH\x0b\x36\x14\x39\x13\xd5\x08h\x0d\xcd\x0e\x97\x0d\x13\x0d\x1e\x0b\xee\x0c\x97\x0dN\x0cQ\x0b\x9c\x09\xb7\x09\xc1\x0am\x0b{\x0d\x65\x0e\x32\x0c}\x0c\x1d\x0d\xe7\x0b\x87\x0c\x87\x0c\xa5\x0b\x90\x0c\x0d\x0cm\x0bm\x0b\x7f\x0a\xec\x09\x82\x09\xa5\x0b\xc2\x0b\xe9\x0a\xe9\x0a\xb4\x0a\xe9\x0a\x1e\x0b\x9c\x0b\xf0\x0b\x1f\x0cN\x0cN\x0cN\x0c\x1f\x0c\xc2\x0b\xc2\x0b\x80\x0b\x39\x0b\x7f\x0a\xa6\x0a\xdc\x0a\xc2\x0bh\x0d\xd9\x0d\x1d\x0d\xac\x0c\xf0\x0b\xc2\x0b\x93\x0bm\x0bH\x0b\x1e\x0b\xcb\x0b\x80\x0bQ\x0b\xc2\x0b\xc2\x0b\x9c\x0b\xcb\x0b\x1f\x0c\xf0\x0b\xf0\x0b\xc2\x0bH\x0b\x1e\x0bm\x0bm\x0bH\x0bP\x0f\x7f\x0f\xc2\x0b}\x0c\x1d\x0d\x90\x0c\xdb\x0c\xdb\x0c\x97\x0dx\x0eq\x0d\xa6\x0a\x85\x08\x9c\x09\x14\x0a/\x0a" }   // WB stage-1 weights, 32 x 16, Q9, little-endian pairs

fn silk_tbl_nlsf_dmin_nb_q15() -> str { ret "\xfa\x00\x03\x00\x06\x00\x03\x00\x03\x00\x03\x00\x04\x00\x03\x00\x03\x00\x03\x00\xcd\x01" }   // NB/MB minimum NLSF spacing, Q15, little-endian pairs

fn silk_tbl_nlsf_dmin_wb_q15() -> str { ret "d\x00\x03\x00(\x00\x03\x00\x03\x00\x03\x00\x05\x00\x0e\x00\x0e\x00\x0a\x00\x0b\x00\x03\x00\x08\x00\x09\x00\x07\x00\x03\x00[\x01" }   // WB minimum NLSF spacing, Q15, little-endian pairs

fn silk_tbl_ltp_scale_q14() -> str { ret "\xcd<\x00\x30\x00 " }   // LTP scaling factors, Q14, little-endian pairs

fn silk_tbl_stereo_quant_q13() -> str { ret "\\\xca\xbe\xd8\xb6\xdf\x9a\xe2\x9c\xe6x\xecz\xf4\xcc\xfc\x34\x03\x86\x0b\x88\x13\x64\x19\x66\x1dJ B'\xa4\x35" }   // stereo prediction weight levels, Q13, little-endian pairs

fn silk_tbl_cos_q12() -> str { ret "\x00 \xfe\x1f\xf6\x1f\xea\x1f\xd8\x1f\xc2\x1f\xa8\x1f\x88\x1f\x62\x1f:\x1f\x0a\x1f\xd8\x1e\xa0\x1e\x62\x1e\"\x1e\xdc\x1d\x90\x1d\x42\x1d\xee\x1c\x96\x1c:\x1c\xd8\x1br\x1b\x0a\x1b\x9c\x1a*\x1a\xb4\x19:\x19\xbc\x18<\x18\xb6\x17.\x17\xa0\x16\x10\x16~\x15\xe8\x14N\x14\xb0\x13\x10\x13n\x12\xc8\x11\x1e\x11t\x10\xc6\x0f\x16\x0f\x64\x0e\xae\x0d\xf8\x0c@\x0c\x84\x0b\xc8\x0a\x0a\x0aJ\x09\x8a\x08\xc6\x07\x02\x07>\x06x\x05\xb2\x04\xea\x03\"\x03Z\x02\x92\x01\xca\x00\x00\x00\x36\xffn\xfe\xa6\xfd\xde\xfc\x16\xfcN\xfb\x88\xfa\xc2\xf9\xfe\xf8:\xf8v\xf7\xb6\xf6\xf6\xf5\x38\xf5|\xf4\xc0\xf3\x08\xf3R\xf2\x9c\xf1\xea\xf0:\xf0\x8c\xef\xe2\xee\x38\xee\x92\xed\xf0\xecP\xec\xb2\xeb\x18\xeb\x82\xea\xf0\xe9`\xe9\xd2\xe8J\xe8\xc4\xe7\x44\xe7\xc6\xe6L\xe6\xd6\xe5\x64\xe5\xf6\xe4\x8e\xe4(\xe4\xc6\xe3j\xe3\x12\xe3\xbe\xe2p\xe2$\xe2\xde\xe1\x9e\xe1`\xe1(\xe1\xf6\xe0\xc6\xe0\x9e\xe0x\xe0X\xe0>\xe0(\xe0\x16\xe0\x0a\xe0\x02\xe0\x00\xe0" }   // 2*cos() table for the NLSF to LPC conversion, Q12, little-endian pairs

// ---- resampler tables, emitted by the fixture generator from silk/resampler_rom.c ----

fn silk_tbl_rs_up2() -> str { ret "\xd2\x06\x8a:\xab\x98\xc6\x1a\xa9\x64\xf6\xd8" }   // 2x upsampler allpass coefficients, 2 x 3, little-endian pairs

fn silk_tbl_rs_frac12() -> str { ret "\xbd\x00\xa8\xfdi\x02gwu\x00\x61\xff\xd2\xfb\x08t4\x00\xdd\x00\xa8\xf6tn\xfc\xff\x11\x02\xea\xf2\xe5\x66\xd0\xff\xf6\x02\x8c\xf0\xa5]\xb0\xff\x89\x03u\xef\x06S\x9d\xff\xcc\x03\x82\xef\x66G\x95\xff\xc7\x03\x8b\xf0';\x99\xff\x80\x03\x61\xf2\xae.\xa5\xff\x05\x03\xcf\xf4^\"\xb9\xff\x63\x02\xa1\xf7\x98\x16\xd2\xff\xa9\x01\xa1\xfa\xb4\x0b" }   // FIR interpolation fractions, 12 x 4, little-endian pairs

fn silk_tbl_rs_3_4() -> str { ret "*\xaf\xd5\xc9\xcf\xff@\x00\x11\x00\x63\xff\x61\x01\x10\xfe\xa3\x00'+\xbdV\xd9\xff\x06\x00[\x00V\xff\xba\x00\x17\x00\x80\xfc\xc0\x18\xd8M\xed\xff\xdc\xff\x66\x00\xa7\xff\xe8\xffH\x01I\xfc\x08\x0a%>" }   // 3:4 downsampler, 2 AR2 + 3 x 9 FIR, little-endian pairs

fn silk_tbl_rs_2_3() -> str { ret "\x87\xc7=\xc9@\x00\x80\x00\x86\xff$\x00\x36\x01\x00\xfdH\x02\x33$EE\x0c\x00\x80\x00\x12\x00r\xff \x01\x8b\xff\x9f\xfc\x1b\x10{8" }   // 2:3 downsampler, 2 AR2 + 2 x 9 FIR, little-endian pairs

fn silk_tbl_rs_1_2() -> str { ret "h\x02\x0d\xc8\xf6\xff'\x00:\x00\xd2\xff\xac\xffx\x00\xb8\x00\xc5\xfe\xe3\xfd\x04\x05\x04\x15@#" }   // 1:2 downsampler, 2 AR2 + 12 FIR, little-endian pairs

fn silk_tbl_rs_delay() -> str { ret "\x04\x00\x02\x00\x00\x00\x09\x04\x07\x04\x00\x03\x0c\x07\x07" }   // decoder delay matrix, 3 in rates x 5 out rates
