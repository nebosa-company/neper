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
use vaultfs
use ui
use theme
use sysettings
use sensorclient
use netproto

const NONE: usize = 99usize
const MAX_HITS: usize = 96usize
const PAGES: usize = 11usize
const MAIN: usize = 99usize
const SEARCH: usize = 98usize
const SHEET: usize = 97usize
const DETAIL: usize = 96usize
const FOUND_MAX: usize = 6usize
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
// Time zone: 0 UTC, 1 Berlin (+1), 2 New York (-5), 3 Tokyo (+9). The shell's clock and date follow it.
const TIMEZONE: usize = 34usize
// (C175, C168) How long a copy stays on the clipboard (0 30 s, 1 a minute, 2 five minutes, 3 fifteen), and the profile
// the step counter's calories follow (a height and a weight, four steps each).
const CLIPBOARD: usize = 35usize
const HEIGHT: usize = 36usize
const WEIGHT: usize = 37usize
// The Settings icon's index on the home screen: the one app that cannot be uninstalled.
const SETTINGS_ICON: usize = 19usize

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
    if setting == TIMEZONE { ret "Time zone" }
    if setting == CLIPBOARD { ret "Clear clipboard after" }
    if setting == HEIGHT { ret "Height" }
    if setting == WEIGHT { ret "Weight" }
    ret "Notifications"
}

// (C126) What a setting is called in search, the words that also find it, and the page it lives on. The
// notification switches (NOTIFY + app) are listed under the app's name.
fn setting_label(setting: usize) -> str {
    if setting == TIMEZONE { ret "Time zone" }
    if setting > TIMEZONE { ret setting_name(setting) }
    if setting >= NOTIFY { ret notify_app(setting - NOTIFY) }
    ret setting_name(setting)
}

fn setting_words(setting: usize) -> str {
    if setting == WIFI { ret "wifi wireless internet wlan" }
    if setting == MOBILE { ret "cellular data sim lte 5g" }
    if setting == AIRPLANE { ret "flight radio offline" }
    if setting == HOTSPOT { ret "tethering share internet" }
    if setting == BRIGHTNESS { ret "screen light dim display" }
    if setting == DARK { ret "night mode theme black" }
    if setting == ADAPTIVE { ret "auto light sensor" }
    if setting == TIMEOUT { ret "sleep screen off lock delay" }
    if setting == FONT { ret "text size larger bigger" }
    if setting == MEDIA { ret "sound music video speaker audio" }
    if setting == RING { ret "ringtone call phone volume" }
    if setting == ALARM { ret "clock wake volume" }
    if setting == DND { ret "silent quiet mute interruptions" }
    if setting == VIBRATE { ret "haptic buzz calls" }
    if setting == SAVER { ret "power low battery" }
    if setting == LOCATION { ret "gps position places" }
    if setting == CAMERA_ACCESS { ret "privacy permission photo" }
    if setting == MIC_ACCESS { ret "privacy permission voice record" }
    if setting == FINGERPRINT { ret "biometric unlock security touch" }
    if setting == LOCK { ret "pin pattern password security" }
    if setting == HOUR24 { ret "time clock format military" }
    if setting == CONTRAST { ret "accessibility text vision" }
    if setting == MAGNIFY { ret "zoom accessibility vision" }
    if setting == NETWORK { ret "wifi networks ssid" }
    if setting == BLUETOOTH { ret "pair wireless headphones devices" }
    if setting == ROTATE { ret "orientation landscape portrait screen" }
    if setting == TIMEZONE { ret "region utc berlin new york tokyo clock date" }
    if setting == CLIPBOARD { ret "copy paste clipboard erase privacy" }
    if setting == HEIGHT || setting == WEIGHT { ret "profile body calories steps fitness" }
    ret "alerts messages"
}

fn setting_page(setting: usize) -> usize {
    if setting == WIFI || setting == MOBILE || setting == AIRPLANE || setting == HOTSPOT { ret 0usize }
    if setting == NETWORK || setting == BLUETOOTH { ret 0usize }
    if setting == BRIGHTNESS || setting == DARK || setting == ADAPTIVE || setting == TIMEOUT || setting == FONT { ret 1usize }
    if setting == MEDIA || setting == RING || setting == ALARM || setting == DND || setting == VIBRATE { ret 2usize }
    if setting == SAVER { ret 3usize }
    if setting == TIMEZONE || setting == HEIGHT || setting == WEIGHT { ret 9usize }
    if setting == CLIPBOARD { ret 7usize }
    if setting >= NOTIFY { ret 5usize }
    if setting == LOCATION || setting == CAMERA_ACCESS || setting == MIC_ACCESS || setting == FINGERPRINT || setting == LOCK { ret 7usize }
    if setting == HOUR24 { ret 9usize }
    ret 8usize
}

// Whether the lower-case term q.bytes[from..to] occurs in `hay`, ignoring its case.
fn term_in(hay: str, q: *ui.Field, from: usize, to: usize) -> bool {
    let width = to - from
    var at = 0usize
    while at + width <= hay.len {
        var k = 0usize
        var matched = true
        while k < width && matched {
            var h = hay[at + k]
            if h >= 65u8 && h <= 90u8 { h = h + 32u8 }
            if h != q.bytes[from + k] { matched = false }
            k += 1usize
        }
        if matched { ret true }
        at += 1usize
    }
    ret false
}

