// IMAP4rev1 client (RFC 3501, with STARTTLS, AUTHENTICATE PLAIN RFC 4616, UIDs RFC 3501 section 6.4.8) over
// any `io.Reader` / `io.Writer` pair. `connect` reads the greeting, `capability` and `starttls` negotiate,
// `login` and `authenticate_plain` sign in, then `select`, `list`, `search`, `fetch`, `store`, `expunge`,
// `noop`, `close_mailbox` and `logout` run one tagged command each. Every command is sent as `A<n> text`, the
// untagged responses that arrive before the tagged completion are collected, and a literal in a response
// (`{n}` CRLF n bytes) is kept inline in the response text so that `parse_fetch` and the other parsers find
// it by its length. `Section.value` of a FETCH body is the message bytes ready for `e.fmt.mail.read_message`
// through `io.slice_reader`. Input is buffered, which is safe because the client waits for each completion
// before it writes again; bytes left in the buffer when `starttls` is called are refused as `Protocol`. NO is
// `No` and BAD is `Bad`, both with the server's text in `Session.last`. A command argument carrying CR, LF,
// NUL or a byte above 127 is `Invalid` before it is written; mailbox names are the caller's modified UTF-7.
// No APPEND, no IDLE, no LITERAL+ synchronising literals from the client, no local store.

use e.bytes as codec
use e.io
use e.mem
use e.net.tls as tls
use e.str

type Session = struct {
    a: *mem.Arena, source: io.Reader, sink: io.Writer, stream: *tls.Stream, secured: bool,
    greeting: str, last: str, authenticated: bool, caps: Capabilities, tag: u32, limit: usize,
    buf: []u8, at: usize, len: usize, line: []u8, cmd: []u8,
}
type Capabilities = struct { imap4rev1: bool, starttls: bool, login_disabled: bool, auth_plain: bool, sasl_ir: bool, uidplus: bool, idle: bool, move: bool, raw: str }
type Reply = struct { text: str, untagged: []const str }
type Mailbox = struct { exists: u32, recent: u32, uid_validity: u32, uid_next: u32, unseen: u32, flags: str, permanent_flags: str, read_only: bool }
type Name = struct { attributes: str, delimiter: str, name: str }
type Section = struct { key: str, value: str, present: bool }
type FetchData = struct { seq: u32, uid: u32, size: u32, flags: str, internal_date: str, sections: []const Section }
type Buf = struct { data: []u8, used: usize }
type Scan = struct { text: str, at: usize }
type Value = struct { kind: u8, text: str }

const ATOM: u8 = 0u8
const QUOTED: u8 = 1u8
const LITERAL: u8 = 2u8
const LIST: u8 = 3u8
const NIL: u8 = 4u8

error Protocol
error No
error Bad
error Rejected
error Closed
error TooLarge
error Invalid
error Unsupported

const LINE_LIMIT: usize = 8192usize
const COMMAND_LIMIT: usize = 4096usize

fn no_capabilities() -> Capabilities {
    ret Capabilities { imap4rev1: false, starttls: false, login_disabled: false, auth_plain: false, sasl_ir: false, uidplus: false, idle: false, move: false, raw: "" }
}

// ---- text helpers --------------------------------------------------------------------------------------

fn is_digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

fn same_fold(x: str, y: str) -> bool { ret str.compare_ascii_fold(x, y) == 0i32 }

fn starts_fold(text: str, prefix: str) -> bool {
    if text.len < prefix.len { ret false }
    ret same_fold(text[..prefix.len], prefix)
}

// The first index at or after `from` where `needle` starts, ignoring ASCII case; text.len when absent.
fn find_fold(text: str, needle: str, from: usize) -> usize {
    var i = from
    while i + needle.len <= text.len {
        if same_fold(text[i..i + needle.len], needle) { ret i }
        i += 1usize
    }
    ret text.len
}

fn parse_u32(text: str, at: *usize) -> (u32, bool) {
    var value = 0u64
    var any = false
    while *at < text.len && is_digit(text[*at]) {
        value = value * 10u64 + u64(text[*at] - 48u8)
        if value > 4294967295u64 { ret (0u32, false) }
        any = true
        *at = *at + 1usize
    }
    ret (u32(value), any)
}

