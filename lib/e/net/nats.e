// NATS core protocol client (L115): the text wire protocol over caller buffers, plus the client state a connection
// needs (subscriptions with queue groups and auto-unsubscribe, ping/pong, request-reply inboxes). No sockets: the
// caller moves bytes, exactly as `e.net.mqtt` does. Encoders write into `dst` and answer the count; `parse` reads one
// server operation from the front of a byte stream and answers how many bytes it consumed, or `Incomplete` when the
// stream holds only part of one (call again with more bytes; `needed` says how many a header-complete message is
// still short of). Operation names are case-insensitive, as the protocol specifies. Subjects follow the NATS rules:
// dot-separated non-empty tokens without whitespace, `*` one token and `>` the tail (only as the last token) for
// subscriptions, neither for a publish. Headers (`HPUB`/`HMSG`, NATS/1.0 with inline status such as 503 for no
// responders) are supported. JetStream and TLS upgrade are out of scope; the INFO answer says when TLS is required.
//
// Memory: nothing allocates; `Op` and `Message` borrow the input buffer, `Sub` borrows its subject text.
use e.mem
use e.str

error Incomplete
error Invalid
error TooLarge
error TooSmall

type Message = struct { subject: str, sid: u64, reply: str, headers: []const u8, payload: []const u8 }
type Op = union enum u8 { None, Info: str, Msg: Message, Ok, Err: str, Ping, Pong }
type Info = struct { server_id: str, version: str, host: str, port: u32, max_payload: u64, proto: u32, headers: bool, auth_required: bool, tls_required: bool, tls_available: bool, jetstream: bool, nonce: str, client_id: u64 }
type Header = struct { name: str, value: str }
type Status = struct { code: u16, description: str, count: usize }
type ConnectOptions = struct { verbose: bool, pedantic: bool, headers: bool, no_responders: bool, has_echo: bool, echo: bool, tls_required: bool, name: str, user: str, pass_word: str, auth_token: str, jwt: str, nkey: str, sig: str, lang: str, version: str, protocol: u32 }
type Sub = struct { used: bool, sid: u64, subject: str, queue: str, max: u64, delivered: u64 }
type Client = struct { subs: []Sub, next_sid: u64, connected: bool, pings_out: u32, info: Info, received: u64 }
type Event = enum u8 { None, Delivered, Dropped, Info, Ok, ServerError, Ping, Pong, Finished }

// --- numbers and tokens ------------------------------------------------------------------------------------------

fn is_space(c: u8) -> bool { ret c == 32u8 || c == 9u8 }

fn lower(c: u8) -> u8 {
    if c >= 65u8 && c <= 90u8 { ret c + 32u8 }
    ret c
}

fn same_fold(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if lower(left[i]) != lower(right[i]) { ret false }
        i += 1usize
    }
    ret true
}

fn parse_decimal(s: str) -> (u64, bool) {
    if s.len == 0usize || s.len > 19usize { ret (0u64, false) }
    var value = 0u64
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret (0u64, false) }
        value = value * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
    ret (value, true)
}

// The next whitespace-separated token of `line` from `at`; `at` moves past it.
fn token(line: str, at: *usize) -> str {
    var i = *at
    while i < line.len && is_space(line[i]) { i += 1usize }
    let start = i
    while i < line.len && !is_space(line[i]) { i += 1usize }
    *at = i
    ret line[start..i]
}

fn more(line: str, at: usize) -> bool {
    var i = at
    while i < line.len && is_space(line[i]) { i += 1usize }
    ret i < line.len
}

// --- subjects ----------------------------------------------------------------------------------------------------

// A valid subject (`wildcards` allows `*` tokens and a trailing `>`); no empty token, no whitespace.
fn valid_subject(subject: str, wildcards: bool) -> bool {
    if subject.len == 0usize { ret false }
    var token_start = 0usize
    var i = 0usize
    while i <= subject.len {
        if i == subject.len || subject[i] == 46u8 {
            if i == token_start { ret false }
            let t = subject[token_start..i]
            if t.len == 1usize && (t[0usize] == 42u8 || t[0usize] == 62u8) {
                if !wildcards { ret false }
                if t[0usize] == 62u8 && i != subject.len { ret false }
            } else {
                var j = 0usize
                while j < t.len {
                    if t[j] == 42u8 || t[j] == 62u8 {
                        if !wildcards { ret false }
                    }
                    j += 1usize
                }
            }
            token_start = i + 1usize
        } else if subject[i] <= 32u8 || subject[i] == 127u8 {
            ret false
        }
        i += 1usize
    }
    ret true
}

