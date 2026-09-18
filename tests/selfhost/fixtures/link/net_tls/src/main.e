// TLS stream construction retains explicit caller I/O/configuration and reports
// only the pinned TLS 1.3 version before a handshake has selected ALPN.

use e.io
use e.mem
use e.net.tls
use e.os
use e.time
use e.crypto.kdf as kdf

fn same_bytes(left: []const u8, right: []const u8) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

fn main(a: *mem.Arena) -> err {
    let none: [0]u8 = zero
    var source_state = io.SliceReader { data: none[0..], off: 0usize }
    let source = io.slice_reader(&source_state)
    var sink_bytes: [1]u8 = zero
    var sink_state = io.SliceWriter { data: sink_bytes[0..], off: 0usize }
    let sink = io.slice_writer(&sink_state)
    let protocols: [1]str = [1]str{ "h2" }
    var entropy: [32]u8 = zero
    let client_config = tls.ClientConfig { server_name: "example.com", trust_roots: none[0..], alpn: protocols[0..], entropy: entropy[0..], now: time.Timestamp { nanos: 0i64 } }
    let (client_stream, client_error) = tls.client(a, source, sink, client_config)
    if client_error != ok || client_stream.state == nil || tls.protocol(&client_stream) != .Tls13 || tls.negotiated_alpn(&client_stream).len != 0usize { os.exit(1i32) }
    let server_config = tls.ServerConfig { certificate_chain: none[0..], private_key: none[0..], alpn: protocols[0..], entropy: entropy[0..] }
    let (server_stream, server_error) = tls.server(a, source, sink, server_config)
    if server_error != ok || server_stream.state == nil || tls.protocol(&server_stream) != .Tls13 || tls.negotiated_alpn(&server_stream).len != 0usize { os.exit(2i32) }
    if source_state.off != 0usize || sink_state.off != 0usize { os.exit(3i32) }

    // RFC 8448's first TLS 1.3 "derived" secret pins the label encoding and
    // proves the schedule is composed from e.crypto.kdf.
    let zeros: [32]u8 = zero
    let early = kdf.hkdf_sha256_extract(zeros[0..], zeros[0..])
    var derived: [32]u8 = zero
    let empty = tls.empty_hash()
    let derive_error = tls.hkdf_expand_label(early, "derived", empty[0..], derived[0..])
    let expected = "\x6f\x26\x15\xa1\x08\xc7\x02\xc5\x67\x8f\x54\xfc\x9d\xba\xb6\x97\x16\xc0\x76\x18\x9c\x48\x25\x0c\xeb\xea\xc3\x57\x6c\x36\x11\xba"
    if derive_error != ok || !same_bytes(derived[0..], expected) { os.exit(4i32) }
    ret ok
}
