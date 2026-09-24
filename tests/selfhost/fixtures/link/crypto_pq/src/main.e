// Post-quantum schemes against Python oracles: SHAKE128/256 against hashlib,
// ML-KEM-768 (FIPS 203) against kyber-py for two seed sets -- ek, dk and c by their
// SHA-256, the shared key byte for byte, and the implicit-rejection key of a tampered
// ciphertext -- ML-DSA-44 key generation plus fail-closed signing, and XMSS (RFC
// 8391) against a byte-exact Python replica. Every check has its own exit code.
use e.os
use e.io
use e.mem
use e.crypto.hash as hash
use e.crypto.kx as kx
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

fn kem_check(d: [32]u8, z: [32]u8, m: [32]u8, ek_hash: [32]u8, dk_hash: [32]u8, ct_hash: [32]u8, key: [32]u8, reject: [32]u8, base: i32) {
    var ek: [1184]u8 = zero
    var dk: [2400]u8 = zero
    var c: [1088]u8 = zero
    let (sent, received, e) = kx.ml_kem(d, z, m, ek[0..], dk[0..], c[0..])
    if e != ok { os.exit(base) }
    let h_ek = hash.sha256(ek[0..])
    if !same(h_ek[0..], ek_hash[0..]) { os.exit(base + 1i32) }
    let h_dk = hash.sha256(dk[0..])
    if !same(h_dk[0..], dk_hash[0..]) { os.exit(base + 2i32) }
    let h_c = hash.sha256(c[0..])
    if !same(h_c[0..], ct_hash[0..]) { os.exit(base + 3i32) }
    if !same(sent[0..], key[0..]) { os.exit(base + 4i32) }
    if !same(received[0..], key[0..]) { os.exit(base + 5i32) }
    c[5] = c[5] ^ 1u8
    let (bad, e2) = kx.ml_kem_decaps(dk[0..], c[0..])
    if e2 != ok || !same(bad[0..], reject[0..]) { os.exit(base + 6i32) }
}

