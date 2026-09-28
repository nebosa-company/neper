// Authenticated encryption: AES-GCM (NIST SP 800-38D) at both key sizes and
// ChaCha20-Poly1305 (RFC 8439), sealed as ciphertext followed by the sixteen-byte tag.
// `open` verifies the tag in constant time before it writes a byte of plaintext.
//
// AES-GCM runs a bitsliced AES, four blocks at a time in eight 64-bit words with Boyar and
// Peralta's S-box circuit (BearSSL's aes_ct64), and GHASH as carry-less multiplication built
// from integer products with the carries masked off (BearSSL's ghash_ctmul64) (D1645). The
// byte-oriented AES below, with its algebraic S-box, is the block function `e.crypto.cipher`
// exposes; it was GCM's too until TLS measured it at 372 KB/s. Poly1305 is five 26-bit limbs
// with 64-bit products, the way the reference does it. Nothing here has a secret-indexed
// lookup table or a secret-dependent branch.

use e.crypto.hash as hash
use e.crypto.random as random

error InvalidKey
error InvalidNonce
error TooSmall
error Authentication

// --- AES

fn rotl8(x: u8, count: u8) -> u8 {
    ret (x << count) | (x >> (8u8 - count))
}

// Multiplication by 2 in GF(2^8) with the AES polynomial. The high-bit mask avoids
// secret-dependent control flow.
fn xtime(x: u8) -> u8 {
    ret (x << 1u8) ^ (27u8 * (x >> 7u8))
}

fn gf8_mul(a: u8, b: u8) -> u8 {
    var product = 0u8
    var x = a
    var y = b
    var i = 0usize
    while i < 8usize {
        let mask = 255u8 * (y & 1u8)
        product = product ^ (x & mask)
        x = xtime(x)
        y = y >> 1u8
        i += 1usize
    }
    ret product
}

// x^254 is the multiplicative inverse in GF(2^8), including 0 -> 0. The fixed
// addition chain has the same operation count for every byte.
fn gf8_inverse(x: u8) -> u8 {
    let x2 = gf8_mul(x, x)
    let x4 = gf8_mul(x2, x2)
    let x8 = gf8_mul(x4, x4)
    let x16 = gf8_mul(x8, x8)
    let x32 = gf8_mul(x16, x16)
    let x64 = gf8_mul(x32, x32)
    let x128 = gf8_mul(x64, x64)
    ret gf8_mul(gf8_mul(gf8_mul(x128, x64), gf8_mul(x32, x16)), gf8_mul(gf8_mul(x8, x4), x2))
}

fn sbox(index: u8) -> u8 {
    let x = gf8_inverse(index)
    ret x ^ rotl8(x, 1u8) ^ rotl8(x, 2u8) ^ rotl8(x, 3u8) ^ rotl8(x, 4u8) ^ 99u8
}

type AesKey = struct { round_keys: [240]u8, rounds: usize }

fn expand_key(key: []const u8) -> AesKey {
    var k: AesKey = zero
    let words = key.len / 4usize
    k.rounds = words + 6usize
    let total = 4usize * (k.rounds + 1usize)
    var at = 0usize
    while at < key.len {
        k.round_keys[at] = key[at]
        at += 1usize
    }
    var rcon = 1u8
    var i = words
    while i < total {
        var t0 = k.round_keys[(i - 1usize) * 4usize]
        var t1 = k.round_keys[(i - 1usize) * 4usize + 1usize]
        var t2 = k.round_keys[(i - 1usize) * 4usize + 2usize]
        var t3 = k.round_keys[(i - 1usize) * 4usize + 3usize]
        if i % words == 0usize {
            let rotated = t0
            t0 = sbox(t1) ^ rcon
            t1 = sbox(t2)
            t2 = sbox(t3)
            t3 = sbox(rotated)
            rcon = xtime(rcon)
        } else {
            if words > 6usize && i % words == 4usize {
                t0 = sbox(t0)
                t1 = sbox(t1)
                t2 = sbox(t2)
                t3 = sbox(t3)
            }
        }
        k.round_keys[i * 4usize] = k.round_keys[(i - words) * 4usize] ^ t0
        k.round_keys[i * 4usize + 1usize] = k.round_keys[(i - words) * 4usize + 1usize] ^ t1
        k.round_keys[i * 4usize + 2usize] = k.round_keys[(i - words) * 4usize + 2usize] ^ t2
        k.round_keys[i * 4usize + 3usize] = k.round_keys[(i - words) * 4usize + 3usize] ^ t3
        i += 1usize
    }
    ret k
}

fn add_round_key(state: []u8, k: *const AesKey, round: usize) {
    var at = 0usize
    while at < 16usize {
        state[at] = state[at] ^ k.round_keys[round * 16usize + at]
        at += 1usize
    }
}

fn aes_encrypt_block(k: *const AesKey, block: []u8) {
    var state: [16]u8 = zero
    var at = 0usize
    while at < 16usize {
        state[at] = block[at]
        at += 1usize
    }
    add_round_key(state[0..], k, 0usize)
    var round = 1usize
    while round <= k.rounds {
        // SubBytes
        at = 0usize
        while at < 16usize {
            state[at] = sbox(state[at])
            at += 1usize
        }
        // ShiftRows: the state is column-major, row r shifts left by r.
        var shifted: [16]u8 = zero
        var column = 0usize
        while column < 4usize {
            var row = 0usize
            while row < 4usize {
                shifted[column * 4usize + row] = state[((column + row) % 4usize) * 4usize + row]
                row += 1usize
            }
            column += 1usize
        }
        // MixColumns, except in the last round.
        if round != k.rounds {
            column = 0usize
            while column < 4usize {
                let a0 = shifted[column * 4usize]
                let a1 = shifted[column * 4usize + 1usize]
                let a2 = shifted[column * 4usize + 2usize]
                let a3 = shifted[column * 4usize + 3usize]
                state[column * 4usize] = xtime(a0) ^ (xtime(a1) ^ a1) ^ a2 ^ a3
                state[column * 4usize + 1usize] = a0 ^ xtime(a1) ^ (xtime(a2) ^ a2) ^ a3
                state[column * 4usize + 2usize] = a0 ^ a1 ^ xtime(a2) ^ (xtime(a3) ^ a3)
                state[column * 4usize + 3usize] = (xtime(a0) ^ a0) ^ a1 ^ a2 ^ xtime(a3)
                column += 1usize
            }
        } else {
            at = 0usize
            while at < 16usize {
                state[at] = shifted[at]
                at += 1usize
            }
        }
        add_round_key(state[0..], k, round)
        round += 1usize
    }
    at = 0usize
    while at < 16usize {
        block[at] = state[at]
        at += 1usize
    }
}

