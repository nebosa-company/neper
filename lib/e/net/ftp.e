// FTP client (RFC 959, EPSV RFC 2428, FTPS RFC 4217, FEAT RFC 2389, SIZE and MDTM RFC 3659) over any
// `io.Reader` / `io.Writer` control pair. `connect` reads the 220 greeting; `auth_tls` upgrades the control
// connection through e.net.tls and then PBSZ 0 / PROT P so every data connection is TLS too; `login`,
// `binary`, `pwd`, `cwd`, `cdup`, `mkd`, `rmd`, `dele`, `rename`, `size`, `mdtm`, `feat`, `noop` and `quit` are
// control commands; `list`, `retrieve`/`retr` and `store` move data over a passive-mode connection the client
// dials itself (EPSV, falling back to PASV). The data connection always goes to the control connection's own
// address (`peer`) and only takes the port from the reply, so a server cannot steer the client to another
// host (FTP bounce). Control input is buffered, safe because the client waits for each reply; bytes left in
// the buffer at `auth_tls` are refused as `Protocol`. A 4xx or 5xx reply is `Rejected` with the reply in
// `Session.last` (`transient` tells them apart). Paths carrying CR, LF or NUL are `Invalid` before they are
// written. Each TLS data connection gets fresh entropy derived by hashing the configured entropy with a
// counter, so no two handshakes share a client random or key. No active mode (PORT/EPRT), no MLSD, no resume,
// no server side.

use e.crypto.hash as hash
use e.io
use e.mem
use e.net
use e.net.tls as tls
use e.str

type Reply = struct { code: u16, text: str, lines: usize }
type Session = struct {
    a: *mem.Arena, source: io.Reader, sink: io.Writer, stream: *tls.Stream, secured: bool, protected: bool,
    peer: net.Address, config: tls.ClientConfig, data_count: u32, broken: bool, greeting: Reply, last: Reply,
    buf: []u8, at: usize, len: usize, line: []u8, text: []u8, cmd: []u8,
}
type Collect = struct { a: *mem.Arena, data: []u8, used: usize, limit: usize, failure: err }

error Protocol
error Rejected
error Closed
error TooLarge
error Invalid
error Unsupported

const LINE_LIMIT: usize = 2048usize
const REPLY_LIMIT: usize = 32768usize
const COMMAND_LIMIT: usize = 2048usize

fn no_reply() -> Reply { ret Reply { code: 0u16, text: "", lines: 0usize } }

// ---- text helpers --------------------------------------------------------------------------------------

fn digit(b: u8) -> bool { ret b >= 48u8 && b <= 57u8 }

fn put(buf: []u8, at: *usize, text: []const u8) -> err {
    if *at + text.len > buf.len { ret TooLarge }
    mem.copy[u8](buf[*at..], text)
    *at = *at + text.len
    ret ok
}

fn clean(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        let b = text[i]
        if b == 13u8 || b == 10u8 || b == 0u8 { ret false }
        i += 1usize
    }
    ret true
}

fn parse_number(text: str, at: *usize) -> (u64, bool) {
    var value = 0u64
    var any = false
    while *at < text.len && digit(text[*at]) {
        let next = value * 10u64 + u64(text[*at] - 48u8)
        if next < value { ret (0u64, false) }
        value = next
        any = true
        *at = *at + 1usize
    }
    ret (value, any)
}

// The port of a 227 reply: `(h1,h2,h3,h4,p1,p2)` anywhere in the text. The host part is read and ignored.
fn parse_pasv(text: str) -> (u16, bool) {
    var at = 0usize
    while at < text.len && !digit(text[at]) { at += 1usize }
    var fields: [6]u64 = zero
    var k = 0usize
    while k < 6usize {
        let (n, n_ok) = parse_number(text, &at)
        if !n_ok || n > 255u64 { ret (0u16, false) }
        fields[k] = n
        k += 1usize
        if k < 6usize {
            if at >= text.len || text[at] != 44u8 { ret (0u16, false) }
            at += 1usize
        }
    }
    ret (u16(fields[4] * 256u64 + fields[5]), true)
}

