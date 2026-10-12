// `e.net.grpcserver` over `e.net.http2` against grpcio (L164): scripts/grpcserver_vectors.py compiles the echo service
// (scripts/grpcserver_app.e) into a live server, calls it with a grpcio client through a recording proxy, asserts every
// outcome the client saw, and keeps each call's bytes in both directions. The expected request events come from an
// independent decode of the client's bytes (hyperframe, hpack, the message prefix); the expected response from the same
// decode of what the Neper server answered, which grpcio accepted. This fixture replays the client bytes at several chunk
// sizes into a server running the same service and compares the request events and the response, the response being read
// back with `e.net.grpc`'s client (itself checked against grpcio's server in net_grpc).
// Generated from scripts/grpcserver_fixture_template.e; do not edit.
use e.io
use e.mem
use e.net.grpc as grpc
use e.net.grpcserver as gs
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

// A payload as text: its hex, or for a large one `L<length>.<hash>` (h = h * 31 + byte, 32 bits).
fn pay(a: *mem.Arena, p: []const u8) -> str {
    if p.len <= 1024usize { ret hex(a, p) }
    var h = 0u64
    var i = 0usize
    while i < p.len {
        h = (h * 31u64 + u64(p[i])) & 4294967295u64
        i += 1usize
    }
    ret cat(a, cat(a, cat(a, "L", dec(a, u64(p.len))), "."), dec(a, h))
}

fn standard_name(name: str) -> bool {
    if name.len > 0usize && name[0usize] == 58u8 { ret true }
    if str.eq(name, "content-type") || str.eq(name, "grpc-status") || str.eq(name, "grpc-message") || str.eq(name, "grpc-encoding") { ret true }
    if str.eq(name, "grpc-accept-encoding") || str.eq(name, "user-agent") || str.eq(name, "server") || str.eq(name, "date") || str.eq(name, "accept-encoding") { ret true }
    if str.eq(name, "te") || str.eq(name, "grpc-timeout") { ret true }
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
                if decode_error != ok { os.exit(95i32) }
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

fn render_client_event(a: *mem.Arena, ev: grpc.Event) -> str {
    if ev.kind == grpc.EVENT_HEADERS { ret cat(a, "H:", custom(a, ev.headers)) }
    if ev.kind == grpc.EVENT_MESSAGE {
        var flag = "0"
        if ev.compressed { flag = "1" }
        ret cat(a, cat(a, cat(a, "M:", pay(a, ev.payload)), ":"), flag)
    }
    if ev.kind == grpc.EVENT_TRAILERS {
        var s = cat(a, "T:", dec(a, u64(ev.code)))
        s = cat(a, cat(a, s, ":"), hex(a, ev.text))
        s = cat(a, cat(a, s, ":"), custom(a, ev.headers))
        ret s
    }
    ret "?"
}

fn render_server_event(a: *mem.Arena, ev: gs.Event) -> str {
    if ev.kind == gs.EVENT_REQUEST {
        var s = cat(a, "R:", hex(a, ev.text))
        s = cat(a, cat(a, s, ":"), dec(a, ev.nanos))
        s = cat(a, cat(a, s, ":"), custom(a, ev.headers))
        ret s
    }
    if ev.kind == gs.EVENT_MESSAGE {
        var flag = "0"
        if ev.compressed { flag = "1" }
        ret cat(a, cat(a, cat(a, "M:", pay(a, ev.payload)), ":"), flag)
    }
    if ev.kind == gs.EVENT_HALF_CLOSE { ret "C" }
    if ev.kind == gs.EVENT_RESET { ret cat(a, "X:", dec(a, u64(ev.code))) }
    if ev.kind == gs.EVENT_GOAWAY { ret cat(a, "G:", dec(a, u64(ev.code))) }
    ret "?"
}

fn new_client(a: *mem.Arena) -> grpc.Conn {
    let (streams, streams_error) = mem.alloc[grpc.Stream](a, 4usize)
    let (enc_data, e1) = mem.alloc[u8](a, 4096usize)
    let (enc_lens, e2) = mem.alloc[u32](a, 256usize)
    let (dec_data, e3) = mem.alloc[u8](a, 4096usize)
    let (dec_lens, e4) = mem.alloc[u32](a, 256usize)
    let (block, e5) = mem.alloc[u8](a, 16384usize)
    if streams_error != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(97i32) }
    ret grpc.conn_new(streams, h2.table_new(enc_data, enc_lens, 4096usize), h2.table_new(dec_data, dec_lens, 4096usize), block, 1048576u32, 4194304u32)
}

// The server's bytes as the Neper client reads them, rendered: `H:..|M:..|T:..`.
fn read_back(a: *mem.Arena, path: str, data: []const u8) -> str {
    var conn = new_client(a)
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
    var saw_headers = false
    var start = 0usize
    var events: [16]grpc.Event = zero
    var hdr: [64]h2.Header = zero
    var scratch: [8192]u8 = zero
    var reply: [1024]u8 = zero
    while true {
        let (used, replied, count, e) = grpc.conn_receive(&conn, data[start..], reply[0usize..], events[0usize..], hdr[0usize..], scratch[0usize..])
        if e != ok { ret cat(a, text, "!err") }
        var k = 0usize
        while k < count {
            if !first { text = cat(a, text, "|") }
            first = false
            text = cat(a, text, render_client_event(a, events[k]))
            if events[k].kind == grpc.EVENT_HEADERS { saw_headers = true }
            if events[k].kind == grpc.EVENT_TRAILERS && saw_headers {
                // trailers after initial headers carry no pseudo-header
                var h = 0usize
                while h < events[k].headers.len {
                    if events[k].headers[h].name.len > 0usize && events[k].headers[h].name[0usize] == 58u8 { text = cat(a, text, "!pseudo") }
                    h += 1usize
                }
            }
            k += 1usize
        }
        start += used
        if used == 0usize { break }
    }
    ret text
}

