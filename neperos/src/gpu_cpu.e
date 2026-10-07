// A NeperOS program that opens e.gpu's CPU backend (C110, D2166): e.ui draws through e.gfx.scene,
// which renders through e.gpu, so e.gpu's CPU device must open on NeperOS. It needs a large arena
// (the `-append gpu bigarena` boot gives one), far past the 64 KB in-window default, which is why
// the kernel arena grew and start_driver_server can map a program a big arena. Started as the sole
// virtio-gpu holder, though it drives the CPU backend, not the device.
use e.mem
use e.os
use e.gpu

fn say(text: str) {
    let (written, write_error) = os.write(os.stdout(), text)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("gpu cpu open failed\n")
        ret ok
    }
    say("gpu cpu open ok\n")
    ret ok
}
