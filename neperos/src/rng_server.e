// The NeperOS random-number server (D2246, C117): an EL0 user-mode server that alone holds the
// virtio-rng device. A client holding its endpoints sends the op word WORDS and a count; the server
// answers that many words of eight device-random bytes each. Op QUIT ends it. Nothing the server
// hands out is ever handed out twice: the buffer is refilled from the device when it runs dry.
use e.mem
use e.os
use virtio

const AUX: usize = 548682334144usize
const REQ: usize = 2usize
const REP: usize = 3usize
const NO_SLOT: usize = 99usize

const OP_QUIT: usize = 0usize
const OP_WORDS: usize = 1usize

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn read_device() -> virtio.Device {
    var device: virtio.Device = zero
    device.common = usize(os.load64(AUX))
    device.notify = usize(os.load64(AUX + 8usize))
    device.notify_multiplier = u32(os.load64(AUX + 16usize))
    virtio.pool_set(usize(os.load64(AUX + 24usize)), usize(os.load64(AUX + 32usize)))
    device.config = usize(os.load64(AUX + 40usize))
    ret device
}

fn main(a: *mem.Arena, args: []str) -> err {
    let device = read_device()
    var (source, open_error) = virtio.entropy_open(device, 256usize)
    if open_error != ok {
        say("rng server open failed\n")
        ret ok
    }
    say("rng server up\n")
    var have = 0usize
    var at = 0usize
    var running = true
    while running {
        let op = os.recv(REQ, NO_SLOT)
        if op == OP_QUIT {
            running = false
        } else {
            var left = os.recv(REQ, NO_SLOT)
            while left > 0usize {
                if at + 8usize > have {
                    let (written, fill_error) = virtio.entropy_fill(&source)
                    if fill_error != ok || written < 8usize {
                        say("rng server fill failed\n")
                        ret ok
                    }
                    have = written
                    at = 0usize
                }
                let sent = os.send(REP, usize(os.load64(source.buffer + at)), NO_SLOT)
                at += 8usize
                left -= 1usize
            }
        }
    }
    ret ok
}
