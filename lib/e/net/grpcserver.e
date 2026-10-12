// gRPC over HTTP/2 (L164), server side, over caller buffers and `e.net.http2`: no sockets, the caller moves bytes. It is
// the mirror of the client in `e.net.grpc`, and shares its message framing, `grpc-timeout`, status text and metadata
// functions. `Server` is the connection state machine: it checks the client preface, sends its SETTINGS, answers the
// peer's SETTINGS and PING, keeps both HPACK tables and both flow-control windows, and `server_receive` turns incoming
// bytes into events -- a call's request (path, authority, the deadline as `grpc-timeout` sent it, every header),
// whole messages across DATA frame boundaries, the client's half-close, a reset, GOAWAY. A response is written by
// `response_headers`, `response_message` and `response_finish` (trailers with the status and its percent-encoded
// message, or a trailers-only reply when no headers went out), so unary and streaming calls of every shape are the same
// machine: a call is a stream, messages come and go on it until both sides are done.
//
// Message compression is reported (the flag, the payload as sent), never undone. A deadline is information: the
// caller compares the time it was given with the clock and answers `DEADLINE_EXCEEDED` itself
// (`response_deadline_exceeded`), as every gRPC server does.
//
// Memory: call slots (each with its reassembly buffer, set in buf before server_new), the header block buffer and both
// HPACK tables are the caller's.
use e.mem
use e.net.grpc as grpc
use e.net.http2 as h2
use e.str

const EVENT_REQUEST: u8 = 1u8
const EVENT_MESSAGE: u8 = 2u8
const EVENT_HALF_CLOSE: u8 = 3u8
const EVENT_RESET: u8 = 4u8
const EVENT_GOAWAY: u8 = 5u8

// `code` is a reset or GOAWAY code, or 1 on a request whose `grpc-timeout` did not parse; `text` is the path of a request;
// `nanos` is the deadline a request carried (0 for none).
type Event = struct { kind: u8, stream: u32, code: u32, compressed: bool, nanos: u64, text: str, payload: []const u8, headers: []const h2.Header }

type Call = struct { id: u32, used: bool, remote_closed: bool, half_close_sent: bool, local_headers: bool, local_closed: bool, send_window: i64, recv_window: i64, buf: []u8, buf_len: usize, consumed: usize }

type Server = struct { calls: []Call, last_stream: u32, enc: h2.Table, dec: h2.Table, send_window: i64, recv_window: i64, peer_initial_window: i64, peer_max_frame: usize, initial_recv: i64, max_frame: usize, got_preface: bool, started: bool, got_settings: bool, goaway: bool, block: []u8, block_len: usize, block_stream: u32, block_end_stream: bool, block_active: bool }

fn server_new(calls: []Call, enc: h2.Table, dec: h2.Table, block: []u8, initial_recv: u32, max_frame: u32) -> Server {
    var i = 0usize
    while i < calls.len {
        calls[i].used = false
        i += 1usize
    }
    ret Server { calls: calls, last_stream: 0u32, enc: enc, dec: dec, send_window: 65535i64, recv_window: 65535i64, peer_initial_window: 65535i64, peer_max_frame: 16384usize, initial_recv: i64(initial_recv), max_frame: usize(max_frame), got_preface: false, started: false, got_settings: false, goaway: false, block: block, block_len: 0usize, block_stream: 0u32, block_end_stream: false, block_active: false }
}

fn put_frame(dst: []u8, at: *usize, kind: u8, flags: u8, stream: u32, payload: []const u8) -> err {
    let (n, e) = h2.frame_encode(dst[*at..], kind, flags, stream, payload)
    if e != ok { ret grpc.TooSmall }
    *at += n
    ret ok
}

fn u32_bytes(v: u32) -> [4]u8 {
    var b: [4]u8 = zero
    b[0usize] = u8((v >> 24u32) & 255u32)
    b[1usize] = u8((v >> 16u32) & 255u32)
    b[2usize] = u8((v >> 8u32) & 255u32)
    b[3usize] = u8(v & 255u32)
    ret b
}

