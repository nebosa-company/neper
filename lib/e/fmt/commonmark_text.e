// Text helpers for e.fmt.commonmark: a growable byte buffer, the character classes cmark uses, the
// HTML, href and XML escapers, entity decoding, and the scanners (cmark's re2c scanners written out
// by hand). A scanner takes the text and an offset and answers the length it matched, or 0; the end of
// the text stands where cmark's chunk has its NUL.
//
// Not here: footnote scanners (footnotes are not implemented).

use e.mem
use e.str
use e.fmt.html as html
use e.fmt.commonmark_punct as punct

type Buf = struct { a: *mem.Arena, d: []u8, n: usize, failed: bool }

fn buf_new(a: *mem.Arena, cap: usize) -> Buf {
    var b: Buf = zero
    b.a = a
    if cap > 0usize {
        let (d, e) = mem.alloc[u8](a, cap)
        if e != ok {
            b.failed = true
        } else {
            b.d = d
        }
    }
    ret b
}

fn grow(b: *Buf, extra: usize) {
    if b.failed { ret }
    if b.n + extra <= b.d.len { ret }
    var cap = b.d.len * 2usize
    if cap < b.n + extra { cap = b.n + extra }
    if cap < 64usize { cap = 64usize }
    let (d, e) = mem.alloc[u8](b.a, cap)
    if e != ok {
        b.failed = true
        ret
    }
    var i = 0usize
    while i < b.n {
        d[i] = b.d[i]
        i += 1usize
    }
    b.d = d
}

fn put(b: *Buf, s: str) {
    grow(b, s.len)
    if b.failed { ret }
    var i = 0usize
    while i < s.len {
        b.d[b.n + i] = s[i]
        i += 1usize
    }
    b.n += s.len
}

fn putc(b: *Buf, c: u8) {
    grow(b, 1usize)
    if b.failed { ret }
    b.d[b.n] = c
    b.n += 1usize
}

fn put_i32(b: *Buf, v: i32) {
    if v < 0i32 {
        putc(b, 45u8)
        put_i32(b, 0i32 - v)
        ret
    }
    if v >= 10i32 { put_i32(b, v / 10i32) }
    putc(b, u8(48i32 + v % 10i32))
}

// A scalar value as UTF-8.
fn put_scalar(b: *Buf, c: u32) {
    grow(b, 4usize)
    if b.failed { ret }
    if c < 128u32 {
        b.d[b.n] = u8(c)
        b.n += 1usize
        ret
    }
    if c < 2048u32 {
        b.d[b.n] = u8(192u32 | (c >> 6u32))
        b.d[b.n + 1usize] = u8(128u32 | (c & 63u32))
        b.n += 2usize
        ret
    }
    if c < 65536u32 {
        b.d[b.n] = u8(224u32 | (c >> 12u32))
        b.d[b.n + 1usize] = u8(128u32 | ((c >> 6u32) & 63u32))
        b.d[b.n + 2usize] = u8(128u32 | (c & 63u32))
        b.n += 3usize
        ret
    }
    b.d[b.n] = u8(240u32 | (c >> 18u32))
    b.d[b.n + 1usize] = u8(128u32 | ((c >> 12u32) & 63u32))
    b.d[b.n + 2usize] = u8(128u32 | ((c >> 6u32) & 63u32))
    b.d[b.n + 3usize] = u8(128u32 | (c & 63u32))
    b.n += 4usize
}

fn view(b: *const Buf) -> str {
    if b.n == 0usize { ret "" }
    ret b.d[0usize..b.n]
}

fn last_byte(b: *const Buf) -> u8 {
    if b.n == 0usize { ret 0u8 }
    ret b.d[b.n - 1usize]
}

// --- Characters.

// The byte at `i`, or 0 past the end: cmark's NUL terminator.
fn pk(s: str, i: usize) -> u8 {
    if i >= s.len { ret 0u8 }
    ret s[i]
}

fn is_space(c: u8) -> bool { ret c == 32u8 || (c >= 9u8 && c <= 13u8) }

fn is_blank_char(c: u8) -> bool { ret c == 32u8 || c == 9u8 }

fn is_line_end(c: u8) -> bool { ret c == 10u8 || c == 13u8 }

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }

