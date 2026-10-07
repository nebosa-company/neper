// Weather (D2214): the app behind the Weather icon, after Google's Weather -- four places as chips, the
// temperature now with its condition icon, the day's high and low, an hourly strip, a seven-day list
// with a range bar per day, and a row of Feels like, Humidity, Wind and UV. A chip changes the place;
// the C/F chip changes the unit. Dark ground, cream cards and amber, like the other apps (appkit.e,
// taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves.
// ponytail: the weather is SAMPLE data -- a seeded forecast per place, the same on every run, labelled
// "Sample data, not live" on screen -- because NeperOS has no network yet (queue item C117); a live
// source replaces the sample_* functions when it has one (C119). The hours and weekdays follow the
// real clock (UTC); the numbers do not.
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use appkit
use text

const NONE: usize = 99usize
const PLACES: usize = 4usize
const MAX_HITS: usize = 16usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
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

// "-3°" or "21°": a temperature in Celsius, shown in Fahrenheit when `fahrenheit`.
fn temp_text(a: *mem.Arena, celsius: f32, fahrenheit: bool) -> str {
    var v = celsius
    if fahrenheit { v = celsius * 1.8 + 32.0 }
    var sign = ""
    var magnitude = v
    if v < 0.0 {
        sign = "-"
        magnitude = 0.0 - v
    }
    ret join(a, sign, number(a, usize(magnitude + 0.5)), "\xC2\xB0")
}

fn hour_text(a: *mem.Arena, hour: usize) -> str {
    let h = hour % 24usize
    var h12 = h % 12usize
    if h12 == 0usize { h12 = 12usize }
    var suffix = " AM"
    if h >= 12usize { suffix = " PM" }
    ret join(a, number(a, h12), suffix, "")
}

fn weekday_short(day: usize) -> str {
    if day == 0usize { ret "Mon" }
    if day == 1usize { ret "Tue" }
    if day == 2usize { ret "Wed" }
    if day == 3usize { ret "Thu" }
    if day == 4usize { ret "Fri" }
    if day == 5usize { ret "Sat" }
    ret "Sun"
}

// ----------------------------------------------------------------------------------------------
// The sample forecast: everything is a pure function of the place and the day.

fn place_name(place: usize) -> str {
    if place == 0usize { ret "Seattle" }
    if place == 1usize { ret "Cairo" }
    if place == 2usize { ret "Tokyo" }
    ret "Oslo"
}

fn cond_name(cond: usize) -> str {
    if cond == 0usize { ret "Sunny" }
    if cond == 1usize { ret "Partly cloudy" }
    if cond == 2usize { ret "Cloudy" }
    if cond == 3usize { ret "Rain" }
    if cond == 4usize { ret "Thunderstorms" }
    ret "Snow"
}

// The typical high of a place and how far its low sits below it.
fn base_high(place: usize) -> f32 {
    if place == 0usize { ret 14.0 }
    if place == 1usize { ret 33.0 }
    if place == 2usize { ret 22.0 }
    ret 2.0
}

fn base_range(place: usize) -> f32 {
    if place == 0usize { ret 6.0 }
    if place == 1usize { ret 13.0 }
    if place == 2usize { ret 8.0 }
    ret 5.0
}

fn mix(first: usize, second: usize) -> usize {
    var x = first * 7919usize + second * 104729usize + 12345usize
    x = (x * 1103515245usize + 12345usize) & 2147483647usize
    x = (x * 1103515245usize + 12345usize) & 2147483647usize
    ret x >> 8usize
}

// A repeatable number between -1 and 1.
fn noise(place: usize, day: usize, salt: usize) -> f32 {
    ret f32(mix(place * 100usize + day, salt) % 2001usize) / 1000.0 - 1.0
}

fn day_high(place: usize, day: usize) -> f32 {
    ret base_high(place) + noise(place, day, 1usize) * 3.5
}

fn day_low(place: usize, day: usize) -> f32 {
    ret day_high(place, day) - base_range(place) - (noise(place, day, 2usize) + 1.0) * 1.5
}

