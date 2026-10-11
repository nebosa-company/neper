// `e.net.nats` against nats-py (L115): scripts/nats_vectors.py feeds nats-py's own protocol parser the server streams
// (at several chunk sizes), builds the client bytes with its command builders and CONNECT code, and parses header
// blocks with its client; each expected line is asserted against nats-py before it is written. This fixture runs the
// same inputs through e.net.nats (streams re-chunked to the vector's size, so a split anywhere in an operation is
// covered) and compares text. Lines are tab-separated records; binary fields are hex. Subject validity and matching
// are documentation rules written independently in the generator. Generated from scripts/nats_fixture_template.e.
use e.io
use e.mem
use e.net.nats as nats
use e.os
use e.str

fn nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

fn unhex(a: *mem.Arena, h: str) -> []u8 {
    let (out, e) = mem.alloc[u8](a, h.len / 2usize + 1usize)
    if e != ok { os.exit(90i32) }
    var i = 0usize
    while i + 1usize < h.len {
        out[i / 2usize] = (nibble(h[i]) << 4u8) | nibble(h[i + 1usize])
        i += 2usize
    }
    ret out[0usize..h.len / 2usize]
}

fn hex(a: *mem.Arena, b: []const u8) -> str {
    let digits = "0123456789abcdef"
    let (out, e) = mem.alloc[u8](a, b.len * 2usize + 1usize)
    if e != ok { os.exit(91i32) }
    var i = 0usize
    while i < b.len {
        out[i * 2usize] = digits[usize(b[i] >> 4u8)]
        out[i * 2usize + 1usize] = digits[usize(b[i] & 15u8)]
        i += 1usize
    }
    ret out[0usize..b.len * 2usize]
}

fn cat(a: *mem.Arena, x: str, y: str) -> str {
    let (out, e) = str.concat(a, x, y)
    if e != ok { os.exit(92i32) }
    ret out
}

fn dec(a: *mem.Arena, n: u64) -> str {
    var buf: [24]u8 = zero
    var at = 0usize
    let e = nats.put_decimal(buf[0usize..], &at, n)
    if e != ok { os.exit(93i32) }
    let (out, ae) = mem.alloc[u8](a, at)
    if ae != ok { os.exit(94i32) }
    mem.copy[u8](out, buf[0usize..at])
    ret out
}

fn num(s: str) -> u64 {
    let (v, good) = nats.parse_decimal(s)
    if !good { os.exit(95i32) }
    ret v
}

fn field(rest: *str) -> str {
    let (head, tail, found) = str.split_once(*rest, "\t")
    if !found {
        let all = *rest
        *rest = ""
        ret all
    }
    *rest = tail
    ret head
}

fn flag(s: str) -> bool { ret str.eq(s, "1") }

fn b01(v: bool) -> str {
    if v { ret "1" }
    ret "0"
}

fn render(a: *mem.Arena, op: nats.Op) -> str {
    switch op {
    case .Ping:
        ret "PING"
    case .Pong:
        ret "PONG"
    case .Ok:
        ret "OK"
    case .Err as text:
        ret cat(a, cat(a, "ERR|'", text), "'")
    case .Info as json_text:
        let (info, e) = nats.parse_info(json_text)
        if e != ok { ret "INFO!" }
        var s = cat(a, "INFO|", info.server_id)
        s = cat(a, cat(a, s, "|"), info.version)
        s = cat(a, cat(a, s, "|"), info.host)
        s = cat(a, cat(a, s, "|"), dec(a, u64(info.port)))
        s = cat(a, cat(a, s, "|"), dec(a, info.max_payload))
        s = cat(a, cat(a, s, "|"), dec(a, u64(info.proto)))
        s = cat(a, cat(a, s, "|"), b01(info.headers))
        s = cat(a, cat(a, s, "|"), b01(info.auth_required))
        s = cat(a, cat(a, s, "|"), b01(info.tls_required))
        s = cat(a, cat(a, s, "|"), info.nonce)
        ret s
    case .Msg as m:
        var s = cat(a, "MSG|", m.subject)
        s = cat(a, cat(a, s, "|"), dec(a, m.sid))
        s = cat(a, cat(a, s, "|"), m.reply)
        s = cat(a, cat(a, s, "|"), hex(a, m.headers))
        s = cat(a, cat(a, s, "|"), hex(a, m.payload))
        ret s
    default:
        ret "NONE"
    }
    ret "NONE"
}

// Feed `data` in `chunk`-byte pieces, parsing everything available after each; the events, and whether bytes of an
// unfinished operation were left.
fn run_stream(a: *mem.Arena, data: []const u8, chunk: usize) -> (str, bool) {
    var events = ""
    var first = true
    var start = 0usize
    var have = 0usize
    while true {
        have += chunk
        if have > data.len { have = data.len }
        while true {
            let (op, used, e) = nats.parse(data[start..have], 1048576usize)
            if e == nats.Incomplete { break }
            if e != ok {
                events = cat(a, events, "!bad")
                ret (events, false)
            }
            if !first { events = cat(a, events, "~") }
            first = false
            events = cat(a, events, render(a, op))
            start += used
        }
        if have == data.len { break }
    }
    ret (events, start < data.len)
}

