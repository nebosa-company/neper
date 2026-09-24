// Authenticated encryption: AES-GCM (NIST SP 800-38D) at both key sizes and
// ChaCha20-Poly1305 (RFC 8439), sealed as ciphertext followed by the sixteen-byte tag.
// `open` verifies the tag in constant time before it writes a byte of plaintext.
//
// AES is the straightforward byte-oriented cipher with an algebraic, constant-control-
// flow S-box and the key schedule computed per call; GHASH is the bit-by-bit multiply
// in GF(2^128) over two limbs;
// Poly1305 is five 26-bit limbs with 64-bit products, the way the reference does it.
// It deliberately has no secret-indexed lookup tables. A bitsliced AES is the speed
// upgrade if this algebraic form is ever measured as a bottleneck.

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

// --- GHASH over GF(2^128), the block as (high, low) big-endian.

type Block128 = struct { high: u64, low: u64 }

fn load_block(bytes: []const u8, at: usize, count: usize) -> Block128 {
    var b: Block128 = zero
    var i = 0usize
    while i < count && i < 16usize {
        let byte = u64(bytes[at + i])
        if i < 8usize {
            b.high = b.high | (byte << u32((7usize - i) * 8usize))
        } else {
            b.low = b.low | (byte << u32((15usize - i) * 8usize))
        }
        i += 1usize
    }
    ret b
}

fn store_block(b: Block128, out: []u8) {
    var i = 0usize
    while i < 8usize {
        out[i] = u8((b.high >> u32((7usize - i) * 8usize)) & 255u64)
        out[8usize + i] = u8((b.low >> u32((7usize - i) * 8usize)) & 255u64)
        i += 1usize
    }
}

// x * y in GF(2^128) with GCM's bit order: the reduction polynomial's constant is
// 0xE1 at the top of the high limb.
fn gf_multiply(x: Block128, y: Block128) -> Block128 {
    var z: Block128 = zero
    var v = y
    var bit = 0usize
    while bit < 128usize {
        var x_bit = 0u64
        if bit < 64usize {
            x_bit = (x.high >> u32(63usize - bit)) & 1u64
        } else {
            x_bit = (x.low >> u32(127usize - bit)) & 1u64
        }
        let x_mask = 0u64 -% x_bit
        z.high = z.high ^ (v.high & x_mask)
        z.low = z.low ^ (v.low & x_mask)
        let carry = v.low & 1u64
        v.low = (v.low >> 1u32) | (v.high << 63u32)
        v.high = (v.high >> 1u32) ^ (16212958658533785600u64 & (0u64 -% carry))
        bit += 1usize
    }
    ret z
}

fn ghash_update(acc: Block128, h: Block128, bytes: []const u8) -> Block128 {
    var y = acc
    var at = 0usize
    while at < bytes.len {
        var take = bytes.len - at
        if take > 16usize { take = 16usize }
        let block = load_block(bytes, at, take)
        y.high = y.high ^ block.high
        y.low = y.low ^ block.low
        y = gf_multiply(y, h)
        at += 16usize
    }
    ret y
}

fn gcm_tag(k: *const AesKey, nonce: [12]u8, aad: []const u8, cipher: []const u8) -> [16]u8 {
    var zero_block: [16]u8 = zero
    aes_encrypt_block(k, zero_block[0..])
    let h = load_block(zero_block[0..], 0usize, 16usize)
    var acc: Block128 = zero
    acc = ghash_update(acc, h, aad)
    acc = ghash_update(acc, h, cipher)
    var lengths: [16]u8 = zero
    let aad_bits = u64(aad.len) * 8u64
    let cipher_bits = u64(cipher.len) * 8u64
    var i = 0usize
    while i < 8usize {
        lengths[i] = u8((aad_bits >> u32((7usize - i) * 8usize)) & 255u64)
        lengths[8usize + i] = u8((cipher_bits >> u32((7usize - i) * 8usize)) & 255u64)
        i += 1usize
    }
    acc = ghash_update(acc, h, lengths[0..])
    // E(K, J0) with J0 = nonce || 0x00000001.
    var j0: [16]u8 = zero
    i = 0usize
    while i < 12usize {
        j0[i] = nonce[i]
        i += 1usize
    }
    j0[15] = 1u8
    aes_encrypt_block(k, j0[0..])
    var tag: [16]u8 = zero
    store_block(acc, tag[0..])
    i = 0usize
    while i < 16usize {
        tag[i] = tag[i] ^ j0[i]
        i += 1usize
    }
    ret tag
}

// CTR mode from counter 2, in place over `data`.
fn gcm_crypt(k: *const AesKey, nonce: [12]u8, data: []u8) {
    var counter = 2u32
    var at = 0usize
    while at < data.len {
        var block: [16]u8 = zero
        var i = 0usize
        while i < 12usize {
            block[i] = nonce[i]
            i += 1usize
        }
        block[12] = u8(counter >> 24u32)
        block[13] = u8((counter >> 16u32) & 255u32)
        block[14] = u8((counter >> 8u32) & 255u32)
        block[15] = u8(counter & 255u32)
        aes_encrypt_block(k, block[0..])
        i = 0usize
        while i < 16usize && at + i < data.len {
            data[at + i] = data[at + i] ^ block[i]
            i += 1usize
        }
        counter += 1u32
        at += 16usize
    }
}

fn gcm_seal(dst: []u8, key: []const u8, nonce: [12]u8, aad: []const u8, plain: []const u8) -> (usize, err) {
    if dst.len < plain.len + 16usize { ret (0usize, TooSmall) }
    let k = expand_key(key)
    var at = 0usize
    while at < plain.len {
        dst[at] = plain[at]
        at += 1usize
    }
    gcm_crypt(&k, nonce, dst[..plain.len])
    let tag = gcm_tag(&k, nonce, aad, dst[..plain.len])
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
    let k = expand_key(key)
    let tag = gcm_tag(&k, nonce, aad, sealed[..cipher_len])
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
