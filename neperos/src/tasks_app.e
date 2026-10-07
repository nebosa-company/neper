// The NeperOS Tasks app (C114, D2181 face; D2190 toggle engine): a checklist rendered through
// e.gfx.scene over the e.gpu CPU backend into a 256x256 surface -- a header, then task rows, each with
// a checkbox (filled when done), the task's number in the built-in 3x5 bitmap digit font, and a bar
// for its title. The done-state is COMPUTED: an initial state plus a fixed sequence of toggle inputs
// (check tasks 3 and 5) applied through a toggle engine, and it prints the resulting `tasks done N`.
// Deterministic, so a host run folds to the same hash. Needs the large arena (`bigarena`).
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use appview

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

fn draw_digit(builder: *scene.Builder, font: []const u8, px: f32, py: f32, d: usize, s: f32) {
    var row = 0usize
    while row < 5usize {
        let bits = usize(font[d * 5usize + row])
        var col = 0usize
        while col < 3usize {
            if ((bits >> (2usize - col)) & 1usize) == 1usize {
                fill(builder, px + f32(col) * s, py + f32(row) * s, s, s, 0.92, 0.94, 0.98)
            }
            col += 1usize
        }
        row += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let font: [50]u8 = [50]u8{ 7u8, 5u8, 5u8, 5u8, 7u8, 2u8, 6u8, 2u8, 2u8, 7u8, 7u8, 1u8, 7u8, 4u8, 7u8, 7u8, 1u8, 7u8, 1u8, 7u8, 5u8, 5u8, 7u8, 1u8, 1u8, 7u8, 4u8, 7u8, 1u8, 7u8, 7u8, 4u8, 7u8, 5u8, 7u8, 7u8, 1u8, 2u8, 2u8, 2u8, 7u8, 5u8, 7u8, 5u8, 7u8, 7u8, 5u8, 7u8, 1u8, 7u8 }
    // Six tasks: a done flag and a title width per row. The initial done-state, then a fixed sequence
    // of toggle inputs applied through the toggle engine (D2190) -- so the rendered checkboxes and the
    // done count are COMPUTED from input, not a fixed face.
    var done: [6]u8 = [6]u8{ 1u8, 1u8, 0u8, 1u8, 0u8, 0u8 }
    let widths: [6]u8 = [6]u8{ 120u8, 90u8, 150u8, 70u8, 110u8, 140u8 }
    // Toggle inputs: the user checks tasks 3 and 5 (0-based 2 and 4); each flips that task's flag.
    let toggles: [2]u8 = [2]u8{ 2u8, 4u8 }
    var ti = 0usize
    while ti < 2usize {
        let t = usize(toggles[ti])
        if usize(done[t]) == 1usize { done[t] = 0u8 } else { done[t] = 1u8 }
        ti += 1usize
    }
    var done_count = 0usize
    var dci = 0usize
    while dci < 6usize {
        if usize(done[dci]) == 1usize { done_count += 1usize }
        dci += 1usize
    }
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("tasks gpu failed\n")
        ret ok
    }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("tasks queue failed\n")
        ret ok
    }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok {
        say("tasks target failed\n")
        ret ok
    }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok {
        say("tasks canvas failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("tasks renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    fill(&builder, 0.0, 0.0, 256.0, 256.0, 0.10, 0.11, 0.14)
    // Header.
    fill(&builder, 0.0, 0.0, 256.0, 28.0, 0.16, 0.34, 0.5)
    var i = 0usize
    while i < 6usize {
        let y = 40.0 + f32(i) * 34.0
        // Checkbox: a box, filled green when the task is done.
        if usize(done[i]) == 1usize {
            fill(&builder, 16.0, y, 18.0, 18.0, 0.3, 0.7, 0.4)
        } else {
            fill(&builder, 16.0, y, 18.0, 18.0, 0.22, 0.24, 0.3)
        }
        // The task number.
        draw_digit(&builder, font[0usize..], 44.0, y + 3.0, i + 1usize, 3.0)
        // The title bar.
        fill(&builder, 64.0, y + 4.0, f32(usize(widths[i])), 10.0, 0.45, 0.5, 0.6)
        i += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("tasks compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, canvas, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("tasks render failed\n")
        ret ok
    }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok {
        say("tasks presented failed\n")
        ret ok
    }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret pixels_error }
    if gpu.read_image(q, image, pixels) != ok {
        say("tasks read failed\n")
        ret ok
    }
    var hash = 2166136261usize
    var i2 = 0usize
    while i2 < pixels.len {
        hash = ((hash ^ usize(pixels[i2])) * 16777619usize) & 4294967295usize
        i2 += 1usize
    }
    say("tasks done ")
    say_num(done_count)
    say("\n")
    say("tasks app hash ")
    say_num(hash)
    say("\n")
    appview.show(a, device, list, args)
    ret ok
}
