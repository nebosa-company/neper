// `e.fmt.mime`: media types with token and quoted parameters both ways, the extension
// table, and header blocks from a stream with case-folded lookup, the obsolete folding
// rejected and both limits enforced. Every check has its own exit code.
use e.os
use e.mem
use e.io
use e.test.support
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
    let (_, raw_cr_parameter) = mime.parse_media_type(a, "text/plain; x=\"a\rb\"", 4usize)
    let (_, raw_lf_parameter) = mime.parse_media_type(a, "text/plain; x=\"a\nb\"", 4usize)
    if no_slash != mime.Invalid || bad_param != mime.Invalid || too_many != mime.TooLarge || unterminated != mime.Invalid || raw_cr_parameter != mime.Invalid || raw_lf_parameter != mime.Invalid { os.exit(6) }
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
    // Header parsing stops at the empty line and must leave the message body on
    // the supplied reader for its caller.
    var body_reader = io.slice_reader(&source_state)
    var body: [8]u8 = zero
    let (body_count, body_error) = io.read(&body_reader, body[..])
    if body_error != ok || !text_equal(body[..body_count], "body") { os.exit(14) }
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
    var bare_cr_state: io.SliceReader = zero
    bare_cr_state.data = "X: ok\rInjected: yes\n\n"
    let (_, bare_cr) = mime.parse_headers(a, io.slice_reader(&bare_cr_state), 64usize, 8usize)
    var nul_state: io.SliceReader = zero
    nul_state.data = "X: a\0b\n\n"
    let (_, nul_value) = mime.parse_headers(a, io.slice_reader(&nul_state), 64usize, 8usize)
    var del_state: io.SliceReader = zero
    del_state.data = "X: a\x7fb\n\n"
    let (_, del_value) = mime.parse_headers(a, io.slice_reader(&del_state), 64usize, 8usize)
    var tab_state: io.SliceReader = zero
    tab_state.data = "X: \tallowed\t\n\n"
    let (tab_headers, tab_error) = mime.parse_headers(a, io.slice_reader(&tab_state), 64usize, 8usize)
    if bare_cr != mime.Invalid || nul_value != mime.Invalid || del_value != mime.Invalid || tab_error != ok || tab_headers.len != 1usize || !text_equal(tab_headers[0usize].value, "allowed") { os.exit(13) }
    // EOF may accompany the last byte of a valid header block without dropping it.
    let ended_steps: [1]support.ReadStep = [1]support.ReadStep{ support.ReadStep { bytes: "X-End: complete", failure: io.End } }
    var (ended_script, ended_script_error) = support.scripted_reader(a, ended_steps[..])
    if ended_script_error != ok { os.exit(15) }
    let ended_source = support.reader(&ended_script)
    let (ended_headers, ended_error) = mime.parse_headers(a, ended_source, 64usize, 8usize)
    if ended_error != ok || ended_headers.len != 1usize || !text_equal(ended_headers[0usize].value, "complete") { os.exit(16) }
    // #162: an empty header block is an empty block, not header lines.
    var empty_state: io.SliceReader = zero
    empty_state.data = "\r\nbody"
    let (empty_headers, empty_error) = mime.parse_headers(a, io.slice_reader(&empty_state), 64usize, 8usize)
    if empty_error != ok || empty_headers.len != 0usize { os.exit(40) }
    var empty_reader = io.slice_reader(&empty_state)
    var empty_body: [8]u8 = zero
    let (empty_count, empty_read_error) = io.read(&empty_reader, empty_body[..])
    if empty_read_error != ok || !text_equal(empty_body[..empty_count], "body") { os.exit(41) }
    // #162: the writer validates the type, parameter names and values before emitting.
    let (_, bad_major) = mime.format_media_type(a, mime.MediaType { major: "text\r\nX-Injected: yes", subtype: "plain", parameters: zero })
    if bad_major != mime.Invalid { os.exit(42) }
    let (_, bad_subtype) = mime.format_media_type(a, mime.MediaType { major: "text", subtype: "pl;ain", parameters: zero })
    if bad_subtype != mime.Invalid { os.exit(43) }
    var bad_params: [1]mime.Parameter = zero
    bad_params[0] = mime.Parameter { name: "x", value: "1\r\n\r\n--B" }
    let (_, bad_param_value) = mime.format_media_type(a, mime.MediaType { major: "text", subtype: "plain", parameters: bad_params[0..] })
    if bad_param_value != mime.Invalid { os.exit(44) }
    var bad_name_param: [1]mime.Parameter = zero
    bad_name_param[0] = mime.Parameter { name: "x\r\nY", value: "v" }
    let (_, bad_param_name) = mime.format_media_type(a, mime.MediaType { major: "text", subtype: "plain", parameters: bad_name_param[0..] })
    if bad_param_name != mime.Invalid { os.exit(45) }
    var ok_params: [1]mime.Parameter = zero
    ok_params[0] = mime.Parameter { name: "title", value: "a b" }
    let (quoted_type, quoted_error) = mime.format_media_type(a, mime.MediaType { major: "text", subtype: "plain", parameters: ok_params[0..] })
    if quoted_error != ok || !text_equal(quoted_type, "text/plain; title=\"a b\"") { os.exit(46) }
    os.exit(0)
    ret ok
}