fn copy_text(a: *mem.Arena, text: []const u8) -> (str, err) {
    let (kept, alloc_error) = mem.alloc[u8](a, text.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    mem.copy[u8](kept, text)
    ret (kept[..text.len], ok)
}

fn put(buf: []u8, at: *usize, text: []const u8) -> err {
    if *at + text.len > buf.len { ret TooLarge }
    mem.copy[u8](buf[*at..], text)
    *at = *at + text.len
    ret ok
}

fn put_decimal(buf: []u8, at: *usize, value: u64) -> err {
    var digits: [20]u8 = zero
    var count = 0usize
    var rest = value
    if rest == 0u64 {
        digits[0] = 48u8
        count = 1usize
    }
    while rest > 0u64 {
        digits[count] = u8(rest % 10u64) + 48u8
        rest = rest / 10u64
        count += 1usize
    }
    var out: [20]u8 = zero
    var i = 0usize
    while i < count {
        out[i] = digits[count - 1usize - i]
        i += 1usize
    }
    ret put(buf, at, out[..count])
}

// A command argument that is safe to write: no CR, LF, NUL or byte above 127.
fn clean(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        let b = text[i]
        if b == 13u8 || b == 10u8 || b == 0u8 || b > 127u8 { ret false }
        i += 1usize
    }
    ret true
}

// `text` as a quoted string, with `"` and `\` escaped.
fn quote(buf: []u8, at: *usize, text: str) -> err {
    if !clean(text) { ret Invalid }
    try put(buf, at, "\"")
    var i = 0usize
    while i < text.len {
        if text[i] == 34u8 || text[i] == 92u8 { try put(buf, at, "\\") }
        try put(buf, at, text[i..i + 1usize])
        i += 1usize
    }
    ret put(buf, at, "\"")
}

// ---- reading -------------------------------------------------------------------------------------------

fn fill(s: *Session) -> err {
    var tries = 0usize
    while tries < 8usize {
        let (n, read_error) = io.read(&s.source, s.buf)
        if read_error == io.End { ret Closed }
        if read_error != ok { ret read_error }
        if n > 0usize {
            s.at = 0usize
            s.len = n
            ret ok
        }
        tries += 1usize
    }
    ret Closed
}

fn next_byte(s: *Session) -> (u8, err) {
    if s.at >= s.len {
        let fill_error = fill(s)
        if fill_error != ok { ret (0u8, fill_error) }
    }
    let b = s.buf[s.at]
    s.at += 1usize
    ret (b, ok)
}

// One line without its CRLF (a bare LF is accepted), in `s.line`.
fn read_line(s: *Session) -> (usize, err) {
    var n = 0usize
    while true {
        let (b, byte_error) = next_byte(s)
        if byte_error != ok { ret (0usize, byte_error) }
        if b == 10u8 { break }
        if n >= s.line.len { ret (0usize, TooLarge) }
        s.line[n] = b
        n += 1usize
    }
    if n > 0usize && s.line[n - 1usize] == 13u8 { n -= 1usize }
    ret (n, ok)
}

fn append(s: *Session, b: *Buf, bytes: []const u8) -> err {
    let need = b.used + bytes.len
    if need > s.limit { ret TooLarge }
    if need > b.data.len {
        var size = b.data.len * 2usize
        if size < 4096usize { size = 4096usize }
        while size < need { size *= 2usize }
        if size > s.limit { size = s.limit }
        let (bigger, alloc_error) = mem.alloc[u8](s.a, size)
        if alloc_error != ok { ret alloc_error }
        mem.copy[u8](bigger, b.data[..b.used])
        b.data = bigger
    }
    mem.copy[u8](b.data[b.used..], bytes)
    b.used = need
    ret ok
}

// Whether a line ends in a literal introducer `{n}` or `{n+}`; the count is answered.
fn literal_size(n: usize, line: []const u8) -> (usize, bool) {
    if n < 3usize || line[n - 1usize] != 125u8 { ret (0usize, false) }
    var end = n - 1usize
    if line[end - 1usize] == 43u8 { end -= 1usize }
    var start = end
    while start > 0usize && is_digit(line[start - 1usize]) { start -= 1usize }
    if start == end || start == 0usize || line[start - 1usize] != 123u8 { ret (0usize, false) }
    var value = 0usize
    var i = start
    while i < end {
        value = value * 10usize + usize(line[i] - 48u8)
        if value > 1073741824usize { ret (0usize, false) }
        i += 1usize
    }
    ret (value, true)
}

