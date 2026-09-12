// `e.fmt.mime`: media types with token and quoted parameters both ways, the extension
// table, and header blocks from a stream with case-folded lookup, the obsolete folding
// rejected and both limits enforced. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.fmt.mime as mime

fn text_equal(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (m, e1) = mime.parse_media_type(a, "Text/HTML; charset=utf-8; title=\"a \\\"quoted\\\" name\"", 8usize)
    if e1 != ok || !text_equal(m.major, "Text") || !text_equal(m.subtype, "HTML") || m.parameters.len != 2usize { os.exit(1) }
    if !text_equal(m.parameters[0].name, "charset") || !text_equal(m.parameters[0].value, "utf-8") { os.exit(2) }
    if !text_equal(m.parameters[1].name, "title") || !text_equal(m.parameters[1].value, "a \"quoted\" name") { os.exit(3) }
    let (shown, e2) = mime.format_media_type(a, m)
    if e2 != ok || !text_equal(shown, "Text/HTML; charset=utf-8; title=\"a \\\"quoted\\\" name\"") { os.exit(4) }
    let (plain, e3) = mime.parse_media_type(a, "application/json", 0usize)
    if e3 != ok || plain.parameters.len != 0usize || !text_equal(plain.subtype, "json") { os.exit(5) }
    let (_, no_slash) = mime.parse_media_type(a, "text", 4usize)
    let (_, bad_param) = mime.parse_media_type(a, "text/plain; charset", 4usize)
    let (_, too_many) = mime.parse_media_type(a, "text/plain; a=1; b=2", 1usize)
    let (_, unterminated) = mime.parse_media_type(a, "text/plain; a=\"open", 4usize)
    if no_slash != mime.Invalid || bad_param != mime.Invalid || too_many != mime.TooLarge || unterminated != mime.Invalid { os.exit(6) }
    let (html, known) = mime.extension_type("HTML")
    let (unknown, is_known) = mime.extension_type("xyz")
    if !known || !text_equal(html, "text/html") || is_known || !text_equal(unknown, "application/octet-stream") { os.exit(7) }
    // Headers from a stream, ending at the empty line; the body after it is untouched.
    var source_state: io.SliceReader = zero
    source_state.data = "Host: example.com\r\nContent-Type:  text/plain \r\nX-Empty:\r\n\r\nbody"
    let (headers, e4) = mime.parse_headers(a, io.slice_reader(&source_state), 256usize, 8usize)
    if e4 != ok || headers.len != 3usize { os.exit(8) }
    let (host, has_host) = mime.header(headers, "host")
    let (kind, has_kind) = mime.header(headers, "CONTENT-TYPE")
    let (empty, has_empty) = mime.header(headers, "x-empty")
    let (_, has_none) = mime.header(headers, "accept")
    if !has_host || !text_equal(host, "example.com") || !has_kind || !text_equal(kind, "text/plain") || !has_empty || empty.len != 0usize || has_none { os.exit(9) }
    var folded_state: io.SliceReader = zero
    folded_state.data = "A: one\r\n two\r\n\r\n"
    let (_, folded) = mime.parse_headers(a, io.slice_reader(&folded_state), 256usize, 8usize)
    if folded != mime.Invalid { os.exit(10) }
    var big_state: io.SliceReader = zero
    big_state.data = "A: 1\nB: 2\nC: 3\n\n"
    let (_, too_many_headers) = mime.parse_headers(a, io.slice_reader(&big_state), 256usize, 2usize)
    var big_state2: io.SliceReader = zero
    big_state2.data = "A: 1\nB: 2\nC: 3\n\n"
    let (_, too_long) = mime.parse_headers(a, io.slice_reader(&big_state2), 8usize, 8usize)
    if too_many_headers != mime.TooLarge || too_long != mime.TooLarge { os.exit(11) }
    var lf_state: io.SliceReader = zero
    lf_state.data = "A: 1\nB: 2\n\nrest"
    let (lf_headers, e5) = mime.parse_headers(a, io.slice_reader(&lf_state), 256usize, 8usize)
    if e5 != ok || lf_headers.len != 2usize || !text_equal(lf_headers[1].value, "2") { os.exit(12) }
    os.exit(0)
    ret ok
}
