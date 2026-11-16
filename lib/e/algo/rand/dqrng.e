// R dqrng's xoroshiro128+, xoroshiro128++, xoshiro256+ and xoshiro256++ generators, seeded by the
// splitmix64 chain of dqset.seed, and `unif` (dqrunif: the top 53 bits scaled by 2^-53, then min + (max -
// min) * u). The state is four words; the 128-bit generators use the first two.
//
// Not here: pcg64 and threefry, the ziggurat normal and exponential generators, dqsample, streams and
// jumps, and multi-word seeds.

type Gen = struct { s0: u64, s1: u64, s2: u64, s3: u64, kind: u8 }

fn rotl(v: u64, k: u64) -> u64 { ret (v << k) | (v >> (64u64 - k)) }

// splitmix64: the next state and output
fn splitmix(x: u64) -> (u64, u64) {
    let y = x +% 11400714819323198485u64
    var z = y
    z = (z ^ (z >> 30u64)) *% 13787848793156543929u64
    z = (z ^ (z >> 27u64)) *% 10723151780598845931u64
    ret (y, z ^ (z >> 31u64))
}

// kind: 0 xoroshiro128+, 1 xoroshiro128++, 2 xoshiro256+, 3 xoshiro256++
fn seed(kind: u8, s: u64) -> Gen {
    var x = s
    var g = Gen { s0: 0u64, s1: 0u64, s2: 0u64, s3: 0u64, kind: kind }
    let (x1, v1) = splitmix(x)
    let (x2, v2) = splitmix(x1)
    g.s0 = v1
    g.s1 = v2
    if kind >= 2u8 {
        let (x3, v3) = splitmix(x2)
        let (x4, v4) = splitmix(x3)
        g.s2 = v3
        g.s3 = v4
    }
    ret g
}

// the next 64-bit output
fn next(g: *Gen) -> u64 {
    if g.kind <= 1u8 {
        var r = g.s0 +% g.s1
        if g.kind == 1u8 { r = rotl(g.s0 +% g.s1, 17u64) +% g.s0 }
        let t = g.s1 ^ g.s0
        if g.kind == 1u8 {
            g.s0 = rotl(g.s0, 49u64) ^ t ^ (t << 21u64)
            g.s1 = rotl(t, 28u64)
        } else {
            g.s0 = rotl(g.s0, 24u64) ^ t ^ (t << 16u64)
            g.s1 = rotl(t, 37u64)
        }
        ret r
    }
    var r = g.s0 +% g.s3
    if g.kind == 3u8 { r = rotl(g.s0 +% g.s3, 23u64) +% g.s0 }
    let t = g.s1 << 17u64
    g.s2 = g.s2 ^ g.s0
    g.s3 = g.s3 ^ g.s1
    g.s1 = g.s1 ^ g.s2
    g.s0 = g.s0 ^ g.s3
    g.s2 = g.s2 ^ t
    g.s3 = rotl(g.s3, 45u64)
    ret r
}

// dqrunif(1, min, max)
fn unif(g: *Gen, lo: f64, hi: f64) -> f64 {
    let u = f64(next(g) >> 11u64) * 1.1102230246251565e-16f64
    ret lo + (hi - lo) * u
}
