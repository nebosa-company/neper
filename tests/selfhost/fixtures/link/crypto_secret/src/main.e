// `e.crypto.secret`: GF(2^8) arithmetic against the shift-and-reduce table
// (0x53 * 0xCA == 1), a 16-byte secret split 3-of-5 with LCG coefficients
// matches the Python replica row for row, every 3-subset of the shares and all
// five reconstruct it while a 2-subset does not, a 2-of-2 split of a short
// secret matches and reconstructs, `split_random` round-trips, and the
// argument checks refuse. Each check exits with its own code.

use e.algo.rand
use e.crypto.secret as secret
use e.io
use e.mem
use e.os

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: field arithmetic.
    if secret.gf_mul(83u8, 202u8) != 1u8 || secret.gf_inv(83u8) != 202u8 { os.exit(1i32) }
    var v = 1usize
    while v < 256usize {
        if secret.gf_mul(u8(v), secret.gf_inv(u8(v))) != 1u8 { os.exit(1i32) }
        v += 1usize
    }
    if secret.gf_mul(0u8, 77u8) != 0u8 || secret.gf_inv(0u8) != 0u8 { os.exit(1i32) }

    // 2: 3-of-5 split of 16 bytes with LCG coefficients equals the replica.
    var plain: [16]u8 = zero
    var i = 0usize
    while i < 16usize {
        plain[i] = u8(16usize + i)
        i += 1usize
    }
    var state = 12345u64
    var coefficients: [32]u8 = zero
    i = 0usize
    while i < 32usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        coefficients[i] = u8((state >> 33u32) & 255u64)
        i += 1usize
    }
    let expected: [80]u8 = [80]u8{ 223, 22, 144, 174, 19, 179, 99, 206, 160, 96, 20, 19, 219, 84, 158, 134, 39, 44, 207, 139, 100, 201, 156, 150, 39, 62, 8, 81, 194, 68, 61, 22, 232, 43, 77, 54, 99, 111, 233, 79, 159, 71, 6, 89, 5, 13, 189, 143, 128, 167, 150, 241, 23, 172, 130, 174, 45, 46, 6, 252, 140, 174, 184, 141, 79, 160, 20, 76, 16, 10, 247, 119, 149, 87, 8, 244, 75, 231, 56, 20 }
    var shares: [80]u8 = zero
    if secret.share_size(16usize, 5u8) != 80usize { os.exit(2i32) }
    if secret.split(plain[..], 5u8, 3u8, coefficients[..], shares[..]) != ok { os.exit(2i32) }
    if !same(shares[..], expected[..]) { os.exit(2i32) }

    // 3: every 3-subset reconstructs.
    var xs: [5]u8 = zero
    var picked: [48]u8 = zero
    var out: [16]u8 = zero
    var subsets = 0usize
    var p = 0usize
    while p < 5usize {
        var q = p + 1usize
        while q < 5usize {
            var r = q + 1usize
            while r < 5usize {
                xs[0] = u8(p + 1usize)
                xs[1] = u8(q + 1usize)
                xs[2] = u8(r + 1usize)
                i = 0usize
                while i < 16usize {
                    picked[i] = shares[p * 16usize + i]
                    picked[16usize + i] = shares[q * 16usize + i]
                    picked[32usize + i] = shares[r * 16usize + i]
                    i += 1usize
                }
                if secret.combine(xs[..3usize], picked[..], 16usize, out[..]) != ok { os.exit(3i32) }
                if !same(out[..], plain[..]) { os.exit(3i32) }
                subsets += 1usize
                r += 1usize
            }
            q += 1usize
        }
        p += 1usize
    }
    if subsets != 10usize { os.exit(3i32) }

    // 4: a 2-subset does not (replica: 7e 00 a5 44 ...).
    xs[0] = 1u8
    xs[1] = 2u8
    if secret.combine(xs[..2usize], shares[..32usize], 16usize, out[..]) != ok { os.exit(4i32) }
    if same(out[..], plain[..]) { os.exit(4i32) }
    if out[0] != 126u8 || out[1] != 0u8 || out[2] != 165u8 || out[3] != 68u8 { os.exit(4i32) }

    // 5: all five shares reconstruct.
    i = 0usize
    while i < 5usize {
        xs[i] = u8(i + 1usize)
        i += 1usize
    }
    if secret.combine(xs[..], shares[..], 16usize, out[..]) != ok { os.exit(5i32) }
    if !same(out[..], plain[..]) { os.exit(5i32) }

    // 6: 2-of-2 of a short secret (coefficients continue the LCG).
    var short_coefficients: [3]u8 = zero
    i = 0usize
    while i < 3usize {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        short_coefficients[i] = u8((state >> 33u32) & 255u64)
        i += 1usize
    }
    let short_expected: [6]u8 = [6]u8{ 121, 89, 187, 74, 9, 14 }
    var short_shares: [6]u8 = zero
    if secret.split("hi!", 2u8, 2u8, short_coefficients[..], short_shares[..]) != ok { os.exit(6i32) }
    if !same(short_shares[..], short_expected[..]) { os.exit(6i32) }
    if secret.combine(xs[..2usize], short_shares[..], 3usize, out[..3usize]) != ok { os.exit(6i32) }
    if !same(out[..3usize], "hi!") { os.exit(6i32) }

    // 7: split_random round-trips through shares 2, 4 and 5.
    var rng = rand.pcg64(9u64, 3u64)
    if secret.split_random(plain[..], 5u8, 3u8, shares[..]) != ok { os.exit(7i32) }
    if same(shares[..16usize], plain[..]) { os.exit(7i32) }
    xs[0] = 2u8
    xs[1] = 4u8
    xs[2] = 5u8
    i = 0usize
    while i < 16usize {
        picked[i] = shares[16usize + i]
        picked[16usize + i] = shares[48usize + i]
        picked[32usize + i] = shares[64usize + i]
        i += 1usize
    }
    if secret.combine(xs[..3usize], picked[..], 16usize, out[..]) != ok { os.exit(7i32) }
    if !same(out[..], plain[..]) { os.exit(7i32) }

    // 8: refusals.
    if secret.split(plain[..], 5u8, 1u8, coefficients[..], shares[..]) != secret.Invalid { os.exit(8i32) }
    if secret.split(plain[..], 2u8, 3u8, coefficients[..], shares[..]) != secret.Invalid { os.exit(8i32) }
    if secret.split(plain[..], 5u8, 3u8, coefficients[..31usize], shares[..]) != secret.Invalid { os.exit(8i32) }
    if secret.split(plain[..], 5u8, 3u8, coefficients[..], shares[..79usize]) != secret.TooSmall { os.exit(8i32) }
    if secret.split_random_seeded(plain[..], 5u8, 3u8, &rng, shares[..79usize]) != secret.TooSmall { os.exit(8i32) }
    xs[1] = 2u8
    if secret.combine(xs[..3usize], picked[..], 16usize, out[..]) != secret.Invalid { os.exit(8i32) }
    xs[1] = 0u8
    if secret.combine(xs[..3usize], picked[..], 16usize, out[..]) != secret.Invalid { os.exit(8i32) }
    xs[1] = 4u8
    if secret.combine(xs[..3usize], picked[..], 15usize, out[..]) != secret.Invalid { os.exit(8i32) }
    if secret.combine(xs[..3usize], picked[..], 16usize, out[..15usize]) != secret.TooSmall { os.exit(8i32) }

    try io.print("crypto secret ok\n")
    ret ok
}
