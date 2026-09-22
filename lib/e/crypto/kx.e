// X25519 by RFC 7748: the Montgomery ladder over the field 2^255 - 19, the field held
// in ten limbs alternating 26 and 25 bits so that every product of two limbs fits a
// 64-bit word with room for the ten-term sums -- the arrangement of the reference
// implementation, carried here without its assembly. The scalar is clamped by the
// operation, and an all-zero secret_out secret -- a peer key of small order -- is
// `InvalidKey`.
//
// ponytail: the ladder swaps by an arithmetic mask so the sequence of operations does
// not depend on the scalar; nothing else here claims constant time.

use e.mem
use e.algo.bignum as bignum

type X25519PublicKey = struct { bytes: [32]u8 }
type X25519SecretKey = struct { bytes: [32]u8 }
type X25519SharedKey = struct { bytes: [32]u8 }
error InvalidKey
error TooSmall

type Fe = struct { v: [10]i64 }

fn fe_zero() -> Fe {
    var f: Fe = zero
    ret f
}

fn fe_one() -> Fe {
    var f: Fe = zero
    f.v[0] = 1i64
    ret f
}

fn load24(bytes: []const u8, at: usize) -> i64 {
    ret i64(bytes[at]) | (i64(bytes[at + 1usize]) << 8u32) | (i64(bytes[at + 2usize]) << 16u32)
}

fn load32(bytes: []const u8, at: usize) -> i64 {
    ret load24(bytes, at) | (i64(bytes[at + 3usize]) << 24u32)
}

// Thirty-two bytes little-endian into the ten limbs, the top bit ignored.
fn fe_from_bytes(bytes: []const u8) -> Fe {
    var h0 = load32(bytes, 0usize)
    var h1 = load24(bytes, 4usize) << 6u32
    var h2 = load24(bytes, 7usize) << 5u32
    var h3 = load24(bytes, 10usize) << 3u32
    var h4 = load24(bytes, 13usize) << 2u32
    var h5 = load32(bytes, 16usize)
    var h6 = load24(bytes, 20usize) << 7u32
    var h7 = load24(bytes, 23usize) << 5u32
    var h8 = load24(bytes, 26usize) << 4u32
    var h9 = (load24(bytes, 29usize) & 8388607i64) << 2u32
    var f: Fe = zero
    f.v[0] = h0
    f.v[1] = h1
    f.v[2] = h2
    f.v[3] = h3
    f.v[4] = h4
    f.v[5] = h5
    f.v[6] = h6
    f.v[7] = h7
    f.v[8] = h8
    f.v[9] = h9
    ret fe_carry(f)
}

// Carries every limb into the next, the top limb's carry times 19 into the first.
fn fe_carry(f: Fe) -> Fe {
    var h = f
    var i = 0usize
    while i < 10usize {
        var bits = 26u32
        if i % 2usize == 1usize { bits = 25u32 }
        let half = 1i64 << (bits - 1u32)
        let carry = (h.v[i] + half) >> bits
        if i == 9usize {
            h.v[0] += carry * 19i64
        } else {
            h.v[i + 1usize] += carry
        }
        h.v[i] -= carry << bits
        i += 1usize
    }
    // One more pass over the first two limbs settles the carry from the top.
    let carry0 = (h.v[0] + (1i64 << 25u32)) >> 26u32
    h.v[1] += carry0
    h.v[0] -= carry0 << 26u32
    let carry1 = (h.v[1] + (1i64 << 24u32)) >> 25u32
    h.v[2] += carry1
    h.v[1] -= carry1 << 25u32
    ret h
}

fn fe_add(a: Fe, b: Fe) -> Fe {
    var h: Fe = zero
    var i = 0usize
    while i < 10usize {
        h.v[i] = a.v[i] + b.v[i]
        i += 1usize
    }
    ret h
}

