// Phonetic codes of ASCII names into caller storage: Soundex (a letter and
// three digits), the original Metaphone and NYSIIS. Letters are folded to
// one case; anything else is ignored where the code says so. Each answers
// the code as a slice of `out` (`TooSmall` when it does not fit) and the
// empty string for an empty name.

error TooSmall

fn upper(c: u8) -> u8 {
    if c >= 97u8 && c <= 122u8 { ret c - 32u8 }
    ret c
}
fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}
fn is_vowel(c: u8) -> bool { ret c == 97u8 || c == 101u8 || c == 105u8 || c == 111u8 || c == 117u8 }
fn is_upper_vowel(c: u8) -> bool { ret c == 65u8 || c == 69u8 || c == 73u8 || c == 79u8 || c == 85u8 }
fn is_letter(c: u8) -> bool { ret c >= 65u8 && c <= 90u8 }

fn soundex_digit(c: u8) -> u8 {
    if c == 66u8 || c == 70u8 || c == 80u8 || c == 86u8 { ret 49u8 }
    if c == 67u8 || c == 71u8 || c == 74u8 || c == 75u8 || c == 81u8 || c == 83u8 || c == 88u8 || c == 90u8 { ret 50u8 }
    if c == 68u8 || c == 84u8 { ret 51u8 }
    if c == 76u8 { ret 52u8 }
    if c == 77u8 || c == 78u8 { ret 53u8 }
    if c == 82u8 { ret 54u8 }
    ret 0u8
}

// American Soundex: the first letter, then the digits of the next three coded
// letters, doubles collapsed (across H and W), padded with zeros; `out.len >= 4`.
fn soundex(name: str, out: []u8) -> (str, err) {
    if name.len == 0usize { ret ("", ok) }
    if out.len < 4usize { ret ("", TooSmall) }
    let first = upper(name[0usize])
    out[0usize] = first
    var count = 1usize
    var last = soundex_digit(first)
    var i = 1usize
    while i < name.len && count < 4usize {
        let c = upper(name[i])
        let digit = soundex_digit(c)
        if digit != 0u8 {
            if digit != last {
                out[count] = digit
                count += 1usize
            }
            last = digit
        } else if c != 72u8 && c != 87u8 {
            last = 0u8
        }
        i += 1usize
    }
    while count < 4usize {
        out[count] = 48u8
        count += 1usize
    }
    ret (out[..4usize], ok)
}

fn at(s: str, i: usize) -> u8 {
    if i < s.len { ret lower(s[i]) }
    ret 0u8
}
fn in_iey(c: u8) -> bool { ret c == 105u8 || c == 101u8 || c == 121u8 }
fn in_oa(c: u8) -> bool { ret c == 111u8 || c == 97u8 }

