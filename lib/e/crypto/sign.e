// Ed25519 by RFC 8032: the twisted Edwards curve over 2^255 - 19 in extended
// coordinates with the unified addition formula, the field in the ten-limb form
// `e.crypto.kx` uses, scalars mod L as eight 32-bit limbs reduced bit by bit. Keys are
// seeds; signing derives the scalar and prefix from SHA-512 of the seed. Verification
// rejects a non-canonical point or scalar encoding and a public key of small order.
//
// ponytail: scalar multiplication is double-and-add and varies with the scalar; the
// field core is duplicated from kx.e because a fence admits no shared private helper.
use e.crypto.hash as hash
use e.crypto.mac as mac
use e.algo.bignum as bignum
use e.mem

type Ed25519PublicKey = struct { bytes: [32]u8 }
type Ed25519SecretKey = struct { bytes: [32]u8 }
type Ed25519Signature = struct { bytes: [64]u8 }
type P256PublicKey = struct { bytes: [65]u8 }
error InvalidKey
error InvalidSignature
error TooSmall
error Invalid

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


fn fe_neg(a: Fe) -> Fe { ret fe_sub(fe_zero(), a) }

fn bytes_equal(a: [32]u8, b: [32]u8) -> bool {
    var i = 0usize
    while i < 32usize {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn fe_equal(a: Fe, b: Fe) -> bool { ret bytes_equal(fe_to_bytes(a), fe_to_bytes(b)) }

fn fe_is_zero(a: Fe) -> bool { ret fe_equal(a, fe_zero()) }

fn fe_is_negative(a: Fe) -> bool {
    let bytes = fe_to_bytes(a)
    ret bytes[0] & 1u8 == 1u8
}

// a^e for a 255-bit little-endian exponent, square-and-multiply from the top.
fn fe_pow(a: Fe, exponent: [32]u8) -> Fe {
    var r = fe_one()
    var i = 255usize
    while i > 0usize {
        i -= 1usize
        r = fe_square(r)
        if (exponent[i / 8usize] >> u8(i % 8usize)) & 1u8 == 1u8 { r = fe_mul(r, a) }
    }
    ret r
}

fn fe_invert(a: Fe) -> Fe {
    let p_minus_2: [32]u8 = [32]u8{ 235, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 127 }
    ret fe_pow(a, p_minus_2)
}

fn fe_d() -> Fe {
    let bytes: [32]u8 = [32]u8{ 163, 120, 89, 19, 202, 77, 235, 117, 171, 216, 65, 65, 77, 10, 112, 0, 152, 232, 121, 119, 121, 64, 199, 140, 115, 254, 111, 43, 238, 108, 3, 82 }
    ret fe_from_bytes(bytes[0..])
}

fn fe_2d() -> Fe {
    let bytes: [32]u8 = [32]u8{ 89, 241, 178, 38, 148, 155, 214, 235, 86, 177, 131, 130, 154, 20, 224, 0, 48, 209, 243, 238, 242, 128, 142, 25, 231, 252, 223, 86, 220, 217, 6, 36 }
    ret fe_from_bytes(bytes[0..])
}

fn fe_sqrt_m1() -> Fe {
    let bytes: [32]u8 = [32]u8{ 176, 160, 14, 74, 39, 27, 238, 196, 120, 228, 47, 173, 6, 24, 67, 47, 167, 215, 251, 61, 153, 0, 77, 43, 11, 223, 193, 79, 128, 36, 131, 43 }
    ret fe_from_bytes(bytes[0..])
}

// A point in extended coordinates: x = X/Z, y = Y/Z, T = XY/Z.
type Pt = struct { x: Fe, y: Fe, z: Fe, t: Fe }

fn pt_identity() -> Pt {
    var p: Pt = zero
    p.x = fe_zero()
    p.y = fe_one()
    p.z = fe_one()
    p.t = fe_zero()
    ret p
}

// The unified formula (add-2008-hwcd-3), sound for doubling too.
fn pt_add(p: Pt, q: Pt) -> Pt {
    let a = fe_mul(fe_sub(p.y, p.x), fe_sub(q.y, q.x))
    let b = fe_mul(fe_add(p.y, p.x), fe_add(q.y, q.x))
    let c = fe_mul(fe_mul(p.t, fe_2d()), q.t)
    let zz = fe_mul(p.z, q.z)
    let d = fe_add(zz, zz)
    let e = fe_sub(b, a)
    let f = fe_sub(d, c)
    let g = fe_add(d, c)
    let h = fe_add(b, a)
    var r: Pt = zero
    r.x = fe_mul(e, f)
    r.y = fe_mul(g, h)
    r.t = fe_mul(e, h)
    r.z = fe_mul(f, g)
    ret r
}

fn pt_mul(scalar: [32]u8, p: Pt) -> Pt {
    var r = pt_identity()
    var i = 256usize
    while i > 0usize {
        i -= 1usize
        r = pt_add(r, r)
        if (scalar[i / 8usize] >> u8(i % 8usize)) & 1u8 == 1u8 { r = pt_add(r, p) }
    }
    ret r
}

fn pt_is_identity(p: Pt) -> bool {
    ret fe_is_zero(p.x) && fe_equal(p.y, p.z)
}

fn pt_encode(p: Pt) -> [32]u8 {
    let inv = fe_invert(p.z)
    let x = fe_mul(p.x, inv)
    let y = fe_mul(p.y, inv)
    var out = fe_to_bytes(y)
    if fe_is_negative(x) { out[31] = out[31] | 128u8 }
    ret out
}

// True when the 255-bit value in `bytes` (top bit ignored) is below p.
fn canonical_field(bytes: [32]u8) -> bool {
    if bytes[31] & 127u8 != 127u8 { ret true }
    var i = 1usize
    while i < 31usize {
        if bytes[i] != 255u8 { ret true }
        i += 1usize
    }
    ret bytes[0] < 237u8
}

fn pt_decode(bytes: [32]u8) -> (Pt, bool) {
    if !canonical_field(bytes) { ret (zero, false) }
    let sign = bytes[31] >> 7u8
    let y = fe_from_bytes(bytes[0..])
    let y2 = fe_square(y)
    let u = fe_sub(y2, fe_one())
    let v = fe_add(fe_mul(fe_d(), y2), fe_one())
    let v3 = fe_mul(fe_square(v), v)
    let v7 = fe_mul(fe_square(v3), v)
    let exponent: [32]u8 = [32]u8{ 253, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 15 }
    var x = fe_mul(fe_mul(u, v3), fe_pow(fe_mul(u, v7), exponent))
    let vx2 = fe_mul(v, fe_square(x))
    if !fe_equal(vx2, u) {
        if !fe_equal(vx2, fe_neg(u)) { ret (zero, false) }
        x = fe_mul(x, fe_sqrt_m1())
    }
    if fe_is_zero(x) && sign == 1u8 { ret (zero, false) }
    var negative = 0u8
    if fe_is_negative(x) { negative = 1u8 }
    if negative != sign { x = fe_neg(x) }
    var p: Pt = zero
    p.x = x
    p.y = y
    p.z = fe_one()
    p.t = fe_mul(x, y)
    ret (p, true)
}

fn pt_base() -> Pt {
    var bytes: [32]u8 = zero
    bytes[0] = 88u8
    var i = 1usize
    while i < 32usize {
        bytes[i] = 102u8
        i += 1usize
    }
    let (b, good) = pt_decode(bytes)
    ret b
}

// Scalars mod L = 2^252 + 27742317777372353535851937790883648493, little-endian limbs.
type Sc = struct { v: [8]u32 }

fn sc_l(index: usize) -> u32 {
    if index == 0usize { ret 1559614445u32 }
    if index == 1usize { ret 1477600026u32 }
    if index == 2usize { ret 2734136534u32 }
    if index == 3usize { ret 350157278u32 }
    if index == 7usize { ret 268435456u32 }
    ret 0u32
}

// r >= L for a nine-limb accumulator.
fn sc_geq_l(r: [9]u32) -> bool {
    if r[8] != 0u32 { ret true }
    var i = 8usize
    while i > 0usize {
        i -= 1usize
        if r[i] > sc_l(i) { ret true }
        if r[i] < sc_l(i) { ret false }
    }
    ret true
}

fn sc_sub_l(r_in: [9]u32) -> [9]u32 {
    var r = r_in
    var borrow = 0u64
    var i = 0usize
    while i < 8usize {
        let lhs = u64(r[i])
        let rhs = u64(sc_l(i)) + borrow
        if lhs >= rhs {
            r[i] = u32(lhs - rhs)
            borrow = 0u64
        } else {
            r[i] = u32(lhs + 4294967296u64 - rhs)
            borrow = 1u64
        }
        i += 1usize
    }
    r[8] = r[8] - u32(borrow)
    ret r
}

// The 512-bit little-endian value reduced mod L, one bit at a time.
fn sc_reduce_wide(wide: [16]u32) -> Sc {
    var r: [9]u32 = zero
    var i = 512usize
    while i > 0usize {
        i -= 1usize
        var carry = (wide[i / 32usize] >> u32(i % 32usize)) & 1u32
        var j = 0usize
        while j < 9usize {
            let shifted = (u64(r[j]) << 1u32) | u64(carry)
            r[j] = u32(shifted & 4294967295u64)
            carry = u32(shifted >> 32u32)
            j += 1usize
        }
        if sc_geq_l(r) { r = sc_sub_l(r) }
    }
    var s: Sc = zero
    i = 0usize
    while i < 8usize {
        s.v[i] = r[i]
        i += 1usize
    }
    ret s
}

fn sc_from_bytes(bytes: []const u8) -> Sc {
    var wide: [16]u32 = zero
    var i = 0usize
    while i < bytes.len && i < 64usize {
        wide[i / 4usize] = wide[i / 4usize] | (u32(bytes[i]) << u32((i % 4usize) * 8usize))
        i += 1usize
    }
    ret sc_reduce_wide(wide)
}

fn sc_to_bytes(s: Sc) -> [32]u8 {
    var out: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        out[i] = u8((s.v[i / 4usize] >> u32((i % 4usize) * 8usize)) & 255u32)
        i += 1usize
    }
    ret out
}

fn sc_mul(a: Sc, b: Sc) -> Sc {
    var wide: [16]u32 = zero
    var i = 0usize
    while i < 8usize {
        var carry = 0u64
        var j = 0usize
        while j < 8usize {
            let t = u64(a.v[i]) * u64(b.v[j]) + u64(wide[i + j]) + carry
            wide[i + j] = u32(t & 4294967295u64)
            carry = t >> 32u32
            j += 1usize
        }
        wide[i + 8usize] = u32(carry)
        i += 1usize
    }
    ret sc_reduce_wide(wide)
}

fn sc_add(a: Sc, b: Sc) -> Sc {
    var r: [9]u32 = zero
    var carry = 0u64
    var i = 0usize
    while i < 8usize {
        let t = u64(a.v[i]) + u64(b.v[i]) + carry
        r[i] = u32(t & 4294967295u64)
        carry = t >> 32u32
        i += 1usize
    }
    r[8] = u32(carry)
    if sc_geq_l(r) { r = sc_sub_l(r) }
    var s: Sc = zero
    i = 0usize
    while i < 8usize {
        s.v[i] = r[i]
        i += 1usize
    }
    ret s
}

// True when the 32 bytes read as a scalar below L.
fn sc_canonical(bytes: []const u8) -> bool {
    var r: [9]u32 = zero
    var i = 0usize
    while i < 32usize {
        r[i / 4usize] = r[i / 4usize] | (u32(bytes[i]) << u32((i % 4usize) * 8usize))
        i += 1usize
    }
    ret !sc_geq_l(r)
}

fn clamp(bytes: []const u8) -> [32]u8 {
    var a: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        a[i] = bytes[i]
        i += 1usize
    }
    a[0] = a[0] & 248u8
    a[31] = a[31] & 127u8
    a[31] = a[31] | 64u8
    ret a
}