fn fail(line: str) -> bool {
    let shown = io.print(line)
    ret false
}

fn parse_list(a: *mem.Arena, list: str, out: []nats.Header) -> usize {
    var count = 0usize
    var rest = list
    while rest.len > 0usize {
        let (item, tail, more) = str.split_once(rest, ",")
        var current = rest
        if more {
            current = item
            rest = tail
        } else {
            rest = ""
        }
        let (name_hex, value_hex, colon) = str.split_once(current, ":")
        if !colon { os.exit(96i32) }
        out[count] = nats.Header { name: unhex(a, name_hex), value: unhex(a, value_hex) }
        count += 1usize
    }
    ret count
}

fn err_name(e: err) -> str {
    if e == nats.Incomplete { ret "Incomplete" }
    if e == nats.Invalid { ret "Invalid" }
    if e == nats.TooLarge { ret "TooLarge" }
    if e == nats.TooSmall { ret "TooSmall" }
    if e == ok { ret "ok" }
    ret "other"
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    if str.eq(kind, "P") {
        let chunk = usize(num(field(&rest)))
        let data = unhex(a, field(&rest))
        let want = field(&rest)
        let leftover = flag(field(&rest))
        let (got, partial) = run_stream(a, data, chunk)
        ret str.eq(got, want) && partial == leftover
    }
    if str.eq(kind, "B") {
        let data = unhex(a, field(&rest))
        let want = field(&rest)
        let (op, used, e) = nats.parse(data, 1048576usize)
        ret str.eq(err_name(e), want)
    }
    if str.eq(kind, "C") {
        var o = nats.options(false)
        o.verbose = flag(field(&rest))
        o.pedantic = flag(field(&rest))
        o.headers = flag(field(&rest))
        o.no_responders = flag(field(&rest))
        o.has_echo = flag(field(&rest))
        o.echo = flag(field(&rest))
        o.tls_required = flag(field(&rest))
        o.name = unhex(a, field(&rest))
        o.user = unhex(a, field(&rest))
        o.pass_word = unhex(a, field(&rest))
        o.auth_token = unhex(a, field(&rest))
        o.jwt = unhex(a, field(&rest))
        o.nkey = unhex(a, field(&rest))
        o.sig = unhex(a, field(&rest))
        o.lang = unhex(a, field(&rest))
        o.version = unhex(a, field(&rest))
        o.protocol = u32(num(field(&rest)))
        let want = field(&rest)
        var buf: [1024]u8 = zero
        let (n, e) = nats.encode_connect(buf[0usize..], &o)
        ret e == ok && str.eq(hex(a, buf[0usize..n]), want)
    }
    if str.eq(kind, "U") {
        let subject = unhex(a, field(&rest))
        let reply = unhex(a, field(&rest))
        let payload = unhex(a, field(&rest))
        let want = field(&rest)
        var buf: [4096]u8 = zero
        let (n, e) = nats.encode_pub(buf[0usize..], subject, reply, payload)
        ret e == ok && str.eq(hex(a, buf[0usize..n]), want)
    }
    if str.eq(kind, "H") || str.eq(kind, "X") {
        let subject = unhex(a, field(&rest))
        let reply = unhex(a, field(&rest))
        var headers: [8]nats.Header = zero
        let count = parse_list(a, field(&rest), headers[0usize..])
        var payload: []u8 = unhex(a, "")
        var want = ""
        if str.eq(kind, "H") {
            payload = unhex(a, field(&rest))
            want = field(&rest)
        }
        var buf: [4096]u8 = zero
        let (n, e) = nats.encode_hpub(buf[0usize..], subject, reply, headers[0usize..count], payload)
        if str.eq(kind, "X") { ret e == nats.Invalid }
        ret e == ok && str.eq(hex(a, buf[0usize..n]), want)
    }
    if str.eq(kind, "S") {
        let subject = unhex(a, field(&rest))
        let queue = unhex(a, field(&rest))
        let sid = num(field(&rest))
        let want = field(&rest)
        var buf: [512]u8 = zero
        let (n, e) = nats.encode_sub(buf[0usize..], subject, queue, sid)
        ret e == ok && str.eq(hex(a, buf[0usize..n]), want)
    }
    if str.eq(kind, "N") {
        let sid = num(field(&rest))
        let max = num(field(&rest))
        let want = field(&rest)
        var buf: [64]u8 = zero
        let (n, e) = nats.encode_unsub(buf[0usize..], sid, max)
        ret e == ok && str.eq(hex(a, buf[0usize..n]), want)
    }
    if str.eq(kind, "D") {
        let block = unhex(a, field(&rest))
        let code = u16(num(field(&rest)))
        let description = unhex(a, field(&rest))
        var want_headers: [8]nats.Header = zero
        let want_count = parse_list(a, field(&rest), want_headers[0usize..])
        var got_headers: [8]nats.Header = zero
        let (status, e) = nats.parse_headers(block, got_headers[0usize..])
        if e != ok || status.code != code || !str.eq(status.description, description) || status.count != want_count { ret false }
        var i = 0usize
        while i < want_count {
            if !str.eq(got_headers[i].name, want_headers[i].name) || !str.eq(got_headers[i].value, want_headers[i].value) { ret false }
            i += 1usize
        }
        ret true
    }
    if str.eq(kind, "Z") {
        let block = unhex(a, field(&rest))
        var out: [4]nats.Header = zero
        let (status, e) = nats.parse_headers(block, out[0usize..])
        ret e == nats.Invalid
    }
    if str.eq(kind, "V") {
        let subject = unhex(a, field(&rest))
        let wild = flag(field(&rest))
        let want = flag(field(&rest))
        ret nats.valid_subject(subject, wild) == want
    }
    if str.eq(kind, "M") {
        let pattern = unhex(a, field(&rest))
        let subject = unhex(a, field(&rest))
        let want = flag(field(&rest))
        ret nats.subject_matches(pattern, subject) == want
    }
    ret false
}

