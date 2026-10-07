// The NeperOS Settings app's face (C114, D2182): a settings list rendered through e.gfx.scene over
// the e.gpu CPU backend into a 256x256 surface -- a header, then rows each with a label bar and a
// toggle switch (a track and a knob, green with the knob right when on, grey with the knob left when
// off). Fixed settings keep the frame deterministic; a host run folds it to the same hash. Needs the
// large arena (`bigarena`).
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene

const SIDE: usize = 256usize

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

fn main(a: *mem.Arena, args: []str) -> err {
    // Five settings: an on flag and a label-bar width per row (fixed).
    let on: [5]u8 = [5]u8{ 1u8, 0u8, 1u8, 1u8, 0u8 }
    let widths: [5]u8 = [5]u8{ 90u8, 120u8, 70u8, 140u8, 100u8 }
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("settings gpu failed\n")
        ret ok
    }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("settings queue failed\n")
        ret ok
    }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok {
        say("settings target failed\n")
        ret ok
    }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok {
        say("settings canvas failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("settings renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    fill(&builder, 0.0, 0.0, 256.0, 256.0, 0.11, 0.11, 0.13)
    fill(&builder, 0.0, 0.0, 256.0, 28.0, 0.4, 0.4, 0.46)
    var i = 0usize
    while i < 5usize {
        let y = 44.0 + f32(i) * 38.0
        // The setting's label bar.
        fill(&builder, 16.0, y + 5.0, f32(usize(widths[i])), 12.0, 0.5, 0.52, 0.58)
        // The toggle: a 44x20 track with a 16x16 knob, green/knob-right when on, grey/knob-left off.
        if usize(on[i]) == 1usize {
            fill(&builder, 196.0, y + 3.0, 44.0, 20.0, 0.3, 0.68, 0.42)
            fill(&builder, 222.0, y + 5.0, 16.0, 16.0, 0.95, 0.97, 0.95)
        } else {
            fill(&builder, 196.0, y + 3.0, 44.0, 20.0, 0.28, 0.3, 0.36)
            fill(&builder, 198.0, y + 5.0, 16.0, 16.0, 0.8, 0.82, 0.86)
        }
        i += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("settings compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, canvas, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("settings render failed\n")
        ret ok
    }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok {
        say("settings presented failed\n")
        ret ok
    }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret pixels_error }
    if gpu.read_image(q, image, pixels) != ok {
        say("settings read failed\n")
        ret ok
    }
    var hash = 2166136261usize
    var i2 = 0usize
    while i2 < pixels.len {
        hash = ((hash ^ usize(pixels[i2])) * 16777619usize) & 4294967295usize
        i2 += 1usize
    }
    say("settings app hash ")
    say_num(hash)
    say("\n")
    ret ok
}
