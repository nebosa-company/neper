// Clock (D2207): the app behind the Clock icon, with the parts of Android's Clock: Alarm, Clock (the
// world clock), Timer, Stopwatch and Bedtime, on the same cream cards as Calc (appkit.e, taps from
// the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
//
// The input server sends a tick every 500 ms in the unified boot, so a running stopwatch or timer, the
// seconds of the world clock and a ringing alarm update without a thread of the app's own.
//   Alarm      up to five alarms: a time, the days it repeats, an on/off switch; tap a time to edit it
//              (steppers, days, Save, Delete); a ringing alarm shows Snooze (5 min) and Dismiss.
//   Clock      the time in UTC, the date, and up to six cities with their standard-time offsets.
//   Timer      type hours, minutes and seconds (or a preset), Start, Pause, Reset, +1:00.
//   Stopwatch  Start, Stop, Lap, Reset, with a list of laps.
//   Bedtime    the wake-up time and the hours of sleep wanted give the time to go to bed.
// ponytail: the machine has one clock and no time zone setting, so "local" time is UTC and the cities
// are fixed offsets without daylight saving; the alarms live in this process (no storage and no
// background ringer yet), so one rings only while the app is open.
use e.mem
use e.os
use e.math
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text
use lunar

const ALARM_TAB: usize = 0usize
const CLOCK_TAB: usize = 1usize
const TIMER_TAB: usize = 2usize
const STOPWATCH_TAB: usize = 3usize
const BEDTIME_TAB: usize = 4usize
const NONE: usize = 99usize
const MAX_HITS: usize = 96usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

// Print a string that lives in the arena (the console call reads the program's own window only).
fn say_text(value: str) {
    var buffer: [48]u8 = zero
    var n = 0usize
    while n < value.len && n < 48usize {
        buffer[n] = value[n]
        n += 1usize
    }
    say(buffer[0usize..n])
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

fn two(a: *mem.Arena, value: usize) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, 2usize)
    if buffer_error != ok { ret "00" }
    buffer[0usize] = u8(value / 10usize % 10usize) + 48u8
    buffer[1usize] = u8(value % 10usize) + 48u8
    ret buffer[0usize..2usize]
}

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

// "HH:MM" of a count of minutes into the day.
fn hhmm(a: *mem.Arena, minutes: usize) -> str {
    ret join(a, two(a, minutes / 60usize % 24usize), ":", two(a, minutes % 60usize))
}

fn weekday_name(day: usize) -> str {
    if day == 0usize { ret "Monday" }
    if day == 1usize { ret "Tuesday" }
    if day == 2usize { ret "Wednesday" }
    if day == 3usize { ret "Thursday" }
    if day == 4usize { ret "Friday" }
    if day == 5usize { ret "Saturday" }
    ret "Sunday"
}

fn day_letter(day: usize) -> str {
    if day == 0usize { ret "M" }
    if day == 1usize { ret "T" }
    if day == 2usize { ret "W" }
    if day == 3usize { ret "T" }
    if day == 4usize { ret "F" }
    if day == 5usize { ret "S" }
    ret "S"
}

// ----------------------------------------------------------------------------------------------
// The cities of the world clock: standard-time offsets from UTC, in minutes.

fn city_count() -> usize {
    ret 16usize
}

fn city_name(city: usize) -> str {
    if city == 0usize { ret "UTC" }
    if city == 1usize { ret "London" }
    if city == 2usize { ret "Paris" }
    if city == 3usize { ret "Cairo" }
    if city == 4usize { ret "Moscow" }
    if city == 5usize { ret "Dubai" }
    if city == 6usize { ret "Mumbai" }
    if city == 7usize { ret "Singapore" }
    if city == 8usize { ret "Tokyo" }
    if city == 9usize { ret "Sydney" }
    if city == 10usize { ret "Auckland" }
    if city == 11usize { ret "Honolulu" }
    if city == 12usize { ret "Los Angeles" }
    if city == 13usize { ret "Chicago" }
    if city == 14usize { ret "New York" }
    ret "Sao Paulo"
}

fn city_offset(city: usize) -> i64 {
    if city == 0usize { ret 0i64 }
    if city == 1usize { ret 0i64 }
    if city == 2usize { ret 60i64 }
    if city == 3usize { ret 120i64 }
    if city == 4usize { ret 180i64 }
    if city == 5usize { ret 240i64 }
    if city == 6usize { ret 330i64 }
    if city == 7usize { ret 480i64 }
    if city == 8usize { ret 540i64 }
    if city == 9usize { ret 600i64 }
    if city == 10usize { ret 720i64 }
    if city == 11usize { ret 0i64 - 600i64 }
    if city == 12usize { ret 0i64 - 480i64 }
    if city == 13usize { ret 0i64 - 360i64 }
    if city == 14usize { ret 0i64 - 300i64 }
    ret 0i64 - 180i64
}

// ----------------------------------------------------------------------------------------------
// State.

type Alarm = struct { minutes: usize, on: bool, days: usize }
type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    tab: usize,
    // The clock.
    wall0: i64,
    mono0: i64,
    now_ms: i64,
    cities: [6]usize,
    city_total: usize,
    picker: bool,
    // The alarms.
    alarms: [5]Alarm,
    alarm_total: usize,
    editing: usize,
    edit: Alarm,
    ringing: usize,
    fired: usize,
    // The timer.
    timer_digits: [6]u8,
    timer_typed: usize,
    timer_total_ms: i64,
    timer_end_ms: i64,
    timer_left_ms: i64,
    timer_running: bool,
    timer_paused: bool,
    timer_done: bool,
    // The stopwatch.
    sw_running: bool,
    sw_start_ms: i64,
    sw_acc_ms: i64,
    laps: [8]i64,
    lap_total: usize,
    // Bedtime.
    wake_minutes: usize,
    sleep_half_hours: usize,
    bedtime_on: bool,
    // What the last frame showed, to redraw only when the display changed.
    shown: i64,
    hits: [96]Hit,
    hit_total: usize,
}

// The time now in UTC seconds, from the wall clock read at start and the monotonic clock since.
fn utc_seconds(s: *State) -> usize {
    let value = s.wall0 + (s.now_ms - s.mono0) / 1000i64
    if value < 0i64 { ret 0usize }
    ret usize(value)
}

fn refresh(s: *State) {
    let (now, now_error) = time.monotonic()
    if now_error == ok { s.now_ms = now.nanos / 1000000i64 }
}

fn minutes_of_day(seconds: usize) -> usize {
    ret seconds % 86400usize / 60usize
}

// Monday = 0.
fn weekday_of(seconds: usize) -> usize {
    ret (seconds / 86400usize + 3usize) % 7usize
}