// Every space-separated term of the query is in the setting's name or its words; an empty query matches nothing.
fn setting_matches(q: *ui.Field, setting: usize) -> bool {
    let name = setting_label(setting)
    let words = setting_words(setting)
    var i = 0usize
    var any = false
    while i < q.len {
        while i < q.len && q.bytes[i] == 32u8 { i += 1usize }
        let start = i
        while i < q.len && q.bytes[i] != 32u8 { i += 1usize }
        if i > start {
            any = true
            if !term_in(name, q, start, i) && !term_in(words, q, start, i) { ret false }
        }
    }
    ret any
}

fn find_settings(s: *State) {
    s.found_total = 0usize
    var setting = 0usize
    while setting < NOTIFY + 9usize && s.found_total < FOUND_MAX {
        if setting_matches(&s.search, setting) {
            s.found[s.found_total] = setting
            s.found_total += 1usize
        }
        setting += 1usize
    }
}

// (C126) The networks the network server hears (its SCAN: a name, secured, signal, flags), through the two
// endpoints every app is granted when the machine has a network device; and joining one, with the password
// from the sheet. A machine without the capability gets the kernel's refusal and shows "no networks".
fn scan_networks(s: *State) {
    s.net_total = 0usize
    s.net_ok = false
    let sent = os.send(3usize, netproto.OP_SCAN, netproto.NO_SLOT)
    if sent == 18446744073709551615usize { ret }
    let result = os.recv(4usize, netproto.NO_SLOT)
    let count = os.recv(4usize, netproto.NO_SLOT)
    var scratch: [32]u8 = zero
    var i = 0usize
    while i < count {
        var kept = 0usize
        if i < 8usize {
            kept = netproto.recv_bytes(4usize, mem.address_of(&s.net_names[i * 24usize]), 24usize)
        } else {
            kept = netproto.recv_bytes(4usize, mem.address_of(&scratch[0usize]), 24usize)
        }
        let secured = os.recv(4usize, netproto.NO_SLOT)
        let signal = os.recv(4usize, netproto.NO_SLOT)
        let flags = os.recv(4usize, netproto.NO_SLOT)
        if i < 8usize {
            s.net_len[i] = kept
            s.net_secured[i] = secured
            s.net_signal[i] = signal
            s.net_flags[i] = flags
        }
        i += 1usize
    }
    if count > 8usize { s.net_total = 8usize } else { s.net_total = count }
    s.net_ok = result == netproto.R_OK
    say("settings wifi scan ")
    say_num(s.net_total)
    say("\n")
}

// The first network with its connected flag, or 99.
fn connected_net(s: *State) -> usize {
    var i = 0usize
    while i < s.net_total {
        if (s.net_flags[i] & 1usize) != 0usize { ret i }
        i += 1usize
    }
    ret 99usize
}

// Join network `n` with the password typed on the sheet; a netproto.R_* result (a refused send counts as R_NO_NETWORK).
fn join_network(s: *State, n: usize) -> usize {
    let sent = os.send(3usize, netproto.OP_JOIN, netproto.NO_SLOT)
    if sent == 18446744073709551615usize { ret netproto.R_NO_NETWORK }
    netproto.send_bytes(3usize, mem.address_of(&s.net_names[n * 24usize]), s.net_len[n])
    netproto.send_bytes(3usize, mem.address_of(&s.pass.bytes[0usize]), s.pass.len)
    ret os.recv(4usize, netproto.NO_SLOT)
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
    search: ui.Field,
    mirror: [48]usize,
    hidden: usize,
    battery: usize,
    dyn_total: usize,
    dyn_names: [144]u8,
    dyn_len: [6]usize,
    dyn_version: [6]usize,
    detail: usize,
    net_names: [192]u8,
    net_len: [8]usize,
    net_flags: [8]usize,
    net_secured: [8]usize,
    net_signal: [8]usize,
    net_total: usize,
    net_ok: bool,
    sheet: usize,
    pass: ui.Field,
    join_note: usize,
    have_storage: bool,
    storage_used: usize,
    storage_total: usize,
    app_sizes: [32]usize,
    found: [8]usize,
    found_total: usize,
    keys: ui.Hits,
}

// (C126) Every setting at its default, from theme.e, the table the settings server uses too.
fn defaults(s: *State) {
    var i = 0usize
    while i < SETTINGS {
        s.values[i] = theme.default_value(i)
        i += 1usize
    }
    dark_theme = true
}

// (C126) The values are kept in /settings, one byte each, through the filesystem server on the endpoints the
// kernel grants this app (slots 5 and 6, as for Secure). A machine without a disk refuses the first send and
// the app runs on its defaults; a file of another length or with a value past a slider's range is ignored.
fn save(s: *State) {
    var raw: [48]u8 = zero
    var i = 0usize
    while i < SETTINGS {
        raw[i] = u8(s.values[i])
        i += 1usize
    }
    if vaultfs.write("/settings", mem.address_of(&raw[0usize]), SETTINGS) { say("settings saved\n") }
}

