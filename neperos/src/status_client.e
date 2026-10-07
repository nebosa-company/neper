// A NeperOS app that reads the system status service (C111, D2171). It holds no providers, only the
// status endpoints the boot grants it: a request endpoint (slot 1, send) and a reply endpoint (slot
// 2, receive). It subscribes, reads the five-word snapshot and reports each field -- an absent
// provider (present bit clear) as "unavailable" rather than a made-up value, the wall clock and the
// notification count by value. It then posts a notification through the service and reads the
// snapshot again, so the count it reports rises from 0 to 1. Finally it tells the server to quit.
use e.mem
use e.os

const REQ: usize = 1usize
const REPLY: usize = 2usize
const NO_SLOT: usize = 99usize
const OP_QUIT: usize = 0usize
const OP_POST: usize = 2usize
const OP_SUBSCRIBE: usize = 3usize
const PRESENT: usize = 2147483648usize
const LOW8: usize = 255usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn say_num(value: usize) {
    var digits: [20]u8 = zero
    var at = 20usize
    var rest = value
    var open = true
    while open {
        at -= 1usize
        digits[at] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    say(digits[at..20usize])
}

fn report(battery: usize, wifi: usize, cellular: usize, clock_ns: usize, notes: usize) {
    if (battery & PRESENT) == 0usize {
        say("status battery unavailable\n")
    } else {
        say("status battery level ")
        say_num(battery & LOW8)
        say("\n")
    }
    if (wifi & PRESENT) == 0usize {
        say("status wifi unavailable\n")
    } else {
        say("status wifi signal ")
        say_num(wifi & LOW8)
        say("\n")
    }
    if (cellular & PRESENT) == 0usize {
        say("status cellular unavailable\n")
    } else {
        say("status cellular signal ")
        say_num(cellular & LOW8)
        say("\n")
    }
    say("status clock ")
    say_num(clock_ns)
    say("\n")
    say("status notifications ")
    say_num(notes)
    say("\n")
}

fn main(a: *mem.Arena, args: []str) -> err {
    let subscribe = os.send(REQ, OP_SUBSCRIBE, NO_SLOT)
    let battery = os.recv(REPLY, NO_SLOT)
    let wifi = os.recv(REPLY, NO_SLOT)
    let cellular = os.recv(REPLY, NO_SLOT)
    let clock_ns = os.recv(REPLY, NO_SLOT)
    let notes = os.recv(REPLY, NO_SLOT)
    report(battery, wifi, cellular, clock_ns, notes)
    // Post a notification through the service; the pushed snapshot carries the raised count.
    let post = os.send(REQ, OP_POST, NO_SLOT)
    let battery2 = os.recv(REPLY, NO_SLOT)
    let wifi2 = os.recv(REPLY, NO_SLOT)
    let cellular2 = os.recv(REPLY, NO_SLOT)
    let clock2 = os.recv(REPLY, NO_SLOT)
    let notes2 = os.recv(REPLY, NO_SLOT)
    report(battery2, wifi2, cellular2, clock2, notes2)
    let quit = os.send(REQ, OP_QUIT, NO_SLOT)
    say("status client done\n")
    ret ok
}
