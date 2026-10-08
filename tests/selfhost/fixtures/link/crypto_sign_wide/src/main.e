// `e.crypto.hash` SHA-384, `e.crypto.sign` ECDSA over P-384 and P-256 with SHA-256/384/512, and RSA PKCS#1
// v1.5 and PSS with SHA-256/384/512 (C144, D2249), against hashlib and Python's cryptography package
// (vectors.py beside this fixture writes this file). Each signature is also refused for another message,
// another hash, a flipped bit, a truncation, an off-curve key and another key. Every check has its own
// exit code.
use e.os
use e.mem
use e.crypto.hash as hash
use e.crypto.sign as sign
use e.crypto.x509 as x509
use e.time

fn same(a: []const u8, b: []const u8) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn copy(dst: []u8, src: []const u8) {
    var i = 0usize
    while i < src.len {
        dst[i] = src[i]
        i += 1usize
    }
}

fn options(roots: []const x509.Certificate, intermediates: []const x509.Certificate, dns_name: str, usage: x509.KeyUsage, depth: u16) -> x509.VerifyOptions {
    var o: x509.VerifyOptions = zero
    o.roots = x509.Pool { certificates: roots }
    o.intermediates = x509.Pool { certificates: intermediates }
    o.dns_name = dns_name
    o.now = time.Instant { nanos: 1780272000i64 * 1000000000i64 }
    o.usage = usage
    o.max_depth = depth
    ret o
}

fn key_p384(raw: []const u8) -> sign.P384PublicKey {
    var key: sign.P384PublicKey = zero
    copy(key.bytes[0..], raw)
    ret key
}

fn key_p256(raw: []const u8) -> sign.P256PublicKey {
    var key: sign.P256PublicKey = zero
    copy(key.bytes[0..], raw)
    ret key
}

