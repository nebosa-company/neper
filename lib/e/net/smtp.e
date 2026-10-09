// SMTP submission client (RFC 5321, with EHLO extensions RFC 1869, STARTTLS RFC 3207, SIZE RFC 1870,
// AUTH RFC 4954) over any `io.Reader` / `io.Writer` pair: a socket from e.net, a pipe, or a TLS stream.
// `connect` reads the greeting, `ehlo` learns the server's capabilities (falling back to HELO), `starttls`
// upgrades the same connection through e.net.tls and says EHLO again, `auth` picks PLAIN, LOGIN or XOAUTH2
// from what the server offers, and `send` runs MAIL FROM, RCPT TO, DATA for one message read from an
// `io.Reader`, dot-stuffing it and turning bare CR or LF into CRLF on the way. Replies are read byte by byte,
// so nothing is buffered past a reply (a STARTTLS handshake can follow the 220 at once); a command is never
// pipelined. Addresses are checked before they reach the wire: no control characters, spaces, angle
// brackets or non-ASCII, which also closes command injection through a recipient. A non-2xx/3xx reply is the
// error `Rejected` with the reply kept in `Session.last`; `transient` tells 4xx (try later) from 5xx.
// No mailbox storage, no message composition (e.fmt.mail parses; the caller supplies the bytes), no CRAM-MD5,
// no SMTPUTF8 and no pipelining.

use e.bytes as codec
use e.io
use e.mem
use e.net.tls as tls
use e.str

type Reply = struct { code: u16, text: str, lines: usize }
type Capabilities = struct {
    starttls: bool, pipelining: bool, eight_bit: bool, utf8: bool, enhanced: bool, size: u64,
    auth_plain: bool, auth_login: bool, auth_xoauth2: bool,
}
type Rejection = struct { address: str, code: u16 }
type Sent = struct { rejected: []const Rejection, accepted: usize, reply: Reply }
type Session = struct {
    a: *mem.Arena, source: io.Reader, sink: io.Writer, stream: *tls.Stream, secured: bool,
    local: str, greeting: Reply, caps: Capabilities, last: Reply, line: []u8, text: []u8, cmd: []u8,
}

error Protocol
error Rejected
error Closed
error Unsupported
error TooLarge
error Invalid

const LINE_LIMIT: usize = 1024usize
const REPLY_LIMIT: usize = 16384usize
const COMMAND_LIMIT: usize = 4096usize

fn no_reply() -> Reply { ret Reply { code: 0u16, text: "", lines: 0usize } }

fn no_capabilities() -> Capabilities {
    ret Capabilities {
        starttls: false, pipelining: false, eight_bit: false, utf8: false, enhanced: false, size: 0u64,
        auth_plain: false, auth_login: false, auth_xoauth2: false,
    }
}

// ---- replies -----------------------------------------------------------------------------------------

fn read_byte(s: *Session) -> (u8, err) {
    var one: [1]u8 = zero
    var tries = 0usize
    while tries < 8usize {
        let (n, read_error) = io.read(&s.source, one[0..])
        if read_error == io.End { ret (0u8, Closed) }
        if read_error != ok { ret (0u8, read_error) }
        if n == 1usize { ret (one[0], ok) }
        tries += 1usize
    }
    ret (0u8, Closed)
}

fn digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

// One reply, possibly several `ddd-text` lines closed by `ddd text`. The text is the lines joined by \n.
fn read_reply(s: *Session) -> (Reply, err) {
    var used = 0usize
    var code = 0u16
    var lines = 0usize
    while true {
        var n = 0usize
        while true {
            let (b, byte_error) = read_byte(s)
            if byte_error != ok { ret (no_reply(), byte_error) }
            if b == 10u8 { break }
            if n >= s.line.len { ret (no_reply(), TooLarge) }
            s.line[n] = b
            n += 1usize
        }
        if n > 0usize && s.line[n - 1usize] == 13u8 { n -= 1usize }
        if n < 3usize || !digit(s.line[0]) || !digit(s.line[1]) || !digit(s.line[2]) { ret (no_reply(), Protocol) }
        let here = u16(s.line[0] - 48u8) * 100u16 + u16(s.line[1] - 48u8) * 10u16 + u16(s.line[2] - 48u8)
        if lines == 0usize { code = here } else if here != code { ret (no_reply(), Protocol) }
        var last = true
        if n > 3usize {
            if s.line[3] == 45u8 { last = false } else if s.line[3] != 32u8 { ret (no_reply(), Protocol) }
        }
        var start = 3usize
        if n > 3usize { start = 4usize }
        if lines > 0usize {
            if used >= s.text.len { ret (no_reply(), TooLarge) }
            s.text[used] = 10u8
            used += 1usize
        }
        if used + (n - start) > s.text.len { ret (no_reply(), TooLarge) }
        mem.copy[u8](s.text[used..], s.line[start..n])
        used += n - start
        lines += 1usize
        if last { break }
    }
    let (kept, alloc_error) = mem.alloc[u8](s.a, used + 1usize)
    if alloc_error != ok { ret (no_reply(), alloc_error) }
    mem.copy[u8](kept, s.text[..used])
    ret (Reply { code: code, text: kept[..used], lines: lines }, ok)
}