//__APP__

type Replay = struct { requests: str, response: []u8 }

// Run the service over the client's bytes, delivered `chunk` at a time.
fn replay(a: *mem.Arena, chunk: usize, data: []const u8) -> Replay {
    let (calls, ce) = mem.alloc[gs.Call](a, 4usize)
    if ce != ok { os.exit(100i32) }
    var c = 0usize
    while c < calls.len {
        let (buf, be) = mem.alloc[u8](a, 131072usize)
        if be != ok { os.exit(101i32) }
        calls[c].buf = buf
        c += 1usize
    }
    let (enc_data, e1) = mem.alloc[u8](a, 8192usize)
    let (enc_lens, e2) = mem.alloc[u32](a, 256usize)
    let (dec_data, e3) = mem.alloc[u8](a, 8192usize)
    let (dec_lens, e4) = mem.alloc[u32](a, 256usize)
    let (block, e5) = mem.alloc[u8](a, 16384usize)
    let (out, e6) = mem.alloc[u8](a, 262144usize)
    let (total, e7) = mem.alloc[u8](a, 400000usize)
    let (scratch, e8) = mem.alloc[u8](a, 16384usize)
    let (events, e9) = mem.alloc[gs.Event](a, 32usize)
    let (hdr, e10) = mem.alloc[h2.Header](a, 128usize)
    let (acc, e11) = mem.alloc[u8](a, 4096usize)
    let (big, e12) = mem.alloc[u8](a, 70016usize)
    let (slots, e13) = mem.alloc[Slot](a, 6usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { os.exit(102i32) }
    var s = gs.server_new(calls, h2.table_new(enc_data, enc_lens, 4096usize), h2.table_new(dec_data, dec_lens, 4096usize), block, 65535u32, 16384u32)
    var z = 0usize
    while z < slots.len {
        slots[z].used = false
        z += 1usize
    }
    var app = App { srv: &s, slots: slots, acc: acc, big: big }
    var total_len = 0usize
    let (start_len, start_error) = gs.server_start(&s, out)
    if start_error != ok { os.exit(103i32) }
    mem.copy[u8](total[0usize..start_len], out[0usize..start_len])
    total_len = start_len
    var text = ""
    var first = true
    var start = 0usize
    var have = 0usize
    while true {
        have += chunk
        if have > data.len { have = data.len }
        while true {
            let (used, out_n, count, rx) = gs.server_receive(&s, data[start..have], out, events, hdr, scratch)
            if rx != ok {
                text = cat(a, text, "!rx")
                have = data.len
                break
            }
            var at = out_n
            var k = 0usize
            while k < count {
                if !first { text = cat(a, text, "|") }
                first = false
                text = cat(a, text, render_server_event(a, events[k]))
                let ae = app_event(&app, events[k], out, &at)
                if ae != ok { text = cat(a, text, "!app") }
                k += 1usize
            }
            let pe = pump_all(&app, out, &at)
            if pe != ok { text = cat(a, text, "!pump") }
            if total_len + at > total.len { os.exit(104i32) }
            mem.copy[u8](total[total_len..total_len + at], out[0usize..at])
            total_len += at
            start += used
            if used == 0usize && count == 0usize { break }
        }
        if have == data.len { break }
    }
    ret Replay { requests: text, response: total[0usize..total_len] }
}

fn run_one(a: *mem.Arena, line: str) -> bool {
    var rest = line
    let kind = field(&rest)
    if str.eq(kind, "S") {
        let name = field(&rest)
        let path = unhex(a, field(&rest))
        let chunk = usize(num(field(&rest)))
        let data = unhex(a, field(&rest))
        let want_requests = field(&rest)
        let want_response = field(&rest)
        let r = replay(a, chunk, data)
        let got_response = read_back(a, path, r.response)
        var good = true
        if !str.eq(r.requests, want_requests) {
            good = false
            var n = r.requests.len
            if n > 120usize { n = 120usize }
            let shown = io.print(cat(a, cat(a, cat(a, name, " requests: "), r.requests[0usize..n]), "\n"))
        }
        if !str.eq(got_response, want_response) {
            good = false
            var n = got_response.len
            if n > 160usize { n = 160usize }
            let shown = io.print(cat(a, cat(a, cat(a, name, " response: "), got_response[0usize..n]), "\n"))
        }
        ret good
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
            if !run_one(a, line) { ret 1u8 }
            mem.reset(a, mark)
            start = i + 1usize
        }
        i += 1usize
    }
    ret 0u8
}

fn main(a: *mem.Arena, args: []str) -> err {
    //__VECTOR_CALLS__
    try io.print("net grpcserver ok")
    ret ok
}
