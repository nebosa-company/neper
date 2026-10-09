// Terraform's encoding functions over the codecs Neper already has (L023), after petcow's interpreter: no new codec,
// only the contracts around them. `base64_encode` and `base64_decode` (the decoded bytes must be UTF-8: a binary
// result is `NotUtf8`, fail closed), `text_encode_base64` and `text_decode_base64` (the charset is named and only
// UTF-8 is accepted, in the spellings `UTF-8` and `UTF8` in any case with surrounding spaces; any other charset is
// `UnsupportedEncoding` and nothing is silently mis-encoded), `url_encode` (RFC 3986 percent-encoding: letters,
// digits and `-_.~` stay, every other byte becomes `%XX`; unlike Go's query escape a space is `%20`, not `+`),
// `json_encode`/`json_decode` (`e.fmt.json`), `yaml_encode`/`yaml_decode` (`e.fmt.yaml`) and `csv_decode` (RFC 4180
// text with a header row to a list of objects whose values are all strings; a row whose column count differs from
// the header's is `Ragged`, and text with no rows is an empty list).
//
// Results are in the caller's arena. Decoding base64 is as tolerant as `e.bytes`: padding is optional, anything
// outside the alphabet is `BadBase64`.

use e.bytes
use e.fmt.csv as csv
use e.fmt.json as json
use e.fmt.yaml as yaml
use e.io
use e.mem
use e.text.utf8 as utf8

error BadBase64
error NotUtf8
error UnsupportedEncoding
error Ragged
error Invalid

fn base64_encode(a: *mem.Arena, s: str) -> (str, err) {
    let (size, size_error) = bytes.base64_encoded_len(s.len, true)
    if size_error != ok { ret ("", size_error) }
    let (out, out_error) = mem.alloc[u8](a, size)
    if out_error != ok { ret ("", out_error) }
    let (text, encode_error) = bytes.base64_encode(out, s, .Standard, true)
    if encode_error != ok { ret ("", encode_error) }
    ret (text, ok)
}

// The decoded bytes of `s`, which must be valid UTF-8.
fn base64_decode(a: *mem.Arena, s: str) -> (str, err) {
    let (out, out_error) = mem.alloc[u8](a, s.len / 4usize * 3usize + 3usize)
    if out_error != ok { ret ("", out_error) }
    let (decoded, decode_error) = bytes.base64_decode(out, s, .Standard)
    if decode_error != ok { ret ("", BadBase64) }
    if !utf8.validate(decoded) { ret ("", NotUtf8) }
    ret (decoded, ok)
}

// Whether a charset name is UTF-8 (trimmed, any case, `UTF-8` or `UTF8`).
fn is_utf8_name(name: str) -> bool {
    var start = 0usize
    var end = name.len
    while start < end && (name[start] == 32u8 || (name[start] >= 9u8 && name[start] <= 13u8)) { start += 1usize }
    while end > start && (name[end - 1usize] == 32u8 || (name[end - 1usize] >= 9u8 && name[end - 1usize] <= 13u8)) { end -= 1usize }
    let trimmed = name[start..end]
    var upper: [5]u8 = zero
    if trimmed.len != 4usize && trimmed.len != 5usize { ret false }
    var i = 0usize
    while i < trimmed.len {
        var c = trimmed[i]
        if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        upper[i] = c
        i += 1usize
    }
    if trimmed.len == 4usize { ret upper[0usize] == 85u8 && upper[1usize] == 84u8 && upper[2usize] == 70u8 && upper[3usize] == 56u8 }
    ret upper[0usize] == 85u8 && upper[1usize] == 84u8 && upper[2usize] == 70u8 && upper[3usize] == 45u8 && upper[4usize] == 56u8
}

fn text_encode_base64(a: *mem.Arena, s: str, encoding: str) -> (str, err) {
    if !is_utf8_name(encoding) { ret ("", UnsupportedEncoding) }
    let (text, text_error) = base64_encode(a, s)
    ret (text, text_error)
}

fn text_decode_base64(a: *mem.Arena, s: str, encoding: str) -> (str, err) {
    if !is_utf8_name(encoding) { ret ("", UnsupportedEncoding) }
    let (text, text_error) = base64_decode(a, s)
    ret (text, text_error)
}

fn upper_hex(nibble: u8) -> u8 {
    if nibble < 10u8 { ret 48u8 + nibble }
    ret 55u8 + nibble
}