// One response: its first line, then for each literal its bytes and the rest of the line, kept verbatim
// (the `{n}` CRLF stays in front of the literal's bytes).
fn read_response(s: *Session) -> (str, err) {
    var out = Buf { data: zero, used: 0usize }
    while true {
        let (n, line_error) = read_line(s)
        if line_error != ok { ret ("", line_error) }
        let (size, is_literal) = literal_size(n, s.line)
        let line_append = append(s, &out, s.line[..n])
        if line_append != ok { ret ("", line_append) }
        if !is_literal { break }
        let crlf_append = append(s, &out, "\r\n")
        if crlf_append != ok { ret ("", crlf_append) }
        var left = size
        while left > 0usize {
            if s.at >= s.len {
                let fill_error = fill(s)
                if fill_error != ok { ret ("", fill_error) }
            }
            var take = s.len - s.at
            if take > left { take = left }
            let data_append = append(s, &out, s.buf[s.at..s.at + take])
            if data_append != ok { ret ("", data_append) }
            s.at += take
            left -= take
        }
    }
    ret (out.data[..out.used], ok)
}

// ---- commands ------------------------------------------------------------------------------------------

fn tag_text(s: *Session, buf: []u8, at: *usize) -> err {
    try put(buf, at, "A")
    ret put_decimal(buf, at, u64(s.tag))
}

// Send `A<n> <text>`; with a continuation, answer the server's `+` with it. Collect the untagged responses
// up to the tagged completion. NO is `No`, BAD is `Bad`; `Reply.text` is the completion's text.
fn run(s: *Session, text: []const u8, continuation: []const u8, has_continuation: bool) -> (Reply, err) {
    var none = Reply { text: "", untagged: zero }
    s.tag += 1u32
    var n = 0usize
    let tag_error = tag_text(s, s.cmd, &n)
    if tag_error != ok { ret (none, tag_error) }
    let tag_len = n
    let space_error = put(s.cmd, &n, " ")
    if space_error != ok { ret (none, space_error) }
    let text_error = put(s.cmd, &n, text)
    if text_error != ok { ret (none, text_error) }
    let crlf_error = put(s.cmd, &n, "\r\n")
    if crlf_error != ok { ret (none, crlf_error) }
    let write_error = io.write_all(&s.sink, s.cmd[..n])
    if write_error != ok { ret (none, write_error) }
    let flush_error = io.flush(&s.sink)
    if flush_error != ok { ret (none, flush_error) }
    var tag: [12]u8 = zero
    mem.copy[u8](tag[0..], s.cmd[..tag_len])
    var items: []str = zero
    var count = 0usize
    var pending = has_continuation
    while true {
        let (response, response_error) = read_response(s)
        if response_error != ok { ret (none, response_error) }
        if response.len >= 1usize && response[0] == 43u8 {
            if !pending { ret (none, Protocol) }
            pending = false
            let (line_buf, line_alloc) = mem.alloc[u8](s.a, continuation.len + 2usize)
            if line_alloc != ok { ret (none, line_alloc) }
            mem.copy[u8](line_buf, continuation)
            line_buf[continuation.len] = 13u8
            line_buf[continuation.len + 1usize] = 10u8
            let cont_error = io.write_all(&s.sink, line_buf[..continuation.len + 2usize])
            if cont_error != ok { ret (none, cont_error) }
            let cont_flush = io.flush(&s.sink)
            if cont_flush != ok { ret (none, cont_flush) }
            continue
        }
        if response.len >= 2usize && response[0] == 42u8 && response[1] == 32u8 {
            if count >= items.len {
                var size = items.len * 2usize
                if size < 16usize { size = 16usize }
                let (bigger, alloc_error) = mem.alloc[str](s.a, size)
                if alloc_error != ok { ret (none, alloc_error) }
                var k = 0usize
                while k < count {
                    bigger[k] = items[k]
                    k += 1usize
                }
                items = bigger
            }
            items[count] = response[2usize..]
            count += 1usize
            continue
        }
        if response.len > tag_len && same_fold(response[..tag_len], tag[..tag_len]) && response[tag_len] == 32u8 {
            let rest = response[tag_len + 1usize..]
            s.last = rest
            var result = Reply { text: rest, untagged: items[..count] }
            if starts_fold(rest, "OK") { ret (result, ok) }
            if starts_fold(rest, "NO") { ret (result, No) }
            if starts_fold(rest, "BAD") { ret (result, Bad) }
            ret (result, Protocol)
        }
        ret (none, Protocol)
    }
    ret (none, Protocol)
}

