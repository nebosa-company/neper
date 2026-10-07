// The NeperOS unified shell (C112, D2192; C115, D2204): one process that IS the lock screen and the
// launcher, rendered over the real compositor AND interactive. It opens an e.ui.window (the
// compositor's shared surface -- the whole 1280x2856 panel), lays everything out in dp (412 wide; the
// scene's base transform scales dp to pixels) and draws through e.gfx.scene over the e.gpu CPU backend.
//
// It shows the lunar lock screen first -- the clock in Jost Bold, the date, a Moon-phase card and a
// notification card (Sora, Space Grotesk, Exo 2), and a dock -- over the wallpaper, then on the first
// key (a tap on the panel) the home screen: a status bar, and the app icons with their names under
// them. A second key launches an app as a process (os.launch), waits for it (os.reap) and returns
// Home. The top bar shows the C111 status service's snapshot over endpoints 3 (request) and 4
// (reply); the Moon phase and the date come from the same wall-clock reading (lunar.e).
//
// What it is handed (the kernel's initrd arguments): args[1] the wallpaper PNG, args[2..6] the fonts
// -- Jost Bold, Jost Regular, Sora Medium, Space Grotesk Regular, Exo 2 Regular -- each read in place.
// Without the fonts it skips the lock screen and draws the home screen without names; without the
// wallpaper it takes a 4x4 gradient the filesystem loader streams over slot 5, else a flat fill.
// Archive layout: [comp=0, shell=1, input=2, app=3, status=4, fs server=5, wall loader=6, wallpaper=7,
// fonts=8..12]. Boot `compositor bigarena unified` on the 1 GB display kernel.
use e.mem
use e.os
use e.gpu
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.image
use e.gfx.svg
use e.io
use e.fmt.png
use e.text.layout
use e.text.shape
use e.ui.window
use icons
use text
use lunar

const ROUTED: usize = 2usize
const NO_SLOT: usize = 99usize
const SENTINEL: usize = 65535usize
const LOW16: usize = 65535usize
const LOW32: usize = 4294967295usize
const EV_KEY: usize = 1usize
const EV_ABS: usize = 3usize
const BTN_LEFT: usize = 272usize
const APP_INDEX: usize = 3usize
const WALL_FROM: usize = 5usize
const STATUS_REQ: usize = 3usize
const STATUS_REPLY: usize = 4usize
const OP_QUIT: usize = 0usize
const OP_POST: usize = 2usize
const OP_SUBSCRIBE: usize = 3usize
const PRESENT: usize = 2147483648usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
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

// A number as text, two digits at least ("07"), in the arena.
fn two_digits(a: *mem.Arena, value: usize) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, 2usize)
    if buffer_error != ok { ret "00" }
    buffer[0usize] = u8(value / 10usize % 10usize) + 48u8
    buffer[1usize] = u8(value % 10usize) + 48u8
    ret buffer[0usize..2usize]
}

fn number_text(a: *mem.Arena, value: usize) -> str {
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
    let (buffer, buffer_error) = mem.alloc[u8](a, 20usize - at)
    if buffer_error != ok { ret "0" }
    var i = 0usize
    while at + i < 20usize {
        buffer[i] = digits[at + i]
        i += 1usize
    }
    ret buffer[0usize..20usize - at]
}

fn join3(a: *mem.Arena, first: str, second: str, third: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, first.len + second.len + third.len)
    if buffer_error != ok { ret first }
    var n = 0usize
    var i = 0usize
    while i < first.len {
        buffer[n] = first[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < second.len {
        buffer[n] = second[i]
        n += 1usize
        i += 1usize
    }
    i = 0usize
    while i < third.len {
        buffer[n] = third[i]
        n += 1usize
        i += 1usize
    }
    ret buffer[0usize..n]
}

fn fill(builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, c: paint.Color) -> err {
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(x, y, w, h), brush: paint.Brush { Solid: c } } })
    ret ok
}

// A rounded rectangle (a card), filled.
fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