// --- Bitsliced AES for GCM (BearSSL's aes_ct64). Four blocks travel together in eight
// 64-bit words; word i holds bit i of all 64 bytes, so SubBytes is one pass of a boolean
// circuit and ShiftRows and MixColumns are shifts and rotations of whole words.

const M55: u64 = 6148914691236517205u64
const MAA: u64 = 12297829382473034410u64
const M33: u64 = 3689348814741910323u64
const MCC: u64 = 14757395258967641292u64
const M0F: u64 = 1085102592571150095u64
const MF0: u64 = 17361641481138401520u64
const M00FF: u64 = 71777214294589695u64
const M0000FFFF: u64 = 281470681808895u64
const M11: u64 = 1229782938247303441u64
const M22: u64 = 2459565876494606882u64
const M44: u64 = 4919131752989213764u64
const M88: u64 = 9838263505978427528u64
const LOW32: u64 = 4294967295u64
const ONES: u64 = 18446744073709551615u64

// The round keys already bitsliced, eight words a round, for up to fourteen rounds.
type CtKey = struct { skey: [120]u64, rounds: usize }

// SubBytes on all 64 bytes: Boyar and Peralta's 113-gate circuit, bit 7 in q[0].
fn ct_sbox(q: []u64) {
    let x0 = q[7]
    let x1 = q[6]
    let x2 = q[5]
    let x3 = q[4]
    let x4 = q[3]
    let x5 = q[2]
    let x6 = q[1]
    let x7 = q[0]
    // The top linear transformation.
    let y14 = x3 ^ x5
    let y13 = x0 ^ x6
    let y9 = x0 ^ x3
    let y8 = x0 ^ x5
    let t0 = x1 ^ x2
    let y1 = t0 ^ x7
    let y4 = y1 ^ x3
    let y12 = y13 ^ y14
    let y2 = y1 ^ x0
    let y5 = y1 ^ x6
    let y3 = y5 ^ y8
    let t1 = x4 ^ y12
    let y15 = t1 ^ x5
    let y20 = t1 ^ x1
    let y6 = y15 ^ x7
    let y10 = y15 ^ t0
    let y11 = y20 ^ y9
    let y7 = x7 ^ y11
    let y17 = y10 ^ y11
    let y19 = y10 ^ y8
    let y16 = t0 ^ y11
    let y21 = y13 ^ y16
    let y18 = x0 ^ y16
    // The non-linear section.
    let t2 = y12 & y15
    let t3 = y3 & y6
    let t4 = t3 ^ t2
    let t5 = y4 & x7
    let t6 = t5 ^ t2
    let t7 = y13 & y16
    let t8 = y5 & y1
    let t9 = t8 ^ t7
    let t10 = y2 & y7
    let t11 = t10 ^ t7
    let t12 = y9 & y11
    let t13 = y14 & y17
    let t14 = t13 ^ t12
    let t15 = y8 & y10
    let t16 = t15 ^ t12
    let t17 = t4 ^ t14
    let t18 = t6 ^ t16
    let t19 = t9 ^ t14
    let t20 = t11 ^ t16
    let t21 = t17 ^ y20
    let t22 = t18 ^ y19
    let t23 = t19 ^ y21
    let t24 = t20 ^ y18
    let t25 = t21 ^ t22
    let t26 = t21 & t23
    let t27 = t24 ^ t26
    let t28 = t25 & t27
    let t29 = t28 ^ t22
    let t30 = t23 ^ t24
    let t31 = t22 ^ t26
    let t32 = t31 & t30
    let t33 = t32 ^ t24
    let t34 = t23 ^ t33
    let t35 = t27 ^ t33
    let t36 = t24 & t35
    let t37 = t36 ^ t34
    let t38 = t27 ^ t36
    let t39 = t29 & t38
    let t40 = t25 ^ t39
    let t41 = t40 ^ t37
    let t42 = t29 ^ t33
    let t43 = t29 ^ t40
    let t44 = t33 ^ t37
    let t45 = t42 ^ t41
    let z0 = t44 & y15
    let z1 = t37 & y6
    let z2 = t33 & x7
    let z3 = t43 & y16
    let z4 = t40 & y1
    let z5 = t29 & y7
    let z6 = t42 & y11
    let z7 = t45 & y17
    let z8 = t41 & y10
    let z9 = t44 & y12
    let z10 = t37 & y3
    let z11 = t33 & y4
    let z12 = t43 & y13
    let z13 = t40 & y5
    let z14 = t29 & y2
    let z15 = t42 & y9
    let z16 = t45 & y14
    let z17 = t41 & y8
    // The bottom linear transformation.
    let t46 = z15 ^ z16
    let t47 = z10 ^ z11
    let t48 = z5 ^ z13
    let t49 = z9 ^ z10
    let t50 = z2 ^ z12
    let t51 = z2 ^ z5
    let t52 = z7 ^ z8
    let t53 = z0 ^ z3
    let t54 = z6 ^ z7
    let t55 = z16 ^ z17
    let t56 = z12 ^ t48
    let t57 = t50 ^ t53
    let t58 = z4 ^ t46
    let t59 = z3 ^ t54
    let t60 = t46 ^ t57
    let t61 = z14 ^ t57
    let t62 = t52 ^ t58
    let t63 = t49 ^ t58
    let t64 = z4 ^ t59
    let t65 = t61 ^ t62
    let t66 = z1 ^ t63
    let s0 = t59 ^ t63
    let s6 = t56 ^ t62 ^ ONES
    let s7 = t48 ^ t60 ^ ONES
    let t67 = t64 ^ t65
    let s3 = t53 ^ t66
    let s4 = t51 ^ t66
    let s5 = t47 ^ t65
    let s1 = t64 ^ s3 ^ ONES
    let s2 = t55 ^ t67 ^ ONES
    q[7] = s0
    q[6] = s1
    q[5] = s2
    q[4] = s3
    q[3] = s4
    q[2] = s5
    q[1] = s6
    q[0] = s7
}