fn timer_value_ms(s: *State) -> i64 {
    var digits = 0usize
    var n = 0usize
    while n < s.timer_typed {
        digits = digits * 10usize + usize(s.timer_digits[n] - 48u8)
        n += 1usize
    }
    let seconds = digits % 100usize
    let minutes = digits / 100usize % 100usize
    let hours = digits / 10000usize
    ret (i64(hours) * 3600i64 + i64(minutes) * 60i64 + i64(seconds)) * 1000i64
}

fn stopwatch_ms(s: *State) -> i64 {
    if s.sw_running { ret s.sw_acc_ms + (s.now_ms - s.sw_start_ms) }
    ret s.sw_acc_ms
}

fn timer_remaining_ms(s: *State) -> i64 {
    if s.timer_running { ret s.timer_end_ms - s.now_ms }
    ret s.timer_left_ms
}

// A number that changes exactly when something on the shown tab does, so a tick that would redraw
// the same frame answers "nothing to show" instead.
fn display_key(s: *State) -> i64 {
    var key = i64(s.tab) * 1000000000000i64 + i64(s.ringing) * 100000000000i64
    if s.tab == CLOCK_TAB { key = key + i64(utc_seconds(s)) }
    if s.tab == BEDTIME_TAB { key = key + i64(utc_seconds(s) / 60usize) }
    if s.tab == STOPWATCH_TAB { key = key + stopwatch_ms(s) / 100i64 }
    if s.tab == TIMER_TAB { key = key + (timer_remaining_ms(s) + 999i64) / 1000i64 }
    ret key
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn cream(alpha: f32) -> paint.Color {
    ret paint.Color { red: 0.92, green: 0.90, blue: 0.86, alpha: alpha }
}

fn white() -> paint.Color {
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

fn grey() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

// A hit rectangle for the tap handler, registered as the thing is drawn.
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

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

fn right(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, edge: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, edge - text.measure(a, font, size, line), y, c)
}

// A button: the cap, its label centred, and its hit rectangle.
fn button(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink())
    hit(s, id, x, y, w, h)
    ret ok
}

// A square key (the timer's keypad).
fn pad_key(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color) -> err {
    try card(a, builder, x, y + 3.0, w, h, 12.0, paint.Color { red: 0.25, green: 0.24, blue: 0.22, alpha: 0.28 })
    try card(a, builder, x, y, w, h, 12.0, fill)
    try centred(a, builder, faces.grotesk, 24.0, label, x + w / 2.0, y + h / 2.0 - 15.0, ink())
    hit(s, id, x, y, w, h)
    ret ok
}

fn tab_name(tab: usize) -> str {
    if tab == 0usize { ret "Alarm" }
    if tab == 1usize { ret "Clock" }
    if tab == 2usize { ret "Timer" }
    if tab == 3usize { ret "Stopwatch" }
    ret "Bedtime"
}

fn chrome(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    let faces = kit.faces
    // The backdrop alternates its alpha by 0.2% a frame (invisible): the renderer's incremental redraw
    // left changed text without the cards under it, so each frame must differ in its first command.
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    try card(a, builder, 20.0, 40.0, 372.0, 56.0, 14.0, cream(0.96))
    try put(a, builder, faces.sora, 22.0, "CLOCK", 36.0, 53.0, ink())
    try card(a, builder, 20.0, 108.0, 372.0, 730.0, 16.0, cream(0.92))
    var tab = 0usize
    while tab < 5usize {
        let x = 36.0 + f32(tab) * 69.5
        var fill = grey()
        var c = muted()
        if tab == s.tab {
            fill = ink()
            c = paint.Color { red: 0.95, green: 0.94, blue: 0.92, alpha: 1.0 }
        }
        try card(a, builder, x, 122.0, 62.0, 32.0, 16.0, fill)
        try centred(a, builder, faces.jost, 12.0, tab_name(tab), x + 31.0, 130.0, c)
        hit(s, 100usize + tab, x, 122.0, 62.0, 32.0)
        tab += 1usize
    }
    try card(a, builder, 156.0, 876.0, 100.0, 6.0, 3.0, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
    ret ok
}

// ---- the light screens (D2209): Android's look for every tab -- a light ground, white rounded rows, a
// blue accent, round buttons, and the bottom navigation bar (draw_nav, with the stopwatch's helpers).

fn panel() -> paint.Color {
    ret paint.Color { red: 0.97, green: 0.96, blue: 0.94, alpha: 1.0 }
}

fn soft() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

fn gray_text() -> paint.Color {
    ret paint.Color { red: 0.36, green: 0.35, blue: 0.34, alpha: 1.0 }
}

// Text on the dark ground, and a quieter tone of it.
fn light() -> paint.Color {
    ret paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 }
}

fn light_muted() -> paint.Color {
    ret paint.Color { red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0 }
}

// The amber of Calc, darker where it is text or a thin line on the cream.
fn accent_dark() -> paint.Color {
    ret paint.Color { red: 0.78, green: 0.52, blue: 0.12, alpha: 1.0 }
}

fn accent_c() -> paint.Color {
    ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
}

fn title(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, line: str) -> err {
    ret put(a, builder, faces.jost_bold, 34.0, line, 24.0, 40.0, light())
}

// A round button with a label in its middle.
fn round_button(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, cx: f32, cy: f32, radius: f32, label: str, fill: paint.Color, ink_color: paint.Color, size: f32) -> err {
    try disc(a, builder, cx, cy, radius, fill)
    try centred(a, builder, faces.jost, size, label, cx, cy - size * 0.62, ink_color)
    hit(s, id, cx - radius, cy - radius, radius * 2.0, radius * 2.0)
    ret ok
}

// A wide pill button.
fn pill(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, ink_color: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink_color)
    hit(s, id, x, y, w, h)
    ret ok
}

// The blue round button: a plus, a play triangle, or pause bars.
fn fab(a: *mem.Arena, builder: *scene.Builder, s: *State, id: usize, cx: f32, cy: f32, radius: f32, kind: usize) -> err {
    try disc(a, builder, cx, cy, radius, accent_c())
    if kind == 0usize {
        try card(a, builder, cx - 11.0, cy - 2.0, 22.0, 4.0, 2.0, ink())
        try card(a, builder, cx - 2.0, cy - 11.0, 4.0, 22.0, 2.0, ink())
    } else if kind == 1usize {
        let (play_builder, play_error) = geometry.path_builder(a, 4usize, 3usize)
        if play_error != ok { ret play_error }
        var play = play_builder
        try geometry.move_to(&play, geometry.Point { x: cx - 8.0, y: cy - 14.0 })
        try geometry.line_to(&play, geometry.Point { x: cx + 13.0, y: cy })
        try geometry.line_to(&play, geometry.Point { x: cx - 8.0, y: cy + 14.0 })
        try geometry.close_path(&play)
        try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&play), brush: paint.Brush { Solid: ink() } } })
    } else {
        try card(a, builder, cx - 10.0, cy - 12.0, 7.0, 24.0, 2.0, ink())
        try card(a, builder, cx + 3.0, cy - 12.0, 7.0, 24.0, 2.0, ink())
    }
    hit(s, id, cx - radius, cy - radius, radius * 2.0, radius * 2.0)
    ret ok
}

