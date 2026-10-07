// The NeperOS launcher's layout, first increment (C112, D2172): the wallpaper, the top bar and the
// 8-row by 5-column icon grid rendered through e.gfx.scene over the e.gpu CPU backend into a 256x256
// surface (the compositor's surface size). This is the launcher's visual skeleton -- the spatial
// layout the later increments fill in: a real PNG wallpaper from the filesystem, labels and real app
// icons, the C111 status in the top bar, presentation over the compositor, and tap-to-launch with
// Home. It folds the frame to a hash; a host run renders the same layout to the same hash. Needs the
// large arena (`bigarena`).
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene

const SIDE: usize = 256usize
const COLS: usize = 5usize
const ROWS: usize = 8usize

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
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("ui launcher gpu failed\n")
        ret ok
    }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("ui launcher queue failed\n")
        ret ok
    }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok {
        say("ui launcher target failed\n")
        ret ok
    }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok {
        say("ui launcher canvas failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("ui launcher renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    // Wallpaper: a cover fill (a real PNG from the filesystem replaces this later).
    fill(&builder, 0.0, 0.0, 256.0, 256.0, 0.09, 0.11, 0.18)
    // Top bar: a strip with five status ticks on the right (battery, Wi-Fi, 5G, clock, notifications).
    fill(&builder, 0.0, 0.0, 256.0, 18.0, 0.05, 0.06, 0.10)
    var tick = 0usize
    while tick < 5usize {
        let tx = 256.0 - 10.0 - f32(tick) * 12.0
        fill(&builder, tx, 5.0, 8.0, 8.0, 0.7, 0.75, 0.85)
        tick += 1usize
    }
    // The 8x5 icon grid: one tile per cell, shaded by index so the layout is visible.
    var r = 0usize
    while r < ROWS {
        var c = 0usize
        while c < COLS {
            let cx = 8.0 + f32(c) * 48.0
            let cy = 28.0 + f32(r) * 28.0
            let idx = r * COLS + c
            let shade = f32(idx) / f32(ROWS * COLS)
            fill(&builder, cx + 6.0, cy + 4.0, 48.0 - 12.0, 28.0 - 8.0, 0.3 + shade * 0.5, 0.5, 0.85 - shade * 0.4)
            c += 1usize
        }
        r += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("ui launcher compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, canvas, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("ui launcher render failed\n")
        ret ok
    }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok {
        say("ui launcher presented failed\n")
        ret ok
    }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret pixels_error }
    if gpu.read_image(q, image, pixels) != ok {
        say("ui launcher read failed\n")
        ret ok
    }
    var hash = 2166136261usize
    var i = 0usize
    while i < pixels.len {
        hash = ((hash ^ usize(pixels[i])) * 16777619usize) & 4294967295usize
        i += 1usize
    }
    say("ui launcher hash ")
    say_num(hash)
    say("\n")
    ret ok
}