fn ed25519_public_from_secret(secret: Ed25519SecretKey) -> (Ed25519PublicKey, err) {
    let digest = hash.sha512(secret.bytes[0..])
    let a = clamp(digest[0..32])
    var public: Ed25519PublicKey = zero
    public.bytes = pt_encode(pt_mul(a, pt_base()))
    ret (public, ok)
}

fn ed25519_sign(secret: Ed25519SecretKey, message: []const u8) -> (Ed25519Signature, err) {
    let digest = hash.sha512(secret.bytes[0..])
    let a = clamp(digest[0..32])
    let base = pt_base()
    let public = pt_encode(pt_mul(a, base))
    var h = hash.sha512_init()
    hash.sha512_update(&h, digest[32..64])
    hash.sha512_update(&h, message)
    let r_digest = hash.sha512_done(&h)
    let r = sc_from_bytes(r_digest[0..])
    let r_bytes = sc_to_bytes(r)
    let big_r = pt_encode(pt_mul(r_bytes, base))
    var k_hash = hash.sha512_init()
    hash.sha512_update(&k_hash, big_r[0..])
    hash.sha512_update(&k_hash, public[0..])
    hash.sha512_update(&k_hash, message)
    let k_digest = hash.sha512_done(&k_hash)
    let k = sc_from_bytes(k_digest[0..])
    let s = sc_to_bytes(sc_add(r, sc_mul(k, sc_from_bytes(a[0..]))))
    var signature: Ed25519Signature = zero
    var i = 0usize
    while i < 32usize {
        signature.bytes[i] = big_r[i]
        signature.bytes[32usize + i] = s[i]
        i += 1usize
    }
    ret (signature, ok)
}

fn ed25519_verify(public: Ed25519PublicKey, message: []const u8, signature: Ed25519Signature) -> bool {
    let (a, a_ok) = pt_decode(public.bytes)
    if !a_ok { ret false }
    // Small order: eight times the point is the identity.
    let a2 = pt_add(a, a)
    let a4 = pt_add(a2, a2)
    if pt_is_identity(pt_add(a4, a4)) { ret false }
    var r_bytes: [32]u8 = zero
    var s_bytes: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        r_bytes[i] = signature.bytes[i]
        s_bytes[i] = signature.bytes[32usize + i]
        i += 1usize
    }
    let (r, r_ok) = pt_decode(r_bytes)
    if !r_ok { ret false }
    if !sc_canonical(s_bytes[0..]) { ret false }
    var k_hash = hash.sha512_init()
    hash.sha512_update(&k_hash, r_bytes[0..])
    hash.sha512_update(&k_hash, public.bytes[0..])
    hash.sha512_update(&k_hash, message)
    let k_digest = hash.sha512_done(&k_hash)
    let k = sc_to_bytes(sc_from_bytes(k_digest[0..]))
    let lhs = pt_encode(pt_mul(s_bytes, pt_base()))
    let rhs = pt_encode(pt_add(r, pt_mul(k, a)))
    ret bytes_equal(lhs, rhs)
}

// ECDSA P-256 verification for TLS and X.509. Values are eight little-endian
// 32-bit limbs; modular multiplication uses bounded double-and-add so the
// implementation needs no wider integer or platform crypto dependency.
// ponytail: verification handles public inputs, so variable-time scalar work is
// acceptable here; add a constant-time signing implementation only if signing is
// added to the public surface.
type P256Int = struct { v: [8]u32 }
type P256Affine = struct { x: P256Int, y: P256Int }
type P256Point = struct { x: P256Int, y: P256Int, z: P256Int }

fn p256_p() -> P256Int {
    ret P256Int { v: [8]u32{ 4294967295, 4294967295, 4294967295, 0, 0, 0, 1, 4294967295 } }
}

fn p256_n() -> P256Int {
    ret P256Int { v: [8]u32{ 4234356049, 4089039554, 2803342980, 3169254061, 4294967295, 4294967295, 0, 4294967295 } }
}

fn p256_b() -> P256Int {
    ret P256Int { v: [8]u32{ 668098635, 1003371582, 3428036854, 1696401072, 1989707452, 3018571093, 2855965671, 1522939352 } }
}

fn p256_base() -> P256Affine {
    let x = P256Int { v: [8]u32{ 3633889942, 4104206661, 770388896, 1996717441, 1671708914, 4173129445, 3777774151, 1796723186 } }
    let y = P256Int { v: [8]u32{ 935285237, 3417718888, 1798397646, 734933847, 2081398294, 2397563722, 4263149467, 1340293858 } }
    ret P256Affine { x: x, y: y }
}

fn p256_zero(a: P256Int) -> bool {
    var i = 0usize
    while i < 8usize {
        if a.v[i] != 0u32 { ret false }
        i += 1usize
    }
    ret true
}

fn p256_equal(a: P256Int, b: P256Int) -> bool {
    var i = 0usize
    while i < 8usize {
        if a.v[i] != b.v[i] { ret false }
        i += 1usize
    }
    ret true
}

fn p256_compare(a: P256Int, b: P256Int) -> i32 {
    var i = 8usize
    while i > 0usize {
        i -= 1usize
        if a.v[i] < b.v[i] { ret -1i32 }
        if a.v[i] > b.v[i] { ret 1i32 }
    }
    ret 0i32
}

fn p256_sub_raw(a: P256Int, b: P256Int) -> P256Int {
    var out: P256Int = zero
    var borrow = 0u64
    var i = 0usize
    while i < 8usize {
        let lhs = u64(a.v[i])
        let rhs = u64(b.v[i]) + borrow
        if lhs >= rhs {
            out.v[i] = u32(lhs - rhs)
            borrow = 0u64
        } else {
            out.v[i] = u32(lhs + 4294967296u64 - rhs)
            borrow = 1u64
        }
        i += 1usize
    }
    ret out
}

fn p256_add_mod(a: P256Int, b: P256Int, modulus: P256Int) -> P256Int {
    var out: P256Int = zero
    var carry = 0u64
    var i = 0usize
    while i < 8usize {
        let sum = u64(a.v[i]) + u64(b.v[i]) + carry
        out.v[i] = u32(sum & 4294967295u64)
        carry = sum >> 32u32
        i += 1usize
    }
    if carry != 0u64 || p256_compare(out, modulus) >= 0i32 { ret p256_sub_raw(out, modulus) }
    ret out
}

fn p256_sub_mod(a: P256Int, b: P256Int, modulus: P256Int) -> P256Int {
    if p256_compare(a, b) >= 0i32 { ret p256_sub_raw(a, b) }
    ret p256_sub_raw(modulus, p256_sub_raw(b, a))
}

fn p256_bit(a: P256Int, bit: usize) -> bool {
    ret ((a.v[bit / 32usize] >> u32(bit % 32usize)) & 1u32) != 0u32
}

fn p256_mul_mod(a: P256Int, b: P256Int, modulus: P256Int) -> P256Int {
    var out: P256Int = zero
    var addend = a
    var bit = 0usize
    while bit < 256usize {
        if p256_bit(b, bit) { out = p256_add_mod(out, addend, modulus) }
        addend = p256_add_mod(addend, addend, modulus)
        bit += 1usize
    }
    ret out
}

fn p256_pow_mod(a: P256Int, exponent: P256Int, modulus: P256Int) -> P256Int {
    var out: P256Int = zero
    out.v[0] = 1u32
    var base = a
    var bit = 0usize
    while bit < 256usize {
        if p256_bit(exponent, bit) { out = p256_mul_mod(out, base, modulus) }
        base = p256_mul_mod(base, base, modulus)
        bit += 1usize
    }
    ret out
}

fn p256_inverse(a: P256Int, modulus: P256Int) -> P256Int {
    var two: P256Int = zero
    two.v[0] = 2u32
    ret p256_pow_mod(a, p256_sub_raw(modulus, two), modulus)
}

fn p256_from_be(bytes: []const u8) -> (P256Int, bool) {
    var out: P256Int = zero
    if bytes.len == 0usize || bytes.len > 32usize { ret (out, false) }
    var i = 0usize
    while i < bytes.len {
        let from_end = bytes.len - 1usize - i
        out.v[from_end / 4usize] = out.v[from_end / 4usize] | (u32(bytes[i]) << u32((from_end % 4usize) * 8usize))
        i += 1usize
    }
    ret (out, true)
}

fn p256_field_add(a: P256Int, b: P256Int) -> P256Int { ret p256_add_mod(a, b, p256_p()) }
fn p256_field_sub(a: P256Int, b: P256Int) -> P256Int { ret p256_sub_mod(a, b, p256_p()) }
fn p256_field_mul(a: P256Int, b: P256Int) -> P256Int { ret p256_mul_mod(a, b, p256_p()) }
fn p256_field_square(a: P256Int) -> P256Int { ret p256_field_mul(a, a) }
fn p256_field_double(a: P256Int) -> P256Int { ret p256_field_add(a, a) }

fn p256_field_four(a: P256Int) -> P256Int { ret p256_field_double(p256_field_double(a)) }
fn p256_field_eight(a: P256Int) -> P256Int { ret p256_field_double(p256_field_four(a)) }

fn p256_point_double(point: P256Point) -> P256Point {
    if p256_zero(point.z) || p256_zero(point.y) { ret zero }
    let delta = p256_field_square(point.z)
    let gamma = p256_field_square(point.y)
    let beta = p256_field_mul(point.x, gamma)
    let product = p256_field_mul(p256_field_sub(point.x, delta), p256_field_add(point.x, delta))
    let alpha = p256_field_add(p256_field_double(product), product)
    let x = p256_field_sub(p256_field_square(alpha), p256_field_eight(beta))
    let z = p256_field_sub(p256_field_sub(p256_field_square(p256_field_add(point.y, point.z)), gamma), delta)
    let y = p256_field_sub(p256_field_mul(alpha, p256_field_sub(p256_field_four(beta), x)), p256_field_eight(p256_field_square(gamma)))
    ret P256Point { x: x, y: y, z: z }
}

fn p256_point_add_mixed(point: P256Point, affine: P256Affine) -> P256Point {
    if p256_zero(point.z) {
        var one: P256Int = zero
        one.v[0] = 1u32
        ret P256Point { x: affine.x, y: affine.y, z: one }
    }
    let zz = p256_field_square(point.z)
    let u = p256_field_mul(affine.x, zz)
    let s = p256_field_mul(affine.y, p256_field_mul(point.z, zz))
    let h = p256_field_sub(u, point.x)
    if p256_zero(h) {
        if p256_equal(s, point.y) { ret p256_point_double(point) }
        ret zero
    }
    let hh = p256_field_square(h)
    let i = p256_field_four(hh)
    let j = p256_field_mul(h, i)
    let r = p256_field_double(p256_field_sub(s, point.y))
    let v = p256_field_mul(point.x, i)
    let x = p256_field_sub(p256_field_sub(p256_field_square(r), j), p256_field_double(v))
    let y = p256_field_sub(p256_field_mul(r, p256_field_sub(v, x)), p256_field_double(p256_field_mul(point.y, j)))
    let z = p256_field_sub(p256_field_sub(p256_field_square(p256_field_add(point.z, h)), zz), hh)
    ret P256Point { x: x, y: y, z: z }
}

