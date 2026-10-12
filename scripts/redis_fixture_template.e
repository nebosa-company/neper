// `x.redis.resp` against redis-py (L114): scripts/redis_vectors.py builds RESP2 and RESP3 reply streams from a typed
// model, asserts redis-py's own parsers read them as the model's type-erased form, and gives command bytes
// (`Connection.pack_command`), cluster slots (`redis.crc.key_slot`) and redirects (`AskError`/`MovedError`). This
// fixture re-chunks each stream (a split anywhere in a reply is covered) and compares typed text. Pub/sub and
// session accounting are defined by the generator's model and checked in the scripted session at the end.
// Generated from scripts/redis_fixture_template.e; do not edit.
use e.io
use e.mem
use e.os
use e.str
use x.redis.resp as resp

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

fn dec(a: *mem.Arena, n: i64) -> str {
    let negative = n < 0i64
    var magnitude = 0u64
    if negative {
        magnitude = u64(0i64 - (n + 1i64)) + 1u64
    } else {
        magnitude = u64(n)
    }
    var buf: [24]u8 = zero
    var at = 24usize
    if magnitude == 0u64 {
        at -= 1usize
        buf[at] = 48u8
    }
    while magnitude > 0u64 {
        at -= 1usize
        buf[at] = 48u8 + u8(magnitude % 10u64)
        magnitude = magnitude / 10u64
    }
    if negative {
        at -= 1usize
        buf[at] = 45u8
    }
    let (out, e) = mem.alloc[u8](a, 24usize - at)
    if e != ok { os.exit(93i32) }
    mem.copy[u8](out, buf[at..24usize])
    ret out
}