// The enhanced status code (RFC 2034) opening a reply's text, such as `2.1.5`, or "" when it has none.
fn enhanced(r: Reply) -> str {
    var at = 0usize
    var dots = 0usize
    while at < r.text.len {
        let b = r.text[at]
        if b == 46u8 {
            dots += 1usize
        } else if !digit(b) {
            break
        }
        at += 1usize
    }
    if dots == 2usize && at >= 5usize && (at == r.text.len || r.text[at] == 32u8) { ret r.text[..at] }
    ret ""
}

fn transient(r: Reply) -> bool { ret r.code >= 400u16 && r.code < 500u16 }

// ---- commands ----------------------------------------------------------------------------------------

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

fn send_line(s: *Session, n: usize) -> err {
    s.cmd[n] = 13u8
    s.cmd[n + 1usize] = 10u8
    try io.write_all(&s.sink, s.cmd[..n + 2usize])
    ret io.flush(&s.sink)
}

// Write `line` (without CRLF) and read the reply to it.
fn exchange(s: *Session, line: []const u8) -> (Reply, err) {
    if line.len + 2usize > s.cmd.len { ret (no_reply(), TooLarge) }
    mem.copy[u8](s.cmd, line)
    let write_error = send_line(s, line.len)
    if write_error != ok { ret (no_reply(), write_error) }
    let (reply, reply_error) = read_reply(s)
    ret (reply, reply_error)
}

// A reply in the 2xx or 3xx family, else `Rejected` with it kept in `last`.
fn accept(s: *Session, r: Reply, want: u16) -> err {
    s.last = r
    if r.code == want { ret ok }
    if r.code >= 200u16 && r.code < 400u16 && want == 0u16 { ret ok }
    ret Rejected
}

fn path_ok(address: str) -> bool {
    var i = 0usize
    while i < address.len {
        let b = address[i]
        if b <= 32u8 || b >= 127u8 || b == 60u8 || b == 62u8 { ret false }
        i += 1usize
    }
    ret true
}

fn domain_ok(name: str) -> bool { ret name.len > 0usize && path_ok(name) }

// ---- session -----------------------------------------------------------------------------------------

// Wrap an open connection and read the server's greeting (220).
fn connect(a: *mem.Arena, source: io.Reader, sink: io.Writer, local: str) -> (Session, err) {
    var empty: Session = zero
    if !domain_ok(local) { ret (empty, Invalid) }
    let (line, line_error) = mem.alloc[u8](a, LINE_LIMIT)
    if line_error != ok { ret (empty, line_error) }
    let (text, text_error) = mem.alloc[u8](a, REPLY_LIMIT)
    if text_error != ok { ret (empty, text_error) }
    let (cmd, cmd_error) = mem.alloc[u8](a, COMMAND_LIMIT)
    if cmd_error != ok { ret (empty, cmd_error) }
    var s = Session {
        a: a, source: source, sink: sink, stream: nil, secured: false, local: local, greeting: no_reply(),
        caps: no_capabilities(), last: no_reply(), line: line, text: text, cmd: cmd,
    }
    let (greeting, greeting_error) = read_reply(&s)
    if greeting_error != ok { ret (s, greeting_error) }
    s.greeting = greeting
    s.last = greeting
    if greeting.code != 220u16 { ret (s, Rejected) }
    ret (s, ok)
}

fn parse_size(text: str) -> u64 {
    var value = 0u64
    var i = 0usize
    while i < text.len && digit(text[i]) {
        let next = value * 10u64 + u64(text[i] - 48u8)
        if next < value { ret 0u64 }
        value = next
        i += 1usize
    }
    ret value
}

fn word_end(text: str, from: usize) -> usize {
    var at = from
    while at < text.len && text[at] != 32u8 { at += 1usize }
    ret at
}

