// Classical pen-and-paper ciphers over ASCII letters: Caesar, ROT13, Atbash,
// Vigenere, simple substitution, affine, rail fence and Playfair. Every cipher
// writes into caller storage and answers the byte count written; `TooSmall`
// when `out` is short, `Invalid` for a bad key. The letter ciphers preserve
// case and copy non-letters through unchanged; rail fence transposes every
// byte; Playfair keeps letters only and answers upper case.
//
// Playfair convention: letters only, upper-cased, J is read as I; a repeated
// letter inside a pair is split with X (Q when the letter itself is X) and an
// odd tail is padded the same way. Non-letters in the key are ignored.
// `playfair_decrypt` undoes the square only: filler letters stay in the text.

error TooSmall
error Invalid

fn is_upper(c: u8) -> bool { ret c >= 65u8 && c <= 90u8 }
fn is_lower(c: u8) -> bool { ret c >= 97u8 && c <= 122u8 }
fn is_letter(c: u8) -> bool { ret is_upper(c) || is_lower(c) }

// Shifts a letter forward by `k` places (any `k`; reduced mod 26) keeping case.
fn shift_letter(c: u8, k: u32) -> u8 {
    if is_upper(c) { ret u8((u32(c) - 65u32 + k % 26u32) % 26u32) + 65u8 }
    if is_lower(c) { ret u8((u32(c) - 97u32 + k % 26u32) % 26u32) + 97u8 }
    ret c
}

fn caesar(text: []const u8, shift: u32, out: []u8) -> (usize, err) {
    if out.len < text.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < text.len {
        out[i] = shift_letter(text[i], shift)
        i += 1usize
    }
    ret (text.len, ok)
}
fn caesar_decrypt(text: []const u8, shift: u32, out: []u8) -> (usize, err) {
    let (n, e) = caesar(text, 26u32 - shift % 26u32, out)
    ret (n, e)
}
fn rot13(text: []const u8, out: []u8) -> (usize, err) {
    let (n, e) = caesar(text, 13u32, out)
    ret (n, e)
}

// A <-> Z, B <-> Y, ... (an involution).
fn atbash(text: []const u8, out: []u8) -> (usize, err) {
    if out.len < text.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if is_upper(c) {
            out[i] = 90u8 - (c - 65u8)
        } else if is_lower(c) {
            out[i] = 122u8 - (c - 97u8)
        } else {
            out[i] = c
        }
        i += 1usize
    }
    ret (text.len, ok)
}

// The key is letters only (either case) and advances only on letters of the text.
fn vigenere(text: []const u8, key: []const u8, out: []u8) -> (usize, err) {
    let (n, e) = vigenere_walk(text, key, out, false)
    ret (n, e)
}
fn vigenere_decrypt(text: []const u8, key: []const u8, out: []u8) -> (usize, err) {
    let (n, e) = vigenere_walk(text, key, out, true)
    ret (n, e)
}
fn vigenere_walk(text: []const u8, key: []const u8, out: []u8, decrypt: bool) -> (usize, err) {
    if out.len < text.len { ret (0usize, TooSmall) }
    if key.len == 0usize { ret (0usize, Invalid) }
    var j = 0usize
    while j < key.len {
        if !is_letter(key[j]) { ret (0usize, Invalid) }
        j += 1usize
    }
    j = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if is_letter(c) {
            var k = u32(key[j % key.len] | 32u8) - 97u32
            if decrypt { k = 26u32 - k }
            out[i] = shift_letter(c, k)
            j += 1usize
        } else {
            out[i] = c
        }
        i += 1usize
    }
    ret (text.len, ok)
}

