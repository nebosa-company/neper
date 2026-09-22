// `e.crypto.kdf`'s password hashes and `e.crypto.hash.blake2b`: PBKDF2-HMAC-SHA-256 and
// -SHA-512 against hashlib, scrypt against RFC 7914's first two vectors, bcrypt against
// the bcrypt package (a 72-byte password, the empty password, the `$2b$` text and
// verification), Argon2id against RFC 9106's test vector (with secret and associated
// data) and against `cryptography` for the plain, two-lane and 100-byte-tag cases, and
// BLAKE2b against hashlib plain, keyed and streamed. Every expected value is emitted by
// gen.py in the scratch directory. Each check has its own exit code.
use e.io
use e.os
use e.mem
use e.crypto.hash as hash
use e.crypto.kdf as kdf

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
    let pbkdf2_a: [20]u8 = [20]u8{ 18, 15, 182, 207, 252, 248, 179, 44, 67, 231, 34, 82, 86, 196, 248, 55, 168, 101, 72, 201 }
    let pbkdf2_b: [32]u8 = [32]u8{ 197, 228, 120, 213, 146, 136, 200, 65, 170, 83, 13, 182, 132, 92, 76, 141, 150, 40, 147, 160, 1, 206, 78, 17, 164, 150, 56, 115, 170, 152, 19, 74 }
    let pbkdf2_c: [70]u8 = [70]u8{ 14, 40, 243, 239, 168, 2, 162, 240, 205, 59, 74, 206, 94, 61, 154, 250, 219, 124, 45, 204, 197, 239, 16, 238, 219, 138, 101, 100, 223, 176, 201, 166, 59, 111, 70, 177, 225, 80, 88, 123, 159, 231, 135, 92, 250, 249, 153, 208, 11, 69, 75, 183, 215, 66, 149, 198, 13, 241, 187, 229, 248, 243, 109, 161, 136, 39, 29, 178, 33, 16 }
    let scrypt_a: [64]u8 = [64]u8{ 119, 214, 87, 98, 56, 101, 123, 32, 59, 25, 202, 66, 193, 138, 4, 151, 241, 107, 72, 68, 227, 7, 74, 232, 223, 223, 250, 63, 237, 226, 20, 66, 252, 208, 6, 157, 237, 9, 72, 248, 50, 106, 117, 58, 15, 200, 31, 23, 232, 211, 224, 251, 46, 13, 54, 40, 207, 53, 226, 12, 56, 209, 137, 6 }
    let scrypt_b: [64]u8 = [64]u8{ 253, 186, 190, 28, 157, 52, 114, 0, 120, 86, 231, 25, 13, 1, 233, 254, 124, 106, 215, 203, 200, 35, 120, 48, 231, 115, 118, 99, 75, 55, 49, 98, 46, 175, 48, 217, 46, 34, 163, 136, 111, 241, 9, 39, 157, 152, 48, 218, 199, 39, 175, 185, 74, 131, 238, 109, 131, 96, 203, 223, 162, 204, 6, 64 }
    let bcrypt_a: [60]u8 = [60]u8{ 36, 50, 98, 36, 48, 54, 36, 46, 46, 67, 65, 46, 117, 79, 68, 47, 101, 97, 71, 65, 79, 109, 74, 66, 46, 121, 77, 66, 117, 54, 74, 114, 120, 67, 98, 113, 101, 53, 65, 97, 112, 47, 120, 103, 87, 69, 68, 107, 57, 55, 78, 102, 69, 65, 88, 68, 110, 57, 82, 105 }
    let bcrypt_long: [60]u8 = [60]u8{ 36, 50, 98, 36, 48, 52, 36, 65, 120, 47, 84, 99, 110, 57, 67, 52, 79, 50, 120, 85, 70, 48, 103, 118, 56, 117, 80, 76, 101, 80, 107, 79, 46, 71, 55, 84, 78, 70, 112, 84, 74, 101, 100, 83, 100, 114, 110, 109, 110, 118, 50, 121, 77, 98, 98, 104, 120, 69, 51, 71 }
    let bcrypt_empty: [60]u8 = [60]u8{ 36, 50, 98, 36, 48, 52, 36, 65, 120, 47, 84, 99, 110, 57, 67, 52, 79, 50, 120, 85, 70, 48, 103, 118, 56, 117, 80, 76, 101, 81, 70, 114, 51, 100, 101, 103, 103, 83, 101, 78, 55, 47, 85, 107, 108, 82, 122, 90, 86, 74, 89, 98, 114, 112, 52, 56, 110, 46, 118, 121 }
    let salt4: [16]u8 = [16]u8{ 11, 48, 85, 122, 159, 196, 233, 14, 51, 88, 125, 162, 199, 236, 17, 54 }
    let argon_rfc: [32]u8 = [32]u8{ 13, 100, 13, 245, 141, 120, 118, 108, 8, 192, 55, 163, 74, 139, 83, 201, 208, 30, 240, 69, 45, 117, 182, 94, 181, 37, 32, 233, 107, 1, 230, 89 }
    let argon_plain: [32]u8 = [32]u8{ 3, 170, 185, 101, 193, 32, 1, 201, 215, 208, 210, 222, 51, 25, 44, 4, 148, 182, 132, 187, 20, 129, 150, 215, 60, 29, 241, 172, 175, 109, 12, 46 }
    let argon_long: [100]u8 = [100]u8{ 102, 128, 181, 90, 151, 18, 98, 39, 163, 56, 213, 108, 153, 164, 211, 7, 103, 172, 148, 27, 145, 233, 128, 53, 234, 76, 63, 231, 176, 234, 193, 187, 252, 51, 120, 135, 123, 237, 157, 58, 107, 139, 167, 56, 143, 87, 234, 53, 225, 90, 95, 9, 79, 90, 62, 166, 78, 69, 33, 151, 20, 82, 180, 143, 178, 184, 113, 56, 87, 146, 38, 164, 167, 87, 151, 6, 184, 166, 113, 174, 205, 193, 6, 238, 96, 135, 141, 14, 148, 20, 72, 75, 239, 129, 252, 59, 61, 15, 34, 152 }
    let argon_two: [16]u8 = [16]u8{ 135, 212, 145, 88, 14, 141, 110, 44, 61, 126, 179, 12, 204, 20, 178, 249 }
    let blake_a: [64]u8 = [64]u8{ 186, 128, 165, 63, 152, 28, 77, 13, 106, 39, 151, 182, 159, 18, 246, 233, 76, 33, 47, 20, 104, 90, 196, 183, 75, 18, 187, 111, 219, 255, 162, 209, 125, 135, 197, 57, 42, 171, 121, 45, 194, 82, 213, 222, 69, 51, 204, 149, 24, 211, 138, 168, 219, 241, 146, 90, 185, 35, 134, 237, 212, 0, 153, 35 }
    let blake_b: [20]u8 = [20]u8{ 109, 199, 188, 16, 149, 134, 201, 13, 136, 213, 1, 220, 116, 32, 118, 128, 222, 224, 181, 111 }
    let blake_c: [64]u8 = [64]u8{ 228, 53, 228, 82, 190, 216, 38, 0, 251, 166, 202, 20, 197, 79, 0, 218, 228, 168, 250, 169, 53, 6, 81, 139, 230, 96, 29, 238, 138, 183, 15, 227, 91, 30, 31, 177, 16, 220, 147, 129, 53, 34, 251, 96, 209, 115, 119, 124, 106, 89, 3, 42, 234, 12, 242, 31, 18, 69, 206, 172, 60, 43, 231, 204 }
    // PBKDF2.
    var d20: [20]u8 = zero
    if kdf.pbkdf2_sha256("password", "salt", 1u32, d20[0..]) != ok || !same(d20[0..], pbkdf2_a[0..]) { os.exit(1i32) }
    var d32: [32]u8 = zero
    if kdf.pbkdf2_sha256("password", "salt", 4096u32, d32[0..]) != ok || !same(d32[0..], pbkdf2_b[0..]) { os.exit(2i32) }
    var d70: [70]u8 = zero
    if kdf.pbkdf2_sha512("passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 1000u32, d70[0..]) != ok || !same(d70[0..], pbkdf2_c[0..]) { os.exit(3i32) }
    var e20: [20]u8 = zero
    var e70: [70]u8 = zero
    if kdf.pbkdf2(.Sha256, "password", "salt", 1u32, e20[0..]) != ok || !same(e20[0..], pbkdf2_a[0..]) { os.exit(4i32) }
    if kdf.pbkdf2(.Sha512, "passwordPASSWORDpassword", "saltSALTsaltSALTsaltSALTsaltSALTsalt", 1000u32, e70[0..]) != ok || !same(e70[0..], pbkdf2_c[0..]) { os.exit(5i32) }
    if kdf.pbkdf2_sha256("password", "salt", 0u32, d20[0..]) != kdf.Invalid { os.exit(6i32) }
    // scrypt: RFC 7914 section 12 vectors 1 and 2.
    let (scratch, scratch_error) = mem.alloc[u8](a, kdf.scrypt_scratch_required(1024usize, 8usize, 16usize))
    if scratch_error != ok { os.exit(7i32) }
    var s64: [64]u8 = zero
    if kdf.scrypt("", "", 16usize, 1usize, 1usize, s64[0..], scratch) != ok || !same(s64[0..], scrypt_a[0..]) { os.exit(8i32) }
    if kdf.scrypt("password", "NaCl", 1024usize, 8usize, 16usize, s64[0..], scratch) != ok || !same(s64[0..], scrypt_b[0..]) { os.exit(9i32) }
    if kdf.scrypt("password", "NaCl", 1024usize, 8usize, 16usize, s64[0..], scratch[..1000usize]) != kdf.TooSmall { os.exit(10i32) }
    if kdf.scrypt("password", "NaCl", 3usize, 8usize, 1usize, s64[0..], scratch) != kdf.Invalid { os.exit(11i32) }
    // bcrypt.
    var salt6: [16]u8 = zero
    var i = 0usize
    while i < 16usize {
        salt6[i] = u8(i)
        i += 1usize
    }
    let (text6, text6_error) = kdf.bcrypt_hash_text("password", salt6, 6u32)
    if text6_error != ok || !same(text6[0..], bcrypt_a[0..]) { os.exit(12i32) }
    if !kdf.bcrypt_verify("password", bcrypt_a[0..]) || kdf.bcrypt_verify("passwore", bcrypt_a[0..]) { os.exit(13i32) }
    var salt_b: [16]u8 = zero
    i = 0usize
    while i < 16usize {
        salt_b[i] = salt4[i]
        i += 1usize
    }
    var long_password: [75]u8 = zero
    i = 0usize
    while i < 64usize {
        long_password[i] = 120u8
        i += 1usize
    }
    let tail = "abcdefghZZZ"
    i = 0usize
    while i < 11usize {
        long_password[64usize + i] = tail[i]
        i += 1usize
    }
    let (text72, text72_error) = kdf.bcrypt_hash_text(long_password[..72], salt_b, 4u32)
    if text72_error != ok || !same(text72[0..], bcrypt_long[0..]) { os.exit(14i32) }
    let (text75, text75_error) = kdf.bcrypt_hash_text(long_password[0..], salt_b, 4u32)
    if text75_error != ok || !same(text75[0..], bcrypt_long[0..]) { os.exit(15i32) }
    let (text_empty, text_empty_error) = kdf.bcrypt_hash_text("", salt_b, 4u32)
    if text_empty_error != ok || !same(text_empty[0..], bcrypt_empty[0..]) { os.exit(16i32) }
    let (raw3, raw3_error) = kdf.bcrypt("password", salt6, 3u32)
    if raw3_error != kdf.Invalid || kdf.bcrypt_verify("password", bcrypt_a[..59]) || kdf.bcrypt_verify("", bcrypt_a[0..]) { os.exit(17i32) }
    // Argon2id: RFC 9106 section 5.3, then cryptography's answers.
    let (memory, memory_error) = mem.alloc[u8](a, kdf.argon2_memory_required(32u32))
    if memory_error != ok { os.exit(18i32) }
    var password: [32]u8 = zero
    var salt: [16]u8 = zero
    var secret: [8]u8 = zero
    var ad: [12]u8 = zero
    i = 0usize
    while i < 32usize {
        password[i] = 1u8
        if i < 16usize { salt[i] = 2u8 }
        if i < 8usize { secret[i] = 3u8 }
        if i < 12usize { ad[i] = 4u8 }
        i += 1usize
    }
    var tag: [32]u8 = zero
    if kdf.argon2id_keyed(password[0..], salt[0..], secret[0..], ad[0..], 3u32, 32u32, 4u32, tag[0..], memory) != ok || !same(tag[0..], argon_rfc[0..]) { os.exit(19i32) }
    if kdf.argon2id(password[0..], salt[0..], 3u32, 32u32, 4u32, tag[0..], memory) != ok || !same(tag[0..], argon_plain[0..]) { os.exit(20i32) }
    var tag100: [100]u8 = zero
    if kdf.argon2id("pw", "somesalt", 1u32, 8u32, 1u32, tag100[0..], memory) != ok || !same(tag100[0..], argon_long[0..]) { os.exit(21i32) }
    var tag16: [16]u8 = zero
    if kdf.argon2id("password", "saltsalt", 2u32, 16u32, 2u32, tag16[0..], memory) != ok || !same(tag16[0..], argon_two[0..]) { os.exit(22i32) }
    if kdf.argon2id("password", "saltsalt", 2u32, 16u32, 2u32, tag16[0..], memory[..10000usize]) != kdf.TooSmall { os.exit(23i32) }
    if kdf.argon2id("password", "saltsalt", 0u32, 16u32, 2u32, tag16[0..], memory) != kdf.Invalid { os.exit(24i32) }
    // BLAKE2b.
    let b_abc = hash.blake2b("abc")
    if !same(b_abc[0..], blake_a[0..]) { os.exit(25i32) }
    var keyed = hash.blake2b_init(20usize, "key")
    hash.blake2b_update(&keyed, "The quick brown fox jumps over the lazy dog")
    let b_fox = hash.blake2b_done(&keyed)
    if !same(b_fox[..20], blake_b[0..]) { os.exit(26i32) }
    var key64: [64]u8 = zero
    i = 0usize
    while i < 64usize {
        key64[i] = u8(i)
        i += 1usize
    }
    var big: [300]u8 = zero
    i = 0usize
    while i < 300usize {
        big[i] = u8((i * 7usize) & 255usize)
        i += 1usize
    }
    let b_big = hash.blake2b_keyed(key64[0..], big[0..])
    if !same(b_big[0..], blake_c[0..]) { os.exit(27i32) }
    var streamed = hash.blake2b_init(64usize, key64[0..])
    hash.blake2b_update(&streamed, big[..63])
    hash.blake2b_update(&streamed, big[63..129])
    hash.blake2b_update(&streamed, big[129..])
    let b_streamed = hash.blake2b_done(&streamed)
    if !same(b_streamed[0..], blake_c[0..]) { os.exit(28i32) }
    try io.print("crypto kdf plan ok\n")
    ret ok
}
