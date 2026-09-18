use e.mem
use e.net
use e.io
use e.os
use e.str

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
    let (client, connect_error) = net.tcp_connect(local)
    if connect_error != ok { ret connect_error }
    var client_socket = client
    defer let _ = net.close(client_socket)
    let (served, peer, accept_error) = net.tcp_accept(listener)
    if accept_error != ok { ret accept_error }
    var served_socket = served
    defer let _ = net.close(served_socket)
    if peer.port == 0u16 { ret Failed }
    var sink = net.writer(&client_socket)
    if io.write_all(&sink, "hello") != ok { ret Failed }
    var source = net.reader(&served_socket)
    var greeting: [5]u8 = zero
    if io.read_exact(&source, greeting[0..]) != ok || !str.eq(greeting[0..], "hello") { ret Failed }
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