fn num(a: *mem.Arena, s: str) -> i64 {
    let (v, good) = resp.parse_integer(s)
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

// The typed text the generator writes for a value.
fn render(a: *mem.Arena, v: resp.Value) -> str {
    switch v {
    case .Null:
        ret "N"
    case .Simple as s:
        ret cat(a, "+", hex(a, s))
    case .Error as s:
        ret cat(a, "-", hex(a, s))
    case .Integer as n:
        ret cat(a, ":", dec(a, n))
    case .Bulk as b:
        ret cat(a, "$", hex(a, b))
    case .Bool as t:
        if t { ret "#t" }
        ret "#f"
    case .Double as d:
        let bits = mem.bitcast[u64](d)
        var raw: [8]u8 = zero
        var i = 0usize
        while i < 8usize {
            raw[i] = u8((bits >> (56u64 - u64(i) * 8u64)) & 255u64)
            i += 1usize
        }
        ret cat(a, ",", hex(a, raw[0usize..8usize]))
    case .Big as s:
        ret cat(a, "(", hex(a, s))
    case .BlobError as b:
        ret cat(a, "!", hex(a, b))
    case .Verbatim as vb:
        ret cat(a, cat(a, cat(a, "=", hex(a, vb.format)), ":"), hex(a, vb.data))
    case .Array as items:
        ret cat(a, "*", list(a, items))
    case .Set as items:
        ret cat(a, "~", list(a, items))
    case .Push as items:
        ret cat(a, ">", list(a, items))
    case .Map as pairs:
        var s = "%["
        var i = 0usize
        while i < pairs.len {
            if i > 0usize { s = cat(a, s, ",") }
            s = cat(a, s, render(a, pairs[i].key))
            s = cat(a, s, "=")
            s = cat(a, s, render(a, pairs[i].value))
            i += 1usize
        }
        ret cat(a, s, "]")
    }
    ret "?"
}

fn list(a: *mem.Arena, items: []const resp.Value) -> str {
    var s = "["
    var i = 0usize
    while i < items.len {
        if i > 0usize { s = cat(a, s, ",") }
        s = cat(a, s, render(a, items[i]))
        i += 1usize
    }
    ret cat(a, s, "]")
}

fn err_name(e: err) -> str {
    if e == resp.Incomplete { ret "Incomplete" }
    if e == resp.Invalid { ret "Invalid" }
    if e == resp.TooLarge { ret "TooLarge" }
    if e == resp.TooSmall { ret "TooSmall" }
    if e == ok { ret "ok" }
    ret "other"
}

fn run_stream(a: *mem.Arena, data: []const u8, chunk: usize, lim: *const resp.Limits) -> (str, bool) {
    var out = ""
    var first = true
    var start = 0usize
    var have = 0usize
    while true {
        have += chunk
        if have > data.len { have = data.len }
        while true {
            let (v, used, e) = resp.parse(a, data[start..have], lim)
            if e == resp.Incomplete { break }
            if e != ok { ret (cat(a, out, "!bad"), false) }
            if !first { out = cat(a, out, ";") }
            first = false
            out = cat(a, out, render(a, v))
            start += used
        }
        if have == data.len { break }
    }
    ret (out, start < data.len)
}

fn kind_name(k: resp.ErrorKind) -> str {
    if k == .Generic { ret "Generic" }
    if k == .Moved { ret "Moved" }
    if k == .Ask { ret "Ask" }
    if k == .WrongType { ret "WrongType" }
    if k == .NoAuth { ret "NoAuth" }
    if k == .ReadOnly { ret "ReadOnly" }
    if k == .Loading { ret "Loading" }
    if k == .TryAgain { ret "TryAgain" }
    if k == .ClusterDown { ret "ClusterDown" }
    if k == .MasterDown { ret "MasterDown" }
    if k == .NoScript { ret "NoScript" }
    if k == .Busy { ret "Busy" }
    ret "?"
}

// The comma-separated hex arguments of a command vector; `L<n>` stands for n bytes of `x`.
fn parse_args(a: *mem.Arena, text: str, out: [][]const u8) -> usize {
    var count = 0usize
    var cursor = text
    while cursor.len > 0usize {
        let (item, tail, more) = str.split_once(cursor, ",")
        var current = cursor
        if more {
            current = item
            cursor = tail
        } else {
            cursor = ""
        }
        if current.len > 0usize && current[0usize] == 76u8 {
            let size = usize(num(a, current[1usize..]))
            let (big, big_error) = mem.alloc[u8](a, size)
            if big_error != ok { os.exit(97i32) }
            var k = 0usize
            while k < size {
                big[k] = 120u8
                k += 1usize
            }
            out[count] = big
        } else {
            out[count] = unhex(a, current[1usize..])
        }
        count += 1usize
    }
    ret count
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    var lim = resp.limits()
    if str.eq(kind, "R") {
        let proto = field(&rest)
        let chunk = usize(num(a, field(&rest)))
        let data = unhex(a, field(&rest))
        let want = field(&rest)
        let leftover = str.eq(field(&rest), "1")
        let (got, partial) = run_stream(a, data, chunk, &lim)
        ret str.eq(got, want) && partial == leftover
    }
    if str.eq(kind, "B") {
        let data = unhex(a, field(&rest))
        let want = field(&rest)
        let (v, used, e) = resp.parse(a, data, &lim)
        ret str.eq(err_name(e), want)
    }
    if str.eq(kind, "C") {
        let list_text = field(&rest)
        let want = field(&rest)
        var args: [8][]const u8 = zero
        let n = parse_args(a, list_text, args[0usize..])
        let (buf, buf_error) = mem.alloc[u8](a, 80000usize)
        if buf_error != ok { os.exit(98i32) }
        let (used, e) = resp.encode_command(buf, args[0usize..n])
        if e != ok { ret false }
        if want[0usize] == 83u8 {
            ret used == usize(num(a, want[1usize..]))
        }
        ret str.eq(hex(a, buf[0usize..used]), want)
    }
    if str.eq(kind, "K") {
        let key = unhex(a, field(&rest))
        let slot = num(a, field(&rest))
        ret i64(resp.key_slot(key)) == slot
    }
    if str.eq(kind, "M") {
        let text = unhex(a, field(&rest))
        let found = str.eq(field(&rest), "1")
        let ask = str.eq(field(&rest), "1")
        let slot = num(a, field(&rest))
        let host = unhex(a, field(&rest))
        let port = num(a, field(&rest))
        let (r, good) = resp.parse_redirect(text)
        if good != found { ret false }
        if !found { ret true }
        ret r.ask == ask && i64(r.slot) == slot && str.eq(r.host, host) && i64(r.port) == port
    }
    if str.eq(kind, "E") {
        let text = unhex(a, field(&rest))
        let want = field(&rest)
        ret str.eq(kind_name(resp.error_kind(text)), want)
    }
    ret false
}

//__VECTOR_FUNCTIONS__
fn fail(line: str) {
    let shown = io.print(line)
}

fn run_chunk(a: *mem.Arena, body: str) -> u8 {
    var start = 0usize
    var i = 0usize
    while i < body.len {
        if body[i] == 10u8 {
            let mark = mem.mark(a)
            let line = body[start..i]
            if !run_one(a, line) {
                fail(line)
                ret 1u8
            }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn arg_list(a: *mem.Arena, one: str, two: str, three: str) -> []const []const u8 {
    let (items, e) = mem.alloc[[]const u8](a, 3usize)
    if e != ok { os.exit(99i32) }
    items[0usize] = one
    items[1usize] = two
    items[2usize] = three
    ret items
}

// A session with pub/sub in RESP2 and RESP3: SUBSCRIBE draws one confirmation per channel, messages are not
// replies, the count in a confirmation sets the session's subscriptions, a GET reply consumes one pending command.
fn session(a: *mem.Arena) -> bool {
    var lim = resp.limits()
    var out: [256]u8 = zero
    var s = resp.session(2u8)
    let (n1, e1) = resp.send(&s, out[0usize..], arg_list(a, "SUBSCRIBE", "news", "sport"), 2usize)
    if e1 != ok || s.pending != 2usize { ret false }
    if !str.eq(out[0usize..n1], "*3\r\n$9\r\nSUBSCRIBE\r\n$4\r\nnews\r\n$5\r\nsport\r\n") { ret false }
    let confirmations = "*3\r\n$9\r\nsubscribe\r\n$4\r\nnews\r\n:1\r\n*3\r\n$9\r\nsubscribe\r\n$5\r\nsport\r\n:2\r\n"
    var at = 0usize
    var seen = 0usize
    while at < confirmations.len {
        let (v, used, e) = resp.parse(a, confirmations[at..], &lim)
        if e != ok { ret false }
        at += used
        if !resp.is_reply(&s, v) { ret false }
        resp.note(&s, v)
        seen += 1usize
    }
    if seen != 2usize || s.pending != 0usize || s.subscriptions != 2usize { ret false }
    // A message in subscribed mode is not a reply and leaves the count alone.
    let message = "*3\r\n$7\r\nmessage\r\n$4\r\nnews\r\n$5\r\nhello\r\n"
    let (mv, mused, me) = resp.parse(a, message, &lim)
    if me != ok || mused != message.len || resp.is_reply(&s, mv) { ret false }
    resp.note(&s, mv)
    if s.pending != 0usize || s.subscriptions != 2usize { ret false }
    switch mv {
    case .Array as items:
        let (event, found) = resp.pubsub_event(items)
        if !found || event.kind != .Message || !str.eq(event.channel, "news") || !str.eq(event.payload, "hello") { ret false }
    default:
        ret false
    }
    // Unsubscribing everything returns the session to ordinary replies.
    let gone = "*3\r\n$11\r\nunsubscribe\r\n$4\r\nnews\r\n:1\r\n*3\r\n$11\r\nunsubscribe\r\n$5\r\nsport\r\n:0\r\n"
    s.pending = 2usize
    at = 0usize
    while at < gone.len {
        let (v, used, e) = resp.parse(a, gone[at..], &lim)
        if e != ok { ret false }
        at += used
        resp.note(&s, v)
    }
    if s.pending != 0usize || s.subscriptions != 0usize { ret false }
    // RESP3: a push is never a reply, a plain array is.
    var s3 = resp.session(3u8)
    s3.pending = 1usize
    let push = ">3\r\n$7\r\nmessage\r\n$4\r\nnews\r\n$2\r\nhi\r\n"
    let (pv, pused, pe) = resp.parse(a, push, &lim)
    if pe != ok || pused != push.len || resp.is_reply(&s3, pv) { ret false }
    resp.note(&s3, pv)
    if s3.pending != 1usize { ret false }
    let reply = "*1\r\n$1\r\nx\r\n"
    let (rv, rused, re) = resp.parse(a, reply, &lim)
    if re != ok || !resp.is_reply(&s3, rv) { ret false }
    resp.note(&s3, rv)
    if s3.pending != 0usize { ret false }
    // HELLO with and without AUTH.
    let (hn, he) = resp.encode_hello(out[0usize..], 3u8, "", "")
    if he != ok || !str.eq(out[0usize..hn], "*2\r\n$5\r\nHELLO\r\n$1\r\n3\r\n") { ret false }
    let (an, ae) = resp.encode_hello(out[0usize..], 3u8, "default", "pw")
    if ae != ok || !str.eq(out[0usize..an], "*5\r\n$5\r\nHELLO\r\n$1\r\n3\r\n$4\r\nAUTH\r\n$7\r\ndefault\r\n$2\r\npw\r\n") { ret false }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    if !session(a) { os.exit(80i32) }
    try io.print("x redis resp ok")
    ret ok
}
