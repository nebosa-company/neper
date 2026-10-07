// The NeperOS Clock app (C113, D2179 face; D2188 live): a digital clock rendered through e.gfx.scene
// over the e.gpu CPU backend into a 256x256 surface -- a dark card on a wallpaper, the CURRENT time
// in HH:MM in large digits with a colon, drawn with the built-in 3x5 bitmap digit font. The time is
// read live from the wall clock through e.time (os.clock -> the PL031 RTC the device tree names), so
// the app is a real clock, not a fixed face. It prints the time it read and rendered (`clock live
// HH:MM`) and the epoch seconds, so a boot asserts a live reading without a frame golden (the frame
// varies with the clock). Started as the single raw program of the `gpu bigarena` boot; needs the
// large arena.
use e.mem
use e.os
use e.time
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

fn say2(value: usize) {
    var two: [2]u8 = zero
    two[0usize] = u8(value / 10usize) + 48u8
    two[1usize] = u8(value % 10usize) + 48u8
    say(two[0usize..2usize])
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
    // The LIVE time in HH:MM, read from the wall clock through e.time (os.clock -> the PL031 RTC):
    // seconds since the epoch folded to time of day. A real clock, not a fixed face (D2188).
    var hour = 0usize
    var minute = 0usize
    var epoch = 0usize
    let (wall, wall_error) = time.now()
    if wall_error == ok && wall.nanos > 0i64 {
        epoch = usize(wall.nanos / 1000000000i64)
        let day = epoch % 86400usize
        hour = day / 3600usize
        minute = (day % 3600usize) / 60usize
    }
    // Large digits with a colon. Digit cells 24 wide (scale 8), 12 px apart.
    let s: f32 = 8.0
    draw_digit(&builder, font[0usize..], 48.0, 108.0, hour / 10usize, s)
    draw_digit(&builder, font[0usize..], 80.0, 108.0, hour % 10usize, s)
    fill(&builder, 120.0, 124.0, 8.0, 8.0, 0.92, 0.96, 1.0)
    fill(&builder, 120.0, 148.0, 8.0, 8.0, 0.92, 0.96, 1.0)
    draw_digit(&builder, font[0usize..], 140.0, 108.0, minute / 10usize, s)
    draw_digit(&builder, font[0usize..], 172.0, 108.0, minute % 10usize, s)
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
    say("clock live ")
    say2(hour)
    say(":")
    say2(minute)
    say("\n")
    say("clock epoch ")
    say_num(epoch)
    say("\n")
    say("clock app hash ")
    say_num(hash)
    say("\n")
    appview.show(a, device, list, args)
    ret ok
}
