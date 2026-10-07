// The NeperOS Calculator app (C113, D2180 face; D2189 compute): a result display and a 4x4 button
// grid rendered through e.gfx.scene over the e.gpu CPU backend into a 256x256 surface. Digit buttons
// show their digit in the built-in 3x5 bitmap font; operator buttons (/ * - + = C) show a small
// rect-composed symbol on a tinted tile. The display shows a COMPUTED result: a small calculator
// engine processes a fixed press sequence ("7 * 6 + 9 =") left-to-right and renders the computed
// value (51) right-aligned, and prints `calc result 51`. Deterministic, so the frame folds to a hash
// a host run reproduces (host==neperos). Needs the large arena (`bigarena`).
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
                fill(builder, px + f32(col) * s, py + f32(row) * s, s, s, 0.95, 0.95, 0.95)
            }
            col += 1usize
        }
        row += 1usize
    }
}

// An operator glyph at (px,py) in a ~16x16 box: 10=/ 11=* 12=- 13=+ 14== 15=C, rect-composed.
fn draw_symbol(builder: *scene.Builder, px: f32, py: f32, kind: usize) {
    if kind == 12usize {
        fill(builder, px, py + 7.0, 16.0, 3.0, 0.95, 0.95, 0.95)
    }
    if kind == 13usize {
        fill(builder, px, py + 7.0, 16.0, 3.0, 0.95, 0.95, 0.95)
        fill(builder, px + 7.0, py, 3.0, 16.0, 0.95, 0.95, 0.95)
    }
    if kind == 14usize {
        fill(builder, px, py + 4.0, 16.0, 3.0, 0.95, 0.95, 0.95)
        fill(builder, px, py + 10.0, 16.0, 3.0, 0.95, 0.95, 0.95)
    }
    if kind == 11usize {
        fill(builder, px + 5.0, py + 5.0, 6.0, 6.0, 0.95, 0.95, 0.95)
    }
    if kind == 10usize {
        fill(builder, px + 10.0, py, 3.0, 16.0, 0.95, 0.95, 0.95)
    }
    if kind == 15usize {
        fill(builder, px, py, 14.0, 3.0, 0.95, 0.95, 0.95)
        fill(builder, px, py, 3.0, 16.0, 0.95, 0.95, 0.95)
        fill(builder, px, py + 13.0, 14.0, 3.0, 0.95, 0.95, 0.95)
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let font: [50]u8 = [50]u8{ 7u8, 5u8, 5u8, 5u8, 7u8, 2u8, 6u8, 2u8, 2u8, 7u8, 7u8, 1u8, 7u8, 4u8, 7u8, 7u8, 1u8, 7u8, 1u8, 7u8, 5u8, 5u8, 7u8, 1u8, 1u8, 7u8, 4u8, 7u8, 1u8, 7u8, 7u8, 4u8, 7u8, 5u8, 7u8, 7u8, 1u8, 2u8, 2u8, 2u8, 7u8, 5u8, 7u8, 5u8, 7u8, 7u8, 5u8, 7u8, 1u8, 7u8 }
    // The 4x4 keypad: digits 0-9 and operators (10=/ 11=* 12=- 13=+ 14== 15=C).
    let keys: [16]u8 = [16]u8{ 7u8, 8u8, 9u8, 10u8, 4u8, 5u8, 6u8, 11u8, 1u8, 2u8, 3u8, 12u8, 0u8, 15u8, 14u8, 13u8 }
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("calc gpu failed\n")
        ret ok
    }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("calc queue failed\n")
        ret ok
    }
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok {
        say("calc target failed\n")
        ret ok
    }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok {
        say("calc canvas failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("calc renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 512usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    fill(&builder, 0.0, 0.0, 256.0, 256.0, 0.08, 0.09, 0.12)
    // The calculator engine (D2189): process a fixed press sequence "7 * 6 + 9 =" left-to-right (no
    // precedence, as a basic calculator), so the displayed number is COMPUTED, not a fixed face.
    let presses: [6]u8 = [6]u8{ 7u8, 11u8, 6u8, 13u8, 9u8, 14u8 }
    var acc = 0usize
    var cur = 0usize
    var op = 0usize
    var pi = 0usize
    while pi < 6usize {
        let kp = usize(presses[pi])
        if kp < 10usize {
            cur = cur * 10usize + kp
        } else {
            if op == 0usize {
                acc = cur
            } else {
                if op == 11usize { acc = acc * cur }
                if op == 13usize { acc = acc + cur }
                if op == 12usize { acc = acc - cur }
            }
            cur = 0usize
            if kp != 14usize { op = kp }
        }
        pi += 1usize
    }
    let result = acc
    // The result display, showing the computed value right-aligned.
    fill(&builder, 16.0, 12.0, 224.0, 40.0, 0.14, 0.16, 0.2)
    var rtmp = result
    var rx: f32 = 212.0
    if result == 0usize {
        draw_digit(&builder, font[0usize..], rx, 20.0, 0usize, 5.0)
    } else {
        while rtmp > 0usize {
            draw_digit(&builder, font[0usize..], rx, 20.0, rtmp % 10usize, 5.0)
            rtmp = rtmp / 10usize
            rx -= 20.0
        }
    }
    // The 4x4 keypad below the display.
    var r = 0usize
    while r < 4usize {
        var c = 0usize
        while c < 4usize {
            let key = usize(keys[r * 4usize + c])
            let bx = 16.0 + f32(c) * 58.0
            let by = 64.0 + f32(r) * 46.0
            var tint: f32 = 0.22
            if key >= 10usize { tint = 0.34 }
            fill(&builder, bx, by, 52.0, 40.0, tint, tint * 0.9, tint * 0.8)
            if key < 10usize {
                draw_digit(&builder, font[0usize..], bx + 18.0, by + 10.0, key, 4.0)
            } else {
                draw_symbol(&builder, bx + 18.0, by + 12.0, key)
            }
            c += 1usize
        }
        r += 1usize
    }
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("calc compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, canvas, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("calc render failed\n")
        ret ok
    }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok {
        say("calc presented failed\n")
        ret ok
    }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret pixels_error }
    if gpu.read_image(q, image, pixels) != ok {
        say("calc read failed\n")
        ret ok
    }
    var hash = 2166136261usize
    var i = 0usize
    while i < pixels.len {
        hash = ((hash ^ usize(pixels[i])) * 16777619usize) & 4294967295usize
        i += 1usize
    }
    say("calc result ")
    say_num(result)
    say("\n")
    say("calc app hash ")
    say_num(hash)
    say("\n")
    appview.show(a, device, list, args)
    ret ok
}