// Validates a 26-letter permutation key and writes it upper-cased into `table`.
fn key_table(key: []const u8, table: []u8) -> err {
    if key.len != 26usize { ret Invalid }
    var seen: [26]u8 = zero
    var i = 0usize
    while i < 26usize {
        var c = key[i]
        if is_lower(c) { c -= 32u8 }
        if !is_upper(c) { ret Invalid }
        if seen[usize(c - 65u8)] != 0u8 { ret Invalid }
        seen[usize(c - 65u8)] = 1u8
        table[i] = c
        i += 1usize
    }
    ret ok
}
fn apply_table(text: []const u8, table: []const u8, out: []u8) -> (usize, err) {
    if out.len < text.len { ret (0usize, TooSmall) }
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if is_upper(c) {
            out[i] = table[usize(c - 65u8)]
        } else if is_lower(c) {
            out[i] = table[usize(c - 97u8)] + 32u8
        } else {
            out[i] = c
        }
        i += 1usize
    }
    ret (text.len, ok)
}
// `key` is a permutation of the 26 letters: plaintext A maps to key[0], B to key[1], ...
fn substitution(text: []const u8, key: []const u8, out: []u8) -> (usize, err) {
    var table: [26]u8 = zero
    let e = key_table(key, table[..])
    if e != ok { ret (0usize, e) }
    let (n, e2) = apply_table(text, table[..], out)
    ret (n, e2)
}
fn substitution_decrypt(text: []const u8, key: []const u8, out: []u8) -> (usize, err) {
    var table: [26]u8 = zero
    let e = key_table(key, table[..])
    if e != ok { ret (0usize, e) }
    var inverse: [26]u8 = zero
    var i = 0usize
    while i < 26usize {
        inverse[usize(table[i] - 65u8)] = u8(i) + 65u8
        i += 1usize
    }
    let (n, e2) = apply_table(text, inverse[..], out)
    ret (n, e2)
}

// The multiplicative inverse of `a` mod 26, or 0 when gcd(a, 26) != 1.
fn inverse26(a: u32) -> u32 {
    var x = 1u32
    while x < 26u32 {
        if ((a % 26u32) * x) % 26u32 == 1u32 { ret x }
        x += 1u32
    }
    ret 0u32
}
// x -> a*x + b mod 26; `Invalid` when `a` has no inverse.
fn affine(text: []const u8, a: u32, b: u32, out: []u8) -> (usize, err) {
    if inverse26(a) == 0u32 { ret (0usize, Invalid) }
    if out.len < text.len { ret (0usize, TooSmall) }
    let m = a % 26u32
    let add = b % 26u32
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if is_upper(c) {
            out[i] = u8((m * (u32(c) - 65u32) + add) % 26u32) + 65u8
        } else if is_lower(c) {
            out[i] = u8((m * (u32(c) - 97u32) + add) % 26u32) + 97u8
        } else {
            out[i] = c
        }
        i += 1usize
    }
    ret (text.len, ok)
}
fn affine_decrypt(text: []const u8, a: u32, b: u32, out: []u8) -> (usize, err) {
    let inv = inverse26(a)
    if inv == 0u32 { ret (0usize, Invalid) }
    // x = inv * (y - b) = inv * y + (26 - inv * b) mod 26
    let (n, e) = affine(text, inv, (26u32 - (inv * (b % 26u32)) % 26u32) % 26u32, out)
    ret (n, e)
}

// Zigzag transposition over every byte; `rails` of 1 is the identity.
fn rail_fence(text: []const u8, rails: usize, out: []u8) -> (usize, err) {
    let (n, e) = rail_walk(text, rails, out, false)
    ret (n, e)
}
fn rail_fence_decrypt(text: []const u8, rails: usize, out: []u8) -> (usize, err) {
    let (n, e) = rail_walk(text, rails, out, true)
    ret (n, e)
}
fn rail_walk(text: []const u8, rails: usize, out: []u8, decrypt: bool) -> (usize, err) {
    if rails == 0usize { ret (0usize, Invalid) }
    if out.len < text.len { ret (0usize, TooSmall) }
    if rails == 1usize {
        var i = 0usize
        while i < text.len {
            out[i] = text[i]
            i += 1usize
        }
        ret (text.len, ok)
    }
    // Rail r holds positions r, period - r, period + r, ... with the two step
    // sizes alternating (a zero step collapses to the full period on the edges).
    let period = 2usize * (rails - 1usize)
    var k = 0usize
    var r = 0usize
    while r < rails {
        var i = r
        var down = true
        while i < text.len {
            if decrypt { out[i] = text[k] } else { out[k] = text[i] }
            k += 1usize
            var step = 2usize * r
            if down { step = period - 2usize * r }
            if step == 0usize { step = period }
            i += step
            down = !down
        }
        r += 1usize
    }
    ret (text.len, ok)
}

