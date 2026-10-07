// The NeperOS Clock app's face (C113, D2179): a digital clock rendered through e.gfx.scene over the
// e.gpu CPU backend into a 256x256 surface -- a dark card on a wallpaper, the time "12:34" in large
// digits with a blinking-style colon, drawn with the built-in 3x5 bitmap digit font. A fixed time is
// used so the frame is deterministic (the live time comes from os.clock, proven in C107/C111); this
// is the app's visual, which the shell hosts once the unified launcher lands. It folds the frame to
// a hash; a host run renders the same face to the same hash. Needs the large arena (`bigarena`).
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

fn draw_digit(builder: *scene.Builder, font: []const u8, px: f32, py: f32, d: usize, s: f32) {
    var row = 0usize
    while row < 5usize {
        let bits = usize(font[d * 5usize + row])
        var col = 0usize
        while col < 3usize {
            if ((bits >> (2usize - col)) & 1usize) == 1usize {
                fill(builder, px + f32(col) * s, py + f32(row) * s, s, s, 0.92, 0.96, 1.0)
            }
            col += 1usize
        }
        row += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let font: [50]u8 = [50]u8{ 7u8, 5u8, 5u8, 5u8, 7u8, 2u8, 6u8, 2u8, 2u8, 7u8, 7u8, 1u8, 7u8, 4u8, 7u8, 7u8, 1u8, 7u8, 1u8, 7u8, 5u8, 5u8, 7u8, 1u8, 1u8, 7u8, 4u8, 7u8, 1u8, 7u8, 7u8, 4u8, 7u8, 5u8, 7u8, 7u8, 1u8, 2u8, 2u8, 2u8, 7u8, 5u8, 7u8, 5u8, 7u8, 7u8, 5u8, 7u8, 1u8, 7u8 }
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("clock gpu failed\n")
        ret ok
    }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("clock queue failed\n")
        ret ok
    }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok {
        say("clock target failed\n")
        ret ok
    }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok {
        say("clock canvas failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("clock renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 256usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    // Wallpaper and a clock card.
    fill(&builder, 0.0, 0.0, 256.0, 256.0, 0.08, 0.10, 0.16)
    fill(&builder, 28.0, 88.0, 200.0, 80.0, 0.14, 0.16, 0.24)
    // The time "12:34" in large digits with a colon. Digit cells 24 wide (scale 8), 12 px apart.
    let s: f32 = 8.0
    draw_digit(&builder, font[0usize..], 48.0, 108.0, 1usize, s)
    draw_digit(&builder, font[0usize..], 80.0, 108.0, 2usize, s)
    fill(&builder, 120.0, 124.0, 8.0, 8.0, 0.92, 0.96, 1.0)
    fill(&builder, 120.0, 148.0, 8.0, 8.0, 0.92, 0.96, 1.0)
    draw_digit(&builder, font[0usize..], 140.0, 108.0, 3usize, s)
    draw_digit(&builder, font[0usize..], 172.0, 108.0, 4usize, s)
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("clock compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, canvas, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("clock render failed\n")
        ret ok
    }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok {
        say("clock presented failed\n")
        ret ok
    }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret pixels_error }
    if gpu.read_image(q, image, pixels) != ok {
        say("clock read failed\n")
        ret ok
    }
    var hash = 2166136261usize
    var i = 0usize
    while i < pixels.len {
        hash = ((hash ^ usize(pixels[i])) * 16777619usize) & 4294967295usize
        i += 1usize
    }
    say("clock app hash ")
    say_num(hash)
    say("\n")
    ret ok
}