// Our opening bytes: SETTINGS (push off, the receive window we will use, the largest frame we accept) and a
// WINDOW_UPDATE raising the connection window to the same size.
fn server_start(s: *Server, dst: []u8) -> (usize, err) {
    var at = 0usize
    var settings: [3]h2.Setting = zero
    settings[0usize] = h2.Setting { id: 2u16, value: 0u32 }
    settings[1usize] = h2.Setting { id: 4u16, value: u32(s.initial_recv) }
    settings[2usize] = h2.Setting { id: 5u16, value: u32(s.max_frame) }
    var payload: [18]u8 = zero
    let (n, settings_error) = h2.settings_encode(payload[0usize..], settings[0usize..])
    if settings_error != ok { ret (0usize, settings_error) }
    var e = put_frame(dst, &at, h2.SETTINGS, 0u8, 0u32, payload[0usize..n])
    if e != ok { ret (0usize, e) }
    if s.initial_recv > 65535i64 {
        let delta = u32_bytes(u32(s.initial_recv - 65535i64))
        e = put_frame(dst, &at, h2.WINDOW_UPDATE, 0u8, 0u32, delta[0usize..4usize])
        if e != ok { ret (0usize, e) }
        s.recv_window = s.initial_recv
    }
    s.started = true
    ret (at, ok)
}

fn find_call(s: *Server, id: u32) -> usize {
    var i = 0usize
    while i < s.calls.len {
        if s.calls[i].used && s.calls[i].id == id { ret i }
        i += 1usize
    }
    ret s.calls.len
}

// Whether a request header list is a gRPC call: POST with a `content-type` of `application/grpc` (and a suffix such as
// `+proto`), and a path.
fn request_is_grpc(headers: []const h2.Header) -> bool {
    let (method, has_method) = grpc.find_header(headers, ":method")
    let (path, has_path) = grpc.find_header(headers, ":path")
    let (ct, has_ct) = grpc.find_header(headers, "content-type")
    if !has_method || !has_path || !has_ct { ret false }
    if !str.eq(method, "POST") { ret false }
    if !str.starts_with(ct, "application/grpc") { ret false }
    if ct.len > 16usize && ct[16usize] != 43u8 && ct[16usize] != 59u8 { ret false }
    ret true
}

// Deliver the complete messages buffered on every call, and the half-close once nothing is left to read. Events that do
// not fit stay buffered for the next call.
fn drain(s: *Server, events: []Event, count: *usize, hdr: []h2.Header) {
    var i = 0usize
    while i < s.calls.len {
        let c = &s.calls[i]
        if c.used {
            while *count < events.len {
                let (m, m_used, m_error) = grpc.message_decode(c.buf[c.consumed..c.buf_len], c.buf.len)
                if m_error != ok { break }
                events[*count] = Event { kind: EVENT_MESSAGE, stream: c.id, code: 0u32, compressed: m.compressed, nanos: 0u64, text: "", payload: m.payload, headers: hdr[0usize..0usize] }
                *count += 1usize
                c.consumed += m_used
            }
            if c.remote_closed && !c.half_close_sent && c.consumed == c.buf_len && *count < events.len {
                events[*count] = Event { kind: EVENT_HALF_CLOSE, stream: c.id, code: 0u32, compressed: false, nanos: 0u64, text: "", payload: "", headers: hdr[0usize..0usize] }
                *count += 1usize
                c.half_close_sent = true
            }
        }
        i += 1usize
    }
}

fn release_if_done(s: *Server, at_call: usize) {
    let c = &s.calls[at_call]
    if c.local_closed && c.remote_closed && c.half_close_sent { c.used = false }
}

