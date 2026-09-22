// FLAC decoding (RFC 9639) over caller storage: `stream_info` parses the `fLaC`
// marker and STREAMINFO (every other metadata block is skipped by length),
// `decoder` positions after the metadata, `decode_frame` decodes one frame
// (header with CRC-8, constant / verbatim / fixed / LPC subframes with wasted
// bits and Rice residuals, CRC-16 footer, channel decorrelation) into interleaved
// `i32` samples, `decode` runs the whole stream, `frame_header` parses one header
// on its own, and `md5_check` verifies the decode against the STREAMINFO MD5.

use e.crypto.hash

type StreamInfo = struct { min_block: u32, max_block: u32, min_frame: u32, max_frame: u32, rate: u32, channels: u32, bits: u32, total: u64, md5: [16]u8 }
type Assignment = enum u8 { Independent, LeftSide, RightSide, MidSide }
type FrameHeader = struct { variable: bool, block_size: u32, rate: u32, channels: u32, assignment: Assignment, bits: u32, number: u64, size: usize }
type Decoder = struct { src: []const u8, pos: usize, info: StreamInfo }
type Bits = struct { data: []const u8, pos: usize, bad: bool }
error Malformed
error Unsupported
error TooSmall
error Checksum

// ------------------------------------------------------------------ bits

fn read(b: *Bits, n: u32) -> u64 {
    var v = 0u64
    var left = n
    while left > 0u32 {
        let byte_at = b.pos >> 3u32
        if byte_at >= b.data.len {
            b.bad = true
            ret 0u64
        }
        let avail = 8u32 - u32(b.pos & 7usize)
        var take = avail
        if take > left { take = left }
        let chunk = (u64(b.data[byte_at]) >> (avail - take)) & ((1u64 << take) - 1u64)
        v = (v << take) | chunk
        b.pos += usize(take)
        left -= take
    }
    ret v
}

fn read_signed(b: *Bits, n: u32) -> i64 {
    if n == 0u32 { ret 0i64 }
    let v = read(b, n)
    if ((v >> (n - 1u32)) & 1u64) == 1u64 { ret i64(v) - i64(1u64 << n) }
    ret i64(v)
}

fn unary(b: *Bits) -> u32 {
    var count = 0u32
    while !b.bad && read(b, 1u32) == 0u64 { count += 1u32 }
    ret count
}

fn align(b: *Bits) {
    b.pos = (b.pos + 7usize) & ~7usize
}

// ------------------------------------------------------------------ checksums

fn crc8(data: []const u8) -> u8 {
    var c = 0u32
    var i = 0usize
    while i < data.len {
        c = c ^ u32(data[i])
        var k = 0u32
        while k < 8u32 {
            c = c << 1u32
            if (c & 256u32) != 0u32 { c = c ^ 7u32 }
            k += 1u32
        }
        i += 1usize
    }
    ret u8(c & 255u32)
}

fn crc16(data: []const u8) -> u16 {
    var c = 0u32
    var i = 0usize
    while i < data.len {
        c = c ^ (u32(data[i]) << 8u32)
        var k = 0u32
        while k < 8u32 {
            c = c << 1u32
            if (c & 65536u32) != 0u32 { c = c ^ 32773u32 }
            k += 1u32
        }
        c = c & 65535u32
        i += 1usize
    }
    ret u16(c)
}

// ------------------------------------------------------------------ metadata

fn big(src: []const u8, at: usize, n: usize) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < n {
        v = (v << 8u32) | u64(src[at + i])
        i += 1usize
    }
    ret v
}

// STREAMINFO and the byte offset of the first frame.
fn metadata(src: []const u8) -> (StreamInfo, usize, err) {
    if src.len < 8usize { ret (zero, 0usize, TooSmall) }
    if src[0] != 102u8 || src[1] != 76u8 || src[2] != 97u8 || src[3] != 67u8 { ret (zero, 0usize, Malformed) }
    var info: StreamInfo = zero
    var seen = false
    var pos = 4usize
    var last = false
    while !last {
        if pos + 4usize > src.len { ret (zero, 0usize, TooSmall) }
        last = (src[pos] & 128u8) != 0u8
        let kind = src[pos] & 127u8
        let length = usize(big(src, pos + 1usize, 3usize))
        pos += 4usize
        if length > src.len - pos { ret (zero, 0usize, TooSmall) }
        if kind == 0u8 {
            if length < 34usize || seen { ret (zero, 0usize, Malformed) }
            var b = Bits { data: src[pos..pos + 34usize], pos: 0usize, bad: false }
            info.min_block = u32(read(&b, 16u32))
            info.max_block = u32(read(&b, 16u32))
            info.min_frame = u32(read(&b, 24u32))
            info.max_frame = u32(read(&b, 24u32))
            info.rate = u32(read(&b, 20u32))
            info.channels = u32(read(&b, 3u32)) + 1u32
            info.bits = u32(read(&b, 5u32)) + 1u32
            info.total = read(&b, 36u32)
            var i = 0usize
            while i < 16usize {
                info.md5[i] = src[pos + 18usize + i]
                i += 1usize
            }
            if info.min_block < 16u32 || info.max_block < info.min_block || info.rate == 0u32 { ret (zero, 0usize, Malformed) }
            seen = true
        } else if kind == 127u8 {
            ret (zero, 0usize, Malformed)
        }
        pos += length
    }
    if !seen { ret (zero, 0usize, Malformed) }
    ret (info, pos, ok)
}

