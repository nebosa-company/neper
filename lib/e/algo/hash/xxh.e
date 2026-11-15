// xxHash 0.8: XXH32, XXH3 64-bit and XXH3 128-bit (default secret, with a seed), and Jenkins's
// one-at-a-time hash as R's digest2int computes it. Answers equal the reference implementation's
// on every input length, which the paths below split at: 0, 1-3, 4-8, 9-16, 17-128, 129-240
// and past 240 bytes. `e.algo.hash.xxhash64` is the 64-bit XXH64.
//
// `jenkins_one_at_a_time` adds each byte as a signed char, as digest's C does on x86, so a byte
// of 128 or more adds a negative value, and it stops at the first zero byte.

type Hash128 = struct { low: u64, high: u64 }

const P32_1: u32 = 2654435761u32
const P32_2: u32 = 2246822519u32
const P32_3: u32 = 3266489917u32
const P32_4: u32 = 668265263u32
const P32_5: u32 = 374761393u32

const P64_1: u64 = 11400714785074694791u64
const P64_2: u64 = 14029467366897019727u64
const P64_3: u64 = 1609587929392839161u64
const P64_4: u64 = 9650029242287828579u64
const P64_5: u64 = 2870177450012600261u64

const MX1: u64 = 1609587791953885689u64
const MX2: u64 = 11507291218515648293u64

fn secret_hex() -> str { ret "b8fe6c3923a44bbe7c01812cf721ad1cded46de9839097db7240a4a4b7b3671fcb79e64eccc0e578825ad07dccff7221b8084674f743248ee03590e6813a264c3c2852bb91c300cb88d0658b1b532ea371644897a20df94e3819ef46a9deacd8a8fa763fe39c343ff9dcbbc7c70b4f1d8a51e04bcdb45931c89f7ec9d9787364eac5ac8334d3ebc3c581a0fffa1363eb170ddd51b7f0da49d316552629d4689e2b16be587d47a1fc8ff8b8d17ad031ce45cb3a8f95160428afd7fbcabb4b407e" }

fn rotl32(x: u32, n: u32) -> u32 { ret (x << n) | (x >> (32u32 - n)) }

fn rotl64(x: u64, n: u64) -> u64 { ret (x << n) | (x >> (64u64 - n)) }

fn swap32(x: u32) -> u32 {
    ret (x << 24u32) | ((x & 65280u32) << 8u32) | ((x >> 8u32) & 65280u32) | (x >> 24u32)
}

fn swap64(x: u64) -> u64 {
    let low = u64(swap32(u32(x & 4294967295u64)))
    let high = u64(swap32(u32(x >> 32u64)))
    ret (low << 32u64) | high
}

fn le32(d: []const u8, at: usize) -> u32 {
    ret u32(d[at]) | (u32(d[at + 1usize]) << 8u32) | (u32(d[at + 2usize]) << 16u32) | (u32(d[at + 3usize]) << 24u32)
}

fn le64(d: []const u8, at: usize) -> u64 {
    ret u64(le32(d, at)) | (u64(le32(d, at + 4usize)) << 32u64)
}

