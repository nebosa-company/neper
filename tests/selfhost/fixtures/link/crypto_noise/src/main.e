// `e.crypto.noise`: BLAKE2s (plain, keyed, HMAC, Noise HKDF) against hashlib, then an
// IK handshake with fixed keys whose two messages, handshake hash and transport keys
// equal a Python replica over `cryptography`, a transport message crossing with the
// nonce advancing and tampering refused, IKpsk2 agreeing on different keys with a wrong
// psk failing at message 2, and TooSmall. Every check has its own exit code.
use e.crypto.noise as noise
use e.io
use e.mem
use e.os

fn fold(bytes: []const u8) -> u64 {
    var x = 14695981039346656037u64
    var i = 0usize
    while i < bytes.len {
        x = (x ^ u64(bytes[i])) *% 1099511628211u64
        i += 1usize
    }
    ret x
}

fn fill(dst: []u8, seed: u64) {
    var state = seed
    var i = 0usize
    while i < dst.len {
        state = state *% 6364136223846793005u64 +% 1442695040888963407u64
        dst[i] = u8((state >> 33u32) & 255u64)
        i += 1usize
    }
}

fn key(seed: u64) -> [32]u8 {
    var k: [32]u8 = zero
    fill(k[0..], seed)
    ret k
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: BLAKE2s plain, keyed, HMAC and HKDF against hashlib.
    var buf: [200]u8 = zero
    fill(buf[0..], 1u64)
    let h0 = noise.blake2s(buf[..0usize])
    if fold(h0[0..]) != 2676443675549617779u64 { os.exit(1i32) }
    let h1 = noise.blake2s("abc")
    if fold(h1[0..]) != 240294868369380921u64 { os.exit(2i32) }
    let h2 = noise.blake2s(buf[0..])
    if fold(h2[0..]) != 11220147694863362121u64 { os.exit(3i32) }
    let k = key(2u64)
    let h3 = noise.blake2s_keyed(k[0..], buf[0..])
    if fold(h3[0..]) != 4884529236347742601u64 { os.exit(4i32) }
    let h4 = noise.hmac_blake2s(buf[0..], buf[..50usize])
    if fold(h4[0..]) != 4681382935406166590u64 { os.exit(5i32) }
    let kd = noise.hkdf3(k, buf[..64usize])
    if fold(kd.a[0..]) != 3335050650309013338u64 { os.exit(6i32) }
    if fold(kd.b[0..]) != 512861459333134221u64 { os.exit(7i32) }
    if fold(kd.c[0..]) != 3646946419122229848u64 { os.exit(8i32) }

    // 2: IK handshake with fixed keys equals the replica.
    let i_s = key(11u64)
    let r_s = key(12u64)
    let i_e = key(13u64)
    let r_e = key(14u64)
    let psk = key(15u64)
    let r_s_pub = noise.public_key(r_s)
    if fold(r_s_pub[0..]) != fold_expected_rs_pub() { os.exit(9i32) }
    var none: [0]u8 = zero
    var ini = noise.initialize("Noise_IK_25519_ChaChaPoly_BLAKE2s", true, "neper", i_s, r_s_pub, none[0..])
    var res = noise.initialize("Noise_IK_25519_ChaChaPoly_BLAKE2s", false, "neper", r_s, noise.zero_key(), none[0..])
    var m1: [128]u8 = zero
    var m2: [128]u8 = zero
    var payload: [64]u8 = zero
    let (n1, w1) = noise.write_message(&ini, "hello responder", m1[0..], i_e)
    if w1 != ok || n1 != 111usize { os.exit(10i32) }
    if fold(m1[..n1]) != 17650509138564174799u64 { os.exit(11i32) }
    let (p1, r1) = noise.read_message(&res, m1[..n1], payload[0..])
    if r1 != ok || p1 != 15usize || payload[0] != 104u8 || payload[14] != 114u8 { os.exit(12i32) }
    let (n2, w2) = noise.write_message(&res, "hi initiator!", m2[0..], r_e)
    if w2 != ok || n2 != 61usize { os.exit(13i32) }
    if fold(m2[..n2]) != 15205928923476762452u64 { os.exit(14i32) }
    let (p2, r2) = noise.read_message(&ini, m2[..n2], payload[0..])
    if r2 != ok || p2 != 13usize || payload[0] != 104u8 || payload[12] != 33u8 { os.exit(15i32) }
    var (ti, si) = noise.split(&ini)
    var (tr, sr) = noise.split(&res)
    if si != ok || sr != ok { os.exit(16i32) }
    if !noise.equal(ti.h[0..], tr.h[0..]) || fold(ti.h[0..]) != 166219325302973108u64 { os.exit(17i32) }
    if fold(ti.send.k[0..]) != 2432230809148567705u64 || fold(ti.recv.k[0..]) != 14253312446575218961u64 { os.exit(18i32) }
    if !noise.equal(ti.send.k[0..], tr.recv.k[0..]) || !noise.equal(ti.recv.k[0..], tr.send.k[0..]) { os.exit(19i32) }
    // Out of turn: the responder cannot write message 1, and the handshake is over.
    let (_, w3) = noise.write_message(&ini, none[0..], m1[0..], i_e)
    if w3 != noise.Invalid { os.exit(20i32) }

    // 3: a transport message crosses, the nonce advances, tampering is refused.
    var sealed: [64]u8 = zero
    let (tn, te) = noise.encrypt_with_ad(&ti.send, none[0..], "transport payload", sealed[0..])
    if te != ok || tn != 33usize || fold(sealed[..tn]) != 2888855611661403395u64 { os.exit(21i32) }
    if ti.send.n != 1u64 { os.exit(22i32) }
    let (on, oe) = noise.decrypt_with_ad(&tr.recv, none[0..], sealed[..tn], payload[0..])
    if oe != ok || on != 17usize || payload[0] != 116u8 || payload[16] != 100u8 || tr.recv.n != 1u64 { os.exit(23i32) }
    sealed[5] = sealed[5] ^ 1u8
    let (_, bad) = noise.decrypt_with_ad(&tr.recv, none[0..], sealed[..tn], payload[0..])
    if bad != noise.Authentication || tr.recv.n != 1u64 { os.exit(24i32) }
    // A second message under the advanced nonce differs from the first and still opens.
    let (tn2, te2) = noise.encrypt_with_ad(&ti.send, none[0..], "transport payload", sealed[0..])
    if te2 != ok || fold(sealed[..tn2]) == 2888855611661403395u64 { os.exit(25i32) }
    let (on2, oe2) = noise.decrypt_with_ad(&tr.recv, none[0..], sealed[..tn2], payload[0..])
    if oe2 != ok || on2 != 17usize || tr.recv.n != 2u64 { os.exit(26i32) }
    // Rekey on both sides keeps them in step.
    noise.rekey(&ti.send)
    noise.rekey(&tr.recv)
    if noise.equal(ti.send.k[0..], ti.recv.k[0..]) || !noise.equal(ti.send.k[0..], tr.recv.k[0..]) { os.exit(27i32) }

    // 4: IKpsk2 agrees on different keys; a wrong psk fails at message 2.
    var (pi, pr, pe) = noise.handshake_ik("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s", "neper", i_s, r_s, i_e, r_e, psk[0..], m1[0..], m2[0..])
    if pe != ok { os.exit(28i32) }
    if fold(pi.h[0..]) != 16038798623283293951u64 || !noise.equal(pi.h[0..], pr.h[0..]) { os.exit(29i32) }
    if fold(pi.send.k[0..]) != 563577588721011465u64 || fold(pi.recv.k[0..]) != 18439048492694358259u64 { os.exit(30i32) }
    if !noise.equal(pi.send.k[0..], pr.recv.k[0..]) || noise.equal(pi.send.k[0..], ti.send.k[0..]) { os.exit(31i32) }
    let wrong = key(16u64)
    var ini2 = noise.initialize("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s", true, "neper", i_s, r_s_pub, psk[0..])
    var res2 = noise.initialize("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s", false, "neper", r_s, noise.zero_key(), wrong[0..])
    let (q1, x1) = noise.write_message(&ini2, none[0..], m1[0..], i_e)
    if x1 != ok || q1 != 96usize || fold(m1[..q1]) == 17650509138564174799u64 { os.exit(32i32) }
    let (_, x2) = noise.read_message(&res2, m1[..q1], payload[0..])
    if x2 != ok { os.exit(33i32) }
    let (q2, x3) = noise.write_message(&res2, none[0..], m2[0..], r_e)
    if x3 != ok || q2 != 48usize { os.exit(34i32) }
    let (_, x4) = noise.read_message(&ini2, m2[..q2], payload[0..])
    if x4 != noise.Authentication { os.exit(35i32) }
    let (_, x5) = noise.split(&ini2)
    if x5 != noise.Invalid { os.exit(36i32) }

    // 5: TooSmall on every buffer.
    var ini3 = noise.initialize("Noise_IK_25519_ChaChaPoly_BLAKE2s", true, "neper", i_s, r_s_pub, none[0..])
    var res3 = noise.initialize("Noise_IK_25519_ChaChaPoly_BLAKE2s", false, "neper", r_s, noise.zero_key(), none[0..])
    let (_, y1) = noise.write_message(&ini3, "hello responder", m1[..110usize], i_e)
    if y1 != noise.TooSmall { os.exit(37i32) }
    let (_, y2) = noise.read_message(&res3, m1[..95usize], payload[0..])
    if y2 != noise.TooSmall { os.exit(38i32) }
    let (_, y3) = noise.encrypt_with_ad(&pi.send, none[0..], "transport payload", sealed[..32usize])
    if y3 != noise.TooSmall { os.exit(39i32) }
    try io.print("crypto noise ok\n")
    ret ok
}

fn fold_expected_rs_pub() -> u64 {
    let expected: [32]u8 = [32]u8{ 49, 34, 38, 107, 40, 240, 61, 203, 160, 2, 182, 174, 2, 9, 231, 115, 94, 96, 200, 207, 244, 158, 229, 79, 208, 38, 98, 14, 35, 171, 48, 60 }
    ret fold(expected[0..])
}
