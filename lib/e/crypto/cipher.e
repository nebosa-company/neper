// Unauthenticated block and stream ciphers: the AES block (FIPS 197) in both
// directions at all three key sizes, ECB/CBC/CTR modes (NIST SP 800-38A) with PKCS#7
// padding helpers, and ChaCha20 (RFC 8439) as a block function, an in-place xor, and
// HChaCha20 for XChaCha nonce extension. The key schedule, S-box and forward block
// come from `e.crypto.aead`; only the inverse cipher and the modes live here.
//
// None of this authenticates: pair with `e.crypto.mac` or use `e.crypto.aead`.
// ponytail: byte-oriented AES, not constant-time against S-box cache timing; a
// bitsliced or table-driven cipher is the upgrade.

use e.crypto.aead as aead
use e.crypto.random as random

error Invalid
error TooSmall

type AesKey = aead.AesKey

fn inverse_sbox(index: u8) -> u8 {
    let table: [256]u8 = [256]u8{
        82, 9, 106, 213, 48, 54, 165, 56, 191, 64, 163, 158, 129, 243, 215, 251,
        124, 227, 57, 130, 155, 47, 255, 135, 52, 142, 67, 68, 196, 222, 233, 203,
        84, 123, 148, 50, 166, 194, 35, 61, 238, 76, 149, 11, 66, 250, 195, 78,
        8, 46, 161, 102, 40, 217, 36, 178, 118, 91, 162, 73, 109, 139, 209, 37,
        114, 248, 246, 100, 134, 104, 152, 22, 212, 164, 92, 204, 93, 101, 182, 146,
        108, 112, 72, 80, 253, 237, 185, 218, 94, 21, 70, 87, 167, 141, 157, 132,
        144, 216, 171, 0, 140, 188, 211, 10, 247, 228, 88, 5, 184, 179, 69, 6,
        208, 44, 30, 143, 202, 63, 15, 2, 193, 175, 189, 3, 1, 19, 138, 107,
        58, 145, 17, 65, 79, 103, 220, 234, 151, 242, 207, 206, 240, 180, 230, 115,
        150, 172, 116, 34, 231, 173, 53, 133, 226, 249, 55, 232, 28, 117, 223, 110,
        71, 241, 26, 113, 29, 41, 197, 137, 111, 183, 98, 14, 170, 24, 190, 27,
        252, 86, 62, 75, 198, 210, 121, 32, 154, 219, 192, 254, 120, 205, 90, 244,
        31, 221, 168, 51, 136, 7, 199, 49, 177, 18, 16, 89, 39, 128, 236, 95,
        96, 81, 127, 169, 25, 181, 74, 13, 45, 229, 122, 159, 147, 201, 156, 239,
        160, 224, 59, 77, 174, 42, 245, 176, 200, 235, 187, 60, 131, 83, 153, 97,
        23, 43, 4, 126, 186, 119, 214, 38, 225, 105, 20, 99, 85, 33, 12, 125 }
    ret table[usize(index)]
}

// a * b in GF(2^8) with the AES polynomial, by shift-and-add.
fn gf_mul(a: u8, b: u8) -> u8 {
    var product = 0u8
    var x = a
    var y = b
    while y != 0u8 {
        if (y & 1u8) != 0u8 { product = product ^ x }
        x = aead.xtime(x)
        y = y >> 1u8
    }
    ret product
}

// --- AES block

// The expanded key for a 16-, 24- or 32-byte key; anything else is `Invalid`.
fn aes_key(key: []const u8) -> (AesKey, err) {
    if key.len != 16usize && key.len != 24usize && key.len != 32usize {
        var none: AesKey = zero
        ret (none, Invalid)
    }
    ret (aead.expand_key(key), ok)
}

// One block encrypted in place.
fn aes_block(k: *const AesKey, block: []u8) {
    aead.aes_encrypt_block(k, block)
}

