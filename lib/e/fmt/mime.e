// Media types and header blocks by RFC 2045 and RFC 5322: `type/subtype` with
// `; name=value` parameters, the value a token or a quoted string; and a header block
// of `Name: value` lines ending at an empty line. Names compare by ASCII case folding.
// Obsolete line folding (a continuation line beginning with white space) is rejected,
// as the fence says. `extension_type` knows the handful of extensions a toolchain
// serves and nothing more.

use e.io
use e.mem

type Parameter = struct { name: str, value: str }
type MediaType = struct { major: str, subtype: str, parameters: []const Parameter }
type Header = struct { name: str, value: str }
error Invalid
error TooLarge

fn is_token_byte(c: u8) -> bool {
    if c <= 32u8 || c >= 127u8 { ret false }
    // tspecials: ( ) < > @ , ; : \ " / [ ] ? =
    if c == 40u8 || c == 41u8 || c == 60u8 || c == 62u8 || c == 64u8 || c == 44u8 || c == 59u8 || c == 58u8 { ret false }
    if c == 92u8 || c == 34u8 || c == 47u8 || c == 91u8 || c == 93u8 || c == 63u8 || c == 61u8 { ret false }
    ret true
}

fn fold(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn same_folded(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var at = 0usize
    while at < a.len {
        if fold(a[at]) != fold(b[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn skip_space(source: str, at: usize) -> usize {
    var end = at
    while end < source.len && (source[end] == 32u8 || source[end] == 9u8) { end += 1usize }
    ret end
}

fn token_end(source: str, at: usize) -> usize {
    var end = at
    while end < source.len && is_token_byte(source[end]) { end += 1usize }
    ret end
}

// A parameter value, either a token or a quoted string with `\` escapes; the value is
// returned unquoted, copied into the arena when an escape has to be removed.
fn parameter_value(a: *mem.Arena, source: str, at: usize) -> (str, usize, err) {
    if at < source.len && source[at] == 34u8 {
        var end = at + 1usize
        var escapes = 0usize
        while end < source.len && source[end] != 34u8 {
            if source[end] == 92u8 {
                if end + 1usize >= source.len { ret ("", at, Invalid) }
                escapes += 1usize
                end += 1usize
            }
            end += 1usize
        }
        if end >= source.len { ret ("", at, Invalid) }
        let raw = source[at + 1usize..end]
        if escapes == 0usize { ret (raw, end + 1usize, ok) }
        let (out, out_error) = mem.alloc[u8](a, raw.len - escapes)
        if out_error != ok { ret ("", at, out_error) }
        var written = 0usize
        var read = 0usize
        while read < raw.len {
            if raw[read] == 92u8 { read += 1usize }
            out[written] = raw[read]
            written += 1usize
            read += 1usize
        }
        ret (out[..written], end + 1usize, ok)
    }
    let end = token_end(source, at)
    if end == at { ret ("", at, Invalid) }
    ret (source[at..end], end, ok)
}

fn parse_media_type(a: *mem.Arena, source: str, limit: usize) -> (MediaType, err) {
    var m: MediaType = zero
    var at = skip_space(source, 0usize)
    let major_end = token_end(source, at)
    if major_end == at || major_end >= source.len || source[major_end] != 47u8 { ret (zero, Invalid) }
    m.major = source[at..major_end]
    at = major_end + 1usize
    let subtype_end = token_end(source, at)
    if subtype_end == at { ret (zero, Invalid) }
    m.subtype = source[at..subtype_end]
    at = skip_space(source, subtype_end)
    // Count the parameters first, then fill a slice of exactly that many.
    var count = 0usize
    var probe = at
    while probe < source.len {
        if source[probe] != 59u8 { ret (zero, Invalid) }
        probe = skip_space(source, probe + 1usize)
        let name_end = token_end(source, probe)
        if name_end == probe || name_end >= source.len || source[name_end] != 61u8 { ret (zero, Invalid) }
        let (_, value_end, value_error) = parameter_value(a, source, name_end + 1usize)
        if value_error != ok { ret (zero, value_error) }
        count += 1usize
        if count > limit { ret (zero, TooLarge) }
        probe = skip_space(source, value_end)
    }
    let (parameters, parameters_error) = mem.alloc[Parameter](a, count)
    if parameters_error != ok { ret (zero, parameters_error) }
    var index = 0usize
    while at < source.len {
        at = skip_space(source, at + 1usize)
        let name_end = token_end(source, at)
        let (value, value_end, value_error) = parameter_value(a, source, name_end + 1usize)
        if value_error != ok { ret (zero, value_error) }
        parameters[index].name = source[at..name_end]
        parameters[index].value = value
        index += 1usize
        at = skip_space(source, value_end)
    }
    m.parameters = parameters[0..]
    ret (m, ok)
}

fn needs_quoting(value: str) -> bool {
    if value.len == 0usize { ret true }
    var at = 0usize
    while at < value.len {
        if !is_token_byte(value[at]) { ret true }
        at += 1usize
    }
    ret false
}

fn format_media_type(a: *mem.Arena, value: MediaType) -> (str, err) {
    var needed = value.major.len + 1usize + value.subtype.len
    var at = 0usize
    while at < value.parameters.len {
        // `; name="value"` with room for every byte to be escaped.
        needed += 2usize + value.parameters[at].name.len + 1usize + value.parameters[at].value.len * 2usize + 2usize
        at += 1usize
    }
    let (out, out_error) = mem.alloc[u8](a, needed)
    if out_error != ok { ret ("", out_error) }
    var written = append(out, 0usize, value.major)
    out[written] = 47u8
    written += 1usize
    written = append(out, written, value.subtype)
    at = 0usize
    while at < value.parameters.len {
        let p = value.parameters[at]
        out[written] = 59u8
        out[written + 1usize] = 32u8
        written += 2usize
        written = append(out, written, p.name)
        out[written] = 61u8
        written += 1usize
        if needs_quoting(p.value) {
            out[written] = 34u8
            written += 1usize
            var v = 0usize
            while v < p.value.len {
                let c = p.value[v]
                if c == 34u8 || c == 92u8 {
                    out[written] = 92u8
                    written += 1usize
                }
                out[written] = c
                written += 1usize
                v += 1usize
            }
            out[written] = 34u8
            written += 1usize
        } else {
            written = append(out, written, p.value)
        }
        at += 1usize
    }
    ret (out[..written], ok)
}

fn append(out: []u8, at: usize, text: str) -> usize {
    var copy = 0usize
    while copy < text.len {
        out[at + copy] = text[copy]
        copy += 1usize
    }
    ret at + text.len
}

// The types a toolchain serves, by extension without its dot, case-folded.
fn extension_type(extension: str) -> (str, bool) {
    if same_folded(extension, "html") || same_folded(extension, "htm") { ret ("text/html", true) }
    if same_folded(extension, "css") { ret ("text/css", true) }
    if same_folded(extension, "js") || same_folded(extension, "mjs") { ret ("text/javascript", true) }
    if same_folded(extension, "json") { ret ("application/json", true) }
    if same_folded(extension, "txt") { ret ("text/plain", true) }
    if same_folded(extension, "csv") { ret ("text/csv", true) }
    if same_folded(extension, "xml") { ret ("application/xml", true) }
    if same_folded(extension, "svg") { ret ("image/svg+xml", true) }
    if same_folded(extension, "png") { ret ("image/png", true) }
    if same_folded(extension, "jpg") || same_folded(extension, "jpeg") { ret ("image/jpeg", true) }
    if same_folded(extension, "gif") { ret ("image/gif", true) }
    if same_folded(extension, "webp") { ret ("image/webp", true) }
    if same_folded(extension, "ico") { ret ("image/x-icon", true) }
    if same_folded(extension, "pdf") { ret ("application/pdf", true) }
    if same_folded(extension, "zip") { ret ("application/zip", true) }
    if same_folded(extension, "gz") { ret ("application/gzip", true) }
    if same_folded(extension, "tar") { ret ("application/x-tar", true) }
    if same_folded(extension, "wasm") { ret ("application/wasm", true) }
    if same_folded(extension, "woff2") { ret ("font/woff2", true) }
    if same_folded(extension, "mp4") { ret ("video/mp4", true) }
    if same_folded(extension, "mp3") { ret ("audio/mpeg", true) }
    ret ("application/octet-stream", false)
}

// `Name: value` lines to the first empty line, over at most `byte_limit` bytes and
// `count_limit` headers; a line that starts with white space is the obsolete folding
// and is `Invalid`. The block is read whole into the arena, since the slices point
// into it.
fn parse_headers(a: *mem.Arena, source: io.Reader, byte_limit: usize, count_limit: usize) -> ([]Header, err) {
    let (buffer, buffer_error) = mem.alloc[u8](a, byte_limit)
    if buffer_error != ok { ret (zero, buffer_error) }
    var filled = 0usize
    var reader = source
    var block_end = 0usize
    var found_end = false
    while !found_end {
        if filled == byte_limit { ret (zero, TooLarge) }
        let (count, read_error) = io.read(&reader, buffer[filled..])
        if read_error == io.End { break }
        if read_error != ok { ret (zero, read_error) }
        filled += count
        // The block ends at the first CRLF CRLF, or LF LF.
        var at = 0usize
        while at < filled && !found_end {
            if buffer[at] == 10u8 {
                if at + 2usize < filled && buffer[at + 1usize] == 13u8 && buffer[at + 2usize] == 10u8 {
                    block_end = at + 1usize
                    found_end = true
                }
                if at + 1usize < filled && buffer[at + 1usize] == 10u8 {
                    block_end = at + 1usize
                    found_end = true
                }
            }
            at += 1usize
        }
    }
    if !found_end { block_end = filled }
    // Count lines, then fill.
    var count = 0usize
    var at = 0usize
    while at < block_end {
        var line_end = at
        while line_end < block_end && buffer[line_end] != 10u8 { line_end += 1usize }
        var line = buffer[at..line_end]
        if line.len > 0usize && line[line.len - 1usize] == 13u8 { line = line[..line.len - 1usize] }
        if line.len > 0usize {
            if line[0] == 32u8 || line[0] == 9u8 { ret (zero, Invalid) }
            count += 1usize
            if count > count_limit { ret (zero, TooLarge) }
        }
        at = line_end + 1usize
    }
    let (headers, headers_error) = mem.alloc[Header](a, count)
    if headers_error != ok { ret (zero, headers_error) }
    var index = 0usize
    at = 0usize
    while at < block_end {
        var line_end = at
        while line_end < block_end && buffer[line_end] != 10u8 { line_end += 1usize }
        var line = buffer[at..line_end]
        if line.len > 0usize && line[line.len - 1usize] == 13u8 { line = line[..line.len - 1usize] }
        if line.len > 0usize {
            var colon = 0usize
            while colon < line.len && line[colon] != 58u8 { colon += 1usize }
            if colon == 0usize || colon >= line.len { ret (zero, Invalid) }
            var name_at = 0usize
            while name_at < colon {
                if !is_token_byte(line[name_at]) { ret (zero, Invalid) }
                name_at += 1usize
            }
            var value_start = colon + 1usize
            while value_start < line.len && (line[value_start] == 32u8 || line[value_start] == 9u8) { value_start += 1usize }
            var value_end = line.len
            while value_end > value_start && (line[value_end - 1usize] == 32u8 || line[value_end - 1usize] == 9u8) { value_end -= 1usize }
            headers[index].name = line[..colon]
            headers[index].value = line[value_start..value_end]
            index += 1usize
        }
        at = line_end + 1usize
    }
    ret (headers, ok)
}

fn header(headers: []const Header, name: str) -> (str, bool) {
    var at = 0usize
    while at < headers.len {
        if same_folded(headers[at].name, name) { ret (headers[at].value, true) }
        at += 1usize
    }
    ret ("", false)
}