//__VECTOR_FUNCTIONS__
fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            if !run_one(a, line) {
                let shown = fail(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

// A scripted session: the server's INFO, PONG, messages for two subscriptions (one that ends after two messages),
// a PING and a message for a sid the client does not hold. The client's bytes and the event list are compared with
// the transcript the generator derived from nats-py's builders.
fn session(a: *mem.Arena) -> bool {
    var subs: [4]nats.Sub = zero
    var c = nats.client(subs[0usize..])
    var sent = ""
    var events = ""
    var out: [512]u8 = zero
    var server = "INFO {\"server_id\":\"NSESS\",\"version\":\"2.10.1\",\"headers\":true,\"max_payload\":1048576,\"proto\":1}\r\n"
    server = cat(a, server, "PONG\r\n")
    server = cat(a, server, "MSG orders.new 1 5\r\nhello\r\n")
    server = cat(a, server, "HMSG _INBOX.abc.7 2 12 14\r\nNATS/1.0\r\n\r\nok\r\n")
    server = cat(a, server, "PING\r\n")
    server = cat(a, server, "MSG _INBOX.abc.9 2 1\r\nx\r\n")
    server = cat(a, server, "MSG gone 9 0\r\n\r\n")
    var at = 0usize
    var step = 0usize
    while at < server.len {
        let (op, used, e) = nats.parse(server[at..], 1048576usize)
        if e != ok { ret false }
        at += used
        let (event, n, handle_error) = nats.handle(&c, op, out[0usize..])
        if handle_error != ok { ret false }
        sent = cat(a, sent, hex(a, out[0usize..n]))
        if step == 0usize {
            // INFO: the client answers with CONNECT and PING, then both subscriptions and the request.
            var o = nats.options(false)
            o.name = "t1"
            let (hn, he) = nats.handshake(&c, out[0usize..], &o)
            if he != ok { ret false }
            sent = cat(a, sent, hex(a, out[0usize..hn]))
            let (sid1, sn1, se1) = nats.subscribe(&c, out[0usize..], "orders.*", "workers", 0u64)
            if se1 != ok || sid1 != 1u64 { ret false }
            sent = cat(a, sent, hex(a, out[0usize..sn1]))
            let (sid2, sn2, se2) = nats.subscribe(&c, out[0usize..], "_INBOX.abc.*", "", 2u64)
            if se2 != ok || sid2 != 2u64 { ret false }
            sent = cat(a, sent, hex(a, out[0usize..sn2]))
            var reply_buf: [64]u8 = zero
            let (reply, re) = nats.reply_subject(reply_buf[0usize..], "_INBOX.abc", 7u64)
            if re != ok { ret false }
            let (pn, pe) = nats.encode_pub(out[0usize..], "svc.echo", reply, "hi")
            if pe != ok { ret false }
            sent = cat(a, sent, hex(a, out[0usize..pn]))
        }
        var name = "?"
        if event == .Info { name = "I" }
        if event == .Pong { name = "O" }
        if event == .Delivered { name = "D" }
        if event == .Finished { name = "F" }
        if event == .Ping { name = "G" }
        if event == .Dropped { name = "X" }
        if step > 0usize { events = cat(a, events, "~") }
        events = cat(a, events, name)
        step += 1usize
    }
    if !c.connected || c.received != 3u64 || c.info.max_payload != 1048576u64 { ret false }
    // sid 2 was spent by its UNSUB limit, sid 1 remains.
    if subs[1usize].used || !subs[0usize].used { ret false }
    if !str.eq(events, "I~O~D~D~G~F~X") { ret false }
    ret str.eq(sent, session_sent())
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    if !session(a) { os.exit(80i32) }
    try io.print("net nats ok")
    ret ok
}
