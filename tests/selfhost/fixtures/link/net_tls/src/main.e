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
use e.crypto.sign as sign
use e.crypto.x509 as x509
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
    let coalesced = "\x08\x00\x00\x00\x14\x00\x00\x00"
    var coalesced_record: [30]u8 = zero
    var coalesced_keys = record_keys0
    let (coalesced_len, coalesced_seal_error) = tls.seal_record(&coalesced_keys, 22u8, coalesced, coalesced_record[0..])
    if coalesced_seal_error != ok || coalesced_len != 30usize { os.exit(47i32) }
    var framed: [36]u8 = zero
    framed[0] = 20u8
    framed[1] = 3u8
    framed[2] = 3u8
    framed[4] = 1u8
    framed[5] = 1u8
    mem.copy[u8](framed[6usize..], coalesced_record[0..])
    var framed_source_state = io.SliceReader { data: framed[0..], off: 0usize }
    let framed_source = io.slice_reader(&framed_source_state)
    var framed_sink_state = io.SliceWriter { data: sink_bytes[0..0], off: 0usize }
    let framed_sink = io.slice_writer(&framed_sink_state)
    let (framed_stream, framed_create_error) = tls.client(a, framed_source, framed_sink, client_config)
    if framed_create_error != ok { os.exit(48i32) }
    var framed_read_keys = record_keys0
    var messages: tls.HandshakeReader = zero
    messages.state = mem.cast[*tls.State](framed_stream.state)
    messages.keys = &framed_read_keys
    var first_message: [4]u8 = zero
    var second_message: [4]u8 = zero
    let (first_len, first_error) = tls.read_handshake_message(&messages, first_message[0..])
    let (second_len, second_error) = tls.read_handshake_message(&messages, second_message[0..])
    if first_error != ok || second_error != ok || first_len != 4usize || second_len != 4usize || !same_bytes(first_message[0..], coalesced[..4usize]) || !same_bytes(second_message[0..], coalesced[4usize..]) { os.exit(49i32) }

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
    // ed25519, ecdsa_secp256r1_sha256, ecdsa_secp384r1_sha384, rsa_pss_rsae_sha256/384/512 and
    // rsa_pkcs1_sha256/384/512 (D1644, D2249).
    let p256_offer = "\x00\x0d\x00\x14\x00\x12\x08\x07\x04\x03\x05\x03\x08\x04\x08\x05\x08\x06\x04\x01\x05\x01\x06\x01"
    var offer_at = 0usize
    var has_p256_offer = false
    while offer_at + p256_offer.len <= client_hello_len {
        if same_bytes(client_hello[offer_at..offer_at + p256_offer.len], p256_offer) { has_p256_offer = true }
        offer_at += 1usize
    }
    if !has_p256_offer { os.exit(45i32) }
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
    if certificate_verify_error != ok || certificate_verify_len != 72usize || tls.verify_certificate_verify(a, certificate_set.leaf, transcript_hash, certificate_verify[0..]) != ok { os.exit(18i32) }
    certificate_verify[20] = certificate_verify[20] ^ 1u8
    if tls.verify_certificate_verify(a, certificate_set.leaf, transcript_hash, certificate_verify[0..]) != tls.InvalidCertificate { os.exit(19i32) }
    let p256_public_bytes = "\x04\x60\xfe\xd4\xba\x25\x5a\x9d\x31\xc9\x61\xeb\x74\xc6\x35\x6d\x68\xc0\x49\xb8\x92\x3b\x61\xfa\x6c\xe6\x69\x62\x2e\x60\xf2\x9f\xb6\x79\x03\xfe\x10\x08\xb8\xbc\x99\xa4\x1a\xe9\xe9\x56\x28\xbc\x64\xf2\xf1\xb2\x0c\x2d\x7e\x9f\x51\x77\xa3\xc2\x94\xd4\x46\x22\x99"
    var p256_public: sign.P256PublicKey = zero
    var p256_at = 0usize
    while p256_at < 65usize {
        p256_public.bytes[p256_at] = p256_public_bytes[p256_at]
        p256_at += 1usize
    }
    var p256_certificate: x509.Certificate = zero
    p256_certificate.public_key = x509.PublicKey { P256: p256_public }
    let p256_certificate_verify = "\x0f\x00\x00\x4a\x04\x03\x00\x46\x30\x44\x02\x20\x39\x5c\xd2\x8b\x80\x4c\x7d\x0e\x96\xba\x11\x0a\x21\x77\xcc\x10\x06\x68\xf9\x7d\x72\x0f\x16\x9b\x39\x51\xea\xbb\xac\xc5\xb4\x94\x02\x20\x1c\x70\x56\x28\x9e\x8e\xb1\x8d\xeb\xf4\x13\x03\x96\xdd\xef\x52\x16\x5e\x2f\x17\xb2\x4d\xd2\xa6\xb4\x00\xaf\x6b\xb3\x02\x1f\x75"
    if tls.verify_certificate_verify(a, p256_certificate, transcript_hash, p256_certificate_verify) != ok { os.exit(46i32) }
    // RSA-PSS (D1644): OpenSSL's rsa_pss_rsae_sha256 signature, salt 32, over the same zero
    // transcript, by the key of a self-signed RSA certificate.
    let (rsa_certificate, rsa_parse_error) = x509.parse(a, "\x30\x82\x03\x12\x30\x82\x01\xfa\xa0\x03\x02\x01\x02\x02\x01\x07\x30\x0d\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0b\x05\x00\x30\x16\x31\x14\x30\x12\x06\x03\x55\x04\x03\x0c\x0b\x72\x73\x61\x2e\x65\x78\x61\x6d\x70\x6c\x65\x30\x1e\x17\x0d\x32\x36\x30\x39\x32\x38\x31\x39\x33\x37\x33\x30\x5a\x17\x0d\x33\x36\x30\x39\x32\x35\x31\x39\x33\x37\x33\x30\x5a\x30\x16\x31\x14\x30\x12\x06\x03\x55\x04\x03\x0c\x0b\x72\x73\x61\x2e\x65\x78\x61\x6d\x70\x6c\x65\x30\x82\x01\x22\x30\x0d\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x01\x05\x00\x03\x82\x01\x0f\x00\x30\x82\x01\x0a\x02\x82\x01\x01\x00\xb0\xf9\x4c\x97\xdd\x8d\x14\x61\x7b\x84\xfe\x0b\x78\xc1\x93\x22\x01\xcc\x2a\x1a\x96\x6e\xb6\x8f\x40\x2e\x66\x03\x9c\xe4\x3d\x1f\x00\xfb\x07\xb9\x8e\x16\xbf\x25\x54\x1f\x8e\xde\x1e\xfd\x4e\x5d\xb8\xab\xc6\xfe\x39\x99\xca\xc7\xf8\x01\x42\x5f\x3b\x8f\xb0\xfa\x3a\xa6\x98\x17\xcc\x6c\xb9\x33\xf1\x36\xc6\x55\xb6\x8b\x4e\xd3\x07\xe6\x99\xe2\x0f\x3c\xce\xf9\x84\x48\xf1\x31\x7f\x7e\xac\xe5\xc4\x9d\x7f\xd6\x47\x91\x84\x7c\xed\x03\x17\xa1\xe3\xaa\x9b\x0b\x84\x52\x7d\x38\xe7\xce\xe9\xbe\xd1\x0b\x88\xd2\xd9\xe3\x56\x9f\xc2\xad\x82\x9f\x56\x19\xd0\xba\x8a\xfd\x03\x29\x25\x61\x0d\x39\x79\x3d\x8a\x1b\x73\xe7\x59\x3c\xfa\x25\x5b\xab\x88\xcd\x25\x0f\x8e\x52\x92\x12\x2d\x31\x0d\x1c\xe8\x75\x82\x6a\x2f\x09\xa3\x66\x90\x56\x6f\x02\x51\x89\x2f\x80\x35\xc9\xfc\xb9\xbe\x2c\x0f\x02\x24\x34\x58\xc9\xa9\xed\x98\x90\x10\x4e\xbb\xef\x9d\xbb\x19\x69\x06\xe2\x64\x38\xa2\x45\x91\x33\x81\x9a\xf6\x4c\xf4\x61\x70\xdc\x5b\x7a\x55\x68\x20\x37\x5d\xc6\xb5\x9f\x06\x92\xb0\x74\x0a\x32\xc7\xc2\x60\x60\xd4\x63\x95\xfd\x06\x2a\x95\x3d\xc7\xdd\x53\x27\x02\x03\x01\x00\x01\xa3\x6b\x30\x69\x30\x1d\x06\x03\x55\x1d\x0e\x04\x16\x04\x14\x48\xeb\x1d\x7a\x63\xff\x97\xf0\x76\x59\x38\xc2\x62\x98\x22\x4d\xfd\x55\xe6\xb3\x30\x1f\x06\x03\x55\x1d\x23\x04\x18\x30\x16\x80\x14\x48\xeb\x1d\x7a\x63\xff\x97\xf0\x76\x59\x38\xc2\x62\x98\x22\x4d\xfd\x55\xe6\xb3\x30\x0f\x06\x03\x55\x1d\x13\x01\x01\xff\x04\x05\x30\x03\x01\x01\xff\x30\x16\x06\x03\x55\x1d\x11\x04\x0f\x30\x0d\x82\x0b\x72\x73\x61\x2e\x65\x78\x61\x6d\x70\x6c\x65\x30\x0d\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x01\x0b\x05\x00\x03\x82\x01\x01\x00\x2d\x12\x0e\x17\x8e\x33\x4f\xb4\xe4\xeb\x2a\xcb\xf2\x94\x2d\x97\x45\x36\xc7\xeb\x76\xf7\x9c\x8b\xc3\x8e\xfd\x60\x12\x42\xd6\xed\x3d\xd7\xeb\x6c\x23\xbe\x5f\x18\x92\xc2\xb4\x3d\x58\x30\x93\x98\x26\x09\x21\x29\xc4\xe7\xa9\xd8\x6e\x49\xc9\xed\xe7\xb5\x34\x86\x1f\xc6\x97\x22\x6c\xd0\x8b\x0b\x81\x54\xee\x2b\x48\xae\xe1\x36\x2e\x95\x95\xa8\x9a\xd6\xe1\x2e\x3c\x99\x83\xc9\x44\x3d\x04\x64\xac\x4c\x4d\x66\xfb\xce\xb2\x35\xad\x06\x40\xee\xf6\x80\x06\xad\x21\xd7\x49\x9b\xd1\x3d\xbe\xcd\xb6\x42\xa9\xdc\x93\x95\xf2\xd0\xb2\x18\x99\xfc\xba\xc3\xda\x14\xaa\x6d\xee\xa3\x27\x18\x71\xd2\xd8\x87\x0f\xb1\x58\x74\x31\x85\x78\xb1\xa8\x25\x30\x91\xc6\x83\x8c\x3c\xc9\x77\x7d\x42\x21\x16\x51\x70\x87\xf8\x83\x9d\xb5\xb7\x58\x39\x44\xf2\x4a\x7f\xc9\xe6\x21\xc3\x46\xd6\x5f\x68\xe2\x18\x30\x7e\x05\x80\x05\x40\x07\xc9\x14\xc1\xcf\xba\x2a\xe8\x55\x58\x1a\x3f\x75\xd5\x0f\x8d\x48\x4c\xd7\x9d\x44\x6f\xcd\x1f\x3e\x23\x2f\x3d\x4b\x5f\xf5\xb8\xb1\xe7\xb4\x62\x3b\x2a\xcb\x70\x7a\x19\xab\xbc\x7a\x8b\x1d\xe3\x80\xe6\xc6\x4b\xfa\x01\xe7\x96\x58\xfa")
    if rsa_parse_error != ok { os.exit(50i32) }
    let rsa_certificate_verify = "\x0f\x00\x01\x04\x08\x04\x01\x00\x56\x25\x97\x5c\x24\x58\x91\x64\xdc\x40\x93\x24\x9d\xef\x92\x89\xd8\x79\x8e\xb2\x4c\x98\xf0\x0f\xdf\x0e\xc0\x62\xe3\xb7\xc3\xfa\x1b\xc3\xd3\x4d\xde\x91\x59\x4a\xdb\x8f\x73\xc8\xc6\xce\x25\xaa\x8a\xfa\xe3\x47\x55\xf3\x9a\x47\x56\xac\x06\x01\x2f\xaa\x4d\x4f\x77\xe9\xe0\xcd\x34\x21\xf4\x00\xa7\xaa\xfb\x47\x3f\xc3\x00\xd2\x91\x15\xcc\xd0\xef\x5d\x5c\x00\xda\x9a\x80\xee\x14\xcc\x6a\xaa\xe8\x93\x46\x98\x38\xc6\x2c\x18\x7a\x5b\x03\x16\xb1\x0a\x64\x3f\xa5\x58\xf4\xb3\xaf\xc8\x7e\x8a\x9a\x83\x60\x50\x73\xf6\x1f\x89\x3b\xe9\x0d\xde\x65\x47\x25\x43\xcc\xa4\x05\x10\xf1\xfd\x8a\xca\x25\x82\x4e\x3d\x46\xe6\xa3\x76\x18\xac\x69\xff\x45\x7d\xd1\x48\x52\xe2\x67\xf9\xe6\x58\xb5\xd2\xdf\xd2\x8f\x03\x19\x82\x05\x17\xaf\x9d\x4f\x29\x15\x0a\x84\xd9\x79\xea\x7a\x57\xda\x6a\x75\x8e\x0c\x48\x04\xbc\x70\xc7\xe9\x03\x6f\x4f\x94\xa6\x2d\xb2\x4f\x49\xf8\xcf\x75\x6d\x24\xdc\x14\x40\x3d\xe3\x88\x01\x39\x10\x1c\xdd\x3c\x83\x5a\x2b\xd5\x7e\xdd\x56\xb8\x11\xdf\x08\xdf\x25\xf4\xff\x37\xae\x25\x4a\x38\x85\x2d\xea\x9d\x56\xfa\xef\xef\x0d\x7d\x84"
    if tls.verify_certificate_verify(a, rsa_certificate, transcript_hash, rsa_certificate_verify) != ok { os.exit(50i32) }
    var rsa_forged_verify: [264]u8 = zero
    var rsa_at = 0usize
    while rsa_at < 264usize {
        rsa_forged_verify[rsa_at] = rsa_certificate_verify[rsa_at]
        rsa_at += 1usize
    }
    rsa_forged_verify[100] = rsa_forged_verify[100] ^ 1u8
    if tls.verify_certificate_verify(a, rsa_certificate, transcript_hash, rsa_forged_verify[0..]) != tls.InvalidCertificate { os.exit(51i32) }
    // The same signature under PKCS#1 v1.5's code, which TLS 1.3 forbids in CertificateVerify.
    rsa_forged_verify[100] = rsa_forged_verify[100] ^ 1u8
    rsa_forged_verify[4] = 4u8
    rsa_forged_verify[5] = 1u8
    if tls.verify_certificate_verify(a, rsa_certificate, transcript_hash, rsa_forged_verify[0..]) != tls.Protocol { os.exit(52i32) }
    // After the handshake a record of whole NewSessionTicket messages is read past (D1644);
    // anything else in a handshake record is still a protocol error.
    if !tls.only_session_tickets("\x04\x00\x00\x02ab") || !tls.only_session_tickets("\x04\x00\x00\x01a\x04\x00\x00\x00") { os.exit(53i32) }
    if tls.only_session_tickets("") || tls.only_session_tickets("\x04\x00\x00\x02a") || tls.only_session_tickets("\x04\x00\x00\x01a\x18\x00\x00\x01\x00") { os.exit(54i32) }

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
