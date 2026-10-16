// The WHATWG Encoding Standard's labels and its single-byte and Unicode decoders (tracker 1.4): `label_to_name` maps an
// encoding label ("latin1", " UTF8 ") to the canonical name, `decode` turns bytes into UTF-8 for the names this module can
// decode -- UTF-8, UTF-16LE/BE, the 27 single-byte encodings (windows-125x, ISO-8859-x, KOI8, IBM866, macintosh, ...),
// x-user-defined and replacement. The multi-byte encodings (gbk, gb18030, Big5, euc-jp, iso-2022-jp, shift_jis, euc-kr)
// are `e.text.charset_cjk`, which keeps their large tables out of programs that do not need them.
//
// Every malformed sequence becomes U+FFFD, as the Standard's decoders do. `decode_sniffing_bom` is the Standard's
// "decode" algorithm: a BOM wins over the given encoding and is removed.
//
// Memory: results are allocated in the arena given.

use e.mem
use e.str
use e.text.charset_table as table
use e.text.encoding as unicode_encoding

error Unsupported

fn lower_byte(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_ascii_space(c: u8) -> bool { ret c == 9u8 || c == 10u8 || c == 12u8 || c == 13u8 || c == 32u8 }

// The canonical name of an encoding label ("" and false when the Standard has no such encoding).
fn label_to_name(label: str) -> (str, bool) {
    var lo = 0usize
    var hi = label.len
    while lo < hi && is_ascii_space(label[lo]) { lo += 1usize }
    while hi > lo && is_ascii_space(label[hi - 1usize]) { hi -= 1usize }
    let want = label[lo..hi]
    if want.len == 0usize { ret ("", false) }
    let t = table.label_table()
    var start = 0usize
    while start < t.len {
        var end = start
        while end < t.len && t[end] != 10u8 { end += 1usize }
        // "label name"
        var sp = start
        while sp < end && t[sp] != 32u8 { sp += 1usize }
        if sp - start == want.len {
            var same = true
            var k = 0usize
            while k < want.len {
                if lower_byte(want[k]) != t[start + k] { same = false }
                k += 1usize
            }
            if same { ret (t[sp + 1usize..end], true) }
        }
        start = end + 1usize
    }
    ret ("", false)
}

// ASCII case-insensitive equality (the Standard's names are mixed case, the index names lower case).
fn eq_fold(x: str, y: str) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if lower_byte(x[i]) != lower_byte(y[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn is_single_byte(name: str) -> bool {
    var i = 0usize
    while i < table.single_count() {
        if eq_fold(table.single_name(i), name) { ret true }
        i += 1usize
    }
    ret false
}

fn put_scalar(out: []u8, at: usize, cp: u32) -> usize {
    ret unicode_encoding.write_utf8(cp, out, at)
}

fn entry(t: str, i: usize) -> u32 {
    let at = i * 3usize
    ret (u32(t[at]) << 16u32) | (u32(t[at + 1usize]) << 8u32) | u32(t[at + 2usize])
}

// Bytes in a single-byte encoding to UTF-8.
fn decode_single(a: *mem.Arena, index: usize, bytes: []const u8) -> (str, err) {
    let t = table.single_table(index)
    let (out, e) = mem.alloc[u8](a, bytes.len * 3usize + 4usize)
    if e != ok { ret ("", e) }
    var n = 0usize
    var i = 0usize
    while i < bytes.len {
        let b = bytes[i]
        i += 1usize
        if b < 128u8 {
            out[n] = b
            n += 1usize
        } else {
            var cp = entry(t, usize(b) - 128usize)
            if cp == 16777215u32 { cp = 65533u32 }
            n += put_scalar(out, n, cp)
        }
    }
    ret (out[0usize..n], ok)
}

fn decode_user_defined(a: *mem.Arena, bytes: []const u8) -> (str, err) {
    let (out, e) = mem.alloc[u8](a, bytes.len * 3usize + 4usize)
    if e != ok { ret ("", e) }
    var n = 0usize
    var i = 0usize
    while i < bytes.len {
        let b = bytes[i]
        i += 1usize
        if b < 128u8 {
            out[n] = b
            n += 1usize
        } else {
            n += put_scalar(out, n, 63360u32 + u32(b) - 128u32)
        }
    }
    ret (out[0usize..n], ok)
}

// Decodes `bytes` as encoding `name` (canonical, from `label_to_name`) into UTF-8.
fn decode(a: *mem.Arena, name: str, bytes: []const u8) -> (str, err) {
    if str.eq(name, "UTF-8") {
        let (text, e) = unicode_encoding.to_utf8(a, .Utf8, bytes, .Replace)
        ret (text, e)
    }
    if str.eq(name, "UTF-16LE") {
        let (text, e) = unicode_encoding.to_utf8(a, .Utf16Le, bytes, .Replace)
        ret (text, e)
    }
    if str.eq(name, "UTF-16BE") {
        let (text, e) = unicode_encoding.to_utf8(a, .Utf16Be, bytes, .Replace)
        ret (text, e)
    }
    if str.eq(name, "replacement") {
        if bytes.len == 0usize { ret ("", ok) }
        ret ("\xef\xbf\xbd", ok)
    }
    if str.eq(name, "x-user-defined") {
        let (text, e) = decode_user_defined(a, bytes)
        ret (text, e)
    }
    var i = 0usize
    while i < table.single_count() {
        if eq_fold(table.single_name(i), name) {
            let (text, e) = decode_single(a, i, bytes)
            ret (text, e)
        }
        i += 1usize
    }
    ret ("", Unsupported)
}

// The Standard's "decode": a UTF-8 or UTF-16 BOM overrides `name` and is removed.
fn decode_sniffing_bom(a: *mem.Arena, name: str, bytes: []const u8) -> (str, err) {
    if bytes.len >= 3usize && bytes[0usize] == 239u8 && bytes[1usize] == 187u8 && bytes[2usize] == 191u8 {
        let (text, e) = decode(a, "UTF-8", bytes[3usize..])
        ret (text, e)
    }
    if bytes.len >= 2usize && bytes[0usize] == 254u8 && bytes[1usize] == 255u8 {
        let (text, e) = decode(a, "UTF-16BE", bytes[2usize..])
        ret (text, e)
    }
    if bytes.len >= 2usize && bytes[0usize] == 255u8 && bytes[1usize] == 254u8 {
        let (text, e) = decode(a, "UTF-16LE", bytes[2usize..])
        ret (text, e)
    }
    let (text2, e2) = decode(a, name, bytes)
    ret (text2, e2)
}
