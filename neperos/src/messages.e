// Messages (D2212): the app behind the Messages icon, after Google Messages -- a search pill, the
// conversations newest first (a round avatar with the initial, the name, the last message, its time, an
// unread dot and bold type), a "Start chat" button, and a conversation with a bubble per message
// (received on the left in cream, sent on the right in amber), day separators, and a compose bar whose
// field opens an on-screen keyboard. Dark ground, cream and amber, like Calc, Clock and Tasks
// (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom
// leaves the app.
// ponytail: the conversations live in this process (no storage, no network), so they are the sample
// conversations again each time the app starts; nobody answers, and there are no attachments or groups.
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
use lunar

const NONE: usize = 99usize
const MAX_CONVS: usize = 8usize
const MAX_MSGS: usize = 14usize
const MAX_TEXT: usize = 60usize
const MAX_HITS: usize = 96usize

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

// "9:41 AM" from a minute of the day.
fn clock_text(a: *mem.Arena, minute: usize) -> str {
    let hour24 = minute / 60usize
    var hour12 = hour24 % 12usize
    if hour12 == 0usize { hour12 = 12usize }
    var suffix = " AM"
    if hour24 >= 12usize { suffix = " PM" }
    var tens = ""
    if minute % 60usize < 10usize { tens = "0" }
    ret join(a, join(a, number(a, hour12), ":", tens), number(a, minute % 60usize), suffix)
}

// ----------------------------------------------------------------------------------------------
// State.

type Msg = struct { body: [60]u8, length: usize, mine: bool, day: usize, minute: usize }

type Conv = struct { name: [20]u8, name_length: usize, msgs: [14]Msg, count: usize, unread: bool, used: bool, tint: usize }

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    convs: [8]Conv,
    order: [8]usize,
    order_total: usize,
    today: usize,
    now_minutes: usize,
    // The conversation open on screen, or NONE for the list.
    open: usize,
    typing: bool,
    draft: [60]u8,
    draft_length: usize,
    next_contact: usize,
    hits: [96]Hit,
    hit_total: usize,
}

// The minute since the epoch now, never earlier than three days in (so a sample "yesterday" exists
// even when the clock reads zero).
fn now_minutes() -> usize {
    var minutes = 0usize
    let (wall, wall_error) = time.now()
    if wall_error == ok { minutes = usize(wall.nanos / 1000000000i64) / 60usize }
    if minutes < 4320usize { minutes = 4320usize }
    ret minutes
}

fn conv_name(a: *mem.Arena, s: *State, c: usize) -> str {
    ret text_of(a, s.convs[c].name[0usize..], s.convs[c].name_length)
}

fn append_msg(s: *State, c: usize, body: str, mine: bool, ago: usize) {
    if s.convs[c].count == MAX_MSGS {
        var k = 1usize
        while k < MAX_MSGS {
            s.convs[c].msgs[k - 1usize] = s.convs[c].msgs[k]
            k += 1usize
        }
        s.convs[c].count -= 1usize
    }
    let at = s.convs[c].count
    var m: Msg = zero
    var i = 0usize
    while i < body.len && i < MAX_TEXT {
        m.body[i] = body[i]
        i += 1usize
    }
    m.length = i
    m.mine = mine
    let stamp = s.now_minutes - ago
    m.day = stamp / 1440usize
    m.minute = stamp % 1440usize
    s.convs[c].msgs[at] = m
    s.convs[c].count = at + 1usize
}

// A new conversation at the end of the list; NONE when all are in use.
fn add_conv(s: *State, name: str, unread: bool) -> usize {
    var c = 0usize
    while c < MAX_CONVS {
        if !s.convs[c].used {
            var conv: Conv = zero
            var i = 0usize
            while i < name.len && i < 20usize {
                conv.name[i] = name[i]
                i += 1usize
            }
            conv.name_length = i
            conv.unread = unread
            conv.used = true
            conv.tint = c
            s.convs[c] = conv
            s.order[s.order_total] = c
            s.order_total += 1usize
            ret c
        }
        c += 1usize
    }
    ret NONE
}

// Move conversation `c` to the top of the list.
fn to_front(s: *State, c: usize) {
    var at = 0usize
    while at < s.order_total && s.order[at] != c { at += 1usize }
    if at == s.order_total { ret }
    while at > 0usize {
        s.order[at] = s.order[at - 1usize]
        at -= 1usize
    }
    s.order[0usize] = c
}