fn ct_swap(q: []u64, i: usize, j: usize, low: u64, high: u64, s: u32) {
    let a = q[i]
    let b = q[j]
    q[i] = (a & low) | ((b & low) << s)
    q[j] = ((a & high) >> s) | (b & high)
}

// Between the interleaved words and the bitsliced ones; its own inverse.
fn ct_ortho(q: []u64) {
    ct_swap(q, 0usize, 1usize, M55, MAA, 1u32)
    ct_swap(q, 2usize, 3usize, M55, MAA, 1u32)
    ct_swap(q, 4usize, 5usize, M55, MAA, 1u32)
    ct_swap(q, 6usize, 7usize, M55, MAA, 1u32)
    ct_swap(q, 0usize, 2usize, M33, MCC, 2u32)
    ct_swap(q, 1usize, 3usize, M33, MCC, 2u32)
    ct_swap(q, 4usize, 6usize, M33, MCC, 2u32)
    ct_swap(q, 5usize, 7usize, M33, MCC, 2u32)
    ct_swap(q, 0usize, 4usize, M0F, MF0, 4u32)
    ct_swap(q, 1usize, 5usize, M0F, MF0, 4u32)
    ct_swap(q, 2usize, 6usize, M0F, MF0, 4u32)
    ct_swap(q, 3usize, 7usize, M0F, MF0, 4u32)
}

// One block's four little-endian words spread into q[i0] (bytes 0, 2, ...) and q[i1].
fn ct_interleave_in(q: []u64, i0: usize, i1: usize, w: []const u32) {
    var x0 = u64(w[0])
    var x1 = u64(w[1])
    var x2 = u64(w[2])
    var x3 = u64(w[3])
    x0 = (x0 | (x0 << 16u32)) & M0000FFFF
    x1 = (x1 | (x1 << 16u32)) & M0000FFFF
    x2 = (x2 | (x2 << 16u32)) & M0000FFFF
    x3 = (x3 | (x3 << 16u32)) & M0000FFFF
    x0 = (x0 | (x0 << 8u32)) & M00FF
    x1 = (x1 | (x1 << 8u32)) & M00FF
    x2 = (x2 | (x2 << 8u32)) & M00FF
    x3 = (x3 | (x3 << 8u32)) & M00FF
    q[i0] = x0 | (x2 << 8u32)
    q[i1] = x1 | (x3 << 8u32)
}

fn ct_interleave_out(w: []u32, q0: u64, q1: u64) {
    var x0 = q0 & M00FF
    var x1 = q1 & M00FF
    var x2 = (q0 >> 8u32) & M00FF
    var x3 = (q1 >> 8u32) & M00FF
    x0 = (x0 | (x0 >> 8u32)) & M0000FFFF
    x1 = (x1 | (x1 >> 8u32)) & M0000FFFF
    x2 = (x2 | (x2 >> 8u32)) & M0000FFFF
    x3 = (x3 | (x3 >> 8u32)) & M0000FFFF
    w[0] = u32((x0 | (x0 >> 16u32)) & LOW32)
    w[1] = u32((x1 | (x1 >> 16u32)) & LOW32)
    w[2] = u32((x2 | (x2 >> 16u32)) & LOW32)
    w[3] = u32((x3 | (x3 >> 16u32)) & LOW32)
}

fn ct_shift_rows(q: []u64) {
    var i = 0usize
    while i < 8usize {
        let x = q[i]
        q[i] = (x & 65535u64) | ((x & 4293918720u64) >> 4u32) | ((x & 983040u64) << 12u32) | ((x & 280375465082880u64) >> 8u32) | ((x & 1095216660480u64) << 8u32) | ((x & 17293822569102704640u64) >> 12u32) | ((x & 1152640029630136320u64) << 4u32)
        i += 1usize
    }
}

fn rotr32_64(x: u64) -> u64 { ret (x << 32u32) | (x >> 32u32) }