fn parse_capabilities(text: str) -> Capabilities {
    var caps = no_capabilities()
    var at = 0usize
    var first = true
    while at <= text.len {
        var end = at
        while end < text.len && text[end] != 10u8 { end += 1usize }
        if !first {
            let line = text[at..end]
            let key_end = word_end(line, 0usize)
            let key = line[..key_end]
            var rest = ""
            if key_end < line.len { rest = line[key_end + 1usize..] }
            if str.compare_ascii_fold(key, "STARTTLS") == 0i32 { caps.starttls = true }
            if str.compare_ascii_fold(key, "PIPELINING") == 0i32 { caps.pipelining = true }
            if str.compare_ascii_fold(key, "8BITMIME") == 0i32 { caps.eight_bit = true }
            if str.compare_ascii_fold(key, "SMTPUTF8") == 0i32 { caps.utf8 = true }
            if str.compare_ascii_fold(key, "ENHANCEDSTATUSCODES") == 0i32 { caps.enhanced = true }
            if str.compare_ascii_fold(key, "SIZE") == 0i32 { caps.size = parse_size(rest) }
            if str.compare_ascii_fold(key, "AUTH") == 0i32 {
                var m = 0usize
                while m < rest.len {
                    let m_end = word_end(rest, m)
                    let mechanism = rest[m..m_end]
                    if str.compare_ascii_fold(mechanism, "PLAIN") == 0i32 { caps.auth_plain = true }
                    if str.compare_ascii_fold(mechanism, "LOGIN") == 0i32 { caps.auth_login = true }
                    if str.compare_ascii_fold(mechanism, "XOAUTH2") == 0i32 { caps.auth_xoauth2 = true }
                    m = m_end + 1usize
                }
            }
        }
        first = false
        at = end + 1usize
    }
    ret caps
}

// EHLO; a server that does not know it (500, 501, 502, 504) gets HELO and no extensions.
fn ehlo(s: *Session) -> err {
    var n = 0usize
    try put(s.cmd, &n, "EHLO ")
    try put(s.cmd, &n, s.local)
    let (reply, reply_error) = exchange(s, s.cmd[..n])
    if reply_error != ok { ret reply_error }
    if reply.code == 250u16 {
        s.last = reply
        s.caps = parse_capabilities(reply.text)
        ret ok
    }
    if reply.code == 500u16 || reply.code == 501u16 || reply.code == 502u16 || reply.code == 504u16 {
        var m = 0usize
        try put(s.cmd, &m, "HELO ")
        try put(s.cmd, &m, s.local)
        let (second, second_error) = exchange(s, s.cmd[..m])
        if second_error != ok { ret second_error }
        try accept(s, second, 250u16)
        s.caps = no_capabilities()
        ret ok
    }
    s.last = reply
    ret Rejected
}

// STARTTLS: ask, run the handshake over the same connection, and say EHLO again over it.
fn starttls(s: *Session, config: tls.ClientConfig) -> err {
    if s.secured { ret Unsupported }
    if !s.caps.starttls { ret Unsupported }
    let (reply, reply_error) = exchange(s, "STARTTLS")
    if reply_error != ok { ret reply_error }
    try accept(s, reply, 220u16)
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
    s.caps = no_capabilities()
    ret ehlo(s)
}

fn base64_of(buf: []u8, at: *usize, raw: []const u8) -> err {
    var room: [1536]u8 = zero
    let (text, encode_error) = codec.base64_encode(room[0..], raw, .Standard, true)
    if encode_error != ok { ret TooLarge }
    ret put(buf, at, text)
}

fn wipe(buf: []u8) {
    var i = 0usize
    while i < buf.len {
        buf[i] = 0u8
        i += 1usize
    }
}

// AUTH PLAIN with the initial response (RFC 4616).
fn auth_plain(s: *Session, user: str, password: str) -> err {
    if !s.caps.auth_plain { ret Unsupported }
    var raw: [1024]u8 = zero
    var r = 0usize
    try put(raw[0..], &r, "\x00")
    try put(raw[0..], &r, user)
    try put(raw[0..], &r, "\x00")
    try put(raw[0..], &r, password)
    var n = 0usize
    try put(s.cmd, &n, "AUTH PLAIN ")
    try base64_of(s.cmd, &n, raw[..r])
    let (reply, reply_error) = exchange(s, s.cmd[..n])
    wipe(raw[0..])
    if reply_error != ok { ret reply_error }
    ret accept(s, reply, 235u16)
}