// Process the bytes of the connection: whole frames are consumed (the count is returned; the caller keeps the rest and
// calls again with more), SETTINGS and PING are answered into `dst`, and events are written to `events`. `hdr` and `scratch`
// hold the decoded header lists and strings the events point into (valid until the next call). Stops early, consuming only
// what it handled, when `events` is full; a call with no input delivers what an earlier one left buffered.
fn server_receive(s: *Server, input: []const u8, dst: []u8, events: []Event, hdr: []h2.Header, scratch: []u8) -> (usize, usize, usize, err) {
    var at = 0usize
    var out = 0usize
    var count = 0usize
    var hdr_used = 0usize
    var scratch_used = 0usize
    // Compact each call's reassembly buffer: the messages handed out last time are gone.
    var i = 0usize
    while i < s.calls.len {
        let c = &s.calls[i]
        if c.used && c.consumed > 0usize {
            var k = 0usize
            while k + c.consumed < c.buf_len {
                c.buf[k] = c.buf[k + c.consumed]
                k += 1usize
            }
            c.buf_len -= c.consumed
            c.consumed = 0usize
        }
        i += 1usize
    }
    drain(s, events, &count, hdr)
    if !s.got_preface {
        let preface = h2.preface()
        if input.len < preface.len { ret (0usize, out, count, ok) }
        if !str.eq(input[0usize..preface.len], preface) { ret (0usize, out, count, grpc.Protocol) }
        at = preface.len
        s.got_preface = true
    }
    while at < input.len && count + 4usize <= events.len {
        let (f, used, frame_error) = h2.frame_decode(input[at..], s.max_frame)
        if frame_error == h2.Incomplete { break }
        if frame_error != ok { ret (at, out, count, grpc.Protocol) }
        at += used
        if s.block_active && f.kind != h2.CONTINUATION { ret (at, out, count, grpc.Protocol) }
        if !s.got_settings && f.kind != h2.SETTINGS { ret (at, out, count, grpc.Protocol) }
        if f.kind == h2.SETTINGS {
            if (f.flags & h2.FLAG_ACK) != 0u8 { continue }
            var settings: [16]h2.Setting = zero
            let (n, settings_error) = h2.settings_decode(f.payload, settings[0usize..])
            if settings_error != ok { ret (at, out, count, grpc.Protocol) }
            var k = 0usize
            while k < n {
                let id = settings[k].id
                let value = settings[k].value
                if id == 1u16 {
                    h2.table_announce(&s.enc, usize(value))
                } else if id == 4u16 {
                    if value > 2147483647u32 { ret (at, out, count, grpc.Protocol) }
                    let delta = i64(value) - s.peer_initial_window
                    s.peer_initial_window = i64(value)
                    var j = 0usize
                    while j < s.calls.len {
                        if s.calls[j].used { s.calls[j].send_window += delta }
                        j += 1usize
                    }
                } else if id == 5u16 {
                    if value < 16384u32 || value > 16777215u32 { ret (at, out, count, grpc.Protocol) }
                    s.peer_max_frame = usize(value)
                }
                k += 1usize
            }
            s.got_settings = true
            let e = put_frame(dst, &out, h2.SETTINGS, h2.FLAG_ACK, 0u32, "")
            if e != ok { ret (at, out, count, grpc.TooSmall) }
        } else if f.kind == h2.PING {
            if (f.flags & h2.FLAG_ACK) == 0u8 {
                if f.payload.len != 8usize { ret (at, out, count, grpc.Protocol) }
                let e = put_frame(dst, &out, h2.PING, h2.FLAG_ACK, 0u32, f.payload)
                if e != ok { ret (at, out, count, grpc.TooSmall) }
            }
        } else if f.kind == h2.WINDOW_UPDATE {
            if f.payload.len != 4usize { ret (at, out, count, grpc.Protocol) }
            let inc = i64(h2.be32(f.payload, 0usize) & 2147483647u32)
            if inc == 0i64 { ret (at, out, count, grpc.Protocol) }
            if f.stream == 0u32 {
                s.send_window += inc
            } else {
                let j = find_call(s, f.stream)
                if j < s.calls.len { s.calls[j].send_window += inc }
            }
        } else if f.kind == h2.RST_STREAM {
            if f.payload.len != 4usize { ret (at, out, count, grpc.Protocol) }
            let j = find_call(s, f.stream)
            if j < s.calls.len {
                events[count] = Event { kind: EVENT_RESET, stream: f.stream, code: h2.be32(f.payload, 0usize), compressed: false, nanos: 0u64, text: "", payload: "", headers: hdr[0usize..0usize] }
                count += 1usize
                s.calls[j].used = false
            }
        } else if f.kind == h2.GOAWAY {
            if f.payload.len < 8usize { ret (at, out, count, grpc.Protocol) }
            s.goaway = true
            events[count] = Event { kind: EVENT_GOAWAY, stream: h2.be32(f.payload, 0usize) & 2147483647u32, code: h2.be32(f.payload, 4usize), compressed: false, nanos: 0u64, text: "", payload: "", headers: hdr[0usize..0usize] }
            count += 1usize
        } else if f.kind == h2.HEADERS || f.kind == h2.CONTINUATION {
            var fragment = f.payload
            if f.kind == h2.HEADERS {
                if f.stream == 0u32 || (f.stream & 1u32) == 0u32 { ret (at, out, count, grpc.Protocol) }
                let (frag, frag_error) = h2.headers_fragment(f)
                if frag_error != ok { ret (at, out, count, grpc.Protocol) }
                fragment = frag
                s.block_len = 0usize
                s.block_stream = f.stream
                s.block_end_stream = (f.flags & h2.FLAG_END_STREAM) != 0u8
                s.block_active = true
            } else if !s.block_active || f.stream != s.block_stream {
                ret (at, out, count, grpc.Protocol)
            }
            if s.block_len + fragment.len > s.block.len { ret (at, out, count, grpc.TooLarge) }
            mem.copy[u8](s.block[s.block_len..s.block_len + fragment.len], fragment)
            s.block_len += fragment.len
            if (f.flags & h2.FLAG_END_HEADERS) != 0u8 {
                s.block_active = false
                var decoded: [48]h2.Header = zero
                let (n, decode_error) = h2.decode_block(&s.dec, s.block[0usize..s.block_len], decoded[0usize..], scratch[scratch_used..])
                if decode_error != ok { ret (at, out, count, grpc.Protocol) }
                var needed = 0usize
                var d = 0usize
                while d < n {
                    needed += decoded[d].name.len + decoded[d].value.len
                    d += 1usize
                }
                if hdr_used + n > hdr.len { ret (at, out, count, grpc.TooSmall) }
                var d2 = 0usize
                while d2 < n {
                    hdr[hdr_used + d2] = decoded[d2]
                    d2 += 1usize
                }
                let list = hdr[hdr_used..hdr_used + n]
                hdr_used += n
                scratch_used += needed
                var j = find_call(s, s.block_stream)
                if j == s.calls.len {
                    // A new call: a free slot, and a stream id above every one seen.
                    if s.block_stream <= s.last_stream { ret (at, out, count, grpc.Protocol) }
                    var slot = s.calls.len
                    var q = 0usize
                    while q < s.calls.len {
                        if !s.calls[q].used {
                            slot = q
                            break
                        }
                        q += 1usize
                    }
                    if slot == s.calls.len { ret (at, out, count, grpc.TooSmall) }
                    s.calls[slot] = Call { id: s.block_stream, used: true, remote_closed: false, half_close_sent: false, local_headers: false, local_closed: false, send_window: s.peer_initial_window, recv_window: s.initial_recv, buf: s.calls[slot].buf, buf_len: 0usize, consumed: 0usize }
                    s.last_stream = s.block_stream
                    j = slot
                    let (path, has_path) = grpc.find_header(list, ":path")
                    var nanos = 0u64
                    var bad_timeout = 0u32
                    let (timeout, has_timeout) = grpc.find_header(list, "grpc-timeout")
                    if has_timeout {
                        let (value, timeout_error) = grpc.timeout_parse(timeout)
                        if timeout_error == ok { nanos = value } else { bad_timeout = 1u32 }
                    }
                    events[count] = Event { kind: EVENT_REQUEST, stream: s.block_stream, code: bad_timeout, compressed: false, nanos: nanos, text: path, payload: "", headers: list }
                    count += 1usize
                }
                if s.block_end_stream { s.calls[j].remote_closed = true }
            }
        } else if f.kind == h2.DATA {
            if f.stream == 0u32 { ret (at, out, count, grpc.Protocol) }
            let (body, body_error) = h2.unpad(f)
            if body_error != ok { ret (at, out, count, grpc.Protocol) }
            s.recv_window -= i64(f.payload.len)
            if s.recv_window < 0i64 { ret (at, out, count, grpc.Protocol) }
            let j = find_call(s, f.stream)
            if j < s.calls.len {
                let c = &s.calls[j]
                c.recv_window -= i64(f.payload.len)
                if c.recv_window < 0i64 { ret (at, out, count, grpc.Protocol) }
                if c.buf_len + body.len > c.buf.len { ret (at, out, count, grpc.TooLarge) }
                mem.copy[u8](c.buf[c.buf_len..c.buf_len + body.len], body)
                c.buf_len += body.len
                if (f.flags & h2.FLAG_END_STREAM) != 0u8 { c.remote_closed = true }
                // Hand the window back when half of it is used.
                if c.recv_window < s.initial_recv / 2i64 && (f.flags & h2.FLAG_END_STREAM) == 0u8 {
                    let delta = u32_bytes(u32(s.initial_recv - c.recv_window))
                    let e = put_frame(dst, &out, h2.WINDOW_UPDATE, 0u8, f.stream, delta[0usize..4usize])
                    if e != ok { ret (at, out, count, grpc.TooSmall) }
                    c.recv_window = s.initial_recv
                }
            }
            if s.recv_window < s.initial_recv / 2i64 {
                let delta = u32_bytes(u32(s.initial_recv - s.recv_window))
                let e = put_frame(dst, &out, h2.WINDOW_UPDATE, 0u8, 0u32, delta[0usize..4usize])
                if e != ok { ret (at, out, count, grpc.TooSmall) }
                s.recv_window = s.initial_recv
            }
        }
        drain(s, events, &count, hdr)
    }
    // A call that has nothing more to say either way is free again.
    var r = 0usize
    while r < s.calls.len {
        if s.calls[r].used { release_if_done(s, r) }
        r += 1usize
    }
    ret (at, out, count, ok)
}

