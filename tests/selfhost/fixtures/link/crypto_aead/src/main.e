// `e.crypto.aead`: AES-128-GCM and AES-256-GCM against NIST GCM test cases 4 and 16,
// ChaCha20-Poly1305 against RFC 8439 2.8.2, tampered ciphertext and aad refused, the
// short buffer, and the empty message. The vectors and a from-scratch reference are
// in vectors.py beside this fixture. Every check has its own exit code.
use e.os
use e.mem
use e.crypto.aead as aead

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
    let gcm_key128: [16]u8 = [16]u8{ 254, 255, 233, 146, 134, 101, 115, 28, 109, 106, 143, 148, 103, 48, 131, 8 }
    let gcm_plain: [60]u8 = [60]u8{ 217, 49, 50, 37, 248, 132, 6, 229, 165, 89, 9, 197, 175, 245, 38, 154, 134, 167, 169, 83, 21, 52, 247, 218, 46, 76, 48, 61, 138, 49, 138, 114, 28, 60, 12, 149, 149, 104, 9, 83, 47, 207, 14, 36, 73, 166, 181, 37, 177, 106, 237, 245, 170, 13, 230, 87, 186, 99, 123, 57 }
    let gcm_aad: [20]u8 = [20]u8{ 254, 237, 250, 206, 222, 173, 190, 239, 254, 237, 250, 206, 222, 173, 190, 239, 171, 173, 218, 210 }
    let gcm_nonce: [12]u8 = [12]u8{ 202, 254, 186, 190, 250, 206, 219, 173, 222, 202, 248, 136 }
    let gcm_sealed128: [76]u8 = [76]u8{ 66, 131, 30, 194, 33, 119, 116, 36, 75, 114, 33, 183, 132, 208, 212, 156, 227, 170, 33, 47, 44, 2, 164, 224, 53, 193, 126, 35, 41, 172, 161, 46, 33, 213, 20, 178, 84, 102, 147, 28, 125, 143, 106, 90, 172, 132, 170, 5, 27, 163, 11, 57, 106, 10, 172, 151, 61, 88, 224, 145, 91, 201, 79, 188, 50, 33, 165, 219, 148, 250, 233, 90, 231, 18, 26, 71 }
    let gcm_key256: [32]u8 = [32]u8{ 254, 255, 233, 146, 134, 101, 115, 28, 109, 106, 143, 148, 103, 48, 131, 8, 254, 255, 233, 146, 134, 101, 115, 28, 109, 106, 143, 148, 103, 48, 131, 8 }
    let gcm_sealed256: [76]u8 = [76]u8{ 82, 45, 193, 240, 153, 86, 125, 7, 244, 127, 55, 163, 42, 132, 66, 125, 100, 58, 140, 220, 191, 229, 192, 201, 117, 152, 162, 189, 37, 85, 209, 170, 140, 176, 142, 72, 89, 13, 187, 61, 167, 176, 139, 16, 86, 130, 136, 56, 197, 246, 30, 99, 147, 186, 122, 10, 188, 201, 246, 98, 118, 252, 110, 206, 15, 78, 23, 104, 205, 223, 136, 83, 187, 45, 85, 27 }
    let cp_key: [32]u8 = [32]u8{ 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159 }
    let cp_nonce: [12]u8 = [12]u8{ 7, 0, 0, 0, 64, 65, 66, 67, 68, 69, 70, 71 }
    let cp_aad: [12]u8 = [12]u8{ 80, 81, 82, 83, 192, 193, 194, 195, 196, 197, 198, 199 }
    let cp_plain: [114]u8 = [114]u8{ 76, 97, 100, 105, 101, 115, 32, 97, 110, 100, 32, 71, 101, 110, 116, 108, 101, 109, 101, 110, 32, 111, 102, 32, 116, 104, 101, 32, 99, 108, 97, 115, 115, 32, 111, 102, 32, 39, 57, 57, 58, 32, 73, 102, 32, 73, 32, 99, 111, 117, 108, 100, 32, 111, 102, 102, 101, 114, 32, 121, 111, 117, 32, 111, 110, 108, 121, 32, 111, 110, 101, 32, 116, 105, 112, 32, 102, 111, 114, 32, 116, 104, 101, 32, 102, 117, 116, 117, 114, 101, 44, 32, 115, 117, 110, 115, 99, 114, 101, 101, 110, 32, 119, 111, 117, 108, 100, 32, 98, 101, 32, 105, 116, 46 }
    let cp_sealed: [130]u8 = [130]u8{ 211, 26, 141, 52, 100, 142, 96, 219, 123, 134, 175, 188, 83, 239, 126, 194, 164, 173, 237, 81, 41, 110, 8, 254, 169, 226, 181, 167, 54, 238, 98, 214, 61, 190, 164, 94, 140, 169, 103, 18, 130, 250, 251, 105, 218, 146, 114, 139, 26, 113, 222, 10, 158, 6, 11, 41, 5, 214, 165, 182, 126, 205, 59, 54, 146, 221, 189, 127, 45, 119, 139, 140, 152, 3, 174, 227, 40, 9, 27, 88, 250, 179, 36, 228, 250, 214, 117, 148, 85, 133, 128, 139, 72, 49, 215, 188, 63, 244, 222, 240, 142, 75, 122, 157, 229, 118, 210, 101, 134, 206, 198, 75, 97, 22, 26, 225, 11, 89, 79, 9, 226, 106, 126, 144, 46, 203, 208, 96, 6, 145 }
    // NIST GCM test cases 4 (AES-128) and 16 (AES-256).
    var out: [160]u8 = zero
    let (n1, e1) = aead.aes128_gcm_seal(out[0..], gcm_key128, gcm_nonce, gcm_aad[0..], gcm_plain[0..])
    if e1 != ok || n1 != 76usize || !same(out[..n1], gcm_sealed128[0..]) { os.exit(1) }
    var back: [128]u8 = zero
    let (n2, e2) = aead.aes128_gcm_open(back[0..], gcm_key128, gcm_nonce, gcm_aad[0..], gcm_sealed128[0..])
    if e2 != ok || n2 != 60usize || !same(back[..n2], gcm_plain[0..]) { os.exit(2) }
    let (n3, e3) = aead.aes256_gcm_seal(out[0..], gcm_key256, gcm_nonce, gcm_aad[0..], gcm_plain[0..])
    if e3 != ok || n3 != 76usize || !same(out[..n3], gcm_sealed256[0..]) { os.exit(3) }
    let (n4, e4) = aead.aes256_gcm_open(back[0..], gcm_key256, gcm_nonce, gcm_aad[0..], gcm_sealed256[0..])
    if e4 != ok || n4 != 60usize || !same(back[..n4], gcm_plain[0..]) { os.exit(4) }
    // A flipped byte, a flipped aad byte, and a short buffer.
    var tampered = gcm_sealed128
    tampered[10] = tampered[10] ^ 1u8
    let (_, e5) = aead.aes128_gcm_open(back[0..], gcm_key128, gcm_nonce, gcm_aad[0..], tampered[0..])
    var other_aad = gcm_aad
    other_aad[0] = other_aad[0] ^ 1u8
    let (_, e6) = aead.aes128_gcm_open(back[0..], gcm_key128, gcm_nonce, other_aad[0..], gcm_sealed128[0..])
    var short: [8]u8 = zero
    let (_, e7) = aead.aes128_gcm_seal(short[0..], gcm_key128, gcm_nonce, gcm_aad[0..], gcm_plain[0..])
    if e5 != aead.Authentication || e6 != aead.Authentication || e7 != aead.TooSmall { os.exit(5) }
    // RFC 8439 2.8.2.
    let (n8, e8) = aead.chacha20_poly1305_seal(out[0..], cp_key, cp_nonce, cp_aad[0..], cp_plain[0..])
    if e8 != ok { os.exit(63) }
    if n8 != cp_sealed.len { os.exit(64) }
    if !same(out[..n8 - 16usize], cp_sealed[..cp_sealed.len - 16usize]) { os.exit(61) }
    if !same(out[n8 - 16usize..n8], cp_sealed[cp_sealed.len - 16usize..]) { os.exit(62) }
    let (n9, e9) = aead.chacha20_poly1305_open(back[0..], cp_key, cp_nonce, cp_aad[0..], cp_sealed[0..])
    if e9 != ok || n9 != cp_plain.len || !same(back[..n9], cp_plain[0..]) { os.exit(7) }
    var tampered2 = cp_sealed
    tampered2[cp_sealed.len - 1usize] = tampered2[cp_sealed.len - 1usize] ^ 128u8
    let (_, e10) = aead.chacha20_poly1305_open(back[0..], cp_key, cp_nonce, cp_aad[0..], tampered2[0..])
    if e10 != aead.Authentication { os.exit(8) }
    // Empty plaintext and aad still produce a verifiable tag.
    let none: [0]u8 = zero
    var just_tag: [16]u8 = zero
    let (n11, e11) = aead.chacha20_poly1305_seal(just_tag[0..], cp_key, cp_nonce, none[0..], none[0..])
    let (n12, e12) = aead.chacha20_poly1305_open(back[0..], cp_key, cp_nonce, none[0..], just_tag[0..])
    if e11 != ok || n11 != 16usize || e12 != ok || n12 != 0usize { os.exit(9) }
    os.exit(0)
    ret ok
}
