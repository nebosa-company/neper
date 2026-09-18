// Interleaved PCM frame views and deterministic sample conversion. The canonical
// scalar is signed i32 full scale; i16 occupies its high sixteen bits and f32 uses
// [-1, 1]. Samples are little-endian on every host.

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
