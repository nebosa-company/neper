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
// (C149) A notification from app `n` (a word follows; 0 to 7, the order of Settings' notification list): counted only
// when the app is allowed, and the snapshot is pushed either way. SET_ALLOWED mask (bit n for app n) is what the
// settings server sends when a notification switch changes and at start; no reply. A plain POST is the system's and
// is never blocked.
const OP_POST_APP: usize = 4usize
const OP_SET_ALLOWED: usize = 5usize
// (D4007) A notification from a background process: counted, and no snapshot is pushed (the shell reads it at its next
// query), so the sender -- the background services process -- never waits for a reader that is behind an app.
const OP_POST_QUIET: usize = 6usize
// The same as POST_APP (a word follows: the app's place in Settings' notification list) without the snapshot push: how a
// background process posts as an app (C176).
const OP_POST_APP_QUIET: usize = 7usize
// A field's present bit; absent providers send 0, so a client reads them as unavailable.
const PRESENT: usize = 2147483648usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

// Push the five-word snapshot: battery, Wi-Fi, cellular, wall-clock nanoseconds, notification count.
// Battery packs present | charging<<8 | level; Wi-Fi present | signal; cellular present | kind<<8 |
// signal. QEMU virt has none of the three, so each is 0 (present bit clear). The clock is read fresh.
fn push_snapshot(notes: usize, battery: usize) {
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

fn digit_text(n: usize) -> str {
    if n == 0usize { ret "0" }
    if n == 1usize { ret "1" }
    if n == 2usize { ret "2" }
    if n == 3usize { ret "3" }
    if n == 4usize { ret "4" }
    if n == 5usize { ret "5" }
    if n == 6usize { ret "6" }
    ret "7"
}

fn main(a: *mem.Arena, args: []str) -> err {
    say("status server up\n")
    var notes = 0usize
    // (C126) The test boots name this process "statusbat" and give it a recorded battery (78%, not charging), the way
    // they record the Wi-Fi air: QEMU virt has no battery, and a real provider would fill this word.
    var battery = 0usize
    if args.len > 0usize && args[0usize].len == 9usize { battery = PRESENT | 78usize }
    var allowed = 255usize
    var running = true
    while running {
        let op = os.recv(REQ, NO_SLOT)
        if op == OP_QUIT { running = false }
        if op == OP_SET_ALLOWED { allowed = os.recv(REQ, NO_SLOT) & 255usize }
        if op == OP_POST_APP {
            let app = os.recv(REQ, NO_SLOT)
            if app < 8usize && ((allowed >> app) & 1usize) == 0usize {
                say("status notification blocked ")
                say(digit_text(app))
                say("\n")
            } else {
                notes += 1usize
            }
            push_snapshot(notes, battery)
        }
        if op == OP_POST_QUIET { notes += 1usize }
        if op == OP_POST_APP_QUIET {
            let quiet_app = os.recv(REQ, NO_SLOT)
            if quiet_app < 8usize && ((allowed >> quiet_app) & 1usize) == 0usize {
                say("status notification blocked ")
                say(digit_text(quiet_app))
                say("\n")
            } else {
                notes += 1usize
            }
        }
        if op == OP_SUBSCRIBE { push_snapshot(notes, battery) }
        if op == OP_QUERY { push_snapshot(notes, battery) }
        if op == OP_POST {
            notes += 1usize
            push_snapshot(notes, battery)
        }
    }
    say("status server done\n")
    ret ok
}
