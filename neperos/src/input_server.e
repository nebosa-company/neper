// The NeperOS virtio-input driver as an EL0 user-mode server (C109, D2160): it alone holds the
// input device (the kernel maps its BAR and a DMA pool in, and grants a notification bound to the
// device's interrupt). It posts event buffers, blocks on the notification until input arrives, then
// drains the burst and forwards each event to a client over an endpoint (slot 2, send) as one
// packed word -- type<<48 | code<<32 | value -- so a multi-word message never interleaves. A
// sentinel word (type 0xFFFF) ends the stream. Works for any virtio-input device: a keyboard or an
// absolute-pointer tablet alike, since the event shape is the same.
use e.mem
use e.os
use virtio

const AUX: usize = 548682334144usize
const CLIENT: usize = 2usize
const NOTIFY: usize = 1usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize

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
    let (opened, open_error) = virtio.input_open(device, virtio.INPUT_EVENTS)
    if open_error != ok {
        say("input open failed\n")
        ret ok
    }
    var input = opened
    say("input ready\n")
    // Wake on the device's interrupt (the notification the kernel bound), then drain the burst with
    // a bounded poll and forward each event. The notification is what makes this interrupt-driven.
    let bits = os.notify_wait(NOTIFY)
    var iterations = 0usize
    var forwarded = 0usize
    while iterations < 400000000usize && forwarded < 24usize {
        let (etype, ecode, evalue, present) = virtio.input_next(&input)
        if present {
            let word = (usize(etype) << 48usize) | (usize(ecode) << 32usize) | usize(evalue)
            let sent = os.send(CLIENT, word, NO_SLOT)
            forwarded += 1usize
        }
        iterations += 1usize
    }
    let done = os.send(CLIENT, SENTINEL << 48usize, NO_SLOT)
    ret ok
}