fn load(s: *State) -> bool {
    var raw: [48]u8 = zero
    let (count, found) = vaultfs.read("/settings", mem.address_of(&raw[0usize]), 48usize)
    if !found || count != SETTINGS { ret false }
    var i = 0usize
    while i < SETTINGS {
        if raw[i] > 10u8 { ret false }
        i += 1usize
    }
    i = 0usize
    while i < SETTINGS {
        s.values[i] = usize(raw[i])
        i += 1usize
    }
    dark_theme = s.values[DARK] != 0usize
    ret true
}

// (C126) The three settings every app follows go out as the theme word: to this app's own text and ground at
// once, and to the shell as the exit code, which hands it to the apps it launches next.
fn sync_theme(s: *State) {
    theme.set(theme.word_of(s.values[DARK], s.values[CONTRAST], s.values[FONT], s.values[HOUR24], s.values[BRIGHTNESS], s.values[LOCK], s.values[DND]))
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

fn zone_name(zone: usize) -> str {
    if zone == 0usize { ret "UTC" }
    if zone == 1usize { ret "Berlin" }
    if zone == 2usize { ret "New York" }
    ret "Tokyo"
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
        if is_on(s, WIFI) {
            let connected = connected_net(s)
            if connected != 99usize { ret join(a, "Wi-Fi on, ", ui.text_of(a, s.net_names[connected * 24usize..], s.net_len[connected]), "") }
            ret "Wi-Fi on"
        }
        ret "Wi-Fi off"
    }
    if page == 1usize { ret join(a, join(a, "Brightness ", number(a, s.values[BRIGHTNESS] * 10usize), "%"), ", dark theme ", on_off(is_on(s, DARK))) }
    if page == 2usize { ret join(a, "Media volume ", number(a, s.values[MEDIA] * 10usize), "%") }
    if page == 3usize {
        if (s.battery & 2147483648usize) != 0usize { ret join(a, join(a, number(a, s.battery & 255usize), "%, battery saver ", ""), on_off(is_on(s, SAVER)), "") }
        ret join(a, "Level unavailable, battery saver ", on_off(is_on(s, SAVER)), "")
    }
    if page == 4usize {
        if !s.have_storage { ret "No storage" }
        ret join(a, size_text(a, s.storage_used * 512usize), " used of ", size_text(a, s.storage_total * 512usize))
    }
    if page == 5usize { ret join(a, number(a, notify_count(s)), " of 8 apps allowed", "") }
    if page == 6usize {
        var installed = 0usize
        var i = 0usize
        while i < icons.APP_COUNT {
            if ((s.hidden >> i) & 1usize) == 0usize { installed += 1usize }
            i += 1usize
        }
        ret join(a, number(a, installed + s.dyn_total), " apps", "")
    }
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

// (C176) A permission of one app (the sensor server holds it, one bit a kind and an app): a switch whose state is the app's
// own, with the system-wide switch it also needs noted beneath.
fn perm_row(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, label: str, caption: str, kind: usize, program: usize, y: f32) -> err {
    let on = sensorclient.permitted(program, kind)
    try card(a, builder, 16.0, y + 2.0, 380.0, 64.0, 18.0, surface())
    try put(a, builder, faces.jost, 18.0, label, 32.0, y + 12.0, ink())
    if caption.len > 0usize { try put(a, builder, faces.grotesk, 12.0, caption, 32.0, y + 40.0, muted()) }
    var track = soft()
    if on { track = amber() }
    try card(a, builder, 328.0, y + 20.0, 52.0, 28.0, 14.0, track)
    var knob_x: f32 = 342.0
    if on { knob_x = 366.0 }
    try disc(a, builder, knob_x, y + 34.0, 11.0, paint.Color { red: 0.99, green: 0.98, blue: 0.96, alpha: 1.0 })
    hit(s, 8000usize + kind, 16.0, y + 2.0, 380.0, 64.0)
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
        if s.net_total == 0usize {
            try card(a, builder, 16.0, y + 2.0, 380.0, 54.0, 16.0, surface())
            try put(a, builder, faces.jost, 17.0, "No networks found", 32.0, y + 8.0, ink())
            try put(a, builder, faces.grotesk, 12.0, "This machine has no network device.", 32.0, y + 32.0, muted())
            y += 58.0
        }
        var n = 0usize
        while n < s.net_total {
            let connected = (s.net_flags[n] & 1usize) != 0usize
            try card(a, builder, 16.0, y + 2.0, 380.0, 54.0, 16.0, surface())
            try put(a, builder, faces.jost, 17.0, ui.text_of(a, s.net_names[n * 24usize..], s.net_len[n]), 32.0, y + 8.0, ink())
            var line = "Open"
            if s.net_secured[n] != 0usize { line = "Secured" }
            if (s.net_flags[n] & 2usize) != 0usize { line = "Secured, saved" }
            if connected { line = "Connected" }
            try put(a, builder, faces.grotesk, 12.0, line, 32.0, y + 32.0, muted())
            try put_right(a, builder, faces.grotesk, 12.0, join(a, number(a, s.net_signal[n]), "%", ""), 346.0, y + 32.0, muted())
            if connected { try disc(a, builder, 372.0, y + 29.0, 6.0, amber()) }
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

// (C126) The battery's level and use are the status service's and no app is granted it yet, so the page says
// so rather than show made-up numbers; the battery saver switch is kept.
fn draw_battery(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    if (s.battery & 2147483648usize) != 0usize {
        let level = s.battery & 255usize
        try card(a, builder, 16.0, y + 2.0, 380.0, 96.0, 18.0, surface())
        try put(a, builder, faces.jost_bold, 40.0, join(a, number(a, level), "%", ""), 32.0, y + 10.0, ink())
        var state_line = "Not charging"
        if (s.battery & 256usize) != 0usize { state_line = "Charging" }
        try put(a, builder, faces.grotesk, 13.0, state_line, 32.0, y + 58.0, muted())
        try card(a, builder, 32.0, y + 78.0, 348.0, 8.0, 4.0, soft())
        try card(a, builder, 32.0, y + 78.0, 348.0 * f32(level) / 100.0, 8.0, 4.0, amber())
        y += 108.0
    } else {
        try card(a, builder, 16.0, y + 2.0, 380.0, 76.0, 18.0, surface())
        try put(a, builder, faces.jost, 20.0, "Battery level unavailable", 32.0, y + 12.0, ink())
        try put(a, builder, faces.grotesk, 13.0, "No battery provider reports to the system.", 32.0, y + 46.0, muted())
        y += 88.0
    }
    try toggle_row(a, builder, s, faces, SAVER, "Limits background activity", y)
    ret ok
}

// (C126) A size in B, KB or MB with one decimal.
fn size_text(a: *mem.Arena, bytes: usize) -> str {
    if bytes >= 1048576usize {
        let tenths = bytes * 10usize / 1048576usize
        ret join(a, join(a, number(a, tenths / 10usize), ".", number(a, tenths % 10usize)), " MB", "")
    }
    if bytes >= 1024usize {
        let tenths = bytes * 10usize / 1024usize
        ret join(a, join(a, number(a, tenths / 10usize), ".", number(a, tenths % 10usize)), " KB", "")
    }
    ret join(a, number(a, bytes), " B", "")
}

// The disk's real numbers, from the filesystem server's OP_STATS: blocks allocated and blocks held.
fn draw_storage(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var y: f32 = 92.0
    if !s.have_storage {
        try card(a, builder, 16.0, y + 2.0, 380.0, 70.0, 18.0, surface())
        try put(a, builder, faces.jost, 20.0, "No storage on this machine", 32.0, y + 12.0, ink())
        try put(a, builder, faces.grotesk, 13.0, "The system has no disk to report.", 32.0, y + 42.0, muted())
        ret ok
    }
    let used_bytes = s.storage_used * 512usize
    let total_bytes = s.storage_total * 512usize
    var share: f32 = 0.0
    if s.storage_total > 0usize { share = f32(s.storage_used) / f32(s.storage_total) }
    if share > 1.0 { share = 1.0 }
    try card(a, builder, 16.0, y + 2.0, 380.0, 96.0, 18.0, surface())
    try put(a, builder, faces.jost_bold, 28.0, size_text(a, used_bytes), 32.0, y + 10.0, ink())
    try put(a, builder, faces.grotesk, 13.0, join(a, "used of ", size_text(a, total_bytes), ""), 32.0, y + 48.0, muted())
    try card(a, builder, 32.0, y + 74.0, 348.0, 12.0, 6.0, soft())
    if share > 0.0 { try card(a, builder, 32.0, y + 74.0, 348.0 * share + 4.0, 12.0, 6.0, amber()) }
    y += 104.0
    try info_row(a, builder, faces, "Used", size_text(a, used_bytes), y)
    y += 54.0
    var free_bytes = 0usize
    if total_bytes > used_bytes { free_bytes = total_bytes - used_bytes }
    try info_row(a, builder, faces, "Free", size_text(a, free_bytes), y)
    y += 54.0
    try info_row(a, builder, faces, "Disk size", size_text(a, total_bytes), y)
    y += 54.0
    try info_row(a, builder, faces, "Blocks in use", number(a, s.storage_used), y)
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
            hit(s, 7000usize + pos, 16.0, y + 2.0, 380.0, 50.0)
            if ((s.hidden >> pos) & 1usize) != 0usize {
                try put_right(a, builder, faces.grotesk, 13.0, "Uninstalled", 380.0, y + 18.0, muted())
            } else {
            // The size of the app's program in the archive, handed to this app by the kernel (entries 13 to 44).
            let program = icons.program_of(pos)
            if program >= 13usize && program < 45usize && s.app_sizes[program - 13usize] > 0usize {
                try put_right(a, builder, faces.grotesk, 13.0, size_text(a, s.app_sizes[program - 13usize]), 380.0, y + 18.0, muted())
            }
            }
        }
        pos += 1usize
    }
    // The dynamic apps follow the system ones, with the Dynamic icon and their version.
    var dyn = 0usize
    while dyn < s.dyn_total {
        let y: f32 = 92.0 - s.scroll + f32(icons.APP_COUNT + dyn) * 56.0
        if y >= 90.0 && y + 56.0 <= 826.0 {
            try card(a, builder, 16.0, y + 2.0, 380.0, 50.0, 16.0, surface())
            try svg.draw(a, builder, icons.app(26usize), geometry.rect(26.0, y + 8.0, 38.0, 38.0), ink())
            try put(a, builder, faces.jost, 17.0, ui.text_of(a, s.dyn_names[dyn * 24usize..], s.dyn_len[dyn]), 78.0, y + 14.0, ink())
            try put_right(a, builder, faces.grotesk, 13.0, join(a, "Dynamic, v", number(a, s.dyn_version[dyn]), ""), 380.0, y + 18.0, muted())
            hit(s, 7100usize + dyn, 16.0, y + 2.0, 380.0, 50.0)
        }
        dyn += 1usize
    }
    let content = f32(icons.APP_COUNT + s.dyn_total) * 56.0
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
    y += 68.0
    try chips_row(a, builder, s, faces, CLIPBOARD, y, "30 s", "1 min", "5 min", "15 min")
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
    try chips_row(a, builder, s, faces, TIMEZONE, y, "UTC", "Berlin", "New York", "Tokyo")
    y += 92.0
    try chips_row(a, builder, s, faces, HEIGHT, y, "155 cm", "165 cm", "175 cm", "185 cm")
    y += 92.0
    try chips_row(a, builder, s, faces, WEIGHT, y, "55 kg", "70 kg", "85 kg", "100 kg")
    y += 92.0
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
    try card(a, builder, 292.0, 24.0, 104.0, 38.0, 19.0, surface())
    try centred(a, builder, faces.jost, 17.0, "Search", 344.0, 31.0, ink())
    hit(s, 600usize, 292.0, 24.0, 104.0, 38.0)
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

fn draw_search(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), fg())
    hit(s, 500usize, 0.0, 10.0, 66.0, 56.0)
    try put(a, builder, faces.jost_bold, 24.0, "Search", 62.0, 20.0, fg())
    try card(a, builder, 16.0, 70.0, 380.0, 50.0, 14.0, cream())
    if s.search.len == 0usize {
        try put(a, builder, faces.jost, 20.0, "Search settings", 30.0, 82.0, muted())
        try centred(a, builder, faces.grotesk, 14.0, "Try brightness, wifi or volume", 206.0, 150.0, fg_dim())
    } else {
        try put(a, builder, faces.jost, 20.0, ui.field_text(a, &s.search), 30.0, 82.0, ink())
        if s.found_total == 0usize {
            try centred(a, builder, faces.grotesk, 14.0, "No settings match", 206.0, 150.0, fg_dim())
        }
    }
    var i = 0usize
    while i < s.found_total {
        let y: f32 = 136.0 + f32(i) * 58.0
        let setting = s.found[i]
        try card(a, builder, 16.0, y, 380.0, 50.0, 14.0, surface())
        try put(a, builder, faces.jost, 18.0, setting_label(setting), 30.0, y + 5.0, ink())
        try clipped(a, builder, faces.grotesk, 12.0, page_name(setting_page(setting)), 30.0, y + 30.0, 330.0, muted())
        hit(s, 6000usize + i, 16.0, y, 380.0, 50.0)
        i += 1usize
    }
    s.keys.total = 0usize
    try ui.keyboard(a, builder, &s.keys, faces, "Go")
    ret ok
}

