// More parameters than the prologue moves directly (sixteen), with the first four in argument registers, one unused, and a
// slice among them: every one must arrive.
fn weigh(a: i64, b: i64, unused: i64, d: i64, e: i64, f: i64, g: i64, h: i64, i: i64, j: i64, k: i64, l: i64, m: i64, n: i64, o: i64, p: i64, q: i64, r: i64, tail: []i64) -> i64 {
    var sum = a + 2i64 * b + 4i64 * d + 8i64 * e + 16i64 * f + 32i64 * g + 64i64 * h + 128i64 * i
    sum += 256i64 * j + 512i64 * k + 1024i64 * l + 2048i64 * m + 4096i64 * n + 8192i64 * o + 16384i64 * p + 32768i64 * q + 65536i64 * r
    ret sum + tail[1usize]
}

fn weigh_pair(x: i64, y: i64) -> i64 {
    ret x * 10i64 + y
}

// the four register arguments passed on in another order, so the prologue's parallel move has a cycle to break
fn swap4(a: i64, b: i64, c: i64, d: i64) -> i64 {
    ret weigh_pair(d, c) * 100i64 + weigh_pair(b, a)
}

fn main() -> i64 {
    var tail: [3]i64 = zero
    tail[1usize] = 1000000i64
    let got = weigh(1i64, 1i64, 99i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, 1i64, tail[..])
    // the coefficients are 1, 2, 4, ..., 65536 (seventeen of them, the unused one has none): 131071
    if got != 131071i64 + 1000000i64 { ret 1i64 }
    if swap4(1i64, 2i64, 3i64, 4i64) != 4321i64 { ret 2i64 }
    ret 0i64
}