fn ct_mix_columns(q: []u64) {
    let q0 = q[0]
    let q1 = q[1]
    let q2 = q[2]
    let q3 = q[3]
    let q4 = q[4]
    let q5 = q[5]
    let q6 = q[6]
    let q7 = q[7]
    let r0 = (q0 >> 16u32) | (q0 << 48u32)
    let r1 = (q1 >> 16u32) | (q1 << 48u32)
    let r2 = (q2 >> 16u32) | (q2 << 48u32)
    let r3 = (q3 >> 16u32) | (q3 << 48u32)
    let r4 = (q4 >> 16u32) | (q4 << 48u32)
    let r5 = (q5 >> 16u32) | (q5 << 48u32)
    let r6 = (q6 >> 16u32) | (q6 << 48u32)
    let r7 = (q7 >> 16u32) | (q7 << 48u32)
    q[0] = q7 ^ r7 ^ r0 ^ rotr32_64(q0 ^ r0)
    q[1] = q0 ^ r0 ^ q7 ^ r7 ^ r1 ^ rotr32_64(q1 ^ r1)
    q[2] = q1 ^ r1 ^ r2 ^ rotr32_64(q2 ^ r2)
    q[3] = q2 ^ r2 ^ q7 ^ r7 ^ r3 ^ rotr32_64(q3 ^ r3)
    q[4] = q3 ^ r3 ^ q7 ^ r7 ^ r4 ^ rotr32_64(q4 ^ r4)
    q[5] = q4 ^ r4 ^ r5 ^ rotr32_64(q5 ^ r5)
    q[6] = q5 ^ r5 ^ r6 ^ rotr32_64(q6 ^ r6)
    q[7] = q6 ^ r6 ^ r7 ^ rotr32_64(q7 ^ r7)
}

fn ct_add_round_key(q: []u64, k: *const CtKey, round: usize) {
    var i = 0usize
    while i < 8usize {
        q[i] = q[i] ^ k.skey[round * 8usize + i]
        i += 1usize
    }
}

fn ct_sub_word(x: u32) -> u32 {
    var q: [8]u64 = zero
    q[0] = u64(x)
    ct_ortho(q[0..])
    ct_sbox(q[0..])
    ct_ortho(q[0..])
    ret u32(q[0] & LOW32)
}

// One compressed round-key word spread back over four bit positions.
fn ct_spread(c: u64, bit: u64, shift: u32) -> u64 {
    let x = (c & bit) >> shift
    ret (x << 4u32) -% x
}

// The key schedule of FIPS 197 5.2 on little-endian words, each round key then bitsliced.
fn ct_key(key: []const u8) -> CtKey {
    var k: CtKey = zero
    let nk = key.len / 4usize
    k.rounds = nk + 6usize
    let total = (k.rounds + 1usize) * 4usize
    let rcon: [10]u32 = [10]u32{ 1, 2, 4, 8, 16, 32, 64, 128, 27, 54 }
    var words: [60]u32 = zero
    var i = 0usize
    while i < nk {
        words[i] = u32(key[4usize * i]) | (u32(key[4usize * i + 1usize]) << 8u32) | (u32(key[4usize * i + 2usize]) << 16u32) | (u32(key[4usize * i + 3usize]) << 24u32)
        i += 1usize
    }
    var tmp = words[nk - 1usize]
    var j = 0usize
    var r = 0usize
    while i < total {
        if j == 0usize {
            tmp = (tmp << 24u32) | (tmp >> 8u32)
            tmp = ct_sub_word(tmp) ^ rcon[r]
        } else if nk > 6usize && j == 4usize {
            tmp = ct_sub_word(tmp)
        }
        tmp = tmp ^ words[i - nk]
        words[i] = tmp
        j += 1usize
        if j == nk {
            j = 0usize
            r += 1usize
        }
        i += 1usize
    }
    var q: [8]u64 = zero
    var round = 0usize
    while round <= k.rounds {
        ct_interleave_in(q[0..], 0usize, 4usize, words[round * 4usize..round * 4usize + 4usize])
        q[1] = q[0]
        q[2] = q[0]
        q[3] = q[0]
        q[5] = q[4]
        q[6] = q[4]
        q[7] = q[4]
        ct_ortho(q[0..])
        let c0 = (q[0] & M11) | (q[1] & M22) | (q[2] & M44) | (q[3] & M88)
        let c1 = (q[4] & M11) | (q[5] & M22) | (q[6] & M44) | (q[7] & M88)
        let at = round * 8usize
        k.skey[at] = ct_spread(c0, M11, 0u32)
        k.skey[at + 1usize] = ct_spread(c0, M22, 1u32)
        k.skey[at + 2usize] = ct_spread(c0, M44, 2u32)
        k.skey[at + 3usize] = ct_spread(c0, M88, 3u32)
        k.skey[at + 4usize] = ct_spread(c1, M11, 0u32)
        k.skey[at + 5usize] = ct_spread(c1, M22, 1u32)
        k.skey[at + 6usize] = ct_spread(c1, M44, 2u32)
        k.skey[at + 7usize] = ct_spread(c1, M88, 3u32)
        round += 1usize
    }
    ret k
}

// Four blocks (64 bytes) encrypted in place.
fn ct_encrypt4(k: *const CtKey, blocks: []u8) {
    var w: [16]u32 = zero
    var i = 0usize
    while i < 16usize {
        let at = i * 4usize
        w[i] = u32(blocks[at]) | (u32(blocks[at + 1usize]) << 8u32) | (u32(blocks[at + 2usize]) << 16u32) | (u32(blocks[at + 3usize]) << 24u32)
        i += 1usize
    }
    var q: [8]u64 = zero
    i = 0usize
    while i < 4usize {
        ct_interleave_in(q[0..], i, i + 4usize, w[i * 4usize..i * 4usize + 4usize])
        i += 1usize
    }
    ct_ortho(q[0..])
    ct_add_round_key(q[0..], k, 0usize)
    var round = 1usize
    while round < k.rounds {
        ct_sbox(q[0..])
        ct_shift_rows(q[0..])
        ct_mix_columns(q[0..])
        ct_add_round_key(q[0..], k, round)
        round += 1usize
    }
    ct_sbox(q[0..])
    ct_shift_rows(q[0..])
    ct_add_round_key(q[0..], k, k.rounds)
    ct_ortho(q[0..])
    i = 0usize
    while i < 4usize {
        ct_interleave_out(w[i * 4usize..i * 4usize + 4usize], q[i], q[i + 4usize])
        i += 1usize
    }
    i = 0usize
    while i < 16usize {
        let at = i * 4usize
        blocks[at] = u8(w[i] & 255u32)
        blocks[at + 1usize] = u8((w[i] >> 8u32) & 255u32)
        blocks[at + 2usize] = u8((w[i] >> 16u32) & 255u32)
        blocks[at + 3usize] = u8(w[i] >> 24u32)
        i += 1usize
    }
}