fn day_cond(place: usize, day: usize) -> usize {
    let r = mix(place * 100usize + day, 3usize) % 10usize
    var cond = 2usize
    if place == 0usize {
        if r < 2usize { cond = 0usize } else if r < 4usize { cond = 1usize } else if r < 6usize { cond = 2usize } else if r < 9usize { cond = 3usize } else { cond = 4usize }
    } else if place == 1usize {
        if r < 7usize { cond = 0usize } else if r < 9usize { cond = 1usize } else { cond = 2usize }
    } else if place == 2usize {
        if r < 3usize { cond = 0usize } else if r < 5usize { cond = 1usize } else if r < 7usize { cond = 2usize } else if r < 9usize { cond = 3usize } else { cond = 4usize }
    } else {
        if r < 1usize { cond = 0usize } else if r < 3usize { cond = 1usize } else if r < 6usize { cond = 2usize } else { cond = 5usize }
    }
    ret cond
}

// The temperature at `hour` (0..23) of day `day`: the low before sunrise, the high mid-afternoon.
fn hour_temp(place: usize, day: usize, hour: usize) -> f32 {
    let h = hour % 24usize
    var away = 0usize
    if h >= 15usize { away = h - 15usize } else { away = 15usize - h }
    if away > 12usize { away = 24usize - away }
    var warmth: f32 = 0.0
    if away < 9usize { warmth = 1.0 - f32(away) / 9.0 }
    let low = day_low(place, day)
    ret low + (day_high(place, day) - low) * warmth
}

fn humidity(place: usize) -> usize {
    ret 40usize + mix(place, 11usize) % 45usize
}

fn wind_kmh(place: usize) -> usize {
    ret 6usize + mix(place, 12usize) % 22usize
}

fn uv_index(place: usize, cond: usize) -> usize {
    var uv = 1usize
    if cond == 0usize { uv = 7usize }
    if cond == 1usize { uv = 5usize }
    if cond == 2usize { uv = 3usize }
    if place == 3usize && uv > 2usize { uv -= 2usize }
    ret uv
}

// ----------------------------------------------------------------------------------------------
// State.

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    place: usize,
    fahrenheit: bool,
    // Today as a weekday (0 = Monday) and the hour now, from the clock.
    weekday: usize,
    hour: usize,
    hits: [16]Hit,
    hit_total: usize,
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

fn light() -> paint.Color {
    ret paint.Color { red: 0.94, green: 0.93, blue: 0.90, alpha: 1.0 }
}

fn light_muted() -> paint.Color {
    ret paint.Color { red: 0.72, green: 0.72, blue: 0.74, alpha: 1.0 }
}

fn amber() -> paint.Color {
    ret paint.Color { red: 0.88, green: 0.70, blue: 0.42, alpha: 1.0 }
}

fn soft() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

fn card(a: *mem.Arena, builder: *scene.Builder, x: f32, y: f32, w: f32, h: f32, radius: f32, c: paint.Color) -> err {
    let (path, path_error) = svg.rect_path(a, x, y, w, h, radius, radius)
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

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

fn put_right(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, right: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, right - text.measure(a, font, size, line), y, c)
}

