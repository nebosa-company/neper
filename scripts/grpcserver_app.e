// The echo service both the live interop server and the replay fixture of `e.net.grpcserver` run (L164): a fragment
// concatenated after the `use` lines of scripts/grpcserver_interop_template.e and scripts/grpcserver_fixture_template.e by
// scripts/grpcserver_vectors.py, so the server that grpcio called and the server the fixture replays are one piece of code.
// Methods of `test.Echo`: Unary reverses the request, Empty answers an empty message, Fail and StatusMessage end with a
// status and a non-ASCII message, Meta carries initial and trailing metadata (a `-bin` value too), Big answers 70000 bytes
// (more than a flow-control window, so the write is resumed after WINDOW_UPDATEs), Gzip answers a message flagged
// compressed under `grpc-encoding: gzip`, ServerStream sends three messages, ClientStream joins what it is sent, Bidi
// upper-cases each message, BigRequest answers the byte count of what it was sent, Deadline answers DEADLINE_EXCEEDED when
// the call carried a deadline, Slow never answers; anything else is UNIMPLEMENTED.

const K_UNIMPL: u8 = 0u8
const K_UNARY: u8 = 1u8
const K_EMPTY: u8 = 2u8
const K_FAIL: u8 = 3u8
const K_META: u8 = 4u8
const K_BIG: u8 = 5u8
const K_GZIP: u8 = 6u8
const K_STATUS: u8 = 7u8
const K_SSTREAM: u8 = 8u8
const K_CSTREAM: u8 = 9u8
const K_BIDI: u8 = 10u8
const K_BIGREQ: u8 = 11u8
const K_DEADLINE: u8 = 12u8
const K_SLOW: u8 = 13u8

type Slot = struct { id: u32, used: bool, kind: u8, acc_len: usize, big_len: usize, big_at: usize, pending: bool }

type App = struct { srv: *gs.Server, slots: []Slot, acc: []u8, big: []u8 }

fn kind_of(path: str) -> u8 {
    if str.eq(path, "/test.Echo/Unary") { ret K_UNARY }
    if str.eq(path, "/test.Echo/Empty") { ret K_EMPTY }
    if str.eq(path, "/test.Echo/Fail") { ret K_FAIL }
    if str.eq(path, "/test.Echo/Meta") { ret K_META }
    if str.eq(path, "/test.Echo/Big") { ret K_BIG }
    if str.eq(path, "/test.Echo/Gzip") { ret K_GZIP }
    if str.eq(path, "/test.Echo/StatusMessage") { ret K_STATUS }
    if str.eq(path, "/test.Echo/ServerStream") { ret K_SSTREAM }
    if str.eq(path, "/test.Echo/ClientStream") { ret K_CSTREAM }
    if str.eq(path, "/test.Echo/Bidi") { ret K_BIDI }
    if str.eq(path, "/test.Echo/BigRequest") { ret K_BIGREQ }
    if str.eq(path, "/test.Echo/Deadline") { ret K_DEADLINE }
    if str.eq(path, "/test.Echo/Slow") { ret K_SLOW }
    ret K_UNIMPL
}

fn app_slot(app: *App, id: u32) -> usize {
    var i = 0usize
    while i < app.slots.len {
        if app.slots[i].used && app.slots[i].id == id { ret i }
        i += 1usize
    }
    ret app.slots.len
}

fn hex_nibble(c: u8) -> u8 {
    if c >= 97u8 { ret c - 87u8 }
    ret c - 48u8
}

// The canned gzip body of the Gzip method, as hex written by the generator.
fn gzip_hex() -> str { ret "//__GZIP_HEX__" }

fn gzip_body(dst: []u8) -> usize {
    let text = gzip_hex()
    var n = 0usize
    while n * 2usize + 1usize < text.len && n < dst.len {
        dst[n] = (hex_nibble(text[n * 2usize]) << 4u8) | hex_nibble(text[n * 2usize + 1usize])
        n += 1usize
    }
    ret n
}

// A whole small message: headers if not yet sent, then the DATA, appended to `out`.
fn say(app: *App, out: []u8, at: *usize, id: u32, payload: []const u8, compressed: bool) -> err {
    let (n, e) = gs.response_message(app.srv, out[*at..], id, payload, compressed)
    if e != ok { ret e }
    *at += n
    ret ok
}

fn finish(app: *App, out: []u8, at: *usize, id: u32, status: u32, message: str, meta: []const h2.Header) -> err {
    let (n, e) = gs.response_finish(app.srv, out[*at..], id, status, message, meta)
    if e != ok { ret e }
    *at += n
    ret ok
}

