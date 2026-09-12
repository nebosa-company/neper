// `e.crypto.mac`, `e.crypto.kdf` and `e.crypto.random`: HMAC against RFC 4231 cases 2
// and 6 with the streaming form and verification, HKDF against RFC 5869 cases 1 and 3
// plus the SHA-512 form and the length refusal, and ChaCha20 against RFC 8439's block
// and keystream with exhaustion at the last counter and bounded draws. The vectors are
// Python's (vectors.py beside this fixture). Every check has its own exit code.
use e.os
use e.mem
use e.crypto.mac as mac
use e.crypto.kdf as kdf
use e.crypto.random as random

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
    let hmac256_jefe: [32]u8 = [32]u8{ 91, 220, 193, 70, 191, 96, 117, 78, 106, 4, 36, 38, 8, 149, 117, 199, 90, 0, 63, 8, 157, 39, 57, 131, 157, 236, 88, 185, 100, 236, 56, 67 }
    let hmac512_jefe: [64]u8 = [64]u8{ 22, 75, 122, 123, 252, 248, 25, 226, 227, 149, 251, 231, 59, 86, 224, 163, 135, 189, 100, 34, 46, 131, 31, 214, 16, 39, 12, 215, 234, 37, 5, 84, 151, 88, 191, 117, 192, 90, 153, 74, 109, 3, 79, 101, 248, 240, 230, 253, 202, 234, 177, 163, 77, 74, 107, 75, 99, 110, 7, 10, 56, 188, 231, 55 }
    let hmac256_long: [32]u8 = [32]u8{ 96, 228, 49, 89, 30, 224, 182, 127, 13, 138, 38, 170, 203, 245, 183, 127, 142, 11, 198, 33, 55, 40, 197, 20, 5, 70, 4, 15, 14, 227, 127, 84 }
    let hmac512_long: [64]u8 = [64]u8{ 128, 178, 66, 99, 199, 193, 163, 235, 183, 20, 147, 193, 221, 123, 232, 180, 155, 70, 209, 244, 27, 74, 238, 193, 18, 27, 1, 55, 131, 248, 243, 82, 107, 86, 208, 55, 224, 95, 37, 152, 189, 15, 210, 33, 93, 106, 30, 82, 149, 230, 79, 115, 246, 63, 10, 236, 139, 145, 90, 152, 93, 120, 101, 152 }
    let hkdf_prk: [32]u8 = [32]u8{ 7, 119, 9, 54, 44, 46, 50, 223, 13, 220, 63, 13, 196, 123, 186, 99, 144, 182, 199, 59, 181, 15, 156, 49, 34, 236, 132, 74, 215, 194, 179, 229 }
    let hkdf_okm: [42]u8 = [42]u8{ 60, 178, 95, 37, 250, 172, 213, 122, 144, 67, 79, 100, 208, 54, 47, 42, 45, 45, 10, 144, 207, 26, 90, 76, 93, 176, 45, 86, 236, 196, 197, 191, 52, 0, 114, 8, 213, 184, 135, 24, 88, 101 }
    let hkdf_prk3: [32]u8 = [32]u8{ 25, 239, 36, 163, 44, 113, 123, 22, 127, 51, 169, 29, 111, 100, 139, 223, 150, 89, 103, 118, 175, 219, 99, 119, 172, 67, 76, 28, 41, 60, 203, 4 }
    let hkdf_okm3: [42]u8 = [42]u8{ 141, 164, 231, 117, 165, 99, 193, 143, 113, 95, 128, 42, 6, 60, 90, 49, 184, 161, 31, 92, 94, 225, 135, 158, 195, 69, 78, 95, 60, 115, 141, 45, 157, 32, 19, 149, 250, 164, 182, 26, 150, 200 }
    let hkdf512_okm: [82]u8 = [82]u8{ 131, 35, 144, 8, 108, 218, 113, 251, 71, 98, 91, 181, 206, 177, 104, 228, 200, 226, 106, 26, 22, 237, 52, 217, 252, 127, 233, 44, 20, 129, 87, 147, 56, 218, 54, 44, 184, 217, 249, 37, 215, 203, 204, 224, 223, 247, 9, 135, 105, 207, 21, 149, 152, 103, 213, 113, 193, 113, 84, 80, 203, 83, 1, 55, 190, 63, 182, 47, 60, 243, 43, 132, 254, 186, 143, 30, 177, 181, 99, 226, 13, 151 }
    let chacha_stream: [100]u8 = [100]u8{ 34, 79, 81, 243, 64, 27, 217, 225, 47, 222, 39, 111, 184, 99, 29, 237, 140, 19, 31, 130, 61, 44, 6, 226, 126, 79, 202, 236, 158, 243, 207, 120, 138, 59, 10, 163, 114, 96, 10, 146, 181, 121, 116, 205, 237, 43, 147, 52, 121, 76, 186, 64, 198, 62, 52, 205, 234, 33, 44, 76, 240, 125, 65, 183, 105, 166, 116, 159, 63, 99, 15, 65, 34, 202, 254, 40, 236, 77, 196, 126, 38, 212, 52, 109, 112, 185, 140, 115, 243, 233, 197, 58, 196, 12, 89, 69, 57, 139, 110, 218 }
    let chacha_block: [64]u8 = [64]u8{ 16, 241, 231, 228, 209, 59, 89, 21, 80, 15, 221, 31, 163, 32, 113, 196, 199, 209, 244, 199, 51, 192, 104, 3, 4, 34, 170, 154, 195, 212, 108, 78, 210, 130, 100, 70, 7, 159, 170, 9, 20, 194, 215, 5, 217, 139, 2, 162, 181, 18, 156, 209, 222, 22, 78, 185, 203, 208, 131, 232, 162, 80, 60, 78 }
    // RFC 4231 cases 2 and 6.
    let t1 = mac.hmac_sha256("Jefe", "what do ya want for nothing?")
    if !same(t1[0..], hmac256_jefe[0..]) { os.exit(1) }
    let t2 = mac.hmac_sha512("Jefe", "what do ya want for nothing?")
    if !same(t2[0..], hmac512_jefe[0..]) { os.exit(2) }
    var long_key: [131]u8 = zero
    var i = 0usize
    while i < 131usize {
        long_key[i] = 170u8
        i += 1usize
    }
    let t3 = mac.hmac_sha256(long_key[0..], "Test Using Larger Than Block-Size Key - Hash Key First")
    if !same(t3[0..], hmac256_long[0..]) { os.exit(3) }
    let t4 = mac.hmac_sha512(long_key[0..], "Test Using Larger Than Block-Size Key - Hash Key First")
    if !same(t4[0..], hmac512_long[0..]) { os.exit(4) }
    // Streaming in pieces, and verification.
    var s = mac.sha256_init("Jefe")
    mac.sha256_update(&s, "what do ya ")
    mac.sha256_update(&s, "want for nothing?")
    let streamed = mac.sha256_done(&s)
    if !same(streamed[0..], hmac256_jefe[0..]) { os.exit(5) }
    if !mac.verify_sha256("Jefe", "what do ya want for nothing?", t1) || mac.verify_sha256("Jefe", "what do ya want for nothing!", t1) { os.exit(6) }
    if !mac.verify_sha512("Jefe", "what do ya want for nothing?", t2) || mac.verify_sha512("jefe", "what do ya want for nothing?", t2) { os.exit(7) }
    // RFC 5869 cases 1 and 3.
    var ikm: [22]u8 = zero
    i = 0usize
    while i < 22usize {
        ikm[i] = 11u8
        i += 1usize
    }
    var salt: [13]u8 = zero
    i = 0usize
    while i < 13usize {
        salt[i] = u8(i)
        i += 1usize
    }
    var info: [10]u8 = zero
    i = 0usize
    while i < 10usize {
        info[i] = 240u8 + u8(i)
        i += 1usize
    }
    let prk = kdf.hkdf_sha256_extract(salt[0..], ikm[0..])
    if !same(prk[0..], hkdf_prk[0..]) { os.exit(8) }
    var okm: [42]u8 = zero
    if kdf.hkdf_sha256_expand(okm[0..], prk, info[0..]) != ok || !same(okm[0..], hkdf_okm[0..]) { os.exit(9) }
    let none: [0]u8 = zero
    let prk3 = kdf.hkdf_sha256_extract(none[0..], ikm[0..])
    if !same(prk3[0..], hkdf_prk3[0..]) { os.exit(10) }
    var okm3: [42]u8 = zero
    if kdf.hkdf_sha256_expand(okm3[0..], prk3, none[0..]) != ok || !same(okm3[0..], hkdf_okm3[0..]) { os.exit(11) }
    let prk512 = kdf.hkdf_sha512_extract(salt[0..], ikm[0..])
    var okm512: [82]u8 = zero
    if kdf.hkdf_sha512_expand(okm512[0..], prk512, info[0..]) != ok || !same(okm512[0..], hkdf512_okm[0..]) { os.exit(12) }
    let (too_long, too_long_error) = mem.alloc[u8](a, 255usize * 32usize + 1usize)
    if too_long_error != ok { os.exit(13) }
    if kdf.hkdf_sha256_expand(too_long, prk, info[0..]) != kdf.TooLarge { os.exit(14) }
    // ChaCha20: RFC 8439 2.3.2 block and 2.4.2 keystream, read in odd pieces.
    var key: [32]u8 = zero
    i = 0usize
    while i < 32usize {
        key[i] = u8(i)
        i += 1usize
    }
    var nonce2: [12]u8 = zero
    nonce2[3] = 9u8
    nonce2[7] = 74u8
    var r = random.chacha20_init(key, nonce2, 1u32)
    var one_block: [64]u8 = zero
    if random.chacha20_fill(&r, one_block[0..]) != ok || !same(one_block[0..], chacha_block[0..]) { os.exit(15) }
    var nonce: [12]u8 = zero
    nonce[7] = 74u8
    var r2 = random.chacha20_init(key, nonce, 1u32)
    var stream: [100]u8 = zero
    if random.chacha20_fill(&r2, stream[..7]) != ok || random.chacha20_fill(&r2, stream[7..64]) != ok || random.chacha20_fill(&r2, stream[64..]) != ok { os.exit(16) }
    if !same(stream[0..], chacha_stream[0..]) { os.exit(17) }
    // Exhaustion at the last counter value, and bounded draws.
    var last = random.chacha20_init(key, nonce, 4294967295u32)
    var tail: [64]u8 = zero
    if random.chacha20_fill(&last, tail[0..]) != ok { os.exit(18) }
    var more: [1]u8 = zero
    if random.chacha20_fill(&last, more[0..]) != random.Exhausted { os.exit(19) }
    var draws = random.chacha20_init(key, nonce, 0u32)
    let (z, z_error) = random.chacha20_bounded(&draws, 0u64)
    if z_error != ok || z != 0u64 { os.exit(20) }
    var n = 0usize
    while n < 200usize {
        let (v, v_error) = random.chacha20_bounded(&draws, 6u64)
        if v_error != ok || v >= 6u64 { os.exit(21) }
        n += 1usize
    }
    let (w, w_error) = random.chacha20_next_u64(&draws)
    if w_error != ok || w == 0u64 { os.exit(22) }
    os.exit(0)
    ret ok
}