fn is_alpha(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

fn is_alnum(c: u8) -> bool { ret is_digit(c) || is_alpha(c) }

fn is_xdigit(c: u8) -> bool { ret is_digit(c) || (c >= 65u8 && c <= 70u8) || (c >= 97u8 && c <= 102u8) }

fn is_punct(c: u8) -> bool {
    ret (c >= 33u8 && c <= 47u8) || (c >= 58u8 && c <= 64u8) || (c >= 91u8 && c <= 96u8) || (c >= 123u8 && c <= 126u8)
}

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_uspace(c: u32) -> bool {
    ret c == 9u32 || c == 10u32 || c == 12u32 || c == 13u32 || c == 32u32 || c == 160u32 || c == 5760u32 || (c >= 8192u32 && c <= 8202u32) || c == 8239u32 || c == 8287u32 || c == 12288u32
}

fn is_upunct(c: u32) -> bool {
    if c < 128u32 { ret is_punct(u8(c)) }
    ret punct.is_unicode_punct(c)
}

// Case-insensitive prefix test against a lower-case ASCII word.
fn starts_with_fold(s: str, at: usize, word: str) -> bool {
    if at + word.len > s.len { ret false }
    var i = 0usize
    while i < word.len {
        if lower(s[at + i]) != word[i] { ret false }
        i += 1usize
    }
    ret true
}

// --- Escaping into a buffer.

fn escape_html(b: *Buf, s: str) {
    var i = 0usize
    var org = 0usize
    while i < s.len {
        let c = s[i]
        var rep = ""
        if c == 38u8 { rep = "&amp;" } else {
        if c == 60u8 { rep = "&lt;" } else {
        if c == 62u8 { rep = "&gt;" } else {
        if c == 34u8 { rep = "&quot;" }
        }
        }
        }
        if rep.len > 0usize {
            put(b, s[org..i])
            put(b, rep)
            org = i + 1usize
        }
        i += 1usize
    }
    put(b, s[org..s.len])
}

fn href_safe(c: u8) -> bool {
    if c >= 128u8 { ret false }
    if is_alnum(c) { ret true }
    if c == 33u8 || c == 35u8 || c == 36u8 || c == 37u8 || c == 61u8 || c == 63u8 || c == 64u8 || c == 95u8 || c == 126u8 { ret true }
    ret c >= 40u8 && c <= 47u8 || c == 58u8 || c == 59u8
}

fn escape_href(b: *Buf, s: str) {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if href_safe(c) {
            putc(b, c)
        } else {
            if c == 38u8 {
                put(b, "&amp;")
            } else {
                if c == 39u8 {
                    put(b, "&#x27;")
                } else {
                    putc(b, 37u8)
                    let hex = "0123456789ABCDEF"
                    putc(b, hex[usize(c >> 4u8)])
                    putc(b, hex[usize(c & 15u8)])
                }
            }
        }
        i += 1usize
    }
}

fn escape_xml(b: *Buf, s: str) {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 {
            put(b, "&quot;")
        } else {
        if c == 38u8 {
            put(b, "&amp;")
        } else {
        if c == 60u8 {
            put(b, "&lt;")
        } else {
        if c == 62u8 {
            put(b, "&gt;")
        } else {
        if (c < 9u8) || c == 11u8 || c == 12u8 || (c >= 14u8 && c <= 31u8) {
            put(b, "\xef\xbf\xbd")
        } else {
        if (c == 190u8 || c == 191u8) && i >= 2usize && s[i - 2usize] == 239u8 && s[i - 1usize] == 191u8 {
            putc(b, 189u8)
        } else {
            putc(b, c)
        }
        }
        }
        }
        }
        }
        i += 1usize
    }
}

// --- Entities and backslash escapes.

