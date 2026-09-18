// RIFF/WAVE PCM decoding into caller-provided audio frames.

use e.audio
use e.mem

type Decoder = struct { bytes: []const u8, data_start: usize, at: usize, format: audio.Format, frames: usize }
error Invalid
error Unsupported

fn little_u16(bytes: []const u8, at: usize) -> u16 {
    ret u16(bytes[at]) | (u16(bytes[at + 1usize]) << 8u16)
}

fn little_u32(bytes: []const u8, at: usize) -> u32 {
    ret u32(bytes[at]) | (u32(bytes[at + 1usize]) << 8u32) | (u32(bytes[at + 2usize]) << 16u32) | (u32(bytes[at + 3usize]) << 24u32)
}

fn tag(bytes: []const u8, at: usize, a: u8, b: u8, c: u8, d: u8) -> bool {
    ret bytes[at] == a && bytes[at + 1usize] == b && bytes[at + 2usize] == c && bytes[at + 3usize] == d
}

fn open(a: *mem.Arena, source_bytes: []const u8) -> (Decoder, err) {
    if source_bytes.len < 12usize || !tag(source_bytes, 0usize, 82u8, 73u8, 70u8, 70u8) || !tag(source_bytes, 8usize, 87u8, 65u8, 86u8, 69u8) { ret (zero, Invalid) }
    let riff_size = usize(little_u32(source_bytes, 4usize))
    if riff_size < 4usize || riff_size > source_bytes.len - 8usize { ret (zero, Invalid) }
    let limit = riff_size + 8usize
    var found_format = false
    var found_data = false
    var decoded_format: audio.Format = zero
    var data_start = 0usize
    var data_size = 0usize
    var at = 12usize
    while at + 8usize <= limit {
        let size = usize(little_u32(source_bytes, at + 4usize))
        let payload = at + 8usize
        if size > limit - payload { ret (zero, Invalid) }
        if !found_format && tag(source_bytes, at, 102u8, 109u8, 116u8, 32u8) {
            if size < 16usize { ret (zero, Invalid) }
            let encoding = little_u16(source_bytes, payload)
            let channels = little_u16(source_bytes, payload + 2usize)
            let rate = little_u32(source_bytes, payload + 4usize)
            let byte_rate = little_u32(source_bytes, payload + 8usize)
            let block = little_u16(source_bytes, payload + 12usize)
            let bits = little_u16(source_bytes, payload + 14usize)
            if channels == 0u16 || channels > 255u16 || rate == 0u32 { ret (zero, Unsupported) }
            var sample: audio.SampleFormat = .I16
            if encoding == 1u16 && bits == 16u16 {
                sample = .I16
            } else if encoding == 1u16 && bits == 32u16 {
                sample = .I32
            } else if encoding == 3u16 && bits == 32u16 {
                sample = .F32
            } else {
                ret (zero, Unsupported)
            }
            decoded_format = audio.Format { rate: rate, channels: u8(channels), sample: sample }
            let expected_block = audio.frame_bytes(decoded_format)
            if expected_block != usize(block) || u64(byte_rate) != u64(rate) * u64(expected_block) { ret (zero, Invalid) }
            found_format = true
        }
        if !found_data && tag(source_bytes, at, 100u8, 97u8, 116u8, 97u8) {
            data_start = payload
            data_size = size
            found_data = true
        }
        let padded = size + (size % 2usize)
        if padded > limit - payload { ret (zero, Invalid) }
        at = payload + padded
    }
    if at != limit || !found_format || !found_data { ret (zero, Invalid) }
    let frame_width = audio.frame_bytes(decoded_format)
    if frame_width == 0usize || data_size % frame_width != 0usize { ret (zero, Invalid) }
    let checkpoint = a.off
    let (owned, allocation_error) = mem.alloc[u8](a, limit)
    if allocation_error != ok { ret (zero, allocation_error) }
    mem.copy[u8](owned, source_bytes[0..limit])
    let frames = data_size / frame_width
    if data_start + data_size > owned.len {
        a.off = checkpoint
        ret (zero, Invalid)
    }
    ret (Decoder { bytes: owned, data_start: data_start, at: 0usize, format: decoded_format, frames: frames }, ok)
}

fn format(d: Decoder) -> audio.Format {
    ret d.format
}

fn frame_count(d: Decoder) -> usize {
    ret d.frames
}

fn decoded_sample(d: Decoder, frame: usize, channel: u8) -> (i32, err) {
    let width = audio.sample_bytes(d.format.sample)
    let offset = d.data_start + (frame * usize(d.format.channels) + usize(channel)) * width
    if offset + width > d.bytes.len { ret (0i32, Invalid) }
    if d.format.sample == .I16 {
        ret (i32(mem.bitcast[i16](little_u16(d.bytes, offset))) * 65536i32, ok)
    }
    if d.format.sample == .I32 {
        ret (mem.bitcast[i32](little_u32(d.bytes, offset)), ok)
    }
    let value = mem.bitcast[f32](little_u32(d.bytes, offset))
    if !(value == value) { ret (0i32, Unsupported) }
    if value <= -1.0f32 { ret (-2147483647i32 - 1i32, ok) }
    if value >= 1.0f32 { ret (2147483647i32, ok) }
    ret (i32(f64(value) * 2147483647.0), ok)
}

fn decode_into(d: *Decoder, out: *audio.Frames) -> (usize, err) {
    if d.at > d.frames || out.format.rate != d.format.rate || out.format.channels != d.format.channels || out.count > audio.frames_in(out.format, out.bytes.len) { ret (0usize, Unsupported) }
    var count = out.count
    if count > d.frames - d.at { count = d.frames - d.at }
    var frame = 0usize
    while frame < count {
        var channel = 0u8
        while channel < d.format.channels {
            let (sample, sample_error) = decoded_sample(*d, d.at + frame, channel)
            if sample_error != ok { ret (frame, sample_error) }
            let write_error = audio.set_sample_i32(out, frame, channel, sample)
            if write_error != ok { ret (frame, write_error) }
            channel += 1u8
        }
        frame += 1usize
    }
    d.at += count
    ret (count, ok)
}

fn seek(d: *Decoder, frame: usize) -> err {
    if frame > d.frames { ret Invalid }
    d.at = frame
    ret ok
}