// Resume a pending Big answer: write what the windows allow, finish when all of it is out.
fn pump(app: *App, out: []u8, at: *usize, j: usize) -> err {
    let slot = &app.slots[j]
    if !slot.pending { ret ok }
    let (taken, written, e) = gs.response_write(app.srv, out[*at..], slot.id, app.big[slot.big_at..slot.big_len])
    if e != ok { ret e }
    *at += written
    slot.big_at += taken
    if slot.big_at == slot.big_len {
        slot.pending = false
        let none: []const h2.Header = zero
        ret finish(app, out, at, slot.id, grpc.OK, "", none)
    }
    ret ok
}

fn pump_all(app: *App, out: []u8, at: *usize) -> err {
    var j = 0usize
    while j < app.slots.len {
        if app.slots[j].used && app.slots[j].pending {
            let e = pump(app, out, at, j)
            if e != ok { ret e }
        }
        j += 1usize
    }
    ret ok
}

fn upper_into(dst: []u8, src: []const u8) {
    var i = 0usize
    while i < src.len {
        var c = src[i]
        if c >= 97u8 && c <= 122u8 { c = c - 32u8 }
        dst[i] = c
        i += 1usize
    }
}

fn decimal_into(dst: []u8, value: usize) -> usize {
    var digits: [20]u8 = zero
    var n = 0usize
    var v = value
    if v == 0usize {
        digits[0usize] = 48u8
        n = 1usize
    }
    while v > 0usize {
        digits[n] = 48u8 + u8(v % 10usize)
        v = v / 10usize
        n += 1usize
    }
    var i = 0usize
    while i < n {
        dst[i] = digits[n - 1usize - i]
        i += 1usize
    }
    ret n
}

