// TLS stream construction retains explicit caller I/O/configuration and reports
// only the pinned TLS 1.3 version before a handshake has selected ALPN.

use e.io
use e.mem
use e.net.tls
use e.net
use e.net.http as http
use e.os
use e.time
use e.crypto.kdf as kdf
use e.crypto.kx as kx
use e.crypto.aead as aead
use e.cancel
use e.thread

fn same_bytes(left: []const u8, right: []const u8) -> bool {
    if left.len != right.len { ret false }
    var at = 0usize
    while at < left.len {
        if left[at] != right[at] { ret false }
        at += 1usize
    }
    ret true
}

type ServerJob = struct {
    reading: *os.File,
    writing: *os.File,
    config: tls.ServerConfig,
    selected: str,
    failure: err,
}

fn serve(job: *ServerJob) {
    var storage: [262144]u8 = zero
    var arena = mem.arena_from(storage[0..])
    let source = io.file_reader(job.reading)
    let sink = io.file_writer(job.writing)
    let (stream0, create_error) = tls.server(&arena, source, sink, job.config)
    if create_error != ok {
        job.failure = create_error
        ret
    }
    var stream = stream0
    job.failure = tls.handshake(&stream)
    if job.failure != ok { ret }
    job.selected = tls.negotiated_alpn(&stream)
    var secure_source = tls.reader(&stream)
    var request: [4]u8 = zero
    job.failure = io.read_exact(&secure_source, request[0..])
    if job.failure != ok || !same_bytes(request[0..], "ping") { ret }
    var secure_sink = tls.writer(&stream)
    job.failure = io.write_all(&secure_sink, "pong")
    if job.failure == ok { job.failure = tls.close(&stream) }
}

fn live_handshake(a: *mem.Arena, server_read: *os.File, client_write: *os.File, client_read: *os.File, server_write: *os.File, server_config: tls.ServerConfig, client_config: tls.ClientConfig, client_selected: *str, server_selected: *str) -> err {
    var server_job = ServerJob { reading: server_read, writing: server_write, config: server_config, selected: "", failure: ok }
    let (server_thread, thread_error) = os.thread_create[ServerJob](serve, &server_job, 8388608usize)
    if thread_error != ok { ret thread_error }
    let client_source = io.file_reader(client_read)
    let client_sink = io.file_writer(client_write)
    let (live_stream0, live_create_error) = tls.client(a, client_source, client_sink, client_config)
    if live_create_error != ok { os.exit(20i32) }
    var live_stream = live_stream0
    if tls.handshake(&live_stream) != ok { os.exit(21i32) }
    var live_sink = tls.writer(&live_stream)
    if io.write_all(&live_sink, "ping") != ok { os.exit(26i32) }
    var live_source = tls.reader(&live_stream)
    var reply: [4]u8 = zero
    if io.read_exact(&live_source, reply[0..]) != ok || !same_bytes(reply[0..], "pong") { os.exit(27i32) }
    var after_close: [1]u8 = zero
    let (_, end_error) = io.read(&live_source, after_close[0..])
    if end_error != io.End { os.exit(28i32) }
    if tls.close(&live_stream) != ok || tls.close(&live_stream) != ok { os.exit(29i32) }
    let (_, closed_write_error) = io.write(&live_sink, "x")
    if closed_write_error != tls.Closed { os.exit(30i32) }
    let join_error = os.thread_join(server_thread)
    if join_error != ok { os.exit(22i32) }
    if server_job.failure != ok { os.exit(22i32) }
    *client_selected = tls.negotiated_alpn(&live_stream)
    *server_selected = server_job.selected
    ret ok
}

type HttpServerJob = struct { listener: net.Socket, config: tls.ServerConfig, failed: bool }

fn http_limits() -> http.Limits {
    ret http.Limits { start_line: 128usize, header_bytes: 512usize, header_count: 16usize, body_bytes: 64usize }
}

