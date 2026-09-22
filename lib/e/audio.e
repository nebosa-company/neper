// Interleaved PCM frame views and deterministic sample conversion. The canonical
// scalar is signed i32 full scale; i16 occupies its high sixteen bits and f32 uses
// [-1, 1]. Samples are little-endian on every host.

use e.algo.rand
use e.mem

type SampleFormat = enum u8 { I16, I32, F32 }
type Format = struct { rate: u32, channels: u8, sample: SampleFormat }
type Frames = struct { bytes: []u8, format: Format, count: usize }
error Unsupported
error Truncated

fn sample_bytes(s: SampleFormat) -> usize {
    if s == .I16 { ret 2usize }
    ret 4usize
}

fn frame_bytes(f: Format) -> usize {
    ret usize(f.channels) * sample_bytes(f.sample)
}

fn frames_in(f: Format, bytes: usize) -> usize {
    let width = frame_bytes(f)
    if width == 0usize { ret 0usize }
    ret bytes / width
}

fn view(bytes: []u8, f: Format) -> (Frames, err) {
    let width = frame_bytes(f)
    if f.rate == 0u32 || width == 0usize { ret (zero, Unsupported) }
    if bytes.len % width != 0usize { ret (zero, Truncated) }
    ret (Frames { bytes: bytes, format: f, count: bytes.len / width }, ok)
}

fn read_u16(bytes: []const u8, at: usize) -> u16 {
    ret u16(bytes[at]) | (u16(bytes[at + 1usize]) << 8u16)
}

fn read_u32(bytes: []const u8, at: usize) -> u32 {
    ret u32(bytes[at]) | (u32(bytes[at + 1usize]) << 8u32) | (u32(bytes[at + 2usize]) << 16u32) | (u32(bytes[at + 3usize]) << 24u32)
}

fn write_u16(bytes: []u8, at: usize, value: u16) {
    bytes[at] = u8(value & 255u16)
    bytes[at + 1usize] = u8(value >> 8u16)
}

fn write_u32(bytes: []u8, at: usize, value: u32) {
    bytes[at] = u8(value & 255u32)
    bytes[at + 1usize] = u8((value >> 8u32) & 255u32)
    bytes[at + 2usize] = u8((value >> 16u32) & 255u32)
    bytes[at + 3usize] = u8(value >> 24u32)
}

fn sample_i32(fr: Frames, frame: usize, channel: u8) -> (i32, err) {
    if frame >= fr.count || channel >= fr.format.channels { ret (0i32, Truncated) }
    let width = sample_bytes(fr.format.sample)
    let offset = (frame * usize(fr.format.channels) + usize(channel)) * width
    if offset + width > fr.bytes.len { ret (0i32, Truncated) }
    if fr.format.sample == .I16 {
        ret (i32(mem.bitcast[i16](read_u16(fr.bytes, offset))) * 65536i32, ok)
    }
    if fr.format.sample == .I32 {
        ret (mem.bitcast[i32](read_u32(fr.bytes, offset)), ok)
    }
    let value = mem.bitcast[f32](read_u32(fr.bytes, offset))
    if !(value == value) { ret (0i32, Unsupported) }
    if value <= -1.0f32 { ret (-2147483647i32 - 1i32, ok) }
    if value >= 1.0f32 { ret (2147483647i32, ok) }
    ret (i32(f64(value) * 2147483647.0), ok)
}

fn set_sample_i32(fr: *Frames, frame: usize, channel: u8, value: i32) -> err {
    if frame >= fr.count || channel >= fr.format.channels { ret Truncated }
    let width = sample_bytes(fr.format.sample)
    let offset = (frame * usize(fr.format.channels) + usize(channel)) * width
    if offset + width > fr.bytes.len { ret Truncated }
    if fr.format.sample == .I16 {
        var narrow = value / 65536i32
        if narrow < -32768i32 { narrow = -32768i32 }
        if narrow > 32767i32 { narrow = 32767i32 }
        write_u16(fr.bytes, offset, mem.bitcast[u16](i16(narrow)))
        ret ok
    }
    if fr.format.sample == .I32 {
        write_u32(fr.bytes, offset, mem.bitcast[u32](value))
        ret ok
    }
    var normalized = -1.0f32
    if value != (-2147483647i32 - 1i32) { normalized = f32(f64(value) / 2147483647.0) }
    write_u32(fr.bytes, offset, mem.bitcast[u32](normalized))
    ret ok
}

