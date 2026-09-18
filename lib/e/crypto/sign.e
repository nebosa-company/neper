// Ed25519 by RFC 8032: the twisted Edwards curve over 2^255 - 19 in extended
// coordinates with the unified addition formula, the field in the ten-limb form
// `e.crypto.kx` uses, scalars mod L as eight 32-bit limbs reduced bit by bit. Keys are
// seeds; signing derives the scalar and prefix from SHA-512 of the seed. Verification
// rejects a non-canonical point or scalar encoding and a public key of small order.
//
// ponytail: scalar multiplication is double-and-add and varies with the scalar; the
// field core is duplicated from kx.e because a fence admits no shared private helper.
use e.crypto.hash as hash

type Ed25519PublicKey = struct { bytes: [32]u8 }
type Ed25519SecretKey = struct { bytes: [32]u8 }
type Ed25519Signature = struct { bytes: [64]u8 }
type P256PublicKey = struct { bytes: [65]u8 }
error InvalidKey
error InvalidSignature

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
