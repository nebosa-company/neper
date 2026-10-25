// Why `os_poller` and `async` sometimes see one of two loopback datagrams on a Mac: the fixture's shape in a loop, and
// on a miss a second poller holding only the missing socket says whether the datagram arrived (the first poller missed
// it) or never did (loopback lost it). Prints one line per miss and a total.
use e.mem
use e.os

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn digit(value: usize) {
    var one: [1]u8 = zero
    one[0usize] = u8(48usize + value % 10usize)
    let (written, write_error) = os.write(os.stdout(), one[..])
}

fn number(value: usize) {
    if value >= 10usize { number(value / 10usize) }
    digit(value)
}

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
    var misses = 0usize
    var late = 0usize
    var round = 0usize
    while round < 300usize {
        let (poller, poller_error) = os.poller_open(a)
        if poller_error != ok { os.exit(10i32) }
        let (first, first_error) = os.socket_open(.Ip4, .Datagram)
        let (second, second_error) = os.socket_open(.Ip4, .Datagram)
        let (sender, sender_error) = os.socket_open(.Ip4, .Datagram)
        if first_error != ok { os.exit(11i32) }
        if second_error != ok { os.exit(11i32) }
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
            var at = 0usize
            while at < got {
                if events[at].token == 1usize { seen_first = true }
                if events[at].token == 2usize { seen_second = true }
                at += 1usize
            }
            waits += 1usize
        }
        if !(seen_first && seen_second) {
            misses += 1usize
            let (check, check_error) = os.poller_open(a)
            if check_error != ok { os.exit(14i32) }
            var only: os.PollInterest = zero
            only.readable = true
            let probed = os.poller_register(check, os.socket_handle(second), 2usize, only)
            let (again, again_error) = os.poller_wait(check, events[..], 1000000000i64)
            let closed_check = os.poller_close(check)
            let readded = os.poller_register(poller, os.socket_handle(second), 2usize, only)
            let (rescued, rescued_error) = os.poller_wait(poller, events[..], 1000000000i64)
            say("readd_events=")
            number(rescued)
            say(" ")
            say("miss round ")
            number(round)
            say(" first=")
            number(sent_one)
            say(" second=")
            number(sent_two)
            say(" seen_first=")
            if seen_first { say("1") } else { say("0") }
            say(" seen_second=")
            if seen_second { say("1") } else { say("0") }
            say(" fresh_poller_events=")
            number(again)
            say("\n")
            if again != 0usize { late += 1usize }
        }
        let closed_poller = os.poller_close(poller)
        let closed_a = os.socket_close(first)
        let closed_b = os.socket_close(second)
        let closed_c = os.socket_close(sender)
        round += 1usize
    }
    say("misses ")
    number(misses)
    say(" of 300, arrived-anyway ")
    number(late)
    say("\n")
    ret ok
}