fn url_encode(a: *mem.Arena, s: str) -> (str, err) {
    var needed = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 45u8 || c == 95u8 || c == 46u8 || c == 126u8 {
            needed += 1usize
        } else {
            needed += 3usize
        }
        i += 1usize
    }
    if needed == 0usize { ret ("", ok) }
    let (out, out_error) = mem.alloc[u8](a, needed)
    if out_error != ok { ret ("", out_error) }
    var n = 0usize
    i = 0usize
    while i < s.len {
        let c = s[i]
        if (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) || c == 45u8 || c == 95u8 || c == 46u8 || c == 126u8 {
            out[n] = c
            n += 1usize
        } else {
            out[n] = 37u8
            out[n + 1usize] = upper_hex(c >> 4u8)
            out[n + 2usize] = upper_hex(c & 15u8)
            n += 3usize
        }
        i += 1usize
    }
    ret (out[0usize..n], ok)
}

// Compact JSON text of a value.
fn json_encode(a: *mem.Arena, v: json.Value) -> (str, err) {
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret ("", writer_error) }
    var held = state
    var w = io.writer(mem.cast[*void](&held), io.memory_write)
    var copy = v
    let write_error = json.write(&w, &copy)
    if write_error != ok { ret ("", write_error) }
    ret (io.memory_bytes(&held), ok)
}

fn json_decode(a: *mem.Arena, text: str) -> (json.Value, err) {
    let (value, parse_error) = json.parse(a, text, json.Options { allow_duplicate_keys: false, max_depth: 64u16 })
    ret (value, parse_error)
}

fn yaml_encode(a: *mem.Arena, v: yaml.Value) -> (str, err) {
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret ("", writer_error) }
    var held = state
    var w = io.writer(mem.cast[*void](&held), io.memory_write)
    var copy = v
    let write_error = yaml.write(&w, &copy, 2u8)
    if write_error != ok { ret ("", write_error) }
    ret (io.memory_bytes(&held), ok)
}

fn yaml_decode(a: *mem.Arena, text: str) -> (yaml.Value, err) {
    let (value, parse_error) = yaml.parse(a, text, yaml.Options { max_depth: 64u16, allow_duplicate_keys: false })
    ret (value, parse_error)
}

fn copy_text(a: *mem.Arena, s: str) -> (str, err) {
    if s.len == 0usize { ret ("", ok) }
    let (out, out_error) = mem.alloc[u8](a, s.len)
    if out_error != ok { ret ("", out_error) }
    var i = 0usize
    while i < s.len {
        out[i] = s[i]
        i += 1usize
    }
    ret (out, ok)
}

// CSV text with a header row as a list of objects (string values).
fn csv_decode(a: *mem.Arena, text: str) -> (json.Value, err) {
    var none: json.Value = zero
    var cursor = io.SliceReader { data: text, off: 0usize }
    let (reader, reader_error) = csv.reader(a, io.slice_reader(&cursor), csv.csv(), 0usize, 0usize)
    if reader_error != ok { ret (none, reader_error) }
    var rd = reader
    let (header_row, header_more, header_error) = csv.reader_next_err(&rd)
    if header_error != ok { ret (none, header_error) }
    if !header_more { ret (json.Value { Array: none_list() }, ok) }
    let width = header_row.fields.len
    let (names, names_error) = mem.alloc[str](a, width)
    if names_error != ok { ret (none, names_error) }
    var c = 0usize
    while c < width {
        let (copied, copy_error) = copy_text(a, header_row.fields[c])
        if copy_error != ok { ret (none, copy_error) }
        names[c] = copied
        c += 1usize
    }
    // Rows are collected into a growing list of objects.
    var objects: []json.Value = none_list()
    var count = 0usize
    var capacity = 0usize
    var more = true
    while more {
        let (row, row_more, row_error) = csv.reader_next_err(&rd)
        if row_error != ok { ret (none, row_error) }
        if !row_more {
            more = false
        } else {
            if row.fields.len != width { ret (none, Ragged) }
            if count == capacity {
                var grown = capacity * 2usize
                if grown == 0usize { grown = 8usize }
                let (bigger, bigger_error) = mem.alloc[json.Value](a, grown)
                if bigger_error != ok { ret (none, bigger_error) }
                var k = 0usize
                while k < count {
                    bigger[k] = objects[k]
                    k += 1usize
                }
                objects = bigger
                capacity = grown
            }
            let (members, members_error) = mem.alloc[json.Member](a, width)
            if members_error != ok { ret (none, members_error) }
            var f = 0usize
            while f < width {
                let (value_text, value_error) = copy_text(a, row.fields[f])
                if value_error != ok { ret (none, value_error) }
                members[f] = json.Member { key: names[f], value: json.Value { String: value_text } }
                f += 1usize
            }
            objects[count] = json.Value { Object: members }
            count += 1usize
        }
    }
    ret (json.Value { Array: objects[0usize..count] }, ok)
}

fn none_list() -> []json.Value {
    var none: []json.Value = zero
    ret none
}
