// `e.crypto.merkle`: the RFC 6962 test tree (eight leaves "", 00, 10, 2021,
// 3031, 40414243, 5051525354555657, 606162...6f) against a hashlib replica
// (ref.py): the empty root, the roots for n = 1..8 (first eight bytes), an
// inclusion proof for every leaf of the 8-tree verifying and a tampered leaf
// or wrong index not, consistency proofs 3->7, 4->8, 1->8 and 6->8 verifying
// and a wrong old root not, and the storage and index errors. Each check
// exits with its own code.

use e.crypto.merkle as merkle
use e.io
use e.mem
use e.os

fn first_u64(h: [32]u8) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < 8usize {
        v = (v << 8u32) | u64(h[i])
        i += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    var backing: [40]u8 = zero
    backing[0usize] = 0u8
    backing[1usize] = 16u8
    backing[2usize] = 32u8
    backing[3usize] = 33u8
    backing[4usize] = 48u8
    backing[5usize] = 49u8
    var i = 0usize
    while i < 4usize {
        backing[6usize + i] = u8(64usize + i)
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        backing[10usize + i] = u8(80usize + i)
        i += 1usize
    }
    i = 0usize
    while i < 16usize {
        backing[18usize + i] = u8(96usize + i)
        i += 1usize
    }
    var leaves: [8][]const u8 = zero
    leaves[0usize] = backing[0usize..0usize]
    leaves[1usize] = backing[0usize..1usize]
    leaves[2usize] = backing[1usize..2usize]
    leaves[3usize] = backing[2usize..4usize]
    leaves[4usize] = backing[4usize..6usize]
    leaves[5usize] = backing[6usize..10usize]
    leaves[6usize] = backing[10usize..18usize]
    leaves[7usize] = backing[18usize..34usize]

    // 1: the empty tree hashes to SHA-256("").
    var nodes: [480]u8 = zero
    let (empty, empty_error) = merkle.build(leaves[0usize..0usize], nodes[..])
    if empty_error != ok || first_u64(merkle.root(&empty)) != 16406829232824261652u64 { os.exit(1i32) }

    // 11..18: the roots for n = 1..8.
    let expected: [8]u64 = [8]u64{ 7940984811893783192, 18069921664435251564, 12589457608127770785, 15239868983339243863, 5637305102470974927, 8567673526270500368, 15976691081710444082, 6758172931874249129 }
    var n = 1usize
    while n <= 8usize {
        let (t, build_error) = merkle.build(leaves[0usize..n], nodes[..])
        if build_error != ok || t.nodes.len != merkle.nodes_required(n) { os.exit(i32(10usize + n)) }
        if first_u64(merkle.root(&t)) != expected[n - 1usize] { os.exit(i32(10usize + n)) }
        n += 1usize
    }

    // 3: every leaf of the 8-tree has a verifying inclusion proof.
    let (t8, t8_error) = merkle.build(leaves[0usize..8usize], nodes[..])
    if t8_error != ok { os.exit(3i32) }
    let r8 = merkle.root(&t8)
    var path: [96]u8 = zero
    i = 0usize
    while i < 8usize {
        let (len, path_error) = merkle.audit_path(&t8, i, path[..])
        if path_error != ok || len != 96usize { os.exit(3i32) }
        if !merkle.verify(r8, leaves[i], i, 8usize, path[..len]) { os.exit(3i32) }
        // 4: a tampered leaf and a wrong index do not verify.
        if merkle.verify(r8, backing[0usize..3usize], i, 8usize, path[..len]) { os.exit(4i32) }
        if merkle.verify(r8, leaves[i], (i + 1usize) % 8usize, 8usize, path[..len]) { os.exit(4i32) }
        i += 1usize
    }
    // 5: the seven-leaf tree's last leaf has a two-node path.
    var nodes7: [416]u8 = zero
    let (t7, t7_error) = merkle.build(leaves[0usize..7usize], nodes7[..])
    if t7_error != ok { os.exit(5i32) }
    let (len7, path7_error) = merkle.audit_path(&t7, 6usize, path[..])
    if path7_error != ok || len7 != 64usize || !merkle.verify(merkle.root(&t7), leaves[6usize], 6usize, 7usize, path[..len7]) { os.exit(5i32) }
    if merkle.verify(merkle.root(&t7), leaves[6usize], 6usize, 7usize, path[..96usize]) { os.exit(5i32) }

    // 6: consistency 3 -> 7 (four nodes) and 4 -> 8 (one node).
    var nodes3: [160]u8 = zero
    let (t3, _) = merkle.build(leaves[0usize..3usize], nodes3[..])
    var proof: [128]u8 = zero
    let (c37, c37_error) = merkle.consistency_proof(&t7, 3usize, proof[..])
    if c37_error != ok || c37 != 128usize { os.exit(6i32) }
    if !merkle.verify_consistency(merkle.root(&t3), merkle.root(&t7), 3usize, 7usize, proof[..c37]) { os.exit(6i32) }
    var nodes4: [224]u8 = zero
    let (t4, _) = merkle.build(leaves[0usize..4usize], nodes4[..])
    let (c48, c48_error) = merkle.consistency_proof(&t8, 4usize, proof[..])
    if c48_error != ok || c48 != 32usize { os.exit(6i32) }
    if !merkle.verify_consistency(merkle.root(&t4), r8, 4usize, 8usize, proof[..c48]) { os.exit(6i32) }

    // 7: consistency 1 -> 8 and 6 -> 8 (three nodes each), and 8 -> 8 is empty.
    let (t1, _) = merkle.build(leaves[0usize..1usize], nodes3[..])
    let (c18, _) = merkle.consistency_proof(&t8, 1usize, proof[..])
    if c18 != 96usize || !merkle.verify_consistency(merkle.root(&t1), r8, 1usize, 8usize, proof[..c18]) { os.exit(7i32) }
    var nodes6: [352]u8 = zero
    let (t6, _) = merkle.build(leaves[0usize..6usize], nodes6[..])
    let (c68, _) = merkle.consistency_proof(&t8, 6usize, proof[..])
    if c68 != 96usize || !merkle.verify_consistency(merkle.root(&t6), r8, 6usize, 8usize, proof[..c68]) { os.exit(7i32) }
    let (c88, _) = merkle.consistency_proof(&t8, 8usize, proof[..])
    if c88 != 0usize || !merkle.verify_consistency(r8, r8, 8usize, 8usize, proof[..0usize]) { os.exit(7i32) }

    // 8: a wrong old root (the 4-tree's for m = 3) does not verify.
    if merkle.verify_consistency(merkle.root(&t4), merkle.root(&t7), 3usize, 7usize, proof[..c37]) { os.exit(8i32) }
    if merkle.verify_consistency(merkle.root(&t3), r8, 3usize, 7usize, proof[..c37]) { os.exit(8i32) }

    // 9: storage and index errors.
    let (_, short_error) = merkle.build(leaves[0usize..8usize], nodes[..479usize])
    if short_error != merkle.TooSmall { os.exit(9i32) }
    let (_, index_error) = merkle.audit_path(&t8, 8usize, path[..])
    if index_error != merkle.Invalid { os.exit(9i32) }
    let (_, path_short) = merkle.audit_path(&t8, 0usize, path[..95usize])
    if path_short != merkle.TooSmall { os.exit(9i32) }
    let (_, m_error) = merkle.consistency_proof(&t8, 9usize, proof[..])
    if m_error != merkle.Invalid { os.exit(9i32) }
    let (_, proof_short) = merkle.consistency_proof(&t7, 3usize, proof[..127usize])
    if proof_short != merkle.TooSmall { os.exit(9i32) }

    try io.print("crypto merkle ok\n")
    ret ok
}