// The original Metaphone (Lawrence Philips, 1990) in its common form: initial
// KN, GN, PN, WR and AE lose their first letter, doubles other than CC
// collapse, and the transformation table maps each letter by its
// neighbours. The code is upper case, `0` standing for TH; `out.len >= name.len + 1`.
fn metaphone(name: str, out: []u8) -> (str, err) {
    if out.len < name.len + 1usize { ret ("", TooSmall) }
    var count = 0usize
    var i = 0usize
    let a0 = at(name, 0usize)
    let a1 = at(name, 1usize)
    if (a0 == 107u8 && a1 == 110u8) || (a0 == 103u8 && a1 == 110u8) || (a0 == 112u8 && a1 == 110u8) || (a0 == 119u8 && a1 == 114u8) || (a0 == 97u8 && a1 == 101u8) { i = 1usize }
    let start = i
    while i < name.len {
        let c = at(name, i)
        let next = at(name, i + 1usize)
        let after = at(name, i + 2usize)
        var previous = 0u8
        if i > start { previous = at(name, i - 1usize) }
        if c == next && c != 99u8 {
            i += 1usize
        } else if is_vowel(c) {
            if i == start || previous == 32u8 {
                out[count] = c
                count += 1usize
            }
            i += 1usize
        } else if c == 98u8 {
            // B is silent after M at the end of the word.
            if !(previous == 109u8 && next == 0u8) {
                out[count] = 98u8
                count += 1usize
            }
            i += 1usize
        } else if c == 99u8 {
            if (next == 105u8 && after == 97u8) || next == 104u8 {
                out[count] = 120u8
                count += 1usize
                i += 2usize
            } else if in_iey(next) {
                out[count] = 115u8
                count += 1usize
                i += 2usize
            } else {
                out[count] = 107u8
                count += 1usize
                i += 1usize
            }
        } else if c == 100u8 {
            if next == 103u8 && in_iey(after) {
                out[count] = 106u8
                count += 1usize
                i += 3usize
            } else {
                out[count] = 116u8
                count += 1usize
                i += 1usize
            }
        } else if c == 102u8 || c == 106u8 || c == 108u8 || c == 109u8 || c == 110u8 || c == 114u8 {
            out[count] = c
            count += 1usize
            i += 1usize
        } else if c == 103u8 {
            if in_iey(next) {
                out[count] = 106u8
                count += 1usize
                i += 1usize
            } else if next == 104u8 && after != 0u8 && !is_vowel(after) {
                i += 2usize
            } else if next == 110u8 && after == 0u8 {
                i += 2usize
            } else {
                out[count] = 107u8
                count += 1usize
                i += 1usize
            }
        } else if c == 104u8 {
            if i == start || is_vowel(next) || !is_vowel(previous) {
                out[count] = 104u8
                count += 1usize
            }
            i += 1usize
        } else if c == 107u8 {
            if i == start || previous != 99u8 {
                out[count] = 107u8
                count += 1usize
            }
            i += 1usize
        } else if c == 112u8 {
            if next == 104u8 {
                out[count] = 102u8
                count += 1usize
                i += 2usize
            } else {
                out[count] = 112u8
                count += 1usize
                i += 1usize
            }
        } else if c == 113u8 {
            out[count] = 107u8
            count += 1usize
            i += 1usize
        } else if c == 115u8 {
            if next == 104u8 {
                out[count] = 120u8
                count += 1usize
                i += 2usize
            } else if next == 105u8 && in_oa(after) {
                out[count] = 120u8
                count += 1usize
                i += 3usize
            } else {
                out[count] = 115u8
                count += 1usize
                i += 1usize
            }
        } else if c == 116u8 {
            if next == 105u8 && in_oa(after) {
                out[count] = 120u8
                count += 1usize
                i += 1usize
            } else if next == 104u8 {
                out[count] = 48u8
                count += 1usize
                i += 2usize
            } else {
                if next != 99u8 || after != 104u8 {
                    out[count] = 116u8
                    count += 1usize
                }
                i += 1usize
            }
        } else if c == 118u8 {
            out[count] = 102u8
            count += 1usize
            i += 1usize
        } else if c == 119u8 {
            if i == start && next == 104u8 {
                out[count] = 119u8
                count += 1usize
                i += 2usize
            } else {
                if is_vowel(next) {
                    out[count] = 119u8
                    count += 1usize
                }
                i += 1usize
            }
        } else if c == 120u8 {
            if i == start {
                if next == 104u8 || (next == 105u8 && in_oa(after)) {
                    out[count] = 120u8
                } else {
                    out[count] = 115u8
                }
                count += 1usize
            } else {
                out[count] = 107u8
                out[count + 1usize] = 115u8
                count += 2usize
            }
            i += 1usize
        } else if c == 121u8 {
            if is_vowel(next) {
                out[count] = 121u8
                count += 1usize
            }
            i += 1usize
        } else if c == 122u8 {
            out[count] = 115u8
            count += 1usize
            i += 1usize
        } else if c == 32u8 {
            if count > 0usize && out[count - 1usize] != 32u8 {
                out[count] = 32u8
                count += 1usize
            }
            i += 1usize
        } else {
            i += 1usize
        }
    }
    i = 0usize
    while i < count {
        out[i] = upper(out[i])
        i += 1usize
    }
    ret (out[..count], ok)
}

