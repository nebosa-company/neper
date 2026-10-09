// Ristretto255 prime-order group over Curve25519 (RFC 9496): decoding with
// built-in validation, canonical encoding, equality, addition, negation,
// scalar multiplication, the Elligator map and the 64-byte element
// derivation. The Edwards field, point and scalar arithmetic rides
// `e.crypto.sign`; only the Ristretto layer (constants, square-root ratio,
// encode/decode/map) is new.
//
// Timing discipline mirrors the reference: validity branches decide over
// public encodings only, while every secret-adjacent choice (square-root
// signs, rotation, absolute values, scalar bits) runs through arithmetic
// masks (`fe_select`) and OR-accumulated comparisons. Treat `Ristretto` as
// opaque: build values by decoding, deriving, or operating on valid ones.

use e.crypto.sign as sign

type Ristretto = struct { point: sign.Pt }
error Invalid

// sqrt(ad - 1) for the edwards25519 a = -1.
fn sqrt_ad_minus_one() -> sign.Fe {
    let bytes: [32]u8 = [32]u8{ 27, 46, 123, 73, 160, 246, 151, 126, 189, 84, 120, 27, 12, 142, 157, 175, 253, 209, 245, 49, 201, 252, 60, 15, 172, 72, 131, 43, 191, 49, 105, 55 }
    ret sign.fe_from_bytes(bytes[0..])
}

// 1 / sqrt(a - d).
fn invsqrt_a_minus_d() -> sign.Fe {
    let bytes: [32]u8 = [32]u8{ 234, 64, 93, 128, 170, 253, 200, 153, 190, 114, 65, 90, 23, 22, 47, 157, 64, 216, 1, 254, 145, 123, 194, 22, 162, 252, 175, 207, 5, 137, 108, 120 }
    ret sign.fe_from_bytes(bytes[0..])
}

// 1 - d^2.
fn one_minus_d_sq() -> sign.Fe {
    let bytes: [32]u8 = [32]u8{ 118, 193, 95, 148, 193, 9, 124, 226, 15, 53, 94, 205, 56, 161, 129, 44, 228, 223, 112, 190, 221, 171, 148, 153, 215, 224, 179, 178, 168, 114, 144, 2 }
    ret sign.fe_from_bytes(bytes[0..])
}

// (d - 1)^2.
fn d_minus_one_sq() -> sign.Fe {
    let bytes: [32]u8 = [32]u8{ 32, 77, 237, 68, 170, 90, 173, 49, 153, 25, 30, 176, 44, 74, 158, 210, 235, 78, 155, 82, 47, 211, 220, 76, 65, 34, 108, 246, 122, 179, 104, 89 }
    ret sign.fe_from_bytes(bytes[0..])
}

// (p - 5) / 8 = 2^252 - 3 for the square-root ratio power.
fn pow_252_3() -> [32]u8 {
    ret [32]u8{ 253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 15 }
}

// Constant-time equality of two field values as 0/1 (canonical encodings
// compared with an OR-accumulated difference, no early exit).
fn ct_eq(a: sign.Fe, b: sign.Fe) -> u8 {
    let x = sign.fe_to_bytes(a)
    let y = sign.fe_to_bytes(b)
    var diff = 0u8
    var i = 0usize
    while i < 32usize {
        diff = diff | (x[i] ^ y[i])
        i += 1usize
    }
    if diff == 0u8 { ret 1u8 }
    ret 0u8
}

// Whether the value is zero, as 0/1.
fn ct_is_zero(a: sign.Fe) -> u8 { ret ct_eq(a, sign.fe_zero()) }

// The absolute value through an arithmetic mask.
fn ct_abs(a: sign.Fe) -> sign.Fe {
    var negative = 0u8
    if sign.fe_is_negative(a) { negative = 1u8 }
    ret sign.fe_select(a, sign.fe_neg(a), negative)
}

