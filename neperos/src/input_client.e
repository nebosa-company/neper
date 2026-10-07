// A NeperOS client that receives input events over IPC (C109, D2160): it holds no input device,
// only the endpoint (slot 1, receive) the input server pushes events on. It unpacks each word into
// type, code and value and prints it, until the server's sentinel (type 0xFFFF). The QEMU fixture
// injects taps and keys and asserts these lines -- the event stream a client receives.
use e.mem
use e.os

const SERVER: usize = 1usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
const LOW16: usize = 65535usize
const LOW32: usize = 4294967295usize

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
    var listening = true
    while listening {
        let word = os.recv(SERVER, NO_SLOT)
        let etype = (word >> 48usize) & LOW16
        if etype == SENTINEL {
            listening = false
        } else {
            let ecode = (word >> 32usize) & LOW16
            let evalue = word & LOW32
            say("input ev ")
            say_num(etype)
            say(" ")
            say_num(ecode)
            say(" ")
            say_num(evalue)
            say("\n")
        }
    }
    say("input client done\n")
    ret ok
}