// --- GHASH (BearSSL's ghash_ctmul64). A carry-less 64-bit product is four integer
// products of operands whose set bits are four apart, with the carries masked away; the
// reduction works on bit-reversed halves.

fn bmul64(x: u64, y: u64) -> u64 {
    let x0 = x & M11
    let x1 = x & M22
    let x2 = x & M44
    let x3 = x & M88
    let y0 = y & M11
    let y1 = y & M22
    let y2 = y & M44
    let y3 = y & M88
    let z0 = (x0 *% y0) ^ (x1 *% y3) ^ (x2 *% y2) ^ (x3 *% y1)
    let z1 = (x0 *% y1) ^ (x1 *% y0) ^ (x2 *% y3) ^ (x3 *% y2)
    let z2 = (x0 *% y2) ^ (x1 *% y1) ^ (x2 *% y0) ^ (x3 *% y3)
    let z3 = (x0 *% y3) ^ (x1 *% y2) ^ (x2 *% y1) ^ (x3 *% y0)
    ret (z0 & M11) | (z1 & M22) | (z2 & M44) | (z3 & M88)
}

fn rev64(v: u64) -> u64 {
    var x = v
    x = ((x & M55) << 1u32) | ((x >> 1u32) & M55)
    x = ((x & M33) << 2u32) | ((x >> 2u32) & M33)
    x = ((x & M0F) << 4u32) | ((x >> 4u32) & M0F)
    x = ((x & M00FF) << 8u32) | ((x >> 8u32) & M00FF)
    x = ((x & M0000FFFF) << 16u32) | ((x >> 16u32) & M0000FFFF)
    ret (x << 32u32) | (x >> 32u32)
}

fn be64_at(bytes: []const u8, at: usize, count: usize) -> u64 {
    var x = 0u64
    var i = 0usize
    while i < 8usize {
        var b = 0u64
        if i < count { b = u64(bytes[at + i]) }
        x = (x << 8u32) | b
        i += 1usize
    }
    ret x
}

// The running hash (y1 high, y0 low) and H with its reversed and combined halves.
type Ghash = struct { y1: u64, y0: u64, h1: u64, h0: u64, h1r: u64, h0r: u64, h2: u64, h2r: u64 }

fn ghash_init(h: []const u8) -> Ghash {
    var g: Ghash = zero
    g.h1 = be64_at(h, 0usize, 8usize)
    g.h0 = be64_at(h, 8usize, 8usize)
    g.h0r = rev64(g.h0)
    g.h1r = rev64(g.h1)
    g.h2 = g.h0 ^ g.h1
    g.h2r = g.h0r ^ g.h1r
    ret g
}

// `bytes` in 16-byte blocks, a short last one padded with zeros.
fn ghash_update(g: *Ghash, bytes: []const u8) {
    var at = 0usize
    while at < bytes.len {
        var take = bytes.len - at
        if take > 16usize { take = 16usize }
        var high_count = take
        if high_count > 8usize { high_count = 8usize }
        g.y1 = g.y1 ^ be64_at(bytes, at, high_count)
        if take > 8usize { g.y0 = g.y0 ^ be64_at(bytes, at + 8usize, take - 8usize) }
        let y0 = g.y0
        let y1 = g.y1
        let y0r = rev64(y0)
        let y1r = rev64(y1)
        let y2 = y0 ^ y1
        let y2r = y0r ^ y1r
        let z0 = bmul64(y0, g.h0)
        let z1 = bmul64(y1, g.h1)
        var z2 = bmul64(y2, g.h2)
        var z0h = bmul64(y0r, g.h0r)
        var z1h = bmul64(y1r, g.h1r)
        var z2h = bmul64(y2r, g.h2r)
        z2 = z2 ^ z0 ^ z1
        z2h = z2h ^ z0h ^ z1h
        z0h = rev64(z0h) >> 1u32
        z1h = rev64(z1h) >> 1u32
        z2h = rev64(z2h) >> 1u32
        var v0 = z0
        var v1 = z0h ^ z2
        var v2 = z1 ^ z2h
        var v3 = z1h
        v3 = (v3 << 1u32) | (v2 >> 63u32)
        v2 = (v2 << 1u32) | (v1 >> 63u32)
        v1 = (v1 << 1u32) | (v0 >> 63u32)
        v0 = v0 << 1u32
        v2 = v2 ^ v0 ^ (v0 >> 1u32) ^ (v0 >> 2u32) ^ (v0 >> 7u32)
        v1 = v1 ^ (v0 << 63u32) ^ (v0 << 62u32) ^ (v0 << 57u32)
        v3 = v3 ^ v1 ^ (v1 >> 1u32) ^ (v1 >> 2u32) ^ (v1 >> 7u32)
        v2 = v2 ^ (v1 << 63u32) ^ (v1 << 62u32) ^ (v1 << 57u32)
        g.y0 = v2
        g.y1 = v3
        at += 16usize
    }
}

// --- GCM

// H = E(K, 0) and E(K, J0), J0 = nonce || 1, from one four-block pass.
fn gcm_start(k: *const CtKey, nonce: [12]u8, h: []u8, j0: []u8) {
    var first: [64]u8 = zero
    var i = 0usize
    while i < 12usize {
        first[16usize + i] = nonce[i]
        i += 1usize
    }
    first[31] = 1u8
    ct_encrypt4(k, first[0..])
    i = 0usize
    while i < 16usize {
        h[i] = first[i]
        j0[i] = first[16usize + i]
        i += 1usize
    }
}