// An on/off switch, blue when on.
fn toggle_switch(a: *mem.Arena, builder: *scene.Builder, s: *State, id: usize, x: f32, y: f32, on: bool) -> err {
    var track = paint.Color { red: 0.78, green: 0.79, blue: 0.83, alpha: 1.0 }
    if on { track = accent_c() }
    try card(a, builder, x, y, 56.0, 32.0, 16.0, track)
    var knob_x = x + 4.0
    if on { knob_x = x + 28.0 }
    try card(a, builder, knob_x, y + 4.0, 24.0, 24.0, 12.0, white())
    hit(s, id, x - 8.0, y - 8.0, 72.0, 48.0)
    ret ok
}

// ---- the clock tab

fn draw_clock(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, s: *State) -> err {
    let now = utc_seconds(s)
    if s.picker {
        try title(a, builder, faces, "Choose cities")
        var city = 0usize
        while city < city_count() {
            let x = 16.0 + f32(city % 2usize) * 194.0
            let y = 100.0 + f32(city / 2usize) * 60.0
            var chosen = false
            var i = 0usize
            while i < s.city_total {
                if s.cities[i] == city { chosen = true }
                i += 1usize
            }
            var fill = panel()
            var label_color = ink()
            if chosen {
                fill = accent_c()
                label_color = ink()
            }
            try card(a, builder, x, y, 186.0, 50.0, 25.0, fill)
            try centred(a, builder, faces.jost, 17.0, city_name(city), x + 93.0, y + 14.0, label_color)
            hit(s, 220usize + city, x, y, 186.0, 50.0)
            city += 1usize
        }
        try pill(a, builder, s, faces, 230usize, 56.0, 700.0, 300.0, 56.0, "Done", accent_c(), ink(), 18.0)
        ret ok
    }
    // The time and the date.
    let day = now / 86400usize
    let (month, date) = lunar.month_day(now)
    try centred(a, builder, faces.jost_bold, 68.0, hhmm(a, minutes_of_day(now)), 206.0, 46.0, light())
    try centred(a, builder, faces.grotesk, 15.0, join(a, ":", two(a, now % 60usize), " UTC"), 206.0, 132.0, light_muted())
    try centred(a, builder, faces.jost, 19.0, join(a, weekday_name(weekday_of(now)), ", ", join(a, lunar.month_name(month), " ", number(a, date))), 206.0, 156.0, light())
    // The cities.
    var row = 0usize
    while row < s.city_total {
        let city = s.cities[row]
        let y = 202.0 + f32(row) * 74.0
        try card(a, builder, 16.0, y, 380.0, 66.0, 20.0, panel())
        try put(a, builder, faces.jost, 20.0, city_name(city), 32.0, y + 9.0, ink())
        // The offset from UTC, and whether it is another day there.
        let local = i64(now) + city_offset(city) * 60i64
        var relative = "Today"
        let local_day = (local + 864000000i64) / 86400i64 - 10000i64
        let utc_day = i64(day)
        if local_day > utc_day { relative = "Tomorrow" }
        if local_day < utc_day { relative = "Yesterday" }
        let offset = city_offset(city)
        var sign = "+"
        var shown_offset = offset
        if offset < 0i64 {
            sign = "-"
            shown_offset = 0i64 - offset
        }
        let detail = join(a, relative, ", ", join(a, sign, number(a, usize(shown_offset / 60i64)), join(a, "h", two(a, usize(shown_offset % 60i64)), "")))
        try put(a, builder, faces.grotesk, 12.0, detail, 32.0, y + 38.0, gray_text())
        try right(a, builder, faces.jost, 30.0, hhmm(a, usize(local / 60i64 % 1440i64)), 380.0, y + 14.0, ink())
        row += 1usize
    }
    try fab(a, builder, s, 210usize, 206.0, 764.0, 30.0, 0usize)
    ret ok
}

// ---- the alarm tab

fn days_text(days: usize) -> str {
    if days == 127usize { ret "Every day" }
    if days == 31usize { ret "Weekdays" }
    if days == 96usize { ret "Weekends" }
    if days == 0usize { ret "Once" }
    ret "Custom days"
}

fn draw_alarm(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, s: *State) -> err {
    if s.ringing != NONE {
        let alarm = s.alarms[s.ringing]
        try card(a, builder, 16.0, 120.0, 380.0, 560.0, 32.0, panel())
        try centred(a, builder, faces.jost, 22.0, "Alarm", 206.0, 170.0, gray_text())
        try centred(a, builder, faces.jost_bold, 92.0, hhmm(a, alarm.minutes), 206.0, 230.0, ink())
        try centred(a, builder, faces.exo, 17.0, days_text(alarm.days), 206.0, 366.0, gray_text())
        try pill(a, builder, s, faces, 350usize, 56.0, 470.0, 300.0, 60.0, "Snooze 5 min", soft(), ink(), 20.0)
        try pill(a, builder, s, faces, 351usize, 56.0, 548.0, 300.0, 60.0, "Dismiss", accent_c(), ink(), 20.0)
        ret ok
    }
    if s.editing != NONE {
        try title(a, builder, faces, "Edit alarm")
        try card(a, builder, 16.0, 96.0, 380.0, 640.0, 32.0, panel())
        try centred(a, builder, faces.jost_bold, 72.0, hhmm(a, s.edit.minutes), 206.0, 118.0, ink())
        // Hour and minute steppers.
        try round_button(a, builder, s, faces, 330usize, 70.0, 258.0, 30.0, "-", soft(), ink(), 28.0)
        try centred(a, builder, faces.grotesk, 14.0, "hour", 206.0, 249.0, gray_text())
        try round_button(a, builder, s, faces, 331usize, 342.0, 258.0, 30.0, "+", soft(), ink(), 28.0)
        try round_button(a, builder, s, faces, 332usize, 70.0, 344.0, 30.0, "-", soft(), ink(), 28.0)
        try centred(a, builder, faces.grotesk, 14.0, "minute", 206.0, 335.0, gray_text())
        try round_button(a, builder, s, faces, 333usize, 342.0, 344.0, 30.0, "+", soft(), ink(), 28.0)
        // The days.
        try put(a, builder, faces.exo, 14.0, "Repeat", 40.0, 420.0, gray_text())
        var day = 0usize
        while day < 7usize {
            let cx = 54.0 + f32(day) * 50.0
            var fill = soft()
            var letter_color = ink()
            if (s.edit.days >> day) & 1usize == 1usize {
                fill = accent_c()
                letter_color = ink()
            }
            try disc(a, builder, cx, 474.0, 20.0, fill)
            try centred(a, builder, faces.jost, 16.0, day_letter(day), cx, 464.0, letter_color)
            hit(s, 334usize + day, cx - 20.0, 454.0, 40.0, 40.0)
            day += 1usize
        }
        try pill(a, builder, s, faces, 341usize, 40.0, 540.0, 150.0, 54.0, "Save", accent_c(), ink(), 18.0)
        try pill(a, builder, s, faces, 342usize, 222.0, 540.0, 150.0, 54.0, "Delete", soft(), ink(), 18.0)
        try pill(a, builder, s, faces, 343usize, 40.0, 612.0, 332.0, 50.0, "Cancel", soft(), ink(), 16.0)
        ret ok
    }
    try title(a, builder, faces, "Alarm")
    var i = 0usize
    while i < s.alarm_total {
        let alarm = s.alarms[i]
        let y = 100.0 + f32(i) * 108.0
        try card(a, builder, 16.0, y, 380.0, 98.0, 24.0, panel())
        try put(a, builder, faces.jost, 46.0, hhmm(a, alarm.minutes), 32.0, y + 12.0, ink())
        hit(s, 310usize + i, 16.0, y, 270.0, 98.0)
        try put(a, builder, faces.exo, 14.0, days_text(alarm.days), 34.0, y + 68.0, gray_text())
        try toggle_switch(a, builder, s, 300usize + i, 324.0, y + 33.0, alarm.on)
        i += 1usize
    }
    if s.alarm_total < 5usize { try fab(a, builder, s, 320usize, 206.0, 764.0, 30.0, 0usize) }
    ret ok
}