fn draw_sheet(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), fg())
    hit(s, 500usize, 0.0, 10.0, 66.0, 56.0)
    try put(a, builder, faces.jost_bold, 24.0, join(a, "Join ", ui.text_of(a, s.net_names[s.sheet * 24usize..], s.net_len[s.sheet]), ""), 62.0, 20.0, fg())
    try put(a, builder, faces.grotesk, 14.0, "Password", 20.0, 84.0, fg_dim())
    try card(a, builder, 16.0, 108.0, 380.0, 50.0, 14.0, cream())
    if s.pass.len == 0usize {
        try put(a, builder, faces.jost, 20.0, "Enter the password", 30.0, 120.0, muted())
    } else {
        let (dots, dots_error) = mem.alloc[u8](a, s.pass.len)
        if dots_error != ok { ret dots_error }
        var i = 0usize
        while i < s.pass.len {
            dots[i] = 42u8
            i += 1usize
        }
        try put(a, builder, faces.jost, 22.0, ui.text_of(a, dots[0usize..], s.pass.len), 30.0, 120.0, ink())
    }
    if s.join_note == 1usize { try put(a, builder, faces.grotesk, 14.0, "Wrong password", 20.0, 170.0, paint.Color { red: 0.95, green: 0.45, blue: 0.40, alpha: 1.0 }) }
    if s.join_note == 2usize { try put(a, builder, faces.grotesk, 14.0, "Could not connect", 20.0, 170.0, paint.Color { red: 0.95, green: 0.45, blue: 0.40, alpha: 1.0 }) }
    s.keys.total = 0usize
    try ui.keyboard(a, builder, &s.keys, faces, "Join")
    ret ok
}

