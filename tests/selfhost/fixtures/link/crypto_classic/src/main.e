// `e.crypto.classic`: every cipher against a mixed-case sentence with digits and
// punctuation, each decrypt as a roundtrip, ROT13's classic vector, the LEMON
// Vigenere vector, Wikipedia's Playfair example, and the TooSmall/Invalid
// refusals. Expected strings come from ref.py in the scratch directory. Each
// check exits with its own code.
use e.crypto.classic as classic
use e.io
use e.mem
use e.os

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
    let s = "The Quick brown fox, jumps over 13 lazy dogs!"
    var out: [64]u8 = zero
    var back: [64]u8 = zero

    // 1: caesar, a shift past 26, and its decrypt.
    let (n1, e1) = classic.caesar(s, 7u32, out[..])
    if e1 != ok || !same(out[..n1], "Aol Xbpjr iyvdu mve, qbtwz vcly 13 shgf kvnz!") { os.exit(1i32) }
    let (m1, f1) = classic.caesar_decrypt(out[..n1], 7u32, back[..])
    if f1 != ok || !same(back[..m1], s) { os.exit(1i32) }
    let (n1b, e1b) = classic.caesar(s, 31u32, out[..])
    if e1b != ok || !same(out[..n1b], "Ymj Vznhp gwtbs ktc, ozrux tajw 13 qfed itlx!") { os.exit(1i32) }

    // 2: rot13 is its own inverse.
    let (n2, e2) = classic.rot13("Hello, World!", out[..])
    if e2 != ok || !same(out[..n2], "Uryyb, Jbeyq!") { os.exit(2i32) }
    let (m2, f2) = classic.rot13(out[..n2], back[..])
    if f2 != ok || !same(back[..m2], "Hello, World!") { os.exit(2i32) }

    // 3: atbash is an involution.
    let (n3, e3) = classic.atbash(s, out[..])
    if e3 != ok || !same(out[..n3], "Gsv Jfrxp yildm ulc, qfnkh levi 13 ozab wlth!") { os.exit(3i32) }
    let (m3, f3) = classic.atbash(out[..n3], back[..])
    if f3 != ok || !same(back[..m3], s) { os.exit(3i32) }

    // 4: vigenere: the LEMON vector, a mixed sentence with a lower-case key, bad keys.
    let (n4, e4) = classic.vigenere("ATTACKATDAWN", "LEMON", out[..])
    if e4 != ok || !same(out[..n4], "LXFOPVEFRNHR") { os.exit(4i32) }
    let (m4, f4) = classic.vigenere_decrypt(out[..n4], "lemon", back[..])
    if f4 != ok || !same(back[..m4], "ATTACKATDAWN") { os.exit(4i32) }
    let (n4b, e4b) = classic.vigenere(s, "Key", out[..])
    if e4b != ok || !same(out[..n4b], "Dlc Aygmo zbsux jmh, nswtq yzcb 13 pyjc bykq!") { os.exit(4i32) }
    let (m4b, f4b) = classic.vigenere_decrypt(out[..n4b], "Key", back[..])
    if f4b != ok || !same(back[..m4b], s) { os.exit(4i32) }
    let (_, bad_key) = classic.vigenere(s, "K3Y", out[..])
    if bad_key != classic.Invalid { os.exit(4i32) }
    let (_, empty_key) = classic.vigenere(s, "", out[..])
    if empty_key != classic.Invalid { os.exit(4i32) }

    // 5: substitution with a keyboard-order key, and key validation.
    let k26 = "QWERTYUIOPASDFGHJKLZXCVBNM"
    let (n5, e5) = classic.substitution(s, k26, out[..])
    if e5 != ok || !same(out[..n5], "Zit Jxoea wkgvf ygb, pxdhl gctk 13 sqmn rgul!") { os.exit(5i32) }
    let (m5, f5) = classic.substitution_decrypt(out[..n5], "qwertyuiopasdfghjklzxcvbnm", back[..])
    if f5 != ok || !same(back[..m5], s) { os.exit(5i32) }
    let (_, dup_key) = classic.substitution(s, "QWERTYUIOPASDFGHJKLZXCVBNQ", out[..])
    if dup_key != classic.Invalid { os.exit(5i32) }
    let (_, short_key) = classic.substitution(s, "QWERTY", out[..])
    if short_key != classic.Invalid { os.exit(5i32) }

    // 6: affine 5x+8 and its inverse; an even multiplier is refused.
    let (n6, e6) = classic.affine(s, 5u32, 8u32, out[..])
    if e6 != ok || !same(out[..n6], "Zrc Kewsg npaov hat, beqfu ajcp 13 lidy xamu!") { os.exit(6i32) }
    let (m6, f6) = classic.affine_decrypt(out[..n6], 5u32, 8u32, back[..])
    if f6 != ok || !same(back[..m6], s) { os.exit(6i32) }
    let (_, even_a) = classic.affine(s, 4u32, 1u32, out[..])
    if even_a != classic.Invalid { os.exit(6i32) }
    let (_, thirteen) = classic.affine_decrypt(s, 13u32, 1u32, out[..])
    if thirteen != classic.Invalid { os.exit(6i32) }

    // 7: rail fence with 3 rails, the identity rails, and no rails.
    let (n7, e7) = classic.rail_fence(s, 3usize, out[..])
    if e7 != ok || !same(out[..n7], "TQkof pv1ad!h uc rw o,jmsoe 3lz oseibnxu r yg") { os.exit(7i32) }
    let (m7, f7) = classic.rail_fence_decrypt(out[..n7], 3usize, back[..])
    if f7 != ok || !same(back[..m7], s) { os.exit(7i32) }
    let (n7b, e7b) = classic.rail_fence(s, 1usize, out[..])
    if e7b != ok || !same(out[..n7b], s) { os.exit(7i32) }
    let (n7c, e7c) = classic.rail_fence(s, 100usize, out[..])
    if e7c != ok || !same(out[..n7c], s) { os.exit(7i32) }
    let (m7c, f7c) = classic.rail_fence_decrypt(out[..n7c], 100usize, back[..])
    if f7c != ok || !same(back[..m7c], s) { os.exit(7i32) }
    let (_, no_rails) = classic.rail_fence(s, 0usize, out[..])
    if no_rails != classic.Invalid { os.exit(7i32) }

    // 8: playfair: Wikipedia's example, then a text with a doubled X and a J.
    let (n8, e8) = classic.playfair("Hide the gold in the tree stump", "playfair example", out[..])
    if e8 != ok || !same(out[..n8], "BMODZBXDNABEKUDMUIXMMOUVIF") { os.exit(8i32) }
    let (m8, f8) = classic.playfair_decrypt(out[..n8], "playfair example", back[..])
    if f8 != ok || !same(back[..m8], "HIDETHEGOLDINTHETREXESTUMP") { os.exit(8i32) }
    let (n8b, e8b) = classic.playfair("Boxxer J", "Monarchy", out[..])
    if e8b != ok || !same(out[..n8b], "HAWSUIAK") { os.exit(8i32) }
    let (m8b, f8b) = classic.playfair_decrypt(out[..n8b], "Monarchy", back[..])
    if f8b != ok || !same(back[..m8b], "BOXQXERI") { os.exit(8i32) }
    let (_, odd) = classic.playfair_decrypt("ABC", "Monarchy", out[..])
    if odd != classic.Invalid { os.exit(8i32) }

    // 9: TooSmall everywhere.
    let (_, r1) = classic.caesar(s, 1u32, out[..10])
    let (_, r2) = classic.atbash(s, out[..10])
    let (_, r3) = classic.vigenere(s, "KEY", out[..10])
    let (_, r4) = classic.substitution(s, k26, out[..10])
    let (_, r5) = classic.affine(s, 3u32, 0u32, out[..10])
    let (_, r6) = classic.rail_fence(s, 3usize, out[..10])
    let (_, r7) = classic.playfair(s, "key", out[..10])
    let (_, r8) = classic.playfair_decrypt("BMODZBXDNABEKUDMUIXMMOUVIF", "key", out[..10])
    if r1 != classic.TooSmall || r2 != classic.TooSmall || r3 != classic.TooSmall || r4 != classic.TooSmall { os.exit(9i32) }
    if r5 != classic.TooSmall || r6 != classic.TooSmall || r7 != classic.TooSmall || r8 != classic.TooSmall { os.exit(9i32) }

    try io.print("crypto classic ok\n")
    ret ok
}