// ---- the timer tab

fn timer_text(a: *mem.Arena, ms: i64) -> str {
    var left = ms
    if left < 0i64 { left = 0i64 }
    let total = usize((left + 999i64) / 1000i64)
    if total >= 3600usize {
        ret join(a, two(a, total / 3600usize), ":", join(a, two(a, total / 60usize % 60usize), ":", two(a, total % 60usize)))
    }
    ret join(a, two(a, total / 60usize), ":", two(a, total % 60usize))
}

// The typed digits as HH:MM:SS (right-aligned, like Android's timer).
fn typed_text(a: *mem.Arena, s: *State) -> str {
    var padded: [6]u8 = zero
    var i = 0usize
    while i < 6usize {
        padded[i] = 48u8
        i += 1usize
    }
    var n = 0usize
    while n < s.timer_typed {
        padded[6usize - s.timer_typed + n] = s.timer_digits[n]
        n += 1usize
    }
    let (buffer, buffer_error) = mem.alloc[u8](a, 8usize)
    if buffer_error != ok { ret "00:00:00" }
    buffer[0usize] = padded[0usize]
    buffer[1usize] = padded[1usize]
    buffer[2usize] = 58u8
    buffer[3usize] = padded[2usize]
    buffer[4usize] = padded[3usize]
    buffer[5usize] = 58u8
    buffer[6usize] = padded[4usize]
    buffer[7usize] = padded[5usize]
    ret buffer[0usize..8usize]
}

// A numeric key of the timer.
fn timer_key(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, label: str, fill: paint.Color) -> err {
    try card(a, builder, x, y, 116.0, 72.0, 26.0, fill)
    try centred(a, builder, faces.grotesk, 28.0, label, x + 58.0, y + 36.0 - 17.0, ink())
    hit(s, id, x, y, 116.0, 72.0)
    ret ok
}

fn draw_timer(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, s: *State) -> err {
    if s.timer_done {
        try centred(a, builder, faces.jost_bold, 33.0, "Time's up", 206.0, 160.0, light())
        try centred(a, builder, faces.jost_bold, 84.0, timer_text(a, s.timer_total_ms), 206.0, 230.0, accent_c())
        try pill(a, builder, s, faces, 414usize, 56.0, 470.0, 300.0, 60.0, "Dismiss", accent_c(), ink(), 20.0)
        ret ok
    }
    if s.timer_running || s.timer_paused {
        let left = timer_remaining_ms(s)
        // The ring: what is left of the time, clockwise from the top.
        try disc(a, builder, 206.0, 280.0, 138.0, paint.Color { red: 0.30, green: 0.30, blue: 0.32, alpha: 0.6 })
        try disc(a, builder, 206.0, 280.0, 126.0, panel())
        var fraction = 0.0f32
        if s.timer_total_ms > 0i64 { fraction = f32(left) / f32(s.timer_total_ms) }
        if fraction < 0.0 { fraction = 0.0 }
        if fraction > 1.0 { fraction = 1.0 }
        let (arc_builder, arc_error) = geometry.path_builder(a, 80usize, 80usize)
        if arc_error != ok { ret arc_error }
        var arc = arc_builder
        var step = 0usize
        let steps = 72usize
        while step <= steps {
            let t = fraction * f32(step) / f32(steps)
            if step == 0usize {
                try geometry.move_to(&arc, on_dial(206.0, 280.0, 126.0, t))
            } else {
                try geometry.line_to(&arc, on_dial(206.0, 280.0, 126.0, t))
            }
            step += 1usize
        }
        if fraction > 0.004 {
            try scene.push(builder, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&arc), brush: paint.Brush { Solid: accent_c() }, stroke: paint.Stroke { width: 9.0, cap: paint.StrokeCap.Round, join: paint.StrokeJoin.Round, miter_limit: 4.0 } } })
        }
        try centred(a, builder, faces.jost_bold, 56.0, timer_text(a, left), 206.0, 250.0, ink())
        try round_button(a, builder, s, faces, 412usize, 90.0, 520.0, 30.0, "Reset", soft(), ink(), 13.0)
        var kind = 2usize
        if s.timer_paused { kind = 1usize }
        try fab(a, builder, s, 411usize, 206.0, 520.0, 38.0, kind)
        try round_button(a, builder, s, faces, 413usize, 322.0, 520.0, 30.0, "+1:00", soft(), ink(), 13.0)
        ret ok
    }
    try centred(a, builder, faces.jost_bold, 58.0, typed_text(a, s), 206.0, 50.0, light())
    var preset = 0usize
    while preset < 4usize {
        var label = "1:00"
        if preset == 1usize { label = "5:00" }
        if preset == 2usize { label = "10:00" }
        if preset == 3usize { label = "15:00" }
        try pill(a, builder, s, faces, 420usize + preset, 20.0 + f32(preset) * 94.0, 138.0, 86.0, 38.0, label, soft(), ink(), 15.0)
        preset += 1usize
    }
    var k = 0usize
    while k < 9usize {
        try timer_key(a, builder, s, faces, 401usize + k, 20.0 + f32(k % 3usize) * 128.0, 200.0 + f32(k / 3usize) * 84.0, number(a, k + 1usize), panel())
        k += 1usize
    }
    try timer_key(a, builder, s, faces, 400usize, 148.0, 452.0, "0", panel())
    try timer_key(a, builder, s, faces, 410usize, 276.0, 452.0, "DEL", soft())
    try fab(a, builder, s, 411usize, 206.0, 650.0, 40.0, 1usize)
    ret ok
}