// houdini_unescape_ent: `src` follows an `&`; answers the bytes consumed and appends the decoding,
// or answers 0 when it is not an entity.
fn entity_at(src: str, at: usize, b: *Buf) -> usize {
    let size = src.len - at
    if size >= 3usize && src[at] == 35u8 {
        var codepoint = 0u32
        var digits = 0usize
        var i = 0usize
        if is_digit(src[at + 1usize]) {
            i = 1usize
            while i < size && is_digit(src[at + i]) {
                codepoint = codepoint * 10u32 + u32(src[at + i] - 48u8)
                if codepoint >= 1114112u32 { codepoint = 1114112u32 }
                i += 1usize
            }
            digits = i - 1usize
        } else {
            if src[at + 1usize] == 120u8 || src[at + 1usize] == 88u8 {
                i = 2usize
                while i < size && is_xdigit(src[at + i]) {
                    let h = src[at + i]
                    var v = 0u32
                    if is_digit(h) { v = u32(h - 48u8) } else { v = u32((h | 32u8) - 87u8) }
                    codepoint = codepoint * 16u32 + v
                    if codepoint >= 1114112u32 { codepoint = 1114112u32 }
                    i += 1usize
                }
                digits = i - 2usize
            }
        }
        if digits >= 1usize && digits <= 8usize && i < size && src[at + i] == 59u8 {
            if codepoint == 0u32 || (codepoint >= 55296u32 && codepoint < 57344u32) || codepoint >= 1114112u32 { codepoint = 65533u32 }
            put_scalar(b, codepoint)
            ret i + 1usize
        }
        ret 0usize
    }
    var limit = size
    if limit > 32usize { limit = 32usize }
    var i = 2usize
    while i < limit {
        let c = src[at + i]
        if c == 32u8 { break }
        if c == 59u8 {
            let name = src[at..at + i + 1usize]
            let (value, nlen, found) = html.lookup_entity(name, 0usize, false)
            if found && nlen == i + 1usize {
                put(b, value)
                ret i + 1usize
            }
            break
        }
        i += 1usize
    }
    ret 0usize
}

// houdini_unescape_html_f: every entity decoded, the rest copied.
fn unescape_html(b: *Buf, s: str) {
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c != 38u8 {
            putc(b, c)
            i += 1usize
            continue
        }
        i += 1usize
        let used = entity_at(s, i, b)
        i += used
        if used == 0usize { putc(b, 38u8) }
    }
}

// cmark_strbuf_unescape on the bytes written since `from`: a backslash before ASCII punctuation goes.
fn unescape_backslashes(b: *Buf, from: usize) {
    var w = from
    var r = from
    while r < b.n {
        if b.d[r] == 92u8 && r + 1usize < b.n && is_punct(b.d[r + 1usize]) { r += 1usize }
        b.d[w] = b.d[r]
        w += 1usize
        r += 1usize
    }
    b.n = w
}

// --- Scanners.

fn scan_spacechars(s: str, at: usize) -> usize {
    var i = at
    while i < s.len && is_space(s[i]) { i += 1usize }
    ret i - at
}

// A URI scheme with its colon: a letter, 1 to 31 more of letters, digits, `.+-`, then `:`.
fn scan_scheme(s: str, at: usize) -> usize {
    if at >= s.len || !is_alpha(s[at]) { ret 0usize }
    var i = at + 1usize
    while i < s.len && (is_alnum(s[i]) || s[i] == 46u8 || s[i] == 43u8 || s[i] == 45u8) { i += 1usize }
    let k = i - at - 1usize
    if k < 1usize || k > 31usize || pk(s, i) != 58u8 { ret 0usize }
    ret i + 1usize - at
}

fn scan_autolink_uri(s: str, at: usize) -> usize {
    let sc = scan_scheme(s, at)
    if sc == 0usize { ret 0usize }
    var i = at + sc
    while i < s.len && s[i] > 32u8 && s[i] != 60u8 && s[i] != 62u8 { i += 1usize }
    if pk(s, i) != 62u8 { ret 0usize }
    ret i + 1usize - at
}

fn email_local_char(c: u8) -> bool {
    if is_alnum(c) { ret true }
    ret c == 46u8 || c == 33u8 || c == 35u8 || c == 36u8 || c == 37u8 || c == 38u8 || c == 39u8 || c == 42u8 || c == 43u8 || c == 47u8 || c == 61u8 || c == 63u8 || c == 94u8 || c == 95u8 || c == 96u8 || c == 123u8 || c == 124u8 || c == 125u8 || c == 126u8 || c == 45u8
}

