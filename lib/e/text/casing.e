// Identifier and title conventions over ASCII into caller storage: `words`
// splits an identifier in any convention into its words, `convert` rewrites
// it in another (camelCase, PascalCase, snake_case, kebab-case,
// SCREAMING_SNAKE), `slug` folds text to a lowercase hyphenated URL-safe
// form and `title` capitalises principal words, keeping the small words a
// style guide lowercases. Bytes outside ASCII pass through untouched.

type Style = enum u8 { Camel, Pascal, Snake, Kebab, Screaming }
error TooSmall

fn is_upper(c: u8) -> bool { ret c >= 65u8 && c <= 90u8 }
fn is_lower(c: u8) -> bool { ret c >= 97u8 && c <= 122u8 }
fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }
fn is_alnum(c: u8) -> bool { ret is_upper(c) || is_lower(c) || is_digit(c) }
fn to_lower(c: u8) -> u8 {
    if is_upper(c) { ret c + 32u8 }
    ret c
}
fn to_upper(c: u8) -> u8 {
    if is_lower(c) { ret c - 32u8 }
    ret c
}

// A word starts at `i` (inside an alphanumeric run) at a lower-to-upper
// change or at the last capital of a run before a lowercase letter
// (`HTTPServer` -> `HTTP`, `Server`); digits stay with their neighbours.
fn boundary(name: str, i: usize) -> bool {
    if !is_upper(name[i]) { ret false }
    let before = name[i - 1usize]
    if is_lower(before) || is_digit(before) { ret true }
    ret is_upper(before) && i + 1usize < name.len && is_lower(name[i + 1usize])
}

// Split `name` into words at separators (anything not alphanumeric) and at
// case boundaries; `bounds` receives (start, end) pairs and the count is
// answered, `TooSmall` when `bounds.len < 2 * count`.
fn words(name: str, bounds: []usize) -> (usize, err) {
    var count = 0usize
    var i = 0usize
    while i < name.len {
        if !is_alnum(name[i]) {
            i += 1usize
        } else {
            let start = i
            i += 1usize
            while i < name.len && is_alnum(name[i]) && !boundary(name, i) { i += 1usize }
            if 2usize * count + 1usize >= bounds.len { ret (count, TooSmall) }
            bounds[2usize * count] = start
            bounds[2usize * count + 1usize] = i
            count += 1usize
        }
    }
    ret (count, ok)
}

// Rewrite `name` in `style`; `out.len >= name.len + 1` (a separator may join
// what a case boundary split), `bounds.len >= 2 * words`.
fn convert(name: str, style: Style, out: []u8, bounds: []usize) -> (str, err) {
    let (count, split_error) = words(name, bounds)
    if split_error != ok { ret ("", split_error) }
    if out.len < name.len + 1usize { ret ("", TooSmall) }
    var n = 0usize
    var w = 0usize
    while w < count {
        if w > 0usize {
            if style == .Snake || style == .Screaming {
                out[n] = 95u8
                n += 1usize
            } else if style == .Kebab {
                out[n] = 45u8
                n += 1usize
            }
        }
        var i = bounds[2usize * w]
        let end = bounds[2usize * w + 1usize]
        var first = true
        while i < end {
            var c = name[i]
            if style == .Screaming {
                c = to_upper(c)
            } else if style == .Pascal || (style == .Camel && w > 0usize) {
                if first { c = to_upper(c) } else { c = to_lower(c) }
            } else {
                c = to_lower(c)
            }
            out[n] = c
            n += 1usize
            first = false
            i += 1usize
        }
        w += 1usize
    }
    ret (out[..n], ok)
}

// A URL slug: ASCII letters lowercased and digits kept, every other run of
// bytes one hyphen, none at the ends; `out.len >= text.len`.
fn slug(text: str, out: []u8) -> (str, err) {
    if out.len < text.len { ret ("", TooSmall) }
    var n = 0usize
    var pending = false
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if is_alnum(c) {
            if pending && n > 0usize {
                out[n] = 45u8
                n += 1usize
            }
            pending = false
            out[n] = to_lower(c)
            n += 1usize
        } else {
            pending = true
        }
        i += 1usize
    }
    ret (out[..n], ok)
}

fn is_small_word(word: str) -> bool {
    let small = "a an and as at but by for if in nor of on or so the to up yet via"
    var i = 0usize
    while i < small.len {
        var j = i
        while j < small.len && small[j] != 32u8 { j += 1usize }
        if j - i == word.len {
            var k = 0usize
            var same = true
            while k < word.len && same {
                if to_lower(word[k]) != small[i + k] { same = false }
                k += 1usize
            }
            if same { ret true }
        }
        i = j + 1usize
    }
    ret false
}

// Title case: every word capitalised and the rest lowercased, except the
// articles, conjunctions and short prepositions of the usual style guides
// (`a an and as at but by for if in nor of on or so the to up yet via`),
// which stay lowercase unless first or last. Words are runs between
// spaces; `out.len >= text.len`.
fn title(text: str, out: []u8) -> (str, err) {
    if out.len < text.len { ret ("", TooSmall) }
    var i = 0usize
    while i < text.len {
        out[i] = text[i]
        i += 1usize
    }
    var count = 0usize
    i = 0usize
    while i < text.len {
        if text[i] == 32u8 {
            i += 1usize
        } else {
            let start = i
            while i < text.len && text[i] != 32u8 { i += 1usize }
            let last = i >= text.len
            let word = text[start..i]
            var k = start
            while k < i {
                out[k] = to_lower(text[k])
                k += 1usize
            }
            if count == 0usize || last || !is_small_word(word) {
                k = start
                while k < i && !is_alnum(text[k]) { k += 1usize }
                if k < i { out[k] = to_upper(text[k]) }
            }
            count += 1usize
        }
    }
    ret (out[..text.len], ok)
}