fn p256_public(public: P256PublicKey) -> (P256Affine, bool) {
    var out: P256Affine = zero
    if public.bytes[0] != 4u8 { ret (out, false) }
    let (x, x_ok) = p256_from_be(public.bytes[1usize..33usize])
    let (y, y_ok) = p256_from_be(public.bytes[33usize..65usize])
    let modulus = p256_p()
    if !x_ok || !y_ok || p256_compare(x, modulus) >= 0i32 || p256_compare(y, modulus) >= 0i32 { ret (out, false) }
    let x3 = p256_field_mul(p256_field_square(x), x)
    let three_x = p256_field_add(p256_field_double(x), x)
    let rhs = p256_field_add(p256_field_sub(x3, three_x), p256_b())
    if !p256_equal(p256_field_square(y), rhs) { ret (out, false) }
    ret (P256Affine { x: x, y: y }, true)
}

fn p256_der_integer(encoded: []const u8, at: *usize) -> (P256Int, bool) {
    var out: P256Int = zero
    if *at + 2usize > encoded.len || encoded[*at] != 2u8 { ret (out, false) }
    let length = usize(encoded[*at + 1usize])
    *at += 2usize
    if length == 0usize || length > 33usize || *at + length > encoded.len { ret (out, false) }
    var value = encoded[*at..*at + length]
    *at += length
    if (value[0] & 128u8) != 0u8 { ret (out, false) }
    if value.len > 1usize && value[0] == 0u8 {
        if (value[1] & 128u8) == 0u8 { ret (out, false) }
        value = value[1usize..]
    }
    let (parsed, parsed_ok) = p256_from_be(value)
    if !parsed_ok || p256_zero(parsed) || p256_compare(parsed, p256_n()) >= 0i32 { ret (out, false) }
    ret (parsed, true)
}

fn p256_signature(encoded: []const u8) -> (P256Int, P256Int, bool) {
    var empty: P256Int = zero
    if encoded.len < 8usize || encoded[0] != 48u8 || usize(encoded[1]) + 2usize != encoded.len { ret (empty, empty, false) }
    var at = 2usize
    let (r, r_ok) = p256_der_integer(encoded, &at)
    let (s, s_ok) = p256_der_integer(encoded, &at)
    if !r_ok || !s_ok || at != encoded.len { ret (empty, empty, false) }
    ret (r, s, true)
}

fn p256_joint_mul(u1: P256Int, u2: P256Int, public: P256Affine) -> P256Point {
    let base = p256_base()
    var out: P256Point = zero
    var bit = 256usize
    while bit > 0usize {
        bit -= 1usize
        out = p256_point_double(out)
        if p256_bit(u1, bit) { out = p256_point_add_mixed(out, base) }
        if p256_bit(u2, bit) { out = p256_point_add_mixed(out, public) }
    }
    ret out
}

fn p256_verify(public: P256PublicKey, message: []const u8, signature_der: []const u8) -> bool {
    let (point, point_ok) = p256_public(public)
    let (r, s, signature_ok) = p256_signature(signature_der)
    if !point_ok || !signature_ok { ret false }
    let digest = hash.sha256(message)
    let (z, z_ok) = p256_from_be(digest[0..])
    if !z_ok { ret false }
    let order = p256_n()
    let inverse = p256_inverse(s, order)
    let u1 = p256_mul_mod(z, inverse, order)
    let u2 = p256_mul_mod(r, inverse, order)
    let result = p256_joint_mul(u1, u2, point)
    if p256_zero(result.z) { ret false }
    let z_inverse = p256_inverse(result.z, p256_p())
    var x = p256_field_mul(result.x, p256_field_square(z_inverse))
    if p256_compare(x, order) >= 0i32 { x = p256_sub_raw(x, order) }
    ret p256_equal(x, r)
}

// --- ECDSA P-256 signing with RFC 6979 deterministic nonces over the verifier's
// arithmetic above. The nonce comes from HMAC-SHA256 of the key and the reduced
// digest, so a signature is a pure function of key and message and needs no
// randomness; the DER output is the strict form `p256_verify` accepts.
// ponytail: the scalar multiplication is the verifier's variable-time double-and-add;
// timing leaks the secret on a shared host, so a ladder is the upgrade for signing.
type P256SecretKey = struct { bytes: [32]u8 }

fn p256_to_be(a: P256Int) -> [32]u8 {
    var out: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        let from_end = 31usize - i
        out[i] = u8((a.v[from_end / 4usize] >> u32((from_end % 4usize) * 8usize)) & 255u32)
        i += 1usize
    }
    ret out
}

fn p256_to_affine(point: P256Point) -> P256Affine {
    let z_inverse = p256_inverse(point.z, p256_p())
    let zz = p256_field_square(z_inverse)
    ret P256Affine { x: p256_field_mul(point.x, zz), y: p256_field_mul(point.y, p256_field_mul(zz, z_inverse)) }
}

fn p256_scalar_valid(k: P256Int) -> bool { ret !p256_zero(k) && p256_compare(k, p256_n()) < 0i32 }

fn p256_base_mul(scalar: P256Int) -> P256Affine {
    var none: P256Int = zero
    ret p256_to_affine(p256_joint_mul(scalar, none, p256_base()))
}

fn p256_public_from_secret(secret: P256SecretKey) -> (P256PublicKey, err) {
    let (d, d_ok) = p256_from_be(secret.bytes[0..])
    if !d_ok || !p256_scalar_valid(d) { ret (zero, InvalidKey) }
    let point = p256_base_mul(d)
    let x = p256_to_be(point.x)
    let y = p256_to_be(point.y)
    var public: P256PublicKey = zero
    public.bytes[0] = 4u8
    var i = 0usize
    while i < 32usize {
        public.bytes[1usize + i] = x[i]
        public.bytes[33usize + i] = y[i]
        i += 1usize
    }
    ret (public, ok)
}

// One DER INTEGER, minimal: leading zero bytes dropped, a zero byte prepended when
// the top bit is set. Returns the bytes written.
fn p256_der_put(out: []u8, at: usize, value: P256Int) -> usize {
    let bytes = p256_to_be(value)
    var start = 0usize
    while start < 31usize && bytes[start] == 0u8 { start += 1usize }
    let length = 32usize - start
    var pad = 0usize
    if (bytes[start] & 128u8) != 0u8 { pad = 1usize }
    out[at] = 2u8
    out[at + 1usize] = u8(length + pad)
    if pad == 1usize { out[at + 2usize] = 0u8 }
    var i = 0usize
    while i < length {
        out[at + 2usize + pad + i] = bytes[start + i]
        i += 1usize
    }
    ret 2usize + pad + length
}

fn p256_sign(secret: P256SecretKey, message: []const u8, out: []u8) -> (usize, err) {
    let (d, d_ok) = p256_from_be(secret.bytes[0..])
    if !d_ok || !p256_scalar_valid(d) { ret (0usize, InvalidKey) }
    if out.len < 72usize { ret (0usize, TooSmall) }
    let order = p256_n()
    let digest = hash.sha256(message)
    let (h, _) = p256_from_be(digest[0..])
    var z = h
    if p256_compare(z, order) >= 0i32 { z = p256_sub_raw(z, order) }
    let z_bytes = p256_to_be(z)
    // RFC 6979 3.2: K and V seeded from the key and the reduced digest.
    var v: [32]u8 = zero
    var k_key: [32]u8 = zero
    var seed: [97]u8 = zero
    var i = 0usize
    while i < 32usize {
        v[i] = 1u8
        seed[i] = 1u8
        seed[33usize + i] = secret.bytes[i]
        seed[65usize + i] = z_bytes[i]
        i += 1usize
    }
    k_key = mac.hmac_sha256(k_key[0..], seed[0..])
    v = mac.hmac_sha256(k_key[0..], v[0..])
    i = 0usize
    while i < 32usize {
        seed[i] = v[i]
        i += 1usize
    }
    seed[32] = 1u8
    k_key = mac.hmac_sha256(k_key[0..], seed[0..])
    v = mac.hmac_sha256(k_key[0..], v[0..])
    var attempts = 0usize
    while attempts < 64usize {
        attempts += 1usize
        v = mac.hmac_sha256(k_key[0..], v[0..])
        let (nonce, _) = p256_from_be(v[0..])
        if p256_scalar_valid(nonce) {
            let point = p256_base_mul(nonce)
            var r = point.x
            if p256_compare(r, order) >= 0i32 { r = p256_sub_raw(r, order) }
            if !p256_zero(r) {
                let s = p256_mul_mod(p256_inverse(nonce, order), p256_add_mod(z, p256_mul_mod(r, d, order), order), order)
                if !p256_zero(s) {
                    let r_len = p256_der_put(out, 2usize, r)
                    let s_len = p256_der_put(out, 2usize + r_len, s)
                    out[0] = 48u8
                    out[1] = u8(r_len + s_len)
                    ret (2usize + r_len + s_len, ok)
                }
            }
        }
        var step: [33]u8 = zero
        i = 0usize
        while i < 32usize {
            step[i] = v[i]
            i += 1usize
        }
        k_key = mac.hmac_sha256(k_key[0..], step[0..])
        v = mac.hmac_sha256(k_key[0..], v[0..])
    }
    ret (0usize, InvalidKey)
}

// --- BIP-340 Schnorr over secp256k1 (a = 0, b = 7), on the same 256-bit integer
// routines with the curve's own p and n; the group is Jacobian double-and-add.
// ponytail: nothing here is constant time; the nonce derivation is the BIP's, so a
// signature never repeats a nonce, but timing still leaks on a shared host.
fn k1_p() -> P256Int {
    ret P256Int { v: [8]u32{ 4294966319, 4294967294, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295 } }
}

fn k1_n() -> P256Int {
    ret P256Int { v: [8]u32{ 3493216577, 3218235020, 2940772411, 3132021990, 4294967294, 4294967295, 4294967295, 4294967295 } }
}

fn k1_base() -> P256Affine {
    let x = P256Int { v: [8]u32{ 385357720, 1509065051, 768485593, 43777243, 3464956679, 1436574357, 4191992748, 2042521214 } }
    let y = P256Int { v: [8]u32{ 4212184248, 2621952143, 2793755673, 4246189128, 235997352, 1571093500, 648266853, 1211816567 } }
    ret P256Affine { x: x, y: y }
}

fn k1_mul(a: P256Int, b: P256Int) -> P256Int { ret p256_mul_mod(a, b, k1_p()) }
fn k1_add(a: P256Int, b: P256Int) -> P256Int { ret p256_add_mod(a, b, k1_p()) }
fn k1_sub(a: P256Int, b: P256Int) -> P256Int { ret p256_sub_mod(a, b, k1_p()) }

fn k1_double(point: P256Point) -> P256Point {
    if p256_zero(point.z) || p256_zero(point.y) { ret zero }
    let yy = k1_mul(point.y, point.y)
    let xyy = k1_mul(point.x, yy)
    let s = k1_add(k1_add(xyy, xyy), k1_add(xyy, xyy))
    let xx = k1_mul(point.x, point.x)
    let m = k1_add(k1_add(xx, xx), xx)
    let x = k1_sub(k1_mul(m, m), k1_add(s, s))
    let yyyy = k1_mul(yy, yy)
    let four = k1_add(k1_add(yyyy, yyyy), k1_add(yyyy, yyyy))
    let y = k1_sub(k1_mul(m, k1_sub(s, x)), k1_add(four, four))
    let yz = k1_mul(point.y, point.z)
    ret P256Point { x: x, y: y, z: k1_add(yz, yz) }
}

