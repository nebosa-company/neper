// `e.os`'s readiness poller, over two loopback datagram sockets so the readiness is real.
//
// The poller is written for hosts that have a kernel object holding the registration set.
// Where there is none it reports `Unsupported` from `poller_open`, and this fixture stops
// there rather than pretending: that one answer, and only that one, ends the run happily.

use e.mem
use e.os

const FIRST_PORT: u16 = 47901u16
const LAST_PORT: u16 = 47940u16

const READ_TOKEN: usize = 4242usize
const WRITE_TOKEN: usize = 9182usize

fn loopback() -> os.SocketAddress {
    var address: os.SocketAddress = zero
    address.family = .Ip4
    address.bytes[0usize] = 127u8
    address.bytes[3usize] = 1u8
    ret address
}

fn bind_somewhere(s: os.Socket, from: u16) -> (u16, err) {
    var port = from
    while port <= LAST_PORT {
        var address = loopback()
        address.port = port
        let bind_error = os.socket_bind(s, address)
        if bind_error == ok { ret (port, ok) }
        if bind_error != os.Exists { ret (0u16, bind_error) }
        port += 1u16
    }
    ret (0u16, os.Failed)
}

fn main(a: *mem.Arena) -> err {
    let (poller, poller_error) = os.poller_open(a)
    if poller_error == os.Unsupported { ret ok }
    if poller_error != ok { os.exit(10i32) }

    // Two receivers, each with a token of its own, so a wait that reported the wrong one
    // would be visible rather than merely wrong in the count.
    let (first, first_error) = os.socket_open(.Ip4, .Datagram)
    if first_error != ok { os.exit(11i32) }
    let (first_port, first_bind_error) = bind_somewhere(first, FIRST_PORT)
    if first_bind_error != ok { os.exit(12i32) }
    let (second, second_error) = os.socket_open(.Ip4, .Datagram)
    if second_error != ok { os.exit(13i32) }
    let (second_port, second_bind_error) = bind_somewhere(second, first_port + 1u16)
    if second_bind_error != ok { os.exit(14i32) }

    var readable: os.PollInterest = zero
    readable.readable = true
    if os.poller_register(poller, os.socket_handle(first), READ_TOKEN, readable) != ok { os.exit(15i32) }
    if os.poller_register(poller, os.socket_handle(second), WRITE_TOKEN, readable) != ok { os.exit(16i32) }

    // Nothing has arrived, so a wait that does not block reports nothing.
    var events: [8]os.PollEvent = zero
    let (idle, idle_error) = os.poller_wait(poller, events[..], 0i64)
    if idle_error != ok { os.exit(17i32) }
    if idle != 0usize { os.exit(18i32) }

    // Make both readable at once. Two events from one wait is also what says the entries
    // are read at the right stride: the kernel's are packed, and a second one read from the
    // wrong offset would carry a token that is neither of these.
    let (sender, sender_error) = os.socket_open(.Ip4, .Datagram)
    if sender_error != ok { os.exit(19i32) }
    var payload: [1]u8 = zero
    payload[0usize] = 65u8
    var to_first = loopback()
    to_first.port = first_port
    var to_second = loopback()
    to_second.port = second_port
    let (sent_one, sent_one_error) = os.socket_send_to(sender, to_first, payload[..])
    if sent_one_error != ok { os.exit(20i32) }
    let (sent_two, sent_two_error) = os.socket_send_to(sender, to_second, payload[..])
    if sent_two_error != ok { os.exit(21i32) }

    let (ready, ready_error) = os.poller_wait(poller, events[..], 2000000000i64)
    if ready_error != ok { os.exit(22i32) }
    if ready != 2usize { os.exit(23i32) }
    var saw_read = false
    var saw_write = false
    var at = 0usize
    while at < ready {
        if events[at].token == READ_TOKEN { saw_read = true }
        if events[at].token == WRITE_TOKEN { saw_write = true }
        if !events[at].readable { os.exit(24i32) }
        if events[at].failed { os.exit(25i32) }
        at += 1usize
    }
    if !saw_read { os.exit(26i32) }
    if !saw_write { os.exit(27i32) }

    // Drain both, so the next wait has nothing of its own to report.
    var sink: [8]u8 = zero
    let (drained_one, drain_one_source, drain_one_error) = os.socket_receive_from(first, sink[..])
    if drain_one_error != ok { os.exit(28i32) }
    let (drained_two, drain_two_source, drain_two_error) = os.socket_receive_from(second, sink[..])
    if drain_two_error != ok { os.exit(29i32) }
    let (drained, drained_error) = os.poller_wait(poller, events[..], 0i64)
    if drained_error != ok { os.exit(30i32) }
    if drained != 0usize { os.exit(31i32) }

    // Interest is changed, not re-registered: a datagram socket is always writable, so
    // asking about writing finds one immediately where asking about reading found none.
    var writable: os.PollInterest = zero
    writable.writable = true
    if os.poller_modify(poller, os.socket_handle(first), READ_TOKEN, writable) != ok { os.exit(40i32) }
    let (sendable, sendable_error) = os.poller_wait(poller, events[..], 1000000000i64)
    if sendable_error != ok { os.exit(41i32) }
    if sendable != 1usize { os.exit(42i32) }
    if events[0usize].token != READ_TOKEN { os.exit(43i32) }
    if !events[0usize].writable { os.exit(44i32) }

    // Unregistering takes it back out of the set, so the same wait now finds nothing.
    if os.poller_unregister(poller, os.socket_handle(first)) != ok { os.exit(45i32) }
    let (after_removal, after_removal_error) = os.poller_wait(poller, events[..], 0i64)
    if after_removal_error != ok { os.exit(46i32) }
    if after_removal != 0usize { os.exit(47i32) }

    // A wake returns a wait that would otherwise have waited, and reports no events of its
    // own -- the poller's own descriptor is not the caller's. The clock is what says it
    // returned because of the wake rather than because the timeout ran out.
    if os.poller_wake(poller) != ok { os.exit(50i32) }
    let (before, before_error) = os.clock(.Monotonic)
    if before_error != ok { os.exit(51i32) }
    let (woken, woken_error) = os.poller_wait(poller, events[..], 4000000000i64)
    if woken_error != ok { os.exit(52i32) }
    if woken != 0usize { os.exit(53i32) }
    let (after, after_error) = os.clock(.Monotonic)
    if after_error != ok { os.exit(54i32) }
    // Well under the four seconds asked for: a wake that did nothing would have waited them
    // out and still returned zero, so the time is the only thing that tells the two apart.
    if after - before > 1000000000i64 { os.exit(55i32) }

    // And the wake does not linger: the next wait with no timeout left finds nothing.
    let (settled, settled_error) = os.poller_wait(poller, events[..], 0i64)
    if settled_error != ok { os.exit(56i32) }
    if settled != 0usize { os.exit(57i32) }

    if os.poller_unregister(poller, os.socket_handle(second)) != ok { os.exit(60i32) }
    if os.poller_close(poller) != ok { os.exit(61i32) }
    if os.socket_close(sender) != ok { os.exit(62i32) }
    if os.socket_close(second) != ok { os.exit(63i32) }
    if os.socket_close(first) != ok { os.exit(64i32) }
    ret ok
}
