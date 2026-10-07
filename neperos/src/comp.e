// The NeperOS compositor (C110, D2162): it alone holds the virtio-gpu display. It fills the screen
// background, then waits for an app to signal (over endpoint 2) that it has drawn its surface into
// the frame the kernel mapped SHARED between them; it composites that surface into the display at
// the app's position and flushes. One surface and one app for now; damage-only flush, input routing
// from C109 and multiple surfaces follow.
use e.mem
use e.os
use virtio

const AUX: usize = 548682334144usize
// The shared surface frame (vm.SHARED_FRAME_VA): a 256x256 BGRA surface the app and the compositor
// both map.
const SHARED: usize = 548683907072usize
const SURFACE_W: usize = 256usize
const SURFACE_H: usize = 256usize
const APP: usize = 2usize
const INPUT: usize = 3usize
const FOCUS: usize = 4usize
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

fn fill_rect(fb: usize, stride: usize, x0: usize, y0: usize, w: usize, h: usize, b: u8, g: u8, r: u8) {
    var y = 0usize
    while y < h {
        var x = 0usize
        while x < w {
            let p = fb + ((y0 + y) * stride + (x0 + x)) * 4usize
            os.store8(p, b)
            os.store8(p + 1usize, g)
            os.store8(p + 2usize, r)
            os.store8(p + 3usize, 255u8)
            x += 1usize
        }
        y += 1usize
    }
}

// Copy the shared surface into the display framebuffer at (ox, oy).
fn composite(fb: usize, stride: usize, ox: usize, oy: usize) {
    var y = 0usize
    while y < SURFACE_H {
        var x = 0usize
        while x < SURFACE_W {
            let s = SHARED + (y * SURFACE_W + x) * 4usize
            let d = fb + ((oy + y) * stride + (ox + x)) * 4usize
            os.store8(d, os.load8(s))
            os.store8(d + 1usize, os.load8(s + 1usize))
            os.store8(d + 2usize, os.load8(s + 2usize))
            os.store8(d + 3usize, 255u8)
            x += 1usize
        }
        y += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let device = read_device()
    let (gpu, begin_error) = virtio.gpu_begin(device)
    if begin_error != ok {
        say("comp begin failed\n")
        ret ok
    }
    fill_rect(gpu.fb, gpu.width, 0usize, 0usize, gpu.width, gpu.height, 30u8, 30u8, 45u8)
    say("comp ready\n")
    let frame = os.recv(APP, NO_SLOT)
    composite(gpu.fb, gpu.width, 400usize, 200usize)
    let present_error = virtio.gpu_present(gpu)
    if present_error != ok {
        say("comp present failed\n")
        ret ok
    }
    say("comp composited flushed\n")
    // Route input from the input server (endpoint on slot 3) to the focused surface -- the app
    // (endpoint on slot 4) -- until the stream ends with the sentinel (type 0xFFFF).
    var routing = true
    while routing {
        let event = os.recv(INPUT, NO_SLOT)
        let forwarded = os.send(FOCUS, event, NO_SLOT)
        if (event >> 48usize) == SENTINEL { routing = false }
    }
    say("comp routed input\n")
    ret ok
}