// A condition icon on a 48 x 48 grid: the sun in amber, the cloud pale on the dark ground and slate on
// the cream cards. `night` swaps a clear sky for a crescent.
fn weather_svg(a: *mem.Arena, cond: usize, dark: bool, night: bool) -> str {
    var sun = "#e49a1f"
    var cloud = "#7f8da3"
    if dark {
        sun = "#e0b36a"
        cloud = "#e8ebf0"
    }
    let head = "<svg viewBox='0 0 48 48'>"
    let cloud_path = join(a, "<path d='M14 34 a8 8 0 0 1 -1 -16 a11 11 0 0 1 21 3 a7 7 0 0 1 0 13 z' fill='", cloud, "'/>")
    let high_cloud = join(a, "<path d='M14 28 a8 8 0 0 1 -1 -16 a11 11 0 0 1 21 3 a7 7 0 0 1 0 13 z' fill='", cloud, "'/>")
    if cond == 0usize {
        if night { ret join(a, head, join(a, "<path d='M30 8 a16 16 0 1 0 10 28 a13 13 0 0 1 -10 -28 z' fill='", sun, "'/>"), "</svg>") }
        ret join(a, head, join(a, join(a, "<circle cx='24' cy='24' r='9' fill='", sun, "'/><g stroke='"), join(a, sun, "' stroke-width='3' stroke-linecap='round'><path d='M24 5v5M24 38v5M5 24h5M38 24h5M10.5 10.5l3.5 3.5M34 34l3.5 3.5M37.5 10.5L34 14M14 34l-3.5 3.5'/></g>", ""), ""), "</svg>")
    }
    if cond == 1usize { ret join(a, head, join(a, join(a, "<circle cx='18' cy='17' r='8' fill='", sun, "'/>"), cloud_path, ""), "</svg>") }
    if cond == 2usize { ret join(a, head, cloud_path, "</svg>") }
    if cond == 3usize { ret join(a, head, join(a, high_cloud, "<path d='M16 36l-2 6M25 36l-2 6M34 36l-2 6' stroke='#7ea6d6' stroke-width='3' stroke-linecap='round'/>", ""), "</svg>") }
    if cond == 4usize { ret join(a, head, join(a, high_cloud, join(a, "<path d='M26 29l-6 9h5l-2 8 9-11h-6l3-6z' fill='", sun, "'/>"), ""), "</svg>") }
    ret join(a, head, join(a, high_cloud, "<g fill='#9db4d6'><circle cx='16' cy='38' r='2.4'/><circle cx='25' cy='41' r='2.4'/><circle cx='34' cy='38' r='2.4'/></g>", ""), "</svg>")
}

fn icon(a: *mem.Arena, builder: *scene.Builder, cond: usize, dark: bool, night: bool, x: f32, y: f32, size: f32) -> err {
    try svg.draw(a, builder, weather_svg(a, cond, dark, night), geometry.rect(x, y, size, size), ink())
    ret ok
}

// Is `hour` (0..23) between dusk and dawn?
fn is_night(hour: usize) -> bool {
    ret hour < 6usize || hour >= 20usize
}

