// WebSocket handshake and framing. The allocation-free client nonce and bounded client
// upgrade are delivered; server upgrade and frame transport follow as separate slices.

use e.bytes
use e.crypto.hash
use e.io
use e.mem
use e.net.http

type Opcode = enum u8 { Continuation, Text, Binary, Close, Ping, Pong }
type Frame = struct { final: bool, opcode: Opcode, payload: []const u8 }
type Connection = struct { state: *void }

error InvalidHandshake
error InvalidFrame
error TooLarge
error Closed

const HANDSHAKE_LINE: usize = 1024usize
const HANDSHAKE_HEADERS: usize = 8192usize
const HANDSHAKE_COUNT: usize = 64usize

type ConnectionState = struct {
    source: io.Reader,
    sink: io.Writer,
    client: bool,
    closed: bool,
}

fn client_key(entropy: [16]u8, dst: []u8) -> (str, err) {
    let (encoded, encode_error) = bytes.base64_encode(dst, entropy[0..], .Standard, true)
    if encode_error == bytes.TooLarge { ret ("", TooLarge) }
    if encode_error != ok { ret ("", encode_error) }
    ret (encoded, ok)
}

fn accept_key(key: str, dst: []u8) -> (str, err) {
    if key.len != 24usize { ret ("", InvalidHandshake) }
    let guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    var message: [60]u8 = zero
    var at = 0usize
    while at < key.len {
        message[at] = key[at]
        at += 1usize
    }
    var guid_at = 0usize
    while guid_at < guid.len {
        message[at + guid_at] = guid[guid_at]
        guid_at += 1usize
    }
    let digest = hash.legacy_sha1(message[0..])
    let (encoded, encode_error) = bytes.base64_encode(dst, digest[0..], .Standard, true)
    if encode_error == bytes.TooLarge { ret ("", TooLarge) }
    if encode_error != ok { ret ("", encode_error) }
    ret (encoded, ok)
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn ascii_lower(byte: u8) -> u8 {
    if byte >= 65u8 && byte <= 90u8 { ret byte + 32u8 }
    ret byte
}

fn same_ascii(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if ascii_lower(left[at]) != ascii_lower(right[at]) { ret false }
        at += 1usize
    }
    ret true
}

fn header_has_token(value: str, token: str) -> bool {
    var at = 0usize
    while at < value.len {
        while at < value.len && (value[at] == 32u8 || value[at] == 9u8 || value[at] == 44u8) { at += 1usize }
        var end = at
        while end < value.len && value[end] != 44u8 { end += 1usize }
        var trimmed = end
        while trimmed > at && (value[trimmed - 1usize] == 32u8 || value[trimmed - 1usize] == 9u8) { trimmed -= 1usize }
        if same_ascii(value[at..trimmed], token) { ret true }
        at = end + 1usize
    }
    ret false
}

fn handshake_read(ctx: *void, dst: []u8) -> (usize, err) {
    let state = mem.cast[*ConnectionState](ctx)
    if dst.len == 0usize { ret (0usize, ok) }
    let (count, read_error) = io.read(&state.source, dst[0usize..1usize])
    ret (count, read_error)
}

fn client_upgrade(a: *mem.Arena, stream: io.Reader, sink: io.Writer, host: str, target_path: str, entropy: [16]u8) -> (Connection, err) {
    var out: Connection = zero
    let mark = mem.mark(a)
    let (storage, storage_error) = mem.alloc[ConnectionState](a, 1usize)
    if storage_error != ok { ret (out, storage_error) }
    let state = &storage[0usize]
    state.source = stream
    state.sink = sink
    state.client = true
    state.closed = false

    var key_storage: [24]u8 = zero
    let (key, key_error) = client_key(entropy, key_storage[0..])
    if key_error != ok {
        mem.reset(a, mark)
        ret (out, key_error)
    }
    var headers: [5]http.Header = zero
    headers[0usize] = http.Header { name: "Host", value: host }
    headers[1usize] = http.Header { name: "Upgrade", value: "websocket" }
    headers[2usize] = http.Header { name: "Connection", value: "Upgrade" }
    headers[3usize] = http.Header { name: "Sec-WebSocket-Key", value: key }
    headers[4usize] = http.Header { name: "Sec-WebSocket-Version", value: "13" }
    var request = http.Request { method: .Get, target: target_path, version: .Http11, headers: headers[0..], body: "" }
    var encoder = http.writer(state.sink)
    let write_error = http.write_request(&encoder, &request)
    if write_error != ok {
        mem.reset(a, mark)
        ret (out, write_error)
    }

    let one_byte = io.Reader { ctx: mem.cast[*void](state), read: handshake_read }
    let limits = http.Limits { start_line: HANDSHAKE_LINE, header_bytes: HANDSHAKE_HEADERS, header_count: HANDSHAKE_COUNT, body_bytes: 0usize }
    let (created, reader_error) = http.reader(a, one_byte, limits)
    if reader_error != ok {
        mem.reset(a, mark)
        ret (out, reader_error)
    }
    var decoder = created
    let (response, response_error) = http.read_response(a, &decoder)
    if response_error != ok || response.status != 101u16 {
        mem.reset(a, mark)
        ret (out, InvalidHandshake)
    }
    let (upgrade, has_upgrade) = http.header(response.headers, "Upgrade")
    let (connection, has_connection) = http.header(response.headers, "Connection")
    let (accepted, has_accepted) = http.header(response.headers, "Sec-WebSocket-Accept")
    var expected_storage: [28]u8 = zero
    let (expected, expected_error) = accept_key(key, expected_storage[0..])
    if expected_error != ok || !has_upgrade || !has_connection || !has_accepted || !same_ascii(upgrade, "websocket") || !header_has_token(connection, "Upgrade") || !same(accepted, expected) {
        mem.reset(a, mark)
        ret (out, InvalidHandshake)
    }
    out.state = mem.cast[*void](state)
    ret (out, ok)
}