// SQRT_RATIO_M1(u, v) per RFC 9496 section 4.2.
fn sqrt_ratio(u: sign.Fe, v: sign.Fe) -> (bool, sign.Fe) {
    let v3 = sign.fe_mul(sign.fe_square(v), v)
    let v7 = sign.fe_mul(sign.fe_square(v3), v)
    var r = sign.fe_mul(sign.fe_mul(u, v3), sign.fe_pow(sign.fe_mul(u, v7), pow_252_3()))
    let check = sign.fe_mul(v, sign.fe_square(r))
    let correct = ct_eq(check, u)
    let flipped = ct_eq(check, sign.fe_neg(u))
    let flipped_i = ct_eq(check, sign.fe_neg(sign.fe_mul(u, sign.fe_sqrt_m1())))
    var pick = 0u8
    if (flipped | flipped_i) == 1u8 { pick = 1u8 }
    r = sign.fe_select(r, sign.fe_mul(sign.fe_sqrt_m1(), r), pick)
    r = ct_abs(r)
    if (correct | flipped) == 1u8 { ret (true, r) }
    ret (false, r)
}

// Decode a 32-byte encoding (RFC 9496 section 4.3.1): strict canonical
// `s < p`, non-negative `s`, a square ratio, non-negative `t`, nonzero `y`.
fn decode(bytes: [32]u8) -> (Ristretto, err) {
    if bytes[31] >= 128u8 { ret (zero, Invalid) }
    if !sign.canonical_field(bytes) { ret (zero, Invalid) }
    let s = sign.fe_from_bytes(bytes[0..])
    if sign.fe_is_negative(s) { ret (zero, Invalid) }
    let ss = sign.fe_square(s)
    let u1 = sign.fe_sub(sign.fe_one(), ss)
    let u2 = sign.fe_add(sign.fe_one(), ss)
    let u2_sqr = sign.fe_square(u2)
    let v = sign.fe_neg(sign.fe_add(sign.fe_mul(sign.fe_d(), sign.fe_square(u1)), u2_sqr))
    let (was_square, invsqrt) = sqrt_ratio(sign.fe_one(), sign.fe_mul(v, u2_sqr))
    let den_x = sign.fe_mul(invsqrt, u2)
    let den_y = sign.fe_mul(sign.fe_mul(invsqrt, den_x), v)
    let x = ct_abs(sign.fe_mul(sign.fe_mul(sign.fe_add(sign.fe_one(), sign.fe_one()), s), den_x))
    let y = sign.fe_mul(u1, den_y)
    let t = sign.fe_mul(x, y)
    if !was_square { ret (zero, Invalid) }
    if sign.fe_is_negative(t) { ret (zero, Invalid) }
    if sign.fe_is_zero(y) { ret (zero, Invalid) }
    var p: sign.Pt = zero
    p.x = x
    p.y = y
    p.z = sign.fe_one()
    p.t = t
    ret (Ristretto { point: p }, ok)
}

// Encode to 32 canonical bytes (RFC 9496 section 4.3.2).
fn encode(p: Ristretto) -> [32]u8 {
    let x0 = p.point.x
    let y0 = p.point.y
    let z0 = p.point.z
    let t0 = p.point.t
    let u1 = sign.fe_mul(sign.fe_add(z0, y0), sign.fe_sub(z0, y0))
    let u2 = sign.fe_mul(x0, y0)
    let (_, invsqrt) = sqrt_ratio(sign.fe_one(), sign.fe_mul(u1, sign.fe_square(u2)))
    let den1 = sign.fe_mul(invsqrt, u1)
    let den2 = sign.fe_mul(invsqrt, u2)
    let z_inv = sign.fe_mul(sign.fe_mul(den1, den2), t0)
    let ix0 = sign.fe_mul(x0, sign.fe_sqrt_m1())
    let iy0 = sign.fe_mul(y0, sign.fe_sqrt_m1())
    let enchanted = sign.fe_mul(den1, invsqrt_a_minus_d())
    var rotate = 0u8
    if sign.fe_is_negative(sign.fe_mul(t0, z_inv)) { rotate = 1u8 }
    let x = sign.fe_select(x0, iy0, rotate)
    let y = sign.fe_select(y0, ix0, rotate)
    let den_inv = sign.fe_select(den2, enchanted, rotate)
    var final_y = y
    if sign.fe_is_negative(sign.fe_mul(x, z_inv)) { final_y = sign.fe_neg(y) }
    ret sign.fe_to_bytes(ct_abs(sign.fe_mul(den_inv, sign.fe_sub(p.point.z, final_y))))
}

