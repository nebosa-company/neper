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
use package
use server_key
use fsproto
use theme
use sysettings
use sensorclient

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
// (C126) The filesystem's two endpoints, when the machine has a disk: requests out, replies in.
const FS_REQ: usize = 6usize
const FS_REP: usize = 7usize
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

// (C126) The time of day as the 24-hour clock or the 12-hour one with AM or PM, by the system setting.
fn clock_text(a: *mem.Arena, hour: usize, minute: usize) -> str {
    if theme.is_24h() { ret join3(a, two_digits(a, hour), ":", two_digits(a, minute)) }
    var hour12 = hour % 12usize
    if hour12 == 0usize { hour12 = 12usize }
    var suffix = " AM"
    if hour >= 12usize { suffix = " PM" }
    ret join3(a, join3(a, number_text(a, hour12), ":", two_digits(a, minute)), suffix, "")
}

// (C126) The brightness setting as a dimming layer over the whole screen, nothing at the level the system starts at.
fn dim_layer(builder: *scene.Builder, logical_h: f32) -> err {
    let alpha = theme.dim_alpha()
    if alpha > 0.0 { try fill(builder, 0.0, 0.0, 412.0, logical_h, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: alpha }) }
    ret ok
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
// (C163) Whether the torch is on, as the lock screen's quick toggle last left it (the settings server holds the truth).
var lock_torch: bool = false

