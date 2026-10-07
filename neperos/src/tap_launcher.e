// The NeperOS launcher's tap-to-launch and Home round trip (C112, D2178). Program 1 of the input
// boot's archive (input server program 0, this launcher program 1, the app program 2). The launcher
// receives input events the input server forwards (slot 1, the C109 path); on the first key-down --
// a tap on an icon -- it launches the app as a process (os.launch), waits for it (os.reap), and is
// back at the launcher, which it reports as Home. It keeps reading until the event stream's sentinel.
// The launch-and-return round trip: a tap starts an app process, the app runs and exits, and control
// returns to the launcher.
use e.mem
use e.os

const SERVER: usize = 1usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
const LOW16: usize = 65535usize
const LOW32: usize = 4294967295usize
const EV_KEY: usize = 1usize
const APP_INDEX: usize = 2usize

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

fn main(a: *mem.Arena, args: []str) -> err {
    say("launcher ready\n")
    var launched = false
    var listening = true
    while listening {
        let word = os.recv(SERVER, NO_SLOT)
        let etype = (word >> 48usize) & LOW16
        if etype == SENTINEL {
            listening = false
        } else {
            let value = word & LOW32
            // A key-down is a tap on an icon; launch the app once and run the round trip.
            if etype == EV_KEY && value == 1usize && !launched {
                launched = true
                say("launcher tap\n")
                let child = os.launch(APP_INDEX)
                say("launcher launched app\n")
                let code = os.reap(child)
                say("launcher app code ")
                say_num(code)
                say("\n")
                say("launcher home\n")
            }
        }
    }
    say("launcher done\n")
    ret ok
}