fn stream_info(src: []const u8) -> (StreamInfo, err) {
    let (info, _, e) = metadata(src)
    ret (info, e)
}

// A decoder positioned at the first frame.
fn decoder(src: []const u8) -> (Decoder, err) {
    let (info, pos, e) = metadata(src)
    if e != ok { ret (zero, e) }
    ret (Decoder { src: src, pos: pos, info: info }, ok)
}

fn at_end(d: Decoder) -> bool {
    ret d.pos >= d.src.len
}

// ------------------------------------------------------------------ frame header

fn rate_code(code: u32) -> u32 {
    let table: [12]u32 = [12]u32{ 0, 88200, 176400, 192000, 8000, 16000, 22050, 24000, 32000, 44100, 48000, 96000 }
    ret table[usize(code)]
}

fn header(src: []const u8, at: usize, info: StreamInfo) -> (FrameHeader, err) {
    if at + 5usize > src.len { ret (zero, TooSmall) }
    var b = Bits { data: src, pos: at * 8usize, bad: false }
    if read(&b, 15u32) != 32764u64 { ret (zero, Malformed) }
    var h: FrameHeader = zero
    h.variable = read(&b, 1u32) == 1u64
    let bs_code = u32(read(&b, 4u32))
    let sr_code = u32(read(&b, 4u32))
    let ch_code = u32(read(&b, 4u32))
    let ss_code = u32(read(&b, 3u32))
    if read(&b, 1u32) != 0u64 { ret (zero, Malformed) }
    let first = read(&b, 8u32)
    var number = first
    if first >= 128u64 {
        var extra = 0u32
        var mask = 64u64
        while (first & mask) != 0u64 {
            extra += 1u32
            mask = mask >> 1u32
        }
        if extra == 0u32 || extra > 6u32 { ret (zero, Malformed) }
        number = first & (mask - 1u64)
        var i = 0u32
        while i < extra {
            let c = read(&b, 8u32)
            if (c & 192u64) != 128u64 { ret (zero, Malformed) }
            number = (number << 6u32) | (c & 63u64)
            i += 1u32
        }
    }
    h.number = number
    if bs_code == 0u32 {
        ret (zero, Malformed)
    } else if bs_code == 1u32 {
        h.block_size = 192u32
    } else if bs_code <= 5u32 {
        h.block_size = 576u32 << (bs_code - 2u32)
    } else if bs_code == 6u32 {
        h.block_size = u32(read(&b, 8u32)) + 1u32
    } else if bs_code == 7u32 {
        h.block_size = u32(read(&b, 16u32)) + 1u32
    } else {
        h.block_size = 256u32 << (bs_code - 8u32)
    }
    if sr_code == 0u32 {
        h.rate = info.rate
    } else if sr_code <= 11u32 {
        h.rate = rate_code(sr_code)
    } else if sr_code == 12u32 {
        h.rate = u32(read(&b, 8u32)) * 1000u32
    } else if sr_code == 13u32 {
        h.rate = u32(read(&b, 16u32))
    } else if sr_code == 14u32 {
        h.rate = u32(read(&b, 16u32)) * 10u32
    } else {
        ret (zero, Malformed)
    }
    if ch_code < 8u32 {
        h.channels = ch_code + 1u32
        h.assignment = .Independent
    } else if ch_code == 8u32 {
        h.channels = 2u32
        h.assignment = .LeftSide
    } else if ch_code == 9u32 {
        h.channels = 2u32
        h.assignment = .RightSide
    } else if ch_code == 10u32 {
        h.channels = 2u32
        h.assignment = .MidSide
    } else {
        ret (zero, Malformed)
    }
    if ss_code == 0u32 {
        h.bits = info.bits
    } else if ss_code == 1u32 {
        h.bits = 8u32
    } else if ss_code == 2u32 {
        h.bits = 12u32
    } else if ss_code == 4u32 {
        h.bits = 16u32
    } else if ss_code == 5u32 {
        h.bits = 20u32
    } else if ss_code == 6u32 {
        h.bits = 24u32
    } else if ss_code == 7u32 {
        h.bits = 32u32
    } else {
        ret (zero, Malformed)
    }
    if b.bad { ret (zero, TooSmall) }
    let end = b.pos >> 3u32
    if end >= src.len { ret (zero, TooSmall) }
    if crc8(src[at..end]) != src[end] { ret (zero, Checksum) }
    h.size = end + 1usize - at
    ret (h, ok)
}

