// PEM by RFC 7468: `decode` takes the first block -- a `-----BEGIN label-----` line,
// optional RFC 1421 `Name: value` header lines closed by an empty line, base64 lines,
// and the matching `-----END label-----` line -- and returns it with the unconsumed
// suffix; `encode` writes one back in 64-column lines. The base64 goes through
// `e.bytes`. Text before the first BEGIN is skipped, as the RFC allows; encrypted
// legacy headers are carried as headers and not interpreted.
use e.bytes
use e.io
use e.mem
use e.str
use e.fmt.mime as mime

type Block = struct { label: str, headers: []const mime.Header, bytes: []const u8 }
error Invalid
error TooLarge

fn line_end(source: str, at: usize) -> usize {
    var end = at
    while end < source.len && source[end] != 10u8 { end += 1usize }
    ret end
}

fn strip_cr(line: str) -> str {
    if line.len > 0usize && line[line.len - 1usize] == 13u8 { ret line[..line.len - 1usize] }
    ret line
}

fn is_base64_byte(c: u8) -> bool {
    ret str.is_ascii_alnum(c) || c == 43u8 || c == 47u8 || c == 61u8
}

fn decode(a: *mem.Arena, source: str, byte_limit: usize) -> (Block, str, err) {
    // The BEGIN line.
    let (begin_at, found) = str.find(source, "-----BEGIN ")
    if !found { ret (zero, source, Invalid) }
    var at = begin_at
    var end = line_end(source, at)
    let begin_line = strip_cr(source[at..end])
    if !str.ends_with(begin_line, "-----") { ret (zero, source, Invalid) }
    let label = begin_line[11usize..begin_line.len - 5usize]
    if label.len == 0usize { ret (zero, source, Invalid) }
    at = end + 1usize
    if at > source.len { ret (zero, source, Invalid) }
    // Header lines: a colon in the first line marks a header block, closed by an empty line.
    var header_count = 0usize
    let headers_start = at
    let first_end = line_end(source, at)
    let has_colon = str.contains(strip_cr(source[at..first_end]), ":")
    if has_colon {
        while at < source.len {
            end = line_end(source, at)
            let line = strip_cr(source[at..end])
            if line.len == 0usize { break }
            header_count += 1usize
            at = end + 1usize
        }
        if at >= source.len { ret (zero, source, Invalid) }
        at = end + 1usize
        if at > source.len { ret (zero, source, Invalid) }
    }
    let (headers, headers_error) = mem.alloc[mime.Header](a, header_count)
    if headers_error != ok { ret (zero, source, headers_error) }
    var index = 0usize
    var header_at = headers_start
    while index < header_count {
        end = line_end(source, header_at)
        let line = strip_cr(source[header_at..end])
        let (name, value, split) = str.split_once(line, ":")
        if !split || name.len == 0usize { ret (zero, source, Invalid) }
        headers[index].name = str.trim(name)
        headers[index].value = str.trim(value)
        index += 1usize
        header_at = end + 1usize
    }
    // Base64 lines up to the END line; the text is packed without its line breaks.
    let (text, text_error) = mem.alloc[u8](a, source.len - at)
    if text_error != ok { ret (zero, source, text_error) }
    var packed = 0usize
    var closed = false
    var suffix_at = source.len
    while at < source.len && !closed {
        end = line_end(source, at)
        let line = strip_cr(source[at..end])
        if str.starts_with(line, "-----END ") {
            if !str.ends_with(line, "-----") { ret (zero, source, Invalid) }
            if !str.eq(line[9usize..line.len - 5usize], label) { ret (zero, source, Invalid) }
            closed = true
            suffix_at = end + 1usize
            if suffix_at > source.len { suffix_at = source.len }
        } else {
            var i = 0usize
            while i < line.len {
                if !is_base64_byte(line[i]) { ret (zero, source, Invalid) }
                text[packed] = line[i]
                packed += 1usize
                i += 1usize
            }
        }
        at = end + 1usize
    }
    if !closed { ret (zero, source, Invalid) }
    var decoded_len = packed / 4usize * 3usize
    if packed % 4usize != 0usize { decoded_len += packed % 4usize }
    if decoded_len > byte_limit { ret (zero, source, TooLarge) }
    let (buffer, buffer_error) = mem.alloc[u8](a, decoded_len)
    if buffer_error != ok { ret (zero, source, buffer_error) }
    let (decoded, decode_error) = bytes.base64_decode(buffer, text[..packed], .Standard)
    if decode_error != ok { ret (zero, source, Invalid) }
    var block: Block = zero
    block.label = label
    block.headers = headers
    block.bytes = decoded
    ret (block, source[suffix_at..], ok)
}

fn encode(writer: *io.Writer, block: *const Block) -> err {
    try io.write_all(writer, "-----BEGIN ")
    try io.write_all(writer, block.label)
    try io.write_all(writer, "-----\n")
    var index = 0usize
    while index < block.headers.len {
        try io.write_all(writer, block.headers[index].name)
        try io.write_all(writer, ": ")
        try io.write_all(writer, block.headers[index].value)
        try io.write_all(writer, "\n")
        index += 1usize
    }
    if block.headers.len > 0usize { try io.write_all(writer, "\n") }
    var at = 0usize
    var line: [64]u8 = zero
    while at < block.bytes.len {
        var take = 48usize
        if block.bytes.len - at < take { take = block.bytes.len - at }
        let (encoded, encode_error) = bytes.base64_encode(line[0..], block.bytes[at..at + take], .Standard, true)
        if encode_error != ok { ret encode_error }
        try io.write_all(writer, encoded)
        try io.write_all(writer, "\n")
        at += take
    }
    try io.write_all(writer, "-----END ")
    try io.write_all(writer, block.label)
    try io.write_all(writer, "-----\n")
    ret ok
}