// --- responses ---------------------------------------------------------------------------------------------------

fn response_block(s: *Server, dst: []u8, id: u32, headers: []const h2.Header, end_stream: bool) -> (usize, err) {
    let sensitive: [1]str = zero
    var block: [2048]u8 = zero
    let (block_len, encode_error) = h2.encode_block(&s.enc, block[0usize..], headers, sensitive[0usize..0usize], true)
    if encode_error != ok { ret (0usize, encode_error) }
    var at = 0usize
    var flags = h2.FLAG_END_HEADERS
    if end_stream { flags = flags | h2.FLAG_END_STREAM }
    let e = put_frame(dst, &at, h2.HEADERS, flags, id, block[0usize..block_len])
    if e != ok { ret (0usize, e) }
    ret (at, ok)
}

// The response's initial metadata: `:status 200`, `content-type: application/grpc`, then the caller's.
fn response_headers(s: *Server, dst: []u8, id: u32, metadata: []const h2.Header) -> (usize, err) {
    let j = find_call(s, id)
    if j == s.calls.len { ret (0usize, grpc.NoStream) }
    if s.calls[j].local_headers || s.calls[j].local_closed { ret (0usize, grpc.Protocol) }
    var headers: [24]h2.Header = zero
    var n = 0usize
    headers[n] = h2.Header { name: ":status", value: "200" }
    n += 1usize
    headers[n] = h2.Header { name: "content-type", value: "application/grpc" }
    n += 1usize
    var m = 0usize
    while m < metadata.len && n < headers.len {
        headers[n] = metadata[m]
        n += 1usize
        m += 1usize
    }
    let (len, e) = response_block(s, dst, id, headers[0usize..n], false)
    if e != ok { ret (0usize, e) }
    s.calls[j].local_headers = true
    ret (len, ok)
}

