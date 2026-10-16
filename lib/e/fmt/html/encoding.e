// Choosing the character encoding of an HTML byte stream (tracker 1.4), after the HTML Standard's "determining the
// character encoding": a UTF-8 or UTF-16 byte order mark decides; else the encoding named by the transport layer (the
// `charset` of the HTTP Content-Type); else a prescan of the first 1024 bytes for `<meta charset>` and
// `<meta http-equiv="Content-Type" content="...; charset=...">`; else windows-1252. A meta that names UTF-16 means UTF-8
// (the stream is not UTF-16 or the prescan would not have read it), and x-user-defined means windows-1252.
//
// `determine` answers the canonical encoding name; `decode_document` decodes the bytes with it into UTF-8 text ready for
// `e.fmt.html.parse`. Encoding names are those of `e.text.charset`.
//
// Memory: `decode_document` allocates the text in the arena given; `determine` allocates nothing.

use e.mem
use e.str
use e.text.charset as charset
use e.text.charset_cjk as cjk

type Choice = struct { name: str, from_bom: bool }

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn is_space(c: u8) -> bool { ret c == 9u8 || c == 10u8 || c == 12u8 || c == 13u8 || c == 32u8 }

fn is_letter(c: u8) -> bool { ret (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) }

// Whether the bytes at `at` spell `word` ignoring case.
fn matches_at(b: []const u8, at: usize, word: str) -> bool {
    if at + word.len > b.len { ret false }
    var i = 0usize
    while i < word.len {
        if lower(b[at + i]) != word[i] { ret false }
        i += 1usize
    }
    ret true
}

// The position of `needle` in `b` from `from`, or the length.
fn find_bytes(b: []const u8, from: usize, needle: str) -> usize {
    var i = from
    while i + needle.len <= b.len {
        if matches_at(b, i, needle) { ret i }
        i += 1usize
    }
    ret b.len
}

// One attribute at `pos`: its name and value (lower-cased) and the position after it; `more` is false at the end of the tag.
type Attr = struct { name_lo: usize, name_hi: usize, value_lo: usize, value_hi: usize, next: usize, more: bool }

fn get_attribute(b: []const u8, pos_in: usize) -> Attr {
    var pos = pos_in
    var a = Attr { name_lo: 0usize, name_hi: 0usize, value_lo: 0usize, value_hi: 0usize, next: pos, more: false }
    while pos < b.len && (is_space(b[pos]) || b[pos] == 47u8) { pos += 1usize }
    if pos >= b.len || b[pos] == 62u8 {
        a.next = pos
        ret a
    }
    a.more = true
    a.name_lo = pos
    // The name.
    while true {
        if pos >= b.len {
            a.name_hi = pos
            a.next = pos
            ret a
        }
        let c = b[pos]
        if c == 61u8 && pos > a.name_lo {
            a.name_hi = pos
            pos += 1usize
            break
        }
        if is_space(c) {
            a.name_hi = pos
            while pos < b.len && is_space(b[pos]) { pos += 1usize }
            if pos >= b.len || b[pos] != 61u8 {
                a.next = pos
                ret a
            }
            pos += 1usize
            break
        }
        if c == 47u8 || c == 62u8 {
            a.name_hi = pos
            a.next = pos
            ret a
        }
        pos += 1usize
    }
    // The value.
    while pos < b.len && is_space(b[pos]) { pos += 1usize }
    if pos >= b.len {
        a.next = pos
        ret a
    }
    let q = b[pos]
    if q == 34u8 || q == 39u8 {
        pos += 1usize
        a.value_lo = pos
        while pos < b.len && b[pos] != q { pos += 1usize }
        a.value_hi = pos
        if pos < b.len { pos += 1usize }
        a.next = pos
        ret a
    }
    if q == 62u8 {
        a.next = pos
        ret a
    }
    a.value_lo = pos
    while pos < b.len && !is_space(b[pos]) && b[pos] != 62u8 { pos += 1usize }
    a.value_hi = pos
    a.next = pos
    ret a
}

fn eq_lower(b: []const u8, lo: usize, hi: usize, word: str) -> bool {
    if hi - lo != word.len { ret false }
    var i = 0usize
    while i < word.len {
        if lower(b[lo + i]) != word[i] { ret false }
        i += 1usize
    }
    ret true
}

// The encoding named in a `content` value like "text/html; charset=utf-8" ("" when none).
fn charset_in_content(b: []const u8, lo: usize, hi: usize) -> str {
    var at = lo
    while at < hi {
        let f = find_bytes(b[0usize..hi], at, "charset")
        if f >= hi { ret "" }
        var p = f + 7usize
        while p < hi && is_space(b[p]) { p += 1usize }
        if p >= hi || b[p] != 61u8 {
            at = f + 1usize
            continue
        }
        p += 1usize
        while p < hi && is_space(b[p]) { p += 1usize }
        if p >= hi { ret "" }
        var start = p
        var end = hi
        if b[p] == 34u8 || b[p] == 39u8 {
            let q = b[p]
            start = p + 1usize
            end = start
            while end < hi && b[end] != q { end += 1usize }
            if end >= hi { ret "" }
        } else {
            end = start
            while end < hi && !is_space(b[end]) && b[end] != 59u8 { end += 1usize }
        }
        let (name, good) = charset.label_to_name(str_of(b, start, end))
        if good { ret name }
        ret ""
    }
    ret ""
}