// ---- the stopwatch tab: an analogue dial (after Android's), the digital time over it, a seconds hand,
// a thirty-minute sub-dial, a round play button, and a navigation bar at the bottom.

// "MM:SS.t" of a count of milliseconds (the lap list).
fn stopwatch_text(a: *mem.Arena, ms: i64) -> str {
    let total_tenths = usize(ms / 100i64)
    let tenths = total_tenths % 10usize
    let seconds = total_tenths / 10usize % 60usize
    let minutes = total_tenths / 600usize
    ret join(a, two(a, minutes), ":", join(a, two(a, seconds), ".", number(a, tenths)))
}

// The point at `radius` from (cx, cy) at `turns` of a full turn clockwise from straight up.
fn on_dial(cx: f32, cy: f32, radius: f32, turns: f32) -> geometry.Point {
    let angle = turns * 6.2831855
    ret geometry.Point { x: cx + radius * math.sin[f32](angle), y: cy - radius * math.cos[f32](angle) }
}

// A ring of ticks around a dial: `count` of them from `outer` to `inner`, every `every`th one long
// (to `long_inner`) when `every` is not zero.
fn ticks(a: *mem.Arena, builder: *scene.Builder, cx: f32, cy: f32, outer: f32, inner: f32, long_inner: f32, count: usize, every: usize, width: f32, long_width: f32, c: paint.Color) -> err {
    let (minor_builder, minor_error) = geometry.path_builder(a, count * 2usize + 2usize, count * 2usize + 2usize)
    if minor_error != ok { ret minor_error }
    var minor = minor_builder
    let (major_builder, major_error) = geometry.path_builder(a, count * 2usize + 2usize, count * 2usize + 2usize)
    if major_error != ok { ret major_error }
    var major = major_builder
    var i = 0usize
    while i < count {
        let turns = f32(i) / f32(count)
        if every != 0usize && i % every == 0usize {
            try geometry.move_to(&major, on_dial(cx, cy, outer, turns))
            try geometry.line_to(&major, on_dial(cx, cy, long_inner, turns))
        } else {
            try geometry.move_to(&minor, on_dial(cx, cy, outer, turns))
            try geometry.line_to(&minor, on_dial(cx, cy, inner, turns))
        }
        i += 1usize
    }
    try scene.push(builder, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&minor), brush: paint.Brush { Solid: c }, stroke: paint.Stroke { width: width, cap: paint.StrokeCap.Round, join: paint.StrokeJoin.Round, miter_limit: 4.0 } } })
    try scene.push(builder, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&major), brush: paint.Brush { Solid: c }, stroke: paint.Stroke { width: long_width, cap: paint.StrokeCap.Round, join: paint.StrokeJoin.Round, miter_limit: 4.0 } } })
    ret ok
}

fn hand(a: *mem.Arena, builder: *scene.Builder, from: geometry.Point, to: geometry.Point, width: f32, c: paint.Color) -> err {
    let (path_builder, path_error) = geometry.path_builder(a, 2usize, 2usize)
    if path_error != ok { ret path_error }
    var line = path_builder
    try geometry.move_to(&line, from)
    try geometry.line_to(&line, to)
    try scene.push(builder, scene.Command { StrokePath: scene.StrokePath { path: geometry.finish(&line), brush: paint.Brush { Solid: c }, stroke: paint.Stroke { width: width, cap: paint.StrokeCap.Round, join: paint.StrokeJoin.Round, miter_limit: 4.0 } } })
    ret ok
}

fn disc(a: *mem.Arena, builder: *scene.Builder, cx: f32, cy: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.ellipse_path(a, cx, cy, radius, radius)
    if path_error != ok { ret path_error }
    try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: path, brush: paint.Brush { Solid: c } } })
    ret ok
}

// The navigation icons (24 x 24, drawn in the colour given): alarm clock, globe, stopwatch, hourglass,
// moon.
fn nav_icon(tab: usize) -> str {
    if tab == 0usize { ret "<svg viewBox='0 0 24 24'><g fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><circle cx='12' cy='13.5' r='7.5'/><path d='M12 9.5v4.2l2.6 1.8M3.6 6.2 7 3.4M20.4 6.2 17 3.4'/></g></svg>" }
    if tab == 1usize { ret "<svg viewBox='0 0 24 24'><g fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'><circle cx='12' cy='12' r='9'/><ellipse cx='12' cy='12' rx='4' ry='9'/><path d='M3.4 9.4h17.2M3.4 14.6h17.2'/></g></svg>" }
    if tab == 2usize { ret "<svg viewBox='0 0 24 24'><g fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'><path d='M6.5 3h11M6.5 21h11M7.5 3c0 4.6 3 6 4.5 9-1.5 3-4.5 4.4-4.5 9M16.5 3c0 4.6-3 6-4.5 9 1.5 3 4.5 4.4 4.5 9'/></g></svg>" }
    if tab == 3usize { ret "<svg viewBox='0 0 24 24'><g fill='none' stroke='currentColor' stroke-width='2' stroke-linecap='round'><circle cx='12' cy='14' r='7.6'/><path d='M9.5 2.6h5M12 2.6v3.8M12 14l3-3'/></g></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M15.5 3a9.2 9.2 0 1 0 5.5 13.6A7.4 7.4 0 0 1 15.5 3z' fill='none' stroke='currentColor' stroke-width='2' stroke-linejoin='round'/></svg>"
}

fn nav_name(tab: usize) -> str {
    if tab == 0usize { ret "Alarm" }
    if tab == 1usize { ret "World clock" }
    if tab == 2usize { ret "Timer" }
    if tab == 3usize { ret "Stopwatch" }
    ret "Bedtime"
}

// The bottom navigation of the light screens: an icon and a name for each tab.
fn draw_nav(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, s: *State) -> err {
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 826.0, 412.0, 93.0), brush: paint.Brush { Solid: paint.Color { red: 0.92, green: 0.90, blue: 0.86, alpha: 1.0 } } } })
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 826.0, 412.0, 0.6), brush: paint.Brush { Solid: paint.Color { red: 0.78, green: 0.77, blue: 0.74, alpha: 1.0 } } } })
    var slot = 0usize
    while slot < 5usize {
        // Android's order: Alarm, World clock, Stopwatch, Timer, then Bedtime.
        var tab = slot
        if slot == 2usize { tab = STOPWATCH_TAB }
        if slot == 3usize { tab = TIMER_TAB }
        let cx = 41.2 + f32(slot) * 82.4
        var c = paint.Color { red: 0.45, green: 0.44, blue: 0.42, alpha: 1.0 }
        if tab == s.tab { c = paint.Color { red: 0.13, green: 0.13, blue: 0.14, alpha: 1.0 } }
        var icon = tab
        if tab == STOPWATCH_TAB { icon = 3usize }
        if tab == TIMER_TAB { icon = 2usize }
        if tab == BEDTIME_TAB { icon = 4usize }
        try svg.draw(a, builder, nav_icon(icon), geometry.rect(cx - 13.0, 836.0, 26.0, 26.0), c)
        try centred(a, builder, faces.jost, 12.0, nav_name(tab), cx, 866.0, c)
        hit(s, 100usize + tab, cx - 41.0, 826.0, 82.0, 64.0)
        slot += 1usize
    }
    ret ok
}

