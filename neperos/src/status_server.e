// The NeperOS system status service as an EL0 user-mode server (C111, D2171). It holds the system
// status -- battery, Wi-Fi, cellular, the wall clock and a notification count -- and serves one
// protocol over two endpoints: a request endpoint (slot 2, receive) carrying an op word, and a reply
// endpoint (slot 3, send) carrying a five-word snapshot. A client SUBSCRIBEs or QUERYs to get a
// snapshot; it POSTs to raise the notification count (the notification service apps post to), which
// pushes a fresh snapshot; it QUITs to stop the server. On QEMU virt there is no battery and no
// radio, so those providers report absent (the present bit clear) rather than inventing a level or a
// signal; the wall clock is real (os.clock). The D2148 Android bridge later supplies the real
// battery and radio values behind this same protocol and snapshot layout.
use e.mem
use e.os
use e.time

const REQ: usize = 2usize
const REPLY: usize = 3usize
const NO_SLOT: usize = 99usize
const OP_QUIT: usize = 0usize
const OP_QUERY: usize = 1usize
const OP_POST: usize = 2usize
const OP_SUBSCRIBE: usize = 3usize
// A field's present bit; absent providers send 0, so a client reads them as unavailable.
const PRESENT: usize = 2147483648usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

// Push the five-word snapshot: battery, Wi-Fi, cellular, wall-clock nanoseconds, notification count.
// Battery packs present | charging<<8 | level; Wi-Fi present | signal; cellular present | kind<<8 |
// signal. QEMU virt has none of the three, so each is 0 (present bit clear). The clock is read fresh.
fn push_snapshot(notes: usize) {
    let battery = 0usize
    let wifi = 0usize
    let cellular = 0usize
    var clock_ns = 0usize
    let (stamp, clock_error) = time.now()
    if clock_error == ok { clock_ns = usize(stamp.nanos) }
    let b = os.send(REPLY, battery, NO_SLOT)
    let w = os.send(REPLY, wifi, NO_SLOT)
    let c = os.send(REPLY, cellular, NO_SLOT)
    let t = os.send(REPLY, clock_ns, NO_SLOT)
    let n = os.send(REPLY, notes, NO_SLOT)
}

fn main(a: *mem.Arena, args: []str) -> err {
    say("status server up\n")
    var notes = 0usize
    var running = true
    while running {
        let op = os.recv(REQ, NO_SLOT)
        if op == OP_QUIT { running = false }
        if op == OP_SUBSCRIBE { push_snapshot(notes) }
        if op == OP_QUERY { push_snapshot(notes) }
        if op == OP_POST {
            notes += 1usize
            push_snapshot(notes)
        }
    }
    say("status server done\n")
    ret ok
}
