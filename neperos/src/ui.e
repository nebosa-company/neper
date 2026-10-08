// Helpers the NeperOS apps share (D2221): text and number building, the cream cards and amber discs,
// text placement, the tap targets of a screen, the colours, and the on-screen keyboard. The apps written
// before it carry their own copies; the ones written after it use this.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use text

const NONE: usize = 99usize
const MAX_HITS: usize = 96usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

// The first 40 bytes of `value`: names in serial markers.
fn say_text(value: str) {
    var buffer: [40]u8 = zero
    var n = 0usize
    while n < value.len && n < 40usize {
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

// Two digits: 5 -> "05".
fn two(a: *mem.Arena, value: usize) -> str {
    if value < 10usize { ret join(a, "0", number(a, value), "") }
    ret number(a, value)
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

fn text_of(a: *mem.Arena, bytes: []const u8, length: usize) -> str {
    let (copy, copy_error) = mem.alloc[u8](a, length + 1usize)
    if copy_error != ok { ret "" }
    var i = 0usize
    while i < length {
        copy[i] = bytes[i]
        i += 1usize
    }
    ret copy[0usize..length]
}

fn same(left: str, right: str) -> bool {
    if left.len != right.len { ret false }
    var i = 0usize
    while i < left.len {
        if left[i] != right[i] { ret false }
        i += 1usize
    }
    ret true
}

// "12 min ago", "3 hr ago", "Yesterday", "4 days ago" from minutes.
fn ago_text(a: *mem.Arena, ago: usize) -> str {
    if ago < 1usize { ret "Just now" }
    if ago < 60usize { ret join(a, number(a, ago), " min ago", "") }
    if ago < 1440usize { ret join(a, number(a, ago / 60usize), " hr ago", "") }
    if ago < 2880usize { ret "Yesterday" }
    ret join(a, number(a, ago / 1440usize), " days ago", "")
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

fn month_short(month: usize) -> str {
    if month == 0usize { ret "Jan" }
    if month == 1usize { ret "Feb" }
    if month == 2usize { ret "Mar" }
    if month == 3usize { ret "Apr" }
    if month == 4usize { ret "May" }
    if month == 5usize { ret "Jun" }
    if month == 6usize { ret "Jul" }
    if month == 7usize { ret "Aug" }
    if month == 8usize { ret "Sep" }
    if month == 9usize { ret "Oct" }
    if month == 10usize { ret "Nov" }
    ret "Dec"
}

// "6:42 PM" from a minute of the day.
fn clock_text(a: *mem.Arena, minute: usize) -> str {
    let hour24 = minute / 60usize
    var hour12 = hour24 % 12usize
    if hour12 == 0usize { hour12 = 12usize }
    var suffix = " AM"
    if hour24 >= 12usize { suffix = " PM" }
    ret join(a, join(a, number(a, hour12), ":", two(a, minute % 60usize)), suffix, "")
}

// ----------------------------------------------------------------------------------------------
// Colours.

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

fn amber_dark() -> paint.Color {
    ret paint.Color { red: 0.78, green: 0.52, blue: 0.12, alpha: 1.0 }
}

fn soft() -> paint.Color {
    ret paint.Color { red: 0.80, green: 0.79, blue: 0.77, alpha: 1.0 }
}

fn gain() -> paint.Color {
    ret paint.Color { red: 0.45, green: 0.80, blue: 0.55, alpha: 1.0 }
}

fn loss() -> paint.Color {
    ret paint.Color { red: 0.90, green: 0.30, blue: 0.28, alpha: 1.0 }
}

fn shade(alpha: f32) -> paint.Color {
    ret paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: alpha }
}

// An earthy tone by index, for avatars and tiles.
fn tint(index: usize) -> paint.Color {
    let n = index % 6usize
    if n == 0usize { ret paint.Color { red: 0.85, green: 0.60, blue: 0.45, alpha: 1.0 } }
    if n == 1usize { ret paint.Color { red: 0.55, green: 0.72, blue: 0.62, alpha: 1.0 } }
    if n == 2usize { ret paint.Color { red: 0.60, green: 0.66, blue: 0.85, alpha: 1.0 } }
    if n == 3usize { ret paint.Color { red: 0.82, green: 0.62, blue: 0.75, alpha: 1.0 } }
    if n == 4usize { ret paint.Color { red: 0.88, green: 0.76, blue: 0.45, alpha: 1.0 } }
    ret paint.Color { red: 0.62, green: 0.78, blue: 0.80, alpha: 1.0 }
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn ground(builder: *scene.Builder, frame: usize, logical_h: f32, red: f32, green: f32, blue: f32) -> err {
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, logical_h), brush: paint.Brush { Solid: paint.Color { red: red, green: green, blue: blue, alpha: 1.0 - f32(frame % 2usize) * 0.002 } } } })
    ret ok
}