fn remove_conv(s: *State, c: usize) {
    var at = 0usize
    while at < s.order_total && s.order[at] != c { at += 1usize }
    if at < s.order_total {
        while at + 1usize < s.order_total {
            s.order[at] = s.order[at + 1usize]
            at += 1usize
        }
        s.order_total -= 1usize
    }
    s.convs[c].used = false
}

fn total_messages(s: *State) -> usize {
    var n = 0usize
    var c = 0usize
    while c < MAX_CONVS {
        if s.convs[c].used { n += s.convs[c].count }
        c += 1usize
    }
    ret n
}

// "9:41 AM" today, "Yesterday", or "Oct 5".
fn when_text(a: *mem.Arena, s: *State, day: usize, minute: usize) -> str {
    if day == s.today { ret clock_text(a, minute) }
    if day + 1usize == s.today { ret "Yesterday" }
    let (month, date) = lunar.month_day(day * 86400usize)
    ret join(a, month_short(month), " ", number(a, date))
}

// The day separator in a conversation: Today, Yesterday, or "Mon, Oct 5".
fn day_text(a: *mem.Arena, s: *State, day: usize) -> str {
    if day == s.today { ret "Today" }
    if day + 1usize == s.today { ret "Yesterday" }
    let (month, date) = lunar.month_day(day * 86400usize)
    let weekday = (day + 3usize) % 7usize
    ret join(a, weekday_short(weekday), ", ", join(a, month_short(month), " ", number(a, date)))
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

// The avatar colours: earthy tones, one per conversation slot.
fn tint_of(index: usize) -> paint.Color {
    let n = index % 6usize
    if n == 0usize { ret paint.Color { red: 0.85, green: 0.60, blue: 0.45, alpha: 1.0 } }
    if n == 1usize { ret paint.Color { red: 0.55, green: 0.72, blue: 0.62, alpha: 1.0 } }
    if n == 2usize { ret paint.Color { red: 0.60, green: 0.66, blue: 0.85, alpha: 1.0 } }
    if n == 3usize { ret paint.Color { red: 0.82, green: 0.62, blue: 0.75, alpha: 1.0 } }
    if n == 4usize { ret paint.Color { red: 0.88, green: 0.76, blue: 0.45, alpha: 1.0 } }
    ret paint.Color { red: 0.62, green: 0.78, blue: 0.80, alpha: 1.0 }
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

// A message body, wrapped at the bubble's width.
fn wrapped(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, x: f32, y: f32, c: paint.Color) -> err {
    let (box, draw_error) = text.draw(a, builder, font, size, line, x, y, 240.0, 0u32, layout.Align.Start, c)
    if draw_error != ok { ret draw_error }
    ret ok
}

fn centred(a: *mem.Arena, builder: *scene.Builder, font: shape.Font, size: f32, line: str, cx: f32, y: f32, c: paint.Color) -> err {
    ret put(a, builder, font, size, line, cx - text.measure(a, font, size, line) / 2.0, y, c)
}

fn search_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><circle cx='10.5' cy='10.5' r='6.5' fill='none' stroke='currentColor' stroke-width='2.4'/><path d='M15.5 15.5L21 21' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round'/></svg>"
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn send_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M3 11.5L21 3l-6.5 18-3-7.5z' fill='currentColor' stroke='currentColor' stroke-width='1.6' stroke-linejoin='round'/></svg>"
}

// A round avatar with the initial of `name`.
fn avatar(a: *mem.Arena, builder: *scene.Builder, faces: text.Faces, cx: f32, cy: f32, radius: f32, name: str, tint: usize) -> err {
    try disc(a, builder, cx, cy, radius, tint_of(tint))
    if name.len > 0usize {
        let (one, one_error) = mem.alloc[u8](a, 1usize)
        if one_error != ok { ret one_error }
        one[0usize] = name[0usize]
        try centred(a, builder, faces.jost_bold, radius * 0.95, one[0usize..1usize], cx, cy - radius * 0.62, ink())
    }
    ret ok
}

// ---- the keyboard (the same as Tasks'): digits, three rows of letters, space.

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

fn key_cap(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, label: str, fill: paint.Color) -> err {
    try card(a, builder, x, y + 2.0, w, 48.0, 10.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.35 })
    try card(a, builder, x, y, w, 48.0, 10.0, fill)
    try centred(a, builder, faces.grotesk, 20.0, label, x + w / 2.0, y + 24.0 - 12.0, ink())
    hit(s, id, x, y, w, 48.0)
    ret ok
}

