// Stocks (D2213): the app behind the Stocks icon -- a watchlist (ticker, company, a sparkline, the price
// and the day's change in green or red) and a detail screen per stock (the price, the change over the
// chosen range, a line chart with its area, range chips 1W / 1M / 2M, and the high, low, start and
// previous close). Dark ground, cream rows and amber chips, like the other apps (appkit.e, taps from the
// compositor, the five fonts as args[1..5]). A tap on the bar at the bottom leaves the app.
// ponytail: the prices are SAMPLE data -- a seeded random walk of 60 days per ticker, labelled "Sample
// data, not live" on screen -- because NeperOS has no network yet (queue item C117); a live source
// replaces sample_price() when it has one. No search, no adding tickers, no portfolio.
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

const NONE: usize = 99usize
const TICKERS: usize = 7usize
const DAYS: usize = 60usize
const MAX_HITS: usize = 32usize

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

// Append `piece` to `buffer` at `at`; the new end.
fn emit(buffer: []u8, at: usize, piece: str) -> usize {
    var n = at
    var i = 0usize
    while i < piece.len && n < buffer.len {
        buffer[n] = piece[i]
        n += 1usize
        i += 1usize
    }
    ret n
}

fn emit_num(buffer: []u8, at: usize, value: usize) -> usize {
    var digits: [20]u8 = zero
    var d = 20usize
    var rest = value
    var open = true
    while open {
        d -= 1usize
        digits[d] = u8(rest % 10usize) + 48u8
        rest = rest / 10usize
        if rest == 0usize { open = false }
    }
    ret emit(buffer, at, digits[d..20usize])
}

// Two digits of a hundredth count: 5 -> "05".
fn cents_text(a: *mem.Arena, cents: usize) -> str {
    var tens = ""
    if cents < 10usize { tens = "0" }
    ret join(a, tens, number(a, cents), "")
}

// "$189.52".
fn price_text(a: *mem.Arena, value: f32) -> str {
    let total = usize(value * 100.0 + 0.5)
    ret join(a, join(a, "$", number(a, total / 100usize), "."), cents_text(a, total % 100usize), "")
}

// "+1.23%" or "-0.40%" from a fraction.
fn percent_text(a: *mem.Arena, fraction: f32) -> str {
    var sign = "+"
    var magnitude = fraction
    if fraction < 0.0 {
        sign = "-"
        magnitude = 0.0 - fraction
    }
    let basis = usize(magnitude * 10000.0 + 0.5)
    ret join(a, join(a, sign, number(a, basis / 100usize), "."), cents_text(a, basis % 100usize), "%")
}

// "+2.31" or "-0.40": a price difference.
fn delta_text(a: *mem.Arena, difference: f32) -> str {
    var sign = "+"
    var magnitude = difference
    if difference < 0.0 {
        sign = "-"
        magnitude = 0.0 - difference
    }
    let total = usize(magnitude * 100.0 + 0.5)
    ret join(a, join(a, sign, number(a, total / 100usize), "."), cents_text(a, total % 100usize), "")
}

// ----------------------------------------------------------------------------------------------
// The sample data.

fn symbol(index: usize) -> str {
    if index == 0usize { ret "AAPL" }
    if index == 1usize { ret "MSFT" }
    if index == 2usize { ret "GOOGL" }
    if index == 3usize { ret "AMZN" }
    if index == 4usize { ret "TSLA" }
    if index == 5usize { ret "NVDA" }
    ret "META"
}

fn company(index: usize) -> str {
    if index == 0usize { ret "Apple Inc." }
    if index == 1usize { ret "Microsoft Corp." }
    if index == 2usize { ret "Alphabet Inc." }
    if index == 3usize { ret "Amazon.com Inc." }
    if index == 4usize { ret "Tesla Inc." }
    if index == 5usize { ret "NVIDIA Corp." }
    ret "Meta Platforms"
}

// Where each sample series ends and how restless it is.
fn base_price(index: usize) -> f32 {
    if index == 0usize { ret 189.5 }
    if index == 1usize { ret 412.3 }
    if index == 2usize { ret 141.8 }
    if index == 3usize { ret 178.2 }
    if index == 4usize { ret 245.7 }
    if index == 5usize { ret 877.4 }
    ret 486.1
}

fn volatility(index: usize) -> f32 {
    if index == 0usize { ret 0.012 }
    if index == 1usize { ret 0.010 }
    if index == 2usize { ret 0.014 }
    if index == 3usize { ret 0.016 }
    if index == 4usize { ret 0.034 }
    if index == 5usize { ret 0.028 }
    ret 0.020
}

type State = struct {
    prices: [420]f32,
    selected: usize,
    range: usize,
    hits: [32]Hit,
    hit_total: usize,
}

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

