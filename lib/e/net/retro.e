// The small text protocols of the old and the small internet, as codecs over strings and bytes: Gemini (request
// line, response header, gemtext lines), Gopher (request line, menu items, the terminating dot) and Finger
// (RFC 1288 query line). No sockets here: the caller dials the port (1965, 70, 79), writes `request` and reads the
// reply; a Gemini connection is TLS, which `e.net.tls` provides. Each parser takes a line without its CRLF.
//
// Gemini: a response is `<STATUS><space><META>\r\n` then a body; a status is two digits, the first being the
// class (1 input, 2 success, 3 redirect, 4 temporary failure, 5 permanent failure, 6 client certificate); META is
// at most 1024 bytes. Gemtext lines are classified by their first characters.

error TooLong
error BadHeader
error BadItem

const GEMINI_MAX_URL: usize = 1024usize
const LINE_TEXT: u8 = 0u8
const LINE_LINK: u8 = 1u8
const LINE_HEADING1: u8 = 2u8
const LINE_HEADING2: u8 = 3u8
const LINE_HEADING3: u8 = 4u8
const LINE_LIST: u8 = 5u8
const LINE_QUOTE: u8 = 6u8
const LINE_PRE_TOGGLE: u8 = 7u8

type GeminiResponse = struct { status: u8, meta: str, body_at: usize }
type GopherItem = struct { kind: u8, display: str, selector: str, host: str, port: usize }

fn put_text(out: []u8, at: usize, text: str) -> usize {
    var i = 0usize
    while i < text.len {
        out[at + i] = text[i]
        i += 1usize
    }
    ret at + text.len
}

// ---- Gemini.

// `<url>\r\n` into `out`: the length; TooLong past 1024 bytes of URL (or `out`), Malformed-free: a URL with a
// control byte is `BadHeader`.
fn gemini_request(out: []u8, url: str) -> (usize, err) {
    if url.len > GEMINI_MAX_URL || out.len < url.len + 2usize { ret (0usize, TooLong) }
    var i = 0usize
    while i < url.len {
        if url[i] < 32u8 || url[i] == 127u8 { ret (0usize, BadHeader) }
        i += 1usize
    }
    var at = put_text(out, 0usize, url)
    out[at] = 13u8
    out[at + 1usize] = 10u8
    ret (at + 2usize, ok)
}

// The header at the front of `data`: the status, the meta text (before the CRLF) and where the body starts.
fn gemini_response(data: str) -> (GeminiResponse, err) {
    var r: GeminiResponse = zero
    if data.len < 4usize { ret (r, BadHeader) }
    if data[0usize] < 48u8 || data[0usize] > 57u8 || data[1usize] < 48u8 || data[1usize] > 57u8 { ret (r, BadHeader) }
    if data[2usize] != 32u8 && data[2usize] != 13u8 { ret (r, BadHeader) }
    var end = 2usize
    while end + 1usize < data.len && !(data[end] == 13u8 && data[end + 1usize] == 10u8) {
        end += 1usize
        if end > 1024usize + 3usize { ret (r, BadHeader) }
    }
    if end + 1usize >= data.len { ret (r, BadHeader) }
    r.status = u8((usize(data[0usize]) - 48usize) * 10usize + (usize(data[1usize]) - 48usize))
    var meta_start = 3usize
    if meta_start > end { meta_start = end }
    r.meta = data[meta_start..end]
    r.body_at = end + 2usize
    ret (r, ok)
}

// The kind of a gemtext line (without its line ending). `in_pre` is whether a preformatted block is open: inside
// one, every line is text but the closing toggle.
fn gemini_line_kind(line: str, in_pre: bool) -> u8 {
    if line.len >= 3usize && line[0usize] == 96u8 && line[1usize] == 96u8 && line[2usize] == 96u8 { ret LINE_PRE_TOGGLE }
    if in_pre { ret LINE_TEXT }
    if line.len >= 2usize && line[0usize] == 61u8 && line[1usize] == 62u8 { ret LINE_LINK }
    if line.len >= 3usize && line[0usize] == 35u8 && line[1usize] == 35u8 && line[2usize] == 35u8 { ret LINE_HEADING3 }
    if line.len >= 2usize && line[0usize] == 35u8 && line[1usize] == 35u8 { ret LINE_HEADING2 }
    if line.len >= 1usize && line[0usize] == 35u8 { ret LINE_HEADING1 }
    if line.len >= 2usize && line[0usize] == 42u8 && line[1usize] == 32u8 { ret LINE_LIST }
    if line.len >= 1usize && line[0usize] == 62u8 { ret LINE_QUOTE }
    ret LINE_TEXT
}