fn draw_keyboard(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var d = 0usize
    while d < 10usize {
        try key_cap(a, builder, s, faces, 1100usize + d, 18.0 + f32(d) * 38.0, 500.0, 34.0, number_label((d + 1usize) % 10usize), soft())
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
            try key_cap(a, builder, s, faces, 1000usize + ch - 97usize, x0 + f32(k) * 38.0, 558.0 + f32(row) * 58.0, 34.0, one[0usize..1usize], cream())
            k += 1usize
        }
        row += 1usize
    }
    try key_cap(a, builder, s, faces, 1201usize, 18.0 + 52.0 + 7.0 * 38.0, 558.0 + 2.0 * 58.0, 52.0, "DEL", soft())
    try key_cap(a, builder, s, faces, 1203usize, 18.0, 732.0, 50.0, ",", soft())
    try key_cap(a, builder, s, faces, 1200usize, 76.0, 732.0, 228.0, "space", cream())
    try key_cap(a, builder, s, faces, 1202usize, 312.0, 732.0, 50.0, ".", soft())
    ret ok
}

// ---- the list of conversations.

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    // The search pill, with the account's avatar at its end.
    try card(a, builder, 16.0, 24.0, 380.0, 52.0, 26.0, cream())
    try svg.draw(a, builder, search_icon(), geometry.rect(32.0, 38.0, 24.0, 24.0), muted())
    try put(a, builder, faces.jost, 17.0, "Search conversations", 66.0, 40.0, muted())
    try avatar(a, builder, faces, 370.0, 50.0, 18.0, "N", 4usize)
    var pos = 0usize
    while pos < s.order_total {
        let c = s.order[pos]
        let y: f32 = 96.0 + f32(pos) * 84.0
        let name = conv_name(a, s, c)
        try avatar(a, builder, faces, 44.0, y + 42.0, 26.0, name, s.convs[c].tint)
        var name_face = faces.jost
        var name_color = light()
        var snippet_color = light_muted()
        var when_color = light_muted()
        if s.convs[c].unread {
            name_face = faces.jost_bold
            snippet_color = light()
            when_color = amber()
        }
        try clipped(a, builder, name_face, 19.0, name, 84.0, y + 14.0, 230.0, name_color)
        var snippet = "No messages yet"
        var stamp = ""
        let last = s.convs[c].count
        if last > 0usize {
            let m = s.convs[c].msgs[last - 1usize]
            snippet = text_of(a, m.body[0usize..], m.length)
            if m.mine { snippet = join(a, "You: ", snippet, "") }
            stamp = when_text(a, s, m.day, m.minute)
        }
        try clipped(a, builder, faces.exo, 15.0, snippet, 84.0, y + 42.0, 262.0, snippet_color)
        try put(a, builder, faces.grotesk, 12.0, stamp, 396.0 - text.measure(a, faces.grotesk, 12.0, stamp), y + 16.0, when_color)
        if s.convs[c].unread { try disc(a, builder, 386.0, y + 56.0, 5.0, amber()) }
        hit(s, 100usize + pos, 0.0, y, 412.0, 84.0)
        pos += 1usize
    }
    // Start chat.
    try card(a, builder, 228.0, 780.0, 168.0, 56.0, 28.0, amber())
    try card(a, builder, 250.0 - 9.0, 808.0 - 1.5, 18.0, 3.0, 1.5, ink())
    try card(a, builder, 250.0 - 1.5, 808.0 - 9.0, 3.0, 18.0, 1.5, ink())
    try put(a, builder, faces.jost, 17.0, "Start chat", 276.0, 797.0, ink())
    hit(s, 150usize, 228.0, 780.0, 168.0, 56.0)
    ret ok
}

// ---- a conversation.

fn bubble_size(a: *mem.Arena, faces: text.Faces, line: str) -> (f32, f32) {
    var w: f32 = 60.0
    var h: f32 = 24.0
    let (placed, placed_error) = text.lay_out(a, faces.jost, 17.0, line, 240.0, 0u32, layout.Align.Start)
    if placed_error == ok {
        w = placed.bounds.width
        h = placed.bounds.height
    }
    ret (w, h)
}

