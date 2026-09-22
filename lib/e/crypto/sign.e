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
