// `e.net.grpc` over `e.net.http2` against grpcio (L101): scripts/grpc_vectors.py runs a grpcio server behind a
// recording proxy and keeps each call's server-to-client bytes; the expected events come from an independent decode
// (hyperframe, hpack, the message prefix) asserted equal to what the grpcio client observed. The client's own bytes
// (preface, SETTINGS, HEADERS, DATA, RST_STREAM) are compared with goldens that `h2` read back, as a server, to the
// scenario. This fixture replays the transcripts at several chunk sizes and compares event text; the specification's
// small functions (timeouts, message prefix, status mapping, percent-encoding, `-bin` values) are vectors too.
// Generated from scripts/grpc_fixture_template.e; do not edit.
use e.bytes
use e.io
use e.mem
use e.net.grpc as grpc
use e.net.http2 as h2
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
    var at = 24usize
    var v = n
    if v == 0u64 {
        at -= 1usize
        buf[at] = 48u8
    }
    while v > 0u64 {
        at -= 1usize
        buf[at] = 48u8 + u8(v % 10u64)
        v = v / 10u64
    }
    let (out, e) = mem.alloc[u8](a, 24usize - at)
    if e != ok { os.exit(93i32) }
    mem.copy[u8](out, buf[at..24usize])
    ret out
}

fn num(s: str) -> u64 {
    var v = 0u64
    var i = 0usize
    while i < s.len {
        v = v * 10u64 + u64(s[i] - 48u8)
        i += 1usize
    }
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

fn item_at(text: str, sep: u8, index: usize) -> (str, bool) {
    var start = 0usize
    var n = 0usize
    var i = 0usize
    while i <= text.len {
        if i == text.len || text[i] == sep {
            if n == index { ret (text[start..i], true) }
            n += 1usize
            start = i + 1usize
        }
        i += 1usize
    }
    ret ("", false)
}

fn item_count(text: str, sep: u8) -> usize {
    if text.len == 0usize { ret 0usize }
    var n = 1usize
    var i = 0usize
    while i < text.len {
        if text[i] == sep { n += 1usize }
        i += 1usize
    }
    ret n
}

fn err_name(e: err) -> str {
    if e == grpc.Incomplete { ret "Incomplete" }
    if e == grpc.Invalid { ret "Invalid" }
    if e == grpc.TooLarge { ret "TooLarge" }
    if e == grpc.TooSmall { ret "TooSmall" }
    if e == grpc.Protocol { ret "Protocol" }
    if e == grpc.Blocked { ret "Blocked" }
    if e == grpc.NoStream { ret "NoStream" }
    if e == ok { ret "ok" }
    ret "other"
}

fn standard_name(name: str) -> bool {
    if name.len > 0usize && name[0usize] == 58u8 { ret true }
    if str.eq(name, "content-type") || str.eq(name, "grpc-status") || str.eq(name, "grpc-message") || str.eq(name, "grpc-encoding") { ret true }
    if str.eq(name, "grpc-accept-encoding") || str.eq(name, "user-agent") || str.eq(name, "server") || str.eq(name, "date") || str.eq(name, "accept-encoding") { ret true }
    ret false
}

// The custom metadata of a header list as `hexname=hexvalue,...` (`-bin` values decoded), or `-`.
fn custom(a: *mem.Arena, headers: []const h2.Header) -> str {
    var text = ""
    var first = true
    var i = 0usize
    while i < headers.len {
        let name = headers[i].name
        if !standard_name(name) {
            var value: str = headers[i].value
            if grpc.ends_with_bin(name) {
                let (buf, e) = mem.alloc[u8](a, value.len + 4usize)
                if e != ok { os.exit(94i32) }
                let (n, decode_error) = grpc.binary_value_decode(buf, value)
                if decode_error != ok {
                    let shown = io.print(cat(a, cat(a, name, "="), value))
                    os.exit(95i32)
                }
                value = buf[0usize..n]
            }
            if !first { text = cat(a, text, ",") }
            first = false
            text = cat(a, cat(a, cat(a, text, hex(a, name)), "="), hex(a, value))
        }
        i += 1usize
    }
    if first { ret "-" }
    ret text
}

fn render_event(a: *mem.Arena, ev: grpc.Event) -> str {
    if ev.kind == grpc.EVENT_HEADERS { ret cat(a, "H:", custom(a, ev.headers)) }
    if ev.kind == grpc.EVENT_MESSAGE {
        var flag = "0"
        if ev.compressed { flag = "1" }
        ret cat(a, cat(a, cat(a, "M:", hex(a, ev.payload)), ":"), flag)
    }
    if ev.kind == grpc.EVENT_TRAILERS {
        var s = cat(a, "T:", dec(a, u64(ev.code)))
        s = cat(a, cat(a, s, ":"), hex(a, ev.text))
        s = cat(a, cat(a, s, ":"), custom(a, ev.headers))
        ret s
    }
    ret "?"
}

fn new_conn(a: *mem.Arena) -> grpc.Conn {
    let (streams, streams_error) = mem.alloc[grpc.Stream](a, 4usize)
    let (enc_data, e1) = mem.alloc[u8](a, 4096usize)
    let (enc_lens, e2) = mem.alloc[u32](a, 256usize)
    let (dec_data, e3) = mem.alloc[u8](a, 4096usize)
    let (dec_lens, e4) = mem.alloc[u32](a, 256usize)
    let (block, e5) = mem.alloc[u8](a, 16384usize)
    if streams_error != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(97i32) }
    ret grpc.conn_new(streams, h2.table_new(enc_data, enc_lens, 4096usize), h2.table_new(dec_data, dec_lens, 4096usize), block, 1048576u32, 4194304u32)
}