fn gcm_tag(h: []const u8, j0: []const u8, aad: []const u8, cipher: []const u8) -> [16]u8 {
    var g = ghash_init(h)
    ghash_update(&g, aad)
    ghash_update(&g, cipher)
    var lengths: [16]u8 = zero
    let aad_bits = u64(aad.len) * 8u64
    let cipher_bits = u64(cipher.len) * 8u64
    var i = 0usize
    while i < 8usize {
        lengths[i] = u8((aad_bits >> u32((7usize - i) * 8usize)) & 255u64)
        lengths[8usize + i] = u8((cipher_bits >> u32((7usize - i) * 8usize)) & 255u64)
        i += 1usize
    }
    ghash_update(&g, lengths[0..])
    var tag: [16]u8 = zero
    i = 0usize
    while i < 8usize {
        tag[i] = u8((g.y1 >> u32((7usize - i) * 8usize)) & 255u64) ^ j0[i]
        tag[8usize + i] = u8((g.y0 >> u32((7usize - i) * 8usize)) & 255u64) ^ j0[8usize + i]
        i += 1usize
    }
    ret tag
}

// CTR mode from counter 2, in place over `data`, four blocks a pass.
fn gcm_crypt(k: *const CtKey, nonce: [12]u8, data: []u8) {
    var counter = 2u32
    var stream: [64]u8 = zero
    var at = 0usize
    while at < data.len {
        var b = 0usize
        while b < 4usize {
            var i = 0usize
            while i < 12usize {
                stream[b * 16usize + i] = nonce[i]
                i += 1usize
            }
            let n = counter +% u32(b)
            stream[b * 16usize + 12usize] = u8(n >> 24u32)
            stream[b * 16usize + 13usize] = u8((n >> 16u32) & 255u32)
            stream[b * 16usize + 14usize] = u8((n >> 8u32) & 255u32)
            stream[b * 16usize + 15usize] = u8(n & 255u32)
            b += 1usize
        }
        ct_encrypt4(k, stream[0..])
        var take = data.len - at
        if take > 64usize { take = 64usize }
        var i = 0usize
        while i < take {
            data[at + i] = data[at + i] ^ stream[i]
            i += 1usize
        }
        counter = counter +% 4u32
        at += 64usize
    }
}

fn gcm_seal(dst: []u8, key: []const u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err) {
    if dst.len < plain.len + 16usize { ret (0usize, TooSmall) }
    let k = ct_key(key)
    var h: [16]u8 = zero
    var j0: [16]u8 = zero
    gcm_start(&k, nonce, h[0..], j0[0..])
    var at = 0usize
    while at < plain.len {
        dst[at] = plain[at]
        at += 1usize
    }
    gcm_crypt(&k, nonce, dst[..plain.len])
    let tag = gcm_tag(h[0..], j0[0..], aad, dst[..plain.len])
    at = 0usize
    while at < 16usize {
        dst[plain.len + at] = tag[at]
        at += 1usize
    }
    ret (plain.len + 16usize, ok)
}

fn gcm_open(dst: []u8, key: []const u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err) {
    if sealed.len < 16usize { ret (0usize, Authentication) }
    let cipher_len = sealed.len - 16usize
    if dst.len < cipher_len { ret (0usize, TooSmall) }
    let k = ct_key(key)
    var h: [16]u8 = zero
    var j0: [16]u8 = zero
    gcm_start(&k, nonce, h[0..], j0[0..])
    let tag = gcm_tag(h[0..], j0[0..], aad, sealed[..cipher_len])
    if !hash.equal_constant_time(tag[0..], sealed[cipher_len..]) { ret (0usize, Authentication) }
    var at = 0usize
    while at < cipher_len {
        dst[at] = sealed[at]
        at += 1usize
    }
    gcm_crypt(&k, nonce, dst[..cipher_len])
    ret (cipher_len, ok)
}

fn aes128_gcm_seal(dst: []u8, key: [16]u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err) {
    let (written, seal_error) = gcm_seal(dst, key[0..], nonce, aad, plain)
    ret (written, seal_error)
}

fn aes128_gcm_open(dst: []u8, key: [16]u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err) {
    let (written, open_error) = gcm_open(dst, key[0..], nonce, aad, sealed)
    ret (written, open_error)
}

fn aes256_gcm_seal(dst: []u8, key: [32]u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err) {
    let (written, seal_error) = gcm_seal(dst, key[0..], nonce, aad, plain)
    ret (written, seal_error)
}

fn aes256_gcm_open(dst: []u8, key: [32]u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err) {
    let (written, open_error) = gcm_open(dst, key[0..], nonce, aad, sealed)
    ret (written, open_error)
}

// --- Poly1305, in five 26-bit limbs.

type Poly = struct { r: [5]u32, h: [5]u32, pad: [4]u32 }

fn load_le32(bytes: []const u8, at: usize) -> u32 {
    let low = u32(bytes[at]) | (u32(bytes[at + 1usize]) << 8u32)
    ret low | (u32(bytes[at + 2usize]) << 16u32) | (u32(bytes[at + 3usize]) << 24u32)
}

fn poly_init(key: []const u8) -> Poly {
    var p: Poly = zero
    // r is clamped: the top four bits of each 32-bit word and the low two of the upper three.
    let t0 = load_le32(key, 0usize)
    let t1 = load_le32(key, 4usize)
    let t2 = load_le32(key, 8usize)
    let t3 = load_le32(key, 12usize)
    p.r[0] = t0 & 67108863u32
    p.r[1] = ((t0 >> 26u32) | (t1 << 6u32)) & 67108611u32
    p.r[2] = ((t1 >> 20u32) | (t2 << 12u32)) & 67092735u32
    p.r[3] = ((t2 >> 14u32) | (t3 << 18u32)) & 66076671u32
    p.r[4] = (t3 >> 8u32) & 1048575u32
    p.pad[0] = load_le32(key, 16usize)
    p.pad[1] = load_le32(key, 20usize)
    p.pad[2] = load_le32(key, 24usize)
    p.pad[3] = load_le32(key, 28usize)
    ret p
}