// The port of a 229 reply: `(|||port|)` with any delimiter character.
fn parse_epsv(text: str) -> (u16, bool) {
    var at = 0usize
    while at < text.len && text[at] != 40u8 { at += 1usize }
    if at + 5usize > text.len { ret (0u16, false) }
    at += 1usize
    let delim = text[at]
    if delim < 33u8 || delim > 126u8 || digit(delim) { ret (0u16, false) }
    if text[at + 1usize] != delim || text[at + 2usize] != delim { ret (0u16, false) }
    at += 3usize
    let (port, port_ok) = parse_number(text, &at)
    if !port_ok || port == 0u64 || port > 65535u64 || at >= text.len || text[at] != delim { ret (0u16, false) }
    ret (u16(port), true)
}

// ---- control replies -----------------------------------------------------------------------------------

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

// One reply: `ddd text`, or `ddd-text` lines up to the closing `ddd text`. The text is the lines joined by \n.
fn read_reply(s: *Session) -> (Reply, err) {
    var used = 0usize
    var code = 0u16
    var lines = 0usize
    var closing = no_reply()
    while true {
        var n = 0usize
        while true {
            let (b, byte_error) = next_byte(s)
            if byte_error != ok { ret (closing, byte_error) }
            if b == 10u8 { break }
            if n >= s.line.len { ret (closing, TooLarge) }
            s.line[n] = b
            n += 1usize
        }
        if n > 0usize && s.line[n - 1usize] == 13u8 { n -= 1usize }
        var last = false
        var start = 0usize
        if lines == 0usize {
            if n < 3usize || !digit(s.line[0]) || !digit(s.line[1]) || !digit(s.line[2]) { ret (closing, Protocol) }
            code = u16(s.line[0] - 48u8) * 100u16 + u16(s.line[1] - 48u8) * 10u16 + u16(s.line[2] - 48u8)
            if n == 3usize {
                last = true
                start = 3usize
            } else if s.line[3] == 32u8 {
                last = true
                start = 4usize
            } else if s.line[3] == 45u8 {
                start = 4usize
            } else {
                ret (closing, Protocol)
            }
        } else if n >= 3usize && digit(s.line[0]) && digit(s.line[1]) && digit(s.line[2]) && u16(s.line[0] - 48u8) * 100u16 + u16(s.line[1] - 48u8) * 10u16 + u16(s.line[2] - 48u8) == code && (n == 3usize || s.line[3] == 32u8) {
            last = true
            start = 3usize
            if n > 3usize { start = 4usize }
        }
        if lines > 0usize {
            if used >= s.text.len { ret (closing, TooLarge) }
            s.text[used] = 10u8
            used += 1usize
        }
        if used + (n - start) > s.text.len { ret (closing, TooLarge) }
        mem.copy[u8](s.text[used..], s.line[start..n])
        used += n - start
        lines += 1usize
        if last { break }
    }
    let (kept, alloc_error) = mem.alloc[u8](s.a, used + 1usize)
    if alloc_error != ok { ret (closing, alloc_error) }
    mem.copy[u8](kept, s.text[..used])
    ret (Reply { code: code, text: kept[..used], lines: lines }, ok)
}

fn transient(r: Reply) -> bool { ret r.code >= 400u16 && r.code < 500u16 }

// Write `verb [argument]` and read its reply.
fn exchange(s: *Session, verb: str, argument: str) -> (Reply, err) {
    if s.broken { ret (no_reply(), Closed) }
    if !clean(argument) { ret (no_reply(), Invalid) }
    var n = 0usize
    let verb_error = put(s.cmd, &n, verb)
    if verb_error != ok { ret (no_reply(), verb_error) }
    if argument.len > 0usize {
        let space_error = put(s.cmd, &n, " ")
        if space_error != ok { ret (no_reply(), space_error) }
        let argument_error = put(s.cmd, &n, argument)
        if argument_error != ok { ret (no_reply(), argument_error) }
    }
    let crlf_error = put(s.cmd, &n, "\r\n")
    if crlf_error != ok { ret (no_reply(), crlf_error) }
    let write_error = io.write_all(&s.sink, s.cmd[..n])
    if write_error != ok { ret (no_reply(), write_error) }
    let flush_error = io.flush(&s.sink)
    if flush_error != ok { ret (no_reply(), flush_error) }
    let (reply, reply_error) = read_reply(s)
    ret (reply, reply_error)
}

