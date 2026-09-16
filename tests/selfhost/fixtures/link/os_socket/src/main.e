// `e.os`'s socket transport over the loopback interface: a real TCP connection and a real
// UDP datagram, both inside one process and one thread.
//
// Nothing here waits on something that has not already happened. A connect into a
// listening socket's backlog completes without the other end having accepted, and every
// receive follows a send that already returned -- so a single thread is enough and the
// fixture cannot hang waiting for a peer that is itself.
//
// Every port is the host's to choose: a bind to port zero and a `socket_local_address` to
// learn what it gave, so nothing here depends on a particular port being free.

use e.mem
use e.os


fn loopback() -> os.SocketAddress {
    var address: os.SocketAddress = zero
    address.family = .Ip4
    address.bytes[0usize] = 127u8
    address.bytes[3usize] = 1u8
    ret address
}

// Port zero asks the host to choose, and `socket_local_address` is how the choice comes
// back. Nothing here guesses a port or hopes one is free, so nothing here can collide with
// whatever else the machine is running.
fn bind_ephemeral(s: os.Socket) -> (u16, err) {
    var address = loopback()
    address.port = 0u16
    let bind_error = os.socket_bind(s, address)
    if bind_error != ok { ret (0u16, bind_error) }
    let (local, local_error) = os.socket_local_address(s)
    if local_error != ok { ret (0u16, local_error) }
    // A chosen port is never zero, so this is also the check that the report is real.
    if local.port == 0u16 { ret (0u16, os.Failed) }
    ret (local.port, ok)
}

fn main(a: *mem.Arena) -> err {
    // --- A stream, both directions, and end of stream.
    let (listener, listener_error) = os.socket_open(.Ip4, .Stream)
    if listener_error != ok { os.exit(10i32) }
    let (port, listen_bind_error) = bind_ephemeral(listener)
    if listen_bind_error != ok { os.exit(11i32) }
    if os.socket_listen(listener, 4u32) != ok { os.exit(12i32) }

    let (client, client_error) = os.socket_open(.Ip4, .Stream)
    if client_error != ok { os.exit(13i32) }
    var server_address = loopback()
    server_address.port = port
    if os.socket_connect(client, server_address) != ok { os.exit(14i32) }

    let (served, peer, accept_error) = os.socket_accept(listener)
    if accept_error != ok { os.exit(15i32) }
    // The other end of a loopback connection is loopback, on some port the host chose.
    if peer.family != .Ip4 { os.exit(16i32) }
    if peer.bytes[0usize] != 127u8 { os.exit(17i32) }
    if peer.bytes[3usize] != 1u8 { os.exit(18i32) }
    if peer.port == 0u16 { os.exit(19i32) }

    var greeting: [5]u8 = zero
    greeting[0usize] = 104u8
    greeting[1usize] = 101u8
    greeting[2usize] = 108u8
    greeting[3usize] = 108u8
    greeting[4usize] = 111u8
    let (sent, send_error) = os.socket_send(client, greeting[..])
    if send_error != ok { os.exit(20i32) }
    if sent != 5usize { os.exit(21i32) }

    var inbox: [16]u8 = zero
    let (taken, receive_error) = os.socket_receive(served, inbox[..])
    if receive_error != ok { os.exit(22i32) }
    if taken != 5usize { os.exit(23i32) }
    var at = 0usize
    while at < 5usize {
        if inbox[at] != greeting[at] { os.exit(24i32) }
        at += 1usize
    }

    // Back the other way, so it is a connection and not a pipe.
    let (echoed, echo_error) = os.socket_send(served, inbox[0usize..taken])
    if echo_error != ok { os.exit(25i32) }
    if echoed != 5usize { os.exit(26i32) }
    var reply: [16]u8 = zero
    let (returned, return_error) = os.socket_receive(client, reply[..])
    if return_error != ok { os.exit(27i32) }
    if returned != 5usize { os.exit(28i32) }
    at = 0usize
    while at < 5usize {
        if reply[at] != greeting[at] { os.exit(29i32) }
        at += 1usize
    }

    // Shutting the writing half is seen at the other end as end of stream: zero bytes and
    // no error, which is the one answer a reader must not confuse with a failure.
    if os.socket_shutdown(client, .Write) != ok { os.exit(30i32) }
    let (finished, finished_error) = os.socket_receive(served, inbox[..])
    if finished_error != ok { os.exit(31i32) }
    if finished != 0usize { os.exit(32i32) }

    if os.socket_close(served) != ok { os.exit(33i32) }
    if os.socket_close(client) != ok { os.exit(34i32) }
    if os.socket_close(listener) != ok { os.exit(35i32) }

    // --- A datagram, where the sender's address arrives with the data.
    let (receiver, receiver_error) = os.socket_open(.Ip4, .Datagram)
    if receiver_error != ok { os.exit(40i32) }
    let (receiver_port, receiver_bind_error) = bind_ephemeral(receiver)
    if receiver_bind_error != ok { os.exit(41i32) }

    let (sender, sender_error) = os.socket_open(.Ip4, .Datagram)
    if sender_error != ok { os.exit(42i32) }
    // The sender is bound too, so it has a port for the receiver to see.
    let (sender_port, sender_bind_error) = bind_ephemeral(sender)
    if sender_bind_error != ok { os.exit(43i32) }

    var destination = loopback()
    destination.port = receiver_port
    let (posted, post_error) = os.socket_send_to(sender, destination, greeting[..])
    if post_error != ok { os.exit(44i32) }
    if posted != 5usize { os.exit(45i32) }

    var datagram: [16]u8 = zero
    let (arrived, source, arrive_error) = os.socket_receive_from(receiver, datagram[..])
    if arrive_error != ok { os.exit(46i32) }
    if arrived != 5usize { os.exit(47i32) }
    at = 0usize
    while at < 5usize {
        if datagram[at] != greeting[at] { os.exit(48i32) }
        at += 1usize
    }
    // The address that came back is the sender's, which is what a datagram carries and a
    // stream does not.
    if source.family != .Ip4 { os.exit(49i32) }
    if source.bytes[0usize] != 127u8 { os.exit(50i32) }
    if source.port != sender_port { os.exit(51i32) }

    // --- Non-blocking, which is only observable when there is nothing to read.
    if os.socket_set_nonblocking(receiver, true) != ok { os.exit(60i32) }
    let (nothing, no_source, nothing_error) = os.socket_receive_from(receiver, datagram[..])
    if nothing_error != os.WouldBlock { os.exit(61i32) }
    // And turning it off again is visible the same way: the flag is read back through
    // behaviour, because nothing here reports it directly.
    if os.socket_set_nonblocking(receiver, false) != ok { os.exit(62i32) }
    let (posted_again, post_again_error) = os.socket_send_to(sender, destination, greeting[..])
    if post_again_error != ok { os.exit(63i32) }
    if posted_again != 5usize { os.exit(64i32) }
    let (arrived_again, second_source, arrive_again_error) = os.socket_receive_from(receiver, datagram[..])
    if arrive_again_error != ok { os.exit(65i32) }
    if arrived_again != 5usize { os.exit(66i32) }

    // The handle is the socket under another name, which is what lets a poller take it;
    // the socket's own bits are `e.os`'s alone (D350).
    if os.socket_handle(receiver).raw == 0usize { os.exit(70i32) }

    if os.socket_close(sender) != ok { os.exit(71i32) }
    if os.socket_close(receiver) != ok { os.exit(72i32) }
    ret ok
}
