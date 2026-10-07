// The NeperOS compositor (C110, D2162): it alone holds the virtio-gpu display. It fills the screen
// background, then waits for an app to signal (over endpoint 2) that it has drawn its surface into
// the frame the kernel mapped SHARED between them; it composites that surface into the display at
// the app's position and flushes. One surface and one app for now; damage-only flush, input routing
// from C109 and multiple surfaces follow.
use e.mem
use e.os
use virtio

const AUX: usize = 548682334144usize
// The shared surface frame (vm.SHARED_FRAME_VA): the whole screen, a 1280x2856 BGRA surface the app and
// the compositor both map (vm.SHARED_FRAME_W and _H; keep equal).
const SHARED: usize = 548684169216usize
const SURFACE_W: usize = 1280usize
const SURFACE_H: usize = 2856usize
const APP: usize = 2usize
const INPUT: usize = 3usize
const FOCUS: usize = 4usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
// The app surface's position on the display, where it is composited and damage-flushed.
const SURFACE_X: usize = 0usize
const SURFACE_Y: usize = 0usize

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
// Two pixels at a time (the surface is an even number of pixels wide), alpha forced opaque. The
// display's own size bounds the copy, so a smaller display shows the top-left of the surface.
const OPAQUE_PAIR: u64 = 18374686483949813760u64

fn composite(fb: usize, stride: usize, height: usize, ox: usize, oy: usize) {
    var rows = SURFACE_H
    if oy + rows > height { rows = height - oy }
    var cols = SURFACE_W
    if ox + cols > stride { cols = stride - ox }
    var y = 0usize
    while y < rows {
        var s = SHARED + y * SURFACE_W * 4usize
        var d = fb + ((oy + y) * stride + ox) * 4usize
        var x = 0usize
        while x + 1usize < cols {
            os.store64(d, u64(os.load64(s)) | OPAQUE_PAIR)
            s += 8usize
            d += 8usize
            x += 2usize
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
    // Present the background once in full, then every surface update is a damage-only flush.
    let background_error = virtio.gpu_present(gpu)
    if background_error != ok {
        say("comp present failed\n")
        ret ok
    }
    say("comp ready\n")
    // An app that answers every routed event (the shell, D2204) first sends 2 on its frame endpoint;
    // after that the compositor takes one frame signal or 0 per event it forwards, so frames after
    // the first are composited too. Any other app sends 1 and gets the single-frame behaviour.
    var lockstep = false
    var frame = os.recv(APP, NO_SLOT)
    if frame == 2usize {
        lockstep = true
        frame = os.recv(APP, NO_SLOT)
    }
    composite(gpu.fb, gpu.width, gpu.height, SURFACE_X, SURFACE_Y)
    // Flush only the app's surface rectangle -- the damage -- not the whole display.
    let present_error = virtio.gpu_present_rect(gpu, SURFACE_X, SURFACE_Y, SURFACE_W, SURFACE_H)
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
        if (event >> 48usize) == SENTINEL {
            routing = false
        } else if lockstep {
            let answer = os.recv(APP, NO_SLOT)
            if answer == 1usize {
                composite(gpu.fb, gpu.width, gpu.height, SURFACE_X, SURFACE_Y)
                let next_error = virtio.gpu_present_rect(gpu, SURFACE_X, SURFACE_Y, SURFACE_W, SURFACE_H)
                if next_error == ok { say("comp composited again\n") }
            }
        }
    }
    say("comp routed input\n")
    // Hold the composited scanout up so a screendump catches it before the kernel powers off.
    var hold = 0usize
    while hold < 2000000000usize { hold += 1usize }
    ret ok
}