// The frame header at `pos`; sample rate and bit depth codes that defer to
// STREAMINFO are resolved from the stream's own metadata.
fn frame_header(src: []const u8, pos: usize) -> (FrameHeader, err) {
    let (info, _, e) = metadata(src)
    if e != ok { ret (zero, e) }
    let (h, he) = header(src, pos, info)
    ret (h, he)
}

// ------------------------------------------------------------------ subframes

fn residual(b: *Bits, out: []i64, block: usize, order: usize) -> err {
    let method = u32(read(b, 2u32))
    if method > 1u32 { ret Malformed }
    let param_bits = 4u32 + method
    let escape = (1u64 << param_bits) - 1u64
    let porder = u32(read(b, 4u32))
    let parts = 1usize << porder
    if block % parts != 0usize || block / parts < order { ret Malformed }
    var at = order
    var p = 0usize
    while p < parts {
        var n = block / parts
        if p == 0usize { n -= order }
        let param = read(b, param_bits)
        let stop = at + n
        if param == escape {
            let width = u32(read(b, 5u32))
            while at < stop {
                out[at] = read_signed(b, width)
                at += 1usize
            }
        } else {
            let k = u32(param)
            while at < stop {
                let q = u64(unary(b))
                if b.bad { ret Malformed }
                let v = (q << k) | read(b, k)
                var s = i64(v >> 1u32)
                if (v & 1u64) == 1u64 { s = -1i64 - s }
                out[at] = s
                at += 1usize
            }
        }
        p += 1usize
    }
    if b.bad { ret Malformed }
    ret ok
}

fn subframe(b: *Bits, out: []i64, block: usize, width_in: u32) -> err {
    if read(b, 1u32) != 0u64 { ret Malformed }
    let kind = u32(read(b, 6u32))
    var wasted = 0u32
    if read(b, 1u32) == 1u64 { wasted = unary(b) + 1u32 }
    if b.bad || wasted >= width_in { ret Malformed }
    let width = width_in - wasted
    var order = 0usize
    if kind == 0u32 {
        let v = read_signed(b, width)
        var i = 0usize
        while i < block {
            out[i] = v
            i += 1usize
        }
    } else if kind == 1u32 {
        var i = 0usize
        while i < block {
            out[i] = read_signed(b, width)
            i += 1usize
        }
    } else if kind >= 8u32 && kind <= 12u32 {
        order = usize(kind - 8u32)
        if order > block { ret Malformed }
        var i = 0usize
        while i < order {
            out[i] = read_signed(b, width)
            i += 1usize
        }
        let e = residual(b, out, block, order)
        if e != ok { ret e }
        i = order
        while i < block {
            var p = 0i64
            if order == 1usize {
                p = out[i - 1usize]
            } else if order == 2usize {
                p = 2i64 * out[i - 1usize] - out[i - 2usize]
            } else if order == 3usize {
                p = 3i64 * out[i - 1usize] - 3i64 * out[i - 2usize] + out[i - 3usize]
            } else if order == 4usize {
                p = 4i64 * out[i - 1usize] - 6i64 * out[i - 2usize] + 4i64 * out[i - 3usize] - out[i - 4usize]
            }
            out[i] = p + out[i]
            i += 1usize
        }
    } else if kind >= 32u32 {
        order = usize(kind - 31u32)
        if order > block { ret Malformed }
        var i = 0usize
        while i < order {
            out[i] = read_signed(b, width)
            i += 1usize
        }
        let precision = u32(read(b, 4u32)) + 1u32
        if precision == 16u32 { ret Malformed }
        let shift = read_signed(b, 5u32)
        if shift < 0i64 { ret Malformed }
        var coefs: [32]i64 = zero
        i = 0usize
        while i < order {
            coefs[i] = read_signed(b, precision)
            i += 1usize
        }
        let e = residual(b, out, block, order)
        if e != ok { ret e }
        // ponytail: i64 accumulator wraps for 32-bit samples at high order and
        // precision (the RFC allows 69 bits); widen to i128 if such streams appear.
        i = order
        while i < block {
            var acc = 0i64
            var j = 0usize
            while j < order {
                acc = acc +% coefs[j] *% out[i - 1usize - j]
                j += 1usize
            }
            out[i] = (acc >> u32(shift)) + out[i]
            i += 1usize
        }
    } else {
        ret Malformed
    }
    if wasted > 0u32 {
        var i = 0usize
        while i < block {
            out[i] = out[i] << wasted
            i += 1usize
        }
    }
    ret ok
}

