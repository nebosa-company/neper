// The NeperOS launcher's top bar driven by the live C111 status service (C112, D2175). It
// subscribes to the status service, reads the snapshot, posts a notification through it (so the
// count rises to 1) and reads the snapshot again, then renders the launcher with the top bar's
// status indicators reflecting what the service reported: a tick per provider, bright when present
// and dim when absent (battery, Wi-Fi and cellular are all absent on QEMU virt), and a lit tick per
// notification. The clock is not drawn, so the frame hash is deterministic. It reports the status it
// read so the fixture can check the launcher read the real values. Program 1 of a status boot.
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene

const REQ: usize = 1usize
const REPLY: usize = 2usize
const NO_SLOT: usize = 99usize
const OP_QUIT: usize = 0usize
const OP_POST: usize = 2usize
const OP_SUBSCRIBE: usize = 3usize
const PRESENT: usize = 2147483648usize

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

fn fill(builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, red: f32, green: f32, blue: f32) {
    let pushed = scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, y, w, h), brush: paint.Brush { Solid: paint.Color { red: red, green: green, blue: blue, alpha: 1.0 } } } })
}

fn report(name: str, word: usize) {
    say("launcher status ")
    say(name)
    if (word & PRESENT) == 0usize { say(" absent\n") } else { say(" present\n") }
}

// A provider tick: bright when the provider is present, dim when absent.
fn provider_tick(builder: *scene.Builder, x: f32, word: usize) {
    if (word & PRESENT) == 0usize {
        fill(builder, x, 5.0, 8.0, 8.0, 0.3, 0.3, 0.33)
    } else {
        fill(builder, x, 5.0, 8.0, 8.0, 0.6, 0.85, 0.7)
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let subscribe = os.send(REQ, OP_SUBSCRIBE, NO_SLOT)
    let b0 = os.recv(REPLY, NO_SLOT)
    let w0 = os.recv(REPLY, NO_SLOT)
    let c0 = os.recv(REPLY, NO_SLOT)
    let t0 = os.recv(REPLY, NO_SLOT)
    let n0 = os.recv(REPLY, NO_SLOT)
    // Post a notification through the service; read the snapshot with the raised count.
    let post = os.send(REQ, OP_POST, NO_SLOT)
    let battery = os.recv(REPLY, NO_SLOT)
    let wifi = os.recv(REPLY, NO_SLOT)
    let cellular = os.recv(REPLY, NO_SLOT)
    let clock = os.recv(REPLY, NO_SLOT)
    let notes = os.recv(REPLY, NO_SLOT)
    report("battery", battery)
    report("wifi", wifi)
    report("cellular", cellular)
    say("launcher status notifications ")
    say_num(notes)
    say("\n")

    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("launcher status gpu failed\n")
        let q0 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    let (qq, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("launcher status queue failed\n")
        let q1 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    let (frames, frames_error) = gpu.open_target(qq, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, 256u32, 256u32, gpu.Format.Bgra8)
    if frames_error != ok {
        say("launcher status target failed\n")
        let q2 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok {
        say("launcher status canvas failed\n")
        let q3 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, qq, 1u32, 1u32)
    if renderer_error != ok {
        say("launcher status renderer failed\n")
        let q4 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 72usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    fill(&builder, 0.0, 0.0, 256.0, 256.0, 0.09, 0.11, 0.18)
    fill(&builder, 0.0, 0.0, 256.0, 18.0, 0.05, 0.06, 0.10)
    // Three provider ticks on the right, each bright or dim by presence.
    provider_tick(&builder, 256.0 - 10.0, battery)
    provider_tick(&builder, 256.0 - 22.0, wifi)
    provider_tick(&builder, 256.0 - 34.0, cellular)
    // Notification ticks on the left: one lit per notification, up to five.
    var notif = 0usize
    while notif < 5usize {
        var lit: f32 = 0.3
        if notif < notes { lit = 0.9 }
        fill(&builder, 6.0 + f32(notif) * 10.0, 5.0, 8.0, 8.0, lit, lit * 0.6, 0.2)
        notif += 1usize
    }
    var r = 0usize
    while r < 8usize {
        var c = 0usize
        while c < 5usize {
            let cx = 8.0 + f32(c) * 48.0
            let cy = 28.0 + f32(r) * 28.0
            let idx = r * 5usize + c
            let shade = f32(idx) / 40.0
            fill(&builder, cx + 6.0, cy + 4.0, 36.0, 20.0, 0.3 + shade * 0.5, 0.5, 0.85 - shade * 0.4)
            c += 1usize
        }
        r += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("launcher status compile failed\n")
        let q5 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, canvas, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("launcher status render failed\n")
        let q6 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    let (rendered, presented_error) = gpu.presented(frames)
    if presented_error != ok {
        say("launcher status presented failed\n")
        let q7 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    let (out_pixels, out_error) = mem.alloc[u32](a, 256usize * 256usize)
    if out_error != ok { ret out_error }
    if gpu.read_image(qq, rendered, out_pixels) != ok {
        say("launcher status read failed\n")
        let q8 = os.send(REQ, OP_QUIT, NO_SLOT)
        ret ok
    }
    var hash = 2166136261usize
    var i = 0usize
    while i < out_pixels.len {
        hash = ((hash ^ usize(out_pixels[i])) * 16777619usize) & 4294967295usize
        i += 1usize
    }
    say("launcher status hash ")
    say_num(hash)
    say("\n")
    let quit = os.send(REQ, OP_QUIT, NO_SLOT)
    ret ok
}