fn fe_sub(a: Fe, b: Fe) -> Fe {
    var h: Fe = zero
    var i = 0usize
    while i < 10usize {
        h.v[i] = a.v[i] - b.v[i]
        i += 1usize
    }
    ret h
}

// The product, reduced: limb i of the result collects a[j] * b[i - j], with the terms
// that wrap past limb 9 scaled by 19 and the odd-position products doubled where two
// 25-bit limbs meet.
fn fe_mul(a: Fe, b: Fe) -> Fe {
    var h: [10]i64 = zero
    var i = 0usize
    while i < 10usize {
        var j = 0usize
        while j < 10usize {
            var term = a.v[i] * b.v[j]
            // Two odd limbs multiply to 2^50 units short of the 2^51 boundary: double.
            if i % 2usize == 1usize && j % 2usize == 1usize { term = term * 2i64 }
            let k = i + j
            if k >= 10usize {
                h[k - 10usize] += term * 19i64
            } else {
                h[k] += term
            }
            j += 1usize
        }
        i += 1usize
    }
    var f: Fe = zero
    i = 0usize
    while i < 10usize {
        f.v[i] = h[i]
        i += 1usize
    }
    ret fe_carry(fe_carry(f))
}

fn fe_square(a: Fe) -> Fe { ret fe_mul(a, a) }

fn fe_mul_small(a: Fe, small: i64) -> Fe {
    var h: Fe = zero
    var i = 0usize
    while i < 10usize {
        h.v[i] = a.v[i] * small
        i += 1usize
    }
    ret fe_carry(h)
}

// a^(p - 2) by the reference's addition chain.
fn fe_invert(z: Fe) -> Fe {
    let z2 = fe_square(z)
    var t = fe_square(z2)
    t = fe_square(t)
    let z9 = fe_mul(t, z)
    let z11 = fe_mul(z9, z2)
    t = fe_square(z11)
    let z2_5_0 = fe_mul(t, z9)
    t = fe_square(z2_5_0)
    var i = 1usize
    while i < 5usize {
        t = fe_square(t)
        i += 1usize
    }
    let z2_10_0 = fe_mul(t, z2_5_0)
    t = fe_square(z2_10_0)
    i = 1usize
    while i < 10usize {
        t = fe_square(t)
        i += 1usize
    }
    let z2_20_0 = fe_mul(t, z2_10_0)
    t = fe_square(z2_20_0)
    i = 1usize
    while i < 20usize {
        t = fe_square(t)
        i += 1usize
    }
    t = fe_mul(t, z2_20_0)
    t = fe_square(t)
    i = 1usize
    while i < 10usize {
        t = fe_square(t)
        i += 1usize
    }
    let z2_50_0 = fe_mul(t, z2_10_0)
    t = fe_square(z2_50_0)
    i = 1usize
    while i < 50usize {
        t = fe_square(t)
        i += 1usize
    }
    let z2_100_0 = fe_mul(t, z2_50_0)
    t = fe_square(z2_100_0)
    i = 1usize
    while i < 100usize {
        t = fe_square(t)
        i += 1usize
    }
    t = fe_mul(t, z2_100_0)
    t = fe_square(t)
    i = 1usize
    while i < 50usize {
        t = fe_square(t)
        i += 1usize
    }
    t = fe_mul(t, z2_50_0)
    t = fe_square(t)
    t = fe_square(t)
    t = fe_square(t)
    t = fe_square(t)
    t = fe_square(t)
    ret fe_mul(t, z11)
}

