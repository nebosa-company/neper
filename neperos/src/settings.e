// Settings (D2220): the app behind the Settings icon, after the Pixel's -- eleven categories as rows (a
// coloured disc with the initial, the name, a summary of its state), and a page for each with the
// controls that category has: switches (Wi-Fi, Bluetooth, Airplane mode, Dark theme, Battery saver, Do
// Not Disturb, Location, ...), sliders (brightness, three volumes), choices (screen timeout, font size,
// screen lock), a list of networks, battery use, storage, the apps, and the facts of the phone. The Dark
// theme switch really changes this app's own look. Dark ground, cream rows and amber, like the other apps
// (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom
// leaves the app; the list of apps scrolls with two arrow buttons.
// ponytail: every value is SAMPLE state in this process -- nothing here reaches the system (the screen
// keeps its brightness, the speaker its volume, the radio its state) and it starts from the same values
// each time. Settings that act on the system, kept across restarts, and the search are queued as C126.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use icons

const NONE: usize = 99usize
const MAX_HITS: usize = 96usize
const PAGES: usize = 11usize
const MAIN: usize = 99usize
// The settings, by number.
const WIFI: usize = 0usize
const MOBILE: usize = 1usize
const AIRPLANE: usize = 2usize
const HOTSPOT: usize = 3usize
const BRIGHTNESS: usize = 4usize
const DARK: usize = 5usize
const ADAPTIVE: usize = 6usize
const TIMEOUT: usize = 7usize
const FONT: usize = 8usize
const MEDIA: usize = 9usize
const RING: usize = 10usize
const ALARM: usize = 11usize
const DND: usize = 12usize
const VIBRATE: usize = 13usize
const SAVER: usize = 14usize
const LOCATION: usize = 15usize
const CAMERA_ACCESS: usize = 16usize
const MIC_ACCESS: usize = 17usize
const FINGERPRINT: usize = 18usize
const LOCK: usize = 19usize
const HOUR24: usize = 20usize
const CONTRAST: usize = 21usize
const MAGNIFY: usize = 22usize
const NETWORK: usize = 23usize
const BLUETOOTH: usize = 24usize
const ROTATE: usize = 25usize
const NOTIFY: usize = 26usize
const SETTINGS: usize = 40usize

// The light or dark look of the app itself: one switch, three colours.
var dark_theme: bool = true

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

// ----------------------------------------------------------------------------------------------
// Text helpers.