// AUTH LOGIN: the server prompts for the user name and then the password, each base64.
fn auth_login(s: *Session, user: str, password: str) -> err {
    if !s.caps.auth_login { ret Unsupported }
    let (prompt, prompt_error) = exchange(s, "AUTH LOGIN")
    if prompt_error != ok { ret prompt_error }
    try accept(s, prompt, 334u16)
    var n = 0usize
    try base64_of(s.cmd, &n, user)
    let (second, second_error) = exchange(s, s.cmd[..n])
    if second_error != ok { ret second_error }
    try accept(s, second, 334u16)
    var m = 0usize
    try base64_of(s.cmd, &m, password)
    let (reply, reply_error) = exchange(s, s.cmd[..m])
    if reply_error != ok { ret reply_error }
    ret accept(s, reply, 235u16)
}

// AUTH XOAUTH2 with a bearer token; a 334 answer is an error document the client must cancel.
fn auth_xoauth2(s: *Session, user: str, token: str) -> err {
    if !s.caps.auth_xoauth2 { ret Unsupported }
    var raw: [1024]u8 = zero
    var r = 0usize
    try put(raw[0..], &r, "user=")
    try put(raw[0..], &r, user)
    try put(raw[0..], &r, "\x01auth=Bearer ")
    try put(raw[0..], &r, token)
    try put(raw[0..], &r, "\x01\x01")
    var n = 0usize
    try put(s.cmd, &n, "AUTH XOAUTH2 ")
    try base64_of(s.cmd, &n, raw[..r])
    let (reply, reply_error) = exchange(s, s.cmd[..n])
    wipe(raw[0..])
    if reply_error != ok { ret reply_error }
    if reply.code == 334u16 {
        let (cancelled, cancel_error) = exchange(s, "")
        if cancel_error != ok { ret cancel_error }
        s.last = cancelled
        ret Rejected
    }
    ret accept(s, reply, 235u16)
}

// PLAIN when offered, else LOGIN, else XOAUTH2 is never guessed (it needs a token, not a password).
fn auth(s: *Session, user: str, password: str) -> err {
    if s.caps.auth_plain { ret auth_plain(s, user, password) }
    if s.caps.auth_login { ret auth_login(s, user, password) }
    ret Unsupported
}

fn command_with_path(s: *Session, verb: str, address: str, extra: []const u8) -> (Reply, err) {
    var n = 0usize
    let prefix_error = put(s.cmd, &n, verb)
    if prefix_error != ok { ret (no_reply(), prefix_error) }
    let open_error = put(s.cmd, &n, "<")
    if open_error != ok { ret (no_reply(), open_error) }
    let address_error = put(s.cmd, &n, address)
    if address_error != ok { ret (no_reply(), address_error) }
    let close_error = put(s.cmd, &n, ">")
    if close_error != ok { ret (no_reply(), close_error) }
    let extra_error = put(s.cmd, &n, extra)
    if extra_error != ok { ret (no_reply(), extra_error) }
    let (reply, reply_error) = exchange(s, s.cmd[..n])
    ret (reply, reply_error)
}

fn reset(s: *Session) -> err {
    let (reply, reply_error) = exchange(s, "RSET")
    if reply_error != ok { ret reply_error }
    ret accept(s, reply, 250u16)
}

fn noop(s: *Session) -> err {
    let (reply, reply_error) = exchange(s, "NOOP")
    if reply_error != ok { ret reply_error }
    ret accept(s, reply, 250u16)
}

fn emit(out: []u8, n: *usize, b: u8) {
    out[*n] = b
    *n = *n + 1usize
}

// Dot-stuffing and CRLF normalisation state, carried across chunks of one message.
type Stuffer = struct { line_start: bool, after_cr: bool, wrote: usize }


// Stuff one chunk into `out` (3 bytes of room per input byte at most) and answer how many bytes it made.
fn stuff(st: *Stuffer, out: []u8, chunk: []const u8) -> usize {
    var n = 0usize
    var i = 0usize
    while i < chunk.len {
        let b = chunk[i]
        i += 1usize
        if st.after_cr {
            st.after_cr = false
            if b == 10u8 {
                emit(out, &n, 10u8)
                st.line_start = true
                continue
            }
            emit(out, &n, 10u8)
            st.line_start = true
        }
        if b == 13u8 {
            emit(out, &n, 13u8)
            st.after_cr = true
            continue
        }
        if b == 10u8 {
            emit(out, &n, 13u8)
            emit(out, &n, 10u8)
            st.line_start = true
            continue
        }
        if st.line_start && b == 46u8 { emit(out, &n, 46u8) }
        emit(out, &n, b)
        st.line_start = false
    }
    st.wrote += n
    ret n
}