// Fully reduced to [0, p) and packed little-endian.
fn fe_to_bytes(f: Fe) -> [32]u8 {
    var h = fe_carry(f)
    // Reduce completely: add 19, take the carry out of the top as q, then subtract q * p.
    var q = (19i64 * h.v[9] + (1i64 << 24u32)) >> 25u32
    q = (h.v[0] + q) >> 26u32
    q = (h.v[1] + q) >> 25u32
    q = (h.v[2] + q) >> 26u32
    q = (h.v[3] + q) >> 25u32
    q = (h.v[4] + q) >> 26u32
    q = (h.v[5] + q) >> 25u32
    q = (h.v[6] + q) >> 26u32
    q = (h.v[7] + q) >> 25u32
    q = (h.v[8] + q) >> 26u32
    q = (h.v[9] + q) >> 25u32
    h.v[0] += 19i64 * q
    var i = 0usize
    while i < 9usize {
        var bits = 26u32
        if i % 2usize == 1usize { bits = 25u32 }
        let carry = h.v[i] >> bits
        h.v[i + 1usize] += carry
        h.v[i] -= carry << bits
        i += 1usize
    }
    h.v[9] -= (h.v[9] >> 25u32) << 25u32
    var out: [32]u8 = zero
    out[0] = u8(h.v[0] & 255i64)
    out[1] = u8((h.v[0] >> 8u32) & 255i64)
    out[2] = u8((h.v[0] >> 16u32) & 255i64)
    out[3] = u8(((h.v[0] >> 24u32) | (h.v[1] << 2u32)) & 255i64)
    out[4] = u8((h.v[1] >> 6u32) & 255i64)
    out[5] = u8((h.v[1] >> 14u32) & 255i64)
    out[6] = u8(((h.v[1] >> 22u32) | (h.v[2] << 3u32)) & 255i64)
    out[7] = u8((h.v[2] >> 5u32) & 255i64)
    out[8] = u8((h.v[2] >> 13u32) & 255i64)
    out[9] = u8(((h.v[2] >> 21u32) | (h.v[3] << 5u32)) & 255i64)
    out[10] = u8((h.v[3] >> 3u32) & 255i64)
    out[11] = u8((h.v[3] >> 11u32) & 255i64)
    out[12] = u8(((h.v[3] >> 19u32) | (h.v[4] << 6u32)) & 255i64)
    out[13] = u8((h.v[4] >> 2u32) & 255i64)
    out[14] = u8((h.v[4] >> 10u32) & 255i64)
    out[15] = u8((h.v[4] >> 18u32) & 255i64)
    out[16] = u8(h.v[5] & 255i64)
    out[17] = u8((h.v[5] >> 8u32) & 255i64)
    out[18] = u8((h.v[5] >> 16u32) & 255i64)
    out[19] = u8(((h.v[5] >> 24u32) | (h.v[6] << 1u32)) & 255i64)
    out[20] = u8((h.v[6] >> 7u32) & 255i64)
    out[21] = u8((h.v[6] >> 15u32) & 255i64)
    out[22] = u8(((h.v[6] >> 23u32) | (h.v[7] << 3u32)) & 255i64)
    out[23] = u8((h.v[7] >> 5u32) & 255i64)
    out[24] = u8((h.v[7] >> 13u32) & 255i64)
    out[25] = u8(((h.v[7] >> 21u32) | (h.v[8] << 4u32)) & 255i64)
    out[26] = u8((h.v[8] >> 4u32) & 255i64)
    out[27] = u8((h.v[8] >> 12u32) & 255i64)
    out[28] = u8(((h.v[8] >> 20u32) | (h.v[9] << 6u32)) & 255i64)
    out[29] = u8((h.v[9] >> 2u32) & 255i64)
    out[30] = u8((h.v[9] >> 10u32) & 255i64)
    out[31] = u8((h.v[9] >> 18u32) & 255i64)
    ret out
}

// Swaps the two when `swap` is one, by an arithmetic mask rather than a branch.
fn fe_cswap(a: *Fe, b: *Fe, swap: i64) {
    let mask = 0i64 - swap
    var i = 0usize
    while i < 10usize {
        let x = (a.v[i] ^ b.v[i]) & mask
        a.v[i] = a.v[i] ^ x
        b.v[i] = b.v[i] ^ x
        i += 1usize
    }
}

