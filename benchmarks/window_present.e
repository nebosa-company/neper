// Present benchmark (D5928): the same frames shown through readback + GDI and through a Vulkan swapchain, a full frame and a 133 x 136 box.
// Usage: out.exe DEVICE_INDEX [1 for 1600x1000]
use e.mem
use e.gpu
use e.io
use e.str
use e.time
use e.os

fn now() -> i64 {
    let (t, e) = time.monotonic()
    ret t.nanos
}

fn say(a: *mem.Arena, tag: str, v: u64) {
    let (sb, sbe) = str.builder(a, 200usize)
    var so = sb
    let e1 = str.push(&so, tag)
    let e2 = str.push(&so, "=")
    let e3 = str.push_u64(&so, v)
    let e4 = str.push(&so, " ")
    let pr = io.print(str.done(&so))
}

type AddressPun = union { bits: usize, pointer: *void }

// Present benchmark (D5928): the same frames shown by the swapchain and by readback + GDI, full frame and a 133 x 136 box.
// Usage: pb.exe DEVICE_INDEX WIDTH HEIGHT
fn run(a: *mem.Arena, index: u32, w: u32, h: u32, native: bool) -> err {
    let (dev, de) = gpu.open(a, .Vulkan, index)
    if de != ok { ret de }
    let (q, qe) = gpu.queue(dev)
    if qe != ok { ret qe }
    let (win, we) = os.window_open(a, os.WindowOptions { title: "pb", width: w, height: h, resizable: false, visible: true, mode: .Windowed })
    if we != ok { ret we }
    let (hwnd, hinstance, ne) = os.window_native(win)
    if ne != ok { ret ne }
    var wp: AddressPun = zero
    var mp: AddressPun = zero
    wp.bits = hwnd
    mp.bits = hinstance
    var kind: gpu.SurfaceKind = .Offscreen
    if native { kind = .Win32 }
    let (tgt, te) = gpu.open_target(q, gpu.Surface { kind: kind, handle: wp.pointer, context: mp.pointer }, w, h, .Bgra8)
    if te != ok {
        let pr = io.print("target failed\n")
        ret te
    }
    let (pixels, pe) = mem.alloc[u32](a, usize(w) * usize(h))
    var i = 0usize
    while i < pixels.len {
        pixels[i] = 4278190080u32 | u32(i % 251usize)
        i += 1usize
    }
    let (rect, re) = mem.alloc[u32](a, 133usize * 136usize)
    var round = 0u32
    while round < 3u32 {
        // full, then box
        var pass = 0u32
        while pass < 2u32 {
            var bx = 0u32
            var by = 0u32
            var bw = w
            var bh = h
            if pass == 1u32 {
                bx = 100u32
                by = 480u32
                bw = 133u32
                bh = 136u32
            }
            var total = 0i64
            var n = 0u32
            while n < 20u32 {
                let t0 = now()
                let (frame, ae) = gpu.acquire(tgt)
                if ae != ok { ret ae }
                if pass == 0u32 {
                    try gpu.write_image(q, frame.image, 0u32, 0u32, w, h, pixels)
                } else {
                    var r = 0usize
                    while r < 136usize {
                        var c = 0usize
                        while c < 133usize {
                            rect[r * 133usize + c] = 4278190080u32 | u32((n * 7u32 + u32(c)) % 251u32)
                            c += 1usize
                        }
                        r += 1usize
                    }
                    try gpu.write_image(q, frame.image, bx, by, bw, bh, rect)
                }
                gpu.report_damage(tgt, bx, by, bx + bw, by + bh)
                let (tok, pre) = gpu.present(q, tgt, frame)
                if pre != ok { ret pre }
                if !gpu.native(tgt) {
                    let (shown, se) = gpu.presented(tgt)
                    if se != ok { ret se }
                    if pass == 0u32 {
                        try gpu.read_image(q, shown, pixels)
                        try os.window_present(win, pixels, w, h)
                    } else {
                        try gpu.read_image_rect(q, shown, bx, by, bw, bh, rect)
                        try os.window_present_rect(win, rect, bx, by, bw, bh)
                    }
                }
                total += now() - t0
                n += 1u32
            }
            if round == 2u32 {
                var tag = "gdi"
                if native { tag = "swapchain" }
                let (sb, sbe) = str.builder(a, 80usize)
                var so = sb
                let e1 = str.push(&so, tag)
                if pass == 0u32 { let e2 = str.push(&so, "_full_us") } else { let e3 = str.push(&so, "_box_us") }
                let pr = io.print(str.done(&so))
                say(a, "", u64(total / 20i64 / 1000i64))
            }
            pass += 1u32
        }
        round += 1u32
    }
    let closed = gpu.close_target(tgt)
    let wc = os.window_close(win)
    let dc = gpu.close(dev)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    var index = 0u32
    if args.len > 1usize { index = u32(args[1usize][0usize] - 48u8) }
    var w = 1180u32
    var h = 780u32
    if args.len > 2usize && args[2usize][0usize] == 49u8 { w = 1600u32 }
    if args.len > 2usize && args[2usize][0usize] == 49u8 { h = 1000u32 }
    let pr0 = io.print("device ")
    say(a, "", u64(index))
    say(a, " w", u64(w))
    try run(a, index, w, h, false)
    try run(a, index, w, h, true)
    let pr = io.print("\n")
    ret ok
}
