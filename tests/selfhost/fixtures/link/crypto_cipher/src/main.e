// `e.crypto.cipher`: FIPS-197 appendix C blocks at all three key sizes both ways,
// SP 800-38A F.2.1 (CBC) and F.5.1 (CTR), CTR seeking, CBC with PKCS#7 over a 37-byte
// message, RFC 8439 2.3.2 (block) and 2.4.2 (sunscreen), HChaCha20, and the refusals.
// Vectors from vectors.py (Python cryptography) in the scratchpad. One exit code each.
use e.io
use e.os
use e.mem
use e.crypto.cipher as cipher

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
    let fips_plain: [16]u8 = [16]u8{ 0, 17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204, 221, 238, 255 }
    let fips128: [16]u8 = [16]u8{ 105, 196, 224, 216, 106, 123, 4, 48, 216, 205, 183, 128, 112, 180, 197, 90 }
    let fips192: [16]u8 = [16]u8{ 221, 169, 124, 164, 134, 76, 223, 224, 110, 175, 112, 160, 236, 13, 113, 145 }
    let fips256: [16]u8 = [16]u8{ 142, 162, 183, 202, 81, 103, 69, 191, 234, 252, 73, 144, 75, 73, 96, 137 }
    var seq: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        seq[i] = u8(i)
        i += 1usize
    }
    // 1-3: FIPS-197 C.1, C.2, C.3 forward; 4: each decrypts back.
    let (k128, e128) = cipher.aes_key(seq[..16])
    let (k192, e192) = cipher.aes_key(seq[..24])
    let (k256, e256) = cipher.aes_key(seq[0..])
    if e128 != ok || e192 != ok || e256 != ok { os.exit(1i32) }
    var block = fips_plain
    cipher.aes_block(&k128, block[0..])
    if !same(block[0..], fips128[0..]) { os.exit(1i32) }
    cipher.aes_block_decrypt(&k128, block[0..])
    if !same(block[0..], fips_plain[0..]) { os.exit(4i32) }
    block = fips_plain
    cipher.aes_block(&k192, block[0..])
    if !same(block[0..], fips192[0..]) { os.exit(2i32) }
    cipher.aes_block_decrypt(&k192, block[0..])
    if !same(block[0..], fips_plain[0..]) { os.exit(4i32) }
    block = fips_plain
    cipher.aes_block(&k256, block[0..])
    if !same(block[0..], fips256[0..]) { os.exit(3i32) }
    cipher.aes_block_decrypt(&k256, block[0..])
    if !same(block[0..], fips_plain[0..]) { os.exit(4i32) }
    // SP 800-38A shared material.
    let nist_key: [16]u8 = [16]u8{ 43, 126, 21, 22, 40, 174, 210, 166, 171, 247, 21, 136, 9, 207, 79, 60 }
    let iv: [16]u8 = [16]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 }
    let ctr_iv: [16]u8 = [16]u8{ 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255 }
    let nist_plain: [64]u8 = [64]u8{ 107, 193, 190, 226, 46, 64, 159, 150, 233, 61, 126, 17, 115, 147, 23, 42, 174, 45, 138, 87, 30, 3, 172, 156, 158, 183, 111, 172, 69, 175, 142, 81, 48, 200, 28, 70, 163, 92, 228, 17, 229, 251, 193, 25, 26, 10, 82, 239, 246, 159, 36, 69, 223, 79, 155, 23, 173, 43, 65, 123, 230, 108, 55, 16 }
    let cbc_expected: [64]u8 = [64]u8{ 118, 73, 171, 172, 129, 25, 178, 70, 206, 233, 142, 155, 18, 233, 25, 125, 80, 134, 203, 155, 80, 114, 25, 238, 149, 219, 17, 58, 145, 118, 120, 178, 115, 190, 214, 184, 227, 193, 116, 59, 113, 22, 230, 158, 34, 34, 149, 22, 63, 241, 202, 161, 104, 31, 172, 9, 18, 14, 202, 48, 117, 134, 225, 167 }
    let ctr_expected: [64]u8 = [64]u8{ 135, 77, 97, 145, 182, 32, 227, 38, 27, 239, 104, 100, 153, 13, 182, 206, 152, 6, 246, 107, 121, 112, 253, 255, 134, 23, 24, 123, 185, 255, 253, 255, 90, 228, 223, 62, 219, 213, 211, 94, 91, 79, 9, 2, 13, 176, 62, 171, 30, 3, 29, 218, 47, 190, 3, 209, 121, 33, 112, 160, 243, 0, 156, 238 }
    let (nk, nke) = cipher.aes_key(nist_key[0..])
    if nke != ok { os.exit(5i32) }
    // 5-6: CBC F.2.1 and back.
    var buf = nist_plain
    if cipher.cbc_encrypt(&nk, iv, buf[0..]) != ok || !same(buf[0..], cbc_expected[0..]) { os.exit(5i32) }
    if cipher.cbc_decrypt(&nk, iv, buf[0..]) != ok || !same(buf[0..], nist_plain[0..]) { os.exit(6i32) }
    // 7-8: CTR F.5.1, then seeking to block 3 reproduces the tail.
    buf = nist_plain
    cipher.ctr(&nk, ctr_iv, buf[0..])
    if !same(buf[0..], ctr_expected[0..]) { os.exit(7i32) }
    var tail: [16]u8 = zero
    i = 0usize
    while i < 16usize {
        tail[i] = nist_plain[48usize + i]
        i += 1usize
    }
    cipher.ctr_at(&nk, ctr_iv, 3u64, tail[0..])
    if !same(tail[0..], ctr_expected[48..]) { os.exit(8i32) }
    cipher.ctr(&nk, ctr_iv, buf[0..])
    if !same(buf[0..], nist_plain[0..]) { os.exit(8i32) }
    // 9-10: CBC with PKCS#7 over 37 bytes against cryptography, and unpadded back.
    let msg37: [37]u8 = [37]u8{ 3, 10, 17, 24, 31, 38, 45, 52, 59, 66, 73, 80, 87, 94, 101, 108, 115, 122, 129, 136, 143, 150, 157, 164, 171, 178, 185, 192, 199, 206, 213, 220, 227, 234, 241, 248, 255 }
    let cbc37: [48]u8 = [48]u8{ 15, 160, 42, 131, 64, 160, 104, 124, 164, 65, 51, 40, 160, 99, 237, 36, 138, 230, 31, 176, 223, 219, 104, 158, 62, 240, 34, 18, 79, 216, 82, 200, 84, 80, 106, 232, 212, 136, 67, 174, 26, 82, 106, 148, 54, 205, 251, 75 }
    var padded: [64]u8 = zero
    let (padded_len, pad_error) = cipher.pad_pkcs7(padded[0..], msg37[0..])
    if pad_error != ok || padded_len != 48usize || padded[47] != 11u8 { os.exit(9i32) }
    if cipher.cbc_encrypt(&nk, iv, padded[..48]) != ok || !same(padded[..48], cbc37[0..]) { os.exit(9i32) }
    if cipher.cbc_decrypt(&nk, iv, padded[..48]) != ok { os.exit(10i32) }
    let (plain_len, unpad_error) = cipher.unpad_pkcs7(padded[..48])
    if unpad_error != ok || plain_len != 37usize || !same(padded[..37], msg37[0..]) { os.exit(10i32) }
    // 11: ECB roundtrip.
    buf = nist_plain
    if cipher.ecb_encrypt(&nk, buf[0..]) != ok || same(buf[0..], nist_plain[0..]) { os.exit(11i32) }
    if cipher.ecb_decrypt(&nk, buf[0..]) != ok || !same(buf[0..], nist_plain[0..]) { os.exit(11i32) }
    // 12: RFC 8439 2.3.2 block.
    let block_nonce: [12]u8 = [12]u8{ 0, 0, 0, 9, 0, 0, 0, 74, 0, 0, 0, 0 }
    let block_expected: [64]u8 = [64]u8{ 16, 241, 231, 228, 209, 59, 89, 21, 80, 15, 221, 31, 163, 32, 113, 196, 199, 209, 244, 199, 51, 192, 104, 3, 4, 34, 170, 154, 195, 212, 108, 78, 210, 130, 100, 70, 7, 159, 170, 9, 20, 194, 215, 5, 217, 139, 2, 162, 181, 18, 156, 209, 222, 22, 78, 185, 203, 208, 131, 232, 162, 80, 60, 78 }
    var stream: [64]u8 = zero
    if cipher.chacha20_block(seq, 1u32, block_nonce, stream[0..]) != ok || !same(stream[0..], block_expected[0..]) { os.exit(12i32) }
    // 13: RFC 8439 2.4.2 sunscreen.
    let sun_nonce: [12]u8 = [12]u8{ 0, 0, 0, 0, 0, 0, 0, 74, 0, 0, 0, 0 }
    let sun = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
    let sun_expected: [114]u8 = [114]u8{ 110, 46, 53, 154, 37, 104, 249, 128, 65, 186, 7, 40, 221, 13, 105, 129, 233, 126, 122, 236, 29, 67, 96, 194, 10, 39, 175, 204, 253, 159, 174, 11, 249, 27, 101, 197, 82, 71, 51, 171, 143, 89, 61, 171, 205, 98, 179, 87, 22, 57, 214, 36, 230, 81, 82, 171, 143, 83, 12, 53, 159, 8, 97, 216, 7, 202, 13, 191, 80, 13, 106, 97, 86, 163, 142, 8, 138, 34, 182, 94, 82, 188, 81, 77, 22, 204, 248, 6, 129, 140, 233, 26, 183, 121, 55, 54, 90, 249, 11, 191, 116, 163, 91, 230, 180, 11, 142, 237, 242, 120, 94, 66, 135, 77 }
    var text: [114]u8 = zero
    i = 0usize
    while i < 114usize {
        text[i] = sun[i]
        i += 1usize
    }
    cipher.chacha20(seq, 1u32, sun_nonce, text[0..])
    if !same(text[0..], sun_expected[0..]) { os.exit(13i32) }
    cipher.chacha20(seq, 1u32, sun_nonce, text[0..])
    if !same(text[0..], sun) { os.exit(13i32) }
    // 14: HChaCha20 (draft-irtf-cfrg-xchacha 2.2.1).
    let hnonce: [16]u8 = [16]u8{ 0, 0, 0, 9, 0, 0, 0, 74, 0, 0, 0, 0, 49, 65, 89, 39 }
    let hexpected: [32]u8 = [32]u8{ 130, 65, 59, 66, 39, 178, 123, 254, 211, 14, 66, 80, 138, 135, 125, 115, 160, 249, 228, 213, 138, 116, 168, 83, 193, 46, 196, 19, 38, 211, 236, 220 }
    let sub = cipher.hchacha20(seq, hnonce)
    if !same(sub[0..], hexpected[0..]) { os.exit(14i32) }
    // 15: refusals -- a 20-byte key, an unaligned CBC, a short pad buffer, bad padding.
    let (_, bad_key) = cipher.aes_key(seq[..20])
    if bad_key != cipher.Invalid { os.exit(15i32) }
    if cipher.cbc_encrypt(&nk, iv, buf[..20]) != cipher.Invalid || cipher.cbc_decrypt(&nk, iv, buf[..20]) != cipher.Invalid { os.exit(15i32) }
    let (_, short) = cipher.pad_pkcs7(padded[..40], msg37[0..])
    if short != cipher.TooSmall { os.exit(15i32) }
    padded[47] = 12u8
    let (_, bad_pad) = cipher.unpad_pkcs7(padded[..48])
    if bad_pad != cipher.Invalid { os.exit(15i32) }
    try io.print("crypto cipher ok\n")
    ret ok
}
