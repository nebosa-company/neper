// Unicode transformation formats, streamed: UTF-8 in, and UTF-16 and UTF-32 in either
// byte order, out to UTF-8 and back. A decoder carries the bytes of an unfinished
// scalar between calls and an encoder remembers whether its BOM is out, so a stream
// can be fed in any pieces. Every invalid sequence is one decision: `Reject` says
// `Invalid`, `Replace` writes U+FFFD once for the maximal invalid subsequence and
// goes on. Nothing here knows a locale or a legacy code page, on purpose.

use e.mem

type Encoding = enum u8 { Utf8, Utf16Le, Utf16Be, Utf32Le, Utf32Be }
type InvalidPolicy = enum u8 { Reject, Replace }
type Decoder = struct { encoding: Encoding, policy: InvalidPolicy, pending: [4]u8, pending_len: u8, bom_seen: bool }
type Encoder = struct { encoding: Encoding, emit_bom: bool, started: bool }
error Invalid
error Incomplete
error TooSmall

const REPLACEMENT: u32 = 65533u32

fn detect_bom(src: []const u8) -> (Encoding, usize, bool) {
    if src.len >= 4usize && src[0] == 255u8 && src[1] == 254u8 && src[2] == 0u8 && src[3] == 0u8 { ret (.Utf32Le, 4usize, true) }
    if src.len >= 4usize && src[0] == 0u8 && src[1] == 0u8 && src[2] == 254u8 && src[3] == 255u8 { ret (.Utf32Be, 4usize, true) }
    if src.len >= 3usize && src[0] == 239u8 && src[1] == 187u8 && src[2] == 191u8 { ret (.Utf8, 3usize, true) }
    if src.len >= 2usize && src[0] == 255u8 && src[1] == 254u8 { ret (.Utf16Le, 2usize, true) }
    if src.len >= 2usize && src[0] == 254u8 && src[1] == 255u8 { ret (.Utf16Be, 2usize, true) }
    ret (.Utf8, 0usize, false)
}

fn decoder(encoding: Encoding, policy: InvalidPolicy, consume_bom: bool) -> Decoder {
    var d: Decoder = zero
    d.encoding = encoding
    d.policy = policy
    d.bom_seen = !consume_bom
    ret d
}

fn encoder(encoding: Encoding, emit_bom: bool) -> Encoder {
    var e: Encoder = zero
    e.encoding = encoding
    e.emit_bom = emit_bom
    ret e
}

// How many bytes one code unit of the encoding takes.
fn unit_size(encoding: Encoding) -> usize {
    if encoding == .Utf8 { ret 1usize }
    if encoding == .Utf16Le || encoding == .Utf16Be { ret 2usize }
    ret 4usize
}

fn bom_length(encoding: Encoding) -> usize {
    if encoding == .Utf8 { ret 3usize }
    ret unit_size(encoding)
}

fn utf8_length(scalar: u32) -> usize {
    if scalar < 128u32 { ret 1usize }
    if scalar < 2048u32 { ret 2usize }
    if scalar < 65536u32 { ret 3usize }
    ret 4usize
}