// One block decrypted in place: the inverse cipher of FIPS 197 5.3.
fn aes_block_decrypt(k: *const AesKey, block: []u8) {
    var state: [16]u8 = zero
    var i = 0usize
    while i < 16usize {
        state[i] = block[i]
        i += 1usize
    }
    aead.add_round_key(state[0..], k, k.rounds)
    var round = k.rounds
    while round > 0usize {
        round -= 1usize
        // InvShiftRows: row r shifts right by r; column-major state.
        var shifted: [16]u8 = zero
        var column = 0usize
        while column < 4usize {
            var row = 0usize
            while row < 4usize {
                shifted[((column + row) % 4usize) * 4usize + row] = state[column * 4usize + row]
                row += 1usize
            }
            column += 1usize
        }
        // InvSubBytes
        i = 0usize
        while i < 16usize {
            state[i] = inverse_sbox(shifted[i])
            i += 1usize
        }
        aead.add_round_key(state[0..], k, round)
        // InvMixColumns, except before the first round key.
        if round != 0usize {
            column = 0usize
            while column < 4usize {
                let a0 = state[column * 4usize]
                let a1 = state[column * 4usize + 1usize]
                let a2 = state[column * 4usize + 2usize]
                let a3 = state[column * 4usize + 3usize]
                state[column * 4usize] = gf_mul(a0, 14u8) ^ gf_mul(a1, 11u8) ^ gf_mul(a2, 13u8) ^ gf_mul(a3, 9u8)
                state[column * 4usize + 1usize] = gf_mul(a0, 9u8) ^ gf_mul(a1, 14u8) ^ gf_mul(a2, 11u8) ^ gf_mul(a3, 13u8)
                state[column * 4usize + 2usize] = gf_mul(a0, 13u8) ^ gf_mul(a1, 9u8) ^ gf_mul(a2, 14u8) ^ gf_mul(a3, 11u8)
                state[column * 4usize + 3usize] = gf_mul(a0, 11u8) ^ gf_mul(a1, 13u8) ^ gf_mul(a2, 9u8) ^ gf_mul(a3, 14u8)
                column += 1usize
            }
        }
    }
    i = 0usize
    while i < 16usize {
        block[i] = state[i]
        i += 1usize
    }
}

// --- Modes

fn ecb_encrypt(k: *const AesKey, data: []u8) -> err {
    if data.len % 16usize != 0usize { ret Invalid }
    var off = 0usize
    while off < data.len {
        aead.aes_encrypt_block(k, data[off..off + 16usize])
        off += 16usize
    }
    ret ok
}

fn ecb_decrypt(k: *const AesKey, data: []u8) -> err {
    if data.len % 16usize != 0usize { ret Invalid }
    var off = 0usize
    while off < data.len {
        aes_block_decrypt(k, data[off..off + 16usize])
        off += 16usize
    }
    ret ok
}

// CBC over whole blocks, in place; pad with `pad_pkcs7` first when the length is not
// a multiple of sixteen.
fn cbc_encrypt(k: *const AesKey, iv: [16]u8, data: []u8) -> err {
    if data.len % 16usize != 0usize { ret Invalid }
    var previous = iv
    var off = 0usize
    while off < data.len {
        var i = 0usize
        while i < 16usize {
            data[off + i] = data[off + i] ^ previous[i]
            i += 1usize
        }
        aead.aes_encrypt_block(k, data[off..off + 16usize])
        i = 0usize
        while i < 16usize {
            previous[i] = data[off + i]
            i += 1usize
        }
        off += 16usize
    }
    ret ok
}

fn cbc_decrypt(k: *const AesKey, iv: [16]u8, data: []u8) -> err {
    if data.len % 16usize != 0usize { ret Invalid }
    var previous = iv
    var off = 0usize
    while off < data.len {
        var cipher_block: [16]u8 = zero
        var i = 0usize
        while i < 16usize {
            cipher_block[i] = data[off + i]
            i += 1usize
        }
        aes_block_decrypt(k, data[off..off + 16usize])
        i = 0usize
        while i < 16usize {
            data[off + i] = data[off + i] ^ previous[i]
            i += 1usize
        }
        previous = cipher_block
        off += 16usize
    }
    ret ok
}

// CTR from block `block_index` of the stream whose first counter block is `iv`: the
// whole sixteen bytes are one big-endian counter. Encrypt and decrypt are the same xor.
fn ctr_at(k: *const AesKey, iv: [16]u8, block_index: u64, data: []u8) {
    var counter = iv
    // counter = iv + block_index, big-endian with carry through all sixteen bytes.
    var carry = block_index
    var i = 16usize
    while i > 0usize && carry != 0u64 {
        i -= 1usize
        let sum = u64(counter[i]) + (carry & 255u64)
        counter[i] = u8(sum & 255u64)
        carry = (carry >> 8u32) + (sum >> 8u32)
    }
    var off = 0usize
    while off < data.len {
        var keystream = counter
        aead.aes_encrypt_block(k, keystream[0..])
        i = 0usize
        while i < 16usize && off + i < data.len {
            data[off + i] = data[off + i] ^ keystream[i]
            i += 1usize
        }
        // Increment the 128-bit counter.
        i = 16usize
        while i > 0usize {
            i -= 1usize
            counter[i] = counter[i] +% 1u8
            if counter[i] != 0u8 { i = 0usize }
        }
        off += 16usize
    }
}

fn ctr(k: *const AesKey, iv: [16]u8, data: []u8) {
    ctr_at(k, iv, 0u64, data)
}

// --- PKCS#7

