// The NeperOS launcher paging past 40 icons (C112, D2177). The grid holds 8x5 = 40 icons; with more
// apps than that the launcher pages. This renders a 45-app launcher: page 0 shows icons 1..40, page
// 1 shows icons 41..45, each with a page-dot row showing which page is current. It renders both
// pages into a 256x256 surface through e.gfx.scene over the e.gpu CPU backend and prints a hash of
// each; a host run renders the same two pages to the same two hashes. Needs the large arena.
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene

const SIDE: usize = 256usize
const PER_PAGE: usize = 40usize
const APP_COUNT: usize = 45usize

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

fn draw_label(builder: *scene.Builder, font: []const u8, px: f32, py: f32, n: usize, s: f32) {
    if n >= 10usize {
        draw_digit(builder, font, px, py, n / 10usize, s)
        draw_digit(builder, font, px + 4.0 * s, py, n % 10usize, s)
    } else {
        draw_digit(builder, font, px + 2.0 * s, py, n, s)
    }
}

// One page of the launcher: the icons whose global index falls on `page`, labelled by that index,
// plus a dot per page with the current page's dot lit.
fn draw_page(builder: *scene.Builder, font: []const u8, page: usize, app_count: usize) {
    fill(builder, 0.0, 0.0, 256.0, 256.0, 0.09, 0.11, 0.18)
    fill(builder, 0.0, 0.0, 256.0, 18.0, 0.05, 0.06, 0.10)
    var slot = 0usize
    while slot < PER_PAGE {
        let global = page * PER_PAGE + slot
        if global < app_count {
            let c = slot % 5usize
            let r = slot / 5usize
            let cx = 8.0 + f32(c) * 48.0
            let cy = 28.0 + f32(r) * 28.0
            let shade = f32(slot) / f32(PER_PAGE)
            fill(builder, cx + 6.0, cy + 4.0, 36.0, 20.0, 0.3 + shade * 0.5, 0.5, 0.85 - shade * 0.4)
            draw_label(builder, font, cx + 15.0, cy + 8.0, global + 1usize, 2.0)
        }
        slot += 1usize
    }
    // Page dots: one per page, the current one lit.
    let pages = (app_count + PER_PAGE - 1usize) / PER_PAGE
    var dot = 0usize
    while dot < pages {
        var bright: f32 = 0.3
        if dot == page { bright = 0.9 }
        fill(builder, 116.0 + f32(dot) * 12.0, 246.0, 8.0, 6.0, bright, bright, bright)
        dot += 1usize
    }
}

fn render_page(a: *mem.Arena, device: *gpu.Device, q: *gpu.Queue, renderer: *scene.Renderer, font: []const u8, page: usize) -> (usize, err) {
    let (frames, frames_error) = gpu.open_target(q, gpu.Surface { kind: gpu.SurfaceKind.Offscreen, handle: zero, context: zero }, u32(SIDE), u32(SIDE), gpu.Format.Bgra8)
    if frames_error != ok { ret (0usize, frames_error) }
    let (canvas, canvas_error) = scene.target_of(a, frames)
    if canvas_error != ok { ret (0usize, canvas_error) }
    let (builder_value, builder_error) = scene.builder(a, 1536usize)
    if builder_error != ok { ret (0usize, builder_error) }
    var builder = builder_value
    draw_page(&builder, font, page, APP_COUNT)
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(renderer, list)
    if compile_error != ok { ret (0usize, compile_error) }
    let render_error = scene.render(renderer, scene_id, canvas, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok { ret (0usize, render_error) }
    let (image, presented_error) = gpu.presented(frames)
    if presented_error != ok { ret (0usize, presented_error) }
    let (pixels, pixels_error) = mem.alloc[u32](a, SIDE * SIDE)
    if pixels_error != ok { ret (0usize, pixels_error) }
    if gpu.read_image(q, image, pixels) != ok { ret (0usize, frames_error) }
    var hash = 2166136261usize
    var i = 0usize
    while i < pixels.len {
        hash = ((hash ^ usize(pixels[i])) * 16777619usize) & 4294967295usize
        i += 1usize
    }
    ret (hash, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let font: [50]u8 = [50]u8{ 7u8, 5u8, 5u8, 5u8, 7u8, 2u8, 6u8, 2u8, 2u8, 7u8, 7u8, 1u8, 7u8, 4u8, 7u8, 7u8, 1u8, 7u8, 1u8, 7u8, 5u8, 5u8, 7u8, 1u8, 1u8, 7u8, 4u8, 7u8, 1u8, 7u8, 7u8, 4u8, 7u8, 5u8, 7u8, 7u8, 1u8, 2u8, 2u8, 2u8, 7u8, 5u8, 7u8, 5u8, 7u8, 7u8, 5u8, 7u8, 1u8, 7u8 }
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("ui pages gpu failed\n")
        ret ok
    }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok {
        say("ui pages queue failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 2u32, 1u32)
    if renderer_error != ok {
        say("ui pages renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    var page = 0usize
    while page < 2usize {
        let (hash, page_error) = render_page(a, device, q, &renderer, font[0usize..], page)
        if page_error != ok {
            say("ui pages render failed\n")
            ret ok
        }
        say("ui pages page ")
        say_num(page)
        say(" hash ")
        say_num(hash)
        say("\n")
        page += 1usize
    }
    ret ok
}