fn k1_add_mixed(point: P256Point, affine: P256Affine) -> P256Point {
    if p256_zero(point.z) {
        var one: P256Int = zero
        one.v[0] = 1u32
        ret P256Point { x: affine.x, y: affine.y, z: one }
    }
    let zz = k1_mul(point.z, point.z)
    let u2 = k1_mul(affine.x, zz)
    let s2 = k1_mul(affine.y, k1_mul(point.z, zz))
    let h = k1_sub(u2, point.x)
    let r = k1_sub(s2, point.y)
    if p256_zero(h) {
        if p256_zero(r) { ret k1_double(point) }
        ret zero
    }
    let hh = k1_mul(h, h)
    let hhh = k1_mul(h, hh)
    let xhh = k1_mul(point.x, hh)
    let x = k1_sub(k1_sub(k1_mul(r, r), hhh), k1_add(xhh, xhh))
    let y = k1_sub(k1_mul(r, k1_sub(xhh, x)), k1_mul(point.y, hhh))
    ret P256Point { x: x, y: y, z: k1_mul(point.z, h) }
}

fn k1_joint_mul(u1: P256Int, u2: P256Int, public: P256Affine) -> P256Point {
    let base = k1_base()
    var out: P256Point = zero
    var bit = 256usize
    while bit > 0usize {
        bit -= 1usize
        out = k1_double(out)
        if p256_bit(u1, bit) { out = k1_add_mixed(out, base) }
        if p256_bit(u2, bit) { out = k1_add_mixed(out, public) }
    }
    ret out
}

fn k1_to_affine(point: P256Point) -> P256Affine {
    let z_inverse = p256_inverse(point.z, k1_p())
    let zz = k1_mul(z_inverse, z_inverse)
    ret P256Affine { x: k1_mul(point.x, zz), y: k1_mul(point.y, k1_mul(zz, z_inverse)) }
}

fn k1_odd(a: P256Int) -> bool { ret (a.v[0] & 1u32) == 1u32 }

// The point with the given x and even y, when x is on the curve: y = (x^3 + 7)^((p+1)/4).
fn k1_lift_x(x_bytes: []const u8) -> (P256Affine, bool) {
    let (x, x_ok) = p256_from_be(x_bytes)
    if !x_ok || p256_compare(x, k1_p()) >= 0i32 { ret (zero, false) }
    var seven: P256Int = zero
    seven.v[0] = 7u32
    let c = k1_add(k1_mul(k1_mul(x, x), x), seven)
    let exponent = P256Int { v: [8]u32{ 3221225228, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 4294967295, 1073741823 } }
    var y = p256_pow_mod(c, exponent, k1_p())
    if !p256_equal(k1_mul(y, y), c) { ret (zero, false) }
    if k1_odd(y) { y = p256_sub_raw(k1_p(), y) }
    ret (P256Affine { x: x, y: y }, true)
}

fn k1_scalar_mod_n(bytes: []const u8) -> P256Int {
    let (value, _) = p256_from_be(bytes)
    if p256_compare(value, k1_n()) >= 0i32 { ret p256_sub_raw(value, k1_n()) }
    ret value
}

fn tagged_hash_init(tag: []const u8) -> hash.Sha256 {
    let tag_digest = hash.sha256(tag)
    var h = hash.sha256_init()
    hash.sha256_update(&h, tag_digest[0..])
    hash.sha256_update(&h, tag_digest[0..])
    ret h
}

fn schnorr_challenge(r_bytes: []const u8, public_x: []const u8, message: []const u8) -> P256Int {
    var h = tagged_hash_init("BIP0340/challenge")
    hash.sha256_update(&h, r_bytes)
    hash.sha256_update(&h, public_x)
    hash.sha256_update(&h, message)
    let digest = hash.sha256_done(&h)
    ret k1_scalar_mod_n(digest[0..])
}

// The x-only public key of a secret scalar.
fn schnorr_public_from_secret(secret: [32]u8) -> ([32]u8, err) {
    let (d, d_ok) = p256_from_be(secret[0..])
    if !d_ok || p256_zero(d) || p256_compare(d, k1_n()) >= 0i32 { ret (zero, InvalidKey) }
    var none: P256Int = zero
    ret (p256_to_be(k1_to_affine(k1_joint_mul(d, none, k1_base())).x), ok)
}

// BIP-340 signing of a message (any length) with 32 bytes of auxiliary randomness (all
// zero is allowed and still yields a sound, deterministic signature).
fn schnorr_sign(secret: [32]u8, message: []const u8, aux: [32]u8) -> ([64]u8, err) {
    let (d0, d_ok) = p256_from_be(secret[0..])
    let order = k1_n()
    if !d_ok || p256_zero(d0) || p256_compare(d0, order) >= 0i32 { ret (zero, InvalidKey) }
    var none: P256Int = zero
    let public = k1_to_affine(k1_joint_mul(d0, none, k1_base()))
    var d = d0
    if k1_odd(public.y) { d = p256_sub_raw(order, d0) }
    let public_x = p256_to_be(public.x)
    let d_bytes = p256_to_be(d)
    var aux_hash = tagged_hash_init("BIP0340/aux")
    hash.sha256_update(&aux_hash, aux[0..])
    let aux_digest = hash.sha256_done(&aux_hash)
    var t: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        t[i] = d_bytes[i] ^ aux_digest[i]
        i += 1usize
    }
    var nonce_hash = tagged_hash_init("BIP0340/nonce")
    hash.sha256_update(&nonce_hash, t[0..])
    hash.sha256_update(&nonce_hash, public_x[0..])
    hash.sha256_update(&nonce_hash, message)
    let nonce_digest = hash.sha256_done(&nonce_hash)
    let k0 = k1_scalar_mod_n(nonce_digest[0..])
    if p256_zero(k0) { ret (zero, InvalidKey) }
    let r_point = k1_to_affine(k1_joint_mul(k0, none, k1_base()))
    var k = k0
    if k1_odd(r_point.y) { k = p256_sub_raw(order, k0) }
    let r_bytes = p256_to_be(r_point.x)
    let e = schnorr_challenge(r_bytes[0..], public_x[0..], message)
    let s_bytes = p256_to_be(p256_add_mod(k, p256_mul_mod(e, d, order), order))
    var signature: [64]u8 = zero
    i = 0usize
    while i < 32usize {
        signature[i] = r_bytes[i]
        signature[32usize + i] = s_bytes[i]
        i += 1usize
    }
    ret (signature, ok)
}

fn schnorr(secret: [32]u8, message: []const u8, aux: [32]u8) -> ([64]u8, err) {
    let (signature, sign_error) = schnorr_sign(secret, message, aux)
    ret (signature, sign_error)
}

fn schnorr_verify(public_x: [32]u8, message: []const u8, signature: [64]u8) -> bool {
    let (public, public_ok) = k1_lift_x(public_x[0..])
    if !public_ok { ret false }
    let (r, r_ok) = p256_from_be(signature[0..32])
    let (s, s_ok) = p256_from_be(signature[32..64])
    let order = k1_n()
    if !r_ok || !s_ok || p256_compare(r, k1_p()) >= 0i32 || p256_compare(s, order) >= 0i32 { ret false }
    let e = schnorr_challenge(signature[0..32], public_x[0..], message)
    let result = k1_joint_mul(s, p256_sub_raw(order, e), public)
    if p256_zero(result.z) { ret false }
    let affine = k1_to_affine(result)
    if k1_odd(affine.y) { ret false }
    ret p256_equal(affine.x, r)
}

// --- RSASSA-PSS and PKCS#1 v1.5 verification with SHA-256 over `e.algo.bignum`.
// Keys are big-endian byte strings; the modulus may be up to 4096 bits. PSS uses
// MGF1-SHA256 and a 32-byte salt, the shape `cryptography`'s default checks.
fn rsa_salt_len() -> usize { ret 32usize }
fn rsa_max_bytes() -> usize { ret 512usize }

// MGF1-SHA256 of `seed`, XORed into all of `mask`.
fn mgf1_xor(seed: []const u8, mask: []u8) {
    var counter = 0u32
    var at = 0usize
    while at < mask.len {
        var h = hash.sha256_init()
        hash.sha256_update(&h, seed)
        var counter_bytes: [4]u8 = zero
        counter_bytes[0] = u8(counter >> 24u32)
        counter_bytes[1] = u8((counter >> 16u32) & 255u32)
        counter_bytes[2] = u8((counter >> 8u32) & 255u32)
        counter_bytes[3] = u8(counter & 255u32)
        hash.sha256_update(&h, counter_bytes[0..])
        let block = hash.sha256_done(&h)
        var i = 0usize
        while i < 32usize && at < mask.len {
            mask[at] = mask[at] ^ block[i]
            at += 1usize
            i += 1usize
        }
        counter += 1u32
    }
}

// H = SHA-256(eight zero bytes || SHA-256(message) || salt).
fn pss_hash(message: []const u8, salt: []const u8) -> [32]u8 {
    let m_hash = hash.sha256(message)
    var zeros: [8]u8 = zero
    var h = hash.sha256_init()
    hash.sha256_update(&h, zeros[0..])
    hash.sha256_update(&h, m_hash[0..])
    hash.sha256_update(&h, salt)
    ret hash.sha256_done(&h)
}

fn rsa_pss_sign(a: *mem.Arena, n: []const u8, d: []const u8, message: []const u8, salt: []const u8, out: []u8) -> (usize, err) {
    if salt.len != rsa_salt_len() { ret (0usize, Invalid) }
    let (modulus, n_error) = bignum.int_from_bytes_be(a, n)
    if n_error != ok { ret (0usize, n_error) }
    let (exponent, d_error) = bignum.int_from_bytes_be(a, d)
    if d_error != ok { ret (0usize, d_error) }
    let mod_bits = bignum.int_bits(modulus)
    let em_bits = mod_bits - 1usize
    let em_len = (em_bits + 7usize) / 8usize
    let k = (mod_bits + 7usize) / 8usize
    if mod_bits < 8usize * (salt.len + 34usize) + 2usize || k > rsa_max_bytes() { ret (0usize, InvalidKey) }
    if out.len < k { ret (0usize, TooSmall) }
    var em: [512]u8 = zero
    let h = pss_hash(message, salt)
    let db_len = em_len - 33usize
    em[db_len - salt.len - 1usize] = 1u8
    var i = 0usize
    while i < salt.len {
        em[db_len - salt.len + i] = salt[i]
        i += 1usize
    }
    mgf1_xor(h[0..], em[..db_len])
    em[0] = em[0] & (255u8 >> u8(8usize * em_len - em_bits))
    i = 0usize
    while i < 32usize {
        em[db_len + i] = h[i]
        i += 1usize
    }
    em[em_len - 1usize] = 188u8
    let (m, m_error) = bignum.int_from_bytes_be(a, em[..em_len])
    if m_error != ok { ret (0usize, m_error) }
    let (s, s_error) = bignum.int_mod_pow(a, m, exponent, modulus)
    if s_error != ok { ret (0usize, s_error) }
    let store_error = bignum.int_to_bytes_be(s, out[..k])
    if store_error != ok { ret (0usize, store_error) }
    ret (k, ok)
}

fn rsa_pss(a: *mem.Arena, n: []const u8, d: []const u8, message: []const u8, salt: []const u8, out: []u8) -> (usize, err) {
    let (written, sign_error) = rsa_pss_sign(a, n, d, message, salt, out)
    ret (written, sign_error)
}

// signature^e mod n as exactly `out.len` bytes; false when the signature is not a
// valid representative or the result does not fit.
fn rsa_public_op(a: *mem.Arena, n: []const u8, e: []const u8, signature: []const u8, out: []u8) -> bool {
    let (modulus, n_error) = bignum.int_from_bytes_be(a, n)
    if n_error != ok { ret false }
    let (exponent, e_error) = bignum.int_from_bytes_be(a, e)
    if e_error != ok { ret false }
    let (s, s_error) = bignum.int_from_bytes_be(a, signature)
    if s_error != ok || bignum.int_cmp(s, modulus) >= 0i32 { ret false }
    let (m, m_error) = bignum.int_mod_pow(a, s, exponent, modulus)
    if m_error != ok { ret false }
    ret bignum.int_to_bytes_be(m, out) == ok
}