// `src` copied into `dst` and padded to the next multiple of sixteen (always at least
// one byte); the padded length, or `TooSmall`.
fn pad_pkcs7(dst: []u8, src: []const u8) -> (usize, err) {
    let pad = 16usize - src.len % 16usize
    let total = src.len + pad
    if dst.len < total { ret (0usize, TooSmall) }
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
    while i < total {
        dst[i] = u8(pad)
        i += 1usize
    }
    ret (total, ok)
}

// The unpadded length of `data`, or `Invalid` when the padding is malformed.
fn unpad_pkcs7(data: []const u8) -> (usize, err) {
    if data.len == 0usize || data.len % 16usize != 0usize { ret (0usize, Invalid) }
    let pad = usize(data[data.len - 1usize])
    if pad == 0usize || pad > 16usize { ret (0usize, Invalid) }
    var i = data.len - pad
    while i < data.len {
        if usize(data[i]) != pad { ret (0usize, Invalid) }
        i += 1usize
    }
    ret (data.len - pad, ok)
}

// --- ChaCha20

fn chacha_state(key: [32]u8, counter: u32, nonce: [12]u8) -> [16]u32 {
    var state: [16]u32 = zero
    state[0] = 1634760805u32
    state[1] = 857760878u32
    state[2] = 2036477234u32
    state[3] = 1797285236u32
    var i = 0usize
    while i < 8usize {
        state[4usize + i] = random.load_le32(key[0..], i * 4usize)
        i += 1usize
    }
    state[12] = counter
    state[13] = random.load_le32(nonce[0..], 0usize)
    state[14] = random.load_le32(nonce[0..], 4usize)
    state[15] = random.load_le32(nonce[0..], 8usize)
    ret state
}

fn chacha_rounds(state: []u32) {
    var round = 0usize
    while round < 10usize {
        random.quarter(state, 0usize, 4usize, 8usize, 12usize)
        random.quarter(state, 1usize, 5usize, 9usize, 13usize)
        random.quarter(state, 2usize, 6usize, 10usize, 14usize)
        random.quarter(state, 3usize, 7usize, 11usize, 15usize)
        random.quarter(state, 0usize, 5usize, 10usize, 15usize)
        random.quarter(state, 1usize, 6usize, 11usize, 12usize)
        random.quarter(state, 2usize, 7usize, 8usize, 13usize)
        random.quarter(state, 3usize, 4usize, 9usize, 14usize)
        round += 1usize
    }
}

fn store_le32(out: []u8, off: usize, word: u32) {
    out[off] = u8(word & 255u32)
    out[off + 1usize] = u8((word >> 8u32) & 255u32)
    out[off + 2usize] = u8((word >> 16u32) & 255u32)
    out[off + 3usize] = u8(word >> 24u32)
}

// The 64-byte keystream block for (key, counter, nonce) into `out` (RFC 8439 2.3).
fn chacha20_block(key: [32]u8, counter: u32, nonce: [12]u8, out: []u8) -> err {
    if out.len < 64usize { ret TooSmall }
    let initial = chacha_state(key, counter, nonce)
    var working = initial
    chacha_rounds(working[0..])
    var i = 0usize
    while i < 16usize {
        store_le32(out, i * 4usize, working[i] +% initial[i])
        i += 1usize
    }
    ret ok
}

// `data` xored in place with the keystream from `counter`; the counter wraps at 2^32
// as the RFC leaves it to the caller not to exceed 256 GiB per nonce.
fn chacha20(key: [32]u8, counter: u32, nonce: [12]u8, data: []u8) {
    var block_counter = counter
    var off = 0usize
    while off < data.len {
        var block: [64]u8 = zero
        let _ = chacha20_block(key, block_counter, nonce, block[0..])
        var i = 0usize
        while i < 64usize && off + i < data.len {
            data[off + i] = data[off + i] ^ block[i]
            i += 1usize
        }
        block_counter = block_counter +% 1u32
        off += 64usize
    }
}

// HChaCha20: the 20 rounds over key and a 16-byte nonce without the final addition;
// words 0-3 and 12-15 are the derived 32-byte subkey for XChaCha20.
fn hchacha20(key: [32]u8, nonce: [16]u8) -> [32]u8 {
    var tail: [12]u8 = zero
    var i = 0usize
    while i < 12usize {
        tail[i] = nonce[4usize + i]
        i += 1usize
    }
    var state = chacha_state(key, random.load_le32(nonce[0..], 0usize), tail)
    chacha_rounds(state[0..])
    var out: [32]u8 = zero
    i = 0usize
    while i < 4usize {
        store_le32(out[0..], i * 4usize, state[i])
        store_le32(out[0..], 16usize + i * 4usize, state[12usize + i])
        i += 1usize
    }
    ret out
}


// The planned name (#604): CBC in place, one call for both directions.
fn cbc(k: *const AesKey, iv: [16]u8, data: []u8, encrypt: bool) -> err {
    if encrypt { ret cbc_encrypt(k, iv, data) }
    ret cbc_decrypt(k, iv, data)
}