// Text centred on `cx`.
fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    let width = text.measure(a, font, size, line)
    let (box, draw_error) = text.draw(a, builder, font, size, line, cx - width / 2.0, y, 0.0, 0u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

// One status glyph in the top bar (icons.bar): bright when `on`, dim when the provider is absent.
fn status_glyph(a: *mem.Arena, builder: *scene.Builder, which: usize, x: f32, on: bool, lit: paint.Color) -> err {
    var c = paint.Color { red: 0.5, green: 0.52, blue: 0.56, alpha: 1.0 }
    if on { c = lit }
    try svg.draw(a, builder, icons.bar(which), geometry.rect(x, 7.0, 16.0, 16.0), c)
    ret ok
}

// The status bar of the home screen: the time at the left, the provider glyphs at the right.
fn status_bar(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, has_fonts: bool, clock: str, snap: [5]usize) -> err {
    try fill(builder, 0.0, 0.0, 412.0, 30.0, paint.Color { red: 0.03, green: 0.04, blue: 0.06, alpha: 0.78 })
    let bright = paint.Color { red: 0.91, green: 0.92, blue: 0.94, alpha: 1.0 }
    let amber = paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
    if has_fonts {
        let (box, draw_error) = text.draw(a, builder, faces.jost, 16.0, clock, 16.0, 4.0, 0.0, 0u32, layout.Align.Start, bright)
        if draw_error != ok { ret draw_error }
    }
    // Glyph order in icons.bar: battery 0, bell 1, cell 2, moon 3, wifi 4.
    try status_glyph(a, builder, 0usize, 380.0, (snap[0usize] & PRESENT) != 0usize, bright)
    try status_glyph(a, builder, 4usize, 358.0, (snap[1usize] & PRESENT) != 0usize, bright)
    try status_glyph(a, builder, 2usize, 336.0, (snap[2usize] & PRESENT) != 0usize, bright)
    try status_glyph(a, builder, 1usize, 314.0, snap[4usize] > 0usize, amber)
    ret ok
}

// The wallpaper, drawn across the whole logical screen.
fn wallpaper_layer(builder: *scene.Builder, texture: scene.TextureId, width: f32, height: f32, logical_h: f32) -> err {
    try scene.push(builder, scene.Command { Image: scene.DrawImage { texture: texture, source: geometry.rect(0.0, 0.0, width, height), destination: geometry.rect(0.0, 0.0, 412.0, logical_h), opacity: 1.0 } })
    ret ok
}

// The lock screen: clock, date, the Moon-phase card, a notification card and the dock.
fn draw_lock(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, hour: usize, minute: usize, seconds: usize) -> err {
    let white = paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
    let soft = paint.Color { red: 0.86, green: 0.87, blue: 0.9, alpha: 1.0 }
    let glass = paint.Color { red: 0.1, green: 0.1, blue: 0.11, alpha: 0.62 }
    let clock = join3(a, two_digits(a, hour), ":", two_digits(a, minute))
    try centred(a, builder, faces.jost_bold, 104.0, clock, 206.0, 28.0, white)
    let (month, day) = lunar.month_day(seconds)
    let date_text = join3(a, lunar.month_name(month), " ", number_text(a, day))
    try centred(a, builder, faces.jost, 30.0, date_text, 206.0, 150.0, white)
    // The Moon phase and illumination, from the wall clock.
    let age = lunar.moon_age(seconds)
    try card(a, builder, 20.0, 232.0, 372.0, 82.0, 14.0, glass)
    let (t1, e1) = text.draw(a, builder, faces.sora, 18.0, join3(a, "Moon Phase: ", lunar.moon_phase(age), ""), 36.0, 244.0, 340.0, 1u32, layout.Align.Start, white)
    if e1 != ok { ret e1 }
    let (t2, e2) = text.draw(a, builder, faces.grotesk, 15.0, join3(a, number_text(a, lunar.moon_percent(age)), "% illuminated", ""), 36.0, 276.0, 340.0, 1u32, layout.Align.Start, soft)
    if e2 != ok { ret e2 }
    // A notification.
    try card(a, builder, 20.0, 324.0, 372.0, 112.0, 14.0, glass)
    let (t3, e3) = text.draw(a, builder, faces.sora, 18.0, "NASA Artemis Mission Update", 36.0, 336.0, 340.0, 1u32, layout.Align.Start, white)
    if e3 != ok { ret e3 }
    let (t4, e4) = text.draw(a, builder, faces.exo, 15.0, "Orion Crew Module successfully tests communication from the Moon\xE2\x80\x99s far side", 36.0, 366.0, 340.0, 3u32, layout.Align.Start, soft)
    if e4 != ok { ret e4 }
    // The dock: camera, settings, files, photos (the icon indexes in icons.e).
    try card(a, builder, 10.0, 756.0, 392.0, 118.0, 28.0, glass)
    var d = 0usize
    while d < 4usize {
        var which = 4usize
        if d == 1usize { which = 19usize }
        if d == 2usize { which = 11usize }
        if d == 3usize { which = 5usize }
        let cx = 51.5 + f32(d) * 103.0
        try svg.draw(a, builder, icons.app(which), geometry.rect(cx - 32.0, 770.0, 64.0, 64.0), white)
        try centred(a, builder, faces.jost, 13.0, icons.app_label(which), cx, 842.0, white)
        d += 1usize
    }
    ret ok
}

// The home screen: the status bar and every app icon with its name under it.
fn draw_home(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, has_fonts: bool, clock: str, snap: [5]usize) -> err {
    try status_bar(a, builder, faces, has_fonts, clock, snap)
    let white = paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
    var idx = 0usize
    while idx < icons.APP_COUNT {
        let col = idx % 4usize
        let row = idx / 4usize
        let cx = 51.5 + f32(col) * 103.0
        let y = 70.0 + f32(row) * 124.0
        try svg.draw(a, builder, icons.app(idx), geometry.rect(cx - 30.0, y, 60.0, 60.0), white)
        if has_fonts {
            // A dark pill under the name keeps it readable on bright terrain.
            let label = icons.app_label(idx)
            let label_width = text.measure(a, faces.jost, 14.5, label)
            var label_height: f32 = 17.0
            let (label_layout, label_error) = text.lay_out(a, faces.jost, 14.5, label, 0.0, 0u32, layout.Align.Start)
            if label_error == ok { label_height = label_layout.bounds.height }
            try card(a, builder, cx - label_width / 2.0 - 9.0, y + 63.0, label_width + 18.0, 24.0, 12.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6 })
            try centred(a, builder, faces.jost, 14.5, label, cx, y + 63.0 + (24.0 - label_height) / 2.0, white)
        }
        idx += 1usize
    }
    ret ok
}