// A seeded random walk: the same sample prices on every run. Each series ends near its base price.
fn fill_sample(s: *State) {
    var t = 0usize
    while t < TICKERS {
        var seed = 12345usize + t * 7919usize
        var price: f32 = base_price(t) * 0.93
        let vol = volatility(t)
        var d = 0usize
        while d < DAYS {
            seed = (seed * 1103515245usize + 12345usize) & 2147483647usize
            let r = f32(seed >> 8usize) / 8388608.0
            price = price * (1.0 + (r - 0.5) * 2.0 * vol + 0.0012)
            s.prices[t * DAYS + d] = price
            d += 1usize
        }
        t += 1usize
    }
}

// The days a range shows: 1W 7, 1M 30, 2M 60.
fn range_days(range: usize) -> usize {
    if range == 0usize { ret 7usize }
    if range == 1usize { ret 30usize }
    ret 60usize
}

fn price_at(s: *State, t: usize, day: usize) -> f32 {
    ret s.prices[t * DAYS + day]
}

fn day_change(s: *State, t: usize) -> f32 {
    ret price_at(s, t, DAYS - 1usize) - price_at(s, t, DAYS - 2usize)
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

// Green and red for a gain and a loss: darker on the cream rows, brighter on the dark ground.
fn gain_on_cream(up: bool) -> paint.Color {
    if up { ret paint.Color { red: 0.13, green: 0.52, blue: 0.28, alpha: 1.0 } }
    ret paint.Color { red: 0.72, green: 0.22, blue: 0.18, alpha: 1.0 }
}

fn gain_on_dark(up: bool) -> paint.Color {
    if up { ret paint.Color { red: 0.45, green: 0.80, blue: 0.55, alpha: 1.0 } }
    ret paint.Color { red: 0.95, green: 0.50, blue: 0.45, alpha: 1.0 }
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

fn clipped(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, width: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, width, 1u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

// Right-aligned at `right`.
fn put_right(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, right: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, right - text.measure(a, font, size, line), y, c)
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

// The line (or, with `area`, the filled area under it) of `days` closing prices of ticker `t`, as an
// svg document of `w` x `h` whole units: high at the top, low at the bottom.
fn chart_svg(a: *mem.Arena, s: *State, t: usize, days: usize, w: usize, h: usize, area: bool, stroke: usize) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, 1600usize)
    if buffer_error != ok { ret "" }
    let first = DAYS - days
    var low = price_at(s, t, first)
    var high = low
    var d = first
    while d < DAYS {
        let v = price_at(s, t, d)
        if v < low { low = v }
        if v > high { high = v }
        d += 1usize
    }
    var span = high - low
    if span < 0.0001 { span = 1.0 }
    var n = 0usize
    n = emit(buffer, n, "<svg viewBox='0 0 ")
    n = emit_num(buffer, n, w)
    n = emit(buffer, n, " ")
    n = emit_num(buffer, n, h)
    n = emit(buffer, n, "'><path d='")
    if area {
        n = emit(buffer, n, "M0 ")
        n = emit_num(buffer, n, h)
    }
    d = 0usize
    while d < days {
        let v = price_at(s, t, first + d)
        let x = d * w / (days - 1usize)
        let y = 2usize + usize((high - v) / span * f32(h - 4usize))
        if d == 0usize && !area { n = emit(buffer, n, "M") } else { n = emit(buffer, n, " L") }
        n = emit_num(buffer, n, x)
        n = emit(buffer, n, " ")
        n = emit_num(buffer, n, y)
        d += 1usize
    }
    if area {
        n = emit(buffer, n, " L")
        n = emit_num(buffer, n, w)
        n = emit(buffer, n, " ")
        n = emit_num(buffer, n, h)
        n = emit(buffer, n, " Z' fill='currentColor' stroke='none'/></svg>")
    } else {
        n = emit(buffer, n, "' fill='none' stroke='currentColor' stroke-width='")
        n = emit_num(buffer, n, stroke)
        n = emit(buffer, n, "' stroke-linecap='round' stroke-linejoin='round'/></svg>")
    }
    ret buffer[0usize..n]
}

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try put(a, builder, faces.jost_bold, 34.0, "Stocks", 24.0, 40.0, light())
    try put(a, builder, faces.grotesk, 12.0, "Sample data, not live", 24.0, 86.0, light_muted())
    var t = 0usize
    while t < TICKERS {
        let y: f32 = 112.0 + f32(t) * 88.0
        let change = day_change(s, t)
        let up = change >= 0.0
        let last = price_at(s, t, DAYS - 1usize)
        let previous = price_at(s, t, DAYS - 2usize)
        try card(a, builder, 16.0, y, 380.0, 76.0, 20.0, cream())
        try put(a, builder, faces.jost_bold, 19.0, symbol(t), 32.0, y + 14.0, ink())
        try clipped(a, builder, faces.grotesk, 12.0, company(t), 32.0, y + 44.0, 124.0, muted())
        try svg.draw(a, builder, chart_svg(a, s, t, 30usize, 80usize, 32usize, false, 2usize), geometry.rect(164.0, y + 22.0, 80.0, 32.0), gain_on_cream(up))
        try put_right(a, builder, faces.jost_bold, 19.0, price_text(a, last), 380.0, y + 14.0, ink())
        try put_right(a, builder, faces.grotesk, 13.0, percent_text(a, change / previous), 380.0, y + 44.0, gain_on_cream(up))
        hit(s, 100usize + t, 16.0, y, 380.0, 76.0)
        t += 1usize
    }
    ret ok
}

