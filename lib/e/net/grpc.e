// gRPC over HTTP/2 (L101), client side, over caller buffers and `e.net.http2`: no sockets, the caller moves bytes.
// The protocol pieces are plain functions (length-prefixed messages, `grpc-timeout`, status codes and the HTTP to
// gRPC status mapping, `grpc-message` percent-encoding, `-bin` metadata, the request header list); `Conn` is the
// client connection state machine: the preface and SETTINGS, stream ids, HPACK both ways, flow control in both
// directions, and `conn_receive`, which turns incoming bytes into events (initial metadata, whole messages across
// DATA frame boundaries, trailers with the status, resets, GOAWAY) while answering SETTINGS and PING itself.
// Unary and streaming calls are the same state machine: a call is a stream, and messages are sent and received on it
// until half-close and trailers. Message compression is reported (the flag, the payload as sent), never undone.
//
// Memory: stream slots, reassembly buffers, the header block buffer and both HPACK tables are the caller's.
use e.bytes
use e.mem
use e.net.http2 as h2
use e.str

error Incomplete
error Invalid
error TooLarge
error TooSmall
error Blocked
error Protocol
error NoStream

const OK: u32 = 0u32
const CANCELLED: u32 = 1u32
const UNKNOWN: u32 = 2u32
const INVALID_ARGUMENT: u32 = 3u32
const DEADLINE_EXCEEDED: u32 = 4u32
const NOT_FOUND: u32 = 5u32
const ALREADY_EXISTS: u32 = 6u32
const PERMISSION_DENIED: u32 = 7u32
const RESOURCE_EXHAUSTED: u32 = 8u32
const FAILED_PRECONDITION: u32 = 9u32
const ABORTED: u32 = 10u32
const OUT_OF_RANGE: u32 = 11u32
const UNIMPLEMENTED: u32 = 12u32
const INTERNAL: u32 = 13u32
const UNAVAILABLE: u32 = 14u32
const DATA_LOSS: u32 = 15u32
const UNAUTHENTICATED: u32 = 16u32

const EVENT_HEADERS: u8 = 1u8
const EVENT_MESSAGE: u8 = 2u8
const EVENT_TRAILERS: u8 = 3u8
const EVENT_RESET: u8 = 4u8
const EVENT_GOAWAY: u8 = 5u8

type Message = struct { compressed: bool, payload: []const u8 }
type Stream = struct { id: u32, used: bool, got_headers: bool, remote_closed: bool, local_closed: bool, send_window: i64, recv_window: i64, buf: []u8, buf_len: usize, consumed: usize }
type Event = struct { kind: u8, stream: u32, code: u32, compressed: bool, text: str, payload: []const u8, headers: []const h2.Header }
type Conn = struct { streams: []Stream, next_id: u32, enc: h2.Table, dec: h2.Table, send_window: i64, recv_window: i64, peer_initial_window: i64, peer_max_frame: usize, initial_recv: i64, max_frame: usize, started: bool, got_settings: bool, goaway: bool, last_stream: u32, block: []u8, block_len: usize, block_stream: u32, block_end_stream: bool, block_active: bool }

// --- status and messages -----------------------------------------------------------------------------------------

fn status_name(code: u32) -> str {
    if code == 0u32 { ret "OK" }
    if code == 1u32 { ret "CANCELLED" }
    if code == 2u32 { ret "UNKNOWN" }
    if code == 3u32 { ret "INVALID_ARGUMENT" }
    if code == 4u32 { ret "DEADLINE_EXCEEDED" }
    if code == 5u32 { ret "NOT_FOUND" }
    if code == 6u32 { ret "ALREADY_EXISTS" }
    if code == 7u32 { ret "PERMISSION_DENIED" }
    if code == 8u32 { ret "RESOURCE_EXHAUSTED" }
    if code == 9u32 { ret "FAILED_PRECONDITION" }
    if code == 10u32 { ret "ABORTED" }
    if code == 11u32 { ret "OUT_OF_RANGE" }
    if code == 12u32 { ret "UNIMPLEMENTED" }
    if code == 13u32 { ret "INTERNAL" }
    if code == 14u32 { ret "UNAVAILABLE" }
    if code == 15u32 { ret "DATA_LOSS" }
    if code == 16u32 { ret "UNAUTHENTICATED" }
    ret "UNKNOWN"
}