fn main(a: *mem.Arena, args: []str) -> err {
    let sha384_abc: [48]u8 = [48]u8{ 203, 0, 117, 63, 69, 163, 94, 139, 181, 160, 61, 105, 154, 198, 80, 7, 39, 44, 50, 171, 14, 222, 209, 99, 26, 139, 96, 90, 67, 255, 91, 237, 128, 134, 7, 43, 161, 231, 204, 35, 88, 186, 236, 161, 52, 200, 37, 167 }
    let sha384_empty: [48]u8 = [48]u8{ 56, 176, 96, 167, 81, 172, 150, 56, 76, 217, 50, 126, 177, 177, 227, 106, 33, 253, 183, 17, 20, 190, 7, 67, 76, 12, 199, 191, 99, 246, 225, 218, 39, 78, 222, 191, 231, 111, 101, 251, 213, 26, 210, 241, 72, 152, 185, 91 }
    let sha384_two: [48]u8 = [48]u8{ 9, 51, 12, 51, 247, 17, 71, 232, 61, 25, 47, 199, 130, 205, 27, 71, 83, 17, 27, 23, 59, 59, 5, 210, 47, 160, 128, 134, 227, 176, 247, 18, 252, 199, 199, 26, 85, 126, 45, 185, 102, 195, 233, 250, 145, 116, 96, 57 }
    let sha384_long: [48]u8 = [48]u8{ 245, 68, 128, 104, 156, 107, 11, 17, 208, 48, 50, 133, 217, 168, 27, 33, 169, 59, 202, 107, 165, 161, 180, 71, 39, 101, 220, 164, 218, 69, 238, 50, 128, 130, 212, 105, 198, 80, 205, 59, 97, 177, 109, 50, 102, 171, 140, 237 }
    var long: [1000]u8 = zero
    var li = 0usize
    while li < 1000usize {
        long[li] = 97u8
        li += 1usize
    }
    let two = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
    let e1 = hash.sha384("abc")
    if !same(e1[0..], sha384_abc[0..]) { os.exit(1) }
    let e2 = hash.sha384("")
    if !same(e2[0..], sha384_empty[0..]) { os.exit(2) }
    let e3 = hash.sha384(two)
    if !same(e3[0..], sha384_two[0..]) { os.exit(3) }
    let e4 = hash.sha384(long[0..])
    if !same(e4[0..], sha384_long[0..]) { os.exit(4) }
    var s = hash.sha384_init()
    hash.sha384_update(&s, long[..129])
    hash.sha384_update(&s, long[129..])
    let streamed = hash.sha384_done(&s)
    if !same(streamed[0..], sha384_long[0..]) { os.exit(5) }
    let message = "neper wide signatures"
    let other = "neper wide signature"
    let p384_key: [97]u8 = [97]u8{ 4, 40, 60, 29, 115, 101, 206, 71, 136, 242, 159, 142, 191, 35, 78, 223, 254, 173, 111, 233, 151, 251, 234, 95, 250, 45, 88, 204, 157, 250, 123, 28, 80, 139, 5, 82, 111, 85, 185, 235, 178, 4, 15, 5, 180, 143, 182, 208, 225, 148, 117, 201, 144, 97, 228, 27, 136, 186, 82, 239, 219, 140, 22, 144, 71, 26, 97, 216, 103, 237, 121, 151, 41, 217, 201, 44, 208, 29, 189, 34, 86, 48, 216, 78, 222, 50, 167, 143, 158, 100, 102, 76, 218, 197, 18, 239, 140 }
    let p384_public = key_p384(p384_key[0..])
    let p384_sig256: [104]u8 = [104]u8{ 48, 102, 2, 49, 0, 146, 110, 95, 83, 198, 68, 86, 89, 48, 237, 85, 31, 234, 128, 94, 208, 17, 33, 223, 209, 136, 149, 188, 128, 202, 3, 93, 72, 73, 248, 51, 133, 179, 50, 13, 184, 148, 173, 150, 179, 164, 226, 180, 178, 222, 214, 19, 85, 2, 49, 0, 236, 171, 62, 157, 166, 155, 82, 11, 234, 218, 164, 206, 86, 81, 62, 94, 48, 7, 133, 94, 221, 31, 29, 148, 87, 45, 191, 184, 22, 201, 225, 211, 224, 255, 130, 228, 202, 112, 197, 37, 114, 219, 240, 19, 25, 134, 18, 27 }
    if !sign.p384_verify_hash(p384_public, message, p384_sig256[0..], 256u16) { os.exit(6) }
    if sign.p384_verify_hash(p384_public, other, p384_sig256[0..], 256u16) { os.exit(7) }
    let p384_sig384: [102]u8 = [102]u8{ 48, 100, 2, 48, 38, 164, 12, 86, 36, 172, 38, 140, 101, 81, 211, 232, 154, 208, 141, 220, 176, 8, 155, 77, 97, 126, 36, 101, 122, 103, 115, 21, 254, 43, 206, 157, 24, 49, 43, 123, 57, 165, 198, 107, 146, 107, 124, 104, 139, 23, 188, 129, 2, 48, 90, 216, 97, 16, 226, 129, 194, 108, 13, 227, 212, 203, 103, 251, 68, 255, 119, 143, 79, 63, 118, 173, 177, 36, 251, 242, 20, 152, 164, 95, 163, 12, 111, 169, 116, 21, 57, 150, 196, 228, 243, 231, 92, 41, 150, 33, 139, 157 }
    if !sign.p384_verify_hash(p384_public, message, p384_sig384[0..], 384u16) { os.exit(8) }
    if sign.p384_verify_hash(p384_public, other, p384_sig384[0..], 384u16) { os.exit(9) }
    let p384_sig512: [102]u8 = [102]u8{ 48, 100, 2, 48, 126, 52, 153, 117, 183, 84, 195, 116, 114, 116, 87, 153, 166, 177, 160, 164, 107, 166, 237, 235, 60, 7, 37, 22, 106, 48, 238, 141, 3, 14, 87, 202, 119, 66, 121, 69, 185, 44, 18, 137, 213, 184, 215, 250, 181, 130, 151, 186, 2, 48, 119, 192, 59, 240, 233, 121, 193, 139, 146, 82, 235, 215, 115, 87, 0, 156, 218, 119, 212, 27, 47, 76, 236, 46, 23, 126, 112, 12, 196, 120, 195, 103, 163, 0, 220, 85, 216, 185, 202, 94, 167, 161, 142, 21, 143, 185, 18, 252 }
    if !sign.p384_verify_hash(p384_public, message, p384_sig512[0..], 512u16) { os.exit(10) }
    if sign.p384_verify_hash(p384_public, other, p384_sig512[0..], 512u16) { os.exit(11) }
    if sign.p384_verify_hash(p384_public, message, p384_sig384[0..], 256u16) { os.exit(12) }
    if sign.p384_verify_hash(p384_public, message, p384_sig384[0..], 7u16) { os.exit(13) }
    var flipped_p384: [102]u8 = zero
    copy(flipped_p384[0..], p384_sig384[0..])
    let p384_sig384_again: [104]u8 = [104]u8{ 48, 102, 2, 49, 0, 151, 248, 198, 182, 123, 33, 94, 8, 203, 183, 13, 83, 99, 208, 223, 245, 185, 229, 209, 121, 225, 147, 93, 220, 128, 3, 212, 7, 98, 130, 150, 124, 178, 123, 112, 172, 179, 14, 88, 101, 140, 84, 15, 19, 143, 102, 4, 66, 2, 49, 0, 142, 17, 38, 77, 126, 37, 174, 110, 161, 119, 8, 22, 105, 37, 63, 80, 113, 96, 187, 252, 134, 142, 115, 48, 127, 67, 188, 66, 155, 180, 10, 24, 201, 51, 191, 153, 231, 172, 27, 250, 95, 127, 21, 190, 193, 119, 189, 171 }
    flipped_p384[97] = flipped_p384[97] ^ 1u8
    if sign.p384_verify_hash(p384_public, message, flipped_p384[..p384_sig384.len], 384u16) { os.exit(14) }
    if sign.p384_verify_hash(p384_public, message, p384_sig384[..p384_sig384.len - 1usize], 384u16) { os.exit(15) }
    if !sign.p384_verify_hash(p384_public, message, p384_sig384_again[0..], 384u16) { os.exit(16) }
    var off_p384 = p384_public
    off_p384.bytes[94] = off_p384.bytes[94] ^ 1u8
    if sign.p384_verify_hash(off_p384, message, p384_sig384[0..], 384u16) { os.exit(17) }
    let p384_other: [97]u8 = [97]u8{ 4, 22, 146, 119, 142, 165, 150, 224, 190, 117, 17, 66, 151, 166, 250, 56, 52, 69, 191, 34, 127, 190, 88, 25, 10, 144, 12, 60, 115, 37, 111, 17, 251, 90, 50, 88, 214, 244, 3, 213, 236, 230, 233, 178, 105, 216, 34, 200, 125, 220, 210, 54, 87, 0, 212, 16, 106, 131, 83, 136, 186, 61, 184, 253, 14, 34, 85, 74, 220, 109, 82, 28, 212, 189, 28, 48, 194, 236, 14, 236, 25, 107, 173, 225, 233, 205, 209, 112, 141, 111, 106, 191, 164, 2, 43, 10, 210 }
    let other_p384 = key_p384(p384_other[0..])
    if sign.p384_verify_hash(other_p384, message, p384_sig384[0..], 384u16) { os.exit(18) }
    let p256_key: [65]u8 = [65]u8{ 4, 62, 209, 19, 183, 136, 59, 76, 89, 6, 56, 55, 157, 176, 194, 28, 218, 22, 116, 46, 208, 37, 80, 72, 191, 67, 51, 145, 211, 116, 188, 33, 209, 144, 153, 32, 154, 204, 196, 200, 162, 36, 200, 67, 175, 164, 244, 198, 138, 9, 13, 4, 218, 94, 152, 137, 218, 226, 248, 238, 252, 232, 42, 55, 64 }
    let p256_public = key_p256(p256_key[0..])
    let p256_sig256: [71]u8 = [71]u8{ 48, 69, 2, 33, 0, 162, 211, 122, 37, 181, 157, 133, 42, 102, 134, 79, 197, 13, 206, 251, 172, 91, 116, 158, 145, 88, 254, 222, 106, 84, 254, 171, 12, 209, 176, 74, 242, 2, 32, 43, 25, 254, 34, 2, 58, 157, 29, 235, 6, 29, 105, 175, 16, 150, 52, 81, 231, 145, 152, 178, 166, 62, 194, 249, 15, 132, 214, 175, 181, 33, 171 }
    if !sign.p256_verify_hash(p256_public, message, p256_sig256[0..], 256u16) { os.exit(19) }
    if sign.p256_verify_hash(p256_public, other, p256_sig256[0..], 256u16) { os.exit(20) }
    let p256_sig384: [71]u8 = [71]u8{ 48, 69, 2, 32, 0, 137, 63, 53, 174, 126, 151, 197, 28, 238, 118, 61, 199, 8, 96, 229, 117, 181, 62, 25, 38, 39, 215, 30, 8, 101, 121, 140, 105, 112, 22, 200, 2, 33, 0, 138, 87, 209, 175, 42, 79, 211, 43, 66, 76, 133, 108, 168, 247, 14, 121, 14, 97, 206, 55, 29, 184, 47, 61, 72, 86, 16, 234, 68, 99, 174, 203 }
    if !sign.p256_verify_hash(p256_public, message, p256_sig384[0..], 384u16) { os.exit(21) }
    if sign.p256_verify_hash(p256_public, other, p256_sig384[0..], 384u16) { os.exit(22) }
    let p256_sig512: [70]u8 = [70]u8{ 48, 68, 2, 32, 27, 229, 138, 97, 105, 50, 53, 82, 135, 180, 6, 12, 174, 35, 13, 69, 221, 203, 37, 234, 178, 102, 225, 86, 197, 159, 90, 233, 194, 48, 223, 1, 2, 32, 94, 71, 99, 219, 216, 3, 30, 240, 81, 80, 96, 220, 171, 75, 93, 235, 114, 122, 214, 181, 242, 40, 224, 72, 47, 31, 232, 87, 192, 98, 30, 7 }
    if !sign.p256_verify_hash(p256_public, message, p256_sig512[0..], 512u16) { os.exit(23) }
    if sign.p256_verify_hash(p256_public, other, p256_sig512[0..], 512u16) { os.exit(24) }
    if sign.p256_verify_hash(p256_public, message, p256_sig384[0..], 256u16) { os.exit(25) }
    if sign.p256_verify_hash(p256_public, message, p256_sig384[0..], 7u16) { os.exit(26) }
    var flipped_p256: [71]u8 = zero
    copy(flipped_p256[0..], p256_sig384[0..])
    let p256_sig384_again: [72]u8 = [72]u8{ 48, 70, 2, 33, 0, 128, 124, 23, 232, 195, 142, 51, 203, 227, 218, 102, 201, 79, 142, 165, 165, 10, 135, 97, 125, 128, 89, 200, 100, 127, 137, 244, 250, 11, 7, 11, 31, 2, 33, 0, 199, 234, 128, 95, 103, 96, 140, 67, 96, 219, 211, 187, 233, 110, 76, 39, 208, 157, 157, 153, 119, 241, 187, 214, 46, 161, 231, 59, 59, 137, 241, 255 }
    flipped_p256[66] = flipped_p256[66] ^ 1u8
    if sign.p256_verify_hash(p256_public, message, flipped_p256[..p256_sig384.len], 384u16) { os.exit(27) }
    if sign.p256_verify_hash(p256_public, message, p256_sig384[..p256_sig384.len - 1usize], 384u16) { os.exit(28) }
    if !sign.p256_verify_hash(p256_public, message, p256_sig384_again[0..], 384u16) { os.exit(29) }
    var off_p256 = p256_public
    off_p256.bytes[62] = off_p256.bytes[62] ^ 1u8
    if sign.p256_verify_hash(off_p256, message, p256_sig384[0..], 384u16) { os.exit(30) }
    let p256_other: [65]u8 = [65]u8{ 4, 116, 29, 213, 189, 168, 23, 217, 94, 70, 38, 83, 115, 32, 229, 213, 81, 121, 152, 48, 40, 178, 248, 44, 153, 213, 0, 197, 238, 134, 36, 227, 196, 7, 112, 180, 106, 156, 56, 95, 220, 86, 115, 131, 85, 72, 135, 177, 84, 142, 235, 145, 44, 53, 186, 92, 167, 25, 149, 255, 34, 205, 68, 129, 211 }
    let other_p256 = key_p256(p256_other[0..])
    if sign.p256_verify_hash(other_p256, message, p256_sig384[0..], 384u16) { os.exit(31) }
    
    let rsa_n: [256]u8 = [256]u8{ 161, 29, 133, 116, 225, 250, 237, 55, 95, 158, 4, 59, 242, 229, 163, 49, 170, 91, 130, 67, 25, 65, 212, 198, 167, 72, 197, 45, 181, 22, 88, 106, 223, 196, 110, 205, 231, 228, 46, 26, 142, 53, 53, 123, 78, 173, 208, 222, 51, 60, 17, 216, 92, 194, 131, 97, 111, 56, 80, 132, 155, 224, 223, 55, 161, 207, 164, 229, 17, 126, 146, 221, 25, 219, 253, 228, 102, 30, 37, 18, 35, 187, 23, 22, 214, 111, 120, 35, 102, 251, 94, 79, 141, 10, 55, 65, 137, 198, 54, 66, 129, 21, 244, 225, 178, 22, 6, 39, 95, 54, 101, 130, 241, 21, 157, 234, 141, 16, 81, 67, 124, 116, 44, 28, 132, 67, 165, 171, 118, 131, 237, 176, 74, 21, 244, 99, 197, 58, 186, 164, 133, 170, 216, 182, 95, 58, 56, 185, 22, 137, 197, 82, 236, 57, 162, 91, 114, 134, 196, 229, 138, 41, 88, 193, 157, 25, 97, 86, 63, 121, 250, 138, 16, 26, 89, 253, 195, 86, 95, 240, 151, 171, 46, 4, 247, 118, 66, 145, 66, 217, 89, 30, 123, 71, 207, 191, 164, 189, 144, 9, 172, 136, 105, 247, 24, 10, 128, 173, 20, 224, 140, 220, 222, 109, 245, 99, 213, 93, 15, 203, 252, 195, 89, 174, 7, 110, 95, 206, 221, 93, 5, 201, 220, 58, 190, 110, 243, 180, 162, 2, 154, 27, 179, 51, 6, 225, 93, 47, 205, 29, 170, 50, 255, 193, 234, 115 }
    let rsa_e: [3]u8 = [3]u8{ 1, 0, 1 }
    let pkcs1_256: [256]u8 = [256]u8{ 53, 68, 213, 239, 207, 211, 125, 217, 33, 182, 125, 4, 147, 194, 37, 147, 82, 214, 202, 141, 12, 187, 201, 187, 121, 182, 169, 137, 5, 134, 186, 248, 121, 6, 177, 75, 53, 147, 115, 85, 100, 203, 205, 132, 124, 150, 166, 208, 165, 54, 209, 36, 119, 77, 254, 70, 4, 248, 184, 132, 190, 82, 23, 16, 181, 199, 180, 2, 245, 125, 139, 82, 52, 232, 94, 130, 35, 136, 147, 156, 184, 207, 255, 235, 87, 197, 105, 218, 208, 51, 99, 78, 171, 35, 1, 12, 162, 196, 243, 105, 150, 38, 119, 17, 75, 252, 167, 180, 226, 154, 162, 198, 221, 185, 210, 236, 159, 134, 254, 84, 191, 126, 165, 38, 45, 13, 198, 202, 207, 199, 94, 7, 188, 167, 123, 140, 234, 57, 154, 132, 31, 4, 149, 178, 126, 154, 242, 139, 79, 29, 193, 252, 44, 57, 217, 72, 194, 199, 84, 178, 27, 156, 157, 198, 51, 252, 53, 6, 222, 170, 198, 121, 26, 172, 66, 37, 207, 189, 103, 104, 117, 7, 14, 178, 236, 26, 169, 57, 114, 135, 168, 85, 72, 126, 180, 180, 135, 165, 87, 211, 163, 17, 28, 149, 255, 158, 29, 229, 222, 217, 30, 154, 217, 49, 60, 54, 36, 186, 80, 164, 241, 255, 51, 249, 113, 104, 186, 118, 45, 192, 73, 70, 102, 201, 190, 231, 170, 136, 243, 157, 39, 156, 65, 21, 156, 14, 61, 22, 137, 97, 163, 201, 14, 246, 1, 1 }
    let pss_256: [256]u8 = [256]u8{ 28, 152, 164, 22, 75, 210, 221, 213, 198, 42, 50, 195, 195, 255, 166, 180, 213, 132, 174, 19, 105, 242, 213, 237, 188, 119, 208, 39, 28, 160, 167, 248, 147, 154, 118, 172, 94, 231, 139, 125, 36, 24, 57, 5, 160, 110, 205, 10, 15, 64, 148, 143, 177, 254, 39, 15, 110, 176, 218, 156, 67, 252, 170, 168, 201, 59, 233, 68, 54, 191, 44, 173, 37, 161, 9, 39, 226, 77, 150, 248, 91, 2, 239, 20, 44, 106, 252, 196, 168, 239, 51, 48, 243, 38, 251, 197, 20, 163, 23, 44, 60, 34, 165, 163, 115, 162, 105, 29, 214, 118, 39, 215, 226, 157, 36, 140, 78, 194, 182, 67, 217, 196, 130, 254, 244, 190, 220, 227, 170, 178, 252, 106, 198, 166, 162, 148, 4, 44, 108, 223, 96, 171, 209, 225, 231, 117, 102, 158, 10, 207, 215, 72, 234, 191, 108, 50, 238, 123, 145, 5, 124, 191, 188, 222, 91, 250, 255, 191, 149, 6, 141, 26, 135, 13, 232, 130, 63, 47, 50, 10, 95, 233, 9, 108, 232, 255, 162, 6, 20, 208, 104, 146, 18, 10, 89, 62, 32, 26, 113, 108, 221, 50, 230, 103, 50, 247, 102, 238, 168, 30, 131, 92, 222, 49, 19, 169, 143, 232, 253, 146, 145, 211, 53, 196, 116, 24, 175, 93, 157, 163, 246, 211, 247, 80, 82, 101, 34, 200, 28, 15, 93, 182, 235, 160, 69, 172, 245, 203, 135, 241, 139, 160, 175, 0, 198, 19 }
    let mark_256 = mem.mark(a)
    if !sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pkcs1_256[0..], 256u16) { os.exit(32) }
    if sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], other, pkcs1_256[0..], 256u16) { os.exit(33) }
    if !sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pss_256[0..], 256u16) { os.exit(34) }
    if sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], other, pss_256[0..], 256u16) { os.exit(35) }
    mem.reset(a, mark_256)
    let pkcs1_384: [256]u8 = [256]u8{ 16, 47, 249, 103, 170, 177, 203, 183, 149, 187, 151, 106, 229, 50, 240, 4, 129, 138, 65, 116, 123, 116, 110, 217, 54, 228, 165, 91, 15, 22, 0, 219, 115, 4, 13, 245, 20, 72, 255, 42, 55, 200, 26, 72, 81, 88, 34, 56, 0, 245, 26, 63, 211, 228, 193, 162, 84, 235, 63, 66, 105, 26, 0, 83, 79, 7, 251, 229, 219, 242, 11, 225, 15, 116, 133, 143, 81, 15, 39, 165, 215, 58, 204, 72, 185, 144, 23, 34, 48, 95, 45, 64, 142, 110, 243, 71, 219, 84, 29, 29, 132, 94, 216, 29, 52, 94, 233, 209, 154, 153, 204, 56, 40, 34, 71, 161, 222, 182, 21, 203, 68, 37, 210, 135, 31, 51, 233, 73, 37, 135, 49, 69, 176, 178, 148, 40, 176, 114, 24, 70, 63, 2, 20, 50, 247, 93, 130, 123, 38, 51, 15, 146, 10, 105, 35, 26, 78, 175, 17, 190, 116, 253, 199, 237, 175, 206, 153, 129, 213, 14, 236, 151, 90, 221, 37, 139, 76, 244, 149, 118, 138, 192, 234, 208, 123, 112, 0, 60, 50, 57, 171, 17, 187, 214, 185, 154, 201, 52, 82, 94, 182, 103, 114, 236, 60, 125, 244, 230, 239, 198, 197, 32, 19, 159, 80, 66, 42, 124, 247, 74, 119, 3, 81, 147, 111, 16, 28, 150, 209, 76, 212, 55, 27, 230, 157, 208, 78, 215, 156, 57, 180, 211, 214, 34, 89, 72, 3, 125, 173, 191, 251, 212, 17, 228, 120, 227 }
    let pss_384: [256]u8 = [256]u8{ 114, 127, 76, 42, 177, 40, 155, 21, 121, 44, 52, 200, 14, 87, 253, 221, 139, 134, 77, 245, 154, 140, 138, 250, 151, 205, 109, 250, 166, 77, 91, 60, 164, 170, 145, 170, 229, 4, 45, 118, 43, 63, 210, 156, 231, 58, 27, 109, 245, 249, 201, 220, 189, 125, 35, 36, 189, 205, 151, 229, 111, 215, 236, 156, 156, 72, 113, 75, 72, 13, 173, 40, 72, 126, 84, 199, 90, 132, 37, 170, 180, 231, 223, 81, 18, 183, 247, 161, 207, 246, 46, 191, 35, 109, 124, 188, 150, 3, 230, 209, 172, 109, 4, 201, 250, 76, 222, 57, 81, 175, 237, 117, 30, 67, 252, 206, 98, 230, 253, 36, 109, 214, 147, 232, 139, 124, 225, 254, 14, 179, 72, 92, 1, 63, 63, 51, 235, 150, 123, 68, 25, 216, 185, 210, 120, 182, 163, 182, 148, 49, 144, 30, 86, 73, 68, 117, 155, 14, 189, 189, 229, 64, 146, 76, 155, 90, 197, 247, 250, 172, 73, 78, 151, 138, 4, 115, 117, 21, 65, 67, 134, 19, 76, 4, 97, 13, 157, 132, 231, 36, 174, 149, 240, 169, 123, 115, 120, 203, 165, 5, 43, 115, 197, 161, 190, 8, 205, 57, 248, 189, 225, 229, 204, 196, 34, 147, 19, 127, 94, 121, 104, 56, 29, 141, 22, 137, 196, 9, 245, 46, 226, 144, 7, 181, 32, 133, 137, 136, 62, 33, 62, 94, 239, 234, 207, 29, 250, 183, 195, 247, 199, 175, 94, 111, 22, 119 }
    let mark_384 = mem.mark(a)
    if !sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pkcs1_384[0..], 384u16) { os.exit(36) }
    if sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], other, pkcs1_384[0..], 384u16) { os.exit(37) }
    if !sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pss_384[0..], 384u16) { os.exit(38) }
    if sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], other, pss_384[0..], 384u16) { os.exit(39) }
    mem.reset(a, mark_384)
    let pkcs1_512: [256]u8 = [256]u8{ 130, 162, 8, 250, 90, 241, 197, 82, 219, 100, 218, 214, 213, 217, 242, 191, 77, 107, 172, 234, 104, 236, 37, 218, 132, 194, 211, 133, 60, 138, 54, 124, 24, 130, 244, 196, 131, 145, 173, 221, 187, 24, 100, 214, 208, 35, 94, 27, 223, 219, 10, 178, 146, 1, 111, 75, 116, 138, 133, 159, 18, 135, 213, 195, 110, 17, 139, 155, 197, 87, 197, 209, 204, 149, 39, 72, 23, 40, 30, 96, 227, 131, 193, 118, 35, 133, 190, 21, 149, 201, 37, 165, 82, 89, 195, 74, 204, 72, 146, 184, 163, 165, 162, 224, 212, 232, 64, 25, 184, 127, 107, 175, 193, 62, 156, 155, 136, 179, 69, 253, 133, 81, 163, 178, 246, 123, 20, 11, 189, 97, 28, 221, 93, 135, 62, 22, 65, 125, 85, 56, 25, 17, 171, 102, 73, 90, 214, 36, 123, 103, 190, 14, 9, 27, 181, 139, 11, 210, 81, 224, 85, 148, 91, 24, 241, 82, 224, 238, 48, 86, 117, 104, 198, 107, 182, 77, 146, 191, 55, 81, 167, 87, 140, 228, 249, 236, 122, 20, 146, 72, 135, 78, 187, 31, 205, 230, 241, 167, 156, 6, 244, 168, 82, 239, 38, 225, 33, 31, 30, 149, 65, 58, 15, 39, 26, 241, 97, 154, 176, 155, 139, 115, 193, 250, 13, 109, 231, 235, 5, 197, 133, 48, 233, 35, 80, 215, 229, 190, 35, 128, 78, 119, 253, 79, 213, 148, 185, 169, 155, 189, 35, 73, 194, 122, 49, 175 }
    let pss_512: [256]u8 = [256]u8{ 135, 180, 182, 224, 205, 123, 224, 55, 10, 174, 153, 142, 205, 239, 122, 229, 20, 158, 97, 206, 250, 62, 224, 221, 235, 221, 120, 158, 49, 164, 57, 90, 199, 132, 121, 45, 154, 205, 212, 0, 21, 133, 132, 194, 103, 168, 148, 185, 142, 41, 4, 238, 4, 162, 213, 187, 124, 146, 134, 241, 57, 47, 107, 141, 106, 194, 98, 45, 19, 167, 101, 199, 80, 23, 221, 95, 37, 240, 245, 64, 107, 48, 104, 123, 172, 71, 158, 142, 178, 77, 221, 105, 59, 127, 108, 72, 4, 200, 138, 38, 229, 60, 31, 56, 151, 250, 105, 11, 20, 29, 247, 161, 96, 250, 68, 30, 170, 45, 38, 238, 217, 39, 141, 68, 140, 0, 31, 134, 83, 176, 236, 190, 162, 32, 48, 194, 202, 148, 113, 87, 109, 147, 75, 238, 195, 21, 149, 251, 251, 8, 1, 91, 72, 236, 128, 53, 126, 244, 209, 173, 215, 89, 157, 4, 51, 31, 214, 63, 202, 69, 157, 66, 136, 220, 4, 82, 139, 139, 2, 190, 155, 25, 56, 246, 110, 33, 196, 203, 71, 193, 152, 212, 115, 143, 113, 217, 206, 109, 120, 140, 165, 152, 244, 87, 122, 67, 15, 82, 57, 106, 55, 153, 34, 250, 250, 70, 87, 91, 209, 140, 94, 125, 119, 104, 240, 203, 93, 189, 22, 242, 189, 88, 239, 169, 223, 201, 113, 176, 110, 137, 243, 51, 105, 93, 55, 250, 71, 53, 176, 144, 240, 83, 200, 228, 186, 188 }
    let mark_512 = mem.mark(a)
    if !sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pkcs1_512[0..], 512u16) { os.exit(40) }
    if sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], other, pkcs1_512[0..], 512u16) { os.exit(41) }
    if !sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pss_512[0..], 512u16) { os.exit(42) }
    if sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], other, pss_512[0..], 512u16) { os.exit(43) }
    mem.reset(a, mark_512)
    if sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pkcs1_384[0..], 512u16) { os.exit(44) }
    if sign.rsa_pkcs1v15_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pkcs1_512[0..], 384u16) { os.exit(45) }
    if sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pss_384[0..], 512u16) { os.exit(46) }
    if sign.rsa_pss_verify_hash(a, rsa_n[0..], rsa_e[0..], message, pss_256[0..], 384u16) { os.exit(47) }
    if !sign.rsa_pkcs1v15_verify(a, rsa_n[0..], rsa_e[0..], message, pkcs1_256[0..]) { os.exit(48) }
    if !sign.rsa_pss_verify(a, rsa_n[0..], rsa_e[0..], message, pss_256[0..]) { os.exit(49) }
    let c1_root = "0\x82\x01p0\x81\xf7\xa0\x03\x02\x01\x02\x02\x01\x010\x0a\x06\x08*\x86H\xce=\x04\x03\x030\x191\x170\x15\x06\x03U\x04\x03\x0c\x0eWide P384 Root0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x191\x170\x15\x06\x03U\x04\x03\x0c\x0eWide P384 Root0v0\x10\x06\x07*\x86H\xce=\x02\x01\x06\x05+\x81\x04\x00\x22\x03b\x00\x04'\x93]\xf4\xe2\x5coG\xc7\x81q!\x05}F\xe1`b\x90\x98_\x82\x83\xf5\xf9\x93a6\xbfB\xcd\xb7F\xa3s\x13\xdf\x88\xfddbkL\x17^\xb7t\x228\x0a\x1a;H\x98\xd4\xcd\x9a\xb1\xa3y\x8d\x1e5$\xa4\xf2\xd4\xae\xc0y\xc6\xb7X]\x9cNla[S+o\x8d\x988\xef\x0c\x13\x9dV\x06\xeb\x10\xc6\x9f\x84\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x0a\x06\x08*\x86H\xce=\x04\x03\x03\x03h\x000e\x020\x10\x03\x8d&\x9fy\xe8\x16\xe2U\x18\x8e\xb7\x93\xc3\x9d\xc3\xdd\xae\xda\x94\xf7z\xb3\x0f\xb5$\xa6*]\x8f\x17\xfar\xb8\xb8\xc2\xfc\x22\x96\x06\x7fEzy@\xc8\x01\x021\x00\xe7i\x03X\xe5\xdbt\x85\x98\x8c\xd6\x12\xd4\x87\xe3\xc5\xec\xcd\x1eW)\xe5\x8d^\x9f\xf9\x8a\xb0u\x92*!w\xdb\x191\xb7\xfa\x03\xe1h\x9b\x10\xe4\xa1\x84\xba\x95"
    let c1_mid = "0\x82\x01[0\x81\xe2\xa0\x03\x02\x01\x02\x02\x01\x020\x0a\x06\x08*\x86H\xce=\x04\x03\x030\x191\x170\x15\x06\x03U\x04\x03\x0c\x0eWide P384 Root0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0!1\x1f0\x1d\x06\x03U\x04\x03\x0c\x16Wide P256 Intermediate0Y0\x13\x06\x07*\x86H\xce=\x02\x01\x06\x08*\x86H\xce=\x03\x01\x07\x03B\x00\x04\xc0\xdd$\x1aP\xd4\x8f\x99\xfc\xc7\xa1\x86\xa6\xd4N\x07c\xec\x90G\x8e\x1d\xef\x8e6\xf5\xc4\xe9P\xd6z\xfb\x82\x86s.\xa9eH\xb8A\xa7\xcd\xc6\xea\xc0b\xd8\xdax\xe5|\xe0>\xa2\xd6\x0c\xbc\xd1k\xd8\xca\xecl\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x0a\x06\x08*\x86H\xce=\x04\x03\x03\x03h\x000e\x021\x00\x84\x17_\x05I\x0e\x7f\xb7l\xb8\x87\x88\xc5jfA\xdcn\xbf\x925\xf3\xe9\xe4!\xea\xf2A\xbax\xcd\xdb{\x92y\x94\xa7\x9e\xc1\xff\xa9-\x06K\xe9s\x1e\x0e\x020\x0e\xbb\x88\x14I\xd2\xaa~P\x12\x9bS\xcf-\xd2\x00F\xc6p\xde\xc1\xf7\x86\xa3\xc7\x9cu\x1f\xf0\xfb\xb4\x9c\xc3\xfb\x0b\x07\x1aHx\xeb\x0d@\x95k!\xab\x00\x22"
    let c1_leaf = "0\x82\x01b0\x82\x01\x07\xa0\x03\x02\x01\x02\x02\x01\x030\x0a\x06\x08*\x86H\xce=\x04\x03\x020!1\x1f0\x1d\x06\x03U\x04\x03\x0c\x16Wide P256 Intermediate0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x151\x130\x11\x06\x03U\x04\x03\x0c\x0ac1.example0Y0\x13\x06\x07*\x86H\xce=\x02\x01\x06\x08*\x86H\xce=\x03\x01\x07\x03B\x00\x04\x0e\x91\xc7#\x9c&@\xd7\xd2\x8a>9\xd4X?\xa6<\x0b\xc0\xa5\xdfd\xa4\xfeg.W0E\xcax\x96]\xf6\x5c;U\x0d\xba\x22\x1a\x22s;\xb8\xe0\xbdm~h\x835u\xe7\xa5\xae\x13\x80FT1@\xadU\xa3<0:0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000\x15\x06\x03U\x1d\x11\x04\x0e0\x0c\x82\x0ac1.example0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x0a\x06\x08*\x86H\xce=\x04\x03\x02\x03I\x000F\x02!\x00\xd2\xe4f=m\xd1\x0a\x8e\xcf\x97\xc0\x90\xa6\xa0\xd0\x19/\xebI\xe7\xf1\x19\xf7/:O\xbd\xe9\x0f\xfe\xa1\xae\x02!\x00\xbc\xfb\xa4v\xd1$\xe9^_\x87\x7f\xcd\xd0I\x81\xb2\xe8D\x81\xf34K\x9b\xdf~\x08\xd3\xc2\x83bq["
    let c1_leaf512 = "0\x82\x01x0\x81\xff\xa0\x03\x02\x01\x02\x02\x01\x040\x0a\x06\x08*\x86H\xce=\x04\x03\x040\x191\x170\x15\x06\x03U\x04\x03\x0c\x0eWide P384 Root0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x151\x130\x11\x06\x03U\x04\x03\x0c\x0ac1.example0Y0\x13\x06\x07*\x86H\xce=\x02\x01\x06\x08*\x86H\xce=\x03\x01\x07\x03B\x00\x04\x0e\x91\xc7#\x9c&@\xd7\xd2\x8a>9\xd4X?\xa6<\x0b\xc0\xa5\xdfd\xa4\xfeg.W0E\xcax\x96]\xf6\x5c;U\x0d\xba\x22\x1a\x22s;\xb8\xe0\xbdm~h\x835u\xe7\xa5\xae\x13\x80FT1@\xadU\xa3<0:0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000\x15\x06\x03U\x1d\x11\x04\x0e0\x0c\x82\x0ac1.example0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x0a\x06\x08*\x86H\xce=\x04\x03\x04\x03h\x000e\x021\x00\xc2\x18Ub\x83g$t\x08\xa2\xb8d\x94\x92\xeb7@\xf7\xcb\xe0<\xff\xff\xa1\x8fG3\xab\xcf(\xb9\xdc\x93\xdeqp{C\xeeES\xa1\x1c<\xba\xbe\x13\xa4\x020\x05\xca\x1c.\xae\xea\x01\x0c\xbbQ\xedjs\xc0L\xbdr\x17\x88\xaa\xc06!\xaf$\x92\x82\xc7\xd4ld\x96\xb1\xb1\xc28\xda\x03\xcd\x10\xca\xf2q\x11[\xd8\xfb\x94"
    let c1_leaf384 = "0\x82\x01\x970\x82\x01\x1c\xa0\x03\x02\x01\x02\x02\x01\x050\x0a\x06\x08*\x86H\xce=\x04\x03\x020\x191\x170\x15\x06\x03U\x04\x03\x0c\x0eWide P384 Root0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x151\x130\x11\x06\x03U\x04\x03\x0c\x0ac1.example0v0\x10\x06\x07*\x86H\xce=\x02\x01\x06\x05+\x81\x04\x00\x22\x03b\x00\x04\x0b+x\xbd\xb3\x99\xc1{\xb3\xc1,\x1d\xff[Q\xa9\xf8&\xf0\x16\x04U\xec\xcb\x7fK\xa7PC\xf7\xcek\x13?\x17\x1d9\x9b\xb3g\xb8\xfcP:R\xc7\x11\x9d;[\xe6@^\x18p\xd1c_\x15\x85NuyM\xe9O\x1a)A\x9a\x8dS\xbd\x11~\xeeDm\x0a\xf1\xc0\xa9\xf61\x86\xf6kQ\x84\xce\xbdDF\xc4h0\xa3<0:0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000\x15\x06\x03U\x1d\x11\x04\x0e0\x0c\x82\x0ac1.example0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x0a\x06\x08*\x86H\xce=\x04\x03\x02\x03i\x000f\x021\x00\x8ee\xdc-[\xdf_\xd6l\xbe\x10\x15\x0f\x89\xf5lG\xfaT\xc7\xd6i\x16v\xcc\x97\x80R\xc2\xd6\x06\x80]\x0eR:\x1e\x87\x85z\xdc\x81<\xbb\x9c\xef\x99\xa6\x021\x00\xb0e\xcc\x01BI\xb7\x0c\xac\xcf\xdf\x9b4,Jt'\xff\xfed\xa0J\x97\x8f\x1f\xfa\xc5F\xef\xa4\xf0u\x1b\x02T0N\x8e\xa9\x12{(r\xdf\x0cz\x93\x1a"
    let c2_root = "0\x82\x02\xbe0\x82\x01\xa6\xa0\x03\x02\x01\x02\x02\x01\x010\x0d\x06\x09*\x86H\x86\xf7\x0d\x01\x01\x0c\x05\x000\x181\x160\x14\x06\x03U\x04\x03\x0c\x0dWide RSA Root0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x181\x160\x14\x06\x03U\x04\x03\x0c\x0dWide RSA Root0\x82\x01\x220\x0d\x06\x09*\x86H\x86\xf7\x0d\x01\x01\x01\x05\x00\x03\x82\x01\x0f\x000\x82\x01\x0a\x02\x82\x01\x01\x00\xe6\xc1\x14e\xe2\xb6n*\xf1\x5c\xf7\x0f\xff\xe9\xc9$\xd5\x0c\x85\xa2\xd9\x1b\xc8\xa1#\xa6\x91&\x22\xfc\x99\x98\xe4\xcc\xba\x11h\x02\x1c\x88Z\xb9\xf4\xaa\xd4K\xf3\xdb\xe7\xe1\x1e\x01\xfa\x13c\xcd\x15?\xa8\xad\x9e\x1b\xf2\xea\xd9\x99\x84\xb4\xa3\x98J\xc0O\xdb\xca\x99Qb\x16z\x82\xf4\x11\xcd\x0c\x96\x90\x84\xe6~\xeb\xd9\x5c&\xee\x09\xca\x9dG`N16>*\xe3\xbb]\xc6G\xb2\xc9\xe1}?\x97\xe3\xd11E\xef\xdbY\xb7:\xe28\x19\x09\x82+\xc6_\x7f\x93\x0a\xa7\x0bp)A\xcc`;2\xfcZ;v\xfej\x90\xc4I\x0c\x8d\xae\x1dnuC\x1d%\xff\x07\xbcT\xd5\x93\xb1\x1b\x00\x93h\xcbo\xa4\x8d@o\xc9\xa0\xff\x8b\xb8\x925!\xeb\x19\x17\x82\xc0+\xf6\x80c\xbe\xd9\x96:\x0b\xf6\x96\x82\x15P\xeesi\xbc\x82\x88\xd1z\x88\xe9\x0cy\xa9\x01\xf0\xaf8uKI4\x8b\xe9\xc3\x5c>\x97PZ@;e@\xf0\xab\x1d\xd6oC\xa3\x93V\x81\xd6y\x0e\xb8\x87\xdb\x02\x03\x01\x00\x01\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x0d\x06\x09*\x86H\x86\xf7\x0d\x01\x01\x0c\x05\x00\x03\x82\x01\x01\x00\xa6d\xfbW0x03{\xe4 B_E*\xaf\xe5\xdcj\xbd?T\xc1\xe0\xe5\x06\x00\x1a\xd1\x83x\xeb\xed\xa6@\xbfg\xa1\x9b\x9b\xc5\x94=\xef\x8a\xb5T\x22\xb2\x82BH\x9d\xd0p\xee\xd1>\xc9\xc1\xa3\x15\xa8\x15^D\x8f\x1b\xaf\xfb\x90\x1f\xb1\xd2\x9f\xcf\xc17\xc1\xf5\xd4\x7fl\x0f\xb2\x00<\x0d(C\x9e\x9f\xf2\x0b\xf9R\x07\xe1\x09Iw\x97\xe7\xdd\x87\x1a_\xa01\x17CI\x9b\xb1\xfe\x14\x14cC\xe0\xe4\xc8l}u~\x1b9\xb4\x11Q\x0bX!\xbd\xca\xa3\xca<*\x0c/\xc1\xf6\x8e2\xf2\x8a\x93\xcbT\x94\x96\xa7\x00\xc5P\xe9!\x0b\x0f.\x92\x22\xb2A\x85\xcc^\xad,J\xf8.\x89+\x92W?G\x1a\xa3\xcel\x8b\xe9\xe7\xa2\xd0\xb3Uo\x85\xb9\x94\xd6\xe6-\xc3ue\xb6\xb6\xf95?x\x04\x12\x94\xf8\x95R>\xd6\x89VG\xd5\xe7\xb0\x1d`t\xd2\x8bD\x01\x03UE\xa8t>\xaf1\x01\xf3/\xeb:\xa4R7\x01\xf7A\xc7\xc9\x1e\x01\xe6\xcf)\x09y"
    let c2_leaf = "0\x82\x02\x190\x82\x01\x01\xa0\x03\x02\x01\x02\x02\x01\x020\x0d\x06\x09*\x86H\x86\xf7\x0d\x01\x01\x0d\x05\x000\x181\x160\x14\x06\x03U\x04\x03\x0c\x0dWide RSA Root0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x151\x130\x11\x06\x03U\x04\x03\x0c\x0ac2.example0Y0\x13\x06\x07*\x86H\xce=\x02\x01\x06\x08*\x86H\xce=\x03\x01\x07\x03B\x00\x04\x0e\x91\xc7#\x9c&@\xd7\xd2\x8a>9\xd4X?\xa6<\x0b\xc0\xa5\xdfd\xa4\xfeg.W0E\xcax\x96]\xf6\x5c;U\x0d\xba\x22\x1a\x22s;\xb8\xe0\xbdm~h\x835u\xe7\xa5\xae\x13\x80FT1@\xadU\xa3<0:0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000\x15\x06\x03U\x1d\x11\x04\x0e0\x0c\x82\x0ac2.example0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x0d\x06\x09*\x86H\x86\xf7\x0d\x01\x01\x0d\x05\x00\x03\x82\x01\x01\x00\xd8\xbc\xf4\xe05\xc5-\x7f0\x1ab\xfdr\x07d\xfd\xfc\x1dk\xa0\xbe:@,]\x14#\x00\xa1t\x0d\xcf\xdaOC~?-\xe7MC\xa58\x92\x1bInO3\x1a\xf0\x07\xea\x0f\xdb\xa1\xbe\xfc2\x1f\xa7\x86\xf8\xe1\xa9\x98\xbb\x22\xec\x02\x05\xfeCp\x84J\x98\x0e\xe0B!fz@<S\x1c\xb0\xd5\xeb\xcaY\xd6\xd7\xf0$\xd8t\x91\xfb\x96\xd8\x91\x16\x15\xe6K\xe0n?\x89\xcd\x90\xef\xbe\xe5\xd8m\xf1\xe5\x18wi\x04\xf1\x1e\x1e;A\x04\xc3`\x07\x83\xf3\xdf\xbea\x7fh\xbc\xb3:\x00fF^f\xba\xdf\x7fF\x99\x85\xe3\xa4\xc4\x008]\xa5\xd18N\xceb\x93\x87\x84\xd8h\xed\x09\x8c\x9a\xd0\x0e\x0c\x06\x7f\x0f\xca-\xf7r\xb8\x12\xc5\x1ak\x80\xa5\x83\x92\x09\x11\xde[\xc4\xaavNsDHi\x84\x9b\xa4\xdf\xf5\xae\xda\xd5\x12\xdc\x1c\xb6\x14\xc3,\x98\xbb(k\xc5>\xfewX\x03|J\x0f\xe9\x14\xf2'^\x11\xbd\xa0u\x0a\xb9\xcf\x8a\x9aJ\xb3PS\x94F\xfa\x97"
    let c2_leaf384 = "0\x82\x02\x190\x82\x01\x01\xa0\x03\x02\x01\x02\x02\x01\x030\x0d\x06\x09*\x86H\x86\xf7\x0d\x01\x01\x0c\x05\x000\x181\x160\x14\x06\x03U\x04\x03\x0c\x0dWide RSA Root0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x151\x130\x11\x06\x03U\x04\x03\x0c\x0ac2.example0Y0\x13\x06\x07*\x86H\xce=\x02\x01\x06\x08*\x86H\xce=\x03\x01\x07\x03B\x00\x04\x0e\x91\xc7#\x9c&@\xd7\xd2\x8a>9\xd4X?\xa6<\x0b\xc0\xa5\xdfd\xa4\xfeg.W0E\xcax\x96]\xf6\x5c;U\x0d\xba\x22\x1a\x22s;\xb8\xe0\xbdm~h\x835u\xe7\xa5\xae\x13\x80FT1@\xadU\xa3<0:0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000\x15\x06\x03U\x1d\x11\x04\x0e0\x0c\x82\x0ac2.example0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x0d\x06\x09*\x86H\x86\xf7\x0d\x01\x01\x0c\x05\x00\x03\x82\x01\x01\x00\x85\x13,\xe6\x12\x87\x8d\xc6\xbc\x0f\x14\x80\x02\xe0\x94\xee\xc4J\x04\xae\x19\xa7\xb1\x96\x18\x90*D\x9f\xd7>\xe5\xe8\x9b\x8b\x1bq\x96\xb9\x09!\xa6\xa0\x92\x8c\xa9\x88\x9c\xc3R\xc9\xf4:5;I\xe1\xb7v\x89\x16\xb7mlj\xb0ol2\x0d\x14m:\xfb\xb6\x0616\x7fg\xa7f\xe2w1\xfd\x05\x85\xab\x9b\x82k\x82G\x96M\x08\xdd\xda\xaa\x9f\xf7@`\x9dH6\x80O\x18&\x0c\xe3pA?\xadR\xb8f\xf5\xd2\xedk.\xf8+1\x9e\xa0\xe3\x86\xa9?\xf7\xc51sL-\x1f\x1c\x85\x1fl9$D)\xc0\xb5\xc2\xe4\xff\x09\x94\xbc^9\x11\xdc\xad\xdcG\xeaN\x98\xc9\xff^\x09&\xfe&\x8c\xbf%\x95\x0f\xb8j)|'v7H%\x9a\x1a\xbc\xe0bY\xa8;b\x80\xea\x01\xbf\xd8\x12y\x12\x159\x15\xbad\x09\x03\xee\xd7\x84\xcf\xc9\xdcP\x82\x064\xbe\x18\xdb\x9eh4\x9c\x97\xe7\x83}$\xa5I1`o:\x81\xcfv\xc1\x86\xf3\x8b\x04\xd4WN\xe2\xd2\xc9\x7f~"
    var c1_roots: [1]x509.Certificate = zero
    var c1_mids: [1]x509.Certificate = zero
    var c2_roots: [1]x509.Certificate = zero
    var c1_root_parsed: x509.Certificate = zero
    let (c1_root_cert, pe_c1_root) = x509.parse(a, c1_root)
    if pe_c1_root != ok { os.exit(50) }
    let (c1_mid_cert, pe_c1_mid) = x509.parse(a, c1_mid)
    if pe_c1_mid != ok { os.exit(51) }
    let (c1_leaf_cert, pe_c1_leaf) = x509.parse(a, c1_leaf)
    if pe_c1_leaf != ok { os.exit(52) }
    let (c1_leaf512_cert, pe_c1_leaf512) = x509.parse(a, c1_leaf512)
    if pe_c1_leaf512 != ok { os.exit(53) }
    let (c1_leaf384_cert, pe_c1_leaf384) = x509.parse(a, c1_leaf384)
    if pe_c1_leaf384 != ok { os.exit(54) }
    let (c2_root_cert, pe_c2_root) = x509.parse(a, c2_root)
    if pe_c2_root != ok { os.exit(55) }
    let (c2_leaf_cert, pe_c2_leaf) = x509.parse(a, c2_leaf)
    if pe_c2_leaf != ok { os.exit(56) }
    let (c2_leaf384_cert, pe_c2_leaf384) = x509.parse(a, c2_leaf384)
    if pe_c2_leaf384 != ok { os.exit(57) }
    c1_roots[0] = c1_root_cert
    c1_mids[0] = c1_mid_cert
    c2_roots[0] = c2_root_cert
    if x509.verify_signature(a, c1_root_cert, c1_root_cert) != ok { os.exit(58) }
    if x509.verify_signature(a, c1_mid_cert, c1_root_cert) != ok { os.exit(59) }
    if x509.verify_signature(a, c1_leaf_cert, c1_mid_cert) != ok { os.exit(60) }
    if x509.verify_signature(a, c1_leaf512_cert, c1_root_cert) != ok { os.exit(61) }
    if x509.verify_signature(a, c1_leaf384_cert, c1_root_cert) != ok { os.exit(62) }
    if x509.verify_signature(a, c1_leaf_cert, c1_root_cert) != x509.InvalidCertificate { os.exit(63) }
    if x509.verify_signature(a, c1_mid_cert, c1_leaf_cert) != x509.InvalidCertificate { os.exit(64) }
    if x509.verify_signature(a, c2_root_cert, c2_root_cert) != ok { os.exit(65) }
    if x509.verify_signature(a, c2_leaf_cert, c2_root_cert) != ok { os.exit(66) }
    if x509.verify_signature(a, c2_leaf384_cert, c2_root_cert) != ok { os.exit(67) }
    if x509.verify_signature(a, c2_leaf_cert, c1_root_cert) != x509.InvalidCertificate { os.exit(68) }
    let (chain1, chain1_error) = x509.verify(a, c1_leaf_cert, options(c1_roots[0..], c1_mids[0..], "c1.example", .ServerAuth, 4u16))
    if chain1_error != ok || chain1.certificates.len != 3usize { os.exit(69) }
    let (chain1b, chain1b_error) = x509.verify(a, c1_leaf_cert, options(c1_roots[0..], c1_mids[0..], "other.example", .ServerAuth, 4u16))
    if chain1b_error == ok { os.exit(70) }
    let (chain2, chain2_error) = x509.verify(a, c2_leaf_cert, options(c2_roots[0..], zero, "c2.example", .ServerAuth, 4u16))
    if chain2_error != ok || chain2.certificates.len != 2usize { os.exit(71) }
    let (chain3, chain3_error) = x509.verify(a, c2_leaf_cert, options(c1_roots[0..], zero, "c2.example", .ServerAuth, 4u16))
    if chain3_error == ok { os.exit(72) }
    os.exit(0)
    ret ok
}
