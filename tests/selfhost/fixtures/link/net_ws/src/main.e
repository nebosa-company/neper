// RFC 6455's client nonce is exactly sixteen caller-supplied bytes and encodes to a
// padded twenty-four-byte standard Base64 key without allocation.

use e.io
use e.mem
use e.net.http
use e.net.ws
use e.os
use e.str

error Failed

fn main(a: *mem.Arena) -> err {
    var entropy: [16]u8 = zero
    let source = "the sample nonce"
    var at = 0usize
    while at < entropy.len {
        entropy[at] = source[at]
        at += 1usize
    }
    var output: [24]u8 = zero
    let (key, key_error) = ws.client_key(entropy, output[0..])
    if key_error != ok || !str.eq(key, "dGhlIHNhbXBsZSBub25jZQ==") { os.exit(10i32) }
    let (short_key, short_error) = ws.client_key(entropy, output[0..23usize])
    if short_error != ws.TooLarge || short_key.len != 0usize { os.exit(11i32) }

    let response_text = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: WebSocket\r\nConnection: keep-alive, upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
    var response_source = io.SliceReader { data: response_text, off: 0usize }
    let response_reader = io.slice_reader(&response_source)
    var request_bytes: [512]u8 = zero
    var request_capture = io.SliceWriter { data: request_bytes[0..], off: 0usize }
    let request_sink = io.slice_writer(&request_capture)
    let (connection, upgrade_error) = ws.client_upgrade(a, response_reader, request_sink, "server.example.com", "/chat", entropy)
    if upgrade_error != ok || connection.state == nil { os.exit(12i32) }
    var upgraded = connection
    let expected_request = "GET /chat HTTP/1.1\r\nHost: server.example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nContent-Length: 0\r\n\r\n"
    if !str.eq(request_bytes[0usize..request_capture.off], expected_request) { os.exit(13i32) }

    // Client frames carry caller masking material. Length 126 selects the first extended
    // form, and every payload byte continues the mask across the whole frame.
    request_capture.off = 0usize
    var payload: [126]u8 = zero
    at = 0usize
    while at < payload.len {
        payload[at] = u8(at)
        at += 1usize
    }
    var mask: [4]u8 = zero
    mask[0usize] = 1u8
    mask[1usize] = 2u8
    mask[2usize] = 3u8
    mask[3usize] = 4u8
    let binary = ws.Frame { final: true, opcode: .Binary, payload: payload[0..] }
    if ws.send(&upgraded, binary, mask) != ok { os.exit(15i32) }
    if request_capture.off != 134usize || request_bytes[0usize] != 130u8 || request_bytes[1usize] != 254u8 || request_bytes[2usize] != 0u8 || request_bytes[3usize] != 126u8 { os.exit(16i32) }
    at = 0usize
    while at < mask.len {
        if request_bytes[4usize + at] != mask[at] { os.exit(17i32) }
        at += 1usize
    }
    at = 0usize
    while at < payload.len {
        if request_bytes[8usize + at] != (payload[at] ^ mask[at % 4usize]) { os.exit(18i32) }
        at += 1usize
    }

    request_capture.off = 0usize
    if ws.ping(&upgraded, payload[0..], mask) != ws.InvalidFrame || request_capture.off != 0usize { os.exit(19i32) }
    if ws.ping(&upgraded, "hi", mask) != ok { os.exit(20i32) }
    if request_capture.off != 8usize || request_bytes[0usize] != 137u8 || request_bytes[1usize] != 130u8 || request_bytes[6usize] != (104u8 ^ 1u8) || request_bytes[7usize] != (105u8 ^ 2u8) { os.exit(21i32) }

    request_capture.off = 0usize
    if ws.close(&upgraded, 1000u16, "bye", mask) != ok { os.exit(22i32) }
    if request_capture.off != 11usize || request_bytes[0usize] != 136u8 || request_bytes[1usize] != 133u8 { os.exit(23i32) }
    if request_bytes[6usize] != (3u8 ^ 1u8) || request_bytes[7usize] != (232u8 ^ 2u8) || request_bytes[8usize] != (98u8 ^ 3u8) || request_bytes[9usize] != (121u8 ^ 4u8) || request_bytes[10usize] != (101u8 ^ 1u8) { os.exit(24i32) }
    if ws.close(&upgraded, 1000u16, "", mask) != ws.Closed { os.exit(25i32) }

    let invalid_text = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: wrong\r\n\r\n"
    var invalid_source = io.SliceReader { data: invalid_text, off: 0usize }
    let invalid_reader = io.slice_reader(&invalid_source)
    var invalid_bytes: [512]u8 = zero
    var invalid_capture = io.SliceWriter { data: invalid_bytes[0..], off: 0usize }
    let invalid_sink = io.slice_writer(&invalid_capture)
    let (invalid_connection, invalid_error) = ws.client_upgrade(a, invalid_reader, invalid_sink, "server.example.com", "/chat", entropy)
    if invalid_error != ws.InvalidHandshake { os.exit(14i32) }

    // A server validates the reciprocal upgrade, unmasks client input and emits
    // unmasked output. The following oversized frame stops at its declared bound.
    var server_headers: [5]http.Header = zero
    server_headers[0usize] = http.Header { name: "Host", value: "server.example.com" }
    server_headers[1usize] = http.Header { name: "Upgrade", value: "WebSocket" }
    server_headers[2usize] = http.Header { name: "Connection", value: "keep-alive, Upgrade" }
    server_headers[3usize] = http.Header { name: "Sec-WebSocket-Key", value: "dGhlIHNhbXBsZSBub25jZQ==" }
    server_headers[4usize] = http.Header { name: "Sec-WebSocket-Version", value: "13" }
    var server_request = http.Request { method: .Get, target: "/chat", version: .Http11, headers: server_headers[0..], body: "" }
    var inbound: [16]u8 = zero
    inbound[0usize] = 129u8
    inbound[1usize] = 130u8
    inbound[2usize] = 1u8
    inbound[3usize] = 2u8
    inbound[4usize] = 3u8
    inbound[5usize] = 4u8
    inbound[6usize] = 121u8 ^ 1u8
    inbound[7usize] = 111u8 ^ 2u8
    inbound[8usize] = 130u8
    inbound[9usize] = 130u8
    inbound[10usize] = 5u8
    inbound[11usize] = 6u8
    inbound[12usize] = 7u8
    inbound[13usize] = 8u8
    inbound[14usize] = 120u8 ^ 5u8
    inbound[15usize] = 121u8 ^ 6u8
    var server_source = io.SliceReader { data: inbound[0..], off: 0usize }
    let server_reader = io.slice_reader(&server_source)
    var server_bytes: [512]u8 = zero
    var server_capture = io.SliceWriter { data: server_bytes[0..], off: 0usize }
    let server_sink = io.slice_writer(&server_capture)
    let (server_connection, server_error) = ws.server_upgrade(a, server_reader, server_sink, &server_request)
    if server_error != ok || server_connection.state == nil { os.exit(26i32) }
    var server = server_connection
    let expected_response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"
    if !str.eq(server_bytes[0usize..server_capture.off], expected_response) { os.exit(27i32) }
    let (text_frame, receive_error) = ws.receive(a, &server, 16usize)
    if receive_error != ok || !text_frame.final || text_frame.opcode != .Text || !str.eq(text_frame.payload, "yo") { os.exit(28i32) }
    server_capture.off = 0usize
    let pong = ws.Frame { final: true, opcode: .Pong, payload: "ok" }
    if ws.send(&server, pong, mask) != ok { os.exit(29i32) }
    if server_capture.off != 4usize || server_bytes[0usize] != 138u8 || server_bytes[1usize] != 2u8 || server_bytes[2usize] != 111u8 || server_bytes[3usize] != 107u8 { os.exit(30i32) }
    let (large_frame, large_error) = ws.receive(a, &server, 1usize)
    if large_error != ws.TooLarge { os.exit(31i32) }
    ret ok
}
