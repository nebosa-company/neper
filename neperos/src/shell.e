// The NeperOS unified shell (C112, D2192): one process that IS the launcher, rendered over the real
// compositor AND interactive. It opens an e.ui.window (the compositor's shared surface), renders the
// launcher layout (wallpaper, top bar, 8x5 icon grid) through e.gfx.scene over the e.gpu CPU backend,
// and presents it (window.request_frame -> os.window_present: blit + signal, the compositor
// composites it to the display). Then it listens for input the compositor routes to it (slot 2, the
// C109 path); on the first key-down -- a tap on an icon -- it launches an app as a process
// (os.launch), waits for it (os.reap), and returns Home. This hosts the launcher on the display with
// LIVE tap input. The top bar shows the C111 status service's snapshot (D2195): the shell subscribes
// over endpoints 3 (request) and 4 (reply), posts one notification and draws a tick per provider and
// per notification, with the clock from the snapshot. (The earlier "AUX heisenbug" that kept the
// status service out was a boot-word collision, fixed in D2194.)
// The wallpaper comes from the C106 filesystem through wall_loader.e (D2196), received on slot 5.
// Archive layout: [comp=0, shell=1, input=2, app=3, status=4, fs server=5, wall loader=6]. Boot
// `compositor bigarena unified` with a virtio-blk disk.
use e.mem
use e.os
use e.time
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.image
use e.io
use e.fmt.png
use e.gfx.svg
use icons
use e.ui.window

const ROUTED: usize = 2usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
const LOW16: usize = 65535usize
const LOW32: usize = 4294967295usize
const EV_KEY: usize = 1usize
const APP_INDEX: usize = 3usize
const WALL_FROM: usize = 5usize
const STATUS_REQ: usize = 3usize
const STATUS_REPLY: usize = 4usize
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
                fill(builder, px + f32(col) * s, py + f32(row) * s, s, s, 0.85, 0.88, 0.95)
            }
            col += 1usize
        }
        row += 1usize
    }
}

// The launcher's chrome: the top-bar strip, then the 8x5 grid. The eight app icons (icons.e, drawn
// through e.gfx.svg) fill the first cells; the rest stay empty until more apps exist.
fn draw_launcher(a: *mem.Arena, builder: *scene.Builder) -> err {
    fill(builder, 0.0, 0.0, 256.0, 18.0, 0.05, 0.06, 0.10)
    let ink = paint.Color { red: 0.91, green: 0.92, blue: 0.94, alpha: 1.0 }
    var r = 0usize
    while r < 8usize {
        var c = 0usize
        while c < 5usize {
            let cx = 8.0 + f32(c) * 48.0
            let cy = 28.0 + f32(r) * 28.0
            let idx = r * 5usize + c
            if idx < icons.APP_COUNT {
                try svg.draw(a, builder, icons.app(idx), geometry.rect(cx + 12.0, cy + 2.0, 24.0, 24.0), ink)
            }
            c += 1usize
        }
        r += 1usize
    }
    ret ok
}

// One status glyph in the top bar (icons.bar): bright when `on`, dim when the provider is absent.
fn status_glyph(a: *mem.Arena, builder: *scene.Builder, which: usize, x: f32, on: bool, lit: paint.Color) -> err {
    var c = paint.Color { red: 0.32, green: 0.33, blue: 0.37, alpha: 1.0 }
    if on { c = lit }
    try svg.draw(a, builder, icons.bar(which), geometry.rect(x, 3.0, 12.0, 12.0), c)
    ret ok
}