// Wrap an open connection and read the greeting: `* OK` or `* PREAUTH`. `limit` bounds one response, literals
// included (a fetched message must fit in it).
fn connect(a: *mem.Arena, source: io.Reader, sink: io.Writer, limit: usize) -> (Session, err) {
    var empty: Session = zero
    let (buf, buf_error) = mem.alloc[u8](a, 4096usize)
    if buf_error != ok { ret (empty, buf_error) }
    let (line, line_error) = mem.alloc[u8](a, LINE_LIMIT)
    if line_error != ok { ret (empty, line_error) }
    let (cmd, cmd_error) = mem.alloc[u8](a, COMMAND_LIMIT)
    if cmd_error != ok { ret (empty, cmd_error) }
    var s = Session {
        a: a, source: source, sink: sink, stream: nil, secured: false, greeting: "", last: "", authenticated: false,
        caps: no_capabilities(), tag: 0u32, limit: limit, buf: buf, at: 0usize, len: 0usize, line: line, cmd: cmd,
    }
    let (greeting, greeting_error) = read_response(&s)
    if greeting_error != ok { ret (s, greeting_error) }
    s.greeting = greeting
    s.last = greeting
    if starts_fold(greeting, "* OK") || starts_fold(greeting, "* PREAUTH") {
        s.authenticated = starts_fold(greeting, "* PREAUTH")
        ret (s, ok)
    }
    ret (s, Rejected)
}

fn parse_capabilities(text: str) -> Capabilities {
    var caps = no_capabilities()
    caps.raw = text
    var at = 0usize
    while at < text.len {
        var end = at
        while end < text.len && text[end] != 32u8 { end += 1usize }
        let word = text[at..end]
        if same_fold(word, "IMAP4rev1") { caps.imap4rev1 = true }
        if same_fold(word, "STARTTLS") { caps.starttls = true }
        if same_fold(word, "LOGINDISABLED") { caps.login_disabled = true }
        if same_fold(word, "AUTH=PLAIN") { caps.auth_plain = true }
        if same_fold(word, "SASL-IR") { caps.sasl_ir = true }
        if same_fold(word, "UIDPLUS") { caps.uidplus = true }
        if same_fold(word, "IDLE") { caps.idle = true }
        if same_fold(word, "MOVE") { caps.move = true }
        at = end + 1usize
    }
    ret caps
}

fn capability(s: *Session) -> err {
    let (reply, run_error) = run(s, "CAPABILITY", "", false)
    if run_error != ok { ret run_error }
    var i = 0usize
    while i < reply.untagged.len {
        if starts_fold(reply.untagged[i], "CAPABILITY ") {
            s.caps = parse_capabilities(reply.untagged[i][11usize..])
            ret ok
        }
        i += 1usize
    }
    ret Protocol
}

// STARTTLS, the handshake over the same connection, then CAPABILITY again.
fn starttls(s: *Session, config: tls.ClientConfig) -> err {
    if s.secured { ret Unsupported }
    let (_, run_error) = run(s, "STARTTLS", "", false)
    if run_error != ok { ret run_error }
    if s.at < s.len { ret Protocol }
    let (slot, slot_error) = mem.alloc[tls.Stream](s.a, 1usize)
    if slot_error != ok { ret slot_error }
    let (made, make_error) = tls.client(s.a, s.source, s.sink, config)
    if make_error != ok { ret make_error }
    slot[0] = made
    try tls.handshake(&slot[0])
    s.stream = &slot[0]
    s.source = tls.reader(s.stream)
    s.sink = tls.writer(s.stream)
    s.secured = true
    s.at = 0usize
    s.len = 0usize
    s.caps = no_capabilities()
    ret capability(s)
}

// LOGIN with both arguments quoted; refused when the server advertised LOGINDISABLED.
fn login(s: *Session, user: str, password: str) -> err {
    if s.caps.login_disabled { ret Unsupported }
    var text: [1024]u8 = zero
    var t = 0usize
    try put(text[0..], &t, "LOGIN ")
    try quote(text[0..], &t, user)
    try put(text[0..], &t, " ")
    try quote(text[0..], &t, password)
    let (_, run_error) = run(s, text[..t], "", false)
    var i = 0usize
    while i < text.len {
        text[i] = 0u8
        i += 1usize
    }
    if run_error != ok { ret run_error }
    s.authenticated = true
    ret ok
}

