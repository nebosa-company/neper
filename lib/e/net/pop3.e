// POP3 client (RFC 1939, STLS RFC 2595, CAPA RFC 2449) over any `io.Reader` / `io.Writer` pair. `connect`
// reads the +OK greeting, `starttls` upgrades the same connection through e.net.tls, `login` sends USER and
// PASS, and `stat`, `list`, `uidl`, `retr`, `top`, `dele`, `rset`, `noop` and `quit` are the transaction
// commands. A multi-line answer (RETR, TOP, LIST, UIDL, CAPA) is read to the lone dot, undoing the dot
// stuffing, and the message comes back as bytes with CRLF line ends, ready for `e.fmt.mail.read_message`
// through `io.slice_reader`. Input is buffered, which is safe because POP3 is strictly lock-step: a buffer
// left holding bytes when `starttls` is called would be plaintext injected before the handshake, so that is
// `Protocol`. A -ERR answer is `Rejected` with its text in `Session.last`. A line or command carrying CR, LF
// or NUL is `Invalid` before it is written. No local store, no APOP, no pipelining.

use e.io
use e.mem
use e.net.tls as tls

type Session = struct {
    a: *mem.Arena, source: io.Reader, sink: io.Writer, stream: *tls.Stream, secured: bool,
    greeting: str, last: str, buf: []u8, at: usize, len: usize, line: []u8, cmd: []u8,
}
type Stat = struct { count: usize, octets: u64 }
type Entry = struct { number: usize, size: u64, id: str }

error Protocol
error Rejected
error Closed
error TooLarge
error Invalid
error Unsupported

const LINE_LIMIT: usize = 1024usize
const COMMAND_LIMIT: usize = 512usize

// ---- reading -------------------------------------------------------------------------------------------

fn next_byte(s: *Session) -> (u8, err) {
    if s.at >= s.len {
        var tries = 0usize
        while tries < 8usize {
            let (n, read_error) = io.read(&s.source, s.buf)
            if read_error == io.End { ret (0u8, Closed) }
            if read_error != ok { ret (0u8, read_error) }
            if n > 0usize {
                s.at = 0usize
                s.len = n
                break
            }
            tries += 1usize
        }
        if s.len == 0usize || s.at >= s.len { ret (0u8, Closed) }
    }
    let b = s.buf[s.at]
    s.at += 1usize
    ret (b, ok)
}

// One line without its CRLF (a bare LF is accepted), in `s.line`; its length is answered.
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

fn copy_text(a: *mem.Arena, text: []const u8) -> (str, err) {
    let (kept, alloc_error) = mem.alloc[u8](a, text.len + 1usize)
    if alloc_error != ok { ret ("", alloc_error) }
    mem.copy[u8](kept, text)
    ret (kept[..text.len], ok)
}

// The status line: "+OK text" answers the text, "-ERR text" is Rejected, anything else is Protocol.
fn read_status(s: *Session) -> (str, err) {
    let (n, line_error) = read_line(s)
    if line_error != ok { ret ("", line_error) }
    var cut = 0usize
    var good = false
    if n >= 3usize && s.line[0] == 43u8 && s.line[1] == 79u8 && s.line[2] == 75u8 {
        good = true
        cut = 3usize
    } else if n >= 4usize && s.line[0] == 45u8 && s.line[1] == 69u8 && s.line[2] == 82u8 && s.line[3] == 82u8 {
        cut = 4usize
    } else {
        ret ("", Protocol)
    }
    if cut < n && s.line[cut] != 32u8 { ret ("", Protocol) }
    if cut < n { cut += 1usize }
    let (text, text_error) = copy_text(s.a, s.line[cut..n])
    if text_error != ok { ret ("", text_error) }
    s.last = text
    if !good { ret (text, Rejected) }
    ret (text, ok)
}

// The lines after a +OK, up to the lone dot, dot-unstuffed and joined with CRLF; at most `limit` bytes.
fn read_multiline(s: *Session, limit: usize) -> ([]const u8, err) {
    var capacity = 4096usize
    if capacity > limit { capacity = limit }
    if capacity == 0usize { ret ("", TooLarge) }
    let (first, alloc_error) = mem.alloc[u8](s.a, capacity)
    if alloc_error != ok { ret ("", alloc_error) }
    var out = first
    var used = 0usize
    while true {
        let (n, line_error) = read_line(s)
        if line_error != ok { ret ("", line_error) }
        var from = 0usize
        if n > 0usize && s.line[0] == 46u8 {
            if n == 1usize { break }
            from = 1usize
        }
        let need = used + (n - from) + 2usize
        if need > limit { ret ("", TooLarge) }
        if need > capacity {
            var bigger_size = capacity * 2usize
            while bigger_size < need { bigger_size *= 2usize }
            if bigger_size > limit { bigger_size = limit }
            let (bigger, grow_error) = mem.alloc[u8](s.a, bigger_size)
            if grow_error != ok { ret ("", grow_error) }
            mem.copy[u8](bigger, out[..used])
            out = bigger
            capacity = bigger_size
        }
        mem.copy[u8](out[used..], s.line[from..n])
        used += n - from
        out[used] = 13u8
        out[used + 1usize] = 10u8
        used += 2usize
    }
    ret (out[..used], ok)
}