fn rsa_pss_verify(a: *mem.Arena, n: []const u8, e: []const u8, message: []const u8, signature: []const u8) -> bool {
    let (modulus, n_error) = bignum.int_from_bytes_be(a, n)
    if n_error != ok { ret false }
    let mod_bits = bignum.int_bits(modulus)
    let em_bits = mod_bits - 1usize
    let em_len = (em_bits + 7usize) / 8usize
    let k = (mod_bits + 7usize) / 8usize
    let salt_len = rsa_salt_len()
    if mod_bits < 8usize * (salt_len + 34usize) + 2usize || k > rsa_max_bytes() || signature.len != k { ret false }
    var em: [512]u8 = zero
    if !rsa_public_op(a, n, e, signature, em[..em_len]) { ret false }
    if em[em_len - 1usize] != 188u8 { ret false }
    let db_len = em_len - 33usize
    let top_mask = 255u8 >> u8(8usize * em_len - em_bits)
    if (em[0] & ~top_mask) != 0u8 { ret false }
    mgf1_xor(em[db_len..db_len + 32usize], em[..db_len])
    em[0] = em[0] & top_mask
    var i = 0usize
    while i < db_len - salt_len - 1usize {
        if em[i] != 0u8 { ret false }
        i += 1usize
    }
    if em[db_len - salt_len - 1usize] != 1u8 { ret false }
    let expected = pss_hash(message, em[db_len - salt_len..db_len])
    ret hash.equal_constant_time(expected[0..], em[db_len..db_len + 32usize])
}

// RSASSA-PKCS1-v1_5 with SHA-256: the encoded message is rebuilt and compared whole.
fn rsa_pkcs1v15_verify(a: *mem.Arena, n: []const u8, e: []const u8, message: []const u8, signature: []const u8) -> bool {
    let (modulus, n_error) = bignum.int_from_bytes_be(a, n)
    if n_error != ok { ret false }
    let k = (bignum.int_bits(modulus) + 7usize) / 8usize
    if k < 62usize || k > rsa_max_bytes() || signature.len != k { ret false }
    var em: [512]u8 = zero
    if !rsa_public_op(a, n, e, signature, em[..k]) { ret false }
    var expected: [512]u8 = zero
    expected[1] = 1u8
    var i = 2usize
    while i < k - 52usize {
        expected[i] = 255u8
        i += 1usize
    }
    let prefix: [19]u8 = [19]u8{ 48, 49, 48, 13, 6, 9, 96, 134, 72, 1, 101, 3, 4, 2, 1, 5, 0, 4, 32 }
    i = 0usize
    while i < 19usize {
        expected[k - 51usize + i] = prefix[i]
        i += 1usize
    }
    let digest = hash.sha256(message)
    i = 0usize
    while i < 32usize {
        expected[k - 32usize + i] = digest[i]
        i += 1usize
    }
    ret hash.equal_constant_time(expected[..k], em[..k])
}

// ML-DSA-44 by FIPS 204 (k = l = 4, eta = 2, tau = 39, gamma1 = 2^17, gamma2 = (q-1)/88,
// beta = 78, omega = 80, d = 13): the NTT over Z_8380417 with zeta = 1753 in
// bit-reversed order, RejNTTPoly from SHAKE128, RejBoundedPoly and ExpandMask from
// SHAKE256, SampleInBall, Power2Round, Decompose with MakeHint/UseHint, the bit
// packers of pkEncode/skEncode/sigEncode, keygen from a 32-byte seed, the
// deterministic signature (rnd = 0^32) with its rejection loop, and verification.
// Polynomials are 256 `i64` coefficients in [0, q); vectors are laid out in a row.
//
// ponytail: arithmetic is plain `%` by q; nothing here claims constant time, and the
// sign rejection loop restarts as soon as a bound fails (as dilithium-py does).

fn dsa_q() -> i64 { ret 8380417i64 }
fn dsa_gamma1() -> i64 { ret 131072i64 }
fn dsa_gamma2() -> i64 { ret 95232i64 }
fn dsa_beta() -> i64 { ret 78i64 }

fn dsa_bitrev8(i: usize) -> usize {
    var r = 0usize
    var b = 0usize
    while b < 8usize {
        r = (r << 1u32) | ((i >> u32(b)) & 1usize)
        b += 1usize
    }
    ret r
}

// zetas[i] = 1753^BitRev8(i) mod q.
fn dsa_zetas() -> [256]i64 {
    var pow: [256]i64 = zero
    var value = 1i64
    var i = 0usize
    while i < 256usize {
        pow[i] = value
        value = (value * 1753i64) % dsa_q()
        i += 1usize
    }
    var z: [256]i64 = zero
    i = 0usize
    while i < 256usize {
        z[i] = pow[dsa_bitrev8(i)]
        i += 1usize
    }
    ret z
}

fn dsa_ntt(w: []i64) {
    let z = dsa_zetas()
    var m = 0usize
    var len = 128usize
    while len >= 1usize {
        var start = 0usize
        while start < 256usize {
            m += 1usize
            let zeta = z[m]
            var j = start
            while j < start + len {
                let t = (zeta * w[j + len]) % dsa_q()
                w[j + len] = (w[j] + dsa_q() - t) % dsa_q()
                w[j] = (w[j] + t) % dsa_q()
                j += 1usize
            }
            start += 2usize * len
        }
        len = len / 2usize
    }
}

fn dsa_intt(w: []i64) {
    let z = dsa_zetas()
    var m = 256usize
    var len = 1usize
    while len < 256usize {
        var start = 0usize
        while start < 256usize {
            m -= 1usize
            let zeta = dsa_q() - z[m]
            var j = start
            while j < start + len {
                let t = w[j]
                w[j] = (t + w[j + len]) % dsa_q()
                w[j + len] = (zeta * ((t + dsa_q() - w[j + len]) % dsa_q())) % dsa_q()
                j += 1usize
            }
            start += 2usize * len
        }
        len = len * 2usize
    }
    var k = 0usize
    while k < 256usize {
        w[k] = (w[k] * 8347681i64) % dsa_q()
        k += 1usize
    }
}

// h += f o g pointwise in the NTT domain.
fn dsa_mul_acc(h: []i64, f: []const i64, g: []const i64) {
    var i = 0usize
    while i < 256usize {
        h[i] = (h[i] + (f[i] * g[i]) % dsa_q()) % dsa_q()
        i += 1usize
    }
}

fn dsa_add(f: []i64, g: []const i64) {
    var i = 0usize
    while i < 256usize {
        f[i] = (f[i] + g[i]) % dsa_q()
        i += 1usize
    }
}

fn dsa_sub(f: []i64, g: []const i64) {
    var i = 0usize
    while i < 256usize {
        f[i] = (f[i] + dsa_q() - g[i]) % dsa_q()
        i += 1usize
    }
}

// The representative of x in (-q/2, q/2].
fn dsa_center(x: i64) -> i64 {
    if x > (dsa_q() - 1i64) / 2i64 { ret x - dsa_q() }
    ret x
}

fn dsa_abs(x: i64) -> i64 {
    if x < 0i64 { ret 0i64 - x }
    ret x
}

// True when the infinity norm of the polynomial reaches `bound`.
fn dsa_norm_reaches(f: []const i64, bound: i64) -> bool {
    var i = 0usize
    while i < 256usize {
        if dsa_abs(dsa_center(f[i])) >= bound { ret true }
        i += 1usize
    }
    ret false
}

// Bit packers: `count` values of `bits` bits each, little-endian bit order.
fn dsa_pack(values: []const i64, bits: usize, out: []u8) {
    var at = 0usize
    while at < values.len * bits / 8usize {
        out[at] = 0u8
        at += 1usize
    }
    var i = 0usize
    while i < values.len {
        let a = u64(values[i])
        var j = 0usize
        while j < bits {
            let bit = i * bits + j
            out[bit / 8usize] = out[bit / 8usize] | u8((((a >> u32(j)) & 1u64) << u32(bit % 8usize)) & 255u64)
            j += 1usize
        }
        i += 1usize
    }
}

fn dsa_unpack(bytes: []const u8, bits: usize, out: []i64) {
    var i = 0usize
    while i < out.len {
        var a = 0u64
        var j = 0usize
        while j < bits {
            let bit = i * bits + j
            a = a | (((u64(bytes[bit / 8usize]) >> u32(bit % 8usize)) & 1u64) << u32(j))
            j += 1usize
        }
        out[i] = i64(a)
        i += 1usize
    }
}

// BitPack(w, a, b): each coefficient as b - w in `bits` bits; the inverse recovers w mod q.
fn dsa_pack_centered(f: []const i64, b: i64, bits: usize, out: []u8) {
    var v: [256]i64 = zero
    var i = 0usize
    while i < 256usize {
        v[i] = b - dsa_center(f[i])
        i += 1usize
    }
    dsa_pack(v[0..], bits, out)
}

fn dsa_unpack_centered(bytes: []const u8, b: i64, bits: usize, out: []i64) {
    dsa_unpack(bytes, bits, out)
    var i = 0usize
    while i < 256usize {
        out[i] = ((b - out[i]) + dsa_q()) % dsa_q()
        i += 1usize
    }
}

// RejNTTPoly(rho || s || r) from SHAKE128, three bytes per candidate with the top bit cleared.
fn dsa_rej_ntt_poly(rho: []const u8, s: u8, r: u8, out: []i64) {
    var xof = hash.shake128_init()
    hash.shake_absorb(&xof, rho)
    var index: [2]u8 = zero
    index[0] = s
    index[1] = r
    hash.shake_absorb(&xof, index[0..])
    var count = 0usize
    var chunk: [3]u8 = zero
    while count < 256usize {
        hash.shake_squeeze(&xof, chunk[0..])
        let z = i64(chunk[0]) + 256i64 * i64(chunk[1]) + 65536i64 * i64(chunk[2] & 127u8)
        if z < dsa_q() {
            out[count] = z
            count += 1usize
        }
    }
}

// RejBoundedPoly(rho' || r as two bytes) from SHAKE256, eta = 2: 2 - (z mod 5) for z < 15.
fn dsa_rej_bounded_poly(rho: []const u8, nonce: usize, out: []i64) {
    var xof = hash.shake256_init()
    hash.shake_absorb(&xof, rho)
    var index: [2]u8 = zero
    index[0] = u8(nonce & 255usize)
    index[1] = u8((nonce >> 8u32) & 255usize)
    hash.shake_absorb(&xof, index[0..])
    var count = 0usize
    var byte: [1]u8 = zero
    while count < 256usize {
        hash.shake_squeeze(&xof, byte[0..])
        let z0 = i64(byte[0] & 15u8)
        let z1 = i64(byte[0] >> 4u32)
        if z0 < 15i64 {
            out[count] = (2i64 - z0 % 5i64 + dsa_q()) % dsa_q()
            count += 1usize
        }
        if z1 < 15i64 && count < 256usize {
            out[count] = (2i64 - z1 % 5i64 + dsa_q()) % dsa_q()
            count += 1usize
        }
    }
}

// ExpandA: a[(r * 4 + s) * 256 ..] = RejNTTPoly(rho, s, r).
fn dsa_expand_a(rho: []const u8, a: []i64) {
    var r = 0usize
    while r < 4usize {
        var s = 0usize
        while s < 4usize {
            dsa_rej_ntt_poly(rho, u8(s & 255usize), u8(r & 255usize), a[(r * 4usize + s) * 256usize..(r * 4usize + s + 1usize) * 256usize])
            s += 1usize
        }
        r += 1usize
    }
}

