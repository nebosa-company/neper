// C179: which way of using kqueue never loses the second datagram. Each variant runs 300 rounds of "two receivers, one
// sender, one datagram each" and prints how many rounds the poller missed a receiver in five 200 ms waits.
use e.mem
use e.os

type Kevent = struct { ident: u64, filter: i16, flags: u16, fflags: u32, data: i64, udata: u64 }

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn number(value: usize) {
    if value >= 10usize { number(value / 10usize) }
    var one: [1]u8 = zero
    one[0usize] = u8(48usize + value % 10usize)
    let (written, write_error) = os.write(os.stdout(), one[..])
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

fn change(queue: usize, ident: usize, flags: u16, udata: u64) -> isize {
    var k: Kevent = zero
    k.ident = u64(ident)
    k.filter = -1i16
    k.flags = flags
    k.udata = udata
    ret os.syscall(363usize, queue, mem.address_of(&k), 1usize, 0usize, 0usize, 0usize)
}

// flags: what EV_ADD is combined with; late: add the filters after the datagrams are sent; reverse: send to the second first.
fn variant(flags: u16, late: bool, reverse: bool, wait_ns: i64, rearm: usize) -> usize {
    var misses = 0usize
    var round = 0usize
    while round < 3000usize {
        let queue = u64(os.syscall(362usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize))
        let (first, first_error) = os.socket_open(.Ip4, .Datagram)
        let (second, second_error) = os.socket_open(.Ip4, .Datagram)
        let (sender, sender_error) = os.socket_open(.Ip4, .Datagram)
        if first_error != ok { os.exit(11i32) }
        if second_error != ok { os.exit(11i32) }
        if sender_error != ok { os.exit(11i32) }
        let first_port = bind_ephemeral(first)
        let second_port = bind_ephemeral(second)
        let first_fd = os.socket_handle(first).raw
        let second_fd = os.socket_handle(second).raw
        if !late {
            let added_one = change(usize(queue), first_fd, 1u16 | flags, 1u64)
            let added_two = change(usize(queue), second_fd, 1u16 | flags, 2u64)
        }
        var payload: [1]u8 = zero
        payload[0usize] = 65u8
        var to_first = loopback()
        to_first.port = first_port
        var to_second = loopback()
        to_second.port = second_port
        if reverse {
            let (s2, e2) = os.socket_send_to(sender, to_second, payload[..])
            let (s1, e1) = os.socket_send_to(sender, to_first, payload[..])
        } else {
            let (s1, e1) = os.socket_send_to(sender, to_first, payload[..])
            let (s2, e2) = os.socket_send_to(sender, to_second, payload[..])
        }
        if late {
            let added_one = change(usize(queue), first_fd, 1u16 | flags, 1u64)
            let added_two = change(usize(queue), second_fd, 1u16 | flags, 2u64)
        }
        var seen_one = false
        var seen_two = false
        var waits = 0usize
        var last_one = false
        var last_two = false
        while !(seen_one && seen_two) && waits < 5usize {
            var changes: [2]Kevent = zero
            var count = 0usize
            if rearm != 0usize {
                if last_one {
                    changes[count].ident = u64(first_fd)
                    changes[count].filter = -1i16
                    changes[count].flags = 1u16 | flags
                    changes[count].udata = 1u64
                    count += 1usize
                }
                if last_two {
                    changes[count].ident = u64(second_fd)
                    changes[count].filter = -1i16
                    changes[count].flags = 1u16 | flags
                    changes[count].udata = 2u64
                    count += 1usize
                }
            }
            last_one = false
            last_two = false
            var change_address = 0usize
            var change_count = 0usize
            if count != 0usize {
                if rearm == 1usize {
                    change_address = mem.address_of(&changes[0usize])
                    change_count = count
                } else {
                    let separate = os.syscall(363usize, usize(queue), mem.address_of(&changes[0usize]), count, 0usize, 0usize, 0usize)
                }
            }
            var out: [8]Kevent = zero
            var limit: [2]i64 = zero
            limit[0usize] = wait_ns / 1000000000i64
            limit[1usize] = wait_ns % 1000000000i64
            let got = os.syscall(363usize, usize(queue), change_address, change_count, mem.address_of(&out[0usize]), 8usize, mem.address_of(&limit[0usize]))
            var at = 0isize
            while at < got {
                if out[usize(at)].udata == 1u64 {
                    seen_one = true
                    last_one = true
                }
                if out[usize(at)].udata == 2u64 {
                    seen_two = true
                    last_two = true
                }
                at += 1isize
            }
            waits += 1usize
        }
        if !(seen_one && seen_two) { misses += 1usize }
        let closed_a = os.socket_close(first)
        let closed_b = os.socket_close(second)
        let closed_c = os.socket_close(sender)
        let closed_q = os.syscall(6usize, usize(queue), 0usize, 0usize, 0usize, 0usize, 0usize)
        round += 1usize
    }
    ret misses
}

fn report(name: str, misses: usize) {
    say(name)
    say(": ")
    number(misses)
    say(" of 300\n")
}

fn main(a: *mem.Arena) -> err {
    report("clear, no rearm", variant(32u16, false, false, 200000000i64, 0usize))
    report("clear, rearm in the wait call", variant(32u16, false, false, 200000000i64, 1usize))
    report("clear, rearm by its own call", variant(32u16, false, false, 200000000i64, 2usize))
    report("clear, rearm in the wait call, reversed", variant(32u16, false, true, 200000000i64, 1usize))
    ret ok
}
