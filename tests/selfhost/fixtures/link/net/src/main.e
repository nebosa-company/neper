use e.mem
use e.net
use e.cancel
use e.io
use e.os
use e.str
use e.time

error Failed

fn roundtrip(text: str, expected: str) -> bool {
    let (address, parse_error) = net.parse_ip(text)
    if parse_error != ok { ret false }
    var output: [64]u8 = zero
    let (formatted, format_error) = net.format_ip(address, output[0..])
    ret format_error == ok && str.eq(formatted, expected)
}

fn main(a: *mem.Arena) -> err {
    if !roundtrip("127.0.0.1", "127.0.0.1") { ret Failed }
    if !roundtrip("255.0.10.42", "255.0.10.42") { ret Failed }
    if !roundtrip("::", "::") { ret Failed }
    if !roundtrip("0:0:0:0:0:0:0:1", "::1") { ret Failed }
    if !roundtrip("2001:0DB8:0:0:1:0:0:1", "2001:db8::1:0:0:1") { ret Failed }
    if !roundtrip("2001:db8:0:1:0:0:0:1", "2001:db8:0:1::1") { ret Failed }
    if !roundtrip("::ffff:127.0.0.1", "::ffff:7f00:1") { ret Failed }
    if !roundtrip("fe80::1%4294967295", "fe80::1%4294967295") { ret Failed }

    let invalid = [10]str{ "", "1.2.3", "1.2.3.256", "111111111111.2.3.4", "01.2.3.4", ":1", "1::2::3", "1:2:3:4:5:6:7:8::", "fe80::1%eth0", "fe80::1%4294967296" }
    var at = 0usize
    while at < invalid.len {
        let (address, parse_error) = net.parse_ip(invalid[at])
        if parse_error != net.Failed { ret Failed }
        at += 1usize
    }

    let (address, parse_error) = net.parse_ip("2001:db8::1")
    if parse_error != ok { ret parse_error }
    var short: [10]u8 = zero
    let (text, short_error) = net.format_ip(address, short[0..])
    if short_error != net.Failed || text.len != 0usize { ret Failed }

    // Resolver output carries the caller's port and the same portable address value.
    let (resolved, resolve_error) = net.resolve(a, "localhost", 8080u16, .Ip4)
    if resolve_error != ok || resolved.len == 0usize || resolved[0usize].port != 8080u16 { ret Failed }
    var no_control: cancel.Control = zero
    let (controlled_resolved, controlled_resolve_error) = net.resolve_with_control(a, "localhost", 8080u16, .Ip4, no_control)
    if controlled_resolve_error != ok || controlled_resolved.len == 0usize { ret Failed }

    let (observed, clock_error) = time.monotonic()
    if clock_error != ok { ret clock_error }
    var live_control = cancel.Control { token: nil, deadline: time.instant_add(observed, time.Duration { nanos: 1000000000i64 }), has_deadline: true }
    let (unsupported_resolved, unsupported_resolve_error) = net.resolve_with_control(a, "localhost", 8080u16, .Ip4, live_control)
    if unsupported_resolve_error != os.Unsupported { ret Failed }
    var stopped_token = cancel.token()
    cancel.request(&stopped_token)
    let stopped_control = cancel.Control { token: &stopped_token, deadline: observed, has_deadline: true }
    let (stopped_resolved, stopped_resolve_error) = net.resolve_with_control(a, "localhost", 8080u16, .Ip4, stopped_control)
    if stopped_resolve_error != cancel.Cancelled { ret Failed }

    let (loopback_address, loopback_error) = net.parse_ip("127.0.0.1")
    if loopback_error != ok { ret loopback_error }
    var local = net.Endpoint { address: loopback_address, port: 0u16 }

    // A real loopback TCP connection through the portable wrappers. e.os reports the
    // host-selected ephemeral port because the planned e.net surface has no local-address call.
    let (listener, listen_error) = net.tcp_listen(local, 4u32)
    if listen_error != ok { ret listen_error }
    defer let _ = net.close(listener)
    let (bound, bound_error) = os.socket_local_address(listener)
    if bound_error != ok || bound.port == 0u16 { ret Failed }
    local.port = bound.port
    let (duplicate, duplicate_error) = net.tcp_listen(local, 1u32)
    if duplicate_error == ok {
        let unused = net.close(duplicate)
        ret Failed
    }
    if duplicate_error != net.AddressInUse { ret Failed }
    let (client, connect_error) = net.tcp_connect_with_control(local, no_control)
    if connect_error != ok { ret connect_error }
    var client_socket = client
    defer let _ = net.close(client_socket)
    let (served, peer, accept_error) = net.tcp_accept(listener)
    if accept_error != ok { ret accept_error }
    var served_socket = served
    defer let _ = net.close(served_socket)
    if peer.port == 0u16 { ret Failed }
    let (cancelled_socket, cancelled_connect_error) = net.tcp_connect_with_control(local, stopped_control)
    if cancelled_connect_error == ok {
        let unused = net.close(cancelled_socket)
        ret Failed
    }
    if cancelled_connect_error != cancel.Cancelled { ret Failed }
    var sink = net.writer(&client_socket)
    if io.write_all(&sink, "hello") != ok { ret Failed }
    var source = net.reader(&served_socket)
    var greeting: [5]u8 = zero
    if io.read_exact(&source, greeting[0..]) != ok || !str.eq(greeting[0..], "hello") { ret Failed }

    let (controlled_sent, controlled_send_error) = net.send_with_control(client_socket, "world", no_control)
    if controlled_send_error != ok || controlled_sent != 5usize { ret Failed }
    var controlled_bytes: [5]u8 = zero
    let (controlled_taken, controlled_receive_error) = net.receive_with_control(served_socket, controlled_bytes[0..], no_control)
    if controlled_receive_error != ok || controlled_taken != 5usize || !str.eq(controlled_bytes[0..], "world") { ret Failed }

    let (before_timeout, timeout_clock_error) = time.monotonic()
    if timeout_clock_error != ok { ret timeout_clock_error }
    let timeout_control = cancel.Control { token: nil, deadline: time.instant_add(before_timeout, time.Duration { nanos: 5000000i64 }), has_deadline: true }
    let (timed_count, timed_error) = net.receive_with_control(served_socket, controlled_bytes[0..], timeout_control)
    if timed_error != net.Timeout || timed_count != 0usize { ret Failed }
    let (after_timeout, after_timeout_error) = time.monotonic()
    if after_timeout_error != ok { ret after_timeout_error }
    let elapsed = time.instant_diff(after_timeout, before_timeout)
    if elapsed.nanos < 0i64 || elapsed.nanos > 100000000i64 { ret Failed }
    let cancelled_control = cancel.Control { token: &stopped_token, deadline: observed, has_deadline: false }
    let (cancelled_count, cancelled_error) = net.receive_with_control(served_socket, controlled_bytes[0..], cancelled_control)
    if cancelled_error != cancel.Cancelled || cancelled_count != 0usize { ret Failed }

    if net.shutdown(client_socket, .Write) != ok { ret Failed }
    var ended: [1]u8 = zero
    let (end_count, end_error) = io.read(&source, ended[0..])
    if end_error != io.End || end_count != 0usize { ret Failed }
    // Datagram endpoints retain the sender's portable address and port.
    local.port = 0u16
    let (receiver, receiver_error) = net.udp_bind(local)
    if receiver_error != ok { ret receiver_error }
    defer let _ = net.close(receiver)
    let (receiver_bound, receiver_bound_error) = os.socket_local_address(receiver)
    if receiver_bound_error != ok || receiver_bound.port == 0u16 { ret Failed }
    let (sender, sender_error) = net.udp_bind(local)
    if sender_error != ok { ret sender_error }
    defer let _ = net.close(sender)
    let (sender_bound, sender_bound_error) = os.socket_local_address(sender)
    if sender_bound_error != ok || sender_bound.port == 0u16 { ret Failed }
    local.port = receiver_bound.port
    let (sent, send_error) = net.send_to(sender, local, "ping")
    if send_error != ok || sent != 4usize { ret Failed }
    var datagram: [8]u8 = zero
    let (taken, from, receive_error) = net.receive_from(receiver, datagram[0..])
    if receive_error != ok || taken != 4usize || !str.eq(datagram[..taken], "ping") || from.port != sender_bound.port { ret Failed }
    ret ok
}