// A reply with the wanted first digit; anything else is `Rejected` with the reply kept in `last`.
fn expect(s: *Session, reply: Reply, family: u16) -> err {
    s.last = reply
    if reply.code / 100u16 == family { ret ok }
    ret Rejected
}

fn simple(s: *Session, verb: str, argument: str, family: u16) -> (Reply, err) {
    let (reply, reply_error) = exchange(s, verb, argument)
    if reply_error != ok { ret (reply, reply_error) }
    let status = expect(s, reply, family)
    ret (reply, status)
}

// ---- session -------------------------------------------------------------------------------------------

// Wrap an open control connection and read the greeting. `peer` is the server's address: data connections go there.
fn connect(a: *mem.Arena, source: io.Reader, sink: io.Writer, peer: net.Address) -> (Session, err) {
    var empty: Session = zero
    let (buf, buf_error) = mem.alloc[u8](a, 4096usize)
    if buf_error != ok { ret (empty, buf_error) }
    let (line, line_error) = mem.alloc[u8](a, LINE_LIMIT)
    if line_error != ok { ret (empty, line_error) }
    let (text, text_error) = mem.alloc[u8](a, REPLY_LIMIT)
    if text_error != ok { ret (empty, text_error) }
    let (cmd, cmd_error) = mem.alloc[u8](a, COMMAND_LIMIT)
    if cmd_error != ok { ret (empty, cmd_error) }
    var s = Session {
        a: a, source: source, sink: sink, stream: nil, secured: false, protected: false, peer: peer, config: zero,
        data_count: 0u32, broken: false, greeting: no_reply(), last: no_reply(), buf: buf, at: 0usize, len: 0usize, line: line, text: text, cmd: cmd,
    }
    var greeting = no_reply()
    var greeting_error = ok
    // a 120 reply (service ready in a while) is followed by the real 220
    var tries = 0usize
    while tries < 2usize {
        let (reply, reply_error) = read_reply(&s)
        greeting = reply
        greeting_error = reply_error
        if reply_error != ok || reply.code != 120u16 { break }
        tries += 1usize
    }
    if greeting_error != ok { ret (s, greeting_error) }
    s.greeting = greeting
    s.last = greeting
    if greeting.code != 220u16 { ret (s, Rejected) }
    ret (s, ok)
}

// AUTH TLS, the handshake over the control connection, then PBSZ 0 and PROT P: data connections are TLS from now on.
fn auth_tls(s: *Session, config: tls.ClientConfig) -> err {
    if s.secured { ret Unsupported }
    let (_, auth_error) = simple(s, "AUTH", "TLS", 2u16)
    if auth_error != ok { ret auth_error }
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
    s.config = config
    s.at = 0usize
    s.len = 0usize
    let (_, pbsz_error) = simple(s, "PBSZ", "0", 2u16)
    if pbsz_error != ok { ret pbsz_error }
    let (_, prot_error) = simple(s, "PROT", "P", 2u16)
    if prot_error != ok { ret prot_error }
    s.protected = true
    ret ok
}

// USER, then PASS when the server asks for it (331). 230 right after USER is accepted.
fn login(s: *Session, user: str, password: str) -> err {
    if user.len == 0usize { ret Invalid }
    let (reply, user_error) = exchange(s, "USER", user)
    if user_error != ok { ret user_error }
    s.last = reply
    if reply.code == 230u16 { ret ok }
    if reply.code != 331u16 && reply.code != 332u16 { ret Rejected }
    let (_, pass_error) = simple(s, "PASS", password, 2u16)
    ret pass_error
}