// One block (sixteen bytes, or fewer at the end) folded in: h = (h + block) * r.
fn poly_block(p: *Poly, block: []const u8, final_partial: bool) {
    var padded: [16]u8 = zero
    var i = 0usize
    while i < block.len {
        padded[i] = block[i]
        i += 1usize
    }
    var high_bit = 16777216u32
    if final_partial {
        padded[block.len] = 1u8
        high_bit = 0u32
    }
    let t0 = load_le32(padded[0..], 0usize)
    let t1 = load_le32(padded[0..], 4usize)
    let t2 = load_le32(padded[0..], 8usize)
    let t3 = load_le32(padded[0..], 12usize)
    var h0 = p.h[0] +% (t0 & 67108863u32)
    var h1 = p.h[1] +% (((t0 >> 26u32) | (t1 << 6u32)) & 67108863u32)
    var h2 = p.h[2] +% (((t1 >> 20u32) | (t2 << 12u32)) & 67108863u32)
    var h3 = p.h[3] +% (((t2 >> 14u32) | (t3 << 18u32)) & 67108863u32)
    var h4 = p.h[4] +% ((t3 >> 8u32) | high_bit)
    let r0 = u64(p.r[0])
    let r1 = u64(p.r[1])
    let r2 = u64(p.r[2])
    let r3 = u64(p.r[3])
    let r4 = u64(p.r[4])
    let s1 = r1 * 5u64
    let s2 = r2 * 5u64
    let s3 = r3 * 5u64
    let s4 = r4 * 5u64
    let d0 = u64(h0) * r0 + u64(h1) * s4 + u64(h2) * s3 + u64(h3) * s2 + u64(h4) * s1
    let d1 = u64(h0) * r1 + u64(h1) * r0 + u64(h2) * s4 + u64(h3) * s3 + u64(h4) * s2
    let d2 = u64(h0) * r2 + u64(h1) * r1 + u64(h2) * r0 + u64(h3) * s4 + u64(h4) * s3
    let d3 = u64(h0) * r3 + u64(h1) * r2 + u64(h2) * r1 + u64(h3) * r0 + u64(h4) * s4
    let d4 = u64(h0) * r4 + u64(h1) * r3 + u64(h2) * r2 + u64(h3) * r1 + u64(h4) * r0
    var carry = d0 >> 26u32
    h0 = u32(d0 & 67108863u64)
    let e1 = d1 + carry
    carry = e1 >> 26u32
    h1 = u32(e1 & 67108863u64)
    let e2 = d2 + carry
    carry = e2 >> 26u32
    h2 = u32(e2 & 67108863u64)
    let e3 = d3 + carry
    carry = e3 >> 26u32
    h3 = u32(e3 & 67108863u64)
    let e4 = d4 + carry
    carry = e4 >> 26u32
    h4 = u32(e4 & 67108863u64)
    h0 = h0 +% u32(carry * 5u64)
    carry = u64(h0 >> 26u32)
    h0 = h0 & 67108863u32
    h1 = h1 +% u32(carry)
    p.h[0] = h0
    p.h[1] = h1
    p.h[2] = h2
    p.h[3] = h3
    p.h[4] = h4
}

fn poly_update(p: *Poly, data: []const u8) {
    var at = 0usize
    while at + 16usize <= data.len {
        poly_block(p, data[at..at + 16usize], false)
        at += 16usize
    }
    if at < data.len { poly_block(p, data[at..], true) }
}

// The AEAD construction zero-pads each of aad and ciphertext to a multiple of sixteen,
// so their last partial block is a full block of zeros beyond the data, not the 0x01-
// terminated partial block of a bare Poly1305 message.
fn poly_update_padded(p: *Poly, data: []const u8) {
    var at = 0usize
    while at + 16usize <= data.len {
        poly_block(p, data[at..at + 16usize], false)
        at += 16usize
    }
    if at < data.len {
        var last: [16]u8 = zero
        var i = 0usize
        while at + i < data.len {
            last[i] = data[at + i]
            i += 1usize
        }
        poly_block(p, last[0..], false)
    }
}