fn number(a: *mem.Arena, value: usize) -> str {
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

fn join(a: *mem.Arena, first: str, second: str, third: str) -> str {
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

fn on_off(on: bool) -> str {
    if on { ret "on" }
    ret "off"
}

// ----------------------------------------------------------------------------------------------
// The categories and the settings.

fn page_name(page: usize) -> str {
    if page == 0usize { ret "Network & internet" }
    if page == 1usize { ret "Display" }
    if page == 2usize { ret "Sound & vibration" }
    if page == 3usize { ret "Battery" }
    if page == 4usize { ret "Storage" }
    if page == 5usize { ret "Notifications" }
    if page == 6usize { ret "Apps" }
    if page == 7usize { ret "Security & privacy" }
    if page == 8usize { ret "Accessibility" }
    if page == 9usize { ret "System" }
    ret "About phone"
}

fn page_tag(page: usize) -> str {
    if page == 0usize { ret "N" }
    if page == 1usize { ret "D" }
    if page == 2usize { ret "S" }
    if page == 3usize { ret "B" }
    if page == 4usize { ret "St" }
    if page == 5usize { ret "No" }
    if page == 6usize { ret "A" }
    if page == 7usize { ret "Se" }
    if page == 8usize { ret "Ac" }
    if page == 9usize { ret "Sy" }
    ret "i"
}

fn page_color(page: usize) -> paint.Color {
    let n = page % 6usize
    if n == 0usize { ret paint.Color { red: 0.55, green: 0.72, blue: 0.62, alpha: 1.0 } }
    if n == 1usize { ret paint.Color { red: 0.85, green: 0.60, blue: 0.45, alpha: 1.0 } }
    if n == 2usize { ret paint.Color { red: 0.60, green: 0.66, blue: 0.85, alpha: 1.0 } }
    if n == 3usize { ret paint.Color { red: 0.82, green: 0.62, blue: 0.75, alpha: 1.0 } }
    if n == 4usize { ret paint.Color { red: 0.88, green: 0.76, blue: 0.45, alpha: 1.0 } }
    ret paint.Color { red: 0.62, green: 0.78, blue: 0.80, alpha: 1.0 }
}

fn setting_name(setting: usize) -> str {
    if setting == WIFI { ret "Wi-Fi" }
    if setting == MOBILE { ret "Mobile network" }
    if setting == AIRPLANE { ret "Airplane mode" }
    if setting == HOTSPOT { ret "Hotspot" }
    if setting == BRIGHTNESS { ret "Brightness" }
    if setting == DARK { ret "Dark theme" }
    if setting == ADAPTIVE { ret "Adaptive brightness" }
    if setting == TIMEOUT { ret "Screen timeout" }
    if setting == FONT { ret "Font size" }
    if setting == MEDIA { ret "Media volume" }
    if setting == RING { ret "Ring volume" }
    if setting == ALARM { ret "Alarm volume" }
    if setting == DND { ret "Do Not Disturb" }
    if setting == VIBRATE { ret "Vibrate for calls" }
    if setting == SAVER { ret "Battery saver" }
    if setting == LOCATION { ret "Location" }
    if setting == CAMERA_ACCESS { ret "Camera access" }
    if setting == MIC_ACCESS { ret "Microphone access" }
    if setting == FINGERPRINT { ret "Fingerprint unlock" }
    if setting == LOCK { ret "Screen lock" }
    if setting == HOUR24 { ret "24-hour format" }
    if setting == CONTRAST { ret "High contrast text" }
    if setting == MAGNIFY { ret "Magnification" }
    if setting == NETWORK { ret "Network" }
    if setting == BLUETOOTH { ret "Bluetooth" }
    if setting == ROTATE { ret "Auto-rotate" }
    ret "Notifications"
}

fn network_name(index: usize) -> str {
    if index == 0usize { ret "Home-5G" }
    if index == 1usize { ret "CafeGuest" }
    if index == 2usize { ret "Neighbour-2G" }
    ret "Office"
}

fn notify_app(index: usize) -> str {
    if index == 0usize { ret "Messages" }
    if index == 1usize { ret "Mail" }
    if index == 2usize { ret "Clock" }
    if index == 3usize { ret "Tasks" }
    if index == 4usize { ret "Weather" }
    if index == 5usize { ret "Stocks" }
    if index == 6usize { ret "Wallet" }
    ret "Chat"
}

// ----------------------------------------------------------------------------------------------
// State.

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    values: [48]usize,
    page: usize,
    scroll: f32,
    hits: [96]Hit,
    hit_total: usize,
}

fn defaults(s: *State) {
    var i = 0usize
    while i < SETTINGS {
        s.values[i] = 0usize
        i += 1usize
    }
    s.values[WIFI] = 1usize
    s.values[MOBILE] = 1usize
    s.values[BRIGHTNESS] = 7usize
    s.values[DARK] = 1usize
    s.values[ADAPTIVE] = 1usize
    s.values[TIMEOUT] = 1usize
    s.values[FONT] = 1usize
    s.values[MEDIA] = 6usize
    s.values[RING] = 8usize
    s.values[ALARM] = 7usize
    s.values[VIBRATE] = 1usize
    s.values[LOCATION] = 1usize
    s.values[CAMERA_ACCESS] = 1usize
    s.values[MIC_ACCESS] = 1usize
    s.values[FINGERPRINT] = 1usize
    s.values[LOCK] = 2usize
    s.values[HOUR24] = 0usize
    s.values[NETWORK] = 0usize
    s.values[BLUETOOTH] = 1usize
    s.values[ROTATE] = 1usize
    var n = 0usize
    while n < 8usize {
        s.values[NOTIFY + n] = 1usize
        n += 1usize
    }
    s.values[NOTIFY + 5usize] = 0usize
    dark_theme = true
}

fn is_on(s: *State, setting: usize) -> bool {
    ret s.values[setting] != 0usize
}

fn notify_count(s: *State) -> usize {
    var count = 0usize
    var n = 0usize
    while n < 8usize {
        if s.values[NOTIFY + n] != 0usize { count += 1usize }
        n += 1usize
    }
    ret count
}

fn lock_name(lock: usize) -> str {
    if lock == 0usize { ret "None" }
    if lock == 1usize { ret "Swipe" }
    ret "PIN"
}

fn font_name(font: usize) -> str {
    if font == 0usize { ret "Small" }
    if font == 1usize { ret "Default" }
    ret "Large"
}

fn timeout_name(timeout: usize) -> str {
    if timeout == 0usize { ret "15 sec" }
    if timeout == 1usize { ret "30 sec" }
    if timeout == 2usize { ret "1 min" }
    ret "5 min"
}

// The line under a category's name on the main list.
fn summary(a: *mem.Arena, s: *State, page: usize) -> str {
    if page == 0usize {
        if is_on(s, AIRPLANE) { ret "Airplane mode is on" }
        if is_on(s, WIFI) { ret join(a, "Wi-Fi on, ", network_name(s.values[NETWORK]), "") }
        ret "Wi-Fi off"
    }
    if page == 1usize { ret join(a, join(a, "Brightness ", number(a, s.values[BRIGHTNESS] * 10usize), "%"), ", dark theme ", on_off(is_on(s, DARK))) }
    if page == 2usize { ret join(a, "Media volume ", number(a, s.values[MEDIA] * 10usize), "%") }
    if page == 3usize { ret join(a, "78%, battery saver ", on_off(is_on(s, SAVER)), "") }
    if page == 4usize { ret "42.7 GB used of 128 GB" }
    if page == 5usize { ret join(a, number(a, notify_count(s)), " of 8 apps allowed", "") }
    if page == 6usize { ret join(a, number(a, icons.APP_COUNT), " apps", "") }
    if page == 7usize { ret join(a, "Screen lock: ", lock_name(s.values[LOCK]), "") }
    if page == 8usize { ret join(a, "Font size: ", font_name(s.values[FONT]), "") }
    if page == 9usize { ret "Date and time, reset" }
    ret "Neper phone"
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn cream() -> paint.Color {
    ret paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
}

fn ink() -> paint.Color {
    ret paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 }
}

fn muted() -> paint.Color {
    ret paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 }
}