// The gRPC status for an HTTP status that carried no `grpc-status` (the transport-level mapping).
fn http_to_grpc(status: u32) -> u32 {
    if status == 400u32 { ret INTERNAL }
    if status == 401u32 { ret UNAUTHENTICATED }
    if status == 403u32 { ret PERMISSION_DENIED }
    if status == 404u32 { ret UNIMPLEMENTED }
    if status == 429u32 || status == 502u32 || status == 503u32 || status == 504u32 { ret UNAVAILABLE }
    ret UNKNOWN
}

// A message: compressed flag, 4-byte big-endian length, payload.
fn message_encode(dst: []u8, payload: []const u8, compressed: bool) -> (usize, err) {
    if dst.len < 5usize + payload.len { ret (0usize, TooSmall) }
    if payload.len > 4294967295usize { ret (0usize, TooLarge) }
    dst[0usize] = 0u8
    if compressed { dst[0usize] = 1u8 }
    let n = u32(payload.len)
    dst[1usize] = u8((n >> 24u32) & 255u32)
    dst[2usize] = u8((n >> 16u32) & 255u32)
    dst[3usize] = u8((n >> 8u32) & 255u32)
    dst[4usize] = u8(n & 255u32)
    mem.copy[u8](dst[5usize..5usize + payload.len], payload)
    ret (5usize + payload.len, ok)
}

// One message at the front of `buf` and the bytes it used; `Incomplete` until it is all there.
fn message_decode(buf: []const u8, max_size: usize) -> (Message, usize, err) {
    var m: Message = zero
    if buf.len < 5usize { ret (m, 0usize, Incomplete) }
    if buf[0usize] > 1u8 { ret (m, 0usize, Invalid) }
    let n = (usize(buf[1usize]) << 24usize) | (usize(buf[2usize]) << 16usize) | (usize(buf[3usize]) << 8usize) | usize(buf[4usize])
    if n > max_size { ret (m, 0usize, TooLarge) }
    if buf.len < 5usize + n { ret (m, 0usize, Incomplete) }
    m.compressed = buf[0usize] == 1u8
    m.payload = buf[5usize..5usize + n]
    ret (m, 5usize + n, ok)
}

// --- timeouts ----------------------------------------------------------------------------------------------------

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

fn ceil_div(value: u64, unit: u64) -> u64 {
    var q = value / unit
    if value % unit > 0u64 { q += 1u64 }
    ret q
}

// `grpc-timeout` for a duration in nanoseconds: at most 8 digits and a unit (n u m S M H), the finest unit that fits,
// rounding up (grpc-go's `encodeTimeout`; zero or less is `0n`).
fn timeout_encode(dst: []u8, nanos: u64) -> (usize, err) {
    var at = 0usize
    var units: [6]u64 = zero
    units[0usize] = 1u64
    units[1usize] = 1000u64
    units[2usize] = 1000000u64
    units[3usize] = 1000000000u64
    units[4usize] = 60000000000u64
    units[5usize] = 3600000000000u64
    let letters = "numSMH"
    var i = 0usize
    while i < 6usize {
        let q = ceil_div(nanos, units[i])
        if q <= 99999999u64 || i == 5usize {
            let e = put_decimal(dst, &at, q)
            if e != ok { ret (0usize, e) }
            if at >= dst.len { ret (0usize, TooSmall) }
            dst[at] = letters[i]
            at += 1usize
            ret (at, ok)
        }
        i += 1usize
    }
    ret (0usize, Invalid)
}