fn scan_autolink_email(s: str, at: usize) -> usize {
    var i = at
    while i < s.len && email_local_char(s[i]) { i += 1usize }
    if i == at || pk(s, i) != 64u8 { ret 0usize }
    i += 1usize
    while true {
        let start = i
        while i < s.len && (is_alnum(s[i]) || s[i] == 45u8) { i += 1usize }
        let run = i - start
        if run == 0usize || run > 63usize || s[start] == 45u8 || s[i - 1usize] == 45u8 { ret 0usize }
        let c = pk(s, i)
        if c == 62u8 { ret i + 1usize - at }
        if c != 46u8 { ret 0usize }
        i += 1usize
    }
    ret 0usize
}

fn is_html_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 11u8 || c == 12u8 || c == 13u8 || c == 10u8 }

// opentag | closetag, after the `<`. Answers the length including the `>`.
fn scan_html_tag(s: str, at: usize) -> usize {
    var i = at
    if pk(s, i) == 47u8 {
        i += 1usize
        if !is_alpha(pk(s, i)) { ret 0usize }
        while is_alnum(pk(s, i)) || pk(s, i) == 45u8 { i += 1usize }
        while is_html_space(pk(s, i)) { i += 1usize }
        if pk(s, i) != 62u8 { ret 0usize }
        ret i + 1usize - at
    }
    if !is_alpha(pk(s, i)) { ret 0usize }
    while is_alnum(pk(s, i)) || pk(s, i) == 45u8 { i += 1usize }
    while true {
        // attribute* : one or more spaces, a name, an optional value
        var j = i
        while is_html_space(pk(s, j)) { j += 1usize }
        if j == i { break }
        let c = pk(s, j)
        if !(is_alpha(c) || c == 95u8 || c == 58u8) { break }
        j += 1usize
        while is_alnum(pk(s, j)) || pk(s, j) == 58u8 || pk(s, j) == 46u8 || pk(s, j) == 95u8 || pk(s, j) == 45u8 { j += 1usize }
        // optional value
        var k = j
        while is_html_space(pk(s, k)) { k += 1usize }
        if pk(s, k) == 61u8 {
            k += 1usize
            while is_html_space(pk(s, k)) { k += 1usize }
            let q = pk(s, k)
            var end = 0usize
            if q == 39u8 || q == 34u8 {
                var m = k + 1usize
                while m < s.len && s[m] != q { m += 1usize }
                if m < s.len { end = m + 1usize }
            } else {
                var m = k
                while m < s.len && !is_html_space(s[m]) && s[m] != 34u8 && s[m] != 39u8 && s[m] != 61u8 && s[m] != 60u8 && s[m] != 62u8 && s[m] != 96u8 { m += 1usize }
                if m > k { end = m }
            }
            if end > 0usize { j = end }
        }
        i = j
    }
    while is_html_space(pk(s, i)) { i += 1usize }
    if pk(s, i) == 47u8 { i += 1usize }
    if pk(s, i) != 62u8 { ret 0usize }
    ret i + 1usize - at
}

// After `<!`: `--` text `-->`, the text free of `--` and not ending in `-`.
fn scan_html_comment(s: str, at: usize) -> usize {
    if pk(s, at) != 45u8 || pk(s, at + 1usize) != 45u8 { ret 0usize }
    var i = at + 2usize
    while i < s.len {
        let c = s[i]
        if c == 45u8 {
            if pk(s, i + 1usize) == 45u8 && pk(s, i + 2usize) == 62u8 { ret i + 3usize - at }
            let n1 = pk(s, i + 1usize)
            if n1 != 45u8 && n1 != 0u8 {
                i += 2usize
            } else {
                if n1 == 45u8 {
                    let n2 = pk(s, i + 2usize)
                    if n2 != 0u8 && n2 != 62u8 {
                        i += 3usize
                    } else {
                        ret 0usize
                    }
                } else {
                    ret 0usize
                }
            }
        } else {
            i += 1usize
        }
    }
    ret 0usize
}

// After `<?`: the longest run of text that does not contain `?>`.
fn scan_html_pi(s: str, at: usize) -> usize {
    var i = at
    while i < s.len {
        let c = s[i]
        if c == 63u8 {
            let n = pk(s, i + 1usize)
            if n == 0u8 || n == 62u8 { break }
            i += 2usize
        } else {
            i += 1usize
        }
    }
    ret i - at
}