fn draw_main(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let place = s.place
    let f = s.fahrenheit
    let today_cond = day_cond(place, 0usize)
    let now_temp = hour_temp(place, 0usize, s.hour)
    // The places.
    var chip = 0usize
    while chip < PLACES {
        var fill = soft()
        if chip == place { fill = amber() }
        let x: f32 = 16.0 + f32(chip) * 96.0
        try card(a, builder, x, 24.0, 88.0, 34.0, 17.0, fill)
        try centred(a, builder, faces.jost, 15.0, place_name(chip), x + 44.0, 24.0 + 17.0 - 9.0, ink())
        hit(s, 100usize + chip, x, 24.0, 88.0, 34.0)
        chip += 1usize
    }
    // Now.
    try put(a, builder, faces.jost_bold, 84.0, temp_text(a, now_temp, f), 24.0, 70.0, light())
    try put(a, builder, faces.jost, 22.0, cond_name(today_cond), 28.0, 176.0, light())
    try put(a, builder, faces.grotesk, 15.0, join(a, join(a, "H ", temp_text(a, day_high(place, 0usize), f), "   L "), temp_text(a, day_low(place, 0usize), f), ""), 28.0, 212.0, light_muted())
    try icon(a, builder, today_cond, true, is_night(s.hour), 268.0, 72.0, 128.0)
    var unit = "C"
    if f { unit = "F" }
    try card(a, builder, 316.0, 206.0, 80.0, 32.0, 16.0, soft())
    try centred(a, builder, faces.jost, 15.0, join(a, "\xC2\xB0", unit, ""), 356.0, 206.0 + 16.0 - 9.0, ink())
    hit(s, 700usize, 316.0, 206.0, 80.0, 32.0)
    // The next eight hours.
    try card(a, builder, 16.0, 250.0, 380.0, 118.0, 20.0, cream())
    var col = 0usize
    while col < 8usize {
        let h = s.hour + col
        let cx: f32 = 16.0 + 23.75 + f32(col) * 47.5
        var label = "Now"
        if col > 0usize { label = hour_text(a, h) }
        try centred(a, builder, faces.grotesk, 11.0, label, cx, 262.0, muted())
        try icon(a, builder, today_cond, false, is_night(h % 24usize), cx - 14.0, 282.0, 28.0)
        try centred(a, builder, faces.jost, 16.0, temp_text(a, hour_temp(place, 0usize, h % 24usize), f), cx, 322.0, ink())
        col += 1usize
    }
    // The seven days.
    try card(a, builder, 16.0, 380.0, 380.0, 336.0, 20.0, cream())
    var week_low = day_low(place, 0usize)
    var week_high = day_high(place, 0usize)
    var d = 1usize
    while d < 7usize {
        if day_low(place, d) < week_low { week_low = day_low(place, d) }
        if day_high(place, d) > week_high { week_high = day_high(place, d) }
        d += 1usize
    }
    let span = week_high - week_low
    d = 0usize
    while d < 7usize {
        let y: f32 = 392.0 + f32(d) * 46.0
        var name = "Today"
        if d > 0usize { name = weekday_short((s.weekday + d) % 7usize) }
        try put(a, builder, faces.jost, 17.0, name, 32.0, y + 10.0, ink())
        try icon(a, builder, day_cond(place, d), false, false, 108.0, y + 4.0, 32.0)
        try put_right(a, builder, faces.jost, 16.0, temp_text(a, day_low(place, d), f), 204.0, y + 11.0, muted())
        let from: f32 = 216.0 + (day_low(place, d) - week_low) / span * 108.0
        let to: f32 = 216.0 + (day_high(place, d) - week_low) / span * 108.0
        try card(a, builder, 216.0, y + 17.0, 108.0, 5.0, 2.5, soft())
        try card(a, builder, from, y + 17.0, to - from + 5.0, 5.0, 2.5, amber())
        try put(a, builder, faces.jost, 16.0, temp_text(a, day_high(place, d), f), 342.0, y + 11.0, ink())
        d += 1usize
    }
    // Feels like, humidity, wind and UV.
    try card(a, builder, 16.0, 730.0, 380.0, 68.0, 20.0, cream())
    let wind = wind_kmh(place)
    var wind_text = join(a, number(a, wind), " km/h", "")
    if f { wind_text = join(a, number(a, wind * 62usize / 100usize), " mph", "") }
    let feels = now_temp - f32(wind) / 15.0
    var stat = 0usize
    while stat < 4usize {
        var label = "Feels like"
        var value = temp_text(a, feels, f)
        if stat == 1usize {
            label = "Humidity"
            value = join(a, number(a, humidity(place)), "%", "")
        }
        if stat == 2usize {
            label = "Wind"
            value = wind_text
        }
        if stat == 3usize {
            label = "UV index"
            value = number(a, uv_index(place, today_cond))
        }
        let cx: f32 = 16.0 + 47.5 + f32(stat) * 95.0
        try centred(a, builder, faces.grotesk, 11.0, label, cx, 744.0, muted())
        try centred(a, builder, faces.jost, 18.0, value, cx, 764.0, ink())
        stat += 1usize
    }
    try centred(a, builder, faces.grotesk, 12.0, "Sample data, not live", 206.0, 814.0, light_muted())
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    try draw_main(a, builder, s, faces)
    try card(a, builder, 156.0, 906.0, 100.0, 5.0, 2.5, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
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

// What a tap on button `id` did: true when the screen changed.
fn act(s: *State, id: usize) -> bool {
    if id >= 100usize && id < 100usize + PLACES {
        s.place = id - 100usize
        say("weather place ")
        say(place_name(s.place))
        say("\n")
        ret true
    }
    if id == 700usize {
        s.fahrenheit = !s.fahrenheit
        if s.fahrenheit { say("weather unit F\n") } else { say("weather unit C\n") }
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
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "weather")
    if kit_error != ok {
        say("weather open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("weather fonts absent\n")
        ret ok
    }
    var s: State = zero
    let (wall, wall_error) = time.now()
    if wall_error == ok {
        let seconds = usize(wall.nanos / 1000000000i64)
        s.hour = (seconds % 86400usize) / 3600usize
        // 1 January 1970 was a Thursday (3 with Monday as 0).
        s.weekday = (seconds / 86400usize + 3usize) % 7usize
    }
    if !show(a, &kit, &s) {
        say("weather present failed\n")
        ret ok
    }
    say("weather shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("weather home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    say("weather present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