// A `grpc-timeout` value in nanoseconds: 1 to 8 digits and one of H M S m u n.
fn timeout_parse(text: str) -> (u64, err) {
    if text.len < 2usize || text.len > 9usize { ret (0u64, Invalid) }
    var v = 0u64
    var i = 0usize
    while i < text.len - 1usize {
        if text[i] < 48u8 || text[i] > 57u8 { ret (0u64, Invalid) }
        v = v * 10u64 + u64(text[i] - 48u8)
        i += 1usize
    }
    let unit = text[text.len - 1usize]
    if unit == 110u8 { ret (v, ok) }
    if unit == 117u8 { ret (v * 1000u64, ok) }
    if unit == 109u8 { ret (v * 1000000u64, ok) }
    if unit == 83u8 { ret (v * 1000000000u64, ok) }
    if unit == 77u8 { ret (v * 60000000000u64, ok) }
    if unit == 72u8 { ret (v * 3600000000000u64, ok) }
    ret (0u64, Invalid)
}

// --- grpc-message and metadata -----------------------------------------------------------------------------------

fn hex_upper(v: u8) -> u8 {
    if v < 10u8 { ret 48u8 + v }
    ret 55u8 + v
}

fn hex_value(c: u8) -> (u8, bool) {
    if c >= 48u8 && c <= 57u8 { ret (c - 48u8, true) }
    if c >= 65u8 && c <= 70u8 { ret (c - 55u8, true) }
    if c >= 97u8 && c <= 102u8 { ret (c - 87u8, true) }
    ret (0u8, false)
}

// Percent-encode a status message: bytes outside printable ASCII (0x20 to 0x7E) and `%` become `%XX`.
fn message_percent_encode(dst: []u8, text: str) -> (usize, err) {
    var at = 0usize
    var i = 0usize
    while i < text.len {
        let c = text[i]
        if c >= 32u8 && c <= 126u8 && c != 37u8 {
            if at >= dst.len { ret (0usize, TooSmall) }
            dst[at] = c
            at += 1usize
        } else {
            if at + 3usize > dst.len { ret (0usize, TooSmall) }
            dst[at] = 37u8
            dst[at + 1usize] = hex_upper(c >> 4u8)
            dst[at + 2usize] = hex_upper(c & 15u8)
            at += 3usize
        }
        i += 1usize
    }
    ret (at, ok)
}

// The reverse; a `%` not followed by two hex digits stays as it is (the specification asks receivers to be lenient).
fn message_percent_decode(dst: []u8, text: str) -> (usize, err) {
    var at = 0usize
    var i = 0usize
    while i < text.len {
        var c = text[i]
        if c == 37u8 && i + 2usize < text.len {
            let (hi, hi_ok) = hex_value(text[i + 1usize])
            let (lo, lo_ok) = hex_value(text[i + 2usize])
            if hi_ok && lo_ok {
                c = (hi << 4u8) | lo
                i += 2usize
            }
        }
        if at >= dst.len { ret (0usize, TooSmall) }
        dst[at] = c
        at += 1usize
        i += 1usize
    }
    ret (at, ok)
}

fn ends_with_bin(name: str) -> bool {
    if name.len < 4usize { ret false }
    ret str.eq(name[name.len - 4usize..], "-bin")
}

// A binary metadata value as sent: base64 without padding.
fn binary_value_encode(dst: []u8, value: []const u8) -> (usize, err) {
    let (text, e) = bytes.base64_encode(dst, value, .Standard, false)
    if e != ok { ret (0usize, TooSmall) }
    ret (text.len, ok)
}

// A binary metadata value as received: base64 with or without padding, or the raw form gRPC C-core writes (one
// zero byte, which no base64 text starts with, and then the value itself; seen in grpcio transcripts).
fn binary_value_decode(dst: []u8, text: str) -> (usize, err) {
    if text.len > 0usize && text[0usize] == 0u8 {
        if text.len - 1usize > dst.len { ret (0usize, Invalid) }
        mem.copy[u8](dst[0usize..text.len - 1usize], text[1usize..])
        ret (text.len - 1usize, ok)
    }
    let (out, e) = bytes.base64_decode(dst, text, .Standard)
    if e != ok { ret (0usize, Invalid) }
    ret (out.len, ok)
}