// Equality through the encodings, which the RFC blesses as equivalent.
fn equals(a: Ristretto, b: Ristretto) -> bool { ret sign.bytes_equal(encode(a), encode(b)) }

// The identity element.
fn identity() -> Ristretto { ret Ristretto { point: sign.pt_identity() } }

// The canonical generator (the Edwards base point inside).
fn base() -> Ristretto { ret Ristretto { point: sign.pt_base() } }

// Negation.
fn neg(p: Ristretto) -> Ristretto {
    ret Ristretto { point: sign.Pt { x: sign.fe_neg(p.point.x), y: p.point.y, z: p.point.z, t: sign.fe_neg(p.point.t) } }
}

// Addition.
fn add(p: Ristretto, q: Ristretto) -> Ristretto { ret Ristretto { point: sign.pt_add(p.point, q.point) } }

// Subtraction.
fn sub(p: Ristretto, q: Ristretto) -> Ristretto { ret add(p, neg(q)) }

// Scalar multiplication by the integer mod l of `scalar` (reduced first,
// constant-time in the scalar through the ladder).
fn mul(scalar: [32]u8, p: Ristretto) -> Ristretto {
    let reduced = sign.sc_to_bytes(sign.sc_from_bytes(scalar[0..]))
    ret Ristretto { point: sign.pt_mul(reduced, p.point) }
}

// The Elligator MAP of a 32-byte string (RFC 9496 section 4.3.4): the top
// bit masked, reduced mod p, then the one-shot map.
fn map(input: [32]u8) -> Ristretto {
    var masked: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        masked[i] = input[i]
        i += 1usize
    }
    masked[31] = masked[31] & 127u8
    let t = sign.fe_from_bytes(masked[0..])
    let r = sign.fe_mul(sign.fe_sqrt_m1(), sign.fe_square(t))
    let u = sign.fe_mul(sign.fe_add(r, sign.fe_one()), one_minus_d_sq())
    let v = sign.fe_mul(sign.fe_neg(sign.fe_add(sign.fe_mul(r, sign.fe_d()), sign.fe_one())), sign.fe_add(r, sign.fe_d()))
    let (was_square, s0) = sqrt_ratio(u, v)
    var st_neg = 0u8
    if sign.fe_is_negative(sign.fe_mul(s0, t)) { st_neg = 1u8 }
    let s_prime = sign.fe_neg(sign.fe_select(sign.fe_mul(s0, t), sign.fe_neg(sign.fe_mul(s0, t)), st_neg))
    var pick_s = 0u8
    if was_square { pick_s = 1u8 }
    let s = sign.fe_select(s_prime, s0, pick_s)
    var pick_c = 0u8
    if was_square { pick_c = 1u8 }
    let c = sign.fe_select(r, sign.fe_neg(sign.fe_one()), pick_c)
    let n = sign.fe_sub(sign.fe_mul(sign.fe_mul(c, sign.fe_sub(r, sign.fe_one())), d_minus_one_sq()), v)
    let w0 = sign.fe_mul(sign.fe_add(s, s), v)
    let w1 = sign.fe_mul(n, sqrt_ad_minus_one())
    let w2 = sign.fe_add(sign.fe_one(), sign.fe_neg(sign.fe_square(s)))
    let w3 = sign.fe_add(sign.fe_one(), sign.fe_square(s))
    var q: sign.Pt = zero
    q.x = sign.fe_mul(w0, w3)
    q.y = sign.fe_mul(w2, w1)
    q.z = sign.fe_mul(w1, w3)
    q.t = sign.fe_mul(w0, w2)
    ret Ristretto { point: q }
}

// The element derivation of a 64-byte string: MAP each half and add (RFC
// 9496 section 4.3.4). Hash the message first (SHA-512 is at hand); domain
// separation stays with the caller.
fn derive(input: []const u8) -> (Ristretto, err) {
    if input.len != 64usize { ret (zero, Invalid) }
    var first: [32]u8 = zero
    var second: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        first[i] = input[i]
        second[i] = input[i + 32usize]
        i += 1usize
    }
    ret (add(map(first), map(second)), ok)
}