// A link line's URL and label: `=>` then spaces or tabs, the URL, then spaces or tabs and the label (possibly empty).
fn gemini_link(line: str) -> (str, str) {
    var i = 2usize
    while i < line.len && (line[i] == 32u8 || line[i] == 9u8) { i += 1usize }
    let url_start = i
    while i < line.len && line[i] != 32u8 && line[i] != 9u8 { i += 1usize }
    let url_end = i
    while i < line.len && (line[i] == 32u8 || line[i] == 9u8) { i += 1usize }
    ret (line[url_start..url_end], line[i..line.len])
}

// ---- Gopher.

// The selector, a tab and the search string when there is one, then CRLF.
fn gopher_request(out: []u8, selector: str, query: str, has_query: bool) -> (usize, err) {
    var need = selector.len + 2usize
    if has_query { need += 1usize + query.len }
    if out.len < need { ret (0usize, TooLong) }
    var at = put_text(out, 0usize, selector)
    if has_query {
        out[at] = 9u8
        at = put_text(out, at + 1usize, query)
    }
    out[at] = 13u8
    out[at + 1usize] = 10u8
    ret (at + 2usize, ok)
}

// One menu line: the item type, then display, selector, host and port separated by tabs. The line "." ends a menu
// (see `gopher_is_end`); a line without the three tabs is `BadItem`.
fn gopher_item(line: str) -> (GopherItem, err) {
    var item: GopherItem = zero
    if line.len == 0usize { ret (item, BadItem) }
    item.kind = line[0usize]
    var tabs: [3]usize = zero
    var found = 0usize
    var i = 1usize
    while i < line.len && found < 3usize {
        if line[i] == 9u8 {
            tabs[found] = i
            found += 1usize
        }
        i += 1usize
    }
    if found < 3usize { ret (item, BadItem) }
    var port_end = line.len
    var j = tabs[2usize] + 1usize
    var scanning = true
    while scanning && j < line.len {
        if line[j] == 9u8 {
            port_end = j
            scanning = false
        } else {
            j += 1usize
        }
    }
    item.display = line[1usize..tabs[0usize]]
    item.selector = line[tabs[0usize] + 1usize..tabs[1usize]]
    item.host = line[tabs[1usize] + 1usize..tabs[2usize]]
    var port = 0usize
    var p = tabs[2usize] + 1usize
    while p < port_end && line[p] >= 48u8 && line[p] <= 57u8 && port < 100000usize {
        port = port * 10usize + usize(line[p] - 48u8)
        p += 1usize
    }
    item.port = port
    ret (item, ok)
}

fn gopher_is_end(line: str) -> bool {
    ret line.len == 1usize && line[0usize] == 46u8
}

// ---- Finger.

// `user\r\n` or, verbose, `/W user\r\n`; an empty user asks for the list of users. A user containing a control
// byte is BadHeader (it would smuggle a second line).
fn finger_request(out: []u8, user: str, verbose: bool) -> (usize, err) {
    var need = user.len + 2usize
    if verbose { need += 3usize }
    if out.len < need { ret (0usize, TooLong) }
    var i = 0usize
    while i < user.len {
        if user[i] < 32u8 || user[i] == 127u8 { ret (0usize, BadHeader) }
        i += 1usize
    }
    var at = 0usize
    if verbose {
        at = put_text(out, 0usize, "/W")
        if user.len > 0usize {
            out[at] = 32u8
            at += 1usize
        }
    }
    at = put_text(out, at, user)
    out[at] = 13u8
    out[at + 1usize] = 10u8
    ret (at + 2usize, ok)
}

// A finger target `user@host` split at the last `@`: the user and the host (empty when there is no `@`).
fn finger_target(spec: str) -> (str, str) {
    var at = spec.len
    var i = spec.len
    while i > 0usize {
        i -= 1usize
        if spec[i] == 64u8 && at == spec.len {
            at = i
            i = 0usize
        }
    }
    if at == spec.len { ret (spec, spec[spec.len..spec.len]) }
    ret (spec[0usize..at], spec[at + 1usize..spec.len])
}