fn parse_metadata(a: *mem.Arena, text: str, out: []h2.Header) -> usize {
    if str.eq(text, "-") { ret 0usize }
    let n = item_count(text, 44u8)
    var i = 0usize
    while i < n {
        let (pair, found) = item_at(text, 44u8, i)
        let (name_hex, value_hex, eq) = str.split_once(pair, "=")
        if !found || !eq { os.exit(96i32) }
        out[i] = h2.Header { name: unhex(a, name_hex), value: unhex(a, value_hex) }
        i += 1usize
    }
    ret n
}

fn run_transcript(a: *mem.Arena, path: str, chunk: usize, data: []const u8) -> str {
    var conn = new_conn(a)
    var out: [4096]u8 = zero
    let (started, start_error) = grpc.conn_start(&conn, out[0usize..])
    if start_error != ok { ret "!start" }
    let (buf, buf_error) = mem.alloc[u8](a, 262144usize)
    if buf_error != ok { os.exit(98i32) }
    var none: [1]h2.Header = zero
    let (id, written, call_error) = grpc.call_start(&conn, out[0usize..], "localhost", path, 0u64, none[0usize..0usize], buf)
    if call_error != ok || id != 1u32 { ret "!call" }
    var text = ""
    var first = true
    var start = 0usize
    var have = 0usize
    var events: [16]grpc.Event = zero
    var hdr: [64]h2.Header = zero
    var scratch: [8192]u8 = zero
    var reply: [1024]u8 = zero
    while true {
        have += chunk
        if have > data.len { have = data.len }
        while true {
            let (used, replied, count, e) = grpc.conn_receive(&conn, data[start..have], reply[0usize..], events[0usize..], hdr[0usize..], scratch[0usize..])
            if e != ok { ret cat(a, cat(a, text, "!"), err_name(e)) }
            var k = 0usize
            while k < count {
                if !first { text = cat(a, text, "|") }
                first = false
                text = cat(a, text, render_event(a, events[k]))
                k += 1usize
            }
            start += used
            if used == 0usize { break }
        }
        if have == data.len { break }
    }
    ret text
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    if str.eq(kind, "G") {
        let name = field(&rest)
        let path = unhex(a, field(&rest))
        let chunk = usize(num(field(&rest)))
        let data = unhex(a, field(&rest))
        let want = field(&rest)
        let got = run_transcript(a, path, chunk, data)
        if !str.eq(got, want) {
            var shown_len = got.len
            if shown_len > 80usize { shown_len = 80usize }
            let shown = io.print(cat(a, cat(a, cat(a, cat(a, name, " got: "), dec(a, u64(got.len))), " "), cat(a, got[0usize..shown_len], "\n")))
        }
        ret str.eq(got, want)
    }
    if str.eq(kind, "O") {
        let nanos = num(field(&rest))
        let want = field(&rest)
        var buf: [16]u8 = zero
        let (n, e) = grpc.timeout_encode(buf[0usize..], nanos)
        ret e == ok && str.eq(buf[0usize..n], want)
    }
    if str.eq(kind, "Op") {
        let text = unhex(a, field(&rest))
        let want = field(&rest)
        let (v, e) = grpc.timeout_parse(text)
        if str.eq(want, "Invalid") { ret e == grpc.Invalid }
        ret e == ok && v == num(want)
    }
    if str.eq(kind, "Mf") {
        let payload = unhex(a, field(&rest))
        let compressed = str.eq(field(&rest), "1")
        let want = field(&rest)
        let (buf, buf_error) = mem.alloc[u8](a, payload.len + 8usize)
        if buf_error != ok { os.exit(99i32) }
        let (n, e) = grpc.message_encode(buf, payload, compressed)
        ret e == ok && str.eq(hex(a, buf[0usize..n]), want)
    }
    if str.eq(kind, "Md") {
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        let (m, used, e) = grpc.message_decode(raw, 1048576usize)
        if e != ok { ret str.eq(err_name(e), want) }
        var flag = "0"
        if m.compressed { flag = "1" }
        ret str.eq(cat(a, cat(a, cat(a, "ok:", flag), ":"), hex(a, m.payload)), want) && used == raw.len
    }
    if str.eq(kind, "Pe") {
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        var buf: [1024]u8 = zero
        let (n, e) = grpc.message_percent_encode(buf[0usize..], raw)
        ret e == ok && str.eq(hex(a, buf[0usize..n]), want)
    }
    if str.eq(kind, "Pd") {
        let text = unhex(a, field(&rest))
        let want = field(&rest)
        var buf: [256]u8 = zero
        let (n, e) = grpc.message_percent_decode(buf[0usize..], text)
        ret e == ok && str.eq(hex(a, buf[0usize..n]), want)
    }
    if str.eq(kind, "Hs") {
        ret u64(grpc.http_to_grpc(u32(num(field(&rest))))) == num(field(&rest))
    }
    if str.eq(kind, "Sn") {
        let code = u32(num(field(&rest)))
        let name = unhex(a, field(&rest))
        ret str.eq(grpc.status_name(code), name)
    }
    if str.eq(kind, "Bn") {
        let raw = unhex(a, field(&rest))
        let want = field(&rest)
        var buf: [128]u8 = zero
        let (n, e) = grpc.binary_value_encode(buf[0usize..], raw)
        if e != ok || !str.eq(buf[0usize..n], want) { ret false }
        var back: [128]u8 = zero
        let (m, de) = grpc.binary_value_decode(back[0usize..], want)
        if de != ok || !str.eq(back[0usize..m], raw) { ret false }
        // padded form is accepted too
        var padded: [128]u8 = zero
        let (text, pe) = bytes.base64_encode(padded[0usize..], raw, .Standard, true)
        if pe != ok { ret false }
        let (p, pde) = grpc.binary_value_decode(back[0usize..], text)
        ret pde == ok && str.eq(back[0usize..p], raw)
    }
    if str.eq(kind, "C") {
        let index = num(field(&rest))
        let authority = unhex(a, field(&rest))
        let path = unhex(a, field(&rest))
        let timeout = num(field(&rest))
        let meta_text = field(&rest)
        let messages_text = field(&rest)
        let mode = field(&rest)
        let golden = field(&rest)
        var metadata: [8]h2.Header = zero
        let meta_count = parse_metadata(a, meta_text, metadata[0usize..])
        var conn = new_conn(a)
        let (out, out_error) = mem.alloc[u8](a, 200000usize)
        if out_error != ok { os.exit(98i32) }
        var at = 0usize
        let (n0, e0) = grpc.conn_start(&conn, out[at..])
        if e0 != ok { ret false }
        at += n0
        let (buf, buf_error) = mem.alloc[u8](a, 1024usize)
        if buf_error != ok { os.exit(98i32) }
        let (id, n1, e1) = grpc.call_start(&conn, out[at..], authority, path, timeout, metadata[0usize..meta_count], buf)
        if e1 != ok { ret false }
        at += n1
        let count = item_count(messages_text, 44u8)
        var real = count
        if str.eq(messages_text, "-") { real = 0usize }
        var m = 0usize
        while m < real {
            let (item, found) = item_at(messages_text, 44u8, m)
            let payload = unhex(a, item[1usize..])
            var last = false
            if m + 1usize == real && str.eq(mode, "eos") { last = true }
            let (n2, e2) = grpc.call_send(&conn, out[at..], id, payload, false, last)
            if e2 != ok { ret false }
            at += n2
            m += 1usize
        }
        if str.eq(mode, "eos") && real == 0usize {
            let (n3, e3) = grpc.call_close_send(&conn, out[at..], id)
            if e3 != ok { ret false }
            at += n3
        } else if str.eq(mode, "close") {
            let (n4, e4) = grpc.call_close_send(&conn, out[at..], id)
            if e4 != ok { ret false }
            at += n4
        } else if str.eq(mode, "cancel") {
            let (n5, e5) = grpc.call_cancel(&conn, out[at..], id)
            if e5 != ok { ret false }
            at += n5
        }
        if golden.len == 0usize {
            var gold = cat(a, "GOLD\t", dec(a, index))
            gold = cat(a, cat(a, gold, "\t"), hex(a, out[0usize..at]))
            let shown = io.print(cat(a, gold, "\n"))
            ret true
        }
        ret str.eq(hex(a, out[0usize..at]), golden[1usize..])
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

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("net grpc ok")
    ret ok
}