// The ladder of RFC 7748 section 5, with (121665 = (486662 - 2) / 4).
fn x25519(scalar_in: [32]u8, point: [32]u8) -> [32]u8 {
    var scalar = scalar_in
    scalar[0] = scalar[0] & 248u8
    scalar[31] = scalar[31] & 127u8
    scalar[31] = scalar[31] | 64u8
    let x1 = fe_from_bytes(point[0..])
    var x2 = fe_one()
    var z2 = fe_zero()
    var x3 = x1
    var z3 = fe_one()
    var swap = 0i64
    var t = 255usize
    while t > 0usize {
        t -= 1usize
        let bit = i64((scalar[t / 8usize] >> u8(t % 8usize)) & 1u8)
        swap = swap ^ bit
        fe_cswap(&x2, &x3, swap)
        fe_cswap(&z2, &z3, swap)
        swap = bit
        let a = fe_add(x2, z2)
        let aa = fe_square(a)
        let b = fe_sub(x2, z2)
        let bb = fe_square(b)
        let e = fe_sub(aa, bb)
        let c = fe_add(x3, z3)
        let d = fe_sub(x3, z3)
        let da = fe_mul(d, a)
        let cb = fe_mul(c, b)
        x3 = fe_square(fe_add(da, cb))
        z3 = fe_mul(x1, fe_square(fe_sub(da, cb)))
        x2 = fe_mul(aa, bb)
        z2 = fe_mul(e, fe_add(aa, fe_mul_small(e, 121665i64)))
    }
    fe_cswap(&x2, &x3, swap)
    fe_cswap(&z2, &z3, swap)
    ret fe_to_bytes(fe_mul(x2, fe_invert(z2)))
}

fn x25519_public_from_secret(secret: X25519SecretKey) -> X25519PublicKey {
    var base: [32]u8 = zero
    base[0] = 9u8
    var p: X25519PublicKey = zero
    p.bytes = x25519(secret.bytes, base)
    ret p
}

fn x25519_exchange(secret: X25519SecretKey, peer: X25519PublicKey) -> (X25519SharedKey, err) {
    var secret_out: X25519SharedKey = zero
    secret_out.bytes = x25519(secret.bytes, peer.bytes)
    var any = 0u8
    var i = 0usize
    while i < 32usize {
        any = any | secret_out.bytes[i]
        i += 1usize
    }
    if any == 0u8 { ret (zero, InvalidKey) }
    ret (secret_out, ok)
}

// --- Finite-field Diffie-Hellman over RFC 7919 ffdhe2048 (generator 2) with
// `e.algo.bignum`. Values are big-endian byte strings; a public value or shared
// secret is always the group's 256 bytes, zero-padded on the left. A peer value is
// accepted only in the open interval (1, p - 1) and in the prime-order subgroup,
// which costs one more exponentiation than the exchange itself.
// ponytail: the exponentiation is bignum's square-and-multiply over Montgomery
// products, not constant time; only ffdhe2048 is offered, the other RFC 7919 groups are a hex
// string each away.
fn ffdhe2048_hex() -> str {
    ret "ffffffffffffffffadf85458a2bb4a9aafdc5620273d3cf1d8b9c583ce2d3695a9e13641146433fbcc939dce249b3ef97d2fe363630c75d8f681b202aec4617ad3df1ed5d5fd65612433f51f5f066ed0856365553ded1af3b557135e7f57c935984f0c70e0e68b77e2a689daf3efe8721df158a136ade73530acca4f483a797abc0ab182b324fb61d108a94bb2c8e3fbb96adab760d7f4681d4f42a3de394df4ae56ede76372bb190b07a7c8ee0a6d709e02fce1cdf7e2ecc03404cd28342f619172fe9ce98583ff8e4f1232eef28183c3fe3b1b4c6fad733bb5fcbc2ec22005c58ef1837d1683b2c6f34a26c1b2effa886b423861285c97ffffffffffffffff"
}