// ------------------------------------------------------------------ frames

// One frame into `out` (interleaved, `block_size * channels` samples) using
// `scratch` (`block_size * channels` i64); answers the samples per channel, or
// 0 at the end of the stream.
fn decode_frame(d: *Decoder, out: []i32, scratch: []i64) -> (usize, err) {
    if d.pos >= d.src.len { ret (0usize, ok) }
    let start = d.pos
    let (h, he) = header(d.src, start, d.info)
    if he != ok { ret (0usize, he) }
    if h.bits > 32u32 || h.channels != d.info.channels { ret (0usize, Unsupported) }
    let block = usize(h.block_size)
    let channels = usize(h.channels)
    if block * channels > out.len || block * channels > scratch.len { ret (0usize, TooSmall) }
    var b = Bits { data: d.src, pos: (start + h.size) * 8usize, bad: false }
    var ch = 0usize
    while ch < channels {
        var width = h.bits
        if (h.assignment == .LeftSide && ch == 1usize) || (h.assignment == .RightSide && ch == 0usize) || (h.assignment == .MidSide && ch == 1usize) { width += 1u32 }
        let e = subframe(&b, scratch[ch * block..(ch + 1usize) * block], block, width)
        if e != ok { ret (0usize, e) }
        ch += 1usize
    }
    align(&b)
    let end = b.pos >> 3u32
    if b.bad || end + 2usize > d.src.len { ret (0usize, Malformed) }
    let footer = (u16(d.src[end]) << 8u16) | u16(d.src[end + 1usize])
    if crc16(d.src[start..end]) != footer { ret (0usize, Checksum) }
    var i = 0usize
    if h.assignment == .Independent {
        while i < block {
            ch = 0usize
            while ch < channels {
                out[i * channels + ch] = i32(scratch[ch * block + i])
                ch += 1usize
            }
            i += 1usize
        }
    } else {
        while i < block {
            let x = scratch[i]
            let y = scratch[block + i]
            var left = 0i64
            var right = 0i64
            if h.assignment == .LeftSide {
                left = x
                right = x - y
            } else if h.assignment == .RightSide {
                left = x + y
                right = y
            } else {
                let mid = (x << 1u32) | (y & 1i64)
                left = (mid + y) >> 1u32
                right = (mid - y) >> 1u32
            }
            out[i * 2usize] = i32(left)
            out[i * 2usize + 1usize] = i32(right)
            i += 1usize
        }
    }
    d.pos = end + 2usize
    ret (block, ok)
}

// The whole stream into `out`; answers the samples per channel.
fn decode(src: []const u8, out: []i32, scratch: []i64) -> (usize, err) {
    let (d0, e) = decoder(src)
    if e != ok { ret (0usize, e) }
    var d = d0
    let channels = usize(d.info.channels)
    var total = 0usize
    while d.pos < d.src.len {
        let (n, fe) = decode_frame(&d, out[total * channels..], scratch)
        if fe != ok { ret (total, fe) }
        total += n
    }
    ret (total, ok)
}

// True when the MD5 of `out` as little-endian samples of the stream's width
// matches STREAMINFO; `bytes` must hold `out.len * ceil(bits / 8)`.
fn md5_check(out: []const i32, info: StreamInfo, bytes: []u8) -> bool {
    let width = usize((info.bits + 7u32) / 8u32)
    let n = out.len * width
    if n > bytes.len { ret false }
    var i = 0usize
    while i < out.len {
        var v = u32(out[i] & 2147483647i32)
        if out[i] < 0i32 { v = v | 2147483648u32 }
        var k = 0usize
        while k < width {
            bytes[i * width + k] = u8((v >> u32(k * 8usize)) & 255u32)
            k += 1usize
        }
        i += 1usize
    }
    let digest = hash.legacy_md5(bytes[..n])
    i = 0usize
    while i < 16usize {
        if digest[i] != info.md5[i] { ret false }
        i += 1usize
    }
    ret true
}