// AUTHENTICATE PLAIN: the server's `+` is answered with the base64 of NUL user NUL password.
fn authenticate_plain(s: *Session, user: str, password: str) -> err {
    if !s.caps.auth_plain { ret Unsupported }
    if !clean(user) || !clean(password) { ret Invalid }
    var raw: [512]u8 = zero
    var r = 0usize
    try put(raw[0..], &r, "\x00")
    try put(raw[0..], &r, user)
    try put(raw[0..], &r, "\x00")
    try put(raw[0..], &r, password)
    var room: [1024]u8 = zero
    let (encoded, encode_error) = codec.base64_encode(room[0..], raw[..r], .Standard, true)
    if encode_error != ok { ret TooLarge }
    let (_, run_error) = run(s, "AUTHENTICATE PLAIN", encoded, true)
    var i = 0usize
    while i < raw.len {
        raw[i] = 0u8
        i += 1usize
    }
    if run_error != ok { ret run_error }
    s.authenticated = true
    ret ok
}

// ---- parsing responses ---------------------------------------------------------------------------------

fn skip_spaces(sc: *Scan) {
    while sc.at < sc.text.len && sc.text[sc.at] == 32u8 { sc.at += 1usize }
}

// The next value: an atom, a quoted string (unescaped), a literal, a parenthesized list (raw, with its
// parentheses) or NIL. A closing parenthesis or the end answers kind 255.
fn next_value(a: *mem.Arena, sc: *Scan) -> (Value, err) {
    skip_spaces(sc)
    if sc.at >= sc.text.len || sc.text[sc.at] == 41u8 { ret (Value { kind: 255u8, text: "" }, ok) }
    let c = sc.text[sc.at]
    if c == 34u8 {
        sc.at += 1usize
        let (out, alloc_error) = mem.alloc[u8](a, sc.text.len - sc.at + 1usize)
        if alloc_error != ok { ret (Value { kind: 255u8, text: "" }, alloc_error) }
        var n = 0usize
        while sc.at < sc.text.len && sc.text[sc.at] != 34u8 {
            if sc.text[sc.at] == 92u8 && sc.at + 1usize < sc.text.len { sc.at += 1usize }
            out[n] = sc.text[sc.at]
            n += 1usize
            sc.at += 1usize
        }
        if sc.at >= sc.text.len { ret (Value { kind: 255u8, text: "" }, Protocol) }
        sc.at += 1usize
        ret (Value { kind: QUOTED, text: out[..n] }, ok)
    }
    if c == 123u8 {
        var at = sc.at + 1usize
        let (size, size_ok) = parse_u32(sc.text, &at)
        if !size_ok { ret (Value { kind: 255u8, text: "" }, Protocol) }
        if at < sc.text.len && sc.text[at] == 43u8 { at += 1usize }
        if at + 3usize > sc.text.len || sc.text[at] != 125u8 || sc.text[at + 1usize] != 13u8 || sc.text[at + 2usize] != 10u8 { ret (Value { kind: 255u8, text: "" }, Protocol) }
        let start = at + 3usize
        if start + usize(size) > sc.text.len { ret (Value { kind: 255u8, text: "" }, Protocol) }
        sc.at = start + usize(size)
        ret (Value { kind: LITERAL, text: sc.text[start..start + usize(size)] }, ok)
    }
    if c == 40u8 {
        let start = sc.at
        var depth = 0usize
        while sc.at < sc.text.len {
            let b = sc.text[sc.at]
            if b == 34u8 {
                sc.at += 1usize
                while sc.at < sc.text.len && sc.text[sc.at] != 34u8 {
                    if sc.text[sc.at] == 92u8 { sc.at += 1usize }
                    sc.at += 1usize
                }
            } else if b == 123u8 {
                let (inner, inner_error) = next_value(a, sc)
                if inner_error != ok || inner.kind == 255u8 { ret (Value { kind: 255u8, text: "" }, Protocol) }
                continue
            } else if b == 40u8 {
                depth += 1usize
            } else if b == 41u8 {
                depth -= 1usize
                if depth == 0usize {
                    sc.at += 1usize
                    ret (Value { kind: LIST, text: sc.text[start..sc.at] }, ok)
                }
            }
            sc.at += 1usize
        }
        ret (Value { kind: 255u8, text: "" }, Protocol)
    }
    let start = sc.at
    while sc.at < sc.text.len && sc.text[sc.at] != 32u8 && sc.text[sc.at] != 41u8 { sc.at += 1usize }
    let word = sc.text[start..sc.at]
    if same_fold(word, "NIL") { ret (Value { kind: NIL, text: "" }, ok) }
    ret (Value { kind: ATOM, text: word }, ok)
}

// A group value without its parentheses.
fn inside(group: str) -> str {
    if group.len >= 2usize && group[0] == 40u8 && group[group.len - 1usize] == 41u8 { ret group[1usize..group.len - 1usize] }
    ret group
}