fn draw_stopwatch(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, s: *State) -> err {
    let ms = stopwatch_ms(s)
    let cx: f32 = 206.0
    let cy: f32 = 251.0
    let accent = accent_dark()
    let dark = ink()
    let tick_grey = paint.Color { red: 0.50, green: 0.49, blue: 0.47, alpha: 1.0 }
    // The dial: a soft glow, then the face.
    try disc(a, builder, cx, cy, 154.0, paint.Color { red: 0.30, green: 0.30, blue: 0.32, alpha: 0.6 })
    try disc(a, builder, cx, cy, 149.0, panel())
    try ticks(a, builder, cx, cy, 142.0, 135.0, 128.0, 60usize, 5usize, 1.4, 3.6, tick_grey)
    // The numbers every five seconds, "60" at the top.
    var mark = 0usize
    while mark < 12usize {
        var label = "60"
        if mark != 0usize { label = number(a, mark * 5usize) }
        let at = on_dial(cx, cy, 106.0, f32(mark) / 12.0)
        try centred(a, builder, faces.jost, 17.0, label, at.x, at.y - 10.0, dark)
        mark += 1usize
    }
    // The sub-dial: thirty minutes round.
    let sx: f32 = 206.0
    let sy: f32 = 302.0
    try ticks(a, builder, sx, sy, 35.0, 31.0, 28.0, 30usize, 5usize, 0.8, 1.6, tick_grey)
    var sub = 0usize
    while sub < 6usize {
        var label = "30"
        if sub != 0usize { label = number(a, sub * 5usize) }
        let at = on_dial(sx, sy, 22.0, f32(sub) / 6.0)
        try centred(a, builder, faces.jost, 9.0, label, at.x, at.y - 5.5, dark)
        sub += 1usize
    }
    // The time over the dial: minutes dark, seconds and hundredths accent.
    let minutes_text = join(a, two(a, usize(ms / 60000i64) % 100usize), ":", "")
    let seconds_text = join(a, two(a, usize(ms / 1000i64) % 60usize), ".", two(a, usize(ms / 10i64) % 100usize))
    let wm = text.measure(a, faces.jost_bold, 33.0, minutes_text)
    let ws = text.measure(a, faces.jost_bold, 33.0, seconds_text)
    let left = cx - (wm + ws) / 2.0
    try put(a, builder, faces.jost_bold, 33.0, minutes_text, left, 175.0, dark)
    try put(a, builder, faces.jost_bold, 33.0, seconds_text, left + wm, 175.0, accent)
    // The sub-dial's hand (one turn in thirty minutes), the seconds hand, and the hub.
    let minute_turns = f32(ms % 1800000i64) / 1800000.0
    try hand(a, builder, geometry.Point { x: sx, y: sy }, on_dial(sx, sy, 24.0, minute_turns), 2.4, dark)
    try disc(a, builder, sx, sy, 3.5, dark)
    let second_turns = f32(ms % 60000i64) / 60000.0
    try hand(a, builder, on_dial(cx, cy, 0.0 - 14.0, second_turns), on_dial(cx, cy, 116.0, second_turns), 3.2, accent)
    try disc(a, builder, cx, cy, 11.0, dark)
    try disc(a, builder, cx, cy, 4.0, accent)
    // The laps, newest first, when there are any.
    var lap = 0usize
    while lap < s.lap_total && lap < 5usize {
        let index = s.lap_total - 1usize - lap
        var split = s.laps[index]
        if index > 0usize { split = s.laps[index] - s.laps[index - 1usize] }
        let y = 424.0 + f32(lap) * 44.0
        try put(a, builder, faces.jost, 16.0, join(a, "Lap ", number(a, index + 1usize), ""), 40.0, y, light_muted())
        try centred(a, builder, faces.jost, 20.0, stopwatch_text(a, split), 206.0, y - 3.0, light())
        try right(a, builder, faces.jost, 16.0, stopwatch_text(a, s.laps[index]), 372.0, y, light_muted())
        lap += 1usize
    }
    // The buttons: a round play (or pause) button, with Lap and Reset beside it once there is time on it.
    try disc(a, builder, cx, 774.0, 32.0, accent_c())
    if s.sw_running {
        try card(a, builder, cx - 10.0, 762.0, 7.0, 24.0, 2.0, ink())
        try card(a, builder, cx + 3.0, 762.0, 7.0, 24.0, 2.0, ink())
    } else {
        let (play_builder, play_error) = geometry.path_builder(a, 4usize, 3usize)
        if play_error != ok { ret play_error }
        var play = play_builder
        try geometry.move_to(&play, geometry.Point { x: cx - 8.0, y: 760.0 })
        try geometry.line_to(&play, geometry.Point { x: cx + 13.0, y: 774.0 })
        try geometry.line_to(&play, geometry.Point { x: cx - 8.0, y: 788.0 })
        try geometry.close_path(&play)
        try scene.push(builder, scene.Command { FillPath: scene.FillPath { path: geometry.finish(&play), brush: paint.Brush { Solid: white() } } })
    }
    hit(s, 500usize, cx - 36.0, 738.0, 72.0, 72.0)
    if s.sw_running || s.sw_acc_ms > 0i64 {
        try disc(a, builder, 100.0, 774.0, 26.0, soft())
        try centred(a, builder, faces.jost, 14.0, "Lap", 100.0, 765.0, dark)
        hit(s, 501usize, 70.0, 744.0, 60.0, 60.0)
        try disc(a, builder, 312.0, 774.0, 26.0, soft())
        try centred(a, builder, faces.jost, 14.0, "Reset", 312.0, 765.0, dark)
        hit(s, 502usize, 282.0, 744.0, 60.0, 60.0)
    }
    ret ok
}

// ---- the bedtime tab

