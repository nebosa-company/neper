// GP-09: a Base16 codec with a 16-byte SIMD body and a scalar tail. The
// standard-library codec is the independent output oracle.

use e.bytes
use e.io
use e.mem
use e.os
use e.simd

error Invalid
error TooSmall

type Input = struct { bytes: [80]u8 }
type Text = struct { bytes: [144]u8, align: Vec[u8, 16] }

fn hex_chars(nibbles: Vec[u8, 16]) -> Vec[u8, 16] {
    let ten = simd.splat[Vec[u8, 16]](10u8)
    let digits = nibbles +% simd.splat[Vec[u8, 16]](48u8)
    let letters = nibbles +% simd.splat[Vec[u8, 16]](87u8)
    ret simd.select(simd.cmp_lt(nibbles, ten), digits, letters)
}

fn encode(dst: []u8, src: []const u8) -> (usize, err) {
    if dst.len < src.len * 2usize { ret (0usize, TooSmall) }
    var at = 0usize
    while at + 16usize <= src.len {
        let values = simd.load_aligned[Vec[u8, 16]](src, at)
        let high = hex_chars(values >> 4u32)
        let low = hex_chars(values & simd.splat[Vec[u8, 16]](15u8))
        var lane = 0usize
        while lane < 16usize {
            dst[2usize * (at + lane)] = high[lane]
            dst[2usize * (at + lane) + 1usize] = low[lane]
            lane += 1usize
        }
        at += 16usize
    }
    while at < src.len {
        let value = src[at]
        let high = value >> 4u32
        let low = value & 15u8
        var high_char = high +% 48u8
        var low_char = low +% 48u8
        if high >= 10u8 { high_char = high +% 87u8 }
        if low >= 10u8 { low_char = low +% 87u8 }
        dst[2usize * at] = high_char
        dst[2usize * at + 1usize] = low_char
        at += 1usize
    }
    ret (src.len * 2usize, ok)
}

fn decode(dst: []u8, src: []const u8) -> (usize, err) {
    if (src.len & 1usize) != 0usize { ret (0usize, Invalid) }
    let needed = src.len / 2usize
    if dst.len < needed { ret (0usize, TooSmall) }
    var at = 0usize
    while at + 16usize <= src.len {
        // Encoded text need not inherit the input buffer's alignment.
        let chars = simd.load[Vec[u8, 16]](src, at)
        let digit = simd.cmp_ge(chars, simd.splat[Vec[u8, 16]](48u8)) & simd.cmp_le(chars, simd.splat[Vec[u8, 16]](57u8))
        let letter = simd.cmp_ge(chars, simd.splat[Vec[u8, 16]](97u8)) & simd.cmp_le(chars, simd.splat[Vec[u8, 16]](102u8))
        if !simd.all[Vec[u8, 16]](digit | letter) { ret (0usize, Invalid) }
        let values = simd.select(digit, chars -% simd.splat[Vec[u8, 16]](48u8), chars -% simd.splat[Vec[u8, 16]](87u8))
        var lane = 0usize
        while lane < 16usize {
            dst[at / 2usize + lane / 2usize] = (values[lane] << 4u32) | values[lane + 1usize]
            lane += 2usize
        }
        at += 16usize
    }
    while at < src.len {
        let high = src[at]
        let low = src[at + 1usize]
        var high_value = 0u8
        var low_value = 0u8
        if high >= 48u8 && high <= 57u8 {
            high_value = high - 48u8
        } else if high >= 97u8 && high <= 102u8 {
            high_value = high - 87u8
        } else {
            ret (0usize, Invalid)
        }
        if low >= 48u8 && low <= 57u8 {
            low_value = low - 48u8
        } else if low >= 97u8 && low <= 102u8 {
            low_value = low - 87u8
        } else {
            ret (0usize, Invalid)
        }
        dst[at / 2usize] = (high_value << 4u32) | low_value
        at += 2usize
    }
    ret (needed, ok)
}

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main() -> err {
    var input: Input = zero
    let skew = (16usize - mem.address_of(&input.bytes[0usize]) % 16usize) % 16usize
    var source = input.bytes[skew..skew + 65usize]
    var i = 0usize
    while i < source.len {
        source[i] = u8((i * 73usize + 19usize) & 255usize)
        i += 1usize
    }
    var got: Text = zero
    var want: Text = zero
    var back: [65]u8 = zero
    var n = 0usize
    while n <= source.len {
        let (got_len, got_error) = encode(got.bytes[0..], source[..n])
        let (want_text, want_error) = bytes.hex_encode(want.bytes[0..], source[..n], false)
        if got_error != ok || want_error != ok || got_len != want_text.len || !same(got.bytes[..got_len], want.bytes[..want_text.len]) { os.exit(1i32) }
        let (back_len, back_error) = decode(back[0..], got.bytes[..got_len])
        if back_error != ok || back_len != n || !same(back[..n], source[..n]) { os.exit(2i32) }
        n += 1usize
    }
    got.bytes[31usize] = 120u8
    let (_, invalid_error) = decode(back[0..], got.bytes[..64usize])
    if invalid_error != Invalid { os.exit(3i32) }
    try io.print("gp09 simd hex ok\n")
    ret ok
}
