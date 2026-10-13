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

// Text that lives in the arena, through a copy on the stack (os.write reads the stack).
fn say_arena(line: str) {
    var copy: [64]u8 = zero
    var n = 0usize
    while n < line.len && n < 64usize {
        copy[n] = line[n]
        n += 1usize
    }
    say(copy[0usize..n])
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
// (C168) The status bar's time text kept in a buffer of its own: a string allocated after the home mark is given back by
// the reset every return to Home makes, so a clock rebuilt in the loop (the time zone changed) lives here instead.
var clock_store: [12]u8 = zero

fn keep_clock(a: *mem.Arena, hour: usize, minute: usize) -> str {
    let shown = clock_text(a, hour, minute)
    var n = 0usize
    while n < shown.len && n < 12usize {
        clock_store[n] = shown[n]
        n += 1usize
    }
    ret clock_store[0usize..n]
}

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
    // (C163) The torch's quick toggle: a pill between the time and the glyphs, amber while the torch is on.
    if has_fonts {
        var pill = paint.Color { red: 0.25, green: 0.27, blue: 0.31, alpha: 1.0 }
        if lock_torch { pill = paint.Color { red: 0.99, green: 0.78, blue: 0.30, alpha: 1.0 } }
        try card(a, builder, 256.0, 5.0, 48.0, 20.0, 10.0, pill)
        let (label_box, label_error) = text.draw(a, builder, faces.jost, 12.0, "Torch", 262.0, 8.0, 0.0, 0u32, layout.Align.Start, bright)
        if label_error != ok { ret label_error }
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

// (C124) The installed apps: signed packages, one the kernel handed the shell (its last archive entry) and the ones kept
// in /apps, each verified against the server's key. (C173, C151) Up to three: the grid has room for three icons after
// the 29 of the system (a fourth would sit under the home bar). Each one's name (24 bytes a slot), and its image in a
// page-aligned buffer, until it is launched from memory.
const MAX_INSTALLED: usize = 3usize
var installed_name: [72]u8 = zero
var installed_len: [3]usize = zero
var installed_va: [3]usize = zero
var installed_pages: [3]usize = zero
// The capabilities the manifest declared: bit 0 network, bit 1 storage.
var installed_caps: [3]usize = zero
// Whether the user allowed the installed app's capabilities this boot (the first run asks); 1 when allowed.
var installed_allowed: [3]usize = zero
// The manifest's version of each, and whether the version it replaced is kept in /apps (for a roll back).
var installed_version: [3]usize = zero
var installed_prev: [3]usize = zero
var installed_total: usize = 0usize
// The one a tap, a prompt or a launch is about.
var installed_pick: usize = 0usize
// (C173) What the home screen's arena is reset to after an app: the mark taken at start, moved up by a roll back (its
// image is allocated after the mark and has to outlive it).
var home_floor: usize = 0usize

// The name of installed app `k`.
fn installed_label(k: usize) -> str {
    ret installed_name[k * 24usize..k * 24usize + installed_len[k]]
}

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

// (C168) The home screen's step widget: today's count and the goal, read from /steps (what the Steps app kept) plus
// what the hub counted since, the shell being one of the hub's step-counter readers. `widget_known` is false until a
// reading arrives (no disk and no hub: no widget). The card sits under the icon grid; a tap on it opens Steps.
var widget_count: usize = 0usize
var widget_goal: usize = 8000usize
var widget_known: bool = false
// (The card is 84 dp high from y = 700; icon_at's neighbour in the tap handler tests the same band.)
const STEPS_PROGRAM: usize = 36usize

fn word_at(buf: []const u8, at: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < 4usize {
        v = v | (usize(buf[at + i]) << (8usize * i))
        i += 1usize
    }
    ret v
}

// Read the widget's numbers; `day` is the wall clock's day (0 with no clock). True when they changed.
fn read_widget(day: usize) -> bool {
    var buf: [136]u8 = zero
    var today = 0usize
    var goal = 8000usize
    var base = 0usize
    let (got, found) = fsproto.read_big(FS_REQ, FS_REP, "/steps", mem.address_of(&buf[0usize]), 136usize)
    var known = false
    if found && got >= 8usize {
        known = true
        today = word_at(buf[0usize..136usize], 0usize)
        let kept_goal = word_at(buf[0usize..136usize], 4usize)
        if kept_goal >= 1000usize && kept_goal <= 100000usize { goal = kept_goal }
        // A count kept on an earlier day is yesterday's; the Steps app rolls the week when it opens.
        if got >= 36usize {
            let kept_day = word_at(buf[0usize..136usize], 8usize)
            if day > 0usize && kept_day > 0usize && day > kept_day { today = 0usize }
        }
        if got >= 136usize { base = word_at(buf[0usize..136usize], 36usize) }
    }
    let (count, cadence, status) = sensorclient.steps()
    if status == sensorclient.STATUS_OK {
        known = true
        if count >= base { today += count - base } else { today += count }
    }
    var changed = false
    if known != widget_known || today != widget_count || goal != widget_goal { changed = true }
    widget_known = known
    widget_count = today
    widget_goal = goal
    ret changed
}

// The Steps icon's index, or 99 when Settings uninstalled it (then the widget is not drawn).
fn steps_icon() -> usize {
    var i = 0usize
    while i < icons.APP_COUNT {
        if icons.program_of(i) == STEPS_PROGRAM && ((hidden_mask >> i) & 1usize) == 0usize { ret i }
        i += 1usize
    }
    ret 99usize
}

// 8,412 with its thousands comma (a count under a million).
fn with_commas(a: *mem.Arena, value: usize) -> str {
    if value < 1000usize { ret number_text(a, value) }
    let low = value % 1000usize
    var low_text = number_text(a, low)
    if low < 10usize { low_text = join3(a, "00", low_text, "") } else if low < 100usize { low_text = join3(a, "0", low_text, "") }
    ret join3(a, number_text(a, (value / 1000usize) % 1000usize), ",", low_text)
}

// The widget takes the free slots at the end of the icon grid (the rest of the last row, or a row of its own): its
// left edge in dp, its top and its width.
fn widget_slot() -> (f32, f32, f32) {
    var count = visible_count()
    if installed_len > 0usize { count += 1usize }
    let col = count % 4usize
    let row = count / 4usize
    ret (f32(col) * 103.0 + 5.0, 70.0 + f32(row) * 104.0, f32(4usize - col) * 103.0 - 10.0)
}

// The card is 84 dp high.
fn draw_widget(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces) -> err {
    let white = paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
    let soft = paint.Color { red: 0.86, green: 0.87, blue: 0.9, alpha: 1.0 }
    let amber = paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
    let (left, top, wide) = widget_slot()
    try card(a, builder, left, top, wide, 84.0, 18.0, paint.Color { red: 0.1, green: 0.1, blue: 0.11, alpha: 0.7 })
    let (t1, e1) = text.draw(a, builder, faces.grotesk, 13.0, "Steps today", left + 14.0, top + 8.0, 0.0, 0u32, layout.Align.Start, soft)
    if e1 != ok { ret e1 }
    let (t2, e2) = text.draw(a, builder, faces.jost_bold, 28.0, with_commas(a, widget_count), left + 14.0, top + 26.0, 0.0, 0u32, layout.Align.Start, white)
    if e2 != ok { ret e2 }
    let goal_line = join3(a, "of ", with_commas(a, widget_goal), "")
    let goal_width = text.measure(a, faces.jost, 14.0, goal_line)
    let (t3, e3) = text.draw(a, builder, faces.jost, 14.0, goal_line, left + wide - 14.0 - goal_width, top + 36.0, 0.0, 0u32, layout.Align.Start, soft)
    if e3 != ok { ret e3 }
    // The bar: the track, and the fill to the share of the goal (at most all of it).
    let track = wide - 28.0
    try card(a, builder, left + 14.0, top + 66.0, track, 8.0, 4.0, paint.Color { red: 0.3, green: 0.3, blue: 0.33, alpha: 1.0 })
    var share: f32 = 1.0
    if widget_count < widget_goal { share = f32(widget_count) / f32(widget_goal) }
    if share > 0.0 {
        var filled = track * share
        if filled < 8.0 { filled = 8.0 }
        try card(a, builder, left + 14.0, top + 66.0, filled, 8.0, 4.0, amber)
    }
    ret ok
}

fn draw_home(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, has_fonts: bool, clock: str, snap: [5]usize) -> err {
    try status_bar(a, builder, faces, has_fonts, clock, snap)
    let white = paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
    if has_fonts && widget_known && steps_icon() != 99usize { try draw_widget(a, builder, faces) }
    var idx = 0usize
    let extra = installed_total
    while idx < visible_count() + extra {
        let icon = visible_icon(idx)
        var glyph = icons.app(icon)
        var caption = icons.app_label(icon)
        if icon == 99usize {
            glyph = icons.app(26usize)
            caption = installed_label(idx - visible_count())
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

// (C168, D5000) Give every scene slot of the renderer its storage now: a slot takes it from the arena at its first
// compile, so a first compile after the arena's reset mark would leave it pointing at memory the reset gave back.
fn prime_scenes(a: *mem.Arena, renderer: *scene.Renderer) {
    var held: [2]scene.SceneId = zero
    var made = 0usize
    var tries = 0usize
    while tries < 2usize {
        let (builder_value, builder_error) = scene.builder(a, 16usize)
        if builder_error == ok {
            var builder = builder_value
            let save: scene.Command = .Save
            let restore: scene.Command = .Restore
            if scene.push(&builder, save) == ok && scene.push(&builder, restore) == ok {
                let (id, compile_error) = scene.compile(renderer, scene.finish(&builder))
                if compile_error == ok {
                    held[made] = id
                    made += 1usize
                }
            }
        }
        tries += 1usize
    }
    var i = 0usize
    while i < made {
        let released = scene.release_scene(renderer, held[i])
        i += 1usize
    }
}

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
    let pick = installed_pick
    if card(a, &builder, 36.0, 270.0, 340.0, 360.0, 24.0, cream) != ok { ret false }
    if centred(a, &builder, faces.jost_bold, 22.0, installed_label(pick), 206.0, 292.0, ink) != ok { ret false }
    if centred(a, &builder, faces.grotesk, 13.0, join3(a, "A generated app, version ", number_text(a, installed_version[pick]), ". It asks for:"), 206.0, 328.0, muted) != ok { ret false }
    var line: f32 = 364.0
    if (installed_caps[pick] & 1usize) != 0usize {
        if centred(a, &builder, faces.jost, 18.0, "The network", 206.0, line, ink) != ok { ret false }
        line += 30.0
    }
    if (installed_caps[pick] & 2usize) != 0usize {
        if centred(a, &builder, faces.jost, 18.0, "Storage", 206.0, line, ink) != ok { ret false }
        line += 30.0
    }
    if installed_caps[pick] == 0usize {
        if centred(a, &builder, faces.jost, 18.0, "Nothing beyond its own screen", 206.0, line, ink) != ok { ret false }
    }
    // (C173) Allow (Open once it was allowed this boot) and Cancel; Remove deletes the package and the icon, Roll
    // back puts the version this one replaced back.
    var open_label = "Allow"
    if installed_allowed[pick] != 0usize { open_label = "Open" }
    if card(a, &builder, 56.0, 490.0, 128.0, 48.0, 24.0, paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }) != ok { ret false }
    if centred(a, &builder, faces.jost, 18.0, open_label, 120.0, 503.0, ink) != ok { ret false }
    if card(a, &builder, 228.0, 490.0, 128.0, 48.0, 24.0, paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }) != ok { ret false }
    if centred(a, &builder, faces.jost, 18.0, "Cancel", 292.0, 503.0, ink) != ok { ret false }
    if card(a, &builder, 56.0, 558.0, 128.0, 48.0, 24.0, paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }) != ok { ret false }
    if centred(a, &builder, faces.jost, 18.0, "Remove", 120.0, 571.0, ink) != ok { ret false }
    if installed_prev[pick] != 0usize {
        if card(a, &builder, 228.0, 558.0, 128.0, 48.0, 24.0, paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }) != ok { ret false }
        if centred(a, &builder, faces.jost, 18.0, "Roll back", 292.0, 571.0, ink) != ok { ret false }
    }
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


// The file name of an app: its name's letters and digits, lower case, up to 14 of them, and ".npkg".
fn package_file(a: *mem.Arena, name: str) -> str {
    var file: [24]u8 = zero
    var f = 0usize
    var k = 0usize
    while k < name.len && f < 14usize {
        var c = name[k]
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
    ret join3(a, "/apps/", file[0usize..f + suffix.len], "")
}

// The number in the manifest's `version=` line (0 when there is none).
fn manifest_version(pkg: package.Package) -> usize {
    let (text_version, has_version) = package.value(pkg, "version")
    var version = 0usize
    var k = 0usize
    while has_version && k < text_version.len && text_version[k] >= 48u8 && text_version[k] <= 57u8 {
        version = version * 10usize + usize(text_version[k] - 48u8)
        k += 1usize
    }
    ret version
}

// (C124) Take a signed package: check it against the server's key, keep the manifest's name and capabilities and the
// image in a page-aligned buffer, and (when `persist`) write the package to /apps so the next boot has it. True when it
// was adopted. (C173, C151) A package of a name already installed is an update when its version is higher (the old
// file is kept beside it as `.prev`, for a roll back), and nothing to do when it is the same; `downgrade` accepts a
// lower one (the roll back). There is room for MAX_INSTALLED apps.
fn adopt(a: *mem.Arena, data: str, persist: bool, downgrade: bool) -> bool {
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
    // (C173) The app kit's level (`api`) is versioned: a package written for a newer kit than this device's is refused
    // for that reason, not as a bad signature.
    if pkg_error == package.TooNew {
        say("shell package needs a newer app kit\n")
        ret false
    }
    if pkg_error != ok {
        say("shell package refused\n")
        ret false
    }
    let (pkg_name, has_pkg_name) = package.value(pkg, "name")
    let version = manifest_version(pkg)
    // The slot of the same name, if there is one.
    var slot = 99usize
    var k = 0usize
    while k < installed_total {
        let held = installed_label(k)
        var same = held.len == pkg_name.len
        var c = 0usize
        while same && c < held.len {
            if held[c] != pkg_name[c] { same = false }
            c += 1usize
        }
        if same { slot = k }
        k += 1usize
    }
    let path = package_file(a, pkg_name)
    var updating = false
    if slot != 99usize {
        if version == installed_version[slot] && !downgrade {
            // Already here. The archive's own copy still goes to the disk when the disk has none.
            if persist {
                let (have_size, have_kind, have_day, have_file) = fsproto.stat(FS_REQ, FS_REP, path)
                if !have_file {
                    let made_dir = fsproto.mkdir(FS_REQ, FS_REP, "/apps")
                    if fsproto.write_big(FS_REQ, FS_REP, path, mem.address_of(&data[0usize]), data.len) {
                        say("shell package kept ")
                        say_arena(path)
                        say("\n")
                    }
                }
            }
            ret true
        }
        if version < installed_version[slot] && !downgrade {
            say("shell package older ")
            say_arena(pkg_name)
            say("\n")
            ret false
        }
        updating = true
    } else {
        if installed_total >= MAX_INSTALLED {
            say("shell package no room ")
            say_arena(pkg_name)
            say("\n")
            ret false
        }
        slot = installed_total
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
    var n = 0usize
    while n < pkg_name.len && n < 24usize {
        installed_name[slot * 24usize + n] = pkg_name[n]
        n += 1usize
    }
    installed_len[slot] = n
    installed_va[slot] = base
    installed_pages[slot] = pages
    installed_caps[slot] = 0usize
    if package.declares(pkg, "network") { installed_caps[slot] = installed_caps[slot] | 1usize }
    if package.declares(pkg, "storage") { installed_caps[slot] = installed_caps[slot] | 2usize }
    installed_version[slot] = version
    if !updating {
        installed_allowed[slot] = 0usize
        installed_prev[slot] = 0usize
        installed_total += 1usize
    }
    say("shell installed ")
    say(installed_label(slot))
    say("\n")
    if updating {
        say("shell updated ")
        say(installed_label(slot))
        say(" to ")
        say_num(version)
        say("\n")
    }
    if persist {
        let made_dir = fsproto.mkdir(FS_REQ, FS_REP, "/apps")
        let kept_path = package_file(a, installed_label(slot))
        // The file about to be replaced becomes the .prev a roll back reads.
        if updating {
            let (old_size, old_kind, old_day, old_found) = fsproto.stat(FS_REQ, FS_REP, kept_path)
            if old_found && old_size > 0usize && old_size <= 4194304usize {
                let (old_buf, old_alloc) = mem.alloc[u8](a, old_size)
                if old_alloc == ok {
                    let (old_got, old_ok) = fsproto.read_big(FS_REQ, FS_REP, kept_path, mem.address_of(&old_buf[0usize]), old_size)
                    if old_ok && old_got == old_size {
                        if fsproto.write_big(FS_REQ, FS_REP, join3(a, kept_path, ".prev", ""), mem.address_of(&old_buf[0usize]), old_got) {
                            installed_prev[slot] = 1usize
                            say("shell previous version kept\n")
                        }
                    }
                }
            }
        }
        if fsproto.write_big(FS_REQ, FS_REP, kept_path, mem.address_of(&data[0usize]), data.len) {
            say("shell package kept ")
            say_arena(kept_path)
            say("\n")
        }
    }
    ret true
}

// (C173) A kept `.prev` beside the app's package, noted for the slot (the disk was read, not written, at start).
fn note_previous(a: *mem.Arena, slot: usize) {
    let path = join3(a, package_file(a, installed_label(slot)), ".prev", "")
    let (size, kind, day, found) = fsproto.stat(FS_REQ, FS_REP, path)
    if found && size > 0usize { installed_prev[slot] = 1usize }
}

// (C124, C173) Every package kept in /apps (names ending .npkg), up to the room there is.
fn adopt_from_disk(a: *mem.Arena) -> bool {
    var names: [512]u8 = zero
    let (count, listed) = fsproto.list(FS_REQ, FS_REP, "/apps", mem.address_of(&names[0usize]), 512usize)
    if !listed || count == 0usize { ret false }
    var any = false
    var start = 0usize
    var at = 0usize
    while at < count {
        if names[at] == 10u8 {
            let leaf = names[start..at]
            if leaf.len > 5usize && leaf[leaf.len - 5usize] == 46u8 && leaf[leaf.len - 4usize] == 110u8 && leaf[leaf.len - 3usize] == 112u8 && leaf[leaf.len - 2usize] == 107u8 && leaf[leaf.len - 1usize] == 103u8 {
                let path = join3(a, "/apps/", leaf, "")
                let (size, kind, day, found) = fsproto.stat(FS_REQ, FS_REP, path)
                if found && size > 0usize && size <= 4194304usize {
                    let (buffer, buffer_error) = mem.alloc[u8](a, size)
                    if buffer_error == ok {
                        let (got, read_ok) = fsproto.read_big(FS_REQ, FS_REP, path, mem.address_of(&buffer[0usize]), size)
                        if read_ok && got == size {
                            let before = installed_total
                            if adopt(a, buffer[0usize..got], false, false) {
                                any = true
                                // The slot this file belongs to (a new one, or the one it matched).
                                var s = 0usize
                                while s < installed_total {
                                    note_previous(a, s)
                                    s += 1usize
                                }
                            }
                        }
                    }
                }
            }
            start = at + 1usize
        }
        at += 1usize
    }
    ret any
}

// (C173) Remove installed app `k`: its package (and the kept previous one) leave /apps and its icon leaves the grid.
fn remove_installed(a: *mem.Arena, k: usize) {
    let path = package_file(a, installed_label(k))
    let gone = fsproto.remove(FS_REQ, FS_REP, path)
    let gone_prev = fsproto.remove(FS_REQ, FS_REP, join3(a, path, ".prev", ""))
    say("shell removed ")
    say(installed_label(k))
    say("\n")
    var i = k
    while i + 1usize < installed_total {
        var c = 0usize
        while c < 24usize {
            installed_name[i * 24usize + c] = installed_name[(i + 1usize) * 24usize + c]
            c += 1usize
        }
        installed_len[i] = installed_len[i + 1usize]
        installed_va[i] = installed_va[i + 1usize]
        installed_pages[i] = installed_pages[i + 1usize]
        installed_caps[i] = installed_caps[i + 1usize]
        installed_allowed[i] = installed_allowed[i + 1usize]
        installed_version[i] = installed_version[i + 1usize]
        installed_prev[i] = installed_prev[i + 1usize]
        i += 1usize
    }
    if installed_total > 0usize { installed_total -= 1usize }
}

// (C173) Roll app `k` back to the version kept beside it: the .prev file is read and adopted over the newer one, then
// becomes the package file (the newer one is dropped).
fn roll_back(a: *mem.Arena, k: usize) -> bool {
    let path = package_file(a, installed_label(k))
    let prev_path = join3(a, path, ".prev", "")
    let (size, kind, day, found) = fsproto.stat(FS_REQ, FS_REP, prev_path)
    if !found || size == 0usize || size > 4194304usize { ret false }
    let (buffer, buffer_error) = mem.alloc[u8](a, size)
    if buffer_error != ok { ret false }
    let (got, read_ok) = fsproto.read_big(FS_REQ, FS_REP, prev_path, mem.address_of(&buffer[0usize]), size)
    if !read_ok || got != size { ret false }
    if !adopt(a, buffer[0usize..got], false, true) { ret false }
    if fsproto.write_big(FS_REQ, FS_REP, path, mem.address_of(&buffer[0usize]), got) {
        let removed_prev = fsproto.remove(FS_REQ, FS_REP, prev_path)
    }
    installed_prev[k] = 0usize
    say("shell rolled back ")
    say(installed_label(k))
    say(" to ")
    say_num(installed_version[k])
    say("\n")
    ret true
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
    // (C173) The packages kept in /apps first, then the archive's: a newer version in the archive is an update of the
    // one on the disk (which is kept as the previous one), the same version is already installed.
    var adopted = adopt_from_disk(a)
    if args.len >= 8usize {
        if adopt(a, args[7usize], true, false) { adopted = true }
    }
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
    // (C168) The step widget is first read on a tick of the home screen, not here: the settings server and the
    // sensor server read their files over the same filesystem endpoints in these first moments, and two
    // processes' multi-word requests must not interleave on them.

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
    // (C168, D5000) The renderer takes each scene slot's storage from this arena the first time the slot compiles.
    // A slot first used after the mark below had its storage given back by the next reset and was then reused
    // (the home screen redrawn from the tick, as the step widget does, trapped at 0x24 inside scene.compile).
    // Both slots are compiled once here, before the mark, so their storage lies below it.
    prime_scenes(a, &renderer)
    // (D2240) Everything the home screen draws after this point is dropped each time an app returns.
    let home_mark = mem.mark(a)
    home_floor = home_mark
    var pointer_x = 0usize
    var pointer_y = 0usize
    var launched_test = false
    var prompting = false
    // (C126) The Screen timeout setting, from the settings server (index 7), and the ticks since the last touch.
    var (timeout_step, timeout_known) = sysettings.get(7usize)
    if !timeout_known { timeout_step = 1usize }
    // The ticks since the last touch count the Screen timeout (as they always did: a slow frame drops ticks, so it is
    // a timeout of delivered ticks). The widget's refresh is measured on the tick's own value, the input server's
    // monotonic milliseconds; `widget_fresh` says its base is taken from the next tick.
    var idle_ticks = 0usize
    var widget_base = 0usize
    var widget_fresh = true
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
                    // Everything the home screen drew since the last reset goes first, as when an app returns.
                    if has_last_scene {
                        let released_home = scene.release_scene(&renderer, last_scene)
                        has_last_scene = false
                    }
                    mem.reset(a, home_floor)
                    if show_lock(a, &renderer, &w, drawable, faces, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale, hour, minute, seconds) {
                        home_shown = false
                        framed = true
                        idle_ticks = 0usize
                        say("shell screen timeout\n")
                    }
                }
            }
            // (C168) The step widget follows the count: read every thirty seconds and redrawn, from a
            // cleared arena like every return to Home, only when the number moved.
            if etype == 241usize && home_shown && !prompting && !framed {
                if widget_fresh {
                    // The first tick on the home screen reads at once; then every half minute.
                    widget_base = (value + 4294967296usize - 30000usize) & LOW32
                    widget_fresh = false
                }
                if ((value + 4294967296usize - widget_base) & LOW32) >= 30000usize {
                    widget_base = value
                    if read_widget(utc_seconds / 86400usize) && widget_known && steps_icon() != 99usize {
                        if has_last_scene {
                            let released_widget = scene.release_scene(&renderer, last_scene)
                            has_last_scene = false
                        }
                        mem.reset(a, home_floor)
                        if show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) {
                            framed = true
                            say("shell widget steps ")
                            say_num(widget_count)
                            say("\n")
                        }
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
            } else if tapped && home_shown && !prompting && !by_key && f32(pointer_x) * 412.0 / 32768.0 >= 250.0 && f32(pointer_x) * 412.0 / 32768.0 < 310.0 && f32(pointer_y) * logical_h / 32768.0 < 30.0 {
                // (C163) The torch's quick toggle on the status bar: the same switch as the lock screen's, the home
                // screen drawn again with the pill's colour.
                let (level, served) = sysettings.torch_toggle()
                if served {
                    lock_torch = level != 0usize
                    say("shell status torch toggle ")
                    say_num(level)
                    say("\n")
                }
                if show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { framed = true }
            } else if tapped && !home_shown && !by_key && f32(pointer_x) * 412.0 / 32768.0 > 320.0 &&f32(pointer_y) * logical_h / 32768.0 > 670.0 && f32(pointer_y) * logical_h / 32768.0 < 750.0 && sensorclient.biometric() != sensorclient.BIOMETRIC_MATCH {
                // (C176) The fingerprint pad did not accept: off in Settings, or not the enrolled finger. It stays locked.
                say("shell fingerprint refused\n")
            } else if tapped && !home_shown {
                // (C168) The step widget's reading goes into the first frame of the home screen.
                let widget_unlock = read_widget(utc_seconds / 86400usize)
                widget_fresh = true
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
                        if installed_allowed[installed_pick] == 0usize {
                            say("shell allowed ")
                        } else {
                            say("shell open ")
                        }
                        installed_allowed[installed_pick] = 1usize
                        app = 97usize
                        say(installed_label(installed_pick))
                        say("\n")
                    } else if px >= 56.0 && px < 184.0 && py >= 558.0 && py < 606.0 {
                        // (C173) Remove: the package and the icon go.
                        remove_installed(a, installed_pick)
                        if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                        framed = true
                    } else if px >= 228.0 && px < 356.0 && py >= 558.0 && py < 606.0 && installed_prev[installed_pick] != 0usize {
                        // (C173) Roll back to the version this one replaced; the image it brings is kept past the next
                        // return to the home screen.
                        if roll_back(a, installed_pick) { home_floor = mem.mark(a) }
                        if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                        framed = true
                    } else {
                        if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                        framed = true
                        say("shell prompt cancelled\n")
                    }
                } else if by_key {
                    if !launched_test { app = 98usize }
                } else {
                    let tap_x = f32(pointer_x) * 412.0 / 32768.0
                    let tap_y = f32(pointer_y) * logical_h / 32768.0
                    let widget_icon = steps_icon()
                    let (slot_left, slot_top, slot_wide) = widget_slot()
                    if widget_known && widget_icon != 99usize && tap_y >= slot_top && tap_y < slot_top + 84.0 && tap_x >= slot_left && tap_x < slot_left + slot_wide {
                        say("shell tap widget steps\n")
                        app = widget_icon
                    }
                    let position = icon_at(tap_x, tap_y)
                    var icon = visible_icon(position)
                    if app != 99usize { icon = app }
                    if icon < icons.APP_COUNT {
                        say("shell tap ")
                        say(icons.app_label(icon))
                        say("\n")
                        app = icon
                    } else if position >= visible_count() && position < visible_count() + installed_total {
                        // (C173) An installed app: its prompt (Allow the first time, Open after; Remove, Roll back).
                        installed_pick = position - visible_count()
                        say("shell tap ")
                        say(installed_label(installed_pick))
                        say("\n")
                        if show_prompt(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) {
                            prompting = true
                            framed = true
                            say("shell prompt ")
                            say(installed_label(installed_pick))
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
                    say(installed_label(installed_pick))
                    say("\n")
                    let install_word = (1usize << 63usize) | (installed_caps[installed_pick] << 56usize) | (installed_pages[installed_pick] << 40usize) | ((installed_va[installed_pick] >> 12usize) << 8usize)
                    let child_installed = os.launch(install_word)
                    let code_installed = os.reap(child_installed)
                    say("shell app code ")
                    say_num(code_installed)
                    say("\n")
                    if has_last_scene {
                        let released_installed = scene.release_scene(&renderer, last_scene)
                        has_last_scene = false
                    }
                    mem.reset(a, home_floor)
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
                        widget_fresh = true
                        let (step_now, step_known) = sysettings.get(7usize)
                        if step_known { timeout_step = step_now }
                        let (zone_now, zone_ok) = sysettings.get(34usize)
                        if zone_ok && zone_now != zone_step && utc_seconds > 0usize {
                            zone_step = zone_now
                            seconds = zone_seconds(utc_seconds, zone_step)
                            let day_now = seconds % 86400usize
                            hour = day_now / 3600usize
                            minute = (day_now % 3600usize) / 60usize
                            clock = keep_clock(a, hour, minute)
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
                        mem.reset(a, home_floor)
                        // (C168) What the Steps app kept (and the hub counted) while it was in front.
                        let widget_back = read_widget(utc_seconds / 86400usize)
                        if !show_home(a, &renderer, &w, drawable, faces, has_fonts, clock, snap, wallpapered, wall_texture, wall_w, wall_h, logical_h, scale) { ret ok }
                        framed = true
                        say("shell home\n")
                        if widget_known {
                            say("shell widget back ")
                            say_num(widget_count)
                            say("\n")
                        }
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