// --- the connection ----------------------------------------------------------------------------------------------

fn conn_new(streams: []Stream, enc: h2.Table, dec: h2.Table, block: []u8, initial_recv: u32, max_frame: u32) -> Conn {
    var i = 0usize
    while i < streams.len {
        streams[i].used = false
        i += 1usize
    }
    ret Conn { streams: streams, next_id: 1u32, enc: enc, dec: dec, send_window: 65535i64, recv_window: 65535i64, peer_initial_window: 65535i64, peer_max_frame: 16384usize, initial_recv: i64(initial_recv), max_frame: usize(max_frame), started: false, got_settings: false, goaway: false, last_stream: 0u32, block: block, block_len: 0usize, block_stream: 0u32, block_end_stream: false, block_active: false }
}

fn put_frame(dst: []u8, at: *usize, kind: u8, flags: u8, stream: u32, payload: []const u8) -> err {
    let (n, e) = h2.frame_encode(dst[*at..], kind, flags, stream, payload)
    if e != ok { ret TooSmall }
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

// The client's opening bytes: the connection preface, SETTINGS (push off, the receive window we will use) and a
// WINDOW_UPDATE that raises the connection window to the same size.
fn conn_start(c: *Conn, dst: []u8) -> (usize, err) {
    var at = 0usize
    let preface = h2.preface()
    if dst.len < preface.len { ret (0usize, TooSmall) }
    mem.copy[u8](dst[0usize..preface.len], preface)
    at = preface.len
    var settings: [3]h2.Setting = zero
    settings[0usize] = h2.Setting { id: 2u16, value: 0u32 }
    settings[1usize] = h2.Setting { id: 4u16, value: u32(c.initial_recv) }
    settings[2usize] = h2.Setting { id: 5u16, value: u32(c.max_frame) }
    var payload: [18]u8 = zero
    let (n, settings_error) = h2.settings_encode(payload[0usize..], settings[0usize..])
    if settings_error != ok { ret (0usize, settings_error) }
    var e = put_frame(dst, &at, h2.SETTINGS, 0u8, 0u32, payload[0usize..n])
    if e != ok { ret (0usize, e) }
    if c.initial_recv > 65535i64 {
        let delta = u32_bytes(u32(c.initial_recv - 65535i64))
        e = put_frame(dst, &at, h2.WINDOW_UPDATE, 0u8, 0u32, delta[0usize..4usize])
        if e != ok { ret (0usize, e) }
        c.recv_window = c.initial_recv
    }
    c.started = true
    ret (at, ok)
}

fn find_stream(c: *Conn, id: u32) -> usize {
    var i = 0usize
    while i < c.streams.len {
        if c.streams[i].used && c.streams[i].id == id { ret i }
        i += 1usize
    }
    ret c.streams.len
}

// Open a call: a HEADERS frame (END_HEADERS) with the request header list, `timeout_nanos` of zero meaning none.
// `buf` is the stream's reassembly buffer for incoming messages. Answers the stream id and the bytes written.
fn call_start(c: *Conn, dst: []u8, authority: str, path: str, timeout_nanos: u64, metadata: []const h2.Header, buf: []u8) -> (u32, usize, err) {
    if c.goaway { ret (0u32, 0usize, Protocol) }
    var slot = c.streams.len
    var i = 0usize
    while i < c.streams.len {
        if !c.streams[i].used {
            slot = i
            break
        }
        i += 1usize
    }
    if slot == c.streams.len { ret (0u32, 0usize, TooSmall) }
    var headers: [24]h2.Header = zero
    var n = 0usize
    headers[n] = h2.Header { name: ":method", value: "POST" }
    n += 1usize
    headers[n] = h2.Header { name: ":scheme", value: "http" }
    n += 1usize
    headers[n] = h2.Header { name: ":path", value: path }
    n += 1usize
    headers[n] = h2.Header { name: ":authority", value: authority }
    n += 1usize
    headers[n] = h2.Header { name: "content-type", value: "application/grpc" }
    n += 1usize
    headers[n] = h2.Header { name: "user-agent", value: "grpc-neper/0.1" }
    n += 1usize
    headers[n] = h2.Header { name: "te", value: "trailers" }
    n += 1usize
    var timeout_text: [16]u8 = zero
    if timeout_nanos > 0u64 {
        let (len, timeout_error) = timeout_encode(timeout_text[0usize..], timeout_nanos)
        if timeout_error != ok { ret (0u32, 0usize, timeout_error) }
        let value: str = timeout_text[0usize..len]
        headers[n] = h2.Header { name: "grpc-timeout", value: value }
        n += 1usize
    }
    var m = 0usize
    while m < metadata.len && n < headers.len {
        headers[n] = metadata[m]
        n += 1usize
        m += 1usize
    }
    let sensitive: [1]str = zero
    var block: [2048]u8 = zero
    let (block_len, encode_error) = h2.encode_block(&c.enc, block[0usize..], headers[0usize..n], sensitive[0usize..0usize], true)
    if encode_error != ok { ret (0u32, 0usize, encode_error) }
    var at = 0usize
    let id = c.next_id
    let e = put_frame(dst, &at, h2.HEADERS, h2.FLAG_END_HEADERS, id, block[0usize..block_len])
    if e != ok { ret (0u32, 0usize, e) }
    c.next_id += 2u32
    c.streams[slot] = Stream { id: id, used: true, got_headers: false, remote_closed: false, local_closed: false, send_window: c.peer_initial_window, recv_window: c.initial_recv, buf: buf, buf_len: 0usize, consumed: 0usize }
    ret (id, at, ok)
}

// Send one message on a call as DATA frames (split at the peer's maximum frame size), `end_stream` half-closing the
// call. `Blocked` when the whole message does not fit the flow-control windows yet; send it after a WINDOW_UPDATE.
fn call_send(c: *Conn, dst: []u8, id: u32, payload: []const u8, compressed: bool, end_stream: bool) -> (usize, err) {
    let at_stream = find_stream(c, id)
    if at_stream == c.streams.len { ret (0usize, NoStream) }
    let s = &c.streams[at_stream]
    if s.local_closed { ret (0usize, Protocol) }
    let total = 5usize + payload.len
    if i64(total) > s.send_window || i64(total) > c.send_window { ret (0usize, Blocked) }
    var framed: [5]u8 = zero
    let (head, head_error) = message_encode(framed[0usize..], "", compressed)
    if head_error != ok { ret (0usize, head_error) }
    let size = u32(payload.len)
    framed[1usize] = u8((size >> 24u32) & 255u32)
    framed[2usize] = u8((size >> 16u32) & 255u32)
    framed[3usize] = u8((size >> 8u32) & 255u32)
    framed[4usize] = u8(size & 255u32)
    var at = 0usize
    var sent = 0usize
    while sent < total {
        var n = total - sent
        if n > c.peer_max_frame { n = c.peer_max_frame }
        // The chunk is bytes sent..sent+n of framed ++ payload.
        var chunk: [16384]u8 = zero
        if n > chunk.len { ret (0usize, TooSmall) }
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
        var flags = 0u8
        if end_stream && sent + n == total { flags = h2.FLAG_END_STREAM }
        let e = put_frame(dst, &at, h2.DATA, flags, id, chunk[0usize..n])
        if e != ok { ret (0usize, e) }
        sent += n
    }
    s.send_window -= i64(total)
    c.send_window -= i64(total)
    if end_stream { s.local_closed = true }
    ret (at, ok)
}

// Half-close a call without a message: an empty DATA frame with END_STREAM.
fn call_close_send(c: *Conn, dst: []u8, id: u32) -> (usize, err) {
    let at_stream = find_stream(c, id)
    if at_stream == c.streams.len { ret (0usize, NoStream) }
    var at = 0usize
    let e = put_frame(dst, &at, h2.DATA, h2.FLAG_END_STREAM, id, "")
    if e != ok { ret (0usize, e) }
    c.streams[at_stream].local_closed = true
    ret (at, ok)
}

// Cancel a call: RST_STREAM with CANCEL (8).
fn call_cancel(c: *Conn, dst: []u8, id: u32) -> (usize, err) {
    let at_stream = find_stream(c, id)
    if at_stream == c.streams.len { ret (0usize, NoStream) }
    var at = 0usize
    let code = u32_bytes(8u32)
    let e = put_frame(dst, &at, h2.RST_STREAM, 0u8, id, code[0usize..4usize])
    if e != ok { ret (0usize, e) }
    c.streams[at_stream].used = false
    ret (at, ok)
}

fn find_header(headers: []const h2.Header, name: str) -> (str, bool) {
    var i = 0usize
    while i < headers.len {
        if str.eq(headers[i].name, name) { ret (headers[i].value, true) }
        i += 1usize
    }
    ret ("", false)
}

fn parse_u32(text: str) -> (u32, bool) {
    if text.len == 0usize || text.len > 9usize { ret (0u32, false) }
    var v = 0u32
    var i = 0usize
    while i < text.len {
        if text[i] < 48u8 || text[i] > 57u8 { ret (0u32, false) }
        v = v * 10u32 + u32(text[i] - 48u8)
        i += 1usize
    }
    ret (v, true)
}

fn release(c: *Conn, at_stream: usize) {
    c.streams[at_stream].used = false
}

// Process the bytes of the connection: whole frames are consumed (the count is returned; the caller keeps the
// rest and calls again with more), SETTINGS and PING are answered into `dst`, and events are written to `events`.
// `hdr` and `scratch` hold the decoded header lists and strings the events point into (valid until the next call).
// Stops early, consuming only what it handled, when `events` is full.
fn conn_receive(c: *Conn, input: []const u8, dst: []u8, events: []Event, hdr: []h2.Header, scratch: []u8) -> (usize, usize, usize, err) {
    var at = 0usize
    var out = 0usize
    var count = 0usize
    var hdr_used = 0usize
    var scratch_used = 0usize
    // Compact each stream's reassembly buffer: the messages handed out last time are gone.
    var i = 0usize
    while i < c.streams.len {
        let s = &c.streams[i]
        if s.used && s.consumed > 0usize {
            var k = 0usize
            while k + s.consumed < s.buf_len {
                s.buf[k] = s.buf[k + s.consumed]
                k += 1usize
            }
            s.buf_len -= s.consumed
            s.consumed = 0usize
        }
        i += 1usize
    }
    while at < input.len && count + 4usize <= events.len {
        let (f, used, frame_error) = h2.frame_decode(input[at..], c.max_frame)
        if frame_error == h2.Incomplete { break }
        if frame_error != ok { ret (at, out, count, Protocol) }
        at += used
        if c.block_active && f.kind != h2.CONTINUATION { ret (at, out, count, Protocol) }
        if !c.got_settings && f.kind != h2.SETTINGS { ret (at, out, count, Protocol) }
        if f.kind == h2.SETTINGS {
            if (f.flags & h2.FLAG_ACK) != 0u8 { continue }
            var settings: [16]h2.Setting = zero
            let (n, settings_error) = h2.settings_decode(f.payload, settings[0usize..])
            if settings_error != ok { ret (at, out, count, Protocol) }
            var s = 0usize
            while s < n {
                let id = settings[s].id
                let value = settings[s].value
                if id == 1u16 {
                    h2.table_announce(&c.enc, usize(value))
                } else if id == 4u16 {
                    if value > 2147483647u32 { ret (at, out, count, Protocol) }
                    let delta = i64(value) - c.peer_initial_window
                    c.peer_initial_window = i64(value)
                    var j = 0usize
                    while j < c.streams.len {
                        if c.streams[j].used { c.streams[j].send_window += delta }
                        j += 1usize
                    }
                } else if id == 5u16 {
                    if value < 16384u32 || value > 16777215u32 { ret (at, out, count, Protocol) }
                    c.peer_max_frame = usize(value)
                }
                s += 1usize
            }
            c.got_settings = true
            let e = put_frame(dst, &out, h2.SETTINGS, h2.FLAG_ACK, 0u32, "")
            if e != ok { ret (at, out, count, TooSmall) }
        } else if f.kind == h2.PING {
            if (f.flags & h2.FLAG_ACK) == 0u8 {
                if f.payload.len != 8usize { ret (at, out, count, Protocol) }
                let e = put_frame(dst, &out, h2.PING, h2.FLAG_ACK, 0u32, f.payload)
                if e != ok { ret (at, out, count, TooSmall) }
            }
        } else if f.kind == h2.WINDOW_UPDATE {
            if f.payload.len != 4usize { ret (at, out, count, Protocol) }
            let inc = i64(h2.be32(f.payload, 0usize) & 2147483647u32)
            if inc == 0i64 { ret (at, out, count, Protocol) }
            if f.stream == 0u32 {
                c.send_window += inc
            } else {
                let j = find_stream(c, f.stream)
                if j < c.streams.len { c.streams[j].send_window += inc }
            }
        } else if f.kind == h2.RST_STREAM {
            if f.payload.len != 4usize { ret (at, out, count, Protocol) }
            let j = find_stream(c, f.stream)
            if j < c.streams.len {
                events[count] = Event { kind: EVENT_RESET, stream: f.stream, code: h2.be32(f.payload, 0usize), compressed: false, text: "", payload: "", headers: hdr[0usize..0usize] }
                count += 1usize
                release(c, j)
            }
        } else if f.kind == h2.GOAWAY {
            if f.payload.len < 8usize { ret (at, out, count, Protocol) }
            c.goaway = true
            c.last_stream = h2.be32(f.payload, 0usize) & 2147483647u32
            events[count] = Event { kind: EVENT_GOAWAY, stream: c.last_stream, code: h2.be32(f.payload, 4usize), compressed: false, text: f.payload[8usize..], payload: "", headers: hdr[0usize..0usize] }
            count += 1usize
        } else if f.kind == h2.HEADERS || f.kind == h2.CONTINUATION {
            var fragment = f.payload
            if f.kind == h2.HEADERS {
                if f.stream == 0u32 { ret (at, out, count, Protocol) }
                let (frag, frag_error) = h2.headers_fragment(f)
                if frag_error != ok { ret (at, out, count, Protocol) }
                fragment = frag
                c.block_len = 0usize
                c.block_stream = f.stream
                c.block_end_stream = (f.flags & h2.FLAG_END_STREAM) != 0u8
                c.block_active = true
            } else if !c.block_active || f.stream != c.block_stream {
                ret (at, out, count, Protocol)
            }
            if c.block_len + fragment.len > c.block.len { ret (at, out, count, TooLarge) }
            mem.copy[u8](c.block[c.block_len..c.block_len + fragment.len], fragment)
            c.block_len += fragment.len
            if (f.flags & h2.FLAG_END_HEADERS) != 0u8 {
                c.block_active = false
                var decoded: [48]h2.Header = zero
                let (n, decode_error) = h2.decode_block(&c.dec, c.block[0usize..c.block_len], decoded[0usize..], scratch[scratch_used..])
                if decode_error != ok { ret (at, out, count, Protocol) }
                // The decoded strings live at the front of the scratch slice we passed; account for them.
                var needed = 0usize
                var d = 0usize
                while d < n {
                    needed += decoded[d].name.len + decoded[d].value.len
                    d += 1usize
                }
                if hdr_used + n > hdr.len { ret (at, out, count, TooSmall) }
                var d2 = 0usize
                while d2 < n {
                    hdr[hdr_used + d2] = decoded[d2]
                    d2 += 1usize
                }
                let list = hdr[hdr_used..hdr_used + n]
                hdr_used += n
                scratch_used += needed
                let j = find_stream(c, c.block_stream)
                if j == c.streams.len { continue }
                let s = &c.streams[j]
                let (grpc_status, has_status) = find_header(list, "grpc-status")
                let (http_status, has_http) = find_header(list, ":status")
                if !s.got_headers && !c.block_end_stream {
                    s.got_headers = true
                    events[count] = Event { kind: EVENT_HEADERS, stream: c.block_stream, code: 0u32, compressed: false, text: "", payload: "", headers: list }
                    count += 1usize
                } else {
                    // Trailers, or a trailers-only response: the status and message, decoded.
                    var code = UNKNOWN
                    if has_status {
                        let (parsed, parsed_ok) = parse_u32(grpc_status)
                        if parsed_ok { code = parsed }
                    } else if has_http {
                        let (hs, hs_ok) = parse_u32(http_status)
                        if hs_ok { code = http_to_grpc(hs) }
                    }
                    let (encoded_message, has_message) = find_header(list, "grpc-message")
                    var message: str = ""
                    if has_message {
                        let start = scratch_used
                        let (len, message_error) = message_percent_decode(scratch[start..], encoded_message)
                        if message_error != ok { ret (at, out, count, TooSmall) }
                        message = scratch[start..start + len]
                        scratch_used += len
                    }
                    events[count] = Event { kind: EVENT_TRAILERS, stream: c.block_stream, code: code, compressed: false, text: message, payload: "", headers: list }
                    count += 1usize
                    s.got_headers = true
                    s.remote_closed = true
                }
                if c.block_end_stream { s.remote_closed = true }
            }
        } else if f.kind == h2.DATA {
            if f.stream == 0u32 { ret (at, out, count, Protocol) }
            let (body, body_error) = h2.unpad(f)
            if body_error != ok { ret (at, out, count, Protocol) }
            c.recv_window -= i64(f.payload.len)
            if c.recv_window < 0i64 { ret (at, out, count, Protocol) }
            let j = find_stream(c, f.stream)
            if j < c.streams.len {
                let s = &c.streams[j]
                s.recv_window -= i64(f.payload.len)
                if s.recv_window < 0i64 { ret (at, out, count, Protocol) }
                if s.buf_len + body.len > s.buf.len { ret (at, out, count, TooLarge) }
                mem.copy[u8](s.buf[s.buf_len..s.buf_len + body.len], body)
                s.buf_len += body.len
                // Whole messages out of the reassembly buffer.
                while count + 2usize <= events.len {
                    let (m, m_used, m_error) = message_decode(s.buf[s.consumed..s.buf_len], s.buf.len)
                    if m_error == Incomplete { break }
                    if m_error != ok { ret (at, out, count, Protocol) }
                    events[count] = Event { kind: EVENT_MESSAGE, stream: f.stream, code: 0u32, compressed: m.compressed, text: "", payload: m.payload, headers: hdr[0usize..0usize] }
                    count += 1usize
                    s.consumed += m_used
                }
                // Hand the window back when half of it is used.
                if s.recv_window < c.initial_recv / 2i64 && (f.flags & h2.FLAG_END_STREAM) == 0u8 {
                    let delta = u32_bytes(u32(c.initial_recv - s.recv_window))
                    let e = put_frame(dst, &out, h2.WINDOW_UPDATE, 0u8, f.stream, delta[0usize..4usize])
                    if e != ok { ret (at, out, count, TooSmall) }
                    s.recv_window = c.initial_recv
                }
                if (f.flags & h2.FLAG_END_STREAM) != 0u8 { s.remote_closed = true }
            }
            if c.recv_window < c.initial_recv / 2i64 {
                let delta = u32_bytes(u32(c.initial_recv - c.recv_window))
                let e = put_frame(dst, &out, h2.WINDOW_UPDATE, 0u8, 0u32, delta[0usize..4usize])
                if e != ok { ret (at, out, count, TooSmall) }
                c.recv_window = c.initial_recv
            }
        }
    }
    ret (at, out, count, ok)
}