// Whether `subject` (no wildcards) falls under `pattern` (`*` one token, a final `>` one or more).
fn subject_matches(pattern: str, subject: str) -> bool {
    var pi = 0usize
    var si = 0usize
    while true {
        var pe = pi
        while pe < pattern.len && pattern[pe] != 46u8 { pe += 1usize }
        var se = si
        while se < subject.len && subject[se] != 46u8 { se += 1usize }
        let pt = pattern[pi..pe]
        let st = subject[si..se]
        if pt.len == 1usize && pt[0usize] == 62u8 && pe == pattern.len { ret st.len > 0usize }
        if st.len == 0usize && se >= subject.len && si >= subject.len && subject.len == 0usize { ret false }
        if !(pt.len == 1usize && pt[0usize] == 42u8) && !str.eq(pt, st) { ret false }
        let pattern_done = pe >= pattern.len
        let subject_done = se >= subject.len
        if pattern_done || subject_done { ret pattern_done && subject_done }
        pi = pe + 1usize
        si = se + 1usize
    }
    ret false
}

// --- output ------------------------------------------------------------------------------------------------------

fn put_bytes(dst: []u8, at: *usize, src: []const u8) -> err {
    if *at + src.len > dst.len { ret TooSmall }
    mem.copy[u8](dst[*at..*at + src.len], src)
    *at += src.len
    ret ok
}

fn put_byte(dst: []u8, at: *usize, b: u8) -> err {
    if *at >= dst.len { ret TooSmall }
    dst[*at] = b
    *at += 1usize
    ret ok
}

fn put_decimal(dst: []u8, at: *usize, value: u64) -> err {
    var digits: [20]u8 = zero
    var n = 0usize
    var v = value
    if v == 0u64 {
        digits[0usize] = 48u8
        n = 1usize
    }
    while v > 0u64 {
        digits[n] = 48u8 + u8(v % 10u64)
        v = v / 10u64
        n += 1usize
    }
    if *at + n > dst.len { ret TooSmall }
    var i = 0usize
    while i < n {
        dst[*at + i] = digits[n - 1usize - i]
        i += 1usize
    }
    *at += n
    ret ok
}

fn put_crlf(dst: []u8, at: *usize) -> err {
    let e = put_byte(dst, at, 13u8)
    if e != ok { ret e }
    ret put_byte(dst, at, 10u8)
}

fn hex_digit(v: u32) -> u8 {
    if v < 10u32 { ret 48u8 + u8(v) }
    ret 87u8 + u8(v)
}

// A JSON string literal (RFC 8259 as `json.dumps` writes it: ASCII only, non-ASCII as \uXXXX with surrogate pairs).
fn put_json_string(dst: []u8, at: *usize, s: str) -> err {
    var e = put_byte(dst, at, 34u8)
    if e != ok { ret e }
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if c == 34u8 || c == 92u8 {
            e = put_byte(dst, at, 92u8)
            if e != ok { ret e }
            e = put_byte(dst, at, c)
        } else if c == 10u8 {
            e = put_bytes(dst, at, "\\n")
        } else if c == 13u8 {
            e = put_bytes(dst, at, "\\r")
        } else if c == 9u8 {
            e = put_bytes(dst, at, "\\t")
        } else if c == 8u8 {
            e = put_bytes(dst, at, "\\b")
        } else if c == 12u8 {
            e = put_bytes(dst, at, "\\f")
        } else if c < 32u8 || c == 127u8 {
            e = put_bytes(dst, at, "\\u00")
            if e != ok { ret e }
            e = put_byte(dst, at, hex_digit(u32(c >> 4u8)))
            if e != ok { ret e }
            e = put_byte(dst, at, hex_digit(u32(c & 15u8)))
        } else if c < 128u8 {
            e = put_byte(dst, at, c)
        } else {
            // A UTF-8 sequence to its scalar value.
            var width = 0usize
            var scalar = 0u32
            if c >= 240u8 && c < 248u8 {
                width = 4usize
                scalar = u32(c & 7u8)
            } else if c >= 224u8 {
                width = 3usize
                scalar = u32(c & 15u8)
            } else if c >= 192u8 {
                width = 2usize
                scalar = u32(c & 31u8)
            } else {
                ret Invalid
            }
            if i + width > s.len { ret Invalid }
            var k = 1usize
            while k < width {
                if (s[i + k] & 192u8) != 128u8 { ret Invalid }
                scalar = (scalar << 6u32) | u32(s[i + k] & 63u8)
                k += 1usize
            }
            i += width - 1usize
            if scalar >= 65536u32 {
                let v = scalar - 65536u32
                e = put_unit(dst, at, 55296u32 + (v >> 10u32))
                if e != ok { ret e }
                e = put_unit(dst, at, 56320u32 + (v & 1023u32))
            } else {
                e = put_unit(dst, at, scalar)
            }
        }
        if e != ok { ret e }
        i += 1usize
    }
    ret put_byte(dst, at, 34u8)
}

fn put_unit(dst: []u8, at: *usize, unit: u32) -> err {
    var e = put_bytes(dst, at, "\\u")
    if e != ok { ret e }
    var shift = 12u32
    while true {
        e = put_byte(dst, at, hex_digit((unit >> shift) & 15u32))
        if e != ok { ret e }
        if shift == 0u32 { break }
        shift -= 4u32
    }
    ret ok
}