// Send one message as DATA frames (split at the peer's maximum frame size). The headers go first if the caller has not sent
// them. `Blocked` when the message does not fit the flow-control windows yet; send it after a WINDOW_UPDATE.
fn response_message(s: *Server, dst: []u8, id: u32, payload: []const u8, compressed: bool) -> (usize, err) {
    let j = find_call(s, id)
    if j == s.calls.len { ret (0usize, grpc.NoStream) }
    var at = 0usize
    if !s.calls[j].local_headers {
        let none: []const h2.Header = zero
        let (n, e) = response_headers(s, dst, id, none)
        if e != ok { ret (0usize, e) }
        at = n
    }
    let c = &s.calls[j]
    if c.local_closed { ret (0usize, grpc.Protocol) }
    let total = 5usize + payload.len
    if i64(total) > c.send_window || i64(total) > s.send_window { ret (0usize, grpc.Blocked) }
    var framed: [5]u8 = zero
    framed[0usize] = 0u8
    if compressed { framed[0usize] = 1u8 }
    let size = u32(payload.len)
    framed[1usize] = u8((size >> 24u32) & 255u32)
    framed[2usize] = u8((size >> 16u32) & 255u32)
    framed[3usize] = u8((size >> 8u32) & 255u32)
    framed[4usize] = u8(size & 255u32)
    var sent = 0usize
    while sent < total {
        var n = total - sent
        if n > s.peer_max_frame { n = s.peer_max_frame }
        var chunk: [16384]u8 = zero
        if n > chunk.len { ret (0usize, grpc.TooSmall) }
        var k = 0usize
        while k < n {
            let at_byte = sent + k
            if at_byte < 5usize {
                chunk[k] = framed[at_byte]
            } else {
                chunk[k] = payload[at_byte - 5usize]
            }
            k += 1usize
        }
        let e = put_frame(dst, &at, h2.DATA, 0u8, id, chunk[0usize..n])
        if e != ok { ret (0usize, e) }
        sent += n
    }
    c.send_window -= i64(total)
    s.send_window -= i64(total)
    ret (at, ok)
}