fn binary(s: *Session) -> err {
    let (_, status) = simple(s, "TYPE", "I", 2u16)
    ret status
}

// PWD: the directory inside the quotes of the 257 reply (doubled quotes are one quote).
fn pwd(s: *Session) -> (str, err) {
    let (reply, status) = simple(s, "PWD", "", 2u16)
    if status != ok { ret ("", status) }
    if reply.code != 257u16 { ret ("", Protocol) }
    let text = reply.text
    if text.len == 0usize || text[0] != 34u8 { ret ("", Protocol) }
    let (out, alloc_error) = mem.alloc[u8](s.a, text.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    var n = 0usize
    var i = 1usize
    while i < text.len {
        if text[i] == 34u8 {
            if i + 1usize < text.len && text[i + 1usize] == 34u8 {
                out[n] = 34u8
                n += 1usize
                i += 2usize
                continue
            }
            ret (out[..n], ok)
        }
        out[n] = text[i]
        n += 1usize
        i += 1usize
    }
    ret ("", Protocol)
}

fn cwd(s: *Session, path: str) -> err {
    let (_, status) = simple(s, "CWD", path, 2u16)
    ret status
}

fn cdup(s: *Session) -> err {
    let (_, status) = simple(s, "CDUP", "", 2u16)
    ret status
}

fn mkd(s: *Session, path: str) -> err {
    let (_, status) = simple(s, "MKD", path, 2u16)
    ret status
}

fn rmd(s: *Session, path: str) -> err {
    let (_, status) = simple(s, "RMD", path, 2u16)
    ret status
}

fn dele(s: *Session, path: str) -> err {
    let (_, status) = simple(s, "DELE", path, 2u16)
    ret status
}

// RNFR then RNTO.
fn rename(s: *Session, from: str, to: str) -> err {
    let (_, from_error) = simple(s, "RNFR", from, 3u16)
    if from_error != ok { ret from_error }
    let (_, to_error) = simple(s, "RNTO", to, 2u16)
    ret to_error
}

fn size(s: *Session, path: str) -> (u64, err) {
    let (reply, status) = simple(s, "SIZE", path, 2u16)
    if status != ok { ret (0u64, status) }
    var at = 0usize
    let (n, n_ok) = parse_number(reply.text, &at)
    if !n_ok { ret (0u64, Protocol) }
    ret (n, ok)
}

// MDTM: the modification time as the server wrote it, `YYYYMMDDHHMMSS`.
fn mdtm(s: *Session, path: str) -> (str, err) {
    let (reply, status) = simple(s, "MDTM", path, 2u16)
    if status != ok { ret ("", status) }
    ret (reply.text, ok)
}

// FEAT: the feature lines (the text after the first line), one per line.
fn feat(s: *Session) -> (str, err) {
    let (reply, status) = simple(s, "FEAT", "", 2u16)
    if status != ok { ret ("", status) }
    var i = 0usize
    while i < reply.text.len && reply.text[i] != 10u8 { i += 1usize }
    if i < reply.text.len { i += 1usize }
    ret (reply.text[i..], ok)
}

fn noop(s: *Session) -> err {
    let (_, status) = simple(s, "NOOP", "", 2u16)
    ret status
}

// QUIT, and close the TLS stream when there is one.
fn quit(s: *Session) -> err {
    let (_, status) = simple(s, "QUIT", "", 2u16)
    if status != ok { ret status }
    if s.secured { ret tls.close(s.stream) }
    ret ok
}

// ---- data connections ----------------------------------------------------------------------------------

// EPSV (229), or PASV (227) when the server does not know it: the data port.
fn passive(s: *Session) -> (u16, err) {
    let (reply, reply_error) = exchange(s, "EPSV", "")
    if reply_error != ok { ret (0u16, reply_error) }
    if reply.code == 229u16 {
        s.last = reply
        let (port, port_ok) = parse_epsv(reply.text)
        if !port_ok { ret (0u16, Protocol) }
        ret (port, ok)
    }
    if reply.code != 500u16 && reply.code != 501u16 && reply.code != 502u16 && reply.code != 522u16 {
        s.last = reply
        ret (0u16, Rejected)
    }
    let (second, second_error) = exchange(s, "PASV", "")
    if second_error != ok { ret (0u16, second_error) }
    s.last = second
    if second.code != 227u16 { ret (0u16, Rejected) }
    let (port, port_ok) = parse_pasv(second.text)
    if !port_ok { ret (0u16, Protocol) }
    ret (port, ok)
}

// A fresh 64 bytes of entropy for one data handshake: SHA-256 of the configured entropy, a label and a counter.
fn data_entropy(s: *Session, out: []u8) {
    s.data_count += 1u32
    var seed: [128]u8 = zero
    var n = 0usize
    let room = seed.len - 12usize
    var take = s.config.entropy.len
    if take > room { take = room }
    mem.copy[u8](seed[0..], s.config.entropy[..take])
    n = take
    let label = "ftp-data"
    mem.copy[u8](seed[n..], label)
    n += label.len
    seed[n] = u8(s.data_count & 255u32)
    seed[n + 1usize] = u8((s.data_count / 256u32) & 255u32)
    n += 2usize
    let first = hash.sha256(seed[..n])
    mem.copy[u8](out[..32usize], first[0..])
    seed[n] = 1u8
    let second = hash.sha256(seed[..n + 1usize])
    mem.copy[u8](out[32usize..64usize], second[0..])
}

// Run `command`: connect to the passive port, send it, move bytes between the data connection and `src`
// (upload) or `dst` (download), close the data connection, and read the closing 226 or 250.
fn transfer_inner(s: *Session, verb: str, argument: str, upload: bool, src: io.Reader, dst: io.Writer) -> err {
    let (port, passive_error) = passive(s)
    if passive_error != ok { ret passive_error }
    let (opened, connect_error) = net.tcp_connect(net.Endpoint { address: s.peer, port: port })
    if connect_error != ok { ret connect_error }
    var connection = opened
    defer let _ = net.close(connection)
    let (start, start_error) = exchange(s, verb, argument)
    if start_error != ok { ret start_error }
    s.last = start
    if start.code / 100u16 != 1u16 { ret Rejected }
    var chunk: [4096]u8 = zero
    var source = src
    var sink = dst
    if s.protected {
        var entropy: [64]u8 = zero
        data_entropy(s, entropy[0..])
        var config = s.config
        config.entropy = entropy[0..]
        let (secure0, create_error) = tls.client(s.a, net.reader(&connection), net.writer(&connection), config)
        if create_error != ok { ret create_error }
        var secure = secure0
        let handshake_error = tls.handshake(&secure)
        if handshake_error != ok {
            let _ = tls.close(&secure)
            ret handshake_error
        }
        var secure_source = tls.reader(&secure)
        var secure_sink = tls.writer(&secure)
        let moved = pump(upload, &source, &sink, &secure_source, &secure_sink, chunk[0..])
        let close_error = tls.close(&secure)
        if moved != ok { ret moved }
        if close_error != ok { ret close_error }
    } else {
        var plain_source = net.reader(&connection)
        var plain_sink = net.writer(&connection)
        let moved = pump(upload, &source, &sink, &plain_source, &plain_sink, chunk[0..])
        if moved != ok { ret moved }
        if upload {
            let shut_error = net.shutdown(connection, .Write)
            if shut_error != ok { ret shut_error }
        }
    }
    let (done, done_error) = read_reply(s)
    if done_error != ok { ret done_error }
    s.last = done
    if done.code != 226u16 && done.code != 250u16 { ret Rejected }
    ret ok
}

// A transfer that fails for any reason but the server's own refusal may leave the control channel out of step
// (the closing reply still to come), so the session is dead afterwards: every later command answers `Closed`.
fn transfer(s: *Session, verb: str, argument: str, upload: bool, src: io.Reader, dst: io.Writer) -> err {
    let result = transfer_inner(s, verb, argument, upload, src, dst)
    if result != ok && result != Rejected { s.broken = true }
    ret result
}

// Copy until the source ends: file to wire for an upload, wire to sink for a download.
fn pump(upload: bool, file_source: *io.Reader, file_sink: *io.Writer, wire_source: *io.Reader, wire_sink: *io.Writer, chunk: []u8) -> err {
    while true {
        var from = wire_source
        var to = file_sink
        if upload {
            from = file_source
            to = wire_sink
        }
        let (n, read_error) = io.read(from, chunk)
        if read_error == io.End { break }
        if read_error != ok { ret read_error }
        if n == 0usize { continue }
        try io.write_all(to, chunk[..n])
    }
    if upload { ret io.flush(wire_sink) }
    ret io.flush(file_sink)
}

fn collect_write(ctx: *void, src: []const u8) -> (usize, err) {
    var c = mem.cast[*Collect](ctx)
    let need = c.used + src.len
    if need > c.limit {
        c.failure = TooLarge
        ret (0usize, TooLarge)
    }
    if need > c.data.len {
        var grown = c.data.len * 2usize
        if grown < 4096usize { grown = 4096usize }
        while grown < need { grown *= 2usize }
        if grown > c.limit { grown = c.limit }
        let (bigger, alloc_error) = mem.alloc[u8](c.a, grown)
        if alloc_error != ok {
            c.failure = alloc_error
            ret (0usize, alloc_error)
        }
        mem.copy[u8](bigger, c.data[..c.used])
        c.data = bigger
    }
    mem.copy[u8](c.data[c.used..], src)
    c.used = need
    ret (src.len, ok)
}

fn collect_flush(ctx: *void) -> err { ret ok }

fn empty_read(ctx: *void, dst: []u8) -> (usize, err) { ret (0usize, io.End) }

fn nothing_to_send() -> io.Reader { ret io.Reader { ctx: nil, read: empty_read } }

fn collect_to_buffer(s: *Session, verb: str, argument: str, limit: usize) -> ([]const u8, err) {
    var c = Collect { a: s.a, data: zero, used: 0usize, limit: limit, failure: ok }
    let sink = io.Writer { ctx: mem.cast[*void](&c), write: collect_write, flush: collect_flush }
    let moved = transfer(s, verb, argument, false, nothing_to_send(), sink)
    if c.failure != ok {
        s.broken = true
        ret ("", c.failure)
    }
    if moved != ok { ret ("", moved) }
    ret (c.data[..c.used], ok)
}

// LIST (a directory listing in the server's own format) or NLST (names only), at most `limit` bytes.
fn list(s: *Session, path: str, names_only: bool, limit: usize) -> ([]const u8, err) {
    if !clean(path) { ret ("", Invalid) }
    var verb = "LIST"
    if names_only { verb = "NLST" }
    let (data, data_error) = collect_to_buffer(s, verb, path, limit)
    ret (data, data_error)
}

// RETR into any writer, as the bytes arrive.
fn retr(s: *Session, path: str, dst: io.Writer) -> err {
    if path.len == 0usize || !clean(path) { ret Invalid }
    ret transfer(s, "RETR", path, false, nothing_to_send(), dst)
}

// RETR into memory, at most `limit` bytes.
fn retrieve(s: *Session, path: str, limit: usize) -> ([]const u8, err) {
    if path.len == 0usize || !clean(path) { ret ("", Invalid) }
    let (data, data_error) = collect_to_buffer(s, "RETR", path, limit)
    ret (data, data_error)
}

// STOR from any reader until it ends.
fn store(s: *Session, path: str, src: io.Reader) -> err {
    if path.len == 0usize || !clean(path) { ret Invalid }
    var none = io.Writer { ctx: nil, write: collect_write, flush: collect_flush }
    ret transfer(s, "STOR", path, true, src, none)
}