fn stat(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, label: str, value: f32, x: f32, y: f32) -> err {
    try put(a, builder, faces.grotesk, 12.0, label, x, y, muted())
    try put(a, builder, faces.jost, 20.0, price_text(a, value), x, y + 18.0, ink())
    ret ok
}

fn draw_detail(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let t = s.selected
    let days = range_days(s.range)
    let first = DAYS - days
    let last = price_at(s, t, DAYS - 1usize)
    let start = price_at(s, t, first)
    var low = start
    var high = start
    var d = first
    while d < DAYS {
        let v = price_at(s, t, d)
        if v < low { low = v }
        if v > high { high = v }
        d += 1usize
    }
    let change = last - start
    let up = change >= 0.0
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 36.0, 28.0, 28.0), light())
    hit(s, 500usize, 0.0, 20.0, 66.0, 60.0)
    try put(a, builder, faces.jost_bold, 26.0, symbol(t), 64.0, 26.0, light())
    try put(a, builder, faces.grotesk, 13.0, company(t), 64.0, 62.0, light_muted())
    try put(a, builder, faces.jost_bold, 46.0, price_text(a, last), 24.0, 96.0, light())
    try put(a, builder, faces.jost, 18.0, join(a, join(a, delta_text(a, change), "  ", percent_text(a, change / start)), "", ""), 24.0, 156.0, gain_on_dark(up))
    // The range chips.
    var chip = 0usize
    while chip < 3usize {
        var label = "1W"
        if chip == 1usize { label = "1M" }
        if chip == 2usize { label = "2M" }
        var fill = soft()
        if chip == s.range { fill = amber() }
        let x: f32 = 16.0 + f32(chip) * 84.0
        try card(a, builder, x, 196.0, 76.0, 36.0, 18.0, fill)
        try centred(a, builder, faces.jost, 15.0, label, x + 38.0, 196.0 + 18.0 - 9.0, ink())
        hit(s, 600usize + chip, x, 196.0, 76.0, 36.0)
        chip += 1usize
    }
    // The chart: the area under the line, then the line; the high above it and the low below.
    try put(a, builder, faces.grotesk, 12.0, join(a, "High ", price_text(a, high), ""), 16.0, 244.0, light_muted())
    try svg.draw(a, builder, chart_svg(a, s, t, days, 380usize, 200usize, true, 3usize), geometry.rect(16.0, 264.0, 380.0, 200.0), paint.Color { red: gain_on_dark(up).red, green: gain_on_dark(up).green, blue: gain_on_dark(up).blue, alpha: 0.2 })
    try svg.draw(a, builder, chart_svg(a, s, t, days, 380usize, 200usize, false, 3usize), geometry.rect(16.0, 264.0, 380.0, 200.0), gain_on_dark(up))
    try put(a, builder, faces.grotesk, 12.0, join(a, "Low ", price_text(a, low), ""), 16.0, 472.0, light_muted())
    // The numbers.
    try card(a, builder, 16.0, 516.0, 380.0, 132.0, 20.0, cream())
    try stat(a, builder, faces, "Range high", high, 36.0, 534.0)
    try stat(a, builder, faces, "Range low", low, 216.0, 534.0)
    try stat(a, builder, faces, "Range start", start, 36.0, 592.0)
    try stat(a, builder, faces, "Previous close", price_at(s, t, DAYS - 2usize), 216.0, 592.0)
    try centred(a, builder, faces.grotesk, 12.0, "Sample data, not live", 206.0, 672.0, light_muted())
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.selected == NONE {
        try draw_list(a, builder, s, faces)
    } else {
        try draw_detail(a, builder, s, faces)
    }
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
    if s.selected == NONE {
        if id >= 100usize && id < 100usize + TICKERS {
            s.selected = id - 100usize
            say("stocks opened ")
            say(symbol(s.selected))
            say("\n")
            ret true
        }
        ret false
    }
    if id == 500usize {
        s.selected = NONE
        say("stocks back\n")
        ret true
    }
    if id >= 600usize && id < 603usize {
        s.range = id - 600usize
        say("stocks range ")
        say_num(range_days(s.range))
        say("\n")
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
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "stocks")
    if kit_error != ok {
        say("stocks open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("stocks fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.selected = NONE
    s.range = 1usize
    fill_sample(&s)
    if !show(a, &kit, &s) {
        say("stocks present failed\n")
        ret ok
    }
    say("stocks shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("stocks home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    say("stocks present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
