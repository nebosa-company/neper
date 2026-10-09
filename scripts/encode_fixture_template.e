// `e.fmt.encode` (Terraform's base64encode/decode, textencodebase64/textdecodebase64, urlencode, jsonencode/decode,
// yamlencode/decode and csvdecode over the existing codecs) against scripts/encode_reference.py, which states the
// contracts with Python's base64, urllib, json and csv modules: petcow's assertions, the fail-closed UTF-8 rule (a
// binary base64 payload is refused, only UTF-8 is a charset), malformed base64, ragged CSV rows and seeded random
// text. A line is `<kind> <arg> ... => <result>`; text arguments are hex of their bytes (`_` for empty); a result is
// hex, JSON text (kinds J and C) or `E:<name>`. Kinds: B base64_encode, b base64_decode, T text_encode_base64,
// t text_decode_base64 (the second argument is the charset name), U url_encode, J json round trip, C csv_decode.
use e.fmt.encode
use e.fmt.json as json
use e.fmt.yaml as yaml
use e.io
use e.mem
use e.os

fn next_token(line: str, at: usize) -> (str, usize) {
    var p = at
    while p < line.len && line[p] == 32u8 { p += 1usize }
    let start = p
    while p < line.len && line[p] != 32u8 { p += 1usize }
    ret (line[start..p], p)
}

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(token: str, buffer: []u8) -> str {
    if token.len == 1usize && token[0usize] == 95u8 { ret buffer[0usize..0usize] }
    var n = 0usize
    var p = 0usize
    while p + 1usize < token.len {
        buffer[n] = nibble(token[p]) * 16u8 + nibble(token[p + 1usize])
        n += 1usize
        p += 2usize
    }
    ret buffer[0usize..n]
}

fn same_text(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

fn error_name(e: err) -> str {
    if e == encode.BadBase64 { ret "BadBase64" }
    if e == encode.NotUtf8 { ret "NotUtf8" }
    if e == encode.UnsupportedEncoding { ret "UnsupportedEncoding" }
    if e == encode.Ragged { ret "Ragged" }
    ret "Other"
}

fn hex_of(a: *mem.Arena, s: str) -> str {
    if s.len == 0usize { ret "_" }
    let (out, out_error) = mem.alloc[u8](a, s.len * 2usize)
    if out_error != ok { ret "?" }
    var i = 0usize
    while i < s.len {
        let hi = s[i] >> 4u8
        let lo = s[i] & 15u8
        var h = 48u8 + hi
        if hi > 9u8 { h = 87u8 + hi }
        var l = 48u8 + lo
        if lo > 9u8 { l = 87u8 + lo }
        out[i * 2usize] = h
        out[i * 2usize + 1usize] = l
        i += 1usize
    }
    ret out[0usize..s.len * 2usize]
}

// The result for a line: the library's text (hex, or JSON) or `E:<name>`.
fn answer(a: *mem.Arena, line: str) -> str {
    let kind = line[0usize]
    let (first, after_first) = next_token(line, 2usize)
    var raw: [2048]u8 = zero
    var other: [64]u8 = zero
    let text = unhex(first, raw[0..])
    var out = ""
    var e = ok
    if kind == 66u8 {
        let (r, re) = encode.base64_encode(a, text)
        out = hex_of(a, r)
        e = re
    } else if kind == 98u8 {
        let (r, re) = encode.base64_decode(a, text)
        out = hex_of(a, r)
        e = re
    } else if kind == 84u8 || kind == 116u8 {
        let (charset_token, after_charset) = next_token(line, after_first)
        let charset = unhex(charset_token, other[0..])
        if kind == 84u8 {
            let (r, re) = encode.text_encode_base64(a, text, charset)
            out = hex_of(a, r)
            e = re
        } else {
            let (r, re) = encode.text_decode_base64(a, text, charset)
            out = hex_of(a, r)
            e = re
        }
    } else if kind == 85u8 {
        let (r, re) = encode.url_encode(a, text)
        out = r
        e = re
    } else if kind == 74u8 {
        let (v, de) = encode.json_decode(a, text)
        if de != ok { ret "E:Invalid" }
        let (r, re) = encode.json_encode(a, v)
        out = r
        e = re
    } else {
        let (v, re) = encode.csv_decode(a, text)
        e = re
        if re == ok {
            let (r, ee) = encode.json_encode(a, v)
            out = r
            e = ee
        }
    }
    if e != ok { ret join_text(a, "E:", error_name(e)) }
    ret out
}

fn join_text(a: *mem.Arena, first: str, second: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, first.len + second.len)
    if buffer_error != ok { ret first }
    var n = 0usize
    var i = 0usize
    while i < first.len {
        buffer[n] = first[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        buffer[n] = second[i]
        n += 1usize
        i += 1usize
    }
    ret buffer[0usize..n]
}

fn find_arrow(line: str) -> usize {
    var i = 0usize
    while i + 3usize < line.len {
        if line[i] == 32u8 && line[i + 1usize] == 61u8 && line[i + 2usize] == 62u8 && line[i + 3usize] == 32u8 { ret i }
        i += 1usize
    }
    ret line.len
}

fn run(a: *mem.Arena, text: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < text.len {
        if text[i] == 10u8 {
            let line = text[start..i]
            let mark = mem.mark(a)
            let got = answer(a, line)
            let arrow = find_arrow(line)
            let good = same_text(got, line[arrow + 4usize..line.len])
            if !good {
                let shown = io.print(line)
                let shown_got = io.print(got)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

//__VECTOR_FUNCTIONS__
fn main(a: *mem.Arena, args: []str) -> err {
    // YAML: a document decodes and encodes back to the same document.
    let (doc, doc_error) = encode.yaml_decode(a, "name: web\nports:\n  - 80\n  - 443\nenabled: true\n")
    if doc_error != ok { os.exit(100i32) }
    let (text, text_error) = encode.yaml_encode(a, doc)
    if text_error != ok { os.exit(101i32) }
    let (again, again_error) = encode.yaml_decode(a, text)
    if again_error != ok { os.exit(102i32) }
    let (twice, twice_error) = encode.yaml_encode(a, again)
    if twice_error != ok || !same_text(twice, text) { os.exit(103i32) }
    if !same_text(text, "name: web\nports:\n  - 80\n  - 443\nenabled: true\n") { os.exit(104i32) }
    let (bad, bad_error) = encode.yaml_decode(a, "a: [1, 2")
    if bad_error == ok { os.exit(105i32) }
    //__VECTOR_CALLS__
    try io.print("fmt encode ok")
    ret ok
}