// Decode a PNG and upload it as a texture; its size comes back with it.
fn load_wallpaper(a: *mem.Arena, renderer: *scene.Renderer, bytes: []const u8) -> (scene.TextureId, f32, f32, bool) {
    var reader_state: io.SliceReader = zero
    reader_state.data = bytes
    reader_state.off = 0usize
    let (decoded, decode_error) = png.decode(a, io.slice_reader(&reader_state), png.DecodeOptions { max_width: 0u32, max_height: 0u32, max_pixels: 0u64, verify_crc: true })
    if decode_error != ok { ret (zero, 0.0, 0.0, false) }
    let (view, view_error) = image.make_const(decoded.pixels, decoded.width, decoded.height, decoded.stride, decoded.format, decoded.alpha)
    if view_error != ok { ret (zero, 0.0, 0.0, false) }
    let (texture, upload_error) = scene.upload_image(renderer, view)
    if upload_error != ok { ret (zero, 0.0, 0.0, false) }
    ret (texture, f32(decoded.width), f32(decoded.height), true)
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

// Compile `list` as a scene of its own and draw it into the window, then present it.
var last_scene: scene.SceneId = zero
var has_last_scene: bool = false

fn show(renderer: *scene.Renderer, w: *window.Window, drawable: scene.Target, list: scene.DisplayList) -> bool {
    // The renderer holds a few scenes; the one drawn before this is released first.
    if has_last_scene {
        let released = scene.release_scene(renderer, last_scene)
        has_last_scene = false
    }
    let (scene_id, compile_error) = scene.compile(renderer, list)
    if compile_error != ok {
        say("shell compile failed\n")
        ret false
    }
    if scene.render(renderer, scene_id, drawable, geometry.Size { width: f32(os.SURFACE_W), height: f32(os.SURFACE_H) }) != ok {
        say("shell render failed\n")
        ret false
    }
    last_scene = scene_id
    has_last_scene = true
    if window.request_frame(w) != ok {
        say("shell present failed\n")
        ret false
    }
    ret true
}

// Build the home screen as a scene of its own and show it.
fn show_home(a: *mem.Arena, renderer: *scene.Renderer, w: *window.Window, drawable: scene.Target, faces: text.Faces, has_fonts: bool, clock: str, snap: [5]usize, wallpapered: bool, wall_texture: scene.TextureId, wall_w: f32, wall_h: f32, logical_h: f32, scale: f32) -> bool {
    let (builder_value, builder_error) = scene.builder(a, 4096usize)
    if builder_error != ok { ret false }
    var builder = builder_value
    let save: scene.Command = .Save
    if scene.push(&builder, save) != ok { ret false }
    if scene.push(&builder, scene.Command { Transform: geometry.transform_scale(scale, scale) }) != ok { ret false }
    if wallpapered {
        if wallpaper_layer(&builder, wall_texture, wall_w, wall_h, logical_h) != ok { ret false }
    } else {
        if fill(&builder, 0.0, 0.0, 412.0, logical_h, paint.Color { red: 0.09, green: 0.11, blue: 0.18, alpha: 1.0 }) != ok { ret false }
    }
    if draw_home(a, &builder, faces, has_fonts, clock, snap) != ok { ret false }
    let restore: scene.Command = .Restore
    if scene.push(&builder, restore) != ok { ret false }
    ret show(renderer, w, drawable, scene.finish(&builder))
}

// The icon under a tap (dp) on the home screen, or 99 outside every icon and its name.
fn icon_at(x: f32, y: f32) -> usize {
    if y < 70.0 || x < 0.0 || x >= 412.0 { ret 99usize }
    let col = usize(x / 103.0)
    let row = usize((y - 70.0) / 124.0)
    let within = (y - 70.0) - f32(row) * 124.0
    if within > 86.0 || col >= 4usize { ret 99usize }
    ret row * 4usize + col
}

// The archive program an icon starts, or 0 when its app is not written yet (the archive's apps
// follow the wallpaper and the five fonts: entry 13 is Calc, 14 is Clock, 15 is Tasks, 16 is Messages, 17 is Stocks).
fn program_of(icon: usize) -> usize {
    if icon == 9usize { ret 13usize }
    if icon == 8usize { ret 14usize }
    if icon == 10usize { ret 15usize }
    if icon == 1usize { ret 16usize }
    if icon == 20usize { ret 17usize }
    ret 0usize
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, gpu.Backend.Cpu, 0u32)
    if open_error != ok {
        say("shell gpu failed\n")
        ret ok
    }
    let (win, win_error) = window.open(a, device, window.Options { title: "shell", width: u32(os.SURFACE_W), height: u32(os.SURFACE_H), min_width: 0u32, min_height: 0u32, resizable: false, transparent: false, mode: window.Mode.Windowed })
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
    let (renderer_value, renderer_error) = scene.renderer(a, device, q, 2u32, 1u32)
    if renderer_error != ok {
        say("shell renderer failed\n")
        ret ok
    }
    var renderer = renderer_value
    // The fonts, handed in as args[2..6].
    let (faces, has_fonts) = text.load_faces(&renderer, args, 2usize)
    say("shell fonts ")
    if has_fonts { say("ok\n") } else { say("absent\n") }
    // The wallpaper: args[1] if the kernel handed one, else a PNG the filesystem loader streams over
    // slot 5 (a length word, then a word per byte), else nothing.
    var wallpapered = false
    var wall_texture: scene.TextureId = zero
    var wall_w = 0.0f32
    var wall_h = 0.0f32
    if args.len >= 2usize {
        say("shell wallpaper bytes ")
        say_num(args[1usize].len)
        say("\n")
        let (texture, tw, th, loaded) = load_wallpaper(a, &renderer, args[1usize])
        wall_texture = texture
        wall_w = tw
        wall_h = th
        wallpapered = loaded
    } else {
        let wall_len = os.recv(WALL_FROM, NO_SLOT)
        if wall_len > 0usize && wall_len <= 4096usize {
            let (wall_bytes, wall_alloc_error) = mem.alloc[u8](a, wall_len)
            if wall_alloc_error != ok { ret wall_alloc_error }
            var got = 0usize
            while got < wall_len {
                wall_bytes[got] = u8(os.recv(WALL_FROM, NO_SLOT))
                got += 1usize
            }
            let (texture, tw, th, loaded) = load_wallpaper(a, &renderer, wall_bytes)
            wall_texture = texture
            wall_w = tw
            wall_h = th
            wallpapered = loaded
        }
    }
    say("shell wallpaper ")
    if wallpapered && args.len >= 2usize {
        say("from initrd\n")
    } else if wallpapered {
        say("from fs\n")
    } else {
        say("fallback\n")
    }
    // Live status, from the C111 status service: subscribe, post a notification, read the snapshot,
    // then stop the service (this shell is its only client).
    var snap: [5]usize = zero
    let subscribed = os.send(STATUS_REQ, OP_SUBSCRIBE, NO_SLOT)
    read_snapshot(&snap)
    let posted = os.send(STATUS_REQ, OP_POST, NO_SLOT)
    read_snapshot(&snap)
    let stopped = os.send(STATUS_REQ, OP_QUIT, NO_SLOT)
    var seconds = 0usize
    var hour = 0usize
    var minute = 0usize
    if snap[3usize] > 0usize {
        seconds = snap[3usize] / 1000000000usize
        let day = seconds % 86400usize
        hour = day / 3600usize
        minute = (day % 3600usize) / 60usize
    }
    let clock = join3(a, two_digits(a, hour), ":", two_digits(a, minute))
    let scale = f32(os.SURFACE_W) / 412.0
    let logical_h = f32(os.SURFACE_H) / scale
    let ground = paint.Color { red: 0.09, green: 0.11, blue: 0.18, alpha: 1.0 }

    // Tell the compositor this app answers every routed event with a frame signal or a 0, so it can
    // take later frames after it starts routing input (value 2 on the frame endpoint).
    let announced = os.send(1usize, 2usize, NO_SLOT)

    // The lock screen, when there are fonts to draw it with.
    var locked = false
    if has_fonts {
        let (builder_value, builder_error) = scene.builder(a, 4096usize)
        if builder_error != ok { ret builder_error }
        var builder = builder_value
        let save: scene.Command = .Save
        try scene.push(&builder, save)
        try scene.push(&builder, scene.Command { Transform: geometry.transform_scale(scale, scale) })
        if wallpapered { try wallpaper_layer(&builder, wall_texture, wall_w, wall_h, logical_h) } else { try fill(&builder, 0.0, 0.0, 412.0, logical_h, ground) }
        try draw_lock(a, &builder, faces, hour, minute, seconds)
        let restore: scene.Command = .Restore
        try scene.push(&builder, restore)
        if !show(&renderer, &w, drawable, scene.finish(&builder)) { ret ok }
        locked = true
        say("shell lock presented\n")
        let age = lunar.moon_age(seconds)
        say("shell moon ")
        say(lunar.moon_phase(age))
        say(" ")
        say_num(lunar.moon_percent(age))
        say("\n")
    }
    say("shell status ")
    say_num(hour)
    say(":")
    say_num(minute)
    say("\n")
    say("shell status service notes ")
    say_num(snap[4usize])
    say("\n")

    // The home screen, drawn at once when there is no lock screen, else on the first key.
    var home_shown = false
    if !locked {
        let (builder_value, builder_error) = scene.builder(a, 4096usize)
        if builder_error != ok { ret builder_error }
        var builder = builder_value
        let save: scene.Command = .Save
        try scene.push(&builder, save)
        try scene.push(&builder, scene.Command { Transform: geometry.transform_scale(scale, scale) })
        if wallpapered { try wallpaper_layer(&builder, wall_texture, wall_w, wall_h, logical_h) } else { try fill(&builder, 0.0, 0.0, 412.0, logical_h, ground) }
        try draw_home(a, &builder, faces, has_fonts, clock, snap)
        let restore: scene.Command = .Restore
        try scene.push(&builder, restore)
        if !show(&renderer, &w, drawable, scene.finish(&builder)) { ret ok }
        home_shown = true
        say("shell presented\n")
    }

    // Live input: the compositor routes each event here (slot 2). A tablet sends the pointer's
    // position (absolute axes) and then the button; the shell keeps the position and a button-down
    // is a tap. A key-down (the keyboard fixtures) acts as a tap with no position. On the lock
    // screen a tap unlocks to the home screen. On the home screen a tap on an icon launches that app
    // as a process, waits for it, and redraws Home; a key launches the test app. Keep reading to the
    // sentinel.
    var pointer_x = 0usize
    var pointer_y = 0usize
    var launched_test = false
    var listening = true
    while listening {
        let word = os.recv(ROUTED, NO_SLOT)
        let etype = (word >> 48usize) & LOW16
        if etype == SENTINEL {
            listening = false
        } else {
            let code = (word >> 32usize) & LOW16
            let value = word & LOW32
            if etype == EV_ABS && code == 0usize { pointer_x = value }
            if etype == EV_ABS && code == 1usize { pointer_y = value }
            // A tap: the pointer's button, or any key. `by_key` marks the keyboard's.
            var tapped = false
            var by_key = false
            if etype == EV_KEY && value == 1usize {
                tapped = true
                if code != BTN_LEFT { by_key = true }
            }
            var framed = false
            if tapped && !home_shown {
                if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                home_shown = true
                framed = true
                say("shell unlocked\n")
                say("shell home presented\n")
            } else if tapped {
                var app = 99usize
                if by_key {
                    if !launched_test { app = 98usize }
                } else {
                    let icon = icon_at(f32(pointer_x) * 412.0 / 32768.0, f32(pointer_y) * logical_h / 32768.0)
                    if icon < icons.APP_COUNT {
                        say("shell tap ")
                        say(icons.app_label(icon))
                        say("\n")
                        app = icon
                    }
                }
                if app == 98usize {
                    // The keyboard fixtures' test app: no screen of its own.
                    launched_test = true
                    say("shell tap\n")
                    let child = os.launch(APP_INDEX)
                    say("shell launched app\n")
                    let code_test = os.reap(child)
                    say("shell app code ")
                    say_num(code_test)
                    say("\n")
                    say("shell home\n")
                } else if app < icons.APP_COUNT {
                    let program = program_of(app)
                    if program == 0usize {
                        say("shell no app yet\n")
                    } else {
                        say("shell launching ")
                        say(icons.app_label(app))
                        say("\n")
                        let child = os.launch(program)
                        // The app presents its own frames and answers the compositor; when it
                        // leaves it has told the compositor a frame will follow, which is Home.
                        let code_app = os.reap(child)
                        say("shell app code ")
                        say_num(code_app)
                        say("\n")
                        if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                        framed = true
                        say("shell home\n")
                    }
                }
            }
            // The compositor waits for one answer per routed event (lockstep, announced above): the
            // frame signal if this event drew a frame, else a 0.
            if !framed { let answered = os.send(1usize, 0usize, NO_SLOT) }
        }
    }
    say("shell done\n")
    ret ok
}