// The flow-controlled primitive under `response_message`: send as much of `data` (message bytes already framed with
// `grpc.message_encode`) as the windows allow, as DATA frames at the peer's maximum frame size, and answer how many bytes
// it took and how many it wrote. Zero taken is a closed window, not an error: keep the rest and call again after the
// peer's WINDOW_UPDATE. The headers go first if the caller has not sent them.
fn response_write(s: *Server, dst: []u8, id: u32, data: []const u8) -> (usize, usize, err) {
    let j = find_call(s, id)
    if j == s.calls.len { ret (0usize, 0usize, grpc.NoStream) }
    var at = 0usize
    if !s.calls[j].local_headers {
        let none: []const h2.Header = zero
        let (n, e) = response_headers(s, dst, id, none)
        if e != ok { ret (0usize, 0usize, e) }
        at = n
    }
    let c = &s.calls[j]
    if c.local_closed { ret (0usize, 0usize, grpc.Protocol) }
    var allowed = c.send_window
    if s.send_window < allowed { allowed = s.send_window }
    if allowed < 0i64 { allowed = 0i64 }
    var take = data.len
    if i64(take) > allowed { take = usize(allowed) }
    var sent = 0usize
    while sent < take {
        var n = take - sent
        if n > s.peer_max_frame { n = s.peer_max_frame }
        let e = put_frame(dst, &at, h2.DATA, 0u8, id, data[sent..sent + n])
        if e != ok { ret (sent, at, e) }
        sent += n
    }
    c.send_window -= i64(take)
    s.send_window -= i64(take)
    ret (take, at, ok)
}