fn write_utf8(scalar: u32, dst: []u8, at: usize) -> usize {
    if scalar < 128u32 {
        dst[at] = u8(scalar)
        ret 1usize
    }
    if scalar < 2048u32 {
        dst[at] = u8(192u32 | (scalar >> 6u32))
        dst[at + 1usize] = u8(128u32 | (scalar & 63u32))
        ret 2usize
    }
    if scalar < 65536u32 {
        dst[at] = u8(224u32 | (scalar >> 12u32))
        dst[at + 1usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
        dst[at + 2usize] = u8(128u32 | (scalar & 63u32))
        ret 3usize
    }
    dst[at] = u8(240u32 | (scalar >> 18u32))
    dst[at + 1usize] = u8(128u32 | ((scalar >> 12u32) & 63u32))
    dst[at + 2usize] = u8(128u32 | ((scalar >> 6u32) & 63u32))
    dst[at + 3usize] = u8(128u32 | (scalar & 63u32))
    ret 4usize
}

// One scalar from UTF-8 at `src[at..]`: the scalar, the bytes it took, and a verdict --
// 0 a scalar, 1 an invalid sequence of `taken` bytes (the maximal subsequence), 2 too
// short to tell.
fn read_utf8(src: []const u8, at: usize) -> (u32, usize, u8) {
    let lead = src[at]
    if lead < 128u8 { ret (u32(lead), 1usize, 0u8) }
    var need = 0usize
    var scalar = 0u32
    var floor = 0u32
    if lead >= 194u8 && lead <= 223u8 {
        need = 1usize
        scalar = u32(lead & 31u8)
        floor = 128u32
    } else {
        if lead >= 224u8 && lead <= 239u8 {
            need = 2usize
            scalar = u32(lead & 15u8)
            floor = 2048u32
        } else {
            if lead >= 240u8 && lead <= 244u8 {
                need = 3usize
                scalar = u32(lead & 7u8)
                floor = 65536u32
            } else {
                ret (0u32, 1usize, 1u8)
            }
        }
    }
    var taken = 1usize
    while taken <= need {
        if at + taken >= src.len { ret (0u32, taken, 2u8) }
        let next = src[at + taken]
        if next < 128u8 || next > 191u8 { ret (0u32, taken, 1u8) }
        scalar = (scalar << 6u32) | u32(next & 63u8)
        taken += 1usize
    }
    // ponytail: an overlong form or a surrogate is judged once the sequence is complete,
    // so its invalid subsequence is the whole sequence rather than Unicode's shortest.
    // One U+FFFD instead of two or three; the text is the same otherwise.
    if scalar < floor || scalar > 1114111u32 || (scalar >= 55296u32 && scalar <= 57343u32) { ret (0u32, taken, 1u8) }
    ret (scalar, taken, 0u8)
}

fn read_unit(src: []const u8, at: usize, encoding: Encoding) -> u32 {
    let b0 = u32(src[at])
    let b1 = u32(src[at + 1usize])
    if encoding == .Utf16Le { ret b0 | (b1 << 8u32) }
    if encoding == .Utf16Be {
        let high_first = (b0 << 8u32) | b1
        ret high_first
    }
    let b2 = u32(src[at + 2usize])
    let b3 = u32(src[at + 3usize])
    if encoding == .Utf32Le { ret b0 | (b1 << 8u32) | (b2 << 16u32) | (b3 << 24u32) }
    let big = (b0 << 24u32) | (b1 << 16u32) | (b2 << 8u32) | b3
    ret big
}

fn write_unit(unit: u32, dst: []u8, at: usize, encoding: Encoding) {
    if encoding == .Utf16Le {
        dst[at] = u8(unit & 255u32)
        dst[at + 1usize] = u8((unit >> 8u32) & 255u32)
        ret
    }
    if encoding == .Utf16Be {
        dst[at] = u8((unit >> 8u32) & 255u32)
        dst[at + 1usize] = u8(unit & 255u32)
        ret
    }
    if encoding == .Utf32Le {
        dst[at] = u8(unit & 255u32)
        dst[at + 1usize] = u8((unit >> 8u32) & 255u32)
        dst[at + 2usize] = u8((unit >> 16u32) & 255u32)
        dst[at + 3usize] = u8(unit >> 24u32)
        ret
    }
    dst[at] = u8(unit >> 24u32)
    dst[at + 1usize] = u8((unit >> 16u32) & 255u32)
    dst[at + 2usize] = u8((unit >> 8u32) & 255u32)
    dst[at + 3usize] = u8(unit & 255u32)
}

// One scalar from a 16- or 32-bit encoding: the same three-way verdict as `read_utf8`.
fn read_wide(src: []const u8, at: usize, encoding: Encoding) -> (u32, usize, u8) {
    let width = unit_size(encoding)
    if at + width > src.len { ret (0u32, src.len - at, 2u8) }
    let unit = read_unit(src, at, encoding)
    if width == 4usize {
        if unit > 1114111u32 || (unit >= 55296u32 && unit <= 57343u32) { ret (0u32, 4usize, 1u8) }
        ret (unit, 4usize, 0u8)
    }
    if unit < 55296u32 || unit > 57343u32 { ret (unit, 2usize, 0u8) }
    if unit >= 56320u32 { ret (0u32, 2usize, 1u8) }
    if at + 4usize > src.len { ret (0u32, src.len - at, 2u8) }
    let low = read_unit(src, at + 2usize, encoding)
    if low < 56320u32 || low > 57343u32 { ret (0u32, 2usize, 1u8) }
    let scalar = 65536u32 + ((unit - 55296u32) << 10u32) + (low - 56320u32)
    ret (scalar, 4usize, 0u8)
}

// Decodes from `src` into UTF-8 in `dst_utf8`: (consumed, written, err). The bytes of a
// trailing partial scalar are kept in the decoder unless `final`, when they are
// `Incomplete`. `TooSmall` leaves the scalar that did not fit for the next call. A BOM
// is looked for once, at the very start of the stream, and only in the first call's
// bytes -- a BOM split across calls is read as text.
fn decode(d: *Decoder, src: []const u8, dst_utf8: []u8, final: bool) -> (usize, usize, err) {
    var consumed = 0usize
    var written = 0usize
    if !d.bom_seen {
        d.bom_seen = true
        let (bom, bom_len, has_bom) = detect_bom(src)
        if has_bom && bom == d.encoding { consumed = bom_len }
    }
    // A scalar begun in the last call is finished from the front of this one.
    if d.pending_len != 0u8 {
        let old = usize(d.pending_len)
        var held: [8]u8 = zero
        var at = 0usize
        while at < old {
            held[at] = d.pending[at]
            at += 1usize
        }
        var extra = 0usize
        while old + extra < 8usize && consumed + extra < src.len {
            held[old + extra] = src[consumed + extra]
            extra += 1usize
        }
        let (scalar, taken, verdict) = read_any(held[..old + extra], 0usize, d.encoding)
        if verdict == 2u8 {
            if !final {
                at = 0usize
                while at < taken {
                    d.pending[at] = held[at]
                    at += 1usize
                }
                d.pending_len = u8(taken)
                ret (consumed + (taken - old), written, ok)
            }
            if d.policy == .Reject { ret (consumed, written, Incomplete) }
        }
        var out = scalar
        if verdict != 0u8 {
            if d.policy == .Reject { ret (consumed, written, Invalid) }
            out = REPLACEMENT
        }
        if written + utf8_length(out) > dst_utf8.len { ret (consumed, written, TooSmall) }
        written += write_utf8(out, dst_utf8, written)
        consumed += taken - old
        d.pending_len = 0u8
    }
    while consumed < src.len {
        let (scalar, taken, verdict) = read_any(src, consumed, d.encoding)
        if verdict == 2u8 {
            if !final {
                var keep = 0usize
                while keep < taken {
                    d.pending[keep] = src[consumed + keep]
                    keep += 1usize
                }
                d.pending_len = u8(taken)
                ret (consumed + taken, written, ok)
            }
            if d.policy == .Reject { ret (consumed, written, Incomplete) }
        }
        var out = scalar
        if verdict != 0u8 {
            if d.policy == .Reject { ret (consumed, written, Invalid) }
            out = REPLACEMENT
        }
        if written + utf8_length(out) > dst_utf8.len { ret (consumed, written, TooSmall) }
        written += write_utf8(out, dst_utf8, written)
        consumed += taken
    }
    ret (consumed, written, ok)
}

fn read_any(src: []const u8, at: usize, encoding: Encoding) -> (u32, usize, u8) {
    if encoding == .Utf8 {
        let (scalar, taken, verdict) = read_utf8(src, at)
        ret (scalar, taken, verdict)
    }
    let (scalar, taken, verdict) = read_wide(src, at, encoding)
    ret (scalar, taken, verdict)
}

// Encodes UTF-8 into the encoder's format: (consumed, written, err). An invalid UTF-8
// sequence in the source is `Invalid`; a partial one at the end is `Incomplete` when
// `final` and otherwise left unconsumed for the next call.
fn encode(e: *Encoder, src_utf8: str, dst: []u8, final: bool) -> (usize, usize, err) {
    var consumed = 0usize
    var written = 0usize
    if e.emit_bom && !e.started {
        let bom_len = bom_length(e.encoding)
        if bom_len > dst.len { ret (0usize, 0usize, TooSmall) }
        if e.encoding == .Utf8 {
            dst[0] = 239u8
            dst[1] = 187u8
            dst[2] = 191u8
        } else {
            write_unit(65279u32, dst, 0usize, e.encoding)
        }
        written = bom_len
        e.started = true
    }
    e.started = true
    while consumed < src_utf8.len {
        let (scalar, taken, verdict) = read_utf8(src_utf8, consumed)
        if verdict == 2u8 {
            if final { ret (consumed, written, Incomplete) }
            ret (consumed, written, ok)
        }
        if verdict == 1u8 { ret (consumed, written, Invalid) }
        var need = 0usize
        if e.encoding == .Utf8 { need = taken }
        if e.encoding == .Utf16Le || e.encoding == .Utf16Be {
            need = 2usize
            if scalar >= 65536u32 { need = 4usize }
        }
        if e.encoding == .Utf32Le || e.encoding == .Utf32Be { need = 4usize }
        if written + need > dst.len { ret (consumed, written, TooSmall) }
        if e.encoding == .Utf8 {
            var copy = 0usize
            while copy < taken {
                dst[written + copy] = src_utf8[consumed + copy]
                copy += 1usize
            }
        } else {
            if need == 4usize && unit_size(e.encoding) == 2usize {
                let offset = scalar - 65536u32
                write_unit(55296u32 + (offset >> 10u32), dst, written, e.encoding)
                write_unit(56320u32 + (offset & 1023u32), dst, written + 2usize, e.encoding)
            } else {
                write_unit(scalar, dst, written, e.encoding)
            }
        }
        written += need
        consumed += taken
    }
    ret (consumed, written, ok)
}

fn decoded_len(encoding: Encoding, src: []const u8, policy: InvalidPolicy) -> (usize, err) {
    var total = 0usize
    var at = 0usize
    let (bom, bom_len, has_bom) = detect_bom(src)
    if has_bom && bom == encoding { at = bom_len }
    while at < src.len {
        var (scalar, taken, verdict) = read_any(src, at, encoding)
        if verdict == 2u8 {
            if policy == .Reject { ret (0usize, Incomplete) }
            scalar = REPLACEMENT
        }
        if verdict == 1u8 {
            if policy == .Reject { ret (0usize, Invalid) }
            scalar = REPLACEMENT
        }
        total += utf8_length(scalar)
        at += taken
    }
    ret (total, ok)
}

fn encoded_len(encoding: Encoding, src_utf8: str, emit_bom: bool) -> (usize, err) {
    var total = 0usize
    if emit_bom { total = bom_length(encoding) }
    var at = 0usize
    while at < src_utf8.len {
        let (scalar, taken, verdict) = read_utf8(src_utf8, at)
        if verdict == 2u8 { ret (0usize, Incomplete) }
        if verdict == 1u8 { ret (0usize, Invalid) }
        if encoding == .Utf8 { total += taken }
        if encoding == .Utf16Le || encoding == .Utf16Be {
            total += 2usize
            if scalar >= 65536u32 { total += 2usize }
        }
        if encoding == .Utf32Le || encoding == .Utf32Be { total += 4usize }
        at += taken
    }
    ret (total, ok)
}

fn to_utf8(a: *mem.Arena, encoding: Encoding, src: []const u8, policy: InvalidPolicy) -> (str, err) {
    let (length, length_error) = decoded_len(encoding, src, policy)
    if length_error != ok { ret ("", length_error) }
    let (buffer, buffer_error) = mem.alloc[u8](a, length)
    if buffer_error != ok { ret ("", buffer_error) }
    var d = decoder(encoding, policy, true)
    let (_, written, decode_error) = decode(&d, src, buffer[0..], true)
    if decode_error != ok { ret ("", decode_error) }
    ret (buffer[..written], ok)
}

fn from_utf8(a: *mem.Arena, encoding: Encoding, src: str, emit_bom: bool) -> ([]u8, err) {
    let (length, length_error) = encoded_len(encoding, src, emit_bom)
    if length_error != ok { ret (zero, length_error) }
    let (buffer, buffer_error) = mem.alloc[u8](a, length)
    if buffer_error != ok { ret (zero, buffer_error) }
    var e = encoder(encoding, emit_bom)
    let (_, written, encode_error) = encode(&e, src, buffer[0..], true)
    if encode_error != ok { ret (zero, encode_error) }
    ret (buffer[..written], ok)
}

// Charset detection among the encodings this module decodes: a BOM decides
// outright (100); else the zero-byte pattern of the wide forms -- UTF-32 has three
// zeros in most quads, UTF-16 a zero in every other byte of Latin text -- names one
// when the bytes also decode strictly (80 and 70); else strict UTF-8 validity (90
// with multibyte sequences, 60 for pure ASCII, which every ASCII superset shares).
// Confidence 0 with `Utf8` means a single-byte legacy page: bytes past 0x7F that
// are not UTF-8, which nothing here decodes. ponytail: no byte-frequency profile
// between Latin-1 and Windows-1252 -- there is no decoder for either to hand the
// answer to; add one with the decoders if they come.
type Guess = struct { encoding: Encoding, confidence: u8 }

fn decodes(encoding: Encoding, src: []const u8) -> bool {
    let (_, verdict) = decoded_len(encoding, src, .Reject)
    ret verdict == ok
}

fn detect(src: []const u8) -> Guess {
    let (bom, _, has_bom) = detect_bom(src)
    if has_bom { ret Guess { encoding: bom, confidence: 100u8 } }
    if src.len == 0usize { ret Guess { encoding: .Utf8, confidence: 50u8 } }
    var zeros: [4]usize = zero
    var high = false
    var i = 0usize
    while i < src.len {
        if src[i] == 0u8 { zeros[i % 4usize] += 1usize }
        if src[i] >= 128u8 { high = true }
        i += 1usize
    }
    let quads = src.len / 4usize
    if src.len % 4usize == 0usize && quads > 0usize {
        if zeros[2] == quads && zeros[3] == quads && zeros[0] < quads && decodes(.Utf32Le, src) { ret Guess { encoding: .Utf32Le, confidence: 80u8 } }
        if zeros[0] == quads && zeros[1] == quads && zeros[3] < quads && decodes(.Utf32Be, src) { ret Guess { encoding: .Utf32Be, confidence: 80u8 } }
    }
    let even = zeros[0] + zeros[2]
    let odd = zeros[1] + zeros[3]
    if src.len % 2usize == 0usize {
        if odd > 0usize && odd > 4usize * even && decodes(.Utf16Le, src) { ret Guess { encoding: .Utf16Le, confidence: 70u8 } }
        if even > 0usize && even > 4usize * odd && decodes(.Utf16Be, src) { ret Guess { encoding: .Utf16Be, confidence: 70u8 } }
    }
    if decodes(.Utf8, src) {
        if high { ret Guess { encoding: .Utf8, confidence: 90u8 } }
        ret Guess { encoding: .Utf8, confidence: 60u8 }
    }
    ret Guess { encoding: .Utf8, confidence: 0u8 }
}
