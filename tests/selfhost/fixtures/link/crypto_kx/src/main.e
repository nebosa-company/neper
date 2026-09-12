// `e.crypto.kx`: X25519 against RFC 7748 -- the section 6.1 Alice/Bob exchange (both
// public keys from their secrets, the expected secret from either side) and the first
// section 5.2 vector, then the small-order all-zero peer refused as InvalidKey. Every
// check has its own exit code.
use e.os
use e.mem
use e.crypto.kx as kx

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
    let a_priv: [32]u8 = [32]u8{ 119, 7, 109, 10, 115, 24, 165, 125, 60, 22, 193, 114, 81, 178, 102, 69, 223, 76, 47, 135, 235, 192, 153, 42, 177, 119, 251, 165, 29, 185, 44, 42 }
    let a_pub: [32]u8 = [32]u8{ 133, 32, 240, 9, 137, 48, 167, 84, 116, 139, 125, 220, 180, 62, 247, 90, 13, 191, 58, 13, 38, 56, 26, 244, 235, 164, 169, 142, 170, 155, 78, 106 }
    let b_priv: [32]u8 = [32]u8{ 93, 171, 8, 126, 98, 74, 138, 75, 121, 225, 127, 139, 131, 128, 14, 230, 111, 59, 177, 41, 38, 24, 182, 253, 28, 47, 139, 39, 255, 136, 224, 235 }
    let b_pub: [32]u8 = [32]u8{ 222, 158, 219, 125, 123, 125, 193, 180, 211, 91, 97, 194, 236, 228, 53, 55, 63, 131, 67, 200, 91, 120, 103, 77, 173, 252, 126, 20, 111, 136, 43, 79 }
    let expected: [32]u8 = [32]u8{ 74, 93, 157, 91, 164, 206, 45, 225, 114, 142, 59, 244, 128, 53, 15, 37, 224, 126, 33, 201, 71, 209, 158, 51, 118, 240, 155, 60, 30, 22, 23, 66 }
    let s1: [32]u8 = [32]u8{ 165, 70, 227, 107, 240, 82, 124, 157, 59, 22, 21, 75, 130, 70, 94, 221, 98, 20, 76, 10, 193, 252, 90, 24, 80, 106, 34, 68, 186, 68, 154, 196 }
    let u1: [32]u8 = [32]u8{ 230, 219, 104, 103, 88, 48, 48, 219, 53, 148, 193, 164, 36, 177, 95, 124, 114, 102, 36, 236, 38, 179, 53, 59, 16, 169, 3, 166, 208, 171, 28, 76 }
    let o1: [32]u8 = [32]u8{ 195, 218, 85, 55, 157, 233, 198, 144, 142, 148, 234, 77, 242, 141, 8, 79, 50, 236, 207, 3, 73, 28, 113, 247, 84, 180, 7, 85, 119, 162, 133, 82 }
    var alice: kx.X25519SecretKey = zero
    alice.bytes = a_priv
    var bob: kx.X25519SecretKey = zero
    bob.bytes = b_priv
    let alice_pub = kx.x25519_public_from_secret(alice)
    if !same(alice_pub.bytes[0..], a_pub[0..]) { os.exit(1) }
    let bob_pub = kx.x25519_public_from_secret(bob)
    if !same(bob_pub.bytes[0..], b_pub[0..]) { os.exit(2) }
    let (k1, e1) = kx.x25519_exchange(alice, bob_pub)
    if e1 != ok { os.exit(3) }
    if !same(k1.bytes[0..], expected[0..]) { os.exit(4) }
    let (k2, e2) = kx.x25519_exchange(bob, alice_pub)
    if e2 != ok { os.exit(5) }
    if !same(k2.bytes[0..], expected[0..]) { os.exit(6) }
    var sk: kx.X25519SecretKey = zero
    sk.bytes = s1
    var pk: kx.X25519PublicKey = zero
    pk.bytes = u1
    let (k3, e3) = kx.x25519_exchange(sk, pk)
    if e3 != ok { os.exit(7) }
    if !same(k3.bytes[0..], o1[0..]) { os.exit(8) }
    var small: kx.X25519PublicKey = zero
    let (k4, e4) = kx.x25519_exchange(alice, small)
    if e4 != kx.InvalidKey { os.exit(9) }
    if k4.bytes[0] != 0u8 { os.exit(10) }
    ret ok
}
