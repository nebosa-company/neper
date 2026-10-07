// The NeperOS virtio-gpu driver as an EL0 user-mode server (C108, D2159): the kernel maps the
// device's BAR and a framebuffer-sized DMA pool into this server and hands it off (the `-append gpu`
// boot). It reads the display mode, creates a BGRA resource the display's size, attaches a
// framebuffer, paints a deterministic test pattern, makes it the scanout and flushes it to the
// screen -- a QEMU screendump of the result is checked against a golden hash. It alone holds the
// scanout.
use e.mem
use e.os
use virtio

// The aux area the kernel fills for a driver server, at USER_BASE + vm.AUX_OFF (D2137).
const AUX: usize = 548682334144usize

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
    let (width, height, gpu_error) = virtio.gpu_bringup(device)
    if gpu_error != ok {
        say("gpu bringup failed\n")
        ret ok
    }
    say("gpu ")
    say_num(width)
    say("x")
    say_num(height)
    say(" test pattern flushed\n")
    // Hold the scanout up a while after the flush so a screendump catches the pattern before the
    // kernel powers off; the harness captures as soon as the line above appears.
    var hold = 0usize
    while hold < 2000000000usize { hold += 1usize }
    ret ok
}