// Fills the 5x5 square: the key's letters in order of first appearance, then
// the rest of the alphabet; J is folded into I and non-letters are skipped.
fn playfair_square(key: []const u8, square: []u8) {
    var seen: [26]u8 = zero
    var n = 0usize
    var i = 0usize
    while i < key.len + 26usize {
        var c = 0u8
        if i < key.len { c = key[i] } else { c = u8(i - key.len) + 65u8 }
        i += 1usize
        if is_lower(c) { c -= 32u8 }
        if !is_upper(c) { continue }
        if c == 74u8 { c = 73u8 }
        if seen[usize(c - 65u8)] != 0u8 { continue }
        seen[usize(c - 65u8)] = 1u8
        square[n] = c
        n += 1usize
    }
}
fn square_index(square: []const u8, c: u8) -> usize {
    var i = 0usize
    while i < 24usize {
        if square[i] == c { ret i }
        i += 1usize
    }
    ret 24usize
}
// Transforms the pairs in `buf[..n]` in place; `step` is 1 to encrypt, 4 to decrypt.
fn playfair_pairs(buf: []u8, n: usize, square: []const u8, step: usize) {
    var i = 0usize
    while i + 1usize < n {
        let a = square_index(square, buf[i])
        let b = square_index(square, buf[i + 1usize])
        let ra = a / 5usize
        let ca = a % 5usize
        let rb = b / 5usize
        let cb = b % 5usize
        if ra == rb {
            buf[i] = square[ra * 5usize + (ca + step) % 5usize]
            buf[i + 1usize] = square[rb * 5usize + (cb + step) % 5usize]
        } else if ca == cb {
            buf[i] = square[((ra + step) % 5usize) * 5usize + ca]
            buf[i + 1usize] = square[((rb + step) % 5usize) * 5usize + cb]
        } else {
            buf[i] = square[ra * 5usize + cb]
            buf[i + 1usize] = square[rb * 5usize + ca]
        }
        i += 2usize
    }
}
fn playfair_filler(c: u8) -> u8 {
    if c == 88u8 { ret 81u8 }
    ret 88u8
}
// Output is at most 2 * (letters in text) bytes, always an even count.
fn playfair(text: []const u8, key: []const u8, out: []u8) -> (usize, err) {
    var square: [25]u8 = zero
    playfair_square(key, square[..])
    var n = 0usize
    var i = 0usize
    while i < text.len {
        var c = text[i]
        i += 1usize
        if is_lower(c) { c -= 32u8 }
        if !is_upper(c) { continue }
        if c == 74u8 { c = 73u8 }
        if n % 2usize == 1usize && out[n - 1usize] == c {
            if n >= out.len { ret (0usize, TooSmall) }
            out[n] = playfair_filler(c)
            n += 1usize
        }
        if n >= out.len { ret (0usize, TooSmall) }
        out[n] = c
        n += 1usize
    }
    if n % 2usize == 1usize {
        if n >= out.len { ret (0usize, TooSmall) }
        out[n] = playfair_filler(out[n - 1usize])
        n += 1usize
    }
    playfair_pairs(out, n, square[..], 1usize)
    ret (n, ok)
}
// `Invalid` when the ciphertext holds an odd number of letters.
fn playfair_decrypt(text: []const u8, key: []const u8, out: []u8) -> (usize, err) {
    var square: [25]u8 = zero
    playfair_square(key, square[..])
    var n = 0usize
    var i = 0usize
    while i < text.len {
        var c = text[i]
        i += 1usize
        if is_lower(c) { c -= 32u8 }
        if !is_upper(c) { continue }
        if c == 74u8 { c = 73u8 }
        if n >= out.len { ret (0usize, TooSmall) }
        out[n] = c
        n += 1usize
    }
    if n % 2usize == 1usize { ret (0usize, Invalid) }
    playfair_pairs(out, n, square[..], 4usize)
    ret (n, ok)
}