fn draw_chat(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let c = s.open
    let name = conv_name(a, s, c)
    // The top bar.
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 36.0, 28.0, 28.0), light())
    hit(s, 500usize, 0.0, 20.0, 66.0, 60.0)
    try avatar(a, builder, faces, 84.0, 50.0, 20.0, name, s.convs[c].tint)
    try put(a, builder, faces.jost, 21.0, name, 116.0, 36.0, light())
    // The compose bar rides above the keyboard while typing.
    var compose_y: f32 = 826.0
    if s.typing { compose_y = 432.0 }
    // Tapping the messages puts the keyboard away.
    if s.typing { hit(s, 530usize, 0.0, 84.0, 412.0, compose_y - 84.0) }
    // The messages, newest at the bottom.
    var y: f32 = compose_y - 12.0
    var m = s.convs[c].count
    var room = true
    if m == 0usize {
        try centred(a, builder, faces.jost, 19.0, join(a, "Say hi to ", name, ""), 206.0, 230.0, light_muted())
    }
    while room && m > 0usize {
        m -= 1usize
        let msg = s.convs[c].msgs[m]
        let line = text_of(a, msg.body[0usize..], msg.length)
        let (bw, bh) = bubble_size(a, faces, line)
        let w = bw + 28.0
        let h = bh + 18.0
        y -= h
        if y < 84.0 {
            room = false
        } else {
            if msg.mine {
                try card(a, builder, 396.0 - w, y, w, h, 18.0, amber())
                try wrapped(a, builder, faces.jost, 17.0, line, 396.0 - w + 14.0, y + 9.0, ink())
            } else {
                try card(a, builder, 16.0, y, w, h, 18.0, cream())
                try wrapped(a, builder, faces.jost, 17.0, line, 30.0, y + 9.0, ink())
            }
            y -= 8.0
            if m == 0usize || s.convs[c].msgs[m - 1usize].day != msg.day {
                y -= 26.0
                if y >= 80.0 { try centred(a, builder, faces.grotesk, 13.0, day_text(a, s, msg.day), 206.0, y + 6.0, light_muted()) }
            }
        }
    }
    // The compose bar.
    try card(a, builder, 16.0, compose_y, 322.0, 52.0, 26.0, cream())
    if s.draft_length == 0usize {
        try put(a, builder, faces.jost, 17.0, "Text message", 34.0, compose_y + 15.0, muted())
    } else {
        try clipped(a, builder, faces.jost, 17.0, text_of(a, s.draft[0usize..], s.draft_length), 34.0, compose_y + 15.0, 290.0, ink())
    }
    if s.typing {
        var caret_x: f32 = 34.0
        if s.draft_length > 0usize { caret_x = 34.0 + text.measure(a, faces.jost, 17.0, text_of(a, s.draft[0usize..], s.draft_length)) + 2.0 }
        if caret_x > 326.0 { caret_x = 326.0 }
        try card(a, builder, caret_x, compose_y + 13.0, 2.0, 26.0, 1.0, amber())
    }
    hit(s, 510usize, 16.0, compose_y, 322.0, 52.0)
    var send_fill = soft()
    if s.draft_length > 0usize { send_fill = amber() }
    try disc(a, builder, 372.0, compose_y + 26.0, 26.0, send_fill)
    try svg.draw(a, builder, send_icon(), geometry.rect(360.0, compose_y + 14.0, 24.0, 24.0), ink())
    hit(s, 520usize, 344.0, compose_y, 56.0, 52.0)
    if s.typing { try draw_keyboard(a, builder, s, faces) }
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.open == NONE {
        try draw_list(a, builder, s, faces)
    } else {
        try draw_chat(a, builder, s, faces)
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

fn type_key(s: *State, byte: u8) {
    if s.draft_length >= MAX_TEXT { ret }
    var b = byte
    // The first letter of a message is a capital.
    if s.draft_length == 0usize && b >= 97u8 && b <= 122u8 { b = b - 32u8 }
    s.draft[s.draft_length] = b
    s.draft_length += 1usize
}

fn open_conv(s: *State, c: usize, typing: bool) {
    s.open = c
    s.typing = typing
    s.draft_length = 0usize
    s.convs[c].unread = false
}

// The conversation is left: one that never got a message is dropped.
fn close_conv(s: *State) {
    if s.convs[s.open].count == 0usize { remove_conv(s, s.open) }
    s.open = NONE
    s.typing = false
    s.draft_length = 0usize
}

fn send(s: *State) {
    let c = s.open
    let draft = s.draft[0usize..s.draft_length]
    s.now_minutes = now_minutes()
    s.today = s.now_minutes / 1440usize
    append_msg(s, c, draft, true, 0usize)
    s.draft_length = 0usize
    to_front(s, c)
    say("messages sent\n")
}

fn new_chat(s: *State) -> bool {
    var name = "Jordan Lee"
    let which = s.next_contact % 5usize
    if which == 1usize { name = "Nora Weiss" }
    if which == 2usize { name = "Taylor Kim" }
    if which == 3usize { name = "Eli Brooks" }
    if which == 4usize { name = "Zoe Park" }
    let c = add_conv(s, name, false)
    if c == NONE { ret false }
    s.next_contact += 1usize
    to_front(s, c)
    open_conv(s, c, true)
    say("messages new chat\n")
    ret true
}

// What a tap on button `id` did: true when the screen changed.
fn act(s: *State, id: usize) -> bool {
    if s.open == NONE {
        if id >= 100usize && id < 108usize {
            let pos = id - 100usize
            if pos < s.order_total {
                open_conv(s, s.order[pos], false)
                say("messages opened\n")
                ret true
            }
            ret false
        }
        if id == 150usize { ret new_chat(s) }
        ret false
    }
    if id == 500usize {
        close_conv(s)
        ret true
    }
    if id == 510usize {
        s.typing = true
        ret true
    }
    if id == 530usize {
        s.typing = false
        ret true
    }
    if id == 520usize {
        if s.draft_length > 0usize { send(s) }
        ret true
    }
    if id >= 1000usize && id < 1026usize {
        type_key(s, u8(97usize + id - 1000usize))
        ret true
    }
    if id >= 1100usize && id < 1110usize {
        type_key(s, u8(48usize + (id - 1100usize + 1usize) % 10usize))
        ret true
    }
    if id == 1200usize {
        if s.draft_length > 0usize { type_key(s, 32u8) }
        ret true
    }
    if id == 1201usize {
        if s.draft_length > 0usize { s.draft_length -= 1usize }
        ret true
    }
    if id == 1202usize {
        type_key(s, 46u8)
        ret true
    }
    if id == 1203usize {
        type_key(s, 44u8)
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
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "messages")
    if kit_error != ok {
        say("messages open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("messages fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.now_minutes = now_minutes()
    s.today = s.now_minutes / 1440usize
    s.open = NONE
    // The conversations it starts with, newest first.
    let c1 = add_conv(&s, "Maya Chen", true)
    append_msg(&s, c1, "Are we still on for lunch?", false, 190usize)
    append_msg(&s, c1, "Yes! 12:30 at the usual place", true, 180usize)
    append_msg(&s, c1, "Perfect, see you there", false, 14usize)
    let c2 = add_conv(&s, "Alex Rivera", true)
    append_msg(&s, c2, "Did you see the build is green?", false, 45usize)
    let c3 = add_conv(&s, "Dad", false)
    append_msg(&s, c3, "Call me when you land", false, 1500usize)
    append_msg(&s, c3, "Landed. Calling now", true, 1490usize)
    let c4 = add_conv(&s, "Priya", false)
    append_msg(&s, c4, "Thanks for the notes", true, 3000usize)
    append_msg(&s, c4, "Anytime!", false, 2990usize)
    let c5 = add_conv(&s, "City Library", false)
    append_msg(&s, c5, "Your hold is ready for pickup", false, 5000usize)
    let c6 = add_conv(&s, "Sam", false)
    append_msg(&s, c6, "Happy birthday!", true, 8000usize)
    append_msg(&s, c6, "Thank you!!", false, 7990usize)
    if !show(a, &kit, &s) {
        say("messages present failed\n")
        ret ok
    }
    say("messages shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("messages home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    say("messages present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
                say("messages count ")
                say_num(total_messages(&s))
                say("\n")
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