// `[NAME value]` inside a status text: the value, or "" when the code is absent.
fn bracket_value(item: str, name: str) -> (str, bool) {
    let open = find_fold(item, "[", 0usize)
    if open >= item.len { ret ("", false) }
    if open + 1usize + name.len > item.len || !same_fold(item[open + 1usize..open + 1usize + name.len], name) { ret ("", false) }
    var start = open + 1usize + name.len
    if start < item.len && item[start] == 32u8 { start += 1usize }
    var end = start
    var depth = 0usize
    while end < item.len {
        if item[end] == 40u8 { depth += 1usize }
        if item[end] == 41u8 && depth > 0usize { depth -= 1usize }
        if item[end] == 93u8 && depth == 0usize { break }
        end += 1usize
    }
    ret (item[start..end], true)
}

fn count_item(item: str, word: str) -> (u32, bool) {
    var at = 0usize
    let (n, number_ok) = parse_u32(item, &at)
    if !number_ok || at >= item.len || item[at] != 32u8 { ret (0u32, false) }
    if !same_fold(item[at + 1usize..], word) { ret (0u32, false) }
    ret (n, true)
}

// SELECT or EXAMINE: the mailbox's counts and flags from the untagged responses.
fn open_mailbox(s: *Session, verb: str, name: str) -> (Mailbox, err) {
    var box = Mailbox { exists: 0u32, recent: 0u32, uid_validity: 0u32, uid_next: 0u32, unseen: 0u32, flags: "", permanent_flags: "", read_only: false }
    var text: [1024]u8 = zero
    var t = 0usize
    let verb_error = put(text[0..], &t, verb)
    if verb_error != ok { ret (box, verb_error) }
    let space_error = put(text[0..], &t, " ")
    if space_error != ok { ret (box, space_error) }
    let quote_error = quote(text[0..], &t, name)
    if quote_error != ok { ret (box, quote_error) }
    let (reply, run_error) = run(s, text[..t], "", false)
    if run_error != ok { ret (box, run_error) }
    var i = 0usize
    while i < reply.untagged.len {
        let item = reply.untagged[i]
        let (exists, exists_ok) = count_item(item, "EXISTS")
        if exists_ok { box.exists = exists }
        let (recent, recent_ok) = count_item(item, "RECENT")
        if recent_ok { box.recent = recent }
        if starts_fold(item, "FLAGS ") {
            var sc = Scan { text: item, at: 6usize }
            let (flag_list, list_error) = next_value(s.a, &sc)
            if list_error == ok && flag_list.kind == LIST { box.flags = inside(flag_list.text) }
        }
        if starts_fold(item, "OK ") {
            let (validity, has_validity) = bracket_value(item, "UIDVALIDITY")
            if has_validity {
                var at = 0usize
                let (n, n_ok) = parse_u32(validity, &at)
                if n_ok { box.uid_validity = n }
            }
            let (next, has_next) = bracket_value(item, "UIDNEXT")
            if has_next {
                var at = 0usize
                let (n, n_ok) = parse_u32(next, &at)
                if n_ok { box.uid_next = n }
            }
            let (unseen, has_unseen) = bracket_value(item, "UNSEEN")
            if has_unseen {
                var at = 0usize
                let (n, n_ok) = parse_u32(unseen, &at)
                if n_ok { box.unseen = n }
            }
            let (permanent, has_permanent) = bracket_value(item, "PERMANENTFLAGS")
            if has_permanent { box.permanent_flags = inside(permanent) }
        }
        i += 1usize
    }
    let (_, read_only) = bracket_value(reply.text, "READ-ONLY")
    box.read_only = read_only
    ret (box, ok)
}

fn select(s: *Session, name: str) -> (Mailbox, err) {
    let (box, box_error) = open_mailbox(s, "SELECT", name)
    ret (box, box_error)
}

fn examine(s: *Session, name: str) -> (Mailbox, err) {
    let (box, box_error) = open_mailbox(s, "EXAMINE", name)
    ret (box, box_error)
}