fn draw_lock(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, hour: usize, minute: usize, seconds: usize) -> err {
    let white = paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
    let soft = paint.Color { red: 0.86, green: 0.87, blue: 0.9, alpha: 1.0 }
    let glass = paint.Color { red: 0.1, green: 0.1, blue: 0.11, alpha: 0.62 }
    if theme.is_24h() {
        try centred(a, builder, faces.jost_bold, 104.0, clock_text(a, hour, minute), 206.0, 28.0, white)
    } else {
        // The 12-hour clock: the digits at the large size and AM or PM small beside them, so it fits the screen.
        var hour12 = hour % 12usize
        if hour12 == 0usize { hour12 = 12usize }
        var suffix = "AM"
        if hour >= 12usize { suffix = "PM" }
        let digits = join3(a, number_text(a, hour12), ":", two_digits(a, minute))
        let digits_width = text.measure(a, faces.jost_bold, 104.0, digits)
        let suffix_width = text.measure(a, faces.jost_bold, 34.0, suffix)
        let left = 206.0 - (digits_width + 10.0 + suffix_width) / 2.0
        let (digits_box, digits_error) = text.draw(a, builder, faces.jost_bold, 104.0, digits, left, 28.0, 0.0, 0u32, layout.Align.Start, white)
        if digits_error != ok { ret digits_error }
        let (suffix_box, suffix_error) = text.draw(a, builder, faces.jost_bold, 34.0, suffix, left + digits_width + 10.0, 40.0, 0.0, 0u32, layout.Align.Start, white)
        if suffix_error != ok { ret suffix_error }
    }
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
    // (C163) The torch's quick toggle, above the dock at the left: amber while it is on.
    var torch_fill = glass
    if lock_torch { torch_fill = paint.Color { red: 0.99, green: 0.78, blue: 0.30, alpha: 1.0 } }
    try card(a, builder, 24.0, 680.0, 56.0, 56.0, 28.0, torch_fill)
    try centred(a, builder, faces.jost, 15.0, "Torch", 52.0, 697.0, white)
    // (C176) The fingerprint pad, above the dock at the right: a touch of the enrolled finger unlocks.
    try card(a, builder, 332.0, 680.0, 56.0, 56.0, 28.0, glass)
    try centred(a, builder, faces.jost, 13.0, "Print", 360.0, 698.0, white)
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
// (C126) The icons Settings uninstalled, one bit per icon index (the settings server's mask): the home screen lays
// out the rest in order, and a tap on a position starts the icon that stands there.
var hidden_mask: usize = 0usize

// (C124) The one installed app: a signed package the kernel handed the shell (its last archive entry), verified
// against the server's key. Its name, and its image in a page-aligned buffer, until it is launched from memory.
var installed_name: [24]u8 = zero
var installed_len: usize = 0usize
var installed_va: usize = 0usize
var installed_pages: usize = 0usize
// The capabilities the manifest declared: bit 0 network, bit 1 storage.
var installed_caps: usize = 0usize
// Whether the user allowed the installed app's capabilities this boot (the first run asks).
var installed_allowed: bool = false

fn visible_count() -> usize {
    var count = 0usize
    // (not counting the installed app, which has the position after the last one)
    var i = 0usize
    while i < icons.APP_COUNT {
        if ((hidden_mask >> i) & 1usize) == 0usize { count += 1usize }
        i += 1usize
    }
    ret count
}

// The icon at grid position `position`, or 99.
fn visible_icon(position: usize) -> usize {
    var seen = 0usize
    var i = 0usize
    while i < icons.APP_COUNT {
        if ((hidden_mask >> i) & 1usize) == 0usize {
            if seen == position { ret i }
            seen += 1usize
        }
        i += 1usize
    }
    ret 99usize
}

fn draw_home(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, has_fonts: bool, clock: str, snap: [5]usize) -> err {
    try status_bar(a, builder, faces, has_fonts, clock, snap)
    let white = paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
    var idx = 0usize
    var extra = 0usize
    if installed_len > 0usize { extra = 1usize }
    while idx < visible_count() + extra {
        let icon = visible_icon(idx)
        var glyph = icons.app(icon)
        var caption = icons.app_label(icon)
        if icon == 99usize {
            glyph = icons.app(26usize)
            caption = installed_name[0usize..installed_len]
        }
        let col = idx % 4usize
        let row = idx / 4usize
        let cx = 51.5 + f32(col) * 103.0
        let y = 70.0 + f32(row) * 104.0
        try svg.draw(a, builder, glyph, geometry.rect(cx - 30.0, y, 60.0, 60.0), white)
        if has_fonts {
            // A dark pill under the name keeps it readable on bright terrain.
            let label = caption
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
// (C126) The system theme word (theme.e): handed to every app launched, above its program index, and replaced by
// the exit code the Settings app (archive entry 24) returns.
var theme_word: usize = 5365usize
const SETTINGS_PROGRAM: usize = 24usize
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
    if dim_layer(&builder, logical_h) != ok { ret false }
    let restore: scene.Command = .Restore
    if scene.push(&builder, restore) != ok { ret false }
    ret show(renderer, w, drawable, scene.finish(&builder))
}

// (C124) The first-run prompt for the installed app: the home screen under a scrim and a card that names the app,
// says it was generated, lists the capabilities its manifest declared and offers Allow and Cancel (the rects the
// tap handler tests: Allow x 56..184, Cancel x 228..356, both y 490..538).
fn show_prompt(a: *mem.Arena, renderer: *scene.Renderer, w: *window.Window, drawable: scene.Target, faces: text.Faces, has_fonts: bool, clock: str, snap: [5]usize, wallpapered: bool, wall_texture: scene.TextureId, wall_w: f32, wall_h: f32, logical_h: f32, scale: f32) -> bool {
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
    if fill(&builder, 0.0, 0.0, 412.0, logical_h, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6 }) != ok { ret false }
    let cream = paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
    let ink = paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
    let muted = paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 }
    if card(a, &builder, 36.0, 270.0, 340.0, 300.0, 24.0, cream) != ok { ret false }
    if centred(a, &builder, faces.jost_bold, 22.0, installed_name[0usize..installed_len], 206.0, 292.0, ink) != ok { ret false }
    if centred(a, &builder, faces.grotesk, 13.0, "A generated app. It asks for:", 206.0, 328.0, muted) != ok { ret false }
    var line: f32 = 364.0
    if (installed_caps & 1usize) != 0usize {
        if centred(a, &builder, faces.jost, 18.0, "The network", 206.0, line, ink) != ok { ret false }
        line += 30.0
    }
    if (installed_caps & 2usize) != 0usize {
        if centred(a, &builder, faces.jost, 18.0, "Storage", 206.0, line, ink) != ok { ret false }
        line += 30.0
    }
    if installed_caps == 0usize {
        if centred(a, &builder, faces.jost, 18.0, "Nothing beyond its own screen", 206.0, line, ink) != ok { ret false }
    }
    if card(a, &builder, 56.0, 490.0, 128.0, 48.0, 24.0, paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }) != ok { ret false }
    if centred(a, &builder, faces.jost, 18.0, "Allow", 120.0, 503.0, ink) != ok { ret false }
    if card(a, &builder, 228.0, 490.0, 128.0, 48.0, 24.0, paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }) != ok { ret false }
    if centred(a, &builder, faces.jost, 18.0, "Cancel", 292.0, 503.0, ink) != ok { ret false }
    let restore: scene.Command = .Restore
    if scene.push(&builder, restore) != ok { ret false }
    ret show(renderer, w, drawable, scene.finish(&builder))
}