fn draw_bedtime(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, s: *State) -> err {
    let sleep_minutes = s.sleep_half_hours * 30usize
    let bed = (s.wake_minutes + 1440usize - sleep_minutes % 1440usize) % 1440usize
    try title(a, builder, faces, "Bedtime")
    try card(a, builder, 16.0, 96.0, 380.0, 190.0, 28.0, panel())
    try centred(a, builder, faces.exo, 15.0, "Go to bed at", 206.0, 116.0, gray_text())
    try centred(a, builder, faces.jost_bold, 84.0, hhmm(a, bed), 206.0, 142.0, ink())
    // In how long.
    let now_minutes = minutes_of_day(utc_seconds(s))
    let wait = (bed + 1440usize - now_minutes) % 1440usize
    try centred(a, builder, faces.grotesk, 15.0, join(a, "in ", number(a, wait / 60usize), join(a, "h ", number(a, wait % 60usize), "m")), 206.0, 248.0, accent_dark())
    // Wake-up time.
    try card(a, builder, 16.0, 304.0, 380.0, 120.0, 24.0, panel())
    try put(a, builder, faces.exo, 14.0, "Wake up", 36.0, 318.0, gray_text())
    try centred(a, builder, faces.jost, 42.0, hhmm(a, s.wake_minutes), 206.0, 346.0, ink())
    try round_button(a, builder, s, faces, 600usize, 70.0, 380.0, 26.0, "-", soft(), ink(), 26.0)
    try round_button(a, builder, s, faces, 601usize, 342.0, 380.0, 26.0, "+", soft(), ink(), 26.0)
    // Sleep wanted.
    try card(a, builder, 16.0, 440.0, 380.0, 120.0, 24.0, panel())
    try put(a, builder, faces.exo, 14.0, "Sleep goal", 36.0, 454.0, gray_text())
    let hours = s.sleep_half_hours / 2usize
    var half = "h"
    if s.sleep_half_hours % 2usize == 1usize { half = ".5 h" }
    try centred(a, builder, faces.jost, 42.0, join(a, number(a, hours), half, ""), 206.0, 482.0, ink())
    try round_button(a, builder, s, faces, 604usize, 70.0, 516.0, 26.0, "-", soft(), ink(), 26.0)
    try round_button(a, builder, s, faces, 605usize, 342.0, 516.0, 26.0, "+", soft(), ink(), 26.0)
    // The reminder.
    try card(a, builder, 16.0, 576.0, 380.0, 84.0, 24.0, panel())
    try put(a, builder, faces.jost, 20.0, "Bedtime reminder", 36.0, 604.0, ink())
    try toggle_switch(a, builder, s, 606usize, 324.0, 602.0, s.bedtime_on)
    ret ok
}