fn str_of(b: []const u8, lo: usize, hi: usize) -> str { ret b[lo..hi] }

// The prescan: the encoding named by a `<meta>` in the first 1024 bytes, "" when none.
fn prescan(b_all: []const u8) -> str {
    var limit = b_all.len
    if limit > 1024usize { limit = 1024usize }
    let b = b_all[0usize..limit]
    var pos = 0usize
    while pos < b.len {
        if matches_at(b, pos, "<!--") {
            let e = find_bytes(b, pos + 2usize, "-->")
            if e >= b.len { ret "" }
            pos = e + 3usize
            continue
        }
        if matches_at(b, pos, "<meta") && pos + 5usize < b.len && (is_space(b[pos + 5usize]) || b[pos + 5usize] == 47u8) {
            pos += 5usize
            var got_pragma = false
            var need_pragma = 0usize
            var found = ""
            var seen_charset = false
            var seen_content = false
            var seen_http = false
            while true {
                let at = get_attribute(b, pos)
                pos = at.next
                if !at.more { break }
                if eq_lower(b, at.name_lo, at.name_hi, "http-equiv") && !seen_http {
                    seen_http = true
                    if eq_lower(b, at.value_lo, at.value_hi, "content-type") { got_pragma = true }
                } else if eq_lower(b, at.name_lo, at.name_hi, "content") && !seen_content {
                    seen_content = true
                    if found.len == 0usize {
                        let named = charset_in_content(b, at.value_lo, at.value_hi)
                        if named.len > 0usize {
                            found = named
                            need_pragma = 1usize
                        }
                    }
                } else if eq_lower(b, at.name_lo, at.name_hi, "charset") && !seen_charset {
                    seen_charset = true
                    let (name, good) = charset.label_to_name(str_of(b, at.value_lo, at.value_hi))
                    if good {
                        found = name
                        need_pragma = 2usize
                    }
                }
            }
            if need_pragma == 0usize { continue }
            if need_pragma == 1usize && !got_pragma { continue }
            if found.len == 0usize { continue }
            if str.eq(found, "UTF-16BE") || str.eq(found, "UTF-16LE") { ret "UTF-8" }
            if str.eq(found, "x-user-defined") { ret "windows-1252" }
            ret found
        }
        if pos + 1usize < b.len && b[pos] == 60u8 && ((is_letter(b[pos + 1usize])) || (b[pos + 1usize] == 47u8 && pos + 2usize < b.len && is_letter(b[pos + 2usize]))) {
            // A tag: skip its name, then its attributes.
            pos += 1usize
            if b[pos] == 47u8 { pos += 1usize }
            while pos < b.len && !is_space(b[pos]) && b[pos] != 62u8 && b[pos] != 47u8 { pos += 1usize }
            while true {
                let at = get_attribute(b, pos)
                pos = at.next
                if !at.more { break }
            }
            continue
        }
        if pos + 1usize < b.len && b[pos] == 60u8 && (b[pos + 1usize] == 33u8 || b[pos + 1usize] == 47u8 || b[pos + 1usize] == 63u8) {
            var e = pos
            while e < b.len && b[e] != 62u8 { e += 1usize }
            pos = e + 1usize
            continue
        }
        pos += 1usize
    }
    ret ""
}

// The canonical encoding name for a byte stream and the label the transport layer gave ("" for none).
fn determine(bytes: []const u8, transport_label: str) -> str {
    if bytes.len >= 3usize && bytes[0usize] == 239u8 && bytes[1usize] == 187u8 && bytes[2usize] == 191u8 { ret "UTF-8" }
    if bytes.len >= 2usize && bytes[0usize] == 254u8 && bytes[1usize] == 255u8 { ret "UTF-16BE" }
    if bytes.len >= 2usize && bytes[0usize] == 255u8 && bytes[1usize] == 254u8 { ret "UTF-16LE" }
    if transport_label.len > 0usize {
        let (name, good) = charset.label_to_name(transport_label)
        if good && !str.eq(name, "replacement") { ret name }
    }
    let scanned = prescan(bytes)
    if scanned.len > 0usize { ret scanned }
    ret "windows-1252"
}

// Decodes an HTML byte stream into UTF-8; `name` receives the encoding used.
fn decode_document(a: *mem.Arena, bytes: []const u8, transport_label: str) -> (str, str, err) {
    let name = determine(bytes, transport_label)
    let (text, e) = cjk.decode_sniffing_bom(a, name, bytes)
    ret (text, name, e)
}