fn poly_tag(p: *Poly) -> [16]u8 {
    var h0 = p.h[0]
    var h1 = p.h[1]
    var h2 = p.h[2]
    var h3 = p.h[3]
    var h4 = p.h[4]
    // Full carry.
    var c = h1 >> 26u32
    h1 = h1 & 67108863u32
    h2 = h2 +% c
    c = h2 >> 26u32
    h2 = h2 & 67108863u32
    h3 = h3 +% c
    c = h3 >> 26u32
    h3 = h3 & 67108863u32
    h4 = h4 +% c
    c = h4 >> 26u32
    h4 = h4 & 67108863u32
    h0 = h0 +% c *% 5u32
    c = h0 >> 26u32
    h0 = h0 & 67108863u32
    h1 = h1 +% c
    // h + -p, and take it if there was no borrow.
    var g0 = h0 +% 5u32
    c = g0 >> 26u32
    g0 = g0 & 67108863u32
    var g1 = h1 +% c
    c = g1 >> 26u32
    g1 = g1 & 67108863u32
    var g2 = h2 +% c
    c = g2 >> 26u32
    g2 = g2 & 67108863u32
    var g3 = h3 +% c
    c = g3 >> 26u32
    g3 = g3 & 67108863u32
    let g4 = h4 +% c -% 67108864u32
    let use_g = 0u32 -% ((g4 >> 31u32) ^ 1u32)
    h0 = (h0 & ~use_g) | (g0 & use_g)
    h1 = (h1 & ~use_g) | (g1 & use_g)
    h2 = (h2 & ~use_g) | (g2 & use_g)
    h3 = (h3 & ~use_g) | (g3 & use_g)
    h4 = (h4 & ~use_g) | (g4 & use_g)
    // Back to four 32-bit words, plus the pad.
    let w0 = h0 | (h1 << 26u32)
    let w1 = (h1 >> 6u32) | (h2 << 20u32)
    let w2 = (h2 >> 12u32) | (h3 << 14u32)
    let w3 = (h3 >> 18u32) | (h4 << 8u32)
    var f = u64(w0) + u64(p.pad[0])
    let o0 = u32(f & 4294967295u64)
    f = u64(w1) + u64(p.pad[1]) + (f >> 32u32)
    let o1 = u32(f & 4294967295u64)
    f = u64(w2) + u64(p.pad[2]) + (f >> 32u32)
    let o2 = u32(f & 4294967295u64)
    f = u64(w3) + u64(p.pad[3]) + (f >> 32u32)
    let o3 = u32(f & 4294967295u64)
    var tag: [16]u8 = zero
    let words: [4]u32 = [4]u32{ o0, o1, o2, o3 }
    var i = 0usize
    while i < 4usize {
        tag[i * 4usize] = u8(words[i] & 255u32)
        tag[i * 4usize + 1usize] = u8((words[i] >> 8u32) & 255u32)
        tag[i * 4usize + 2usize] = u8((words[i] >> 16u32) & 255u32)
        tag[i * 4usize + 3usize] = u8(words[i] >> 24u32)
        i += 1usize
    }
    ret tag
}

// RFC 8439 2.8: the one-time key is the first ChaCha20 block at counter 0; the data
// is encrypted from counter 1; the tag covers aad and ciphertext, each zero-padded to
// sixteen, then both lengths little-endian.
fn chacha_poly_tag(key: [32]u8, nonce: [12]u8, aad: []const u8, cipher: []const u8) -> [16]u8 {
    var stream = random.chacha20_init(key, nonce, 0u32)
    var one_time: [64]u8 = zero
    if random.chacha20_fill(&stream, one_time[0..]) != ok { ret zero }
    var p = poly_init(one_time[..32])
    poly_update_padded(&p, aad)
    poly_update_padded(&p, cipher)
    var lengths: [16]u8 = zero
    let aad_len = u64(aad.len)
    let cipher_len = u64(cipher.len)
    var i = 0usize
    while i < 8usize {
        lengths[i] = u8((aad_len >> u32(i * 8usize)) & 255u64)
        lengths[8usize + i] = u8((cipher_len >> u32(i * 8usize)) & 255u64)
        i += 1usize
    }
    poly_block(&p, lengths[0..], false)
    ret poly_tag(&p)
}

fn chacha_crypt(key: [32]u8, nonce: [12]u8, data: []u8) -> err {
    var stream = random.chacha20_init(key, nonce, 1u32)
    var at = 0usize
    while at < data.len {
        var block: [64]u8 = zero
        var take = data.len - at
        if take > 64usize { take = 64usize }
        let fill_error = random.chacha20_fill(&stream, block[..take])
        if fill_error != ok { ret fill_error }
        var i = 0usize
        while i < take {
            data[at + i] = data[at + i] ^ block[i]
            i += 1usize
        }
        at += take
    }
    ret ok
}

fn chacha20_poly1305_seal(dst: []u8, key: [32]u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err) {
    if dst.len < plain.len + 16usize { ret (0usize, TooSmall) }
    var at = 0usize
    while at < plain.len {
        dst[at] = plain[at]
        at += 1usize
    }
    let crypt_error = chacha_crypt(key, nonce, dst[..plain.len])
    if crypt_error != ok { ret (0usize, crypt_error) }
    let tag = chacha_poly_tag(key, nonce, aad, dst[..plain.len])
    at = 0usize
    while at < 16usize {
        dst[plain.len + at] = tag[at]
        at += 1usize
    }
    ret (plain.len + 16usize, ok)
}

fn chacha20_poly1305_open(dst: []u8, key: [32]u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err) {
    if sealed.len < 16usize { ret (0usize, Authentication) }
    let cipher_len = sealed.len - 16usize
    if dst.len < cipher_len { ret (0usize, TooSmall) }
    let tag = chacha_poly_tag(key, nonce, aad, sealed[..cipher_len])
    if !hash.equal_constant_time(tag[0..], sealed[cipher_len..]) { ret (0usize, Authentication) }
    var at = 0usize
    while at < cipher_len {
        dst[at] = sealed[at]
        at += 1usize
    }
    let crypt_error = chacha_crypt(key, nonce, dst[..cipher_len])
    if crypt_error != ok { ret (0usize, crypt_error) }
    ret (cipher_len, ok)
}


// --- The planned names (#603): AES-GCM dispatching on the key length,
// 16, 24 or 32 bytes (AES-128, AES-192, AES-256); anything else is `InvalidKey`.

fn aes_gcm_seal(dst: []u8, key: []const u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err) {
    if key.len != 16usize && key.len != 24usize && key.len != 32usize { ret (0usize, InvalidKey) }
    let (written, seal_error) = gcm_seal(dst, key, nonce, aad, plain)
    ret (written, seal_error)
}

fn aes_gcm_open(dst: []u8, key: []const u8, nonce: [12]u8, aad: []const u8, sealed: []const u8) -> (usize, err) {
    if key.len != 16usize && key.len != 24usize && key.len != 32usize { ret (0usize, InvalidKey) }
    let (written, open_error) = gcm_open(dst, key, nonce, aad, sealed)
    ret (written, open_error)
}