// After `<!`: uppercase letters, spaces, then anything up to `>`.
fn scan_html_declaration(s: str, at: usize) -> usize {
    var i = at
    while pk(s, i) >= 65u8 && pk(s, i) <= 90u8 { i += 1usize }
    if i == at { ret 0usize }
    let sp = i
    while is_html_space(pk(s, i)) { i += 1usize }
    if i == sp { ret 0usize }
    while i < s.len && s[i] != 62u8 { i += 1usize }
    ret i - at
}

// After `<![`: `CDATA[` and the longest text that does not contain `]]>`.
fn scan_html_cdata(s: str, at: usize) -> usize {
    if !str.starts_with(s[at..s.len], "CDATA[") { ret 0usize }
    var i = at + 6usize
    while i < s.len {
        let c = s[i]
        if c == 93u8 {
            let n1 = pk(s, i + 1usize)
            if n1 == 0u8 { break }
            if n1 == 93u8 {
                let n2 = pk(s, i + 2usize)
                if n2 == 0u8 || n2 == 62u8 { break }
                i += 3usize
            } else {
                i += 2usize
            }
        } else {
            i += 1usize
        }
    }
    ret i - at
}

fn block_tag_name(name: str) -> bool {
    let names = " address article aside base basefont blockquote body caption center col colgroup dd details dialog dir div dl dt fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hr html iframe legend li link main menu menuitem nav noframes ol optgroup option p param section source title summary table tbody td tfoot th thead tr track ul "
    if name.len == 0usize { ret false }
    var i = 0usize
    while i + name.len + 1usize < names.len {
        if names[i] == 32u8 && names[i + name.len + 1usize] == 32u8 {
            var k = 0usize
            while k < name.len && names[i + 1usize + k] == name[k] { k += 1usize }
            if k == name.len { ret true }
        }
        i += 1usize
    }
    ret false
}

// The type (1 to 6) of the HTML block that starts at `at`, or 0.
fn scan_html_block_start(s: str, at: usize) -> usize {
    if pk(s, at) != 60u8 { ret 0usize }
    if starts_with_fold(s, at + 1usize, "script") && is_html_space_or_gt(pk(s, at + 7usize)) { ret 1usize }
    if starts_with_fold(s, at + 1usize, "pre") && is_html_space_or_gt(pk(s, at + 4usize)) { ret 1usize }
    if starts_with_fold(s, at + 1usize, "textarea") && is_html_space_or_gt(pk(s, at + 9usize)) { ret 1usize }
    if starts_with_fold(s, at + 1usize, "style") && is_html_space_or_gt(pk(s, at + 6usize)) { ret 1usize }
    if pk(s, at + 1usize) == 33u8 && pk(s, at + 2usize) == 45u8 && pk(s, at + 3usize) == 45u8 { ret 2usize }
    if pk(s, at + 1usize) == 63u8 { ret 3usize }
    if pk(s, at + 1usize) == 33u8 && pk(s, at + 2usize) >= 65u8 && pk(s, at + 2usize) <= 90u8 { ret 4usize }
    if pk(s, at + 1usize) == 33u8 && pk(s, at + 2usize) == 91u8 && starts_with_fold(s, at + 3usize, "cdata[") { ret 5usize }
    var i = at + 1usize
    if pk(s, i) == 47u8 { i += 1usize }
    let start = i
    while is_alnum(pk(s, i)) { i += 1usize }
    if i == start || i - start > 12usize { ret 0usize }
    var lowered: [12]u8 = zero
    var k = 0usize
    while k < i - start {
        lowered[k] = lower(s[start + k])
        k += 1usize
    }
    if !block_tag_name(lowered[0usize..i - start]) { ret 0usize }
    let c = pk(s, i)
    if is_html_space(c) || c == 62u8 { ret 6usize }
    if c == 47u8 && pk(s, i + 1usize) == 62u8 { ret 6usize }
    ret 0usize
}

fn is_html_space_or_gt(c: u8) -> bool { ret is_html_space(c) || c == 62u8 }

// Type 7: a complete open or close tag alone on its line.
fn scan_html_block_start_7(s: str, at: usize) -> usize {
    if pk(s, at) != 60u8 { ret 0usize }
    let n = scan_html_tag(s, at + 1usize)
    if n == 0usize { ret 0usize }
    var i = at + 1usize + n
    while pk(s, i) == 32u8 || pk(s, i) == 9u8 || pk(s, i) == 12u8 { i += 1usize }
    let c = pk(s, i)
    if c == 13u8 || c == 10u8 { ret 7usize }
    ret 0usize
}

