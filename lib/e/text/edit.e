// Terraform-compatible string edits (L021), after petcow's interpreter: `substr` (by characters, a negative length
// meaning to the end), `chomp`, `indent`, `trim_prefix` and `trim_suffix`, `title`, `reverse` and the slash-pure
// path pair `base_name` and `dir_name`. `starts_with`, `ends_with` and `contains` are `e.str`'s and are not
// repeated.
//
// "Characters" are Unicode scalars, not bytes and not grapheme clusters: `substr("héllo", 1, 3)` is "éll", and
// `reverse` turns a combining sequence around. The functions that read characters (`substr`, `title`, `reverse`)
// refuse text that is not valid UTF-8 with `Invalid`; the byte-level ones (`chomp`, `trim_prefix`, `trim_suffix`,
// `indent`, `base_name`, `dir_name`) work on any bytes, because their delimiters are ASCII. `base_name` and
// `dir_name` never touch a file system and resolve no `.` or `..` (Go's `path.Base`/`path.Dir` without the
// cleaning): `base_name("/var/log/")` is "log", `base_name("/")` is "/", `dir_name("/foo")` is "/", and an empty
// path is "." for both. `title` capitalizes the first character of each space-separated word with Unicode's
// simple one-to-one uppercase (a letter that only has a multi-character uppercase, such as the German sharp s,
// is left as it is); `indent` puts `width` spaces after every newline, as Terraform does for every line but the
// first.

use e.mem
use e.text.utf8 as utf8
use e.text.unicode as unicode

error Invalid
error OffsetRange
error Negative

// `length` characters of `s` from character `offset`; a negative `length` means to the end, and a `length` past
// the end stops at the end. An `offset` below 0 or past the character count is `OffsetRange`. The result is a
// slice of `s`.
fn substr(s: str, offset: i64, length: i64) -> (str, err) {
    let (total, count_error) = utf8.count(s)
    if count_error != ok { ret ("", Invalid) }
    if offset < 0i64 || u64(offset) > u64(total) { ret ("", OffsetRange) }
    let start = usize(offset)
    var stop = total
    if length >= 0i64 && u64(length) < u64(total - start) { stop = start + usize(length) }
    let (from, from_error) = utf8.byte_offset(s, start)
    if from_error != ok { ret ("", Invalid) }
    let (to, to_error) = utf8.byte_offset(s, stop)
    if to_error != ok { ret ("", Invalid) }
    ret (s[from..to], ok)
}

// `s` without its trailing newline and carriage-return characters (any number, in any order).
fn chomp(s: str) -> str {
    var end = s.len
    while end > 0usize && (s[end - 1usize] == 10u8 || s[end - 1usize] == 13u8) { end -= 1usize }
    ret s[0usize..end]
}

// `s` without `prefix` at its start, or `s` itself.
fn trim_prefix(s: str, prefix: str) -> str {
    if prefix.len > s.len { ret s }
    var i = 0usize
    while i < prefix.len {
        if s[i] != prefix[i] { ret s }
        i += 1usize
    }
    ret s[prefix.len..s.len]
}

// `s` without `suffix` at its end, or `s` itself.
fn trim_suffix(s: str, suffix: str) -> str {
    if suffix.len > s.len { ret s }
    let from = s.len - suffix.len
    var i = 0usize
    while i < suffix.len {
        if s[from + i] != suffix[i] { ret s }
        i += 1usize
    }
    ret s[0usize..from]
}

// `s` with `width` spaces after every newline. A negative width is `Negative`.
fn indent(a: *mem.Arena, width: i64, s: str) -> (str, err) {
    if width < 0i64 { ret ("", Negative) }
    var newlines = 0usize
    var i = 0usize
    while i < s.len {
        if s[i] == 10u8 { newlines += 1usize }
        i += 1usize
    }
    if newlines == 0usize { ret (s, ok) }
    let (out, out_error) = mem.alloc[u8](a, s.len + newlines * usize(width))
    if out_error != ok { ret ("", out_error) }
    var n = 0usize
    i = 0usize
    while i < s.len {
        out[n] = s[i]
        n += 1usize
        if s[i] == 10u8 {
            var pad = 0i64
            while pad < width {
                out[n] = 32u8
                n += 1usize
                pad += 1i64
            }
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// The first character of each space-separated word in capitals (simple mapping).
fn title(a: *mem.Arena, s: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, s.len * 2usize + 4usize)
    if out_error != ok { ret ("", out_error) }
    var n = 0usize
    var off = 0usize
    var word_start = true
    while off < s.len {
        let (d, d_error) = utf8.decode(s, off)
        if d_error != ok { ret ("", Invalid) }
        var scalar = d.scalar
        if word_start { scalar = unicode.to_upper_simple(scalar) }
        word_start = d.scalar == 32u32
        var piece: [4]u8 = zero
        let (width, encode_error) = utf8.encode(scalar, piece[0..])
        if encode_error != ok { ret ("", Invalid) }
        var k = 0usize
        while k < usize(width) {
            out[n] = piece[k]
            n += 1usize
            k += 1usize
        }
        off += usize(d.width)
    }
    ret (out[0usize..n], ok)
}

// The characters of `s` in reverse order (by scalar).
fn reverse(a: *mem.Arena, s: str) -> (str, err) {
    if s.len == 0usize { ret (s, ok) }
    let (out, out_error) = mem.alloc[u8](a, s.len)
    if out_error != ok { ret ("", out_error) }
    var off = 0usize
    var at = s.len
    while off < s.len {
        let (d, d_error) = utf8.decode(s, off)
        if d_error != ok { ret ("", Invalid) }
        let width = usize(d.width)
        at -= width
        var k = 0usize
        while k < width {
            out[at + k] = s[off + k]
            k += 1usize
        }
        off += width
    }
    ret (out[0usize..s.len], ok)
}

// The last slash-separated component: "." for an empty path, "/" when only slashes, trailing slashes ignored.
fn base_name(path: str) -> str {
    if path.len == 0usize { ret "." }
    var end = path.len
    while end > 0usize && path[end - 1usize] == 47u8 { end -= 1usize }
    if end == 0usize { ret "/" }
    var start = end
    while start > 0usize && path[start - 1usize] != 47u8 { start -= 1usize }
    ret path[start..end]
}

// Everything before the last slash with trailing slashes trimmed: "." with no slash, "/" for the root.
fn dir_name(path: str) -> str {
    var last = path.len
    var found = false
    var i = path.len
    while i > 0usize && !found {
        i -= 1usize
        if path[i] == 47u8 {
            last = i
            found = true
        }
    }
    if !found { ret "." }
    if last == 0usize { ret "/" }
    var end = last
    while end > 0usize && path[end - 1usize] == 47u8 { end -= 1usize }
    if end == 0usize { ret "/" }
    ret path[0usize..end]
}