// One event of the connection: what the service does about it, written to `out` at `at`.
fn app_event(app: *App, ev: gs.Event, out: []u8, at: *usize) -> err {
    let none: []const h2.Header = zero
    if ev.kind == gs.EVENT_REQUEST {
        var j = 0usize
        while j < app.slots.len && app.slots[j].used { j += 1usize }
        if j == app.slots.len { ret grpc.TooSmall }
        app.slots[j] = Slot { id: ev.stream, used: true, kind: kind_of(ev.text), acc_len: 0usize, big_len: 0usize, big_at: 0usize, pending: false }
        let kind = app.slots[j].kind
        if kind == K_UNIMPL { ret finish(app, out, at, ev.stream, grpc.UNIMPLEMENTED, "Method not found!", none) }
        if kind == K_DEADLINE && ev.nanos > 0u64 {
            let (n, e) = gs.response_deadline_exceeded(app.srv, out[*at..], ev.stream)
            if e != ok { ret e }
            *at += n
        }
        ret ok
    }
    let j = app_slot(app, ev.stream)
    if j == app.slots.len { ret ok }
    let slot = &app.slots[j]
    if ev.kind == gs.EVENT_RESET {
        slot.used = false
        ret ok
    }
    if ev.kind == gs.EVENT_MESSAGE {
        let id = ev.stream
        if slot.kind == K_UNARY {
            var reply: [512]u8 = zero
            var i = 0usize
            while i < ev.payload.len && i < reply.len {
                reply[i] = ev.payload[ev.payload.len - 1usize - i]
                i += 1usize
            }
            let e = say(app, out, at, id, reply[0usize..ev.payload.len], false)
            if e != ok { ret e }
            ret finish(app, out, at, id, grpc.OK, "", none)
        }
        if slot.kind == K_EMPTY {
            let e = say(app, out, at, id, "", false)
            if e != ok { ret e }
            ret finish(app, out, at, id, grpc.OK, "", none)
        }
        if slot.kind == K_FAIL { ret finish(app, out, at, id, grpc.NOT_FOUND, "no such thing: café 100% done", none) }
        if slot.kind == K_META {
            var meta: [2]h2.Header = zero
            var bin_text: [16]u8 = zero
            var raw_init: [4]u8 = zero
            raw_init[1usize] = 1u8
            raw_init[2usize] = 254u8
            raw_init[3usize] = 255u8
            let (bn, be) = grpc.binary_value_encode(bin_text[0usize..], raw_init[0usize..4usize])
            let bin_value: str = bin_text[0usize..bn]
            meta[0usize] = h2.Header { name: "x-init", value: "first" }
            meta[1usize] = h2.Header { name: "x-init-bin", value: bin_value }
            let (hn, he) = gs.response_headers(app.srv, out[*at..], id, meta[0usize..2usize])
            if he != ok { ret he }
            *at += hn
            var body: [128]u8 = zero
            body[0usize] = 109u8
            body[1usize] = 101u8
            body[2usize] = 116u8
            body[3usize] = 97u8
            body[4usize] = 58u8
            var i = 0usize
            while i < ev.payload.len && i + 5usize < body.len {
                body[5usize + i] = ev.payload[i]
                i += 1usize
            }
            let e = say(app, out, at, id, body[0usize..5usize + ev.payload.len], false)
            if e != ok { ret e }
            var trail: [2]h2.Header = zero
            var trail_bin: [16]u8 = zero
            var raw_trail: [3]u8 = zero
            raw_trail[0usize] = 255u8
            raw_trail[2usize] = 16u8
            let (tn, te) = grpc.binary_value_encode(trail_bin[0usize..], raw_trail[0usize..3usize])
            let trail_value: str = trail_bin[0usize..tn]
            trail[0usize] = h2.Header { name: "x-trail", value: "last" }
            trail[1usize] = h2.Header { name: "x-trail-bin", value: trail_value }
            ret finish(app, out, at, id, grpc.OK, "", trail[0usize..2usize])
        }
        if slot.kind == K_BIG {
            var i = 0usize
            let n = 70000usize

            app.big[0usize] = 0u8
            app.big[1usize] = u8((n >> 24usize) & 255usize)
            app.big[2usize] = u8((n >> 16usize) & 255usize)
            app.big[3usize] = u8((n >> 8usize) & 255usize)
            app.big[4usize] = u8(n & 255usize)
            while i < n {
                app.big[5usize + i] = u8((i * 7usize) & 255usize)
                i += 1usize
            }
            slot.big_len = 5usize + n
            slot.big_at = 0usize
            slot.pending = true
            ret pump(app, out, at, j)
        }
        if slot.kind == K_GZIP {
            var meta: [1]h2.Header = zero
            meta[0usize] = h2.Header { name: "grpc-encoding", value: "gzip" }
            let (hn, he) = gs.response_headers(app.srv, out[*at..], id, meta[0usize..1usize])
            if he != ok { ret he }
            *at += hn
            var body: [256]u8 = zero
            let n = gzip_body(body[0usize..])
            let e = say(app, out, at, id, body[0usize..n], true)
            if e != ok { ret e }
            ret finish(app, out, at, id, grpc.OK, "", none)
        }
        if slot.kind == K_STATUS {
            let e = say(app, out, at, id, "partial", false)
            if e != ok { ret e }
            ret finish(app, out, at, id, grpc.RESOURCE_EXHAUSTED, "quota ☃ exceeded", none)
        }
        if slot.kind == K_SSTREAM {
            var k = 0usize
            while k < 3usize {
                var body: [128]u8 = zero
                var i = 0usize
                while i < ev.payload.len && i + 1usize < body.len {
                    body[i] = ev.payload[i]
                    i += 1usize
                }
                body[ev.payload.len] = u8(k)
                let e = say(app, out, at, id, body[0usize..ev.payload.len + 1usize], false)
                if e != ok { ret e }
                k += 1usize
            }
            ret finish(app, out, at, id, grpc.OK, "", none)
        }
        if slot.kind == K_CSTREAM {
            if slot.acc_len > 0usize {
                app.acc[slot.acc_len] = 124u8
                slot.acc_len += 1usize
            }
            var i = 0usize
            while i < ev.payload.len {
                app.acc[slot.acc_len + i] = ev.payload[i]
                i += 1usize
            }
            slot.acc_len += ev.payload.len
            ret ok
        }
        if slot.kind == K_BIDI {
            var body: [256]u8 = zero
            upper_into(body[0usize..], ev.payload)
            ret say(app, out, at, id, body[0usize..ev.payload.len], false)
        }
        if slot.kind == K_BIGREQ {
            var body: [20]u8 = zero
            let n = decimal_into(body[0usize..], ev.payload.len)
            let e = say(app, out, at, id, body[0usize..n], false)
            if e != ok { ret e }
            ret finish(app, out, at, id, grpc.OK, "", none)
        }
        ret ok
    }
    if ev.kind == gs.EVENT_HALF_CLOSE {
        if slot.kind == K_CSTREAM {
            let e = say(app, out, at, ev.stream, app.acc[0usize..slot.acc_len], false)
            if e != ok { ret e }
            ret finish(app, out, at, ev.stream, grpc.OK, "", none)
        }
        if slot.kind == K_BIDI { ret finish(app, out, at, ev.stream, grpc.OK, "", none) }
        ret ok
    }
    ret ok
}