fn amber() -> paint.Color {
    ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
}

fn soft() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

// The ground and the text on it, by theme.
fn ground(alpha: f32) -> paint.Color {
    if dark_theme { ret paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: alpha } }
    ret paint.Color { red: 0.92, green: 0.91, blue: 0.88, alpha: alpha }
}

fn fg() -> paint.Color {
    if dark_theme { ret paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 } }
    ret ink()
}

fn fg_dim() -> paint.Color {
    if dark_theme { ret paint.Color { red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0 } }
    ret muted()
}

fn surface() -> paint.Color {
    if dark_theme { ret cream() }
    ret paint.Color { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn disc(a: *mem.Arena, builder: *scene.Builder, cx: f32, cy: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.ellipse_path(a, cx, cy, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

fn hit(s: *State, id: usize, x: f32, y: f32, w: f32, h: f32) {
    if s.hit_total < MAX_HITS {
        s.hits[s.hit_total] = Hit { id: id, x: x, y: y, w: w, h: h }
        s.hit_total += 1usize
    }
}

fn put(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, 0.0, 0u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn clipped(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, width: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, width, 1u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

fn put_right(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, right: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, right - text.measure(a, font, size, line), y, c)
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn chevron_icon(up: bool) -> str {
    if up { ret "<svg viewBox='0 0 24 24'><path d='M6 15l6-6 6 6' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M6 9l6 6 6-6' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

// ---- rows: each draws itself at `y` and answers the y of the next.

// A switch row: the label, a line under it, the switch at the right.
fn toggle_row(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, setting: usize, caption: str, y: f32) -> err {
    let on = is_on(s, setting)
    try card(a, builder, 16.0, y + 2.0, 380.0, 64.0, 18.0, surface())
    try put(a, builder, faces.jost, 18.0, setting_name(setting), 32.0, y + 12.0, ink())
    if caption.len > 0usize { try put(a, builder, faces.grotesk, 12.0, caption, 32.0, y + 40.0, muted()) }
    var track = soft()
    if on { track = amber() }
    try card(a, builder, 328.0, y + 20.0, 52.0, 28.0, 14.0, track)
    var knob_x: f32 = 342.0
    if on { knob_x = 366.0 }
    try disc(a, builder, knob_x, y + 34.0, 11.0, paint.Color { red: 0.99, green: 0.98, blue: 0.96, alpha: 1.0 })
    hit(s, 1000usize + setting, 16.0, y + 2.0, 380.0, 64.0)
    ret ok
}

// A slider row of ten steps.
fn slider_row(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, setting: usize, y: f32) -> err {
    let value = s.values[setting]
    try card(a, builder, 16.0, y + 2.0, 380.0, 80.0, 18.0, surface())
    try put(a, builder, faces.jost, 18.0, setting_name(setting), 32.0, y + 10.0, ink())
    try put_right(a, builder, faces.jost, 18.0, join(a, number(a, value * 10usize), "%", ""), 380.0, y + 10.0, muted())
    try card(a, builder, 32.0, y + 54.0, 348.0, 6.0, 3.0, soft())
    let knob: f32 = 32.0 + f32(value) * 34.8
    try card(a, builder, 32.0, y + 54.0, knob - 32.0, 6.0, 3.0, amber())
    try disc(a, builder, knob, y + 57.0, 11.0, amber())
    hit(s, 2000usize + setting, 16.0, y + 38.0, 380.0, 44.0)
    ret ok
}

// A row of up to four choices.
fn chips_row(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, setting: usize, y: f32, o0: str, o1: str, o2: str, o3: str) -> err {
    try card(a, builder, 16.0, y + 2.0, 380.0, 88.0, 18.0, surface())
    try put(a, builder, faces.jost, 18.0, setting_name(setting), 32.0, y + 10.0, ink())
    var count = 4usize
    if o3.len == 0usize { count = 3usize }
    var k = 0usize
    while k < count {
        var label = o0
        if k == 1usize { label = o1 }
        if k == 2usize { label = o2 }
        if k == 3usize { label = o3 }
        let w: f32 = (348.0 - 8.0 * f32(count - 1usize)) / f32(count)
        let x: f32 = 32.0 + f32(k) * (w + 8.0)
        var fill = soft()
        if s.values[setting] == k { fill = amber() }
        try card(a, builder, x, y + 44.0, w, 34.0, 17.0, fill)
        try centred(a, builder, faces.jost, 14.0, label, x + w / 2.0, y + 44.0 + 17.0 - 9.0, ink())
        hit(s, 3000usize + setting * 10usize + k, x, y + 44.0, w, 34.0)
        k += 1usize
    }
    ret ok
}

fn info_row(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, label: str, value: str, y: f32) -> err {
    try card(a, builder, 16.0, y + 2.0, 380.0, 50.0, 16.0, surface())
    try put(a, builder, faces.grotesk, 13.0, label, 32.0, y + 17.0, muted())
    try clipped(a, builder, faces.jost, 17.0, value, 140.0, y + 14.0, 240.0, ink())
    ret ok
}

fn section(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, label: str, y: f32) -> err {
    try put(a, builder, faces.jost, 14.0, label, 24.0, y + 8.0, fg_dim())
    ret ok
}

// ---- the pages.

fn draw_network(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try toggle_row(a, builder, s, faces, WIFI, "", y)
    y += 68.0
    if is_on(s, WIFI) {
        try section(a, builder, faces, "Available networks", y)
        y += 34.0
        var n = 0usize
        while n < 4usize {
            try card(a, builder, 16.0, y + 2.0, 380.0, 54.0, 16.0, surface())
            try put(a, builder, faces.jost, 17.0, network_name(n), 32.0, y + 8.0, ink())
            var line = "Saved"
            if n == 1usize { line = "Open" }
            if n == 2usize { line = "Secured" }
            if n == 3usize { line = "Secured, saved" }
            if n == s.values[NETWORK] { line = "Connected" }
            try put(a, builder, faces.grotesk, 12.0, line, 32.0, y + 32.0, muted())
            if n == s.values[NETWORK] { try disc(a, builder, 372.0, y + 29.0, 6.0, amber()) }
            hit(s, 4000usize + n, 16.0, y + 2.0, 380.0, 54.0)
            y += 58.0
            n += 1usize
        }
    }
    try toggle_row(a, builder, s, faces, MOBILE, "", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, AIRPLANE, "", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, HOTSPOT, "", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, BLUETOOTH, "", y)
    ret ok
}

fn draw_display(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try slider_row(a, builder, s, faces, BRIGHTNESS, y)
    y += 84.0
    try toggle_row(a, builder, s, faces, ADAPTIVE, "Adjusts to the light around you", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, DARK, "Dark ground, light text", y)
    y += 68.0
    try chips_row(a, builder, s, faces, TIMEOUT, y, "15 sec", "30 sec", "1 min", "5 min")
    y += 92.0
    try chips_row(a, builder, s, faces, FONT, y, "Small", "Default", "Large", "")
    ret ok
}

fn draw_sound(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try slider_row(a, builder, s, faces, MEDIA, y)
    y += 84.0
    try slider_row(a, builder, s, faces, RING, y)
    y += 84.0
    try slider_row(a, builder, s, faces, ALARM, y)
    y += 84.0
    try toggle_row(a, builder, s, faces, DND, "Silences calls and notifications", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, VIBRATE, "", y)
    ret ok
}

fn draw_battery(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try card(a, builder, 16.0, y + 2.0, 380.0, 104.0, 18.0, surface())
    try put(a, builder, faces.jost_bold, 40.0, "78%", 32.0, y + 12.0, ink())
    try put(a, builder, faces.grotesk, 13.0, "About 1 day 4 hours left", 32.0, y + 66.0, muted())
    try card(a, builder, 32.0, y + 88.0, 348.0, 8.0, 4.0, soft())
    try card(a, builder, 32.0, y + 88.0, 348.0 * 0.78, 8.0, 4.0, amber())
    y += 112.0
    try toggle_row(a, builder, s, faces, SAVER, "Limits background activity", y)
    y += 72.0
    try section(a, builder, faces, "Battery use since full charge", y)
    y += 34.0
    var n = 0usize
    while n < 5usize {
        var name = "Screen"
        var share: f32 = 0.34
        if n == 1usize {
            name = "Camera"
            share = 0.18
        }
        if n == 2usize {
            name = "Maps"
            share = 0.12
        }
        if n == 3usize {
            name = "Messages"
            share = 0.08
        }
        if n == 4usize {
            name = "Music"
            share = 0.05
        }
        try card(a, builder, 16.0, y + 2.0, 380.0, 50.0, 16.0, surface())
        try put(a, builder, faces.jost, 16.0, name, 32.0, y + 14.0, ink())
        try card(a, builder, 170.0, y + 22.0, 150.0, 6.0, 3.0, soft())
        try card(a, builder, 170.0, y + 22.0, 150.0 * share * 2.5, 6.0, 3.0, amber())
        try put_right(a, builder, faces.grotesk, 13.0, join(a, number(a, usize(share * 100.0 + 0.5)), "%", ""), 380.0, y + 17.0, muted())
        y += 54.0
        n += 1usize
    }
    ret ok
}

fn draw_storage(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try card(a, builder, 16.0, y + 2.0, 380.0, 96.0, 18.0, surface())
    try put(a, builder, faces.jost_bold, 28.0, "42.7 GB", 32.0, y + 10.0, ink())
    try put(a, builder, faces.grotesk, 13.0, "used of 128 GB", 32.0, y + 48.0, muted())
    try card(a, builder, 32.0, y + 74.0, 348.0, 12.0, 6.0, soft())
    try card(a, builder, 32.0, y + 74.0, 116.0, 12.0, 6.0, paint.Color { red: 0.60, green: 0.80, blue: 0.70, alpha: 1.0 })
    try card(a, builder, 148.0, y + 74.0, 90.0, 12.0, 0.0, paint.Color { red: 0.72, green: 0.58, blue: 0.85, alpha: 1.0 })
    try card(a, builder, 238.0, y + 74.0, 34.0, 12.0, 0.0, paint.Color { red: 0.50, green: 0.64, blue: 0.88, alpha: 1.0 })
    try card(a, builder, 272.0, y + 74.0, 28.0, 12.0, 0.0, amber())
    y += 104.0
    var n = 0usize
    while n < 5usize {
        var name = "Images"
        var size = "14.6 GB"
        if n == 1usize {
            name = "Video and audio"
            size = "11.3 GB"
        }
        if n == 2usize {
            name = "Apps"
            size = "8.2 GB"
        }
        if n == 3usize {
            name = "Documents"
            size = "3.9 GB"
        }
        if n == 4usize {
            name = "System"
            size = "4.7 GB"
        }
        try info_row(a, builder, faces, name, size, y)
        y += 54.0
        n += 1usize
    }
    ret ok
}

fn draw_notifications(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    var n = 0usize
    while n < 8usize {
        try card(a, builder, 16.0, y + 2.0, 380.0, 64.0, 18.0, surface())
        try put(a, builder, faces.jost, 18.0, notify_app(n), 32.0, y + 22.0, ink())
        var track = soft()
        if s.values[NOTIFY + n] != 0usize { track = amber() }
        try card(a, builder, 328.0, y + 20.0, 52.0, 28.0, 14.0, track)
        var knob_x: f32 = 342.0
        if s.values[NOTIFY + n] != 0usize { knob_x = 366.0 }
        try disc(a, builder, knob_x, y + 34.0, 11.0, paint.Color { red: 0.99, green: 0.98, blue: 0.96, alpha: 1.0 })
        hit(s, 1000usize + NOTIFY + n, 16.0, y + 2.0, 380.0, 64.0)
        y += 68.0
        n += 1usize
    }
    ret ok
}

fn draw_apps(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var pos = 0usize
    while pos < icons.APP_COUNT {
        let y: f32 = 92.0 - s.scroll + f32(pos) * 56.0
        if y >= 90.0 && y + 56.0 <= 826.0 {
            try card(a, builder, 16.0, y + 2.0, 380.0, 50.0, 16.0, surface())
            try svg.draw(a, builder, icons.app(pos), geometry.rect(26.0, y + 8.0, 38.0, 38.0), ink())
            try put(a, builder, faces.jost, 17.0, icons.app_label(pos), 78.0, y + 14.0, ink())
            try put_right(a, builder, faces.grotesk, 13.0, join(a, number(a, 6usize + (pos * 37usize) % 90usize), " MB", ""), 380.0, y + 18.0, muted())
        }
        pos += 1usize
    }
    let content = f32(icons.APP_COUNT) * 56.0
    if s.scroll > 0.0 {
        try card(a, builder, 360.0, 98.0, 40.0, 40.0, 20.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.65 })
        try svg.draw(a, builder, chevron_icon(true), geometry.rect(368.0, 106.0, 24.0, 24.0), paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 })
        hit(s, 800usize, 352.0, 92.0, 56.0, 56.0)
    }
    if s.scroll + 734.0 < content {
        try card(a, builder, 360.0, 770.0, 40.0, 40.0, 20.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.65 })
        try svg.draw(a, builder, chevron_icon(false), geometry.rect(368.0, 778.0, 24.0, 24.0), paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 })
        hit(s, 801usize, 352.0, 764.0, 56.0, 56.0)
    }
    ret ok
}

fn draw_security(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try chips_row(a, builder, s, faces, LOCK, y, "None", "Swipe", "PIN", "")
    y += 92.0
    try toggle_row(a, builder, s, faces, FINGERPRINT, "Unlock with your fingerprint", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, LOCATION, "", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, CAMERA_ACCESS, "Apps can use the camera", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, MIC_ACCESS, "Apps can use the microphone", y)
    ret ok
}

fn draw_accessibility(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try chips_row(a, builder, s, faces, FONT, y, "Small", "Default", "Large", "")
    y += 92.0
    try toggle_row(a, builder, s, faces, CONTRAST, "Makes text easier to read", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, MAGNIFY, "Zoom in with a triple tap", y)
    y += 68.0
    try toggle_row(a, builder, s, faces, ROTATE, "", y)
    ret ok
}

fn draw_system(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try toggle_row(a, builder, s, faces, HOUR24, "", y)
    y += 68.0
    try info_row(a, builder, faces, "Language", "English (United States)", y)
    y += 54.0
    try info_row(a, builder, faces, "Time zone", "UTC", y)
    y += 54.0
    try card(a, builder, 16.0, y + 8.0, 380.0, 52.0, 26.0, amber())
    try centred(a, builder, faces.jost, 17.0, "Reset settings", 206.0, y + 22.0, ink())
    hit(s, 5000usize, 16.0, y + 8.0, 380.0, 52.0)
    ret ok
}

fn draw_about(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    try info_row(a, builder, faces, "Device name", "Neper phone", y)
    y += 54.0
    try info_row(a, builder, faces, "Model", "NeperOS virt (aarch64)", y)
    y += 54.0
    try info_row(a, builder, faces, "NeperOS version", "0.1 (sample)", y)
    y += 54.0
    try info_row(a, builder, faces, "Build number", "D2220", y)
    y += 54.0
    try info_row(a, builder, faces, "Kernel", "neperos aarch64", y)
    y += 54.0
    try info_row(a, builder, faces, "Storage", "128 GB", y)
    y += 54.0
    try info_row(a, builder, faces, "Memory", "1 GB", y)
    y += 54.0
    try info_row(a, builder, faces, "Screen", "1280 x 2856", y)
    ret ok
}

fn draw_main(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try put(a, builder, faces.jost_bold, 32.0, "Settings", 24.0, 22.0, fg())
    var page = 0usize
    while page < PAGES {
        let y: f32 = 80.0 + f32(page) * 68.0
        try card(a, builder, 16.0, y + 2.0, 380.0, 62.0, 18.0, surface())
        try disc(a, builder, 52.0, y + 33.0, 20.0, page_color(page))
        try centred(a, builder, faces.jost_bold, 15.0, page_tag(page), 52.0, y + 24.0, ink())
        try put(a, builder, faces.jost, 18.0, page_name(page), 86.0, y + 10.0, ink())
        try clipped(a, builder, faces.grotesk, 12.0, summary(a, s, page), 86.0, y + 36.0, 300.0, muted())
        hit(s, 100usize + page, 16.0, y + 2.0, 380.0, 62.0)
        page += 1usize
    }
    ret ok
}

fn draw_page(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), fg())
    hit(s, 500usize, 0.0, 10.0, 66.0, 56.0)
    try put(a, builder, faces.jost_bold, 24.0, page_name(s.page), 62.0, 20.0, fg())
    if s.page == 0usize { try draw_network(a, builder, s, faces) }
    if s.page == 1usize { try draw_display(a, builder, s, faces) }
    if s.page == 2usize { try draw_sound(a, builder, s, faces) }
    if s.page == 3usize { try draw_battery(a, builder, s, faces) }
    if s.page == 4usize { try draw_storage(a, builder, s, faces) }
    if s.page == 5usize { try draw_notifications(a, builder, s, faces) }
    if s.page == 6usize { try draw_apps(a, builder, s, faces) }
    if s.page == 7usize { try draw_security(a, builder, s, faces) }
    if s.page == 8usize { try draw_accessibility(a, builder, s, faces) }
    if s.page == 9usize { try draw_system(a, builder, s, faces) }
    if s.page == 10usize { try draw_about(a, builder, s, faces) }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: ground(1.0 - f32(kit.frame % 2usize) * 0.002) } } })
    if s.page == MAIN {
        try draw_main(a, builder, s, faces)
    } else {
        try draw_page(a, builder, s, faces)
    }
    var handle = paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 }
    if !dark_theme { handle = paint.Color { red: 0.15, green: 0.15, blue: 0.17, alpha: 0.8 } }
    try card(a, builder, 156.0, 906.0, 100.0, 5.0, 2.5, handle)
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