// ExpandMask: y[r] from SHAKE256(rho'' || (kappa + r) as two bytes), 18 bits per coefficient.
fn dsa_expand_mask(rho: []const u8, kappa: usize, y: []i64) {
    var r = 0usize
    while r < 4usize {
        var xof = hash.shake256_init()
        hash.shake_absorb(&xof, rho)
        var index: [2]u8 = zero
        index[0] = u8((kappa + r) & 255usize)
        index[1] = u8(((kappa + r) >> 8u32) & 255usize)
        hash.shake_absorb(&xof, index[0..])
        var v: [576]u8 = zero
        hash.shake_squeeze(&xof, v[0..])
        dsa_unpack_centered(v[0..], dsa_gamma1(), 18usize, y[r * 256usize..(r + 1usize) * 256usize])
        r += 1usize
    }
}

// SampleInBall(c_tilde): tau = 39 coefficients of +-1 placed by a Fisher-Yates walk.
fn dsa_sample_in_ball(c_tilde: []const u8, c: []i64) {
    var i = 0usize
    while i < 256usize {
        c[i] = 0i64
        i += 1usize
    }
    var xof = hash.shake256_init()
    hash.shake_absorb(&xof, c_tilde)
    var signs: [8]u8 = zero
    hash.shake_squeeze(&xof, signs[0..])
    i = 217usize
    var byte: [1]u8 = zero
    while i < 256usize {
        hash.shake_squeeze(&xof, byte[0..])
        var j = usize(byte[0])
        while j > i {
            hash.shake_squeeze(&xof, byte[0..])
            j = usize(byte[0])
        }
        c[i] = c[j]
        let bit = i + 39usize - 256usize
        if ((signs[bit / 8usize] >> u32(bit % 8usize)) & 1u8) == 1u8 {
            c[j] = dsa_q() - 1i64
        } else {
            c[j] = 1i64
        }
        i += 1usize
    }
}

// Power2Round: r = r1 * 2^13 + r0 with r0 in (-2^12, 2^12]; answers (r1, r0 mod q).
fn dsa_power2round(r: i64) -> (i64, i64) {
    var r0 = r % 8192i64
    if r0 > 4096i64 { r0 -= 8192i64 }
    ret ((r - r0) / 8192i64, (r0 + dsa_q()) % dsa_q())
}

// Decompose: r = r1 * 2 gamma2 + r0 with r0 in (-gamma2, gamma2]; answers (r1, r0 centered).
fn dsa_decompose(r: i64) -> (i64, i64) {
    var r0 = r % (2i64 * dsa_gamma2())
    if r0 > dsa_gamma2() { r0 -= 2i64 * dsa_gamma2() }
    if r - r0 == dsa_q() - 1i64 { ret (0i64, r0 - 1i64) }
    ret ((r - r0) / (2i64 * dsa_gamma2()), r0)
}

fn dsa_high_bits(r: i64) -> i64 {
    let (r1, _) = dsa_decompose(r)
    ret r1
}

fn dsa_make_hint(z: i64, r: i64) -> u8 {
    if dsa_high_bits(r) != dsa_high_bits((r + z) % dsa_q()) { ret 1u8 }
    ret 0u8
}

fn dsa_use_hint(h: u8, r: i64) -> i64 {
    let (r1, r0) = dsa_decompose(r)
    if h == 0u8 { ret r1 }
    if r0 > 0i64 { ret (r1 + 1i64) % 44i64 }
    ret (r1 + 43i64) % 44i64
}

fn ml_dsa_pk_len() -> usize { ret 1312usize }
fn ml_dsa_sk_len() -> usize { ret 2560usize }
fn ml_dsa_sig_len() -> usize { ret 2420usize }

// ML-DSA.KeyGen_internal(seed): pk = rho || t1 (1312 bytes), sk = rho || K || tr || s1 || s2 || t0 (2560).
fn ml_dsa_keygen(seed: [32]u8, pk: []u8, sk: []u8) -> err {
    if pk.len < 1312usize || sk.len < 2560usize { ret TooSmall }
    var xof = hash.shake256_init()
    hash.shake_absorb(&xof, seed[0..])
    var kl: [2]u8 = zero
    kl[0] = 4u8
    kl[1] = 4u8
    hash.shake_absorb(&xof, kl[0..])
    var seeds: [128]u8 = zero
    hash.shake_squeeze(&xof, seeds[0..])
    var a: [4096]i64 = zero
    dsa_expand_a(seeds[0..32], a[0..])
    var s1: [1024]i64 = zero
    var s2: [1024]i64 = zero
    var s1hat: [1024]i64 = zero
    var r = 0usize
    while r < 4usize {
        dsa_rej_bounded_poly(seeds[32..96], r, s1[r * 256usize..(r + 1usize) * 256usize])
        dsa_rej_bounded_poly(seeds[32..96], r + 4usize, s2[r * 256usize..(r + 1usize) * 256usize])
        var i = 0usize
        while i < 256usize {
            s1hat[r * 256usize + i] = s1[r * 256usize + i]
            i += 1usize
        }
        dsa_ntt(s1hat[r * 256usize..(r + 1usize) * 256usize])
        r += 1usize
    }
    var i = 0usize
    while i < 32usize {
        pk[i] = seeds[i]
        sk[i] = seeds[i]
        sk[32usize + i] = seeds[96usize + i]
        i += 1usize
    }
    var t0: [1024]i64 = zero
    r = 0usize
    while r < 4usize {
        var t: [256]i64 = zero
        var s = 0usize
        while s < 4usize {
            dsa_mul_acc(t[0..], a[(r * 4usize + s) * 256usize..(r * 4usize + s + 1usize) * 256usize], s1hat[s * 256usize..(s + 1usize) * 256usize])
            s += 1usize
        }
        dsa_intt(t[0..])
        dsa_add(t[0..], s2[r * 256usize..(r + 1usize) * 256usize])
        var t1: [256]i64 = zero
        i = 0usize
        while i < 256usize {
            let (high, low) = dsa_power2round(t[i])
            t1[i] = high
            t0[r * 256usize + i] = low
            i += 1usize
        }
        dsa_pack(t1[0..], 10usize, pk[32usize + r * 320usize..32usize + (r + 1usize) * 320usize])
        dsa_pack_centered(s1[r * 256usize..(r + 1usize) * 256usize], 2i64, 3usize, sk[128usize + r * 96usize..128usize + (r + 1usize) * 96usize])
        dsa_pack_centered(s2[r * 256usize..(r + 1usize) * 256usize], 2i64, 3usize, sk[512usize + r * 96usize..512usize + (r + 1usize) * 96usize])
        dsa_pack_centered(t0[r * 256usize..(r + 1usize) * 256usize], 4096i64, 13usize, sk[896usize + r * 416usize..896usize + (r + 1usize) * 416usize])
        r += 1usize
    }
    var tr = hash.shake256_init()
    hash.shake_absorb(&tr, pk[0..1312])
    hash.shake_squeeze(&tr, sk[64..128])
    ret ok
}

// mu = H(tr || 0 || |ctx| || ctx || message, 64): the pure-variant message formatting.
fn dsa_mu(tr: []const u8, message: []const u8, ctx: []const u8) -> [64]u8 {
    var xof = hash.shake256_init()
    hash.shake_absorb(&xof, tr)
    var head: [2]u8 = zero
    head[1] = u8(ctx.len & 255usize)
    hash.shake_absorb(&xof, head[0..])
    hash.shake_absorb(&xof, ctx)
    hash.shake_absorb(&xof, message)
    var mu: [64]u8 = zero
    hash.shake_squeeze(&xof, mu[0..])
    ret mu
}

// w1Encode: 6 bits per coefficient, absorbed straight into the challenge hash.
fn dsa_absorb_w1(xof: *hash.Shake, w1: []const i64) {
    var packed: [768]u8 = zero
    dsa_pack(w1, 6usize, packed[0..])
    hash.shake_absorb(xof, packed[0..])
}

// ML-DSA.Sign_internal with rnd = 0^32 (the deterministic variant); ctx may be empty
// and at most 255 bytes. sig is c_tilde || z || hints (2420 bytes).
fn ml_dsa_sign(sk: []const u8, message: []const u8, ctx: []const u8, sig: []u8) -> err {
    if sk.len < 2560usize || sig.len < 2420usize { ret TooSmall }
    if ctx.len > 255usize { ret Invalid }
    var a: [4096]i64 = zero
    dsa_expand_a(sk[0..32], a[0..])
    var s1hat: [1024]i64 = zero
    var s2hat: [1024]i64 = zero
    var t0hat: [1024]i64 = zero
    var r = 0usize
    while r < 4usize {
        dsa_unpack_centered(sk[128usize + r * 96usize..128usize + (r + 1usize) * 96usize], 2i64, 3usize, s1hat[r * 256usize..(r + 1usize) * 256usize])
        dsa_unpack_centered(sk[512usize + r * 96usize..512usize + (r + 1usize) * 96usize], 2i64, 3usize, s2hat[r * 256usize..(r + 1usize) * 256usize])
        dsa_unpack_centered(sk[896usize + r * 416usize..896usize + (r + 1usize) * 416usize], 4096i64, 13usize, t0hat[r * 256usize..(r + 1usize) * 256usize])
        dsa_ntt(s1hat[r * 256usize..(r + 1usize) * 256usize])
        dsa_ntt(s2hat[r * 256usize..(r + 1usize) * 256usize])
        dsa_ntt(t0hat[r * 256usize..(r + 1usize) * 256usize])
        r += 1usize
    }
    let mu = dsa_mu(sk[64..128], message, ctx)
    var seed = hash.shake256_init()
    hash.shake_absorb(&seed, sk[32..64])
    var rnd: [32]u8 = zero
    hash.shake_absorb(&seed, rnd[0..])
    hash.shake_absorb(&seed, mu[0..])
    var rho2: [64]u8 = zero
    hash.shake_squeeze(&seed, rho2[0..])
    var kappa = 0usize
    var y: [1024]i64 = zero
    var yhat: [1024]i64 = zero
    var w: [1024]i64 = zero
    var w1: [1024]i64 = zero
    var c: [256]i64 = zero
    var z: [1024]i64 = zero
    var hints: [1024]u8 = zero
    var attempts = 0usize
    while attempts < 1024usize {
        attempts += 1usize
        dsa_expand_mask(rho2[0..], kappa, y[0..])
        kappa += 4usize
        var i = 0usize
        while i < 1024usize {
            yhat[i] = y[i]
            w[i] = 0i64
            i += 1usize
        }
        r = 0usize
        while r < 4usize {
            dsa_ntt(yhat[r * 256usize..(r + 1usize) * 256usize])
            r += 1usize
        }
        r = 0usize
        while r < 4usize {
            var s = 0usize
            while s < 4usize {
                dsa_mul_acc(w[r * 256usize..(r + 1usize) * 256usize], a[(r * 4usize + s) * 256usize..(r * 4usize + s + 1usize) * 256usize], yhat[s * 256usize..(s + 1usize) * 256usize])
                s += 1usize
            }
            dsa_intt(w[r * 256usize..(r + 1usize) * 256usize])
            r += 1usize
        }
        i = 0usize
        while i < 1024usize {
            w1[i] = dsa_high_bits(w[i])
            i += 1usize
        }
        var challenge = hash.shake256_init()
        hash.shake_absorb(&challenge, mu[0..])
        dsa_absorb_w1(&challenge, w1[0..])
        hash.shake_squeeze(&challenge, sig[0..32])
        dsa_sample_in_ball(sig[0..32], c[0..])
        dsa_ntt(c[0..])
        // z = y + c s1; r0 = LowBits(w - c s2); ct0 and the hints.
        var ok_so_far = true
        r = 0usize
        while r < 4usize && ok_so_far {
            var cs1: [256]i64 = zero
            dsa_mul_acc(cs1[0..], c[0..], s1hat[r * 256usize..(r + 1usize) * 256usize])
            dsa_intt(cs1[0..])
            dsa_add(cs1[0..], y[r * 256usize..(r + 1usize) * 256usize])
            if dsa_norm_reaches(cs1[0..], dsa_gamma1() - dsa_beta()) { ok_so_far = false }
            i = 0usize
            while i < 256usize {
                z[r * 256usize + i] = cs1[i]
                i += 1usize
            }
            r += 1usize
        }
        var hint_count = 0usize
        r = 0usize
        while r < 4usize && ok_so_far {
            var cs2: [256]i64 = zero
            dsa_mul_acc(cs2[0..], c[0..], s2hat[r * 256usize..(r + 1usize) * 256usize])
            dsa_intt(cs2[0..])
            var wcs2: [256]i64 = zero
            i = 0usize
            while i < 256usize {
                wcs2[i] = (w[r * 256usize + i] + dsa_q() - cs2[i]) % dsa_q()
                let (_, low) = dsa_decompose(wcs2[i])
                if dsa_abs(low) >= dsa_gamma2() - dsa_beta() { ok_so_far = false }
                i += 1usize
            }
            var ct0: [256]i64 = zero
            dsa_mul_acc(ct0[0..], c[0..], t0hat[r * 256usize..(r + 1usize) * 256usize])
            dsa_intt(ct0[0..])
            if dsa_norm_reaches(ct0[0..], dsa_gamma2()) { ok_so_far = false }
            i = 0usize
            while i < 256usize {
                let h = dsa_make_hint(dsa_q() - ct0[i], (wcs2[i] + ct0[i]) % dsa_q())
                hints[r * 256usize + i] = h
                hint_count += usize(h)
                i += 1usize
            }
            r += 1usize
        }
        if ok_so_far && hint_count <= 80usize {
            r = 0usize
            while r < 4usize {
                dsa_pack_centered(z[r * 256usize..(r + 1usize) * 256usize], dsa_gamma1(), 18usize, sig[32usize + r * 576usize..32usize + (r + 1usize) * 576usize])
                r += 1usize
            }
            var at = 0usize
            while at < 84usize {
                sig[2336usize + at] = 0u8
                at += 1usize
            }
            var index = 0usize
            r = 0usize
            while r < 4usize {
                var j = 0usize
                while j < 256usize {
                    if hints[r * 256usize + j] == 1u8 {
                        sig[2336usize + index] = u8(j & 255usize)
                        index += 1usize
                    }
                    j += 1usize
                }
                sig[2416usize + r] = u8(index & 255usize)
                r += 1usize
            }
            ret ok
        }
    }
    ret Invalid
}