fn hex_value(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn default_secret(out: []u8) {
    let hex = secret_hex()
    var i = 0usize
    while i < 192usize {
        out[i] = (hex_value(hex[2usize * i]) << 4u8) | hex_value(hex[2usize * i + 1usize])
        i += 1usize
    }
}

// --- XXH32.

fn round32(acc: u32, input: u32) -> u32 { ret rotl32(acc +% input *% P32_2, 13u32) *% P32_1 }

fn xxhash32(data: []const u8, seed: u32) -> u32 {
    var h = 0u32
    var at = 0usize
    if data.len >= 16usize {
        var v1 = seed +% P32_1 +% P32_2
        var v2 = seed +% P32_2
        var v3 = seed
        var v4 = seed -% P32_1
        while at + 16usize <= data.len {
            v1 = round32(v1, le32(data, at))
            v2 = round32(v2, le32(data, at + 4usize))
            v3 = round32(v3, le32(data, at + 8usize))
            v4 = round32(v4, le32(data, at + 12usize))
            at += 16usize
        }
        h = rotl32(v1, 1u32) +% rotl32(v2, 7u32) +% rotl32(v3, 12u32) +% rotl32(v4, 18u32)
    } else {
        h = seed +% P32_5
    }
    h = h +% u32(data.len & 4294967295usize)
    while at + 4usize <= data.len {
        h = h +% le32(data, at) *% P32_3
        h = rotl32(h, 17u32) *% P32_4
        at += 4usize
    }
    while at < data.len {
        h = h +% u32(data[at]) *% P32_5
        h = rotl32(h, 11u32) *% P32_1
        at += 1usize
    }
    h = h ^ (h >> 15u32)
    h = h *% P32_2
    h = h ^ (h >> 13u32)
    h = h *% P32_3
    ret h ^ (h >> 16u32)
}

// --- XXH3 pieces.

fn mult64to128(lhs: u64, rhs: u64) -> Hash128 {
    let mask = 4294967295u64
    let lo_lo = (lhs & mask) *% (rhs & mask)
    let hi_lo = (lhs >> 32u64) *% (rhs & mask)
    let lo_hi = (lhs & mask) *% (rhs >> 32u64)
    let hi_hi = (lhs >> 32u64) *% (rhs >> 32u64)
    let cross = (lo_lo >> 32u64) +% (hi_lo & mask) +% lo_hi
    let upper = (hi_lo >> 32u64) +% (cross >> 32u64) +% hi_hi
    let lower = (cross << 32u64) | (lo_lo & mask)
    ret Hash128 { low: lower, high: upper }
}

fn mulfold(lhs: u64, rhs: u64) -> u64 {
    let p = mult64to128(lhs, rhs)
    ret p.low ^ p.high
}

fn xorshift(v: u64, n: u64) -> u64 { ret v ^ (v >> n) }

fn avalanche64(h0: u64) -> u64 {
    var h = h0 ^ (h0 >> 33u64)
    h = h *% P64_2
    h = h ^ (h >> 29u64)
    h = h *% P64_3
    ret h ^ (h >> 32u64)
}

fn avalanche3(h0: u64) -> u64 {
    var h = xorshift(h0, 37u64)
    h = h *% MX1
    ret xorshift(h, 32u64)
}

fn rrmxmx(h0: u64, len: u64) -> u64 {
    var h = h0 ^ rotl64(h0, 49u64) ^ rotl64(h0, 24u64)
    h = h *% MX2
    h = h ^ ((h >> 35u64) +% len)
    h = h *% MX2
    ret xorshift(h, 28u64)
}

fn mix16(d: []const u8, at: usize, s: []const u8, so: usize, seed: u64) -> u64 {
    ret mulfold(le64(d, at) ^ (le64(s, so) +% seed), le64(d, at + 8usize) ^ (le64(s, so + 8usize) -% seed))
}

fn xxh3_64_short(d: []const u8, s: []const u8, seed0: u64) -> u64 {
    let len = d.len
    var seed = seed0
    if len > 8usize {
        let bitflip1 = (le64(s, 24usize) ^ le64(s, 32usize)) +% seed
        let bitflip2 = (le64(s, 40usize) ^ le64(s, 48usize)) -% seed
        let input_lo = le64(d, 0usize) ^ bitflip1
        let input_hi = le64(d, len - 8usize) ^ bitflip2
        let acc = u64(len) +% swap64(input_lo) +% input_hi +% mulfold(input_lo, input_hi)
        ret avalanche3(acc)
    }
    if len >= 4usize {
        seed = seed ^ (u64(swap32(u32(seed & 4294967295u64))) << 32u64)
        let input1 = le32(d, 0usize)
        let input2 = le32(d, len - 4usize)
        let bitflip = (le64(s, 8usize) ^ le64(s, 16usize)) -% seed
        let input64 = u64(input2) +% (u64(input1) << 32u64)
        ret rrmxmx(input64 ^ bitflip, u64(len))
    }
    if len > 0usize {
        let combined = (u32(d[0usize]) << 16u32) | (u32(d[len >> 1usize]) << 24u32) | u32(d[len - 1usize]) | (u32(len) << 8u32)
        let bitflip = u64(le32(s, 0usize) ^ le32(s, 4usize)) +% seed
        ret avalanche64(u64(combined) ^ bitflip)
    }
    ret avalanche64(seed ^ (le64(s, 56usize) ^ le64(s, 64usize)))
}

fn xxh3_64_mid(d: []const u8, s: []const u8, seed: u64) -> u64 {
    let len = d.len
    var acc = u64(len) *% P64_1
    if len <= 128usize {
        if len > 32usize {
            if len > 64usize {
                if len > 96usize {
                    acc = acc +% mix16(d, 48usize, s, 96usize, seed)
                    acc = acc +% mix16(d, len - 64usize, s, 112usize, seed)
                }
                acc = acc +% mix16(d, 32usize, s, 64usize, seed)
                acc = acc +% mix16(d, len - 48usize, s, 80usize, seed)
            }
            acc = acc +% mix16(d, 16usize, s, 32usize, seed)
            acc = acc +% mix16(d, len - 32usize, s, 48usize, seed)
        }
        acc = acc +% mix16(d, 0usize, s, 0usize, seed)
        acc = acc +% mix16(d, len - 16usize, s, 16usize, seed)
        ret avalanche3(acc)
    }
    var i = 0usize
    while i < 8usize {
        acc = acc +% mix16(d, 16usize * i, s, 16usize * i, seed)
        i += 1usize
    }
    var acc_end = mix16(d, len - 16usize, s, 119usize, seed)
    acc = avalanche3(acc)
    let rounds = len / 16usize
    i = 8usize
    while i < rounds {
        acc_end = acc_end +% mix16(d, 16usize * i, s, 16usize * (i - 8usize) + 3usize, seed)
        i += 1usize
    }
    ret avalanche3(acc +% acc_end)
}

fn accumulate_stripe(acc: []u64, d: []const u8, at: usize, s: []const u8, so: usize) {
    var lane = 0usize
    while lane < 8usize {
        let data_val = le64(d, at + lane * 8usize)
        let data_key = data_val ^ le64(s, so + lane * 8usize)
        acc[lane ^ 1usize] = acc[lane ^ 1usize] +% data_val
        acc[lane] = acc[lane] +% (data_key & 4294967295u64) *% (data_key >> 32u64)
        lane += 1usize
    }
}

fn scramble(acc: []u64, s: []const u8, so: usize) {
    var lane = 0usize
    while lane < 8usize {
        var a = acc[lane]
        a = xorshift(a, 47u64)
        a = a ^ le64(s, so + lane * 8usize)
        acc[lane] = a *% u64(P32_1)
        lane += 1usize
    }
}

fn init_acc(acc: []u64) {
    acc[0usize] = u64(P32_3)
    acc[1usize] = P64_1
    acc[2usize] = P64_2
    acc[3usize] = P64_3
    acc[4usize] = P64_4
    acc[5usize] = u64(P32_2)
    acc[6usize] = P64_5
    acc[7usize] = u64(P32_1)
}

fn long_loop(acc: []u64, d: []const u8, s: []const u8) {
    let stripes_per_block = (192usize - 64usize) / 8usize
    let block_len = 64usize * stripes_per_block
    let blocks = (d.len - 1usize) / block_len
    var n = 0usize
    while n < blocks {
        var k = 0usize
        while k < stripes_per_block {
            accumulate_stripe(acc, d, n * block_len + k * 64usize, s, k * 8usize)
            k += 1usize
        }
        scramble(acc, s, 192usize - 64usize)
        n += 1usize
    }
    let stripes = ((d.len - 1usize) - block_len * blocks) / 64usize
    var k = 0usize
    while k < stripes {
        accumulate_stripe(acc, d, blocks * block_len + k * 64usize, s, k * 8usize)
        k += 1usize
    }
    accumulate_stripe(acc, d, d.len - 64usize, s, 192usize - 64usize - 7usize)
}

fn merge_accs(acc: []u64, s: []const u8, so: usize, start: u64) -> u64 {
    var result = start
    var i = 0usize
    while i < 4usize {
        result = result +% mulfold(acc[2usize * i] ^ le64(s, so + 16usize * i), acc[2usize * i + 1usize] ^ le64(s, so + 16usize * i + 8usize))
        i += 1usize
    }
    ret avalanche3(result)
}

// The secret the seed derives: each 16-byte pair of the default secret moved by +seed and -seed.
fn custom_secret(out: []u8, seed: u64) {
    var base: [192]u8 = zero
    default_secret(base[0usize..192usize])
    var i = 0usize
    while i < 12usize {
        let lo = le64(base[0usize..192usize], 16usize * i) +% seed
        let hi = le64(base[0usize..192usize], 16usize * i + 8usize) -% seed
        var b = 0usize
        while b < 8usize {
            out[16usize * i + b] = u8((lo >> u64(8usize * b)) & 255u64)
            out[16usize * i + 8usize + b] = u8((hi >> u64(8usize * b)) & 255u64)
            b += 1usize
        }
        i += 1usize
    }
}

fn xxh3_64(data: []const u8, seed: u64) -> u64 {
    var secret: [192]u8 = zero
    if seed == 0u64 { default_secret(secret[0usize..192usize]) } else { custom_secret(secret[0usize..192usize], seed) }
    let s = secret[0usize..192usize]
    var base: [192]u8 = zero
    default_secret(base[0usize..192usize])
    if data.len <= 16usize { ret xxh3_64_short(data, base[0usize..192usize], seed) }
    if data.len <= 240usize { ret xxh3_64_mid(data, base[0usize..192usize], seed) }
    var acc: [8]u64 = zero
    init_acc(acc[0usize..8usize])
    long_loop(acc[0usize..8usize], data, s)
    ret merge_accs(acc[0usize..8usize], s, 11usize, u64(data.len) *% P64_1)
}

// --- XXH3 128.

fn mix32(acc: Hash128, d: []const u8, a1: usize, a2: usize, s: []const u8, so: usize, seed: u64) -> Hash128 {
    var low = acc.low +% mix16(d, a1, s, so, seed)
    low = low ^ (le64(d, a2) +% le64(d, a2 + 8usize))
    var high = acc.high +% mix16(d, a2, s, so + 16usize, seed)
    high = high ^ (le64(d, a1) +% le64(d, a1 + 8usize))
    ret Hash128 { low: low, high: high }
}

fn finish_mid_128(acc: Hash128, len: usize, seed: u64) -> Hash128 {
    let low = acc.low +% acc.high
    let high = acc.low *% P64_1 +% acc.high *% P64_4 +% (u64(len) -% seed) *% P64_2
    ret Hash128 { low: avalanche3(low), high: 0u64 -% avalanche3(high) }
}

fn xxh3_128_short(d: []const u8, s: []const u8, seed0: u64) -> Hash128 {
    let len = d.len
    var seed = seed0
    if len > 8usize {
        let bitflipl = (le64(s, 32usize) ^ le64(s, 40usize)) -% seed
        let bitfliph = (le64(s, 48usize) ^ le64(s, 56usize)) +% seed
        let input_lo = le64(d, 0usize)
        var input_hi = le64(d, len - 8usize)
        var m = mult64to128(input_lo ^ input_hi ^ bitflipl, P64_1)
        m.low = m.low +% ((u64(len) - 1u64) << 54u64)
        input_hi = input_hi ^ bitfliph
        m.high = m.high +% input_hi +% (input_hi & 4294967295u64) *% u64(P32_2 - 1u32)
        m.low = m.low ^ swap64(m.high)
        var h = mult64to128(m.low, P64_2)
        h.high = h.high +% m.high *% P64_2
        ret Hash128 { low: avalanche3(h.low), high: avalanche3(h.high) }
    }
    if len >= 4usize {
        seed = seed ^ (u64(swap32(u32(seed & 4294967295u64))) << 32u64)
        let input_lo = le32(d, 0usize)
        let input_hi = le32(d, len - 4usize)
        let input_64 = u64(input_lo) +% (u64(input_hi) << 32u64)
        let bitflip = (le64(s, 16usize) ^ le64(s, 24usize)) +% seed
        var m = mult64to128(input_64 ^ bitflip, P64_1 +% (u64(len) << 2u64))
        m.high = m.high +% (m.low << 1u64)
        m.low = m.low ^ (m.high >> 3u64)
        m.low = xorshift(m.low, 35u64)
        m.low = m.low *% MX2
        m.low = xorshift(m.low, 28u64)
        m.high = avalanche3(m.high)
        ret m
    }
    if len > 0usize {
        let combinedl = (u32(d[0usize]) << 16u32) | (u32(d[len >> 1usize]) << 24u32) | u32(d[len - 1usize]) | (u32(len) << 8u32)
        let combinedh = rotl32(swap32(combinedl), 13u32)
        let bitflipl = u64(le32(s, 0usize) ^ le32(s, 4usize)) +% seed
        let bitfliph = u64(le32(s, 8usize) ^ le32(s, 12usize)) -% seed
        ret Hash128 { low: avalanche64(u64(combinedl) ^ bitflipl), high: avalanche64(u64(combinedh) ^ bitfliph) }
    }
    let bitflipl = le64(s, 64usize) ^ le64(s, 72usize)
    let bitfliph = le64(s, 80usize) ^ le64(s, 88usize)
    ret Hash128 { low: avalanche64(seed ^ bitflipl), high: avalanche64(seed ^ bitfliph) }
}

fn xxh3_128_mid(d: []const u8, s: []const u8, seed: u64) -> Hash128 {
    let len = d.len
    var acc = Hash128 { low: u64(len) *% P64_1, high: 0u64 }
    if len <= 128usize {
        if len > 32usize {
            if len > 64usize {
                if len > 96usize { acc = mix32(acc, d, 48usize, len - 64usize, s, 96usize, seed) }
                acc = mix32(acc, d, 32usize, len - 48usize, s, 64usize, seed)
            }
            acc = mix32(acc, d, 16usize, len - 32usize, s, 32usize, seed)
        }
        acc = mix32(acc, d, 0usize, len - 16usize, s, 0usize, seed)
        ret finish_mid_128(acc, len, seed)
    }
    var i = 32usize
    while i < 160usize {
        acc = mix32(acc, d, i - 32usize, i - 16usize, s, i - 32usize, seed)
        i += 32usize
    }
    acc.low = avalanche3(acc.low)
    acc.high = avalanche3(acc.high)
    i = 160usize
    while i <= len {
        acc = mix32(acc, d, i - 32usize, i - 16usize, s, 3usize + i - 160usize, seed)
        i += 32usize
    }
    acc = mix32(acc, d, len - 16usize, len - 32usize, s, 136usize - 17usize - 16usize, 0u64 -% seed)
    ret finish_mid_128(acc, len, seed)
}

fn xxh3_128(data: []const u8, seed: u64) -> Hash128 {
    var secret: [192]u8 = zero
    if seed == 0u64 { default_secret(secret[0usize..192usize]) } else { custom_secret(secret[0usize..192usize], seed) }
    let s = secret[0usize..192usize]
    var base: [192]u8 = zero
    default_secret(base[0usize..192usize])
    if data.len <= 16usize { ret xxh3_128_short(data, base[0usize..192usize], seed) }
    if data.len <= 240usize { ret xxh3_128_mid(data, base[0usize..192usize], seed) }
    var acc: [8]u64 = zero
    init_acc(acc[0usize..8usize])
    long_loop(acc[0usize..8usize], data, s)
    let low = merge_accs(acc[0usize..8usize], s, 11usize, u64(data.len) *% P64_1)
    let high = merge_accs(acc[0usize..8usize], s, 192usize - 64usize - 11usize, ~(u64(data.len) *% P64_2))
    ret Hash128 { low: low, high: high }
}

// --- Jenkins one-at-a-time, as digest2int.

fn jenkins_one_at_a_time(data: []const u8, seed: u32) -> u32 {
    var h = seed
    var at = 0usize
    while at < data.len && data[at] != 0u8 {
        var c = u32(data[at])
        if c >= 128u32 { c = c | 4294967040u32 }
        h = h +% c
        h = h +% (h << 10u32)
        h = h ^ (h >> 6u32)
        at += 1usize
    }
    h = h +% (h << 3u32)
    h = h ^ (h >> 11u32)
    ret h +% (h << 15u32)
}