fn dh_bytes() -> usize { ret 256usize }

fn dh_prime(a: *mem.Arena) -> (bignum.Int, err) {
    let (p, parse_error) = bignum.int_parse(a, ffdhe2048_hex(), 16u8)
    ret (p, parse_error)
}

// 1 < value < p - 1.
fn dh_in_range(a: *mem.Arena, value: bignum.Int, p: bignum.Int) -> bool {
    let (one, one_error) = bignum.int_from_i64(a, 1i64)
    if one_error != ok { ret false }
    let (p_minus_1, sub_error) = bignum.int_sub(a, p, one)
    if sub_error != ok { ret false }
    ret bignum.int_cmp(value, one) > 0i32 && bignum.int_cmp(value, p_minus_1) < 0i32
}

fn dh_power(a: *mem.Arena, base: bignum.Int, exponent: []const u8, out: []u8) -> err {
    let (p, p_error) = dh_prime(a)
    if p_error != ok { ret p_error }
    let (x, x_error) = bignum.int_from_bytes_be(a, exponent)
    if x_error != ok { ret x_error }
    if !dh_in_range(a, x, p) { ret InvalidKey }
    let (y, pow_error) = bignum.int_mod_pow(a, base, x, p)
    if pow_error != ok { ret pow_error }
    ret bignum.int_to_bytes_be(y, out[..dh_bytes()])
}

// 2^secret mod p as 256 bytes; the secret must lie in (1, p - 1).
fn dh_public(a: *mem.Arena, secret: []const u8, out: []u8) -> (usize, err) {
    if out.len < dh_bytes() { ret (0usize, TooSmall) }
    let (two, two_error) = bignum.int_from_i64(a, 2i64)
    if two_error != ok { ret (0usize, two_error) }
    let power_error = dh_power(a, two, secret, out)
    if power_error != ok { ret (0usize, power_error) }
    ret (dh_bytes(), ok)
}

// True when the peer value is in (1, p - 1) and y^((p - 1) / 2) == 1.
fn dh_valid_public(a: *mem.Arena, public: []const u8) -> bool {
    let (p, p_error) = dh_prime(a)
    if p_error != ok { ret false }
    let (y, y_error) = bignum.int_from_bytes_be(a, public)
    if y_error != ok || !dh_in_range(a, y, p) { ret false }
    let (one, one_error) = bignum.int_from_i64(a, 1i64)
    if one_error != ok { ret false }
    let (two, two_error) = bignum.int_from_i64(a, 2i64)
    if two_error != ok { ret false }
    let (p_minus_1, sub_error) = bignum.int_sub(a, p, one)
    if sub_error != ok { ret false }
    let (q, _, div_error) = bignum.int_divmod(a, p_minus_1, two)
    if div_error != ok { ret false }
    let (check, pow_error) = bignum.int_mod_pow(a, y, q, p)
    if pow_error != ok { ret false }
    ret bignum.int_cmp(check, one) == 0i32
}

// peer_public^secret mod p as 256 bytes; a peer value outside the subgroup is `InvalidKey`.
fn dh_shared(a: *mem.Arena, secret: []const u8, peer_public: []const u8, out: []u8) -> (usize, err) {
    if out.len < dh_bytes() { ret (0usize, TooSmall) }
    if !dh_valid_public(a, peer_public) { ret (0usize, InvalidKey) }
    let (y, y_error) = bignum.int_from_bytes_be(a, peer_public)
    if y_error != ok { ret (0usize, y_error) }
    let power_error = dh_power(a, y, secret, out)
    if power_error != ok { ret (0usize, power_error) }
    ret (dh_bytes(), ok)
}

fn dh(a: *mem.Arena, secret: []const u8, peer_public: []const u8, out: []u8) -> (usize, err) {
    let (written, shared_error) = dh_shared(a, secret, peer_public, out)
    ret (written, shared_error)
}