fn serve_https(job: *HttpServerJob) {
    var storage: [524288]u8 = zero
    var arena = mem.arena_from(storage[0..])
    let (accepted, peer, accept_error) = net.tcp_accept(job.listener)
    if accept_error != ok {
        job.failed = true
        ret
    }
    var connection = accepted
    defer let _ = net.close(connection)
    let source = net.reader(&connection)
    let sink = net.writer(&connection)
    let (secure0, create_error) = tls.server(&arena, source, sink, job.config)
    if create_error != ok {
        job.failed = true
        ret
    }
    var secure = secure0
    if tls.handshake(&secure) != ok {
        job.failed = true
        ret
    }
    let secure_source = tls.reader(&secure)
    let (decoder0, decoder_error) = http.reader(&arena, secure_source, http_limits())
    if decoder_error != ok {
        job.failed = true
        ret
    }
    var decoder = decoder0
    let (request, request_error) = http.read_request(&arena, &decoder)
    if request_error != ok || request.method != .Get || !same_bytes(request.target, "/secure") {
        job.failed = true
        ret
    }
    var response: http.Response = zero
    response.version = .Http11
    response.status = 200u16
    response.reason = "OK"
    response.body = "secure"
    var secure_sink = tls.writer(&secure)
    var encoder = http.writer(secure_sink)
    if http.write_response(&encoder, &response) != ok || tls.close(&secure) != ok { job.failed = true }
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

    // RFC 8448's protected client Finished record pins AES-128-GCM framing,
    // the authenticated header, inner content type and sequence-zero nonce.
    let client_handshake_secret: [32]u8 = [32]u8{ 179, 237, 219, 18, 110, 6, 127, 53, 167, 128, 179, 171, 244, 94, 45, 143, 59, 26, 149, 7, 56, 245, 46, 150, 0, 116, 106, 14, 39, 165, 90, 33 }
    let (record_keys0, keys_error) = tls.traffic_keys(client_handshake_secret)
    if keys_error != ok { os.exit(5i32) }
    var record_keys = record_keys0
    let finished = "\x14\x00\x00\x20\xa8\xec\x43\x6d\x67\x76\x34\xae\x52\x5a\xc1\xfc\xeb\xe1\x1a\x03\x9e\xc1\x76\x94\xfa\xc6\xe9\x85\x27\xb6\x42\xf2\xed\xd5\xce\x61"
    var record: [58]u8 = zero
    let (record_len, record_error) = tls.seal_record(&record_keys, 22u8, finished, record[0..])
    let expected_record = "\x17\x03\x03\x00\x35\x75\xec\x4d\xc2\x38\xcc\xe6\x0b\x29\x80\x44\xa7\x1e\x21\x9c\x56\xcc\x77\xb0\x51\x7f\xe9\xb9\x3c\x7a\x4b\xfc\x44\xd8\x7f\x38\xf8\x03\x38\xac\x98\xfc\x46\xde\xb3\x84\xbd\x1c\xae\xac\xab\x68\x67\xd7\x26\xc4\x05\x46"
    if record_error != ok || record_len != 58usize || !same_bytes(record[0..], expected_record) { os.exit(6i32) }
    var read_keys = record_keys0
    var opened: [36]u8 = zero
    let (opened_len, opened_type, open_error) = tls.open_record(&read_keys, record[0..], opened[0..])
    if open_error != ok || opened_type != 22u8 || opened_len != finished.len || !same_bytes(opened[0..], finished) { os.exit(7i32) }
    record[20] = record[20] ^ 1u8
    var bad_keys = record_keys0
    let (_, _, bad_error) = tls.open_record(&bad_keys, record[0..], opened[0..])
    if bad_error != tls.Protocol || bad_keys.sequence != 0u64 { os.exit(8i32) }
    var padded_record: [27]u8 = zero
    padded_record[0] = 23u8
    padded_record[1] = 3u8
    padded_record[2] = 3u8
    padded_record[4] = 22u8
    let padded_inner: [6]u8 = [6]u8{ 111, 107, 23, 0, 0, 0 }
    var padded_seal_keys = record_keys0
    let padded_nonce = tls.record_nonce(&padded_seal_keys)
    let (padded_written, padded_seal_error) = aead.aes128_gcm_seal(padded_record[5usize..], padded_seal_keys.key, padded_nonce, padded_record[..5usize], padded_inner[0..])
    var padded_open_keys = record_keys0
    let (padded_len, padded_type, padded_open_error) = tls.open_record(&padded_open_keys, padded_record[..5usize + padded_written], opened[0..])
    if padded_seal_error != ok || padded_written != 22usize || padded_open_error != ok || padded_len != 2usize || padded_type != 23u8 || !same_bytes(opened[..2usize], "ok") { os.exit(43i32) }

    // The narrow hello profile negotiates only TLS 1.3, AES-128-GCM/SHA-256,
    // X25519 and Ed25519, with server-preference ALPN.
    var client_entropy: [64]u8 = zero
    var server_entropy: [64]u8 = zero
    var entropy_at = 0usize
    while entropy_at < 64usize {
        client_entropy[entropy_at] = u8(entropy_at + 1usize)
        server_entropy[entropy_at] = u8(128usize + entropy_at)
        entropy_at += 1usize
    }
    let client_protocols: [2]str = [2]str{ "http/1.1", "h2" }
    let server_protocols: [2]str = [2]str{ "h2", "http/1.1" }
    let hello_client_config = tls.ClientConfig { server_name: "example.com", trust_roots: none[0..], alpn: client_protocols[0..], entropy: client_entropy[0..], now: time.Timestamp { nanos: 0i64 } }
    let hello_server_config = tls.ServerConfig { certificate_chain: none[0..], private_key: none[0..], alpn: server_protocols[0..], entropy: server_entropy[0..] }
    var client_hello: [512]u8 = zero
    let (client_hello_len, client_secret, client_hello_error) = tls.build_client_hello(hello_client_config, client_hello[0..])
    if client_hello_error != ok { os.exit(9i32) }
    let (hello_info, parse_client_error) = tls.parse_client_hello(client_hello[..client_hello_len], server_protocols[0..])
    if parse_client_error != ok || !same_bytes(hello_info.selected_alpn, "h2") { os.exit(10i32) }
    var server_hello: [128]u8 = zero
    let (server_hello_len, server_secret, server_hello_error) = tls.build_server_hello(hello_server_config, server_hello[0..])
    if server_hello_error != ok || server_hello_len != 90usize { os.exit(11i32) }
    let (server_key, parse_server_error) = tls.parse_server_hello(server_hello[..server_hello_len])
    if parse_server_error != ok { os.exit(12i32) }
    server_hello[45] = 43u8
    let (_, duplicate_extension_error) = tls.parse_server_hello(server_hello[..server_hello_len])
    if duplicate_extension_error != tls.Protocol { os.exit(44i32) }
    server_hello[45] = 51u8
    let (client_shared, client_shared_error) = kx.x25519_exchange(client_secret, server_key)
    let (server_shared, server_shared_error) = kx.x25519_exchange(server_secret, hello_info.peer_key)
    if client_shared_error != ok || server_shared_error != ok || !same_bytes(client_shared.bytes[0..], server_shared.bytes[0..]) { os.exit(13i32) }
    var stopped = cancel.token()
    cancel.request(&stopped)
    var cancelled_source_state = io.SliceReader { data: none[0..], off: 0usize }
    let cancelled_source = io.slice_reader(&cancelled_source_state)
    var cancelled_sink_bytes: [1]u8 = zero
    var cancelled_sink_state = io.SliceWriter { data: cancelled_sink_bytes[0..], off: 0usize }
    let cancelled_sink = io.slice_writer(&cancelled_sink_state)
    let (cancelled_stream0, cancelled_create_error) = tls.client(a, cancelled_source, cancelled_sink, hello_client_config)
    if cancelled_create_error != ok { os.exit(31i32) }
    var cancelled_stream = cancelled_stream0
    let control = cancel.Control { token: &stopped, deadline: zero, has_deadline: false }
    if tls.handshake_with_control(&cancelled_stream, control) != cancel.Cancelled || cancelled_source_state.off != 0usize || cancelled_sink_state.off != 0usize { os.exit(32i32) }

    // Ed25519 leaf and intermediate from the e.crypto.x509 reference chain.
    let mid_der = "0\x82\x01\x130\x81\xc6\xa0\x03\x02\x01\x02\x02\x01\x020\x05\x06\x03+ep0%1\x130\x11\x06\x03U\x04\x03\x0c\x0aNeper Root1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0*0\x05\x06\x03+ep\x03!\x00\x819w\x0e\xa8}\x17_V\xa3Tf\xc3L~\xcc\xcb\x8d\x8a\x91\xb4\xee7\xa2]\xf6\x0f[\x8f\xc9\xb3\x94\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x05\x06\x03+ep\x03A\x00R^\x187\xb39[\xa4N\xc4\x83\x10\xde\xfc\x7f\xa0\xbfF[\xa8^\x04S\xa1\xb2\xf8\xbcM\xc7\xfb\xf1t\x89\xa0\x0e\x07\xcc\xbf\x8f6R\x16\x15\xab\x99\x0e\xdd\xc1,\x8d\x8f*\xd4\xaf\x97\xaae\x8b\xab\xe5\x0d\x8e'\x08"
    let leaf_der = "0\x82\x01=0\x81\xf0\xa0\x03\x02\x01\x02\x02\x01\x030\x05\x06\x03+ep0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x161\x140\x12\x06\x03U\x04\x03\x0c\x0bexample.com0*0\x05\x06\x03+ep\x03!\x00\xedI(\xc6(\xd1\xc2\xc6\xea\xe9\x038\x90Y\x95a)Y':\\c\xf966\xc1F\x14\xac\x877\xd1\xa3L0J0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000%\x06\x03U\x1d\x11\x04\x1e0\x1c\x82\x0bexample.com\x82\x0d*.example.org0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x05\x06\x03+ep\x03A\x00\x84Pf\xea\x11\xb7\xdb-w\xdf\xd2\xa8\xden\xd3\xbey|r`B'h\xfc\x22\x08\xca\x8e%u\xa8\xa7)\xd3\xb3\x15Tc\xc8\x10\xa0\x97\x84C\xaaU4\xf0>\x00\x0f\xfau\xe7\xaa\xb9\xae\x9e\x9br\xe8Bv\x09"
    let leaf_pkcs8 = "0.\x02\x01\x000\x05\x06\x03+ep\x04\x22\x04\x20\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03"
    var certificate_message: [1024]u8 = zero
    let (certificate_len, certificate_error) = tls.build_certificate_message(leaf_der, certificate_message[0..])
    if certificate_error != ok { os.exit(14i32) }
    let (certificate_set, certificate_parse_error) = tls.parse_certificate_message(a, certificate_message[..certificate_len])
    if certificate_parse_error != ok { os.exit(15i32) }
    let verify_config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: client_protocols[0..], entropy: client_entropy[0..], now: time.Timestamp { nanos: 1780272000000000000i64 } }
    if tls.verify_certificate_set(a, certificate_set, verify_config) != ok { os.exit(16i32) }
    let credential_config = tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: server_protocols[0..], entropy: server_entropy[0..] }
    let (signing_key, credential_error) = tls.validate_server_credentials(a, credential_config)
    if credential_error != ok { os.exit(17i32) }
    var transcript_hash: [32]u8 = zero
    var certificate_verify: [72]u8 = zero
    let (certificate_verify_len, certificate_verify_error) = tls.build_certificate_verify(signing_key, transcript_hash, certificate_verify[0..])
    if certificate_verify_error != ok || certificate_verify_len != 72usize || tls.verify_certificate_verify(certificate_set.leaf, transcript_hash, certificate_verify[0..]) != ok { os.exit(18i32) }
    certificate_verify[20] = certificate_verify[20] ^ 1u8
    if tls.verify_certificate_verify(certificate_set.leaf, transcript_hash, certificate_verify[0..]) != tls.InvalidCertificate { os.exit(19i32) }

    // A real duplex exchange drives both synchronous state machines through
    // every encrypted authentication message and both Finished checks.
    var server_read: os.File = zero
    var client_write: os.File = zero
    let (server_read_open, client_write_open, client_to_server_error) = os.pipe()
    if client_to_server_error != ok { ret client_to_server_error }
    server_read = server_read_open
    client_write = client_write_open
    var client_read: os.File = zero
    var server_write: os.File = zero
    let (client_read_open, server_write_open, server_to_client_error) = os.pipe()
    if server_to_client_error != ok {
        let _ = os.close(server_read)
        let _ = os.close(client_write)
        ret server_to_client_error
    }
    client_read = client_read_open
    server_write = server_write_open
    var client_selected = ""
    var server_selected = ""
    let live_config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: client_protocols[0..], entropy: client_entropy[0..], now: time.Timestamp { nanos: 1780272000000000000i64 } }
    let live_error = live_handshake(a, &server_read, &client_write, &client_read, &server_write, credential_config, live_config, &client_selected, &server_selected)
    if live_error != ok { os.exit(25i32) }
    if !same_bytes(client_selected, "h2") || !same_bytes(server_selected, "h2") { os.exit(23i32) }
    if os.close(server_read) != ok || os.close(client_write) != ok || os.close(client_read) != ok || os.close(server_write) != ok { os.exit(24i32) }

    // The full HTTP helper owns one authenticated connection end to end.
    let (loopback, loopback_error) = net.parse_ip("127.0.0.1")
    if loopback_error != ok { ret loopback_error }
    var endpoint = net.Endpoint { address: loopback, port: 0u16 }
    let (listener, listen_error) = net.tcp_listen(endpoint, 1u32)
    if listen_error != ok { ret listen_error }
    var https_server_entropy: [64]u8 = zero
    var https_client_entropy: [64]u8 = zero
    entropy_at = 0usize
    while entropy_at < 64usize {
        https_server_entropy[entropy_at] = u8(64usize + entropy_at)
        https_client_entropy[entropy_at] = u8(192usize + entropy_at)
        entropy_at += 1usize
    }
    let https_server_config = tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: client_protocols[0..], entropy: https_server_entropy[0..] }
    var https_server = HttpServerJob { listener: listener, config: https_server_config, failed: false }
    let (bound, bound_error) = os.socket_local_address(https_server.listener)
    if bound_error != ok { os.exit(33i32) }
    endpoint.port = bound.port
    let (https_thread, https_thread_error) = thread.spawn[HttpServerJob](serve_https, &https_server, 8388608usize)
    if https_thread_error != ok { os.exit(34i32) }
    var request: http.Request = zero
    request.method = .Get
    request.target = "/secure"
    request.version = .Http11
    let https_client_config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: client_protocols[0..], entropy: https_client_entropy[0..], now: time.Timestamp { nanos: 1780272000000000000i64 } }
    let (response, request_error) = http.request_tls(a, endpoint, https_client_config, &request, http_limits())
    let https_join_error = thread.join(https_thread)
    if https_join_error != ok || https_server.failed || request_error != ok || response.status != 200u16 || !same_bytes(response.body, "secure") { os.exit(35i32) }

    var stream_server_entropy: [64]u8 = zero
    var stream_client_entropy: [64]u8 = zero
    entropy_at = 0usize
    while entropy_at < 64usize {
        stream_server_entropy[entropy_at] = u8(16usize + entropy_at)
        stream_client_entropy[entropy_at] = u8(128usize + entropy_at)
        entropy_at += 1usize
    }
    https_server.config = tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: client_protocols[0..], entropy: stream_server_entropy[0..] }
    https_server.failed = false
    let (stream_thread, stream_thread_error) = thread.spawn[HttpServerJob](serve_https, &https_server, 8388608usize)
    if stream_thread_error != ok { os.exit(37i32) }
    let stream_client_config = tls.ClientConfig { server_name: "example.com", trust_roots: mid_der, alpn: client_protocols[0..], entropy: stream_client_entropy[0..], now: time.Timestamp { nanos: 1780272000000000000i64 } }
    var no_control: cancel.Control = zero
    let (response_stream0, response_stream_error) = http.request_tls_stream(a, endpoint, stream_client_config, &request, http_limits(), no_control)
    if response_stream_error != ok { os.exit(38i32) }
    var response_stream = response_stream0
    if http.response_head(&response_stream).status != 200u16 { os.exit(39i32) }
    var streamed_body: [6]u8 = zero
    var streamed_at = 0usize
    while streamed_at < streamed_body.len {
        var end = streamed_at + 2usize
        if end > streamed_body.len { end = streamed_body.len }
        let (count, stream_read_error) = http.response_read(&response_stream, streamed_body[streamed_at..end])
        if stream_read_error != ok || count == 0usize { os.exit(40i32) }
        streamed_at += count
    }
    if !same_bytes(streamed_body[0..], "secure") || http.response_close(&response_stream) != ok || http.response_close(&response_stream) != ok { os.exit(41i32) }
    let stream_join_error = thread.join(stream_thread)
    if stream_join_error != ok || https_server.failed { os.exit(42i32) }
    if net.close(https_server.listener) != ok { os.exit(36i32) }
    ret ok
}