// Does the line from `at` to its end contain `needle` (lower case; ASCII case-insensitive)?
fn line_contains(s: str, at: usize, needle: str) -> bool {
    var i = at
    while i + needle.len <= s.len {
        if s[i] == 10u8 { ret false }
        if starts_with_fold(s, i, needle) { ret true }
        i += 1usize
    }
    ret false
}

fn scan_html_block_end(kind: usize, s: str, at: usize) -> bool {
    if kind == 1usize {
        ret line_contains(s, at, "</script>") || line_contains(s, at, "</pre>") || line_contains(s, at, "</textarea>") || line_contains(s, at, "</style>")
    }
    if kind == 2usize { ret line_contains(s, at, "-->") }
    if kind == 3usize { ret line_contains(s, at, "?>") }
    if kind == 4usize { ret line_contains(s, at, ">") }
    if kind == 5usize { ret line_contains(s, at, "]]>") }
    ret false
}

// A link title in quotes or parentheses; a delimiter may appear inside when a backslash precedes it.
fn scan_link_title(s: str, at: usize) -> usize {
    let open = pk(s, at)
    var close = 0u8
    if open == 34u8 || open == 39u8 { close = open } else {
    if open == 40u8 { close = 41u8 } else { ret 0usize }
    }
    var candidate = 0usize
    var i = at + 1usize
    while i < s.len {
        let c = s[i]
        let escaped = s[i - 1usize] == 92u8
        if c == close {
            candidate = i + 1usize - at
            if !escaped { break }
        } else {
            if close == 41u8 && c == 40u8 && !escaped { break }
        }
        i += 1usize
    }
    ret candidate
}

fn scan_atx_heading_start(s: str, at: usize) -> usize {
    var i = at
    while pk(s, i) == 35u8 { i += 1usize }
    let k = i - at
    if k < 1usize || k > 6usize { ret 0usize }
    let c = pk(s, i)
    if c == 32u8 || c == 9u8 {
        while pk(s, i) == 32u8 || pk(s, i) == 9u8 { i += 1usize }
        ret i - at
    }
    if c == 13u8 || c == 10u8 { ret i + 1usize - at }
    ret 0usize
}

// 1 for a line of `=`, 2 for a line of `-`, each with trailing blanks, else 0.
fn scan_setext_heading_line(s: str, at: usize) -> usize {
    let c = pk(s, at)
    if c != 61u8 && c != 45u8 { ret 0usize }
    var i = at
    while pk(s, i) == c { i += 1usize }
    while pk(s, i) == 32u8 || pk(s, i) == 9u8 { i += 1usize }
    if !is_line_end(pk(s, i)) { ret 0usize }
    if c == 61u8 { ret 1usize }
    ret 2usize
}

fn scan_open_code_fence(s: str, at: usize) -> usize {
    let c = pk(s, at)
    if c != 96u8 && c != 126u8 { ret 0usize }
    var i = at
    while pk(s, i) == c { i += 1usize }
    if i - at < 3usize { ret 0usize }
    var j = i
    while j < s.len && !is_line_end(s[j]) {
        if c == 96u8 && s[j] == 96u8 { ret 0usize }
        j += 1usize
    }
    if j >= s.len { ret 0usize }
    ret i - at
}

fn scan_close_code_fence(s: str, at: usize) -> usize {
    let c = pk(s, at)
    if c != 96u8 && c != 126u8 { ret 0usize }
    var i = at
    while pk(s, i) == c { i += 1usize }
    if i - at < 3usize { ret 0usize }
    var j = i
    while pk(s, j) == 32u8 || pk(s, j) == 9u8 { j += 1usize }
    if !is_line_end(pk(s, j)) { ret 0usize }
    ret i - at
}

// A URL that begins with a scheme a browser would run; an image data URI is fine.
fn scan_dangerous_url(s: str, at: usize) -> bool {
    if starts_with_fold(s, at, "data:image/") {
        if starts_with_fold(s, at + 11usize, "png") || starts_with_fold(s, at + 11usize, "gif") || starts_with_fold(s, at + 11usize, "jpeg") || starts_with_fold(s, at + 11usize, "webp") { ret false }
    }
    ret starts_with_fold(s, at, "javascript:") || starts_with_fold(s, at, "vbscript:") || starts_with_fold(s, at, "file:") || starts_with_fold(s, at, "data:")
}

