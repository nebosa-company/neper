// WebSocket handshake and framing. The client handshake and outbound frame path are
// delivered; server upgrade and inbound frame transport follow as separate slices.

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
    fragmented: bool,
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
    state.fragmented = false

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

fn opcode_byte(opcode: Opcode) -> u8 {
    if opcode == .Continuation { ret 0u8 }
    if opcode == .Text { ret 1u8 }
    if opcode == .Binary { ret 2u8 }
    if opcode == .Close { ret 8u8 }
    if opcode == .Ping { ret 9u8 }
    ret 10u8
}

fn control_opcode(opcode: Opcode) -> bool {
    ret opcode == .Close || opcode == .Ping || opcode == .Pong
}

fn send(connection: *Connection, frame: Frame, mask: [4]u8) -> err {
    let state = mem.cast[*ConnectionState](connection.state)
    if state.closed { ret Closed }
    let control = control_opcode(frame.opcode)
    if control && (!frame.final || frame.payload.len > 125usize) { ret InvalidFrame }
    var next_fragmented = state.fragmented
    if frame.opcode == .Continuation {
        if !state.fragmented { ret InvalidFrame }
        if frame.final { next_fragmented = false }
    } else if !control {
        if state.fragmented { ret InvalidFrame }
        if !frame.final { next_fragmented = true }
    }

    var header: [14]u8 = zero
    header[0usize] = opcode_byte(frame.opcode)
    if frame.final { header[0usize] |= 128u8 }
    var used = 2usize
    if frame.payload.len < 126usize {
        header[1usize] = u8(frame.payload.len)
    } else if frame.payload.len <= 65535usize {
        header[1usize] = 126u8
        header[2usize] = u8((frame.payload.len >> 8usize) & 255usize)
        header[3usize] = u8(frame.payload.len & 255usize)
        used = 4usize
    } else {
        header[1usize] = 127u8
        let length = u64(frame.payload.len)
        var at = 0usize
        while at < 8usize {
            header[2usize + at] = u8((length >> u32((7usize - at) * 8usize)) & 255u64)
            at += 1usize
        }
        used = 10usize
    }
    if state.client {
        header[1usize] |= 128u8
        var at = 0usize
        while at < mask.len {
            header[used + at] = mask[at]
            at += 1usize
        }
        used += mask.len
    }
    try io.write_all(&state.sink, header[0usize..used])
    if state.client {
        var block: [1024]u8 = zero
        var offset = 0usize
        while offset < frame.payload.len {
            var count = frame.payload.len - offset
            if count > block.len { count = block.len }
            var at = 0usize
            while at < count {
                block[at] = frame.payload[offset + at] ^ mask[(offset + at) % 4usize]
                at += 1usize
            }
            try io.write_all(&state.sink, block[0usize..count])
            offset += count
        }
    } else {
        try io.write_all(&state.sink, frame.payload)
    }
    state.fragmented = next_fragmented
    if frame.opcode == .Close { state.closed = true }
    ret ok
}

fn ping(connection: *Connection, payload: []const u8, mask: [4]u8) -> err {
    let frame = Frame { final: true, opcode: .Ping, payload: payload }
    ret send(connection, frame, mask)
}

fn valid_close_code(code: u16) -> bool {
    if code >= 3000u16 && code <= 4999u16 { ret true }
    if code < 1000u16 || code > 1014u16 { ret false }
    ret code != 1004u16 && code != 1005u16 && code != 1006u16
}

fn close(connection: *Connection, code: u16, reason: str, mask: [4]u8) -> err {
    if !valid_close_code(code) || reason.len > 123usize { ret InvalidFrame }
    var payload: [125]u8 = zero
    payload[0usize] = u8((code >> 8u16) & 255u16)
    payload[1usize] = u8(code & 255u16)
    var at = 0usize
    while at < reason.len {
        payload[2usize + at] = reason[at]
        at += 1usize
    }
    let frame = Frame { final: true, opcode: .Close, payload: payload[0usize..reason.len + 2usize] }
    ret send(connection, frame, mask)
}