// (C126) The lock screen again, for the Screen timeout setting.
fn show_lock(a: *mem.Arena, renderer: *scene.Renderer, w: *window.Window, drawable: scene.Target, faces: text.Faces, wallpapered: bool, wall_texture: scene.TextureId, wall_w: f32, wall_h: f32, logical_h: f32, scale: f32, hour: usize, minute: usize, seconds: usize) -> bool {
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
    if draw_lock(a, &builder, faces, hour, minute, seconds) != ok { ret false }
    if dim_layer(&builder, logical_h) != ok { ret false }
    let restore: scene.Command = .Restore
    if scene.push(&builder, restore) != ok { ret false }
    ret show(renderer, w, drawable, scene.finish(&builder))
}

// (C126) The Time zone setting (0 UTC, 1 Berlin +1, 2 New York -5, 3 Tokyo +9) applied to UTC seconds.
fn zone_seconds(utc: usize, step: usize) -> usize {
    var hours = 24usize
    if step == 1usize { hours = 25usize }
    if step == 2usize { hours = 19usize }
    if step == 3usize { hours = 33usize }
    ret utc + hours * 3600usize - 86400usize
}

// The Screen timeout setting (0 to 3) as the number of 500 ms ticks of no touch before the lock screen returns.
fn timeout_ticks(step: usize) -> usize {
    if step == 0usize { ret 30usize }
    if step == 1usize { ret 60usize }
    if step == 2usize { ret 120usize }
    ret 600usize
}

// The icon under a tap (dp) on the home screen, or 99 outside every icon and its name.
fn icon_at(x: f32, y: f32) -> usize {
    if y < 70.0 || x < 0.0 || x >= 412.0 { ret 99usize }
    let col = usize(x / 103.0)
    let row = usize((y - 70.0) / 104.0)
    let within = (y - 70.0) - f32(row) * 104.0
    if within > 86.0 || col >= 4usize { ret 99usize }
    ret row * 4usize + col
}


// (C124) Take a signed package: check it against the server's key, keep the manifest's name and capabilities and the
// image in a page-aligned buffer, and (when `persist`) write the package to /apps so the next boot has it. True when it
// was adopted.
fn adopt(a: *mem.Arena, data: str, persist: bool) -> bool {
    // (C143) The revocation list on the disk, if there is one: an app on it is refused whatever its signature.
    var revocations: [1024]u8 = zero
    var revocation_len = 0usize
    let (rev_size, rev_kind, rev_day, rev_found) = fsproto.stat(FS_REQ, FS_REP, "/revoked")
    if rev_found && rev_size > 0usize && rev_size <= 1024usize {
        let (rev_got, rev_ok) = fsproto.read_big(FS_REQ, FS_REP, "/revoked", mem.address_of(&revocations[0usize]), rev_size)
        if rev_ok { revocation_len = rev_got }
    }
    let (pkg, pkg_error) = package.check_revocable(data, server_key.public(), revocations[0usize..revocation_len])
    if pkg_error == package.Revoked {
        say("shell package revoked\n")
        ret false
    }
    if pkg_error != ok {
        say("shell package refused\n")
        ret false
    }
    let (pkg_name, has_pkg_name) = package.value(pkg, "name")
    var n = 0usize
    while n < pkg_name.len && n < 24usize {
        installed_name[n] = pkg_name[n]
        n += 1usize
    }
    let pages = (pkg.image.len + 4095usize) / 4096usize
    let (image_buf, image_error) = mem.alloc[u8](a, pages * 4096usize + 4096usize)
    if image_error != ok { ret false }
    let base = (mem.address_of(&image_buf[0usize]) + 4095usize) & ~4095usize
    var b = 0usize
    while b < pkg.image.len {
        os.store8(base + b, pkg.image[b])
        b += 1usize
    }
    installed_va = base
    installed_pages = pages
    installed_len = n
    installed_caps = 0usize
    if package.declares(pkg, "network") { installed_caps = installed_caps | 1usize }
    if package.declares(pkg, "storage") { installed_caps = installed_caps | 2usize }
    say("shell installed ")
    say(installed_name[0usize..installed_len])
    say("\n")
    if persist {
        // /apps/<the name's letters and digits, lower case>.npkg
        let made_dir = fsproto.mkdir(FS_REQ, FS_REP, "/apps")
        var file: [24]u8 = zero
        var f = 0usize
        var k = 0usize
        while k < installed_len && f < 14usize {
            var c = installed_name[k]
            if c >= 65u8 && c <= 90u8 { c = c + 32u8 }
            if (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) {
                file[f] = c
                f += 1usize
            }
            k += 1usize
        }
        let suffix = ".npkg"
        var s = 0usize
        while s < suffix.len {
            file[f + s] = suffix[s]
            s += 1usize
        }
        let path = join3(a, "/apps/", file[0usize..f + suffix.len], "")
        if fsproto.write_big(FS_REQ, FS_REP, path, mem.address_of(&data[0usize]), data.len) {
            say("shell package kept ")
            say(path)
            say("\n")
        }
    }
    ret true
}