fn convert(a: *mem.Arena, src: Frames, to: SampleFormat) -> (Frames, err) {
    let source_width = frame_bytes(src.format)
    if src.format.rate == 0u32 || source_width == 0usize || src.count > frames_in(src.format, src.bytes.len) { ret (zero, Truncated) }
    let target_format = Format { rate: src.format.rate, channels: src.format.channels, sample: to }
    let target_width = frame_bytes(target_format)
    if src.count != 0usize && target_width > 18446744073709551615usize / src.count { ret (zero, mem.Exhausted) }
    let (bytes, allocation_error) = mem.alloc[u8](a, src.count * target_width)
    if allocation_error != ok { ret (zero, allocation_error) }
    var out = Frames { bytes: bytes, format: target_format, count: src.count }
    var frame = 0usize
    while frame < src.count {
        var channel = 0u8
        while channel < src.format.channels {
            let (value, read_error) = sample_i32(src, frame, channel)
            if read_error != ok { ret (zero, read_error) }
            let write_error = set_sample_i32(&out, frame, channel, value)
            if write_error != ok { ret (zero, write_error) }
            channel += 1u8
        }
        frame += 1usize
    }
    ret (out, ok)
}

fn silence(fr: *Frames) -> err {
    let width = frame_bytes(fr.format)
    if width == 0usize || fr.count > frames_in(fr.format, fr.bytes.len) { ret Truncated }
    var at = 0usize
    while at < fr.count * width {
        fr.bytes[at] = 0u8
        at += 1usize
    }
    ret ok
}


// --- Dither (#1899): quantising f32 samples to 16 bits with TPDF dither
// from a caller `Pcg64` (two uniform draws in [0, 1) subtracted: a triangle
// over (-1, 1) LSB) and, when `shaping` is set, first-order error feedback
// (the previous quantisation error subtracted before rounding, which moves
// the noise power toward the top of the band). Rounding is floor(x + 0.5)
// in f64, the result clamped to the i16 range.

type Dither = struct { rng: *rand.Pcg64, shaping: bool, error_value: f64 }

fn dither(rng: *rand.Pcg64, shaping: bool) -> Dither {
    ret Dither { rng: rng, shaping: shaping, error_value: 0.0f64 }
}

// One sample in [-1, 1] to an i16 (full scale 32767).
fn dither_sample(d: *Dither, x: f32) -> i16 {
    var v = f64(x) * 32767.0f64 - d.error_value
    if !(v == v) { v = 0.0f64 }
    if v > 40000.0f64 { v = 40000.0f64 }
    if v < -40000.0f64 { v = -40000.0f64 }
    let first = rand.pcg64_f64(d.rng)
    let second = rand.pcg64_f64(d.rng)
    let noise = first - second
    let w = v + noise + 0.5f64
    var q = i64(w)
    if f64(q) > w { q -= 1i64 }
    if q < -32768i64 { q = -32768i64 }
    if q > 32767i64 { q = 32767i64 }
    if d.shaping { d.error_value = f64(q) - v }
    ret i16(q)
}

// `dst[i] = dither_sample(src[i])` for every sample; `Truncated` when `dst` is short.
fn dither_block(d: *Dither, src: []const f32, dst: []i16) -> err {
    if dst.len < src.len { ret Truncated }
    var i = 0usize
    while i < src.len {
        dst[i] = dither_sample(d, src[i])
        i += 1usize
    }
    ret ok
}