// Read the five-word snapshot: battery, Wi-Fi, cellular, wall-clock nanoseconds, notification count.
fn read_snapshot(into: *[5]usize) {
    var words: [5]usize = zero
    var i = 0usize
    while i < 5usize {
        words[i] = os.recv(STATUS_REPLY, NO_SLOT)
        i += 1usize
    }
    *into = words
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("shell gpu failed\n")
        ret ok
    }
    let (win, win_error) = window.open(a, device, window.Options { title: "shell", width: 256u32, height: 256u32, min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: window.Mode.Windowed })
    if win_error != ok {
        say("shell window failed\n")
        ret ok
    }
    var w = win
    let (drawable, drawable_error) = window.draw_target(&w)
    if drawable_error != ok {
        say("shell target failed\n")
        ret ok
    }
    let (q, q_error) = gpu.queue(device)
    if q_error != ok {
        say("shell queue failed\n")
        ret ok
    }
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 1u32, 1u32)
    if renderer_error != ok {
        say("shell renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    let (builder_value, builder_error) = scene.builder(a, 4096usize)
    if builder_error != ok { ret builder_error }
    var builder = builder_value
    // The wallpaper: the loader process read a PNG from the C106 filesystem and sends it here (a
    // length word, then a word per byte). It is decoded and drawn scaled to cover; with no wallpaper
    // (an absent or failed loader answers with a length no PNG reaches) the backdrop is a solid fill.
    var wallpapered = false
    let wall_len = os.recv(WALL_FROM, NO_SLOT)
    if wall_len > 0usize && wall_len <= 4096usize {
        let (wall_bytes, wall_alloc_error) = mem.alloc[u8](a, wall_len)
        if wall_alloc_error != ok { ret wall_alloc_error }
        var got = 0usize
        while got < wall_len {
            wall_bytes[got] = u8(os.recv(WALL_FROM, NO_SLOT))
            got += 1usize
        }
        var reader_state: io.SliceReader = zero
        reader_state.data = wall_bytes[0usize..wall_len]
        reader_state.off = 0usize
        let (decoded, decode_error) = png.decode(a, io.slice_reader(&reader_state), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 0u64, verify_crc: true })
        if decode_error == ok {
            let (wall_view, wall_view_error) = image.make_const(decoded.pixels, decoded.width, decoded.height, decoded.stride, decoded.format, decoded.alpha)
            if wall_view_error == ok {
                let (texture, upload_error) = scene.upload_image(&renderer, wall_view)
                if upload_error == ok {
                    let wallpaper = scene.push(&builder, scene.Command { Image: scene.DrawImage { texture: texture, source: geometry.rect(0.0, 0.0, f32(decoded.width), f32(decoded.height)), destination: geometry.rect(0.0, 0.0, 256.0, 256.0), opacity: 1.0 } })
                    wallpapered = true
                }
            }
        }
    }
    if !wallpapered { fill(&builder, 0.0, 0.0, 256.0, 256.0, 0.09, 0.11, 0.18) }
    say("shell wallpaper ")
    if wallpapered { say("from fs\n") } else { say("fallback\n") }
    try draw_launcher(a, &builder)
    // Live status in the top bar, from the C111 status service: subscribe, post a notification, read
    // the snapshot, then stop the service (this shell is its only client).
    var snap: [5]usize = zero
    let subscribed = os.send(STATUS_REQ, OP_SUBSCRIBE, NO_SLOT)
    read_snapshot(&snap)
    let posted = os.send(STATUS_REQ, OP_POST, NO_SLOT)
    read_snapshot(&snap)
    let stopped = os.send(STATUS_REQ, OP_QUIT, NO_SLOT)
    let bright = paint.Color { red: 0.91, green: 0.92, blue: 0.94, alpha: 1.0 }
    let amber = paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
    // Glyph order in icons.bar: battery 0, bell 1, cell 2, moon 3, wifi 4.
    try status_glyph(a, &builder, 0usize, 242.0, (snap[0usize] & PRESENT) != 0usize, bright)
    try status_glyph(a, &builder, 4usize, 228.0, (snap[1usize] & PRESENT) != 0usize, bright)
    try status_glyph(a, &builder, 2usize, 214.0, (snap[2usize] & PRESENT) != 0usize, bright)
    try status_glyph(a, &builder, 1usize, 200.0, snap[4usize] > 0usize, amber)
    var hour = 0usize
    var minute = 0usize
    if snap[3usize] > 0usize {
        let day = (snap[3usize] / 1000000000usize) % 86400usize
        hour = day / 3600usize
        minute = (day % 3600usize) / 60usize
    }
    let font: [50]u8 = [50]u8{ 7u8, 5u8, 5u8, 5u8, 7u8, 2u8, 6u8, 2u8, 2u8, 7u8, 7u8, 1u8, 7u8, 4u8, 7u8, 7u8, 1u8, 7u8, 1u8, 7u8, 5u8, 5u8, 7u8, 1u8, 1u8, 7u8, 4u8, 7u8, 1u8, 7u8, 7u8, 4u8, 7u8, 5u8, 7u8, 7u8, 1u8, 2u8, 2u8, 2u8, 7u8, 5u8, 7u8, 5u8, 7u8, 7u8, 5u8, 7u8, 1u8, 7u8 }
    draw_digit(&builder, font[0usize..], 6.0, 5.0, hour / 10usize, 2.0)
    draw_digit(&builder, font[0usize..], 14.0, 5.0, hour % 10usize, 2.0)
    fill(&builder, 21.0, 7.0, 2.0, 2.0, 0.85, 0.88, 0.95)
    fill(&builder, 21.0, 11.0, 2.0, 2.0, 0.85, 0.88, 0.95)
    draw_digit(&builder, font[0usize..], 25.0, 5.0, minute / 10usize, 2.0)
    draw_digit(&builder, font[0usize..], 33.0, 5.0, minute % 10usize, 2.0)
    let list = scene.finish(&builder)
    let (scene_id, compile_error) = scene.compile(&renderer, list)
    if compile_error != ok {
        say("shell compile failed\n")
        ret ok
    }
    let render_error = scene.render(&renderer, scene_id, drawable, geometry.Size { width: 256.0, height: 256.0 })
    if render_error != ok {
        say("shell render failed\n")
        ret ok
    }
    if window.request_frame(&w) != ok {
        say("shell present failed\n")
        ret ok
    }
    say("shell presented\n")
    say("shell status ")
    say2(hour)
    say(":")
    say2(minute)
    say("\n")
    say("shell status service notes ")
    say_num(snap[4usize])
    say("\n")
    // Live input: the compositor routes each event here (slot 2). The first key-down is a tap on an
    // icon -- launch an app as a process, reap it, and return Home. Keep reading to the sentinel.
    var launched = false
    var listening = true
    while listening {
        let word = os.recv(ROUTED, NO_SLOT)
        let etype = (word >> 48usize) & LOW16
        if etype == SENTINEL {
            listening = false
        } else {
            let value = word & LOW32
            if etype == EV_KEY && value == 1usize && !launched {
                launched = true
                say("shell tap\n")
                let child = os.launch(APP_INDEX)
                say("shell launched app\n")
                let code = os.reap(child)
                say("shell app code ")
                say_num(code)
                say("\n")
                say("shell home\n")
            }
        }
    }
    say("shell done\n")
    ret ok
}
