// GP-09 measurement: lower-case Base16 encode/decode, sixteen bytes at a time
// with scalar tails. The fixture checks this algorithm against e.bytes.
use e.io
use e.mem
use e.os
use e.simd

error Invalid

const N: usize = 4194317usize
const ITERS: usize = 8usize

fn hex_chars(n: Vec[u8, 16]) -> Vec[u8, 16] {
    let digit = n +% simd.splat[Vec[u8, 16]](48u8)
    let letter = n +% simd.splat[Vec[u8, 16]](87u8)
    ret simd.select(simd.cmp_lt(n, simd.splat[Vec[u8, 16]](10u8)), digit, letter)
}

fn encode(dst: []u8, src: []const u8) {
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
        dst[2usize * at] = high +% (if_digit(high, 48u8, 87u8))
        dst[2usize * at + 1usize] = low +% (if_digit(low, 48u8, 87u8))
        at += 1usize
    }
}

fn if_digit(value: u8, digit: u8, letter: u8) -> u8 {
    if value < 10u8 { ret digit }
    ret letter
}

fn decode(dst: []u8, src: []const u8) -> err {
    var at = 0usize
    while at + 16usize <= src.len {
        let chars = simd.load[Vec[u8, 16]](src, at)
        let digit = simd.cmp_ge(chars, simd.splat[Vec[u8, 16]](48u8)) & simd.cmp_le(chars, simd.splat[Vec[u8, 16]](57u8))
        let letter = simd.cmp_ge(chars, simd.splat[Vec[u8, 16]](97u8)) & simd.cmp_le(chars, simd.splat[Vec[u8, 16]](102u8))
        if !simd.all[Vec[u8, 16]](digit | letter) { ret Invalid }
        let values = simd.select(digit, chars -% simd.splat[Vec[u8, 16]](48u8), chars -% simd.splat[Vec[u8, 16]](87u8))
        var lane = 0usize
        while lane < 16usize {
            dst[at / 2usize + lane / 2usize] = (values[lane] << 4u32) | values[lane + 1usize]
            lane += 2usize
        }
        at += 16usize
    }
    while at < src.len {
        let high = scalar_nibble(src[at])
        let low = scalar_nibble(src[at + 1usize])
        if high > 15u8 || low > 15u8 { ret Invalid }
        dst[at / 2usize] = (high << 4u32) | low
        at += 2usize
    }
    ret ok
}

fn scalar_nibble(value: u8) -> u8 {
    if value >= 48u8 && value <= 57u8 { ret value - 48u8 }
    if value >= 97u8 && value <= 102u8 { ret value - 87u8 }
    ret 255u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (raw, raw_error) = mem.alloc[u8](a, N + 15usize)
    if raw_error != ok { ret raw_error }
    let skew = (16usize - mem.address_of(&raw[0usize]) % 16usize) % 16usize
    var input = raw[skew..skew + N]
    let (text, text_error) = mem.alloc[u8](a, N * 2usize)
    let (back, back_error) = mem.alloc[u8](a, N)
    if text_error != ok || back_error != ok { ret mem.Exhausted }
    var i = 0usize
    while i < N {
        input[i] = u8((i * 73usize + 19usize) & 255usize)
        i += 1usize
    }
    var iteration = 0usize
    while iteration < ITERS {
        encode(text, input)
        try decode(back, text)
        iteration += 1usize
    }
    var checksum = 0u64
    i = 0usize
    while i < N {
        if back[i] != input[i] { os.exit(2i32) }
        checksum += u64(back[i])
        i += 1usize
    }
    try io.printf["gp09 {}\n"](checksum)
    ret ok
}