fn handle(a: *mem.Arena, builder: *scene.Builder) -> err {
    try card(a, builder, 156.0, 906.0, 100.0, 5.0, 2.5, paint.Color { red: 0.9, green: 0.9, blue: 0.92, alpha: 0.85 })
    ret ok
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

// A stroked line through the points (xs[i], ys[i]) for i below `count`, `width` thick, round ends.
fn polyline(a: *mem.Arena, builder: *scene.Builder, xs: []const f32, ys: []const f32, count: usize, width: f32, c: paint.Color) -> err {
    if count < 2usize { ret ok }
    let (pb, pb_error) = geometry.path_builder(a, count + 1usize, count + 1usize)
    if pb_error != ok { ret pb_error }
    var b = pb
    try geometry.move_to(&b, geometry.Point { x: xs[0usize], y: ys[0usize] })
    var i = 1usize
    while i < count {
        try geometry.line_to(&b, geometry.Point { x: xs[i], y: ys[i] })
        i += 1usize
    }
    let path = geometry.finish(&b)
    try scene.push(builder, scene.Command { StrokePath: scene.StrokePath { path: path, brush: paint.Brush { Solid: c }, stroke: paint.Stroke { width: width, cap: paint.StrokeCap.Round, join: paint.StrokeJoin.Round, miter_limit: 4.0 } } })
    ret ok
}

// One straight line.
fn stroke_line(a: *mem.Arena, builder: *scene.Builder, x0: f32, y0: f32, x1: f32, y1: f32, width: f32, c: paint.Color) -> err {
    let xs: [2]f32 = [2]f32{ x0, x1 }
    let ys: [2]f32 = [2]f32{ y0, y1 }
    ret polyline(a, builder, xs[0usize..2usize], ys[0usize..2usize], 2usize, width, c)
}

fn put(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, words: str, x: f32, y: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, words, x, y, 0.0, 0u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn clipped(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, words: str, x: f32, y: f32, width: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, words, x, y, width, 1u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

// Wrapped at `width`, up to `lines` lines; the box it took.
fn wrapped(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, words: str, x: f32, y: f32, width: f32, lines: u32, c: paint.Color) -> (geometry.Rect, err) {
    let (box, draw_error) = text.draw(a, builder, font, size, words, x, y, width, lines, layout.Align.Start, c)
    ret (box, draw_error)
}

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, words: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, words, cx - text.measure(a, font, size, words) / 2.0, y, c)
}

fn put_right(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, words: str, right: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, words, right - text.measure(a, font, size, words), y, c)
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

// ----------------------------------------------------------------------------------------------
// Tap targets.

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type Hits = struct { items: [96]Hit, total: usize }

fn hit(hits: *Hits, id: usize, x: f32, y: f32, w: f32, h: f32) {
    if hits.total < MAX_HITS {
        hits.items[hits.total] = Hit { id: id, x: x, y: y, w: w, h: h }
        hits.total += 1usize
    }
}

// The id of the topmost target at (x, y), or NONE.
fn hit_at(hits: *Hits, x: f32, y: f32) -> usize {
    var i = hits.total
    while i > 0usize {
        i -= 1usize
        let t = hits.items[i]
        if x >= t.x && x < t.x + t.w && y >= t.y && y < t.y + t.h { ret t.id }
    }
    ret NONE
}

fn pill(a: *mem.Arena, builder: *scene.Builder, hits: *Hits, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink())
    hit(hits, id, x, y, w, h)
    ret ok
}

// ----------------------------------------------------------------------------------------------
// The on-screen keyboard: digits, three rows of letters, a row of - / space . and Enter, from y = 500.
// Ids: letters 1000 + (a = 0), digits 1100 + (1 = 0 ... 0 = 9), space 1200, delete 1201, period 1202,
// hyphen 1203, slash 1204, enter 1205.

fn number_label(n: usize) -> str {
    if n == 0usize { ret "0" }
    if n == 1usize { ret "1" }
    if n == 2usize { ret "2" }
    if n == 3usize { ret "3" }
    if n == 4usize { ret "4" }
    if n == 5usize { ret "5" }
    if n == 6usize { ret "6" }
    if n == 7usize { ret "7" }
    if n == 8usize { ret "8" }
    ret "9"
}