// ML-DSA.Verify_internal: true when the hints decode, ||z|| < gamma1 - beta and c_tilde matches.
fn ml_dsa_verify(pk: []const u8, message: []const u8, ctx: []const u8, sig: []const u8) -> bool {
    if pk.len < 1312usize || sig.len < 2420usize || ctx.len > 255usize { ret false }
    // HintBitUnpack, refusing a malformed encoding.
    var hints: [1024]u8 = zero
    var index = 0usize
    var r = 0usize
    while r < 4usize {
        let end = usize(sig[2416usize + r])
        if end < index || end > 80usize { ret false }
        let first = index
        while index < end {
            if index > first && sig[2336usize + index - 1usize] >= sig[2336usize + index] { ret false }
            hints[r * 256usize + usize(sig[2336usize + index])] = 1u8
            index += 1usize
        }
        r += 1usize
    }
    while index < 80usize {
        if sig[2336usize + index] != 0u8 { ret false }
        index += 1usize
    }
    var a: [4096]i64 = zero
    dsa_expand_a(pk[0..32], a[0..])
    var zhat: [1024]i64 = zero
    r = 0usize
    while r < 4usize {
        dsa_unpack_centered(sig[32usize + r * 576usize..32usize + (r + 1usize) * 576usize], dsa_gamma1(), 18usize, zhat[r * 256usize..(r + 1usize) * 256usize])
        if dsa_norm_reaches(zhat[r * 256usize..(r + 1usize) * 256usize], dsa_gamma1() - dsa_beta()) { ret false }
        dsa_ntt(zhat[r * 256usize..(r + 1usize) * 256usize])
        r += 1usize
    }
    var tr = hash.shake256_init()
    hash.shake_absorb(&tr, pk[0..1312])
    var tr_bytes: [64]u8 = zero
    hash.shake_squeeze(&tr, tr_bytes[0..])
    let mu = dsa_mu(tr_bytes[0..], message, ctx)
    var c: [256]i64 = zero
    dsa_sample_in_ball(sig[0..32], c[0..])
    dsa_ntt(c[0..])
    var challenge = hash.shake256_init()
    hash.shake_absorb(&challenge, mu[0..])
    var w1: [1024]i64 = zero
    r = 0usize
    while r < 4usize {
        var w: [256]i64 = zero
        var s = 0usize
        while s < 4usize {
            dsa_mul_acc(w[0..], a[(r * 4usize + s) * 256usize..(r * 4usize + s + 1usize) * 256usize], zhat[s * 256usize..(s + 1usize) * 256usize])
            s += 1usize
        }
        var t1: [256]i64 = zero
        dsa_unpack(pk[32usize + r * 320usize..32usize + (r + 1usize) * 320usize], 10usize, t1[0..])
        var i = 0usize
        while i < 256usize {
            t1[i] = (t1[i] * 8192i64) % dsa_q()
            i += 1usize
        }
        dsa_ntt(t1[0..])
        var ct1: [256]i64 = zero
        dsa_mul_acc(ct1[0..], c[0..], t1[0..])
        dsa_sub(w[0..], ct1[0..])
        dsa_intt(w[0..])
        i = 0usize
        while i < 256usize {
            w1[r * 256usize + i] = dsa_use_hint(hints[r * 256usize + i], w[i])
            i += 1usize
        }
        r += 1usize
    }
    dsa_absorb_w1(&challenge, w1[0..])
    var c_tilde: [32]u8 = zero
    hash.shake_squeeze(&challenge, c_tilde[0..])
    ret hash.equal_constant_time(c_tilde[0..], sig[0..32])
}

// One full round: keygen from the seed, sign, verify; answers the verdict.
fn ml_dsa(seed: [32]u8, message: []const u8, ctx: []const u8, pk: []u8, sk: []u8, sig: []u8) -> (bool, err) {
    let keygen_error = ml_dsa_keygen(seed, pk, sk)
    if keygen_error != ok { ret (false, keygen_error) }
    let sign_error = ml_dsa_sign(sk, message, ctx, sig)
    if sign_error != ok { ret (false, sign_error) }
    ret (ml_dsa_verify(pk, message, ctx, sig), ok)
}

// XMSS by RFC 8391 with the XMSS-SHA2_h_256 functions (n = 32, w = 16, len = 67, the
// address structure and the 32-byte padding words 0..3 of F, H, H_msg and PRF), and
// WOTS+ secret keys by SP 800-208 section 7.2.1 (PRF_keygen, padding word 4, over
// S_XMSS || SEED || ADRS). The tree height is a parameter so a short tree can be
// exercised; `xmss_sha2_10_256_height` names the RFC parameter set. The whole tree is
// built at keygen into caller storage of `xmss_nodes_len(height)` bytes, level by
// level, and signing reads its authentication path from there. The secret key holds
// the next index: signing uses it and advances it, and refuses an exhausted key.
//
// ponytail: keygen computes every leaf (2^height WOTS+ key generations); no BDS
// traversal, no caching of chains, nothing constant time.

type XmssSecretKey = struct { index: u32, height: usize, sk_seed: [32]u8, sk_prf: [32]u8, pub_seed: [32]u8, root: [32]u8 }
type XmssPublicKey = struct { height: usize, root: [32]u8, pub_seed: [32]u8 }

fn xmss_sha2_10_256_height() -> usize { ret 10usize }
fn xmss_nodes_len(height: usize) -> usize { ret ((2usize << u32(height)) - 1usize) * 32usize }
fn xmss_sig_len(height: usize) -> usize { ret 36usize + 2144usize + 32usize * height }

// SHA256(toByte(prefix, 32) || key || m).
fn xmss_hash(prefix: u8, key: []const u8, m: []const u8) -> [32]u8 {
    var pad: [32]u8 = zero
    pad[31] = prefix
    var s = hash.sha256_init()
    hash.sha256_update(&s, pad[0..])
    hash.sha256_update(&s, key)
    hash.sha256_update(&s, m)
    ret hash.sha256_done(&s)
}

fn xmss_adrs_set(adrs: []u8, word: usize, value: u32) {
    adrs[word * 4usize] = u8((value >> 24u32) & 255u32)
    adrs[word * 4usize + 1usize] = u8((value >> 16u32) & 255u32)
    adrs[word * 4usize + 2usize] = u8((value >> 8u32) & 255u32)
    adrs[word * 4usize + 3usize] = u8(value & 255u32)
}

fn xmss_adrs_get(adrs: []const u8, word: usize) -> u32 {
    ret (u32(adrs[word * 4usize]) << 24u32) | (u32(adrs[word * 4usize + 1usize]) << 16u32) | (u32(adrs[word * 4usize + 2usize]) << 8u32) | u32(adrs[word * 4usize + 3usize])
}

// setType: the type word and a clear of the four words after it.
fn xmss_adrs_type(adrs: []u8, kind: u32) {
    xmss_adrs_set(adrs, 3usize, kind)
    var word = 4usize
    while word < 8usize {
        xmss_adrs_set(adrs, word, 0u32)
        word += 1usize
    }
}

// Algorithm 2 in place: `steps` applications of F from hash address `start`.
fn xmss_chain(x: []u8, start: usize, steps: usize, adrs: []u8, seed: []const u8) {
    var j = start
    while j < start + steps {
        xmss_adrs_set(adrs, 6usize, u32(j))
        xmss_adrs_set(adrs, 7usize, 0u32)
        let key = xmss_hash(3u8, seed, adrs)
        xmss_adrs_set(adrs, 7usize, 1u32)
        let mask = xmss_hash(3u8, seed, adrs)
        var i = 0usize
        while i < 32usize {
            x[i] = x[i] ^ mask[i]
            i += 1usize
        }
        let next_x = xmss_hash(0u8, key[0..], x)
        i = 0usize
        while i < 32usize {
            x[i] = next_x[i]
            i += 1usize
        }
        j += 1usize
    }
}

// The 67 WOTS+ secret key elements of one leaf (adrs already of type 0 with the OTS address).
fn xmss_wots_sk(sk_seed: []const u8, seed: []const u8, adrs: []u8, out: []u8) {
    var m: [64]u8 = zero
    var i = 0usize
    while i < 32usize {
        m[i] = seed[i]
        i += 1usize
    }
    var chain = 0usize
    while chain < 67usize {
        xmss_adrs_set(adrs, 5usize, u32(chain))
        xmss_adrs_set(adrs, 6usize, 0u32)
        xmss_adrs_set(adrs, 7usize, 0u32)
        i = 0usize
        while i < 32usize {
            m[32usize + i] = adrs[i]
            i += 1usize
        }
        let element = xmss_hash(4u8, sk_seed, m[0..])
        i = 0usize
        while i < 32usize {
            out[chain * 32usize + i] = element[i]
            i += 1usize
        }
        chain += 1usize
    }
}