// Finish a call with its status: trailers (`grpc-status`, the percent-encoded `grpc-message`, the caller's metadata) with
// END_STREAM, or a trailers-only response when no headers went out.
fn response_finish(s: *Server, dst: []u8, id: u32, status: u32, message: str, metadata: []const h2.Header) -> (usize, err) {
    let j = find_call(s, id)
    if j == s.calls.len { ret (0usize, grpc.NoStream) }
    if s.calls[j].local_closed { ret (0usize, grpc.Protocol) }
    var headers: [28]h2.Header = zero
    var n = 0usize
    if !s.calls[j].local_headers {
        headers[n] = h2.Header { name: ":status", value: "200" }
        n += 1usize
        headers[n] = h2.Header { name: "content-type", value: "application/grpc" }
        n += 1usize
    }
    var status_text: [12]u8 = zero
    var sat = 0usize
    var digits: [10]u8 = zero
    var dn = 0usize
    var v = status
    if v == 0u32 {
        digits[0usize] = 48u8
        dn = 1usize
    }
    while v > 0u32 {
        digits[dn] = 48u8 + u8(v % 10u32)
        v = v / 10u32
        dn += 1usize
    }
    var di = 0usize
    while di < dn {
        status_text[sat] = digits[dn - 1usize - di]
        sat += 1usize
        di += 1usize
    }
    let status_value: str = status_text[0usize..sat]
    headers[n] = h2.Header { name: "grpc-status", value: status_value }
    n += 1usize
    var encoded: [512]u8 = zero
    if message.len > 0usize {
        let (len, encode_error) = grpc.message_percent_encode(encoded[0usize..], message)
        if encode_error != ok { ret (0usize, encode_error) }
        let value: str = encoded[0usize..len]
        headers[n] = h2.Header { name: "grpc-message", value: value }
        n += 1usize
    }
    var m = 0usize
    while m < metadata.len && n < headers.len {
        headers[n] = metadata[m]
        n += 1usize
        m += 1usize
    }
    let (len, e) = response_block(s, dst, id, headers[0usize..n], true)
    if e != ok { ret (0usize, e) }
    s.calls[j].local_headers = true
    s.calls[j].local_closed = true
    release_if_done(s, j)
    ret (len, ok)
}

// The deadline passed: `DEADLINE_EXCEEDED` with the usual text.
fn response_deadline_exceeded(s: *Server, dst: []u8, id: u32) -> (usize, err) {
    let none: []const h2.Header = zero
    let (n, e) = response_finish(s, dst, id, grpc.DEADLINE_EXCEEDED, "Deadline Exceeded", none)
    ret (n, e)
}

// Abort a call: RST_STREAM with `code` (8 is CANCEL, 0 NO_ERROR after a response that ended early).
fn response_reset(s: *Server, dst: []u8, id: u32, code: u32) -> (usize, err) {
    let j = find_call(s, id)
    if j == s.calls.len { ret (0usize, grpc.NoStream) }
    var at = 0usize
    let bytes = u32_bytes(code)
    let e = put_frame(dst, &at, h2.RST_STREAM, 0u8, id, bytes[0usize..4usize])
    if e != ok { ret (0usize, e) }
    s.calls[j].used = false
    ret (at, ok)
}