// ----------------------------------------------------------------------------------------------

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The light ground; its alpha alternates by 0.2% a frame (invisible): the renderer's incremental
    // redraw left changed text without the shapes under it, so each frame must differ in its first command.
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.tab == ALARM_TAB {
        try draw_alarm(a, builder, faces, s)
    } else if s.tab == CLOCK_TAB {
        try draw_clock(a, builder, faces, s)
    } else if s.tab == TIMER_TAB {
        try draw_timer(a, builder, faces, s)
    } else if s.tab == STOPWATCH_TAB {
        try draw_stopwatch(a, builder, faces, s)
    } else {
        try draw_bedtime(a, builder, faces, s)
    }
    try draw_nav(a, builder, faces, s)
    try card(a, builder, 156.0, 906.0, 100.0, 5.0, 2.5, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    s.shown = display_key(s)
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

fn start_timer(s: *State) {
    let value = timer_value_ms(s)
    if value <= 0i64 { ret }
    s.timer_total_ms = value
    s.timer_end_ms = s.now_ms + value
    s.timer_running = true
    s.timer_paused = false
    s.timer_done = false
    say("clock timer started\n")
}

// What a tap on button `id` did: true when the screen changed.
fn act(s: *State, id: usize) -> bool {
    if id >= 100usize && id < 105usize {
        s.tab = id - 100usize
        s.picker = false
        ret true
    }
    // The clock's cities.
    if id == 210usize {
        s.picker = true
        ret true
    }
    if id == 230usize {
        s.picker = false
        ret true
    }
    if id >= 220usize && id < 236usize && id != 230usize {
        let city = id - 220usize
        var at = NONE
        var i = 0usize
        while i < s.city_total {
            if s.cities[i] == city { at = i }
            i += 1usize
        }
        if at != NONE {
            while at + 1usize < s.city_total {
                s.cities[at] = s.cities[at + 1usize]
                at += 1usize
            }
            s.city_total -= 1usize
        } else if s.city_total < 6usize {
            s.cities[s.city_total] = city
            s.city_total += 1usize
        }
        ret true
    }
    // The alarms.
    if id >= 300usize && id < 305usize {
        s.alarms[id - 300usize].on = !s.alarms[id - 300usize].on
        ret true
    }
    if id >= 310usize && id < 315usize {
        s.editing = id - 310usize
        s.edit = s.alarms[s.editing]
        ret true
    }
    if id == 320usize {
        s.alarms[s.alarm_total] = Alarm { minutes: 420usize, on: true, days: 127usize }
        s.editing = s.alarm_total
        s.alarm_total += 1usize
        s.edit = s.alarms[s.editing]
        ret true
    }
    if id == 330usize { s.edit.minutes = (s.edit.minutes + 1440usize - 60usize) % 1440usize
        ret true }
    if id == 331usize { s.edit.minutes = (s.edit.minutes + 60usize) % 1440usize
        ret true }
    if id == 332usize { s.edit.minutes = (s.edit.minutes + 1440usize - 5usize) % 1440usize
        ret true }
    if id == 333usize { s.edit.minutes = (s.edit.minutes + 5usize) % 1440usize
        ret true }
    if id >= 334usize && id < 341usize {
        s.edit.days = s.edit.days ^ (1usize << (id - 334usize))
        ret true
    }
    if id == 341usize {
        s.alarms[s.editing] = s.edit
        s.alarms[s.editing].on = true
        s.editing = NONE
        say("clock alarm saved ")
        say_hhmm(s.alarms[s.alarm_total - 1usize].minutes)
        say("\n")
        ret true
    }
    if id == 342usize || id == 343usize {
        if id == 342usize || s.editing + 1usize == s.alarm_total && s.alarms[s.editing].minutes == s.edit.minutes && false {
            var i = s.editing
            while i + 1usize < s.alarm_total {
                s.alarms[i] = s.alarms[i + 1usize]
                i += 1usize
            }
            if s.alarm_total > 0usize { s.alarm_total -= 1usize }
        }
        s.editing = NONE
        ret true
    }
    if id == 350usize {
        // Snooze: five minutes later.
        let alarm = s.alarms[s.ringing]
        s.alarms[s.ringing].minutes = (alarm.minutes + 5usize) % 1440usize
        s.alarms[s.ringing].on = true
        s.ringing = NONE
        ret true
    }
    if id == 351usize {
        s.ringing = NONE
        ret true
    }
    // The timer.
    if id >= 400usize && id < 410usize {
        if s.timer_typed < 6usize && !(s.timer_typed == 0usize && id == 400usize) {
            s.timer_digits[s.timer_typed] = u8(48usize + id - 400usize)
            s.timer_typed += 1usize
        }
        ret true
    }
    if id == 410usize {
        if s.timer_typed > 0usize { s.timer_typed -= 1usize }
        ret true
    }
    if id == 411usize {
        if s.timer_running {
            s.timer_left_ms = s.timer_end_ms - s.now_ms
            s.timer_running = false
            s.timer_paused = true
        } else if s.timer_paused {
            s.timer_end_ms = s.now_ms + s.timer_left_ms
            s.timer_running = true
            s.timer_paused = false
        } else {
            start_timer(s)
        }
        ret true
    }
    if id == 412usize {
        s.timer_running = false
        s.timer_paused = false
        s.timer_done = false
        ret true
    }
    if id == 413usize {
        if s.timer_running { s.timer_end_ms += 60000i64 }
        if s.timer_paused { s.timer_left_ms += 60000i64 }
        s.timer_total_ms += 60000i64
        ret true
    }
    if id == 414usize {
        s.timer_done = false
        ret true
    }
    if id >= 420usize && id < 424usize {
        var minutes = 1usize
        if id == 421usize { minutes = 5usize }
        if id == 422usize { minutes = 10usize }
        if id == 423usize { minutes = 15usize }
        s.timer_digits[0usize] = u8(48usize + minutes / 10usize)
        s.timer_digits[1usize] = u8(48usize + minutes % 10usize)
        s.timer_digits[2usize] = 48u8
        s.timer_digits[3usize] = 48u8
        s.timer_typed = 4usize
        if minutes < 10usize {
            s.timer_digits[0usize] = u8(48usize + minutes)
            s.timer_digits[1usize] = 48u8
            s.timer_digits[2usize] = 48u8
            s.timer_typed = 3usize
        }
        ret true
    }
    // The stopwatch.
    if id == 500usize {
        if s.sw_running {
            s.sw_acc_ms += s.now_ms - s.sw_start_ms
            s.sw_running = false
            say("clock stopwatch stopped ")
            say_num(usize(s.sw_acc_ms / 100i64))
            say("\n")
        } else {
            s.sw_start_ms = s.now_ms
            s.sw_running = true
            say("clock stopwatch started\n")
        }
        ret true
    }
    if id == 501usize {
        if (s.sw_running || s.sw_acc_ms > 0i64) && s.lap_total < 8usize {
            s.laps[s.lap_total] = stopwatch_ms(s)
            s.lap_total += 1usize
            say("clock stopwatch lap\n")
        }
        ret true
    }
    if id == 502usize {
        s.sw_running = false
        s.sw_acc_ms = 0i64
        s.lap_total = 0usize
        ret true
    }
    // Bedtime.
    if id == 600usize { s.wake_minutes = (s.wake_minutes + 1440usize - 15usize) % 1440usize
        ret true }
    if id == 601usize { s.wake_minutes = (s.wake_minutes + 15usize) % 1440usize
        ret true }
    if id == 604usize {
        if s.sleep_half_hours > 8usize { s.sleep_half_hours -= 1usize }
        ret true
    }
    if id == 605usize {
        if s.sleep_half_hours < 24usize { s.sleep_half_hours += 1usize }
        ret true
    }
    if id == 606usize {
        s.bedtime_on = !s.bedtime_on
        ret true
    }
    ret false
}

// "HH:MM" to the console, through a buffer on the stack.
fn say_hhmm(minutes: usize) {
    var buffer: [5]u8 = zero
    buffer[0usize] = u8(minutes / 60usize % 24usize / 10usize) + 48u8
    buffer[1usize] = u8(minutes / 60usize % 24usize % 10usize) + 48u8
    buffer[2usize] = 58u8
    buffer[3usize] = u8(minutes % 60usize / 10usize) + 48u8
    buffer[4usize] = u8(minutes % 60usize % 10usize) + 48u8
    say(buffer[0usize..5usize])
}

// The y from which a tap leaves the app: the bottom bar of the cards, or below the stopwatch's navigation.
fn exit_y(s: *State) -> f32 {
    ret 896.0
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

// On a tick: the timer reaching zero and an alarm's minute arriving. True when something changed.
fn on_tick(s: *State) -> bool {
    var changed = false
    if s.timer_running && s.timer_end_ms - s.now_ms <= 0i64 {
        s.timer_running = false
        s.timer_done = true
        s.timer_left_ms = 0i64
        s.tab = TIMER_TAB
        say("clock timer done\n")
        changed = true
    }
    if s.ringing == NONE {
        let now = utc_seconds(s)
        let minute = minutes_of_day(now)
        let day = weekday_of(now)
        var i = 0usize
        while i < s.alarm_total {
            let alarm = s.alarms[i]
            let today = alarm.days == 0usize || (alarm.days >> day) & 1usize == 1usize
            let stamp = now / 60usize
            if alarm.on && today && alarm.minutes == minute && s.fired != stamp {
                s.fired = stamp
                s.ringing = i
                s.tab = ALARM_TAB
                s.editing = NONE
                say("clock alarm ringing ")
                say_hhmm(alarm.minutes)
                say("\n")
                changed = true
            }
            i += 1usize
        }
    }
    ret changed
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "clock")
    if kit_error != ok {
        say("clock open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("clock fonts absent\n")
        ret ok
    }
    var s: State = zero
    let (wall, wall_error) = time.now()
    if wall_error == ok { s.wall0 = wall.nanos / 1000000000i64 }
    refresh(&s)
    s.mono0 = s.now_ms
    s.tab = CLOCK_TAB
    // Six cities to start with.
    s.cities[0usize] = 14usize
    s.cities[1usize] = 1usize
    s.cities[2usize] = 5usize
    s.cities[3usize] = 8usize
    s.cities[4usize] = 9usize
    s.cities[5usize] = 12usize
    s.city_total = 6usize
    // Two alarms to start with.
    s.alarms[0usize] = Alarm { minutes: 390usize, on: true, days: 31usize }
    s.alarms[1usize] = Alarm { minutes: 480usize, on: false, days: 96usize }
    s.alarm_total = 2usize
    s.editing = NONE
    s.ringing = NONE
    s.fired = 0usize
    s.wake_minutes = 420usize
    s.sleep_half_hours = 16usize
    if !show(a, &kit, &s) {
        say("clock present failed\n")
        ret ok
    }
    say("clock shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        refresh(&s)
        if tap.ended {
            running = false
        } else if tap.tick {
            let alarmed = on_tick(&s)
            if (alarmed || display_key(&s) != s.shown) && show(a, &kit, &s) {
                var unused = 0usize
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= exit_y(&s) {
            say("clock home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    say("clock present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
                say("clock tab ")
                say_text(tab_name(s.tab))
                say("\n")
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