// base_w of the message and its checksum: 64 nibbles then 3 more from csum << 4.
fn xmss_digits(msg: []const u8) -> [67]u8 {
    var d: [67]u8 = zero
    var csum = 0u32
    var i = 0usize
    while i < 32usize {
        d[2usize * i] = msg[i] >> 4u32
        d[2usize * i + 1usize] = msg[i] & 15u8
        csum += 15u32 - u32(d[2usize * i]) + 15u32 - u32(d[2usize * i + 1usize])
        i += 1usize
    }
    csum = csum << 4u32
    d[64] = u8((csum >> 12u32) & 15u32)
    d[65] = u8((csum >> 8u32) & 15u32)
    d[66] = u8((csum >> 4u32) & 15u32)
    ret d
}

// Algorithm 7: H(KEY, (left ^ BM_0) || (right ^ BM_1)) with the three PRF calls.
fn xmss_rand_hash(left: []const u8, right: []const u8, seed: []const u8, adrs: []u8) -> [32]u8 {
    xmss_adrs_set(adrs, 7usize, 0u32)
    let key = xmss_hash(3u8, seed, adrs)
    xmss_adrs_set(adrs, 7usize, 1u32)
    let mask0 = xmss_hash(3u8, seed, adrs)
    xmss_adrs_set(adrs, 7usize, 2u32)
    let mask1 = xmss_hash(3u8, seed, adrs)
    var m: [64]u8 = zero
    var i = 0usize
    while i < 32usize {
        m[i] = left[i] ^ mask0[i]
        m[32usize + i] = right[i] ^ mask1[i]
        i += 1usize
    }
    ret xmss_hash(1u8, key[0..], m[0..])
}

// Algorithm 8 over the 67 public key elements in `pk`, which it consumes.
fn xmss_ltree(pk: []u8, seed: []const u8, adrs: []u8) -> [32]u8 {
    var count = 67usize
    var height = 0u32
    xmss_adrs_set(adrs, 5usize, 0u32)
    while count > 1usize {
        var i = 0usize
        while i < count / 2usize {
            xmss_adrs_set(adrs, 6usize, u32(i))
            let node = xmss_rand_hash(pk[2usize * i * 32usize..(2usize * i + 1usize) * 32usize], pk[(2usize * i + 1usize) * 32usize..(2usize * i + 2usize) * 32usize], seed, adrs)
            var b = 0usize
            while b < 32usize {
                pk[i * 32usize + b] = node[b]
                b += 1usize
            }
            i += 1usize
        }
        if count % 2usize == 1usize {
            var b = 0usize
            while b < 32usize {
                pk[(count / 2usize) * 32usize + b] = pk[(count - 1usize) * 32usize + b]
                b += 1usize
            }
        }
        count = (count + 1usize) / 2usize
        height += 1u32
        xmss_adrs_set(adrs, 5usize, height)
    }
    var out: [32]u8 = zero
    var b = 0usize
    while b < 32usize {
        out[b] = pk[b]
        b += 1usize
    }
    ret out
}

// One leaf: the WOTS+ public key of leaf `index` through its L-tree.
fn xmss_leaf(sk_seed: []const u8, seed: []const u8, index: u32) -> [32]u8 {
    var adrs: [32]u8 = zero
    xmss_adrs_type(adrs[0..], 0u32)
    xmss_adrs_set(adrs[0..], 4usize, index)
    var elements: [2144]u8 = zero
    xmss_wots_sk(sk_seed, seed, adrs[0..], elements[0..])
    var chain = 0usize
    while chain < 67usize {
        xmss_adrs_set(adrs[0..], 5usize, u32(chain))
        xmss_chain(elements[chain * 32usize..(chain + 1usize) * 32usize], 0usize, 15usize, adrs[0..], seed)
        chain += 1usize
    }
    xmss_adrs_type(adrs[0..], 1u32)
    xmss_adrs_set(adrs[0..], 4usize, index)
    ret xmss_ltree(elements[0..], seed, adrs[0..])
}

// Byte offset of node j at level t in the level-by-level layout (level 0 = leaves).
fn xmss_node_at(height: usize, level: usize, j: usize) -> usize {
    ret ((2usize << u32(height)) - (2usize << u32(height - level)) + j) * 32usize
}

// Algorithm 10 without the OID: every node of the tree into `nodes`, the root in the key.
fn xmss_keygen(height: usize, sk_seed: [32]u8, sk_prf: [32]u8, pub_seed: [32]u8, nodes: []u8) -> (XmssSecretKey, err) {
    var sk: XmssSecretKey = zero
    if height < 1usize || height > 20usize { ret (sk, Invalid) }
    if nodes.len < xmss_nodes_len(height) { ret (sk, TooSmall) }
    sk.height = height
    sk.sk_seed = sk_seed
    sk.sk_prf = sk_prf
    sk.pub_seed = pub_seed
    var i = 0usize
    while i < (1usize << u32(height)) {
        let leaf = xmss_leaf(sk_seed[0..], pub_seed[0..], u32(i))
        let at = xmss_node_at(height, 0usize, i)
        var b = 0usize
        while b < 32usize {
            nodes[at + b] = leaf[b]
            b += 1usize
        }
        i += 1usize
    }
    var level = 0usize
    var adrs: [32]u8 = zero
    xmss_adrs_type(adrs[0..], 2u32)
    while level < height {
        xmss_adrs_set(adrs[0..], 5usize, u32(level))
        var j = 0usize
        while j < (1usize << u32(height - level - 1usize)) {
            xmss_adrs_set(adrs[0..], 6usize, u32(j))
            let left = xmss_node_at(height, level, 2usize * j)
            let parent = xmss_rand_hash(nodes[left..left + 32usize], nodes[left + 32usize..left + 64usize], pub_seed[0..], adrs[0..])
            let at = xmss_node_at(height, level + 1usize, j)
            var b = 0usize
            while b < 32usize {
                nodes[at + b] = parent[b]
                b += 1usize
            }
            j += 1usize
        }
        level += 1usize
    }
    let root_at = xmss_node_at(height, height, 0usize)
    i = 0usize
    while i < 32usize {
        sk.root[i] = nodes[root_at + i]
        i += 1usize
    }
    ret (sk, ok)
}

fn xmss_public(sk: XmssSecretKey) -> XmssPublicKey {
    var pk: XmssPublicKey = zero
    pk.height = sk.height
    pk.root = sk.root
    pk.pub_seed = sk.pub_seed
    ret pk
}

// M' = H_msg(r || root || toByte(idx, 32), message).
fn xmss_message_digest(r: []const u8, root: []const u8, index: u32, message: []const u8) -> [32]u8 {
    var key: [96]u8 = zero
    var i = 0usize
    while i < 32usize {
        key[i] = r[i]
        key[32usize + i] = root[i]
        i += 1usize
    }
    xmss_adrs_set(key[64..96], 7usize, index)
    ret xmss_hash(2u8, key[0..], message)
}

// Algorithm 12: sig = idx (4) || r (32) || sig_ots (2144) || auth (32 h); advances sk.index.
fn xmss_sign(sk: *XmssSecretKey, nodes: []const u8, message: []const u8, sig: []u8) -> err {
    let height = sk.height
    if sig.len < xmss_sig_len(height) { ret TooSmall }
    if nodes.len < xmss_nodes_len(height) { ret TooSmall }
    if usize(sk.index) >= (1usize << u32(height)) { ret Invalid }
    let index = sk.index
    sk.index += 1u32
    var index_bytes: [32]u8 = zero
    xmss_adrs_set(index_bytes[0..], 7usize, index)
    let r = xmss_hash(3u8, sk.sk_prf[0..], index_bytes[0..])
    let digest = xmss_message_digest(r[0..], sk.root[0..], index, message)
    xmss_adrs_set(sig[0..4], 0usize, index)
    var i = 0usize
    while i < 32usize {
        sig[4usize + i] = r[i]
        i += 1usize
    }
    var adrs: [32]u8 = zero
    xmss_adrs_type(adrs[0..], 0u32)
    xmss_adrs_set(adrs[0..], 4usize, index)
    xmss_wots_sk(sk.sk_seed[0..], sk.pub_seed[0..], adrs[0..], sig[36..2180])
    let digits = xmss_digits(digest[0..])
    var chain = 0usize
    while chain < 67usize {
        xmss_adrs_set(adrs[0..], 5usize, u32(chain))
        xmss_chain(sig[36usize + chain * 32usize..36usize + (chain + 1usize) * 32usize], 0usize, usize(digits[chain]), adrs[0..], sk.pub_seed[0..])
        chain += 1usize
    }
    var k = 0usize
    while k < height {
        let at = xmss_node_at(height, k, (usize(index) >> u32(k)) ^ 1usize)
        var b = 0usize
        while b < 32usize {
            sig[2180usize + k * 32usize + b] = nodes[at + b]
            b += 1usize
        }
        k += 1usize
    }
    ret ok
}

// Algorithm 14: the WOTS+ public key from the signature, its L-tree, then the root path.
fn xmss_verify(pk: XmssPublicKey, message: []const u8, sig: []const u8) -> bool {
    let height = pk.height
    if sig.len < xmss_sig_len(height) { ret false }
    let index = xmss_adrs_get(sig, 0usize)
    if usize(index) >= (1usize << u32(height)) { ret false }
    let digest = xmss_message_digest(sig[4..36], pk.root[0..], index, message)
    let digits = xmss_digits(digest[0..])
    var adrs: [32]u8 = zero
    xmss_adrs_type(adrs[0..], 0u32)
    xmss_adrs_set(adrs[0..], 4usize, index)
    var elements: [2144]u8 = zero
    var i = 0usize
    while i < 2144usize {
        elements[i] = sig[36usize + i]
        i += 1usize
    }
    var chain = 0usize
    while chain < 67usize {
        xmss_adrs_set(adrs[0..], 5usize, u32(chain))
        xmss_chain(elements[chain * 32usize..(chain + 1usize) * 32usize], usize(digits[chain]), 15usize - usize(digits[chain]), adrs[0..], pk.pub_seed[0..])
        chain += 1usize
    }
    xmss_adrs_type(adrs[0..], 1u32)
    xmss_adrs_set(adrs[0..], 4usize, index)
    var node = xmss_ltree(elements[0..], pk.pub_seed[0..], adrs[0..])
    xmss_adrs_type(adrs[0..], 2u32)
    var tree_index = index
    var k = 0usize
    while k < height {
        xmss_adrs_set(adrs[0..], 5usize, u32(k))
        let auth = sig[2180usize + k * 32usize..2180usize + (k + 1usize) * 32usize]
        if ((index >> u32(k)) & 1u32) == 0u32 {
            tree_index = tree_index / 2u32
            xmss_adrs_set(adrs[0..], 6usize, tree_index)
            node = xmss_rand_hash(node[0..], auth, pk.pub_seed[0..], adrs[0..])
        } else {
            tree_index = (tree_index - 1u32) / 2u32
            xmss_adrs_set(adrs[0..], 6usize, tree_index)
            node = xmss_rand_hash(auth, node[0..], pk.pub_seed[0..], adrs[0..])
        }
        k += 1usize
    }
    ret hash.equal_constant_time(node[0..], pk.root[0..])
}

// One full round at the given height: keygen, one signature at index 0, verify.
fn xmss(height: usize, sk_seed: [32]u8, sk_prf: [32]u8, pub_seed: [32]u8, nodes: []u8, message: []const u8, sig: []u8) -> (bool, err) {
    let (sk_value, keygen_error) = xmss_keygen(height, sk_seed, sk_prf, pub_seed, nodes)
    if keygen_error != ok { ret (false, keygen_error) }
    var sk = sk_value
    let sign_error = xmss_sign(&sk, nodes, message, sig)
    if sign_error != ok { ret (false, sign_error) }
    ret (xmss_verify(xmss_public(sk), message, sig), ok)
}