// LIST reference pattern: every `* LIST (attributes) delimiter name`.
fn list(s: *Session, reference: str, pattern: str) -> ([]const Name, err) {
    var text: [1024]u8 = zero
    var t = 0usize
    try put(text[0..], &t, "LIST ")
    try quote(text[0..], &t, reference)
    try put(text[0..], &t, " ")
    try quote(text[0..], &t, pattern)
    let (reply, run_error) = run(s, text[..t], "", false)
    if run_error != ok { ret (zero, run_error) }
    let (names, alloc_error) = mem.alloc[Name](s.a, reply.untagged.len + 1usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    var count = 0usize
    var i = 0usize
    while i < reply.untagged.len {
        let item = reply.untagged[i]
        if starts_fold(item, "LIST ") {
            var sc = Scan { text: item, at: 5usize }
            let (attributes, attributes_error) = next_value(s.a, &sc)
            let (delimiter, delimiter_error) = next_value(s.a, &sc)
            let (name, name_error) = next_value(s.a, &sc)
            if attributes_error != ok || delimiter_error != ok || name_error != ok || attributes.kind != LIST || name.kind == 255u8 { ret (zero, Protocol) }
            names[count] = Name { attributes: inside(attributes.text), delimiter: delimiter.text, name: name.text }
            count += 1usize
        }
        i += 1usize
    }
    ret (names[..count], ok)
}

fn uid_prefix(by_uid: bool) -> str {
    if by_uid { ret "UID " }
    ret ""
}

// SEARCH (or UID SEARCH) with raw criteria, such as `UNSEEN SINCE 1-Jan-2026`: the matching numbers.
fn search(s: *Session, criteria: str, by_uid: bool) -> ([]const u32, err) {
    if !clean(criteria) || criteria.len == 0usize { ret (zero, Invalid) }
    var text: [1024]u8 = zero
    var t = 0usize
    try put(text[0..], &t, uid_prefix(by_uid))
    try put(text[0..], &t, "SEARCH ")
    try put(text[0..], &t, criteria)
    let (reply, run_error) = run(s, text[..t], "", false)
    if run_error != ok { ret (zero, run_error) }
    var total = 0usize
    var i = 0usize
    while i < reply.untagged.len {
        if starts_fold(reply.untagged[i], "SEARCH") { total += reply.untagged[i].len / 2usize + 1usize }
        i += 1usize
    }
    let (found, alloc_error) = mem.alloc[u32](s.a, total + 1usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    var count = 0usize
    i = 0usize
    while i < reply.untagged.len {
        let item = reply.untagged[i]
        if starts_fold(item, "SEARCH") {
            var at = 6usize
            while at < item.len {
                if item[at] == 32u8 {
                    at += 1usize
                    continue
                }
                let (n, n_ok) = parse_u32(item, &at)
                if !n_ok { ret (zero, Protocol) }
                found[count] = n
                count += 1usize
            }
        }
        i += 1usize
    }
    ret (found[..count], ok)
}

// Parse one `n FETCH (...)` untagged response into its fields and its named sections.
fn parse_fetch(a: *mem.Arena, item: str) -> (FetchData, err) {
    var data = FetchData { seq: 0u32, uid: 0u32, size: 0u32, flags: "", internal_date: "", sections: zero }
    var at = 0usize
    let (seq, seq_ok) = parse_u32(item, &at)
    if !seq_ok { ret (data, Protocol) }
    data.seq = seq
    var sc = Scan { text: item, at: at }
    skip_spaces(&sc)
    if !starts_fold(item[sc.at..], "FETCH") { ret (data, Protocol) }
    sc.at += 5usize
    skip_spaces(&sc)
    if sc.at >= item.len || item[sc.at] != 40u8 { ret (data, Protocol) }
    sc.at += 1usize
    let (sections, alloc_error) = mem.alloc[Section](a, 16usize)
    if alloc_error != ok { ret (data, alloc_error) }
    var count = 0usize
    while true {
        skip_spaces(&sc)
        if sc.at >= item.len { ret (data, Protocol) }
        if item[sc.at] == 41u8 { break }
        let (key, key_error) = next_value(a, &sc)
        if key_error != ok || key.kind != ATOM { ret (data, Protocol) }
        // a BODY[...] key may hold spaces inside its brackets (HEADER.FIELDS (From To)); read to the closing ] and <origin>
        var key_text = key.text
        if find_fold(key_text, "[", 0usize) < key_text.len && find_fold(key_text, "]", 0usize) >= key_text.len {
            let key_start = sc.at - key_text.len
            var close = sc.at
            while close < item.len && item[close] != 93u8 { close += 1usize }
            if close >= item.len { ret (data, Protocol) }
            close += 1usize
            while close < item.len && item[close] != 32u8 && item[close] != 41u8 { close += 1usize }
            key_text = item[key_start..close]
            sc.at = close
        }
        let (value, value_error) = next_value(a, &sc)
        if value_error != ok || value.kind == 255u8 { ret (data, Protocol) }
        if same_fold(key_text, "UID") {
            var p = 0usize
            let (n, n_ok) = parse_u32(value.text, &p)
            if n_ok { data.uid = n }
        } else if same_fold(key_text, "RFC822.SIZE") {
            var p = 0usize
            let (n, n_ok) = parse_u32(value.text, &p)
            if n_ok { data.size = n }
        } else if same_fold(key_text, "FLAGS") {
            data.flags = inside(value.text)
        } else if same_fold(key_text, "INTERNALDATE") {
            data.internal_date = value.text
        } else {
            if count >= sections.len { ret (data, TooLarge) }
            sections[count] = Section { key: key_text, value: value.text, present: value.kind != NIL }
            count += 1usize
        }
    }
    data.sections = sections[..count]
    ret (data, ok)
}

// The value of the section named `key` (such as `BODY[]` or `RFC822.HEADER`), and whether it was there.
fn section(data: FetchData, key: str) -> (str, bool) {
    var i = 0usize
    while i < data.sections.len {
        if same_fold(data.sections[i].key, key) && data.sections[i].present { ret (data.sections[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

// Whether a flag such as `\Seen` is among a fetched message's flags.
fn has_flag(data: FetchData, flag: str) -> bool {
    var at = 0usize
    while at < data.flags.len {
        var end = at
        while end < data.flags.len && data.flags[end] != 32u8 { end += 1usize }
        if same_fold(data.flags[at..end], flag) { ret true }
        at = end + 1usize
    }
    ret false
}

// FETCH (or UID FETCH) of a message set such as `1:3,7` with raw items such as `(UID FLAGS BODY.PEEK[])`.
fn fetch(s: *Session, set: str, items: str, by_uid: bool) -> ([]const FetchData, err) {
    if !clean(set) || !clean(items) || set.len == 0usize || items.len == 0usize { ret (zero, Invalid) }
    var text: [1024]u8 = zero
    var t = 0usize
    try put(text[0..], &t, uid_prefix(by_uid))
    try put(text[0..], &t, "FETCH ")
    try put(text[0..], &t, set)
    try put(text[0..], &t, " ")
    try put(text[0..], &t, items)
    let (reply, run_error) = run(s, text[..t], "", false)
    if run_error != ok { ret (zero, run_error) }
    let (out, alloc_error) = mem.alloc[FetchData](s.a, reply.untagged.len + 1usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    var count = 0usize
    var i = 0usize
    while i < reply.untagged.len {
        let item = reply.untagged[i]
        var at = 0usize
        let (_, number_ok) = parse_u32(item, &at)
        if number_ok && at < item.len && starts_fold(item[at + 1usize..], "FETCH") {
            let (parsed, parse_error) = parse_fetch(s.a, item)
            if parse_error != ok { ret (zero, parse_error) }
            out[count] = parsed
            count += 1usize
        }
        i += 1usize
    }
    ret (out[..count], ok)
}

// STORE (or UID STORE) with a raw action such as `+FLAGS.SILENT (\Seen)`.
fn store(s: *Session, set: str, action: str, by_uid: bool) -> err {
    if !clean(set) || !clean(action) || set.len == 0usize || action.len == 0usize { ret Invalid }
    var text: [1024]u8 = zero
    var t = 0usize
    try put(text[0..], &t, uid_prefix(by_uid))
    try put(text[0..], &t, "STORE ")
    try put(text[0..], &t, set)
    try put(text[0..], &t, " ")
    try put(text[0..], &t, action)
    let (_, run_error) = run(s, text[..t], "", false)
    ret run_error
}

// EXPUNGE: how many messages were removed.
fn expunge(s: *Session) -> (usize, err) {
    let (reply, run_error) = run(s, "EXPUNGE", "", false)
    if run_error != ok { ret (0usize, run_error) }
    var removed = 0usize
    var i = 0usize
    while i < reply.untagged.len {
        let (_, is_expunge) = count_item(reply.untagged[i], "EXPUNGE")
        if is_expunge { removed += 1usize }
        i += 1usize
    }
    ret (removed, ok)
}

fn noop(s: *Session) -> err {
    let (_, run_error) = run(s, "NOOP", "", false)
    ret run_error
}

fn close_mailbox(s: *Session) -> err {
    let (_, run_error) = run(s, "CLOSE", "", false)
    ret run_error
}

// LOGOUT, and close the TLS stream when there is one.
fn logout(s: *Session) -> err {
    let (_, run_error) = run(s, "LOGOUT", "", false)
    if run_error != ok { ret run_error }
    if s.secured { ret tls.close(s.stream) }
    ret ok
}