// One app: its icon, name and size, its notification switch when it has one, the access the system grants all
// apps (the camera, microphone and location switches under Security), and Uninstall or Reinstall.
fn draw_detail(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let pos = s.detail
    if pos >= icons.APP_COUNT {
        // A dynamic app, from the registry: its name and version, and Remove.
        let k = pos - icons.APP_COUNT
        try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), fg())
        hit(s, 500usize, 0.0, 10.0, 66.0, 56.0)
        try put(a, builder, faces.jost_bold, 24.0, "App info", 62.0, 20.0, fg())
        try card(a, builder, 16.0, 78.0, 380.0, 96.0, 18.0, surface())
        try svg.draw(a, builder, icons.app(26usize), geometry.rect(30.0, 94.0, 64.0, 64.0), ink())
        try put(a, builder, faces.jost_bold, 22.0, ui.text_of(a, s.dyn_names[k * 24usize..], s.dyn_len[k]), 112.0, 96.0, ink())
        try put(a, builder, faces.grotesk, 14.0, join(a, "Dynamic app, version ", number(a, s.dyn_version[k]), ""), 112.0, 130.0, muted())
        try card(a, builder, 16.0, 214.0, 380.0, 54.0, 27.0, paint.Color { red: 0.86, green: 0.36, blue: 0.32, alpha: 1.0 })
        try centred(a, builder, faces.jost, 20.0, "Remove", 206.0, 229.0, ink())
        hit(s, 7500usize, 16.0, 214.0, 380.0, 54.0)
        ret ok
    }
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), fg())
    hit(s, 500usize, 0.0, 10.0, 66.0, 56.0)
    try put(a, builder, faces.jost_bold, 24.0, "App info", 62.0, 20.0, fg())
    try card(a, builder, 16.0, 78.0, 380.0, 96.0, 18.0, surface())
    try svg.draw(a, builder, icons.app(pos), geometry.rect(30.0, 94.0, 64.0, 64.0), ink())
    try put(a, builder, faces.jost_bold, 22.0, icons.app_label(pos), 112.0, 96.0, ink())
    let program = icons.program_of(pos)
    var size_line = "Not installed in this build"
    if program >= 13usize && program < 45usize && s.app_sizes[program - 13usize] > 0usize { size_line = size_text(a, s.app_sizes[program - 13usize]) }
    if ((s.hidden >> pos) & 1usize) != 0usize { size_line = "Uninstalled" }
    try put(a, builder, faces.grotesk, 14.0, size_line, 112.0, 130.0, muted())
    var y: f32 = 190.0
    let notify = notify_of(icons.app_label(pos))
    if notify != 99usize {
        try toggle_row(a, builder, s, faces, notify, "Notifications from this app", y)
        y += 68.0
    }
    try section(a, builder, faces, "Access", y)
    y += 34.0
    try perm_row(a, builder, s, faces, "Camera", "Needs Camera access in Security & privacy", sensorclient.KIND_CAMERA, program, y)
    y += 68.0
    try info_row(a, builder, faces, "Microphone", on_off(is_on(s, MIC_ACCESS)), y)
    y += 54.0
    try perm_row(a, builder, s, faces, "Location", "Needs Location in Security & privacy", sensorclient.KIND_LOCATION, program, y)
    y += 68.0
    try perm_row(a, builder, s, faces, "Storage", "Files this app may keep", sensorclient.KIND_STORAGE, program, y)
    y += 74.0
    if pos == SETTINGS_ICON {
        try put(a, builder, faces.grotesk, 14.0, "A system app: it cannot be uninstalled.", 20.0, y + 14.0, fg_dim())
    } else {
        var label = "Uninstall"
        var fill = paint.Color { red: 0.86, green: 0.36, blue: 0.32, alpha: 1.0 }
        if ((s.hidden >> pos) & 1usize) != 0usize {
            label = "Reinstall"
            fill = amber()
        }
        try card(a, builder, 16.0, y, 380.0, 54.0, 27.0, fill)
        try centred(a, builder, faces.jost, 20.0, label, 206.0, y + 15.0, ink())
        hit(s, 7500usize, 16.0, y, 380.0, 54.0)
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
    } else if s.page == SEARCH {
        try draw_search(a, builder, s, faces)
    } else if s.page == SHEET {
        try draw_sheet(a, builder, s, faces)
    } else if s.page == DETAIL {
        try draw_detail(a, builder, s, faces)
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
    if setting == WIFI && s.values[WIFI] != 0usize { scan_networks(s) }
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
// The dynamic apps the settings server's registry holds (the Dynamic app's, C124's to come).
fn load_dynamic(s: *State) {
    s.dyn_total = 0usize
    var i = 0usize
    while i < 6usize {
        let (w0, w1, w2, w3, answered) = sysettings.dyn_get(i)
        let length = w3 & 255usize
        if answered && length > 0usize && length <= 24usize {
            let n = s.dyn_total
            var j = 0usize
            while j < length {
                var word = w2
                if j < 8usize { word = w0 } else if j < 16usize { word = w1 }
                s.dyn_names[n * 24usize + j] = u8((word >> ((j % 8usize) * 8usize)) & 255usize)
                j += 1usize
            }
            s.dyn_len[n] = length
            s.dyn_version[n] = (w3 >> 16usize) & 255usize
            s.dyn_total += 1usize
        }
        i += 1usize
    }
}

// The notification switch an app has in this app's list (NOTIFY + n), by its name, or 99.
fn notify_of(label: str) -> usize {
    var k = 0usize
    while k < 8usize {
        if ui.same(notify_app(k), label) { ret NOTIFY + k }
        k += 1usize
    }
    ret 99usize
}

// Remove dynamic app `k` from the registry: the later entries move up one place.
fn remove_dynamic(s: *State, k: usize) {
    var i = k
    while i < 5usize {
        var w0 = 0usize
        var w1 = 0usize
        var w2 = 0usize
        var w3 = 0usize
        if i + 1usize < 6usize {
            let (n0, n1, n2, n3, answered) = sysettings.dyn_get(i + 1usize)
            w0 = n0
            w1 = n1
            w2 = n2
            w3 = n3
        }
        let stored = sysettings.dyn_set(i, w0, w1, w2, w3)
        i += 1usize
    }
    let cleared = sysettings.dyn_set(5usize, 0usize, 0usize, 0usize, 0usize)
    load_dynamic(s)
}

fn act(s: *State, id: usize, x: f32) -> bool {
    if s.page == DETAIL && s.detail < icons.APP_COUNT && id >= 8000usize && id < 8008usize {
        // A permission of this app flipped: kept by the sensor server, only this app (Settings) may say so.
        let program = icons.program_of(s.detail)
        let kind = id - 8000usize
        let was = sensorclient.permitted(program, kind)
        let taken = sensorclient.set_permit(program, kind, !was)
        say("settings permission ")
        say(icons.app_label(s.detail))
        if kind == sensorclient.KIND_CAMERA { say(" camera ") }
        if kind == sensorclient.KIND_LOCATION { say(" location ") }
        if kind == sensorclient.KIND_STORAGE { say(" storage ") }
        if taken && !was { say("on\n") } else if taken { say("off\n") } else { say("refused\n") }
        ret true
    }
    if s.page == DETAIL && s.detail >= icons.APP_COUNT {
        if id == 500usize {
            s.page = 6usize
            say("settings back\n")
            ret true
        }
        if id == 7500usize {
            let k = s.detail - icons.APP_COUNT
            say("settings dynamic removed ")
            say(s.dyn_names[k * 24usize..k * 24usize + s.dyn_len[k]])
            say("\n")
            remove_dynamic(s, k)
            s.page = 6usize
            ret true
        }
        ret false
    }
    if s.page == 6usize && id >= 7100usize && id < 7100usize + s.dyn_total {
        s.detail = icons.APP_COUNT + (id - 7100usize)
        s.page = DETAIL
        say("settings dynamic app ")
        say(s.dyn_names[(id - 7100usize) * 24usize..(id - 7100usize) * 24usize + s.dyn_len[id - 7100usize]])
        say("\n")
        ret true
    }
    if s.page == DETAIL {
        if id == 500usize {
            s.page = 6usize
            say("settings back\n")
            ret true
        }
        if id == 7500usize && s.detail != SETTINGS_ICON {
            var flag = 1usize
            if ((s.hidden >> s.detail) & 1usize) != 0usize { flag = 0usize }
            s.hidden = sysettings.set_hidden(s.detail, flag)
            if s.hidden == 0usize && flag != 0usize { s.hidden = 1usize << s.detail }
            if flag != 0usize { say("settings uninstalled ") } else { say("settings reinstalled ") }
            say(icons.app_label(s.detail))
            say("\n")
            ret true
        }
        if id >= 1000usize && id < 1000usize + SETTINGS {
            flip(s, id - 1000usize)
            ret true
        }
        ret false
    }
    if s.page == 6usize && id >= 7000usize && id < 7000usize + icons.APP_COUNT {
        s.detail = id - 7000usize
        s.page = DETAIL
        say("settings app ")
        say(icons.app_label(s.detail))
        say("\n")
        ret true
    }
    if s.page == SHEET {
        if id == 500usize {
            s.page = 0usize
            say("settings back\n")
            ret true
        }
        if id == 1205usize {
            let n = s.sheet
            let result = join_network(s, n)
            if result == netproto.R_OK {
                say("settings wifi connected ")
                say(s.net_names[n * 24usize..n * 24usize + s.net_len[n]])
                say("\n")
                scan_networks(s)
                s.page = 0usize
            } else if result == netproto.R_AUTH {
                s.join_note = 1usize
                say("settings wifi wrong password\n")
            } else {
                s.join_note = 2usize
                say("settings wifi join failed\n")
            }
            ret true
        }
        if ui.is_key(id) && ui.field_key(&s.pass, id, false) {
            s.join_note = 0usize
            say("settings wifi password ")
            say_num(s.pass.len)
            say(" chars\n")
            ret true
        }
        ret false
    }
    if s.page == SEARCH {
        var open = NONE
        if id >= 6000usize && id < 6000usize + s.found_total { open = id - 6000usize }
        if id == 1205usize && s.found_total > 0usize { open = 0usize }
        if open != NONE {
            let setting = s.found[open]
            s.page = setting_page(setting)
            s.scroll = 0.0
            say("settings found ")
            say(setting_label(setting))
            say("\n")
            ret true
        }
        if id == 500usize {
            s.page = MAIN
            say("settings back\n")
            ret true
        }
        if ui.is_key(id) && ui.field_key(&s.search, id, false) {
            find_settings(s)
            say("settings search ")
            say(s.search.bytes[0usize..s.search.len])
            say(" ")
            say_num(s.found_total)
            say("\n")
            ret true
        }
        ret false
    }
    if s.page == MAIN && id == 600usize {
        s.page = SEARCH
        s.search.len = 0usize
        s.found_total = 0usize
        say("settings search\n")
        ret true
    }
    if s.page == MAIN {
        if id >= 100usize && id < 100usize + PAGES {
            s.page = id - 100usize
            s.scroll = 0.0
            say("settings page ")
            say(page_name(s.page))
            say("\n")
            if s.page == 0usize && s.values[WIFI] != 0usize { scan_networks(s) }
            if s.page == 6usize {
                s.hidden = sysettings.hidden()
                load_dynamic(s)
                var d = 0usize
                while d < s.dyn_total {
                    say("settings dynamic ")
                    say(s.dyn_names[d * 24usize..d * 24usize + s.dyn_len[d]])
                    say(" v")
                    say_num(s.dyn_version[d])
                    say("\n")
                    d += 1usize
                }
            }
            if s.page == 3usize {
                s.battery = sysettings.battery()
                if (s.battery & 2147483648usize) != 0usize {
                    say("settings battery ")
                    say_num(s.battery & 255usize)
                    say("\n")
                } else {
                    say("settings battery unavailable\n")
                }
            }
            if s.page == 4usize {
                let (used, total, answered) = vaultfs.stats()
                s.have_storage = answered
                s.storage_used = used
                s.storage_total = total
                if answered {
                    say("settings storage used ")
                    say_num(used)
                    say(" of ")
                    say_num(total)
                    say(" blocks\n")
                } else {
                    say("settings storage none\n")
                }
            }
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
        if setting == TIMEZONE { say(zone_name(s.values[setting])) }
        say("\n")
        ret true
    }
    if id >= 4000usize && id < 4008usize && id - 4000usize < s.net_total {
        let n = id - 4000usize
        if (s.net_flags[n] & 1usize) != 0usize { ret false }
        if s.net_secured[n] != 0usize {
            s.sheet = n
            s.pass.len = 0usize
            s.join_note = 0usize
            s.page = SHEET
            say("settings wifi password sheet ")
            say(s.net_names[n * 24usize..n * 24usize + s.net_len[n]])
            say("\n")
            ret true
        }
        s.pass.len = 0usize
        let result = join_network(s, n)
        if result == netproto.R_OK {
            say("settings wifi connected ")
            say(s.net_names[n * 24usize..n * 24usize + s.net_len[n]])
            say("\n")
        } else {
            say("settings wifi join failed\n")
        }
        scan_networks(s)
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
    // The Settings app's last argument is the archive entries' sizes (a 32-bit word each) when the kernel gave it.
    if args.len >= 8usize && args[7usize].len == 128usize {
        var entry = 0usize
        while entry < 32usize {
            let b = args[7usize]
            s.app_sizes[entry] = usize(b[entry * 4usize]) + usize(b[entry * 4usize + 1usize]) * 256usize + usize(b[entry * 4usize + 2usize]) * 65536usize + usize(b[entry * 4usize + 3usize]) * 16777216usize
            entry += 1usize
        }
    }
    // (C126) The settings server, when this process was granted it, holds the values; else the file is read here.
    var served = false
    if sysettings.word() != 0usize {
        served = true
        var index = 0usize
        while index < 40usize {
            let (value, answered) = sysettings.get(index)
            s.values[index] = value
            s.mirror[index] = value
            index += 1usize
        }
        dark_theme = s.values[DARK] != 0usize
    }
    if served || load(&s) {
        say("settings loaded dark ")
        say_num(s.values[DARK])
        say(" brightness ")
        say_num(s.values[BRIGHTNESS] * 10usize)
        say("\n")
    } else {
        // No stored values: show the theme the shell handed this app.
        if theme.is_dark() { s.values[DARK] = 1usize } else { s.values[DARK] = 0usize }
        if theme.high_contrast() { s.values[CONTRAST] = 1usize } else { s.values[CONTRAST] = 0usize }
        s.values[FONT] = theme.word & 3usize
        if theme.is_24h() { s.values[HOUR24] = 1usize } else { s.values[HOUR24] = 0usize }
        s.values[BRIGHTNESS] = theme.brightness_step()
        s.values[LOCK] = theme.screen_lock()
        if theme.do_not_disturb() { s.values[DND] = 1usize } else { s.values[DND] = 0usize }
        dark_theme = s.values[DARK] != 0usize
    }
    sync_theme(&s)
    s.page = MAIN
    s.hidden = sysettings.hidden()
    s.battery = sysettings.battery()
    load_dynamic(&s)
    if s.values[WIFI] != 0usize { scan_networks(&s) }
    let (stored_used, stored_total, stored_answered) = vaultfs.stats()
    s.have_storage = stored_answered
    s.storage_used = stored_used
    s.storage_total = stored_total
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
            var id = NONE
            if s.page == SEARCH || s.page == SHEET { id = ui.hit_at(&s.keys, tap.x, tap.y) }
            if id == NONE { id = hit_at(&s, tap.x, tap.y) }
            if id != NONE && act(&s, id, tap.x) {
                sync_theme(&s)
                if id >= 1000usize && id < 6000usize && s.page != SEARCH && s.page != SHEET {
                    if served {
                        var changed = false
                        var index = 0usize
                        while index < 40usize {
                            if s.values[index] != s.mirror[index] {
                                let word = sysettings.set(index, s.values[index])
                                s.mirror[index] = s.values[index]
                                changed = true
                            }
                            index += 1usize
                        }
                        if changed { say("settings saved\n") }
                    } else {
                        save(&s)
                    }
                }
                if !show(a, &kit, &s) {
                    say("settings present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    // The exit code is the system theme word (shell.e keeps it for the apps it launches).
    os.exit(i32(theme.word))
    ret ok
}