fn starts(s: []const u8, n: usize, p: str) -> bool {
    if n < p.len { ret false }
    var i = 0usize
    while i < p.len {
        if s[i] != p[i] { ret false }
        i += 1usize
    }
    ret true
}
fn ends(s: []const u8, n: usize, p: str) -> bool {
    if n < p.len { ret false }
    var i = 0usize
    while i < p.len {
        if s[n - p.len + i] != p[i] { ret false }
        i += 1usize
    }
    ret true
}

// NYSIIS (the original 1970 rules): prefix and suffix rewrites, then a
// left-to-right translation collapsing repeats, then the trailing S, AY
// and A rules. `out.len >= name.len + 2` and `scratch.len >= name.len + 1`.
fn nysiis(name: str, out: []u8, scratch: []u8) -> (str, err) {
    if name.len == 0usize { ret ("", ok) }
    if out.len < name.len + 2usize || scratch.len < name.len + 1usize { ret ("", TooSmall) }
    var s = scratch
    var n = name.len
    var i = 0usize
    while i < n {
        s[i] = upper(name[i])
        i += 1usize
    }
    if starts(s, n, "MAC") {
        s[1usize] = 67u8
    } else if starts(s, n, "KN") {
        i = 0usize
        while i + 1usize < n {
            s[i] = s[i + 1usize]
            i += 1usize
        }
        n -= 1usize
    } else if s[0usize] == 75u8 {
        s[0usize] = 67u8
    } else if starts(s, n, "PH") || starts(s, n, "PF") {
        s[0usize] = 70u8
        s[1usize] = 70u8
    } else if starts(s, n, "SCH") {
        s[1usize] = 83u8
        s[2usize] = 83u8
    }
    if ends(s, n, "IE") || ends(s, n, "EE") {
        s[n - 2usize] = 89u8
        n -= 1usize
    } else if ends(s, n, "DT") || ends(s, n, "RT") || ends(s, n, "RD") || ends(s, n, "NT") || ends(s, n, "ND") {
        s[n - 2usize] = 68u8
        n -= 1usize
    }
    out[0usize] = s[0usize]
    var count = 1usize
    i = 1usize
    while i < n {
        let ch = s[i]
        let before = s[i - 1usize]
        var next = 0u8
        if i + 1usize < n { next = s[i + 1usize] }
        var first = ch
        var second = 0u8
        if ch == 69u8 && next == 86u8 {
            first = 65u8
            second = 70u8
            i += 1usize
        } else if is_upper_vowel(ch) {
            first = 65u8
        } else if ch == 81u8 {
            first = 71u8
        } else if ch == 90u8 {
            first = 83u8
        } else if ch == 77u8 {
            first = 78u8
        } else if ch == 75u8 {
            if next == 78u8 { first = 78u8 } else { first = 67u8 }
        } else if ch == 83u8 && next == 67u8 && i + 2usize < n && s[i + 2usize] == 72u8 {
            first = 83u8
            second = 83u8
            i += 2usize
        } else if ch == 80u8 && next == 72u8 {
            first = 70u8
            i += 1usize
        } else if ch == 72u8 && (!is_upper_vowel(before) || next == 0u8 || !is_upper_vowel(next)) {
            if is_upper_vowel(before) { first = 65u8 } else { first = before }
        } else if ch == 87u8 && is_upper_vowel(before) {
            first = before
        }
        var tail = first
        if second != 0u8 { tail = second }
        if tail != out[count - 1usize] {
            out[count] = first
            count += 1usize
            if second != 0u8 {
                out[count] = second
                count += 1usize
            }
        }
        i += 1usize
    }
    if count > 1usize && out[count - 1usize] == 83u8 { count -= 1usize }
    if count >= 2usize && out[count - 2usize] == 65u8 && out[count - 1usize] == 89u8 {
        out[count - 2usize] = 89u8
        count -= 1usize
    }
    if count > 1usize && out[count - 1usize] == 65u8 { count -= 1usize }
    ret (out[..count], ok)
}
