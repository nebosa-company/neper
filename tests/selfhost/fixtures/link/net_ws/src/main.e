// RFC 6455's client nonce is exactly sixteen caller-supplied bytes and encodes to a
// padded twenty-four-byte standard Base64 key without allocation.

use e.io
use e.mem
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
    let expected_request = "GET /chat HTTP/1.1\r\nHost: server.example.com\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nContent-Length: 0\r\n\r\n"
    if !str.eq(request_bytes[0usize..request_capture.off], expected_request) { os.exit(13i32) }

    let invalid_text = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: wrong\r\n\r\n"
    var invalid_source = io.SliceReader { data: invalid_text, off: 0usize }
    let invalid_reader = io.slice_reader(&invalid_source)
    var invalid_bytes: [512]u8 = zero
    var invalid_capture = io.SliceWriter { data: invalid_bytes[0..], off: 0usize }
    let invalid_sink = io.slice_writer(&invalid_capture)
    let (invalid_connection, invalid_error) = ws.client_upgrade(a, invalid_reader, invalid_sink, "server.example.com", "/chat", entropy)
    if invalid_error != ws.InvalidHandshake { os.exit(14i32) }
    ret ok
}