// ---- commands ------------------------------------------------------------------------------------------

fn clean(text: str) -> bool {
    var i = 0usize
    while i < text.len {
        let b = text[i]
        if b == 13u8 || b == 10u8 || b == 0u8 { ret false }
        i += 1usize
    }
    ret true
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

fn send_line(s: *Session, n: usize) -> err {
    s.cmd[n] = 13u8
    s.cmd[n + 1usize] = 10u8
    try io.write_all(&s.sink, s.cmd[..n + 2usize])
    ret io.flush(&s.sink)
}

// Write `verb [argument [second]]` and read the status line.
fn command(s: *Session, verb: str, argument: str, second: u64, has_second: bool) -> (str, err) {
    if !clean(argument) { ret ("", Invalid) }
    var n = 0usize
    let verb_error = put(s.cmd, &n, verb)
    if verb_error != ok { ret ("", verb_error) }
    if argument.len > 0usize {
        let space_error = put(s.cmd, &n, " ")
        if space_error != ok { ret ("", space_error) }
        let argument_error = put(s.cmd, &n, argument)
        if argument_error != ok { ret ("", argument_error) }
    }
    if has_second {
        let space_error = put(s.cmd, &n, " ")
        if space_error != ok { ret ("", space_error) }
        let number_error = put_decimal(s.cmd, &n, second)
        if number_error != ok { ret ("", number_error) }
    }
    let write_error = send_line(s, n)
    if write_error != ok { ret ("", write_error) }
    let (text, status_error) = read_status(s)
    ret (text, status_error)
}

// A message number as text, kept in the arena (a command argument).
fn number_text(s: *Session, n: usize) -> str {
    var buf: [20]u8 = zero
    var at = 0usize
    let _ = put_decimal(buf[0..], &at, u64(n))
    let (kept, copy_error) = copy_text(s.a, buf[..at])
    if copy_error != ok { ret "" }
    ret kept
}

// Wrap an open connection and read the +OK greeting.
fn connect(a: *mem.Arena, source: io.Reader, sink: io.Writer) -> (Session, err) {
    var empty: Session = zero
    let (buf, buf_error) = mem.alloc[u8](a, 4096usize)
    if buf_error != ok { ret (empty, buf_error) }
    let (line, line_error) = mem.alloc[u8](a, LINE_LIMIT)
    if line_error != ok { ret (empty, line_error) }
    let (cmd, cmd_error) = mem.alloc[u8](a, COMMAND_LIMIT)
    if cmd_error != ok { ret (empty, cmd_error) }
    var s = Session { a: a, source: source, sink: sink, stream: nil, secured: false, greeting: "", last: "", buf: buf, at: 0usize, len: 0usize, line: line, cmd: cmd }
    let (greeting, greeting_error) = read_status(&s)
    if greeting_error != ok { ret (s, greeting_error) }
    s.greeting = greeting
    ret (s, ok)
}

// STLS, then the handshake over the same connection. The connection must be quiet: bytes already buffered
// would have arrived before the handshake and are refused.
fn starttls(s: *Session, config: tls.ClientConfig) -> err {
    if s.secured { ret Unsupported }
    let (_, reply_error) = command(s, "STLS", "", 0u64, false)
    if reply_error != ok { ret reply_error }
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
    ret ok
}

// USER then PASS. The password is not kept.
fn login(s: *Session, user: str, password: str) -> err {
    if user.len == 0usize { ret Invalid }
    let (_, user_error) = command(s, "USER", user, 0u64, false)
    if user_error != ok { ret user_error }
    let (_, pass_error) = command(s, "PASS", password, 0u64, false)
    ret pass_error
}

// The capability lines (CAPA), one per line with CRLF.
fn capa(s: *Session, limit: usize) -> (str, err) {
    let (_, status_error) = command(s, "CAPA", "", 0u64, false)
    if status_error != ok { ret ("", status_error) }
    let (lines, lines_error) = read_multiline(s, limit)
    ret (lines, lines_error)
}

fn parse_number(text: str, at: *usize) -> (u64, bool) {
    var value = 0u64
    var any = false
    while *at < text.len && text[*at] >= 48u8 && text[*at] <= 57u8 {
        let next = value * 10u64 + u64(text[*at] - 48u8)
        if next < value { ret (0u64, false) }
        value = next
        any = true
        *at = *at + 1usize
    }
    ret (value, any)
}

// STAT: the message count and the total size in octets.
fn stat(s: *Session) -> (Stat, err) {
    var none = Stat { count: 0usize, octets: 0u64 }
    let (text, status_error) = command(s, "STAT", "", 0u64, false)
    if status_error != ok { ret (none, status_error) }
    var at = 0usize
    let (count, count_ok) = parse_number(text, &at)
    if !count_ok || at >= text.len || text[at] != 32u8 { ret (none, Protocol) }
    at += 1usize
    let (octets, octets_ok) = parse_number(text, &at)
    if !octets_ok { ret (none, Protocol) }
    ret (Stat { count: usize(count), octets: octets }, ok)
}

// LIST (or UIDL) for every message: `size` for LIST, `id` for UIDL.
fn listing(s: *Session, verb: str, with_id: bool, limit: usize) -> ([]const Entry, err) {
    let (_, status_error) = command(s, verb, "", 0u64, false)
    if status_error != ok { ret (zero, status_error) }
    let (lines, lines_error) = read_multiline(s, limit)
    if lines_error != ok { ret (zero, lines_error) }
    var rows = 0usize
    var i = 0usize
    while i < lines.len {
        if lines[i] == 10u8 { rows += 1usize }
        i += 1usize
    }
    let (entries, alloc_error) = mem.alloc[Entry](s.a, rows + 1usize)
    if alloc_error != ok { ret (zero, alloc_error) }
    var count = 0usize
    var start = 0usize
    while start < lines.len {
        var end = start
        while end < lines.len && lines[end] != 13u8 { end += 1usize }
        let row = lines[start..end]
        var at = 0usize
        let (number, number_ok) = parse_number(row, &at)
        if !number_ok || at >= row.len || row[at] != 32u8 { ret (zero, Protocol) }
        at += 1usize
        if with_id {
            entries[count] = Entry { number: usize(number), size: 0u64, id: row[at..] }
        } else {
            let (size, size_ok) = parse_number(row, &at)
            if !size_ok { ret (zero, Protocol) }
            entries[count] = Entry { number: usize(number), size: size, id: "" }
        }
        count += 1usize
        start = end + 2usize
    }
    ret (entries[..count], ok)
}

fn list(s: *Session, limit: usize) -> ([]const Entry, err) {
    let (entries, entries_error) = listing(s, "LIST", false, limit)
    ret (entries, entries_error)
}

fn uidl(s: *Session, limit: usize) -> ([]const Entry, err) {
    let (entries, entries_error) = listing(s, "UIDL", true, limit)
    ret (entries, entries_error)
}

// RETR: the message as bytes with CRLF line ends, at most `limit` bytes.
fn retr(s: *Session, number: usize, limit: usize) -> ([]const u8, err) {
    if number == 0usize { ret ("", Invalid) }
    let (_, status_error) = command(s, "RETR", number_text(s, number), 0u64, false)
    if status_error != ok { ret ("", status_error) }
    let (body, body_error) = read_multiline(s, limit)
    ret (body, body_error)
}

// TOP: the headers and the first `lines` lines of the body.
fn top(s: *Session, number: usize, lines: usize, limit: usize) -> ([]const u8, err) {
    if number == 0usize { ret ("", Invalid) }
    let (_, status_error) = command(s, "TOP", number_text(s, number), u64(lines), true)
    if status_error != ok { ret ("", status_error) }
    let (body, body_error) = read_multiline(s, limit)
    ret (body, body_error)
}

fn dele(s: *Session, number: usize) -> err {
    if number == 0usize { ret Invalid }
    let (_, status_error) = command(s, "DELE", number_text(s, number), 0u64, false)
    ret status_error
}

fn rset(s: *Session) -> err {
    let (_, status_error) = command(s, "RSET", "", 0u64, false)
    ret status_error
}

fn noop(s: *Session) -> err {
    let (_, status_error) = command(s, "NOOP", "", 0u64, false)
    ret status_error
}

// QUIT (this commits the DELEs), and close the TLS stream when there is one.
fn quit(s: *Session) -> err {
    let (_, status_error) = command(s, "QUIT", "", 0u64, false)
    if status_error != ok { ret status_error }
    if s.secured { ret tls.close(s.stream) }
    ret ok
}
