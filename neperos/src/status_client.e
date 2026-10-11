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
const OP_POST_APP: usize = 4usize
const OP_SET_ALLOWED: usize = 5usize
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
    // (C149) Per-app notification permission is enforced where notifications are posted: with app 2's switch off in
    // the mask, a post from app 2 is blocked and a post from app 3 is counted.
    let mask = os.send(REQ, OP_SET_ALLOWED, NO_SLOT)
    let mask_value = os.send(REQ, 251usize, NO_SLOT)
    let blocked_post = os.send(REQ, OP_POST_APP, NO_SLOT)
    let blocked_app = os.send(REQ, 2usize, NO_SLOT)
    let b1 = os.recv(REPLY, NO_SLOT)
    let w1 = os.recv(REPLY, NO_SLOT)
    let c1 = os.recv(REPLY, NO_SLOT)
    let k1 = os.recv(REPLY, NO_SLOT)
    let n1 = os.recv(REPLY, NO_SLOT)
    say("status app 2 count ")
    say_num(n1)
    say("\n")
    let allowed_post = os.send(REQ, OP_POST_APP, NO_SLOT)
    let allowed_app = os.send(REQ, 3usize, NO_SLOT)
    let b2 = os.recv(REPLY, NO_SLOT)
    let w2 = os.recv(REPLY, NO_SLOT)
    let c2 = os.recv(REPLY, NO_SLOT)
    let k2 = os.recv(REPLY, NO_SLOT)
    let n2 = os.recv(REPLY, NO_SLOT)
    say("status app 3 count ")
    say_num(n2)
    say("\n")
    let quit = os.send(REQ, OP_QUIT, NO_SLOT)
    say("status client done\n")
    ret ok
}