// --- Table scanners (the GFM extension).

fn is_table_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 || c == 11u8 || c == 12u8 }

// One delimiter-row cell: blanks, an optional colon, one or more hyphens, an optional colon, blanks.
fn scan_table_marker(s: str, at: usize) -> usize {
    var i = at
    while is_table_space(pk(s, i)) { i += 1usize }
    if pk(s, i) == 58u8 { i += 1usize }
    let hy = i
    while pk(s, i) == 45u8 { i += 1usize }
    if i == hy { ret 0usize }
    if pk(s, i) == 58u8 { i += 1usize }
    while is_table_space(pk(s, i)) { i += 1usize }
    ret i - at
}

fn scan_table_start(s: str, at: usize) -> usize {
    var i = at
    if pk(s, i) == 124u8 { i += 1usize }
    while true {
        let m = scan_table_marker(s, i)
        if m == 0usize { ret 0usize }
        i += m
        if pk(s, i) == 124u8 {
            i += 1usize
            var j = i
            while is_table_space(pk(s, j)) { j += 1usize }
            if is_line_end(pk(s, j)) {
                i = j
                break
            }
        } else {
            break
        }
    }
    while is_table_space(pk(s, i)) { i += 1usize }
    let c = pk(s, i)
    if c == 13u8 {
        if pk(s, i + 1usize) != 10u8 { ret 0usize }
        ret i + 2usize - at
    }
    if c == 10u8 { ret i + 1usize - at }
    ret 0usize
}

// A cell: a run without a bare pipe or a line end. A pipe after a backslash stays in the cell.
fn scan_table_cell(s: str, at: usize) -> usize {
    var i = at
    while i < s.len {
        let c = s[i]
        if c == 13u8 || c == 10u8 { break }
        if c == 124u8 && !(i > at && s[i - 1usize] == 92u8) { break }
        i += 1usize
    }
    ret i - at
}

fn scan_table_cell_end(s: str, at: usize) -> usize {
    if pk(s, at) != 124u8 { ret 0usize }
    var i = at + 1usize
    while is_table_space(pk(s, i)) { i += 1usize }
    ret i - at
}

fn scan_table_row_end(s: str, at: usize) -> usize {
    var i = at
    while is_table_space(pk(s, i)) { i += 1usize }
    let c = pk(s, i)
    if c == 13u8 {
        if pk(s, i + 1usize) == 10u8 { ret i + 2usize - at }
        ret i + 1usize - at
    }
    if c == 10u8 { ret i + 1usize - at }
    ret 0usize
}

// What follows a task-list item's marker: blanks, `[ ]` or `[x]`, blanks. The end, or 0.
fn tasklist_tail(s: str, from: usize) -> usize {
    var i = from
    let sp = i
    while is_table_space(pk(s, i)) { i += 1usize }
    if i == sp { ret 0usize }
    if pk(s, i) != 91u8 || pk(s, i + 2usize) != 93u8 { ret 0usize }
    let m = pk(s, i + 1usize)
    if m != 32u8 && m != 120u8 { ret 0usize }
    i += 3usize
    let sp2 = i
    while is_table_space(pk(s, i)) { i += 1usize }
    if i == sp2 { ret 0usize }
    ret i
}

// A task-list marker at the start of a list item's line: a bullet or number and one more character,
// blanks, `[ ]` or `[x]`, blanks. The length, or 0.
fn scan_tasklist(s: str) -> usize {
    var i = 0usize
    while is_table_space(pk(s, i)) { i += 1usize }
    let c = pk(s, i)
    if c == 45u8 || c == 43u8 || c == 42u8 { ret tasklist_tail(s, i + 1usize) }
    let d = i
    while is_digit(pk(s, i)) { i += 1usize }
    if i == d { ret 0usize }
    if pk(s, i) != 0u8 && pk(s, i) != 10u8 {
        let r = tasklist_tail(s, i + 1usize)
        if r > 0usize { ret r }
    }
    if i - d >= 2usize { ret tasklist_tail(s, i) }
    ret 0usize
}