// (C124) The first package in /apps, read from the disk, when the archive carried none.
fn adopt_from_disk(a: *mem.Arena) -> bool {
    var names: [256]u8 = zero
    let (count, listed) = fsproto.list(FS_REQ, FS_REP, "/apps", mem.address_of(&names[0usize]), 256usize)
    if !listed || count == 0usize { ret false }
    var at = 0usize
    while at < count && names[at] != 10u8 { at += 1usize }
    let path = join3(a, "/apps/", names[0usize..at], "")
    let (size, kind, day, found) = fsproto.stat(FS_REQ, FS_REP, path)
    if !found || size == 0usize || size > 4194304usize { ret false }
    let (buffer, buffer_error) = mem.alloc[u8](a, size)
    if buffer_error != ok { ret false }
    let (got, read_ok) = fsproto.read_big(FS_REQ, FS_REP, path, mem.address_of(&buffer[0usize]), size)
    if !read_ok || got != size { ret false }
    ret adopt(a, buffer[0usize..got], false)
}

// The system theme Settings stored (C126, theme.e), or 0 when there is no disk or no file. The first send is
// refused on a machine without the endpoints.
fn stored_theme() -> usize {
    let sent = os.send(FS_REQ, fsproto.OP_READ, fsproto.NO_SLOT)
    if sent == 18446744073709551615usize { ret 0usize }
    fsproto.send_str(FS_REQ, "/settings")
    let result = os.recv(FS_REP, fsproto.NO_SLOT)
    var raw: [48]u8 = zero
    let count = fsproto.recv_bytes(FS_REP, mem.address_of(&raw[0usize]), 48usize)
    if result != fsproto.RESULT_OK { ret 0usize }
    ret theme.stored_word(raw[0usize..count])
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
    // The settings server's word (C126), else what the file holds, else the default.
    var stored = sysettings.word()
    var source = "server"
    if !theme.valid(stored) {
        stored = stored_theme()
        source = "fs"
    }
    if stored != 0usize && stored != theme.DEFAULT {
        theme_word = stored
        theme.set(theme_word)
        say("shell theme from ")
        say(source)
        say(" ")
        say_num(stored)
        say("\n")
    }
    // (C124) A signed app package the kernel mapped after the files (args[7]), else the first one kept in /apps:
    // checked against the server's key and, when it passes, held for the last icon of the grid.
    var adopted = false
    if args.len >= 8usize { adopted = adopt(a, args[7usize], true) }
    if !adopted { adopted = adopt_from_disk(a) }
    hidden_mask = sysettings.hidden()
    if hidden_mask != 0usize {
        say("shell hidden ")
        say_num(hidden_mask)
        say("\n")
    }
    // Live status, from the C111 status service: subscribe, post a notification, read the snapshot,
    // then stop the service (this shell is its only client).
    var snap: [5]usize = zero
    let subscribed = os.send(STATUS_REQ, OP_SUBSCRIBE, NO_SLOT)
    read_snapshot(&snap)
    let posted = os.send(STATUS_REQ, OP_POST, NO_SLOT)
    read_snapshot(&snap)
    // The settings server reads the status service for the apps (the battery), so with it running the service is
    // left running; the older boots stop it here as before.
    if !theme.valid(sysettings.word()) {
        let stopped = os.send(STATUS_REQ, OP_QUIT, NO_SLOT)
    }
    var seconds = 0usize
    var utc_seconds = 0usize
    var hour = 0usize
    var minute = 0usize
    // (C126) The Time zone setting, from the settings server (index 34).
    var (zone_step, zone_known) = sysettings.get(34usize)
    if !zone_known { zone_step = 0usize }
    if zone_step != 0usize {
        say("shell time zone ")
        say_num(zone_step)
        say("\n")
    }
    if snap[3usize] > 0usize {
        utc_seconds = snap[3usize] / 1000000000usize
        seconds = zone_seconds(utc_seconds, zone_step)
        let day = seconds % 86400usize
        hour = day / 3600usize
        minute = (day % 3600usize) / 60usize
    }
    var clock = clock_text(a, hour, minute)
    let scale = f32(os.SURFACE_W) / 412.0
    let logical_h = f32(os.SURFACE_H) / scale
    let ground = paint.Color { red: 0.09, green: 0.11, blue: 0.18, alpha: 1.0 }

    // Tell the compositor this app answers every routed event with a frame signal or a 0, so it can
    // take later frames after it starts routing input (value 2 on the frame endpoint).
    let announced = os.send(1usize, 2usize, NO_SLOT)

    // The lock screen, when there are fonts to draw it with.
    var locked = false
    // (C126) The Screen lock setting: None goes straight to the home screen.
    if theme.screen_lock() == 0usize { say("shell lock none\n") }
    if has_fonts && theme.screen_lock() != 0usize {
        let (builder_value, builder_error) = scene.builder(a, 4096usize)
        if builder_error != ok { ret builder_error }
        var builder = builder_value
        let save: scene.Command = .Save
        try scene.push(&builder, save)
        try scene.push(&builder, scene.Command { Transform: geometry.transform_scale(scale, scale) })
        if wallpapered { try wallpaper_layer(&builder, wall_texture, wall_w, wall_h, logical_h) } else { try fill(&builder, 0.0, 0.0, 412.0, logical_h, ground) }
        try draw_lock(a, &builder, faces, hour, minute, seconds)
        try dim_layer(&builder, logical_h)
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
    // (C126) Do Not Disturb: no notification count on the status bar or the lock screen.
    if theme.do_not_disturb() {
        snap[4usize] = 0usize
        say("shell dnd on\n")
    }

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
        try dim_layer(&builder, logical_h)
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
    // (D2240) Everything the home screen draws after this point is dropped each time an app returns.
    let home_mark = mem.mark(a)
    var pointer_x = 0usize
    var pointer_y = 0usize
    var launched_test = false
    var prompting = false
    // (C126) The Screen timeout setting, from the settings server (index 7), and the ticks since the last touch.
    var (timeout_step, timeout_known) = sysettings.get(7usize)
    if !timeout_known { timeout_step = 1usize }
    var idle_ticks = 0usize
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
            if tapped { idle_ticks = 0usize }
            if etype == 241usize && home_shown && theme.screen_lock() != 0usize {
                idle_ticks += 1usize
                if idle_ticks >= timeout_ticks(timeout_step) {
                    if show_lock(a, &renderer, &w, drawable, faces, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale, hour, minute, seconds) {
                        home_shown = false
                        framed = true
                        idle_ticks = 0usize
                        say("shell screen timeout\n")
                    }
                }
            }
            if tapped && !home_shown && !by_key && f32(pointer_x) * 412.0 / 32768.0 < 92.0 && f32(pointer_y) * logical_h / 32768.0 > 670.0 && f32(pointer_y) * logical_h / 32768.0 < 750.0 {
                // (C163) The torch's quick toggle on the lock screen: the settings server flips it and the lock
                // screen is drawn again; the screen stays locked.
                let (level, served) = sysettings.torch_toggle()
                if served {
                    lock_torch = level != 0usize
                    say("shell torch toggle ")
                    say_num(level)
                    say("\n")
                }
                if show_lock(a, &renderer, &w, drawable, faces, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale, hour, minute, seconds) { framed = true }
            } else if tapped && !home_shown && !by_key && f32(pointer_x) * 412.0 / 32768.0 > 320.0 && f32(pointer_y) * logical_h / 32768.0 > 670.0 && f32(pointer_y) * logical_h / 32768.0 < 750.0 && sensorclient.biometric() != sensorclient.BIOMETRIC_MATCH {
                // (C176) The fingerprint pad did not accept: off in Settings, or not the enrolled finger. It stays locked.
                say("shell fingerprint refused\n")
            } else if tapped && !home_shown {
                if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                home_shown = true
                framed = true
                say("shell unlocked\n")
                say("shell home presented\n")
            } else if tapped {
                var app = 99usize
                if prompting {
                    // The first-run prompt: Allow starts the app, anything else puts the home screen back.
                    let px = f32(pointer_x) * 412.0 / 32768.0
                    let py = f32(pointer_y) * logical_h / 32768.0
                    prompting = false
                    if px >= 56.0 && px < 184.0 && py >= 490.0 && py < 538.0 {
                        installed_allowed = true
                        app = 97usize
                        say("shell allowed ")
                        say(installed_name[0usize..installed_len])
                        say("\n")
                    } else {
                        if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                        framed = true
                        say("shell prompt cancelled\n")
                    }
                } else if by_key {
                    if !launched_test { app = 98usize }
                } else {
                    let position = icon_at(f32(pointer_x) * 412.0 / 32768.0, f32(pointer_y) * logical_h / 32768.0)
                    let icon = visible_icon(position)
                    if icon < icons.APP_COUNT {
                        say("shell tap ")
                        say(icons.app_label(icon))
                        say("\n")
                        app = icon
                    } else if installed_len > 0usize && position == visible_count() {
                        say("shell tap ")
                        say(installed_name[0usize..installed_len])
                        say("\n")
                        if installed_allowed {
                            app = 97usize
                        } else if show_prompt(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) {
                            prompting = true
                            framed = true
                            say("shell prompt ")
                            say(installed_name[0usize..installed_len])
                            say("\n")
                        }
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
                } else if app == 97usize {
                    // The installed app: started from its image in this process's memory (the kernel copies
                    // the pages), as a full-screen app with the capabilities every app has.
                    say("shell launching ")
                    say(installed_name[0usize..installed_len])
                    say("\n")
                    let install_word = (1usize << 63usize) | (installed_caps << 56usize) | (installed_pages << 40usize) | ((installed_va >> 12usize) << 8usize)
                    let child_installed = os.launch(install_word)
                    let code_installed = os.reap(child_installed)
                    say("shell app code ")
                    say_num(code_installed)
                    say("\n")
                    if has_last_scene {
                        let released_installed = scene.release_scene(&renderer, last_scene)
                        has_last_scene = false
                    }
                    mem.reset(a, home_mark)
                    if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                    framed = true
                    say("shell home\n")
                } else if app < icons.APP_COUNT {
                    let program = icons.program_of(app)
                    if program == 0usize {
                        say("shell no app yet\n")
                    } else {
                        say("shell launching ")
                        say(icons.app_label(app))
                        say("\n")
                        let child = os.launch(program + theme_word * 256usize)
                        // The app presents its own frames and answers the compositor; when it
                        // leaves it has told the compositor a frame will follow, which is Home.
                        let code_app = os.reap(child)
                        say("shell app code ")
                        say_num(code_app)
                        say("\n")
                        idle_ticks = 0usize
                        let (step_now, step_known) = sysettings.get(7usize)
                        if step_known { timeout_step = step_now }
                        let (zone_now, zone_ok) = sysettings.get(34usize)
                        if zone_ok && zone_now != zone_step && utc_seconds > 0usize {
                            zone_step = zone_now
                            seconds = zone_seconds(utc_seconds, zone_step)
                            let day_now = seconds % 86400usize
                            hour = day_now / 3600usize
                            minute = (day_now % 3600usize) / 60usize
                            clock = clock_text(a, hour, minute)
                            say("shell zone ")
                            say_num(hour)
                            say(":")
                            say_num(minute)
                            say("\n")
                        }
                        let hidden_now = sysettings.hidden()
                        if hidden_now != hidden_mask {
                            hidden_mask = hidden_now
                            say("shell hidden ")
                            say_num(hidden_mask)
                            say("\n")
                        }
                        let fresh = sysettings.word()
                        if theme.valid(fresh) && fresh != theme_word {
                            theme_word = fresh
                            theme.set(fresh)
                            say("shell theme ")
                            say_num(fresh)
                            say("\n")
                        }
                        if program == SETTINGS_PROGRAM && theme.valid(code_app) && code_app != theme_word {
                            theme_word = code_app
                            theme.set(theme_word)
                            say("shell theme ")
                            say_num(theme_word)
                            say("\n")
                        }
                        // (C125) Hand-over: an app that exits with 20000 + a program asks for that program next
                        // (Files, to open a file in the app for its type); the file's path is in /handover.
                        if code_app >= 20000usize && code_app < 20100usize {
                            say("shell handover ")
                            say_num(code_app - 20000usize)
                            say("\n")
                            let child_next = os.launch((code_app - 20000usize) + theme_word * 256usize)
                            let code_next = os.reap(child_next)
                            say("shell app code ")
                            say_num(code_next)
                            say("\n")
                        }
                        // The last scene is released first, so nothing refers to the memory that is given back.
                        if has_last_scene {
                            let released_scene = scene.release_scene(&renderer, last_scene)
                            has_last_scene = false
                        }
                        mem.reset(a, home_mark)
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