// Send one message: MAIL FROM, RCPT TO for each recipient, DATA, the body, the closing dot. `from` may be ""
// (the null reverse path). `size_hint` is the body's byte count when known (0 when not): it goes out as
// SIZE= and a message above the server's advertised limit fails with TooLarge before anything is sent.
// Recipients the server refuses are listed in `Sent.rejected`; when none is accepted the transaction is reset
// and the result is `Rejected`. The body may use bare LF line ends; it need not end in a newline.
fn send(s: *Session, from: str, recipients: []const str, body: io.Reader, size_hint: u64) -> (Sent, err) {
    var none = Sent { rejected: zero, accepted: 0usize, reply: no_reply() }
    if (from.len > 0usize && !path_ok(from)) || recipients.len == 0usize { ret (none, Invalid) }
    var r = 0usize
    while r < recipients.len {
        if !domain_ok(recipients[r]) { ret (none, Invalid) }
        r += 1usize
    }
    if s.caps.size > 0u64 && size_hint > s.caps.size { ret (none, TooLarge) }
    var extra_buf: [32]u8 = zero
    var e = 0usize
    if s.caps.size > 0u64 && size_hint > 0u64 {
        let size_error = put(extra_buf[0..], &e, " SIZE=")
        if size_error != ok { ret (none, size_error) }
        let digits_error = put_decimal(extra_buf[0..], &e, size_hint)
        if digits_error != ok { ret (none, digits_error) }
    }
    let (mail, mail_error) = command_with_path(s, "MAIL FROM:", from, extra_buf[..e])
    if mail_error != ok { ret (none, mail_error) }
    let mail_status = accept(s, mail, 250u16)
    if mail_status != ok { ret (none, mail_status) }
    let (rejected, rejected_error) = mem.alloc[Rejection](s.a, recipients.len)
    if rejected_error != ok { ret (none, rejected_error) }
    var refused = 0usize
    var accepted = 0usize
    var k = 0usize
    while k < recipients.len {
        let (reply, reply_error) = command_with_path(s, "RCPT TO:", recipients[k], "")
        if reply_error != ok { ret (none, reply_error) }
        s.last = reply
        if reply.code == 250u16 || reply.code == 251u16 {
            accepted += 1usize
        } else {
            rejected[refused] = Rejection { address: recipients[k], code: reply.code }
            refused += 1usize
        }
        k += 1usize
    }
    if accepted == 0usize {
        let last = s.last
        let _ = reset(s)
        s.last = last
        ret (Sent { rejected: rejected[..refused], accepted: 0usize, reply: last }, Rejected)
    }
    let (go, go_error) = exchange(s, "DATA")
    if go_error != ok { ret (none, go_error) }
    let go_status = accept(s, go, 354u16)
    if go_status != ok { ret (none, go_status) }
    var source = body
    var st = Stuffer { line_start: true, after_cr: false, wrote: 0usize }
    var inbuf: [512]u8 = zero
    var out: [1536]u8 = zero
    while true {
        let (got, read_error) = io.read(&source, inbuf[0..])
        if read_error == io.End { break }
        if read_error != ok { ret (none, read_error) }
        if got == 0usize { continue }
        let made = stuff(&st, out[0..], inbuf[..got])
        let write_error = io.write_all(&s.sink, out[..made])
        if write_error != ok { ret (none, write_error) }
    }
    var tail: [8]u8 = zero
    var t = 0usize
    if st.after_cr { emit(tail[0..], &t, 10u8) }
    if st.after_cr || !st.line_start {
        emit(tail[0..], &t, 13u8)
        emit(tail[0..], &t, 10u8)
    }
    emit(tail[0..], &t, 46u8)
    emit(tail[0..], &t, 13u8)
    emit(tail[0..], &t, 10u8)
    let end_error = io.write_all(&s.sink, tail[..t])
    if end_error != ok { ret (none, end_error) }
    let flush_error = io.flush(&s.sink)
    if flush_error != ok { ret (none, flush_error) }
    let (done, done_error) = read_reply(s)
    if done_error != ok { ret (none, done_error) }
    let done_status = accept(s, done, 250u16)
    let result = Sent { rejected: rejected[..refused], accepted: accepted, reply: done }
    if done_status != ok { ret (result, done_status) }
    ret (result, ok)
}

// QUIT, and close the TLS stream when there is one.
fn quit(s: *Session) -> err {
    let (reply, reply_error) = exchange(s, "QUIT")
    if reply_error != ok { ret reply_error }
    try accept(s, reply, 221u16)
    if s.secured { ret tls.close(s.stream) }
    ret ok
}