fn flip(s: *State, setting: usize) {
    if s.values[setting] == 0usize { s.values[setting] = 1usize } else { s.values[setting] = 0usize }
    if setting == DARK { dark_theme = s.values[DARK] != 0usize }
    // Airplane mode turns the radios off.
    if setting == AIRPLANE && s.values[AIRPLANE] != 0usize {
        s.values[WIFI] = 0usize
        s.values[MOBILE] = 0usize
        s.values[BLUETOOTH] = 0usize
        s.values[HOTSPOT] = 0usize
    }
    say("settings toggle ")
    if setting >= NOTIFY && setting < NOTIFY + 8usize { say(notify_app(setting - NOTIFY)) } else { say(setting_name(setting)) }
    say(" ")
    say(on_off(s.values[setting] != 0usize))
    say("\n")
}

// What a tap at `x` on button `id` did: true when the screen changed.
fn act(s: *State, id: usize, x: f32) -> bool {
    if s.page == MAIN {
        if id >= 100usize && id < 100usize + PAGES {
            s.page = id - 100usize
            s.scroll = 0.0
            say("settings page ")
            say(page_name(s.page))
            say("\n")
            ret true
        }
        ret false
    }
    if id == 500usize {
        s.page = MAIN
        say("settings back\n")
        ret true
    }
    if id >= 1000usize && id < 1000usize + SETTINGS {
        flip(s, id - 1000usize)
        ret true
    }
    if id >= 2000usize && id < 2000usize + SETTINGS {
        var step = (x - 32.0) / 34.8 + 0.5
        if step < 0.0 { step = 0.0 }
        if step > 10.0 { step = 10.0 }
        s.values[id - 2000usize] = usize(step)
        say("settings slider ")
        say(setting_name(id - 2000usize))
        say(" ")
        say_num(s.values[id - 2000usize] * 10usize)
        say("\n")
        ret true
    }
    if id >= 3000usize && id < 3000usize + SETTINGS * 10usize {
        let setting = (id - 3000usize) / 10usize
        s.values[setting] = (id - 3000usize) % 10usize
        say("settings choice ")
        say(setting_name(setting))
        say(" ")
        if setting == LOCK { say(lock_name(s.values[setting])) }
        if setting == FONT { say(font_name(s.values[setting])) }
        if setting == TIMEOUT { say(timeout_name(s.values[setting])) }
        say("\n")
        ret true
    }
    if id >= 4000usize && id < 4004usize {
        s.values[NETWORK] = id - 4000usize
        say("settings network ")
        say(network_name(s.values[NETWORK]))
        say("\n")
        ret true
    }
    if id == 5000usize {
        defaults(s)
        say("settings reset\n")
        ret true
    }
    if id == 800usize {
        s.scroll -= 280.0
        if s.scroll < 0.0 { s.scroll = 0.0 }
        ret true
    }
    if id == 801usize {
        s.scroll += 280.0
        ret true
    }
    ret false
}

fn hit_at(s: *State, x: f32, y: f32) -> usize {
    var i = s.hit_total
    while i > 0usize {
        i -= 1usize
        let h = s.hits[i]
        if x >= h.x && x < h.x + h.w && y >= h.y && y < h.y + h.h { ret h.id }
    }
    ret NONE
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "settings")
    if kit_error != ok {
        say("settings open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("settings fonts absent\n")
        ret ok
    }
    var s: State = zero
    defaults(&s)
    s.page = MAIN
    if !show(a, &kit, &s) {
        say("settings present failed\n")
        ret ok
    }
    say("settings shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("settings home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(&s, id, tap.x) {
                if !show(a, &kit, &s) {
                    say("settings present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