fn letter_row(row: usize) -> str {
    if row == 0usize { ret "qwertyuiop" }
    if row == 1usize { ret "asdfghjkl" }
    ret "zxcvbnm"
}

fn key_cap(a: *mem.Arena, builder: *scene.Builder, hits: *Hits, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, label: str, fill: paint.Color) -> err {
    try card(a, builder, x, y + 2.0, w, 48.0, 10.0, shade(0.35))
    try card(a, builder, x, y, w, 48.0, 10.0, fill)
    try centred(a, builder, faces.grotesk, 20.0, label, x + w / 2.0, y + 24.0 - 12.0, ink())
    hit(hits, id, x, y, w, 48.0)
    ret ok
}

fn keyboard(a: *mem.Arena, builder: *scene.Builder, hits: *Hits, faces: text.Faces, enter_label: str) -> err {
    var d = 0usize
    while d < 10usize {
        try key_cap(a, builder, hits, faces, 1100usize + d, 18.0 + f32(d) * 38.0, 500.0, 34.0, number_label((d + 1usize) % 10usize), soft())
        d += 1usize
    }
    var row = 0usize
    while row < 3usize {
        let letters = letter_row(row)
        var x0: f32 = 18.0
        if row == 1usize { x0 = 37.0 }
        if row == 2usize { x0 = 18.0 + 52.0 }
        var k = 0usize
        while k < letters.len {
            let ch = usize(letters[k])
            let (one, one_error) = mem.alloc[u8](a, 1usize)
            if one_error != ok { ret one_error }
            one[0usize] = letters[k]
            try key_cap(a, builder, hits, faces, 1000usize + ch - 97usize, x0 + f32(k) * 38.0, 558.0 + f32(row) * 58.0, 34.0, one[0usize..1usize], cream())
            k += 1usize
        }
        row += 1usize
    }
    try key_cap(a, builder, hits, faces, 1201usize, 18.0 + 52.0 + 7.0 * 38.0, 558.0 + 2.0 * 58.0, 52.0, "DEL", soft())
    try key_cap(a, builder, hits, faces, 1203usize, 18.0, 732.0, 44.0, "-", soft())
    try key_cap(a, builder, hits, faces, 1204usize, 68.0, 732.0, 44.0, "/", soft())
    try key_cap(a, builder, hits, faces, 1200usize, 118.0, 732.0, 130.0, "space", cream())
    try key_cap(a, builder, hits, faces, 1202usize, 254.0, 732.0, 44.0, ".", soft())
    try key_cap(a, builder, hits, faces, 1205usize, 304.0, 732.0, 90.0, enter_label, amber())
    ret ok
}

// The character a keyboard id types, or 0 for delete, enter and anything else.
fn key_byte(id: usize) -> u8 {
    if id >= 1000usize && id < 1026usize { ret u8(97usize + id - 1000usize) }
    if id >= 1100usize && id < 1110usize { ret u8(48usize + (id - 1100usize + 1usize) % 10usize) }
    if id == 1200usize { ret 32u8 }
    if id == 1202usize { ret 46u8 }
    if id == 1203usize { ret 45u8 }
    if id == 1204usize { ret 47u8 }
    ret 0u8
}

fn is_key(id: usize) -> bool {
    ret id >= 1000usize && id <= 1205usize
}

// A text field being edited: up to 160 bytes.
type Field = struct { bytes: [160]u8, len: usize }

fn field_type(f: *Field, byte: u8, capital: bool) {
    if f.len >= 160usize { ret }
    var b = byte
    if capital && f.len == 0usize && b >= 97u8 && b <= 122u8 { b = b - 32u8 }
    f.bytes[f.len] = b
    f.len += 1usize
}

fn field_back(f: *Field) {
    if f.len > 0usize { f.len -= 1usize }
}

fn field_text(a: *mem.Arena, f: *Field) -> str {
    ret text_of(a, f.bytes[0usize..], f.len)
}

// Apply a keyboard id to a field; true if it was a typing key or delete (not enter).
fn field_key(f: *Field, id: usize, capital: bool) -> bool {
    if id == 1201usize {
        field_back(f)
        ret true
    }
    let b = key_byte(id)
    if b != 0u8 {
        field_type(f, b, capital)
        ret true
    }
    ret false
}
