// The poller must report both of two loopback datagram receivers every time: a level-triggered kqueue filter lost one in
// roughly a tenth to a third of the rounds on the Mac runners. 2000 rounds, each waiting up to a second for both.
use e.mem
use e.os

fn loopback() -> os.SocketAddress {
    var address: os.SocketAddress = zero
    address.family = .Ip4
    address.bytes[0usize] = 127u8
    address.bytes[3usize] = 1u8
    ret address
}

fn bind_ephemeral(s: os.Socket) -> u16 {
    var address = loopback()
    address.port = 0u16
    if os.socket_bind(s, address) != ok { os.exit(12i32) }
    let (local, local_error) = os.socket_local_address(s)
    if local_error != ok { os.exit(13i32) }
    ret local.port
}

fn main(a: *mem.Arena) -> err {
    var round = 0usize
    while round < 1500usize {
        let (poller, poller_error) = os.poller_open(a)
        if poller_error != ok { os.exit(10i32) }
        let (first, first_error) = os.socket_open(.Ip4, .Datagram)
        if first_error != ok { os.exit(11i32) }
        let (second, second_error) = os.socket_open(.Ip4, .Datagram)
        if second_error != ok { os.exit(11i32) }
        let (sender, sender_error) = os.socket_open(.Ip4, .Datagram)
        if sender_error != ok { os.exit(11i32) }
        let first_port = bind_ephemeral(first)
        let second_port = bind_ephemeral(second)
        var readable: os.PollInterest = zero
        readable.readable = true
        if os.poller_register(poller, os.socket_handle(first), 1usize, readable) != ok { os.exit(15i32) }
        if os.poller_register(poller, os.socket_handle(second), 2usize, readable) != ok { os.exit(16i32) }
        var payload: [1]u8 = zero
        payload[0usize] = 65u8
        var to_first = loopback()
        to_first.port = first_port
        var to_second = loopback()
        to_second.port = second_port
        let (sent_one, sent_one_error) = os.socket_send_to(sender, to_first, payload[..])
        let (sent_two, sent_two_error) = os.socket_send_to(sender, to_second, payload[..])
        var events: [8]os.PollEvent = zero
        var seen_first = false
        var seen_second = false
        var waits = 0usize
        while !(seen_first && seen_second) && waits < 5usize {
            let (got, wait_error) = os.poller_wait(poller, events[..], 200000000i64)
            if wait_error != ok { os.exit(17i32) }
            var at = 0usize
            while at < got {
                if events[at].token == 1usize { seen_first = true }
                if events[at].token == 2usize { seen_second = true }
                at += 1usize
            }
            waits += 1usize
        }
        if !(seen_first && seen_second) { os.exit(30i32) }
        // What is unread is reported again, whichever wait comes next.
        let (again, again_error) = os.poller_wait(poller, events[..], 1000000i64)
        if again_error != ok || again != 2usize { os.exit(31i32) }
        var sink: [4]u8 = zero
        let (n1, f1, e1) = os.socket_receive_from(first, sink[..])
        let (n2, f2, e2) = os.socket_receive_from(second, sink[..])
        let (drained, drained_error) = os.poller_wait(poller, events[..], 1000000i64)
        if drained_error != ok || drained != 0usize { os.exit(32i32) }
        let closed_poller = os.poller_close(poller)
        let closed_a = os.socket_close(first)
        let closed_b = os.socket_close(second)
        let closed_c = os.socket_close(sender)
        round += 1usize
    }
    ret ok
}