fn json_field(dst: []u8, at: *usize, first: *bool, key: str) -> err {
    if !*first {
        let e = put_bytes(dst, at, ", ")
        if e != ok { ret e }
    }
    *first = false
    var e2 = put_json_string(dst, at, key)
    if e2 != ok { ret e2 }
    ret put_bytes(dst, at, ": ")
}

fn json_text(dst: []u8, at: *usize, first: *bool, key: str, value: str) -> err {
    if value.len == 0usize { ret ok }
    let e = json_field(dst, at, first, key)
    if e != ok { ret e }
    ret put_json_string(dst, at, value)
}

fn json_flag(dst: []u8, at: *usize, first: *bool, key: str, value: bool) -> err {
    let e = json_field(dst, at, first, key)
    if e != ok { ret e }
    if value { ret put_bytes(dst, at, "true") }
    ret put_bytes(dst, at, "false")
}

fn options(verbose: bool) -> ConnectOptions {
    ret ConnectOptions { verbose: verbose, pedantic: false, headers: true, no_responders: true, has_echo: false, echo: true, tls_required: false, name: "", user: "", pass_word: "", auth_token: "", jwt: "", nkey: "", sig: "", lang: "neper", version: "0.1", protocol: 1u32 }
}

// `CONNECT {json}\r\n`, the keys sorted and written as Python's `json.dumps(sort_keys=True)` does.
fn encode_connect(dst: []u8, o: *const ConnectOptions) -> (usize, err) {
    var at = 0usize
    var first = true
    var e = put_bytes(dst, &at, "CONNECT {")
    if e != ok { ret (0usize, e) }
    e = json_text(dst, &at, &first, "auth_token", o.auth_token)
    if e != ok { ret (0usize, e) }
    if o.has_echo {
        e = json_flag(dst, &at, &first, "echo", o.echo)
        if e != ok { ret (0usize, e) }
    }
    if o.headers {
        e = json_flag(dst, &at, &first, "headers", true)
        if e != ok { ret (0usize, e) }
    }
    e = json_text(dst, &at, &first, "jwt", o.jwt)
    if e != ok { ret (0usize, e) }
    e = json_text(dst, &at, &first, "lang", o.lang)
    if e != ok { ret (0usize, e) }
    e = json_text(dst, &at, &first, "name", o.name)
    if e != ok { ret (0usize, e) }
    e = json_text(dst, &at, &first, "nkey", o.nkey)
    if e != ok { ret (0usize, e) }
    if o.no_responders {
        e = json_flag(dst, &at, &first, "no_responders", true)
        if e != ok { ret (0usize, e) }
    }
    e = json_text(dst, &at, &first, "pass", o.pass_word)
    if e != ok { ret (0usize, e) }
    e = json_flag(dst, &at, &first, "pedantic", o.pedantic)
    if e != ok { ret (0usize, e) }
    e = json_field(dst, &at, &first, "protocol")
    if e != ok { ret (0usize, e) }
    e = put_decimal(dst, &at, u64(o.protocol))
    if e != ok { ret (0usize, e) }
    e = json_text(dst, &at, &first, "sig", o.sig)
    if e != ok { ret (0usize, e) }
    if o.tls_required {
        e = json_flag(dst, &at, &first, "tls_required", true)
        if e != ok { ret (0usize, e) }
    }
    e = json_text(dst, &at, &first, "user", o.user)
    if e != ok { ret (0usize, e) }
    e = json_flag(dst, &at, &first, "verbose", o.verbose)
    if e != ok { ret (0usize, e) }
    e = json_text(dst, &at, &first, "version", o.version)
    if e != ok { ret (0usize, e) }
    e = put_bytes(dst, &at, "}")
    if e != ok { ret (0usize, e) }
    e = put_crlf(dst, &at)
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

fn encode_ping(dst: []u8) -> (usize, err) {
    var at = 0usize
    let e = put_bytes(dst, &at, "PING\r\n")
    ret (at, e)
}

fn encode_pong(dst: []u8) -> (usize, err) {
    var at = 0usize
    let e = put_bytes(dst, &at, "PONG\r\n")
    ret (at, e)
}

// `PUB subject [reply] size\r\npayload\r\n`.
fn encode_pub(dst: []u8, subject: str, reply: str, payload: []const u8) -> (usize, err) {
    if !valid_subject(subject, false) { ret (0usize, Invalid) }
    if reply.len > 0usize && !valid_subject(reply, false) { ret (0usize, Invalid) }
    var at = 0usize
    var e = put_bytes(dst, &at, "PUB ")
    if e != ok { ret (0usize, e) }
    e = put_bytes(dst, &at, subject)
    if e != ok { ret (0usize, e) }
    if reply.len > 0usize {
        e = put_byte(dst, &at, 32u8)
        if e != ok { ret (0usize, e) }
        e = put_bytes(dst, &at, reply)
        if e != ok { ret (0usize, e) }
    }
    e = put_byte(dst, &at, 32u8)
    if e != ok { ret (0usize, e) }
    e = put_decimal(dst, &at, u64(payload.len))
    if e != ok { ret (0usize, e) }
    e = put_crlf(dst, &at)
    if e != ok { ret (0usize, e) }
    e = put_bytes(dst, &at, payload)
    if e != ok { ret (0usize, e) }
    e = put_crlf(dst, &at)
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// RFC 9110 token characters, the set `nats.py` accepts for a header name.
fn tchar(c: u8) -> bool {
    if (c >= 48u8 && c <= 57u8) || (c >= 65u8 && c <= 90u8) || (c >= 97u8 && c <= 122u8) { ret true }
    ret c == 33u8 || c == 35u8 || c == 36u8 || c == 37u8 || c == 38u8 || c == 39u8 || c == 42u8 || c == 43u8 || c == 45u8 || c == 46u8 || c == 94u8 || c == 95u8 || c == 96u8 || c == 124u8 || c == 126u8
}

// A header block: `NATS/1.0\r\n`,`Name: value\r\n` per header, a blank line. A name is a token without
// whitespace or `:`; a value has its newlines turned to spaces and its ends trimmed.
fn encode_headers(dst: []u8, headers: []const Header) -> (usize, err) {
    var at = 0usize
    var e = put_bytes(dst, &at, "NATS/1.0\r\n")
    if e != ok { ret (0usize, e) }
    var i = 0usize
    while i < headers.len {
        let name = headers[i].name
        if name.len == 0usize { ret (0usize, Invalid) }
        var j = 0usize
        while j < name.len {
            if !tchar(name[j]) { ret (0usize, Invalid) }
            j += 1usize
        }
        e = put_bytes(dst, &at, name)
        if e != ok { ret (0usize, e) }
        e = put_bytes(dst, &at, ": ")
        if e != ok { ret (0usize, e) }
        var lo = 0usize
        var hi = headers[i].value.len
        let value = headers[i].value
        while lo < hi && (is_space(value[lo]) || value[lo] == 10u8 || value[lo] == 13u8) { lo += 1usize }
        while hi > lo && (is_space(value[hi - 1usize]) || value[hi - 1usize] == 10u8 || value[hi - 1usize] == 13u8) { hi -= 1usize }
        var k = lo
        while k < hi {
            var c = value[k]
            if c == 10u8 || c == 13u8 { c = 32u8 }
            e = put_byte(dst, &at, c)
            if e != ok { ret (0usize, e) }
            k += 1usize
        }
        e = put_crlf(dst, &at)
        if e != ok { ret (0usize, e) }
        i += 1usize
    }
    e = put_crlf(dst, &at)
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// `HPUB subject [reply] header_size total_size\r\n` + header block + payload + CRLF.
fn encode_hpub(dst: []u8, subject: str, reply: str, headers: []const Header, payload: []const u8) -> (usize, err) {
    if !valid_subject(subject, false) { ret (0usize, Invalid) }
    if reply.len > 0usize && !valid_subject(reply, false) { ret (0usize, Invalid) }
    var block: [1024]u8 = zero
    let (block_len, block_error) = encode_headers(block[0usize..], headers)
    if block_error != ok { ret (0usize, block_error) }
    var at = 0usize
    var e = put_bytes(dst, &at, "HPUB ")
    if e != ok { ret (0usize, e) }
    e = put_bytes(dst, &at, subject)
    if e != ok { ret (0usize, e) }
    if reply.len > 0usize {
        e = put_byte(dst, &at, 32u8)
        if e != ok { ret (0usize, e) }
        e = put_bytes(dst, &at, reply)
        if e != ok { ret (0usize, e) }
    }
    e = put_byte(dst, &at, 32u8)
    if e != ok { ret (0usize, e) }
    e = put_decimal(dst, &at, u64(block_len))
    if e != ok { ret (0usize, e) }
    e = put_byte(dst, &at, 32u8)
    if e != ok { ret (0usize, e) }
    e = put_decimal(dst, &at, u64(block_len + payload.len))
    if e != ok { ret (0usize, e) }
    e = put_crlf(dst, &at)
    if e != ok { ret (0usize, e) }
    e = put_bytes(dst, &at, block[0usize..block_len])
    if e != ok { ret (0usize, e) }
    e = put_bytes(dst, &at, payload)
    if e != ok { ret (0usize, e) }
    e = put_crlf(dst, &at)
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// `SUB subject [queue] sid\r\n`.
fn encode_sub(dst: []u8, subject: str, queue: str, sid: u64) -> (usize, err) {
    if !valid_subject(subject, true) { ret (0usize, Invalid) }
    if queue.len > 0usize && !valid_subject(queue, false) { ret (0usize, Invalid) }
    var at = 0usize
    var e = put_bytes(dst, &at, "SUB ")
    if e != ok { ret (0usize, e) }
    e = put_bytes(dst, &at, subject)
    if e != ok { ret (0usize, e) }
    if queue.len > 0usize {
        e = put_byte(dst, &at, 32u8)
        if e != ok { ret (0usize, e) }
        e = put_bytes(dst, &at, queue)
        if e != ok { ret (0usize, e) }
    }
    e = put_byte(dst, &at, 32u8)
    if e != ok { ret (0usize, e) }
    e = put_decimal(dst, &at, sid)
    if e != ok { ret (0usize, e) }
    e = put_crlf(dst, &at)
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// `UNSUB sid [max]\r\n`.
fn encode_unsub(dst: []u8, sid: u64, max: u64) -> (usize, err) {
    var at = 0usize
    var e = put_bytes(dst, &at, "UNSUB ")
    if e != ok { ret (0usize, e) }
    e = put_decimal(dst, &at, sid)
    if e != ok { ret (0usize, e) }
    if max > 0u64 {
        e = put_byte(dst, &at, 32u8)
        if e != ok { ret (0usize, e) }
        e = put_decimal(dst, &at, max)
        if e != ok { ret (0usize, e) }
    }
    e = put_crlf(dst, &at)
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// --- input -------------------------------------------------------------------------------------------------------

fn find_crlf(buf: []const u8, limit: usize) -> (usize, bool) {
    var i = 0usize
    while i + 1usize < buf.len && i <= limit {
        if buf[i] == 13u8 && buf[i + 1usize] == 10u8 { ret (i, true) }
        i += 1usize
    }
    ret (0usize, false)
}

// The fields of a `MSG` (`subject sid [reply] size`) or `HMSG` (`subject sid [reply] header_size total_size`) line
// after its verb: the message with subject, sid and reply, the header size and the total size.
fn message_line(line: str, from: usize, with_headers: bool, max_payload: usize) -> (Message, usize, usize, err) {
    var none: Message = zero
    var at = from
    let subject = token(line, &at)
    let sid_text = token(line, &at)
    let t3 = token(line, &at)
    let t4 = token(line, &at)
    let t5 = token(line, &at)
    if more(line, at) { ret (none, 0usize, 0usize, Invalid) }
    var reply = ""
    var header_text = ""
    var total_text = ""
    if with_headers {
        if t5.len > 0usize {
            reply = t3
            header_text = t4
            total_text = t5
        } else {
            header_text = t3
            total_text = t4
        }
    } else {
        if t5.len > 0usize { ret (none, 0usize, 0usize, Invalid) }
        if t4.len > 0usize {
            reply = t3
            total_text = t4
        } else {
            total_text = t3
        }
    }
    if subject.len == 0usize || sid_text.len == 0usize || total_text.len == 0usize { ret (none, 0usize, 0usize, Invalid) }
    let (sid, sid_ok) = parse_decimal(sid_text)
    if !sid_ok { ret (none, 0usize, 0usize, Invalid) }
    let (total, total_ok) = parse_decimal(total_text)
    if !total_ok { ret (none, 0usize, 0usize, Invalid) }
    var header_len = 0u64
    if with_headers {
        let (h, h_ok) = parse_decimal(header_text)
        if !h_ok || h > total { ret (none, 0usize, 0usize, Invalid) }
        header_len = h
    }
    if total > u64(max_payload) { ret (none, 0usize, 0usize, TooLarge) }
    var m: Message = zero
    m.subject = subject
    m.sid = sid
    m.reply = reply
    ret (m, usize(header_len), usize(total), ok)
}

// The next server operation at the front of `buf`: the operation and the bytes it occupies. `Incomplete` when more
// bytes are needed, `Invalid` for a line that is not NATS, `TooLarge` past `max_payload` or a control line past
// 4096 bytes.
fn parse(buf: []const u8, max_payload: usize) -> (Op, usize, err) {
    var none: Op = .None
    if buf.len == 0usize { ret (none, 0usize, Incomplete) }
    let (end, found) = find_crlf(buf, 4096usize)
    if !found {
        if buf.len > 4096usize { ret (none, 0usize, TooLarge) }
        ret (none, 0usize, Incomplete)
    }
    let line = buf[0usize..end]
    var at = 0usize
    let verb = token(line, &at)
    let after = end + 2usize
    if same_fold(verb, "PING") {
        if more(line, at) { ret (none, 0usize, Invalid) }
        var op: Op = .Ping
        ret (op, after, ok)
    }
    if same_fold(verb, "PONG") {
        if more(line, at) { ret (none, 0usize, Invalid) }
        var op: Op = .Pong
        ret (op, after, ok)
    }
    if same_fold(verb, "+OK") {
        if more(line, at) { ret (none, 0usize, Invalid) }
        var op: Op = .Ok
        ret (op, after, ok)
    }
    if same_fold(verb, "-ERR") {
        var text = line[at..]
        while text.len > 0usize && is_space(text[0usize]) { text = text[1usize..] }
        while text.len > 0usize && is_space(text[text.len - 1usize]) { text = text[..text.len - 1usize] }
        if text.len >= 2usize && text[0usize] == 39u8 && text[text.len - 1usize] == 39u8 { text = text[1usize..text.len - 1usize] }
        ret (Op { Err: text }, after, ok)
    }
    if same_fold(verb, "INFO") {
        var text = line[at..]
        while text.len > 0usize && is_space(text[0usize]) { text = text[1usize..] }
        if text.len == 0usize { ret (none, 0usize, Invalid) }
        ret (Op { Info: text }, after, ok)
    }
    var with_headers = false
    if same_fold(verb, "HMSG") {
        with_headers = true
    } else if !same_fold(verb, "MSG") {
        ret (none, 0usize, Invalid)
    }
    let (message, header_len, total, line_error) = message_line(line, at, with_headers, max_payload)
    if line_error != ok { ret (none, 0usize, line_error) }
    if !valid_subject(message.subject, false) { ret (none, 0usize, Invalid) }
    if after + total + 2usize > buf.len { ret (none, 0usize, Incomplete) }
    if buf[after + total] != 13u8 || buf[after + total + 1usize] != 10u8 { ret (none, 0usize, Invalid) }
    var out = message
    out.headers = buf[after..after + header_len]
    out.payload = buf[after + header_len..after + total]
    ret (Op { Msg: out }, after + total + 2usize, ok)
}

// How many bytes the operation at the front of `buf` occupies in all, once its control line is complete (zero when
// the line itself is not complete or not a message): lets a reader ask its source for exactly the rest.
fn needed(buf: []const u8, max_payload: usize) -> usize {
    let (end, found) = find_crlf(buf, 4096usize)
    if !found { ret 0usize }
    let line = buf[0usize..end]
    var at = 0usize
    let verb = token(line, &at)
    var with_headers = false
    if same_fold(verb, "HMSG") {
        with_headers = true
    } else if !same_fold(verb, "MSG") {
        ret end + 2usize
    }
    let (message, header_len, total, line_error) = message_line(line, at, with_headers, max_payload)
    if line_error != ok { ret 0usize }
    ret end + 2usize + total + 2usize
}

// --- INFO and headers --------------------------------------------------------------------------------------------

fn skip_ws(j: str, at: usize) -> usize {
    var i = at
    while i < j.len && (j[i] == 32u8 || j[i] == 9u8 || j[i] == 10u8 || j[i] == 13u8) { i += 1usize }
    ret i
}

// The end of a JSON string whose opening quote is at `at`; `ok` false when unterminated.
fn string_end(j: str, at: usize) -> (usize, bool) {
    var i = at + 1usize
    while i < j.len {
        if j[i] == 92u8 {
            i += 2usize
        } else if j[i] == 34u8 {
            ret (i + 1usize, true)
        } else {
            i += 1usize
        }
    }
    ret (0usize, false)
}

// The end of one JSON value starting at `at`.
fn skip_value(j: str, at: usize) -> (usize, bool) {
    var i = skip_ws(j, at)
    if i >= j.len { ret (0usize, false) }
    if j[i] == 34u8 {
        let (quoted_end, quoted_ok) = string_end(j, i)
        ret (quoted_end, quoted_ok)
    }
    if j[i] == 123u8 || j[i] == 91u8 {
        var depth = 0usize
        while i < j.len {
            let c = j[i]
            if c == 34u8 {
                let (e, good) = string_end(j, i)
                if !good { ret (0usize, false) }
                i = e
                continue
            }
            if c == 123u8 || c == 91u8 { depth += 1usize }
            if c == 125u8 || c == 93u8 {
                depth -= 1usize
                if depth == 0usize { ret (i + 1usize, true) }
            }
            i += 1usize
        }
        ret (0usize, false)
    }
    var k = i
    while k < j.len && j[k] != 44u8 && j[k] != 125u8 && j[k] != 93u8 && !is_space(j[k]) && j[k] != 10u8 && j[k] != 13u8 { k += 1usize }
    if k == i { ret (0usize, false) }
    ret (k, true)
}

// The server's INFO document: the top-level fields a client acts on (others, and nested objects, are skipped).
// String fields borrow the JSON text with any backslash escapes left as written.
fn parse_info(j: str) -> (Info, err) {
    var info: Info = zero
    var i = skip_ws(j, 0usize)
    if i >= j.len || j[i] != 123u8 { ret (info, Invalid) }
    i += 1usize
    while true {
        i = skip_ws(j, i)
        if i >= j.len { ret (info, Invalid) }
        if j[i] == 125u8 { break }
        if j[i] == 44u8 {
            i += 1usize
            continue
        }
        if j[i] != 34u8 { ret (info, Invalid) }
        let (key_end, key_ok) = string_end(j, i)
        if !key_ok { ret (info, Invalid) }
        let key = j[i + 1usize..key_end - 1usize]
        i = skip_ws(j, key_end)
        if i >= j.len || j[i] != 58u8 { ret (info, Invalid) }
        i = skip_ws(j, i + 1usize)
        let (value_end, value_ok) = skip_value(j, i)
        if !value_ok { ret (info, Invalid) }
        var value = j[i..value_end]
        if value.len >= 2usize && value[0usize] == 34u8 { value = value[1usize..value.len - 1usize] }
        if str.eq(key, "server_id") {
            info.server_id = value
        } else if str.eq(key, "version") {
            info.version = value
        } else if str.eq(key, "host") {
            info.host = value
        } else if str.eq(key, "nonce") {
            info.nonce = value
        } else if str.eq(key, "port") {
            let (n, n_ok) = parse_decimal(value)
            if n_ok { info.port = u32(n) }
        } else if str.eq(key, "max_payload") {
            let (n, n_ok) = parse_decimal(value)
            if n_ok { info.max_payload = n }
        } else if str.eq(key, "proto") {
            let (n, n_ok) = parse_decimal(value)
            if n_ok { info.proto = u32(n) }
        } else if str.eq(key, "client_id") {
            let (n, n_ok) = parse_decimal(value)
            if n_ok { info.client_id = n }
        } else if str.eq(key, "headers") {
            info.headers = str.eq(value, "true")
        } else if str.eq(key, "auth_required") {
            info.auth_required = str.eq(value, "true")
        } else if str.eq(key, "tls_required") {
            info.tls_required = str.eq(value, "true")
        } else if str.eq(key, "tls_available") {
            info.tls_available = str.eq(value, "true")
        } else if str.eq(key, "jetstream") {
            info.jetstream = str.eq(value, "true")
        }
        i = value_end
    }
    ret (info, ok)
}

fn trim(s: str) -> str {
    var lo = 0usize
    var hi = s.len
    while lo < hi && is_space(s[lo]) { lo += 1usize }
    while hi > lo && is_space(s[hi - 1usize]) { hi -= 1usize }
    ret s[lo..hi]
}

// A message's header block: the optional inline status (`NATS/1.0 503`, `NATS/1.0 404 No Messages`) and the
// `Name: value` lines into `out` (names as sent, duplicates kept, a line without a colon or with a non-ASCII name
// dropped). `Status.count` is how many headers were written; `Invalid` when the block does not begin `NATS/1.0`.
fn parse_headers(block: []const u8, out: []Header) -> (Status, err) {
    var status: Status = zero
    let text: str = block
    if text.len < 8usize || !str.eq(text[0usize..8usize], "NATS/1.0") { ret (status, Invalid) }
    let (first_end, first_found) = find_crlf(text, text.len)
    if !first_found { ret (status, Invalid) }
    let first = text[8usize..first_end]
    var rest = text[first_end + 2usize..]
    if first.len > 0usize {
        let rest_of_line = trim(first)
        if rest_of_line.len >= 3usize {
            let (code, code_ok) = parse_decimal(rest_of_line[0usize..3usize])
            if code_ok && (rest_of_line.len == 3usize || is_space(rest_of_line[3usize])) {
                status.code = u16(code)
                status.description = trim(rest_of_line[3usize..])
            }
        }
    }
    while rest.len > 0usize {
        let (line_end, line_found) = find_crlf(rest, rest.len)
        var line = rest
        if line_found {
            line = rest[0usize..line_end]
            rest = rest[line_end + 2usize..]
        } else {
            rest = rest[rest.len..]
        }
        if line.len == 0usize { continue }
        var colon = 0usize
        while colon < line.len && line[colon] != 58u8 { colon += 1usize }
        if colon == line.len { continue }
        let name = trim(line[0usize..colon])
        var ascii = name.len > 0usize
        var n = 0usize
        while n < name.len {
            if name[n] >= 128u8 { ascii = false }
            n += 1usize
        }
        if !ascii { continue }
        if status.count >= out.len { ret (status, TooSmall) }
        out[status.count] = Header { name: name, value: trim(line[colon + 1usize..]) }
        status.count += 1usize
    }
    ret (status, ok)
}

// --- the connection ----------------------------------------------------------------------------------------------

fn client(subs: []Sub) -> Client {
    var i = 0usize
    while i < subs.len {
        subs[i].used = false
        i += 1usize
    }
    ret Client { subs: subs, next_sid: 1u64, connected: false, pings_out: 0u32, info: zero, received: 0u64 }
}

// The bytes a client sends after the server's INFO: CONNECT then PING (the PONG back confirms the handshake).
fn handshake(c: *Client, dst: []u8, o: *const ConnectOptions) -> (usize, err) {
    let (n, connect_error) = encode_connect(dst, o)
    if connect_error != ok { ret (0usize, connect_error) }
    let (m, ping_error) = encode_ping(dst[n..])
    if ping_error != ok { ret (0usize, ping_error) }
    c.pings_out += 1u32
    ret (n + m, ok)
}

fn find_sub(c: *const Client, sid: u64) -> usize {
    var i = 0usize
    while i < c.subs.len {
        if c.subs[i].used && c.subs[i].sid == sid { ret i }
        i += 1usize
    }
    ret c.subs.len
}

// Register a subscription (the subject and queue text must outlive it) and write its SUB. `max` > 0 also writes
// the UNSUB that makes the server stop after that many messages, and the client drops the entry at that count.
fn subscribe(c: *Client, dst: []u8, subject: str, queue: str, max: u64) -> (u64, usize, err) {
    var free = c.subs.len
    var i = 0usize
    while i < c.subs.len {
        if !c.subs[i].used {
            free = i
            break
        }
        i += 1usize
    }
    if free == c.subs.len { ret (0u64, 0usize, TooSmall) }
    let sid = c.next_sid
    let (n, sub_error) = encode_sub(dst, subject, queue, sid)
    if sub_error != ok { ret (0u64, 0usize, sub_error) }
    var total = n
    if max > 0u64 {
        let (m, unsub_error) = encode_unsub(dst[n..], sid, max)
        if unsub_error != ok { ret (0u64, 0usize, unsub_error) }
        total += m
    }
    c.next_sid += 1u64
    c.subs[free] = Sub { used: true, sid: sid, subject: subject, queue: queue, max: max, delivered: 0u64 }
    ret (sid, total, ok)
}

// Drop a subscription now (`max` zero) or after `max` more messages in all, writing the UNSUB.
fn unsubscribe(c: *Client, dst: []u8, sid: u64, max: u64) -> (usize, err) {
    let at = find_sub(c, sid)
    if at == c.subs.len { ret (0usize, Invalid) }
    let (n, e) = encode_unsub(dst, sid, max)
    if e != ok { ret (0usize, e) }
    if max == 0u64 || c.subs[at].delivered >= max {
        c.subs[at].used = false
    } else {
        c.subs[at].max = max
    }
    ret (n, ok)
}

// Apply one server operation: PING is answered with a PONG into `dst`, a MSG is attributed to its subscription
// (`Delivered`, and `Finished` when that was the last one it asked for), a MSG for an unknown sid is `Dropped`.
// Answers the event and the bytes written to `dst`.
fn handle(c: *Client, op: Op, dst: []u8) -> (Event, usize, err) {
    switch op {
    case .Ping:
        let (n, e) = encode_pong(dst)
        ret (.Ping, n, e)
    case .Pong:
        if c.pings_out > 0u32 { c.pings_out -= 1u32 }
        c.connected = true
        ret (.Pong, 0usize, ok)
    case .Ok:
        ret (.Ok, 0usize, ok)
    case .Err as text:
        ret (.ServerError, 0usize, ok)
    case .Info as text:
        let (info, info_error) = parse_info(text)
        if info_error != ok { ret (.None, 0usize, info_error) }
        c.info = info
        ret (.Info, 0usize, ok)
    case .Msg as m:
        let at = find_sub(c, m.sid)
        if at == c.subs.len { ret (.Dropped, 0usize, ok) }
        c.subs[at].delivered += 1u64
        c.received += 1u64
        if c.subs[at].max > 0u64 && c.subs[at].delivered >= c.subs[at].max {
            c.subs[at].used = false
            ret (.Finished, 0usize, ok)
        }
        ret (.Delivered, 0usize, ok)
    default:
        ret (.None, 0usize, ok)
    }
    ret (.None, 0usize, ok)
}

// --- request-reply -----------------------------------------------------------------------------------------------

// The reply subject for request number `n` under an inbox prefix (`_INBOX.<unique>`): `<prefix>.<n>`. Subscribe
// once to `<prefix>.*`, then every request names its own reply.
fn reply_subject(dst: []u8, prefix: str, n: u64) -> (str, err) {
    var at = 0usize
    var e = put_bytes(dst, &at, prefix)
    if e != ok { ret ("", e) }
    e = put_byte(dst, &at, 46u8)
    if e != ok { ret ("", e) }
    e = put_decimal(dst, &at, n)
    if e != ok { ret ("", e) }
    ret (dst[0usize..at], ok)
}

// The request number a reply subject carries under `prefix`, when it is one of ours.
fn reply_number(prefix: str, subject: str) -> (u64, bool) {
    if subject.len <= prefix.len + 1usize { ret (0u64, false) }
    if !str.eq(subject[0usize..prefix.len], prefix) || subject[prefix.len] != 46u8 { ret (0u64, false) }
    let (n, good) = parse_decimal(subject[prefix.len + 1usize..])
    ret (n, good)
}

// Whether a message is the server's "no responders" answer (a header-only 503).
fn no_responders(m: *const Message) -> bool {
    if m.payload.len != 0usize || m.headers.len < 12usize { ret false }
    var out: [1]Header = zero
    let (status, e) = parse_headers(m.headers, out[0usize..])
    ret e == ok && status.code == 503u16
}
