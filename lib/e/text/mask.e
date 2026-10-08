// Filename-mask matching in the Delphi TMask / Windows file-mask style, over bytes with no
// allocation and no filesystem coupling. A mask is made of: `*` (any run, empty included),
// `?` (exactly one UTF-8 code point), `[set]` (one code point from the set: single characters
// and `lo-hi` ranges; a leading `!` or `^` negates; a `]` right after the `[` or `[!` is
// literal; a `-` first or last is literal) and `\c` (the next character literally, inside a set
// too). Every other byte matches itself. `case_sensitive == false` folds ASCII letters only.
// A mask is refused (`Invalid`) when a `[` is never closed, a `\` ends the mask, or a range
// runs backwards, whether or not matching would have reached it. `matches_any` takes masks
// separated by `;` (a `\;` is a literal semicolon). `*` backtracks only to the latest star, so
// matching is O(mask * text) and needs no storage.

error Invalid

type Item = struct { end: usize, kind: u8 }

const STAR: u8 = 1u8
const ANY: u8 = 2u8
const SET: u8 = 3u8
const LITERAL: u8 = 4u8

// One code point at `i`: its value and byte length. A malformed or truncated sequence is one
// byte, so every byte string is matchable.
fn decode(s: str, i: usize) -> (u32, usize) {
    let lead = s[i]
    if lead < 0x80u8 { ret (u32(lead), 1usize) }
    var width = 1usize
    var bits = u32(lead)
    if lead >= 0xC0u8 && lead < 0xE0u8 {
        width = 2usize
        bits = u32(lead & 0x1Fu8)
    } else if lead >= 0xE0u8 && lead < 0xF0u8 {
        width = 3usize
        bits = u32(lead & 0x0Fu8)
    } else if lead >= 0xF0u8 && lead < 0xF8u8 {
        width = 4usize
        bits = u32(lead & 0x07u8)
    }
    if width == 1usize || i + width > s.len { ret (u32(lead), 1usize) }
    var k = 1usize
    while k < width {
        let next = s[i + k]
        if next & 0xC0u8 != 0x80u8 { ret (u32(lead), 1usize) }
        bits = (bits << 6u32) | u32(next & 0x3Fu8)
        k += 1usize
    }
    ret (bits, width)
}

fn fold(c: u32, case_sensitive: bool) -> u32 {
    if !case_sensitive && c >= 65u32 && c <= 90u32 { ret c + 32u32 }
    ret c
}

// The item starting at `p` and where it ends, checked as it is read.
fn item(mask: str, p: usize) -> (Item, err) {
    let c = mask[p]
    if c == 42u8 { ret (Item { end: p + 1usize, kind: STAR }, ok) }
    if c == 63u8 { ret (Item { end: p + 1usize, kind: ANY }, ok) }
    if c == 92u8 {
        if p + 1usize >= mask.len { ret (zero, Invalid) }
        let (_, width) = decode(mask, p + 1usize)
        ret (Item { end: p + 1usize + width, kind: LITERAL }, ok)
    }
    if c == 91u8 {
        var q = p + 1usize
        if q < mask.len && (mask[q] == 33u8 || mask[q] == 94u8) { q += 1usize }
        var first = true
        while true {
            if q >= mask.len { ret (zero, Invalid) }
            if mask[q] == 93u8 && !first { ret (Item { end: q + 1usize, kind: SET }, ok) }
            first = false
            let (low, after_low, low_error) = set_char(mask, q)
            if low_error != ok { ret (zero, low_error) }
            q = after_low
            if q + 1usize < mask.len && mask[q] == 45u8 && mask[q + 1usize] != 93u8 {
                let (high, after_high, high_error) = set_char(mask, q + 1usize)
                if high_error != ok { ret (zero, high_error) }
                if high < low { ret (zero, Invalid) }
                q = after_high
            }
        }
    }
    let (_, width) = decode(mask, p)
    ret (Item { end: p + width, kind: LITERAL }, ok)
}

// A set member at `q`: its code point and the index after it.
fn set_char(mask: str, q: usize) -> (u32, usize, err) {
    if mask[q] == 92u8 {
        if q + 1usize >= mask.len { ret (0u32, 0usize, Invalid) }
        let (cp, width) = decode(mask, q + 1usize)
        ret (cp, q + 1usize + width, ok)
    }
    let (cp, width) = decode(mask, q)
    ret (cp, q + width, ok)
}

// Refuses a malformed mask without matching anything.
fn valid(mask: str) -> err {
    var p = 0usize
    while p < mask.len {
        let (it, item_error) = item(mask, p)
        if item_error != ok { ret item_error }
        p = it.end
    }
    ret ok
}

// Whether the one code point `cp` is matched by the item at `p` (a validated LITERAL or SET).
fn item_matches(mask: str, p: usize, it: Item, cp: u32, case_sensitive: bool) -> bool {
    if it.kind == LITERAL {
        var at = p
        if mask[p] == 92u8 { at = p + 1usize }
        let (literal, _) = decode(mask, at)
        ret fold(literal, case_sensitive) == fold(cp, case_sensitive)
    }
    var q = p + 1usize
    var negate = false
    if mask[q] == 33u8 || mask[q] == 94u8 {
        negate = true
        q += 1usize
    }
    var hit = false
    let value = fold(cp, case_sensitive)
    while q < it.end - 1usize {
        let (low, after_low, _) = set_char(mask, q)
        q = after_low
        var high = low
        if q + 1usize < mask.len && mask[q] == 45u8 && mask[q + 1usize] != 93u8 {
            let (range_high, after_high, _) = set_char(mask, q + 1usize)
            high = range_high
            q = after_high
        }
        if value >= fold(low, case_sensitive) && value <= fold(high, case_sensitive) { hit = true }
    }
    ret hit != negate
}

// Whether `mask` matches all of `text`. `Invalid` for a malformed mask.
fn matches(mask: str, text: str, case_sensitive: bool) -> (bool, err) {
    let checked = valid(mask)
    if checked != ok { ret (false, checked) }
    var p = 0usize
    var t = 0usize
    var star_p = 0usize
    var star_t = 0usize
    var have_star = false
    while t < text.len {
        var advanced = false
        if p < mask.len {
            let (it, _) = item(mask, p)
            if it.kind == STAR {
                have_star = true
                p = it.end
                star_p = p
                star_t = t
                advanced = true
            } else {
                let (cp, width) = decode(text, t)
                if it.kind == ANY || item_matches(mask, p, it, cp, case_sensitive) {
                    p = it.end
                    t += width
                    advanced = true
                }
            }
        }
        if !advanced {
            if !have_star { ret (false, ok) }
            let (_, skip) = decode(text, star_t)
            star_t += skip
            t = star_t
            p = star_p
        }
    }
    while p < mask.len && mask[p] == 42u8 { p += 1usize }
    ret (p == mask.len, ok)
}

// `matches` against each `;`-separated mask; the first malformed mask is the answer's error.
fn matches_any(masks: str, text: str, case_sensitive: bool) -> (bool, err) {
    var start = 0usize
    var i = 0usize
    var found = false
    while i <= masks.len {
        if i < masks.len && masks[i] == 92u8 {
            if i + 1usize >= masks.len { ret (false, Invalid) }
            i += 2usize
        } else {
            if i == masks.len || masks[i] == 59u8 {
                let end = i
                if end > masks.len { ret (false, Invalid) }
                let (hit, mask_error) = matches(masks[start..end], text, case_sensitive)
                if mask_error != ok { ret (false, mask_error) }
                if hit { found = true }
                start = i + 1usize
            }
            i += 1usize
        }
    }
    ret (found, ok)
}
