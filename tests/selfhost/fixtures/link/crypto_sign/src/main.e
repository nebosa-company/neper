// `e.crypto.sign`: Ed25519 against RFC 8032 section 7.1 tests 1-3 (public key from
// the seed, the signature byte for byte, verification), then the refusals: a flipped
// signature bit, a changed message, a non-canonical public key, the identity as a
// public key, and S at L. RFC 6979's P-256/SHA-256 sample pins ECDSA verification,
// strict DER and invalid-point rejection. Every check has its own exit code.
use e.os
use e.mem
use e.crypto.sign as sign

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn check(seed: [32]u8, expected_pk: [32]u8, message: []const u8, expected_sig: [64]u8, base: u8) -> u8 {
    var sk: sign.Ed25519SecretKey = zero
    sk.bytes = seed
    let (pk, e1) = sign.ed25519_public_from_secret(sk)
    if e1 != ok { ret base }
    if !same(pk.bytes[0..], expected_pk[0..]) { ret base + 1u8 }
    let (sig, e2) = sign.ed25519_sign(sk, message)
    if e2 != ok { ret base + 2u8 }
    if !same(sig.bytes[0..], expected_sig[0..]) { ret base + 3u8 }
    if !sign.ed25519_verify(pk, message, sig) { ret base + 4u8 }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    let t1_sk: [32]u8 = [32]u8{ 157, 97, 177, 157, 239, 253, 90, 96, 186, 132, 74, 244, 146, 236, 44, 196, 68, 73, 197, 105, 123, 50, 105, 25, 112, 59, 172, 3, 28, 174, 127, 96 }
    let t1_pk: [32]u8 = [32]u8{ 215, 90, 152, 1, 130, 177, 10, 183, 213, 75, 254, 211, 201, 100, 7, 58, 14, 225, 114, 243, 218, 166, 35, 37, 175, 2, 26, 104, 247, 7, 81, 26 }
    let t1_sig: [64]u8 = [64]u8{ 229, 86, 67, 0, 195, 96, 172, 114, 144, 134, 226, 204, 128, 110, 130, 138, 132, 135, 127, 30, 184, 229, 217, 116, 216, 115, 224, 101, 34, 73, 1, 85, 95, 184, 130, 21, 144, 163, 59, 172, 198, 30, 57, 112, 28, 249, 180, 107, 210, 91, 245, 240, 89, 91, 190, 36, 101, 81, 65, 67, 142, 122, 16, 11 }
    let t2_sk: [32]u8 = [32]u8{ 76, 205, 8, 155, 40, 255, 150, 218, 157, 182, 195, 70, 236, 17, 78, 15, 91, 138, 49, 159, 53, 171, 166, 36, 218, 140, 246, 237, 79, 184, 166, 251 }
    let t2_pk: [32]u8 = [32]u8{ 61, 64, 23, 195, 232, 67, 137, 90, 146, 183, 10, 167, 77, 27, 126, 188, 156, 152, 44, 207, 46, 196, 150, 140, 192, 205, 85, 241, 42, 244, 102, 12 }
    let t2_sig: [64]u8 = [64]u8{ 146, 160, 9, 169, 240, 212, 202, 184, 114, 14, 130, 11, 95, 100, 37, 64, 162, 178, 123, 84, 22, 80, 63, 143, 179, 118, 34, 35, 235, 219, 105, 218, 8, 90, 193, 228, 62, 21, 153, 110, 69, 143, 54, 19, 208, 241, 29, 140, 56, 123, 46, 174, 180, 48, 42, 238, 176, 13, 41, 22, 18, 187, 12, 0 }
    let t3_sk: [32]u8 = [32]u8{ 197, 170, 141, 244, 63, 159, 131, 123, 237, 183, 68, 47, 49, 220, 183, 177, 102, 211, 133, 53, 7, 111, 9, 75, 133, 206, 58, 46, 11, 68, 88, 247 }
    let t3_pk: [32]u8 = [32]u8{ 252, 81, 205, 142, 98, 24, 161, 163, 141, 164, 126, 208, 2, 48, 240, 88, 8, 22, 237, 19, 186, 51, 3, 172, 93, 235, 145, 21, 72, 144, 128, 37 }
    let t3_sig: [64]u8 = [64]u8{ 98, 145, 214, 87, 222, 236, 36, 2, 72, 39, 230, 156, 58, 190, 1, 163, 12, 229, 72, 162, 132, 116, 58, 68, 94, 54, 128, 215, 219, 90, 195, 172, 24, 255, 155, 83, 141, 22, 242, 144, 174, 103, 247, 96, 152, 77, 198, 89, 74, 124, 21, 233, 113, 110, 210, 141, 192, 39, 190, 206, 234, 30, 196, 10 }
    let empty: [1]u8 = zero
    let r1 = check(t1_sk, t1_pk, empty[0..0], t1_sig, 1u8)
    if r1 != 0u8 { os.exit(i32(r1)) }
    let m2: [1]u8 = [1]u8{ 114 }
    let r2 = check(t2_sk, t2_pk, m2[0..], t2_sig, 10u8)
    if r2 != 0u8 { os.exit(i32(r2)) }
    let m3: [2]u8 = [2]u8{ 175, 130 }
    let r3 = check(t3_sk, t3_pk, m3[0..], t3_sig, 20u8)
    if r3 != 0u8 { os.exit(i32(r3)) }
    // Refusals, around test 3.
    var pk: sign.Ed25519PublicKey = zero
    pk.bytes = t3_pk
    var sig: sign.Ed25519Signature = zero
    sig.bytes = t3_sig
    var bad = sig
    bad.bytes[5] = bad.bytes[5] ^ 1u8
    if sign.ed25519_verify(pk, m3[0..], bad) { os.exit(30) }
    bad = sig
    bad.bytes[40] = bad.bytes[40] ^ 1u8
    if sign.ed25519_verify(pk, m3[0..], bad) { os.exit(31) }
    if sign.ed25519_verify(pk, m2[0..], sig) { os.exit(32) }
    var odd: sign.Ed25519PublicKey = zero
    var i = 0usize
    while i < 32usize {
        odd.bytes[i] = 255u8
        i += 1usize
    }
    if sign.ed25519_verify(odd, m3[0..], sig) { os.exit(33) }
    var identity: sign.Ed25519PublicKey = zero
    identity.bytes[0] = 1u8
    if sign.ed25519_verify(identity, m3[0..], sig) { os.exit(34) }
    let l_bytes: [32]u8 = [32]u8{ 237, 211, 245, 92, 26, 99, 18, 88, 214, 156, 247, 162, 222, 249, 222, 20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16 }
    bad = sig
    i = 0usize
    while i < 32usize {
        bad.bytes[32usize + i] = l_bytes[i]
        i += 1usize
    }
    if sign.ed25519_verify(pk, m3[0..], bad) { os.exit(35) }
    let p256_public_bytes = "\x04\x60\xfe\xd4\xba\x25\x5a\x9d\x31\xc9\x61\xeb\x74\xc6\x35\x6d\x68\xc0\x49\xb8\x92\x3b\x61\xfa\x6c\xe6\x69\x62\x2e\x60\xf2\x9f\xb6\x79\x03\xfe\x10\x08\xb8\xbc\x99\xa4\x1a\xe9\xe9\x56\x28\xbc\x64\xf2\xf1\xb2\x0c\x2d\x7e\x9f\x51\x77\xa3\xc2\x94\xd4\x46\x22\x99"
    let p256_signature = "\x30\x46\x02\x21\x00\xef\xd4\x8b\x2a\xac\xb6\xa8\xfd\x11\x40\xdd\x9c\xd4\x5e\x81\xd6\x9d\x2c\x87\x7b\x56\xaa\xf9\x91\xc3\x4d\x0e\xa8\x4e\xaf\x37\x16\x02\x21\x00\xf7\xcb\x1c\x94\x2d\x65\x7c\x41\xd4\x36\xc7\xa1\xb6\xe2\x9f\x65\xf3\xe9\x00\xdb\xb9\xaf\xf4\x06\x4d\xc4\xab\x2f\x84\x3a\xcd\xa8"
    var p256_public: sign.P256PublicKey = zero
    i = 0usize
    while i < 65usize {
        p256_public.bytes[i] = p256_public_bytes[i]
        i += 1usize
    }
    if !sign.p256_verify(p256_public, "sample", p256_signature) { os.exit(36) }
    var bad_p256 = p256_public
    bad_p256.bytes[20] = bad_p256.bytes[20] ^ 1u8
    if sign.p256_verify(bad_p256, "sample", p256_signature) { os.exit(37) }
    if sign.p256_verify(p256_public, "test", p256_signature) { os.exit(38) }
    if sign.p256_verify(p256_public, "sample", p256_signature[..p256_signature.len - 1usize]) { os.exit(39) }
    ret ok
}