fn dsa_check(seed: [32]u8, message: []const u8, ctx: []const u8, pk_hash: [32]u8, sk_hash: [32]u8, base: i32) {
    var pk: [1312]u8 = zero
    var sk: [2560]u8 = zero
    var sig: [2420]u8 = zero
    let keygen_error = sign.ml_dsa_keygen(seed, pk[0..], sk[0..])
    if keygen_error != ok { os.exit(base) }
    let h_pk = hash.sha256(pk[0..])
    if !same(h_pk[0..], pk_hash[0..]) { os.exit(base + 1i32) }
    let h_sk = hash.sha256(sk[0..])
    if !same(h_sk[0..], sk_hash[0..]) { os.exit(base + 2i32) }
    if sign.ml_dsa_sign(sk[0..], message, ctx, sig[0..]) != sign.Unsupported { os.exit(base + 3i32) }
    let (good, full_error) = sign.ml_dsa(seed, message, ctx, pk[0..], sk[0..], sig[0..])
    if full_error != sign.Unsupported || good { os.exit(base + 4i32) }
    if sign.ml_dsa_verify(pk[0..], message, ctx, sig[0..]) { os.exit(base + 5i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1-2: SHAKE across block boundaries.
    let shake128_expect: [32]u8 = [32]u8{ 252, 95, 148, 64, 29, 55, 69, 202, 65, 216, 200, 188, 24, 175, 185, 168, 87, 154, 73, 250, 193, 188, 44, 196, 73, 37, 108, 121, 238, 78, 232, 132 }
    let shake256_expect: [32]u8 = [32]u8{ 163, 142, 55, 77, 138, 113, 11, 184, 210, 78, 98, 49, 25, 70, 43, 130, 191, 238, 40, 248, 67, 116, 215, 223, 127, 112, 212, 143, 30, 114, 99, 178 }
    var xof: [400]u8 = zero
    hash.shake128("", xof[0..])
    let h1 = hash.sha256(xof[0..])
    if !same(h1[0..], shake128_expect[0..]) { os.exit(1i32) }
    var s = hash.shake256_init()
    hash.shake_absorb(&s, "ab")
    hash.shake_absorb(&s, "c")
    hash.shake_squeeze(&s, xof[0..100])
    hash.shake_squeeze(&s, xof[100..300])
    let h2 = hash.sha256(xof[0..300])
    if !same(h2[0..], shake256_expect[0..]) { os.exit(2i32) }

    // 10-26: ML-KEM-768 over two seed sets.
    var d0: [32]u8 = zero
    var z0: [32]u8 = zero
    var m0: [32]u8 = zero
    var d1: [32]u8 = zero
    var z1: [32]u8 = zero
    var m1: [32]u8 = zero
    var i = 0usize
    while i < 32usize {
        d0[i] = u8(i & 255usize)
        z0[i] = u8((i + 32usize) & 255usize)
        m0[i] = u8((i + 64usize) & 255usize)
        d1[i] = u8((255usize - i) & 255usize)
        z1[i] = u8((i * 7usize) & 255usize)
        m1[i] = u8((i * 13usize + 5usize) & 255usize)
        i += 1usize
    }
    let kem0_ek_hash: [32]u8 = [32]u8{ 11, 121, 52, 200, 49, 37, 199, 136, 153, 94, 43, 166, 189, 118, 30, 51, 4, 107, 62, 64, 87, 27, 229, 62, 2, 51, 9, 162, 159, 57, 140, 201 }
    let kem0_dk_hash: [32]u8 = [32]u8{ 218, 194, 104, 189, 230, 168, 221, 35, 142, 152, 135, 17, 125, 107, 102, 78, 122, 122, 147, 80, 173, 107, 124, 8, 169, 72, 229, 4, 128, 149, 114, 165 }
    let kem0_ct_hash: [32]u8 = [32]u8{ 219, 244, 233, 170, 72, 176, 120, 173, 70, 236, 28, 156, 71, 189, 168, 194, 210, 254, 201, 208, 231, 162, 27, 212, 141, 34, 56, 162, 171, 237, 184, 86 }
    let kem0_key: [32]u8 = [32]u8{ 156, 221, 208, 137, 255, 231, 14, 57, 150, 231, 111, 124, 141, 6, 116, 109, 243, 77, 7, 232, 101, 123, 192, 252, 242, 187, 14, 28, 48, 132, 174, 161 }
    let kem0_reject: [32]u8 = [32]u8{ 223, 204, 71, 162, 187, 152, 227, 17, 80, 184, 106, 91, 30, 172, 229, 171, 191, 108, 16, 57, 172, 208, 126, 150, 79, 205, 216, 232, 249, 186, 35, 255 }
    kem_check(d0, z0, m0, kem0_ek_hash, kem0_dk_hash, kem0_ct_hash, kem0_key, kem0_reject, 10i32)
    let kem1_ek_hash: [32]u8 = [32]u8{ 79, 32, 159, 195, 229, 69, 179, 128, 223, 175, 44, 247, 134, 124, 115, 130, 98, 44, 172, 112, 160, 207, 102, 235, 243, 10, 150, 60, 125, 140, 0, 151 }
    let kem1_dk_hash: [32]u8 = [32]u8{ 205, 125, 217, 51, 96, 196, 76, 4, 201, 88, 4, 80, 198, 250, 220, 5, 188, 92, 193, 241, 59, 7, 64, 31, 47, 96, 125, 34, 42, 88, 252, 38 }
    let kem1_ct_hash: [32]u8 = [32]u8{ 219, 44, 169, 151, 95, 219, 144, 74, 209, 82, 63, 126, 19, 111, 90, 225, 209, 131, 235, 198, 36, 175, 154, 184, 62, 203, 82, 154, 38, 158, 218, 140 }
    let kem1_key: [32]u8 = [32]u8{ 230, 22, 213, 80, 178, 144, 190, 210, 2, 156, 240, 35, 104, 14, 132, 208, 156, 73, 169, 131, 27, 110, 31, 190, 89, 149, 37, 187, 90, 200, 152, 103 }
    let kem1_reject: [32]u8 = [32]u8{ 11, 248, 142, 192, 222, 166, 178, 220, 123, 59, 182, 228, 61, 108, 152, 239, 171, 144, 92, 131, 225, 22, 224, 242, 108, 168, 80, 234, 49, 99, 48, 246 }
    kem_check(d1, z1, m1, kem1_ek_hash, kem1_dk_hash, kem1_ct_hash, kem1_key, kem1_reject, 20i32)

    // 30-48: ML-DSA-44 keygen over two seeds; variable-time signing fails closed.
    var seed1: [32]u8 = zero
    i = 0usize
    while i < 32usize {
        seed1[i] = u8((i * 37usize + 11usize) & 255usize)
        i += 1usize
    }
    // seed set 0
    let dsa0_pk_hash: [32]u8 = [32]u8{ 159, 16, 118, 68, 193, 8, 69, 38, 175, 59, 200, 9, 134, 128, 176, 84, 153, 162, 50, 90, 100, 78, 56, 143, 180, 249, 112, 224, 88, 209, 157, 70 }
    let dsa0_sk_hash: [32]u8 = [32]u8{ 4, 191, 107, 159, 87, 145, 102, 166, 39, 150, 29, 252, 92, 59, 249, 113, 125, 248, 104, 219, 136, 134, 56, 86, 53, 108, 70, 104, 200, 181, 107, 11 }
    // seed set 1
    let dsa1_pk_hash: [32]u8 = [32]u8{ 141, 91, 243, 122, 93, 185, 12, 118, 20, 241, 160, 124, 151, 118, 80, 187, 73, 19, 200, 105, 241, 128, 217, 106, 139, 118, 33, 219, 116, 30, 71, 66 }
    let dsa1_sk_hash: [32]u8 = [32]u8{ 82, 60, 4, 180, 198, 251, 42, 181, 80, 214, 254, 93, 27, 211, 84, 113, 88, 66, 67, 218, 235, 49, 80, 26, 22, 35, 84, 244, 170, 177, 50, 121 }
    dsa_check(d0, "post-quantum message one", "", dsa0_pk_hash, dsa0_sk_hash, 30i32)
    dsa_check(seed1, "a second message under a context", "ctx", dsa1_pk_hash, dsa1_sk_hash, 40i32)

    // 50-60: XMSS-SHA2 at height 4 (the RFC parameter set at height 10 agrees with the
    // replica too but its 1024-leaf keygen takes 30 s here): the root, signatures at
    // index 0 and 5, the tampered and altered-message refusals, the exhausted key.
    // xmss h = 4, sig len 2308
    let xmss_root: [32]u8 = [32]u8{ 104, 201, 201, 123, 130, 234, 5, 42, 96, 83, 63, 201, 182, 77, 125, 255, 244, 246, 119, 67, 8, 32, 139, 47, 99, 224, 165, 8, 210, 45, 47, 235 }
    let xmss_sig0_hash: [32]u8 = [32]u8{ 45, 109, 51, 210, 152, 107, 37, 214, 141, 6, 246, 53, 59, 60, 106, 98, 38, 94, 125, 181, 96, 138, 103, 60, 134, 98, 15, 155, 54, 76, 197, 4 }
    let xmss_sig5_hash: [32]u8 = [32]u8{ 78, 56, 147, 173, 141, 101, 112, 191, 89, 43, 115, 224, 250, 64, 222, 150, 71, 198, 36, 108, 38, 223, 112, 129, 83, 98, 54, 68, 12, 44, 156, 151 }
    var nodes: [992]u8 = zero
    var xsig: [2308]u8 = zero
    let (xsk_value, xe) = sign.xmss_keygen(4usize, d0, z0, m0, nodes[0..])
    if xe != ok { os.exit(50i32) }
    var xsk = xsk_value
    if !same(xsk.root[0..], xmss_root[0..]) { os.exit(51i32) }
    let xmsg = "stateful hash-based signature"
    if sign.xmss_sign(&xsk, nodes[0..], xmsg, xsig[0..]) != ok { os.exit(52i32) }
    let h_x0 = hash.sha256(xsig[0..])
    if !same(h_x0[0..], xmss_sig0_hash[0..]) { os.exit(53i32) }
    let xpk = sign.xmss_public(xsk)
    if !sign.xmss_verify(xpk, xmsg, xsig[0..]) { os.exit(54i32) }
    xsk.index = 5u32
    if sign.xmss_sign(&xsk, nodes[0..], xmsg, xsig[0..]) != ok || xsk.index != 6u32 { os.exit(55i32) }
    let h_x5 = hash.sha256(xsig[0..])
    if !same(h_x5[0..], xmss_sig5_hash[0..]) { os.exit(56i32) }
    if !sign.xmss_verify(xpk, xmsg, xsig[0..]) { os.exit(57i32) }
    xsig[100] = xsig[100] ^ 1u8
    if sign.xmss_verify(xpk, xmsg, xsig[0..]) { os.exit(58i32) }
    xsig[100] = xsig[100] ^ 1u8
    if sign.xmss_verify(xpk, "stateful hash-based signaturex", xsig[0..]) { os.exit(59i32) }
    xsk.index = u32(16usize)
    if sign.xmss_sign(&xsk, nodes[0..], xmsg, xsig[0..]) != sign.Invalid { os.exit(60i32) }

    try io.print("crypto pq ok\n")
    ret ok
}
