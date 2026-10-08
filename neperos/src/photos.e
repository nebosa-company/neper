// Photos (D2218): the app behind the Photos icon, after Google Photos -- a grid of pictures in four
// columns under day headings (Today, Yesterday, a date), three tabs (Photos, Albums, Favorites), albums
// as cards with a cover, and a viewer with a heart, details (name, date, time, size, size in pixels,
// album), previous and next, and delete. Dark ground, cream cards and amber, like the other apps
// (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom
// leaves the app. The grid scrolls with the two arrow buttons.
// ponytail: the pictures are SAMPLE scenes (scenes.e, the same ones the Camera draws), twenty of them
// with made-up dates, in this process; the Camera's captures do not arrive here, and there are no
// files, backups, sharing or editing. Real photo files and the Camera hand-over are C122; the library
// of files behind it is the Files app's.
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
use scenes
use lunar

const NONE: usize = 99usize
const MAX_PHOTOS: usize = 24usize
const MAX_HITS: usize = 96usize
const GRID_SCREEN: usize = 0usize
const ALBUMS_SCREEN: usize = 1usize
const VIEW_SCREEN: usize = 2usize
const ALBUMS: usize = 4usize

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
    var tens = ""
    if minute % 60usize < 10usize { tens = "0" }
    ret join(a, join(a, number(a, hour12), ":", tens), number(a, minute % 60usize), suffix)
}

fn album_name(album: usize) -> str {
    if album == 0usize { ret "Camera" }
    if album == 1usize { ret "Trips" }
    if album == 2usize { ret "Family" }
    ret "Documents"
}

// ----------------------------------------------------------------------------------------------
// State.

type Photo = struct { kind: usize, seed: usize, days_ago: usize, minute: usize, album: usize, favorite: bool, used: bool }

type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    photos: [24]Photo,
    today: usize,
    tab: usize,
    screen: usize,
    album_open: usize,
    list: [24]usize,
    list_total: usize,
    view: usize,
    info: bool,
    scroll: f32,
    content: f32,
    hits: [96]Hit,
    hit_total: usize,
}

fn add_photo(s: *State, kind: usize, seed: usize, days_ago: usize, minute: usize, album: usize, favorite: bool) {
    var i = 0usize
    while i < MAX_PHOTOS {
        if !s.photos[i].used {
            s.photos[i] = Photo { kind: kind, seed: seed, days_ago: days_ago, minute: minute, album: album, favorite: favorite, used: true }
            ret
        }
        i += 1usize
    }
}

// The pictures the current view lists, newest first: all of them, the favorites, or one album's.
fn build_list(s: *State) {
    s.list_total = 0usize
    var i = 0usize
    while i < MAX_PHOTOS {
        let p = s.photos[i]
        if p.used {
            var keep = true
            if s.tab == 2usize && !p.favorite { keep = false }
            if s.album_open != NONE && p.album != s.album_open { keep = false }
            if keep {
                s.list[s.list_total] = i
                s.list_total += 1usize
            }
        }
        i += 1usize
    }
}

fn album_count(s: *State, album: usize) -> usize {
    var n = 0usize
    var i = 0usize
    while i < MAX_PHOTOS {
        if s.photos[i].used && s.photos[i].album == album { n += 1usize }
        i += 1usize
    }
    ret n
}

// The first picture of an album, for its cover; NONE for an empty one.
fn album_cover(s: *State, album: usize) -> usize {
    var i = 0usize
    while i < MAX_PHOTOS {
        if s.photos[i].used && s.photos[i].album == album { ret i }
        i += 1usize
    }
    ret NONE
}

// "Today", "Yesterday" or "Mon, Oct 5".
fn day_text(a: *mem.Arena, s: *State, days_ago: usize) -> str {
    if days_ago == 0usize { ret "Today" }
    if days_ago == 1usize { ret "Yesterday" }
    let day = s.today - days_ago
    let (month, date) = lunar.month_day(day * 86400usize)
    ret join(a, join(a, weekday_short((day + 3usize) % 7usize), ", ", month_short(month)), " ", number(a, date))
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

fn panel() -> paint.Color {
    ret paint.Color { red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0 }
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

fn pill(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink())
    hit(s, id, x, y, w, h)
    ret ok
}

// A picture drawn inside its own rectangle: nothing of the scene shows outside it.
fn picture(a: *mem.Arena, builder: *scene.Builder, doc: str, r: geometry.Rect, c: paint.Color) -> err {
    let save: scene.Command = .Save
    try scene.push(builder, save)
    try scene.push(builder, scene.Command { Clip: scene.Clip { Rect: r } })
    try svg.draw(a, builder, doc, r, c)
    let restore: scene.Command = .Restore
    try scene.push(builder, restore)
    ret ok
}

fn back_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M20 12H5M11 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn heart_icon(filled: bool) -> str {
    if filled { ret "<svg viewBox='0 0 24 24'><path d='M12 21C5 15.5 2.5 12 2.5 8.5A4.8 4.8 0 0 1 12 6.6 4.8 4.8 0 0 1 21.5 8.5C21.5 12 19 15.5 12 21z' fill='currentColor'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M12 21C5 15.5 2.5 12 2.5 8.5A4.8 4.8 0 0 1 12 6.6 4.8 4.8 0 0 1 21.5 8.5C21.5 12 19 15.5 12 21z' fill='none' stroke='currentColor' stroke-width='2'/></svg>"
}

fn photos_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><rect x='3' y='4' width='18' height='16' rx='3' fill='none' stroke='currentColor' stroke-width='2'/><path d='M5 17l5-6 4 4 2-2 3 4' fill='none' stroke='currentColor' stroke-width='2' stroke-linejoin='round'/></svg>"
}

fn albums_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><rect x='3' y='3' width='8' height='8' rx='2' fill='currentColor'/><rect x='13' y='3' width='8' height='8' rx='2' fill='currentColor'/><rect x='3' y='13' width='8' height='8' rx='2' fill='currentColor'/><rect x='13' y='13' width='8' height='8' rx='2' fill='currentColor'/></svg>"
}

fn chevron_icon(up: bool) -> str {
    if up { ret "<svg viewBox='0 0 24 24'><path d='M6 15l6-6 6 6' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M6 9l6 6 6-6' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn left_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M15 5l-7 7 7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn right_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M9 5l7 7-7 7' fill='none' stroke='currentColor' stroke-width='2.6' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

// The bottom tabs: Photos, Albums, Favorites.
fn draw_tabs(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try card(a, builder, 0.0, 828.0, 412.0, 68.0, 0.0, panel())
    var tab = 0usize
    while tab < 3usize {
        var label = "Photos"
        if tab == 1usize { label = "Albums" }
        if tab == 2usize { label = "Favorites" }
        var tone = light_muted()
        if tab == s.tab && s.album_open == NONE { tone = amber() }
        let cx: f32 = 68.0 + f32(tab) * 138.0
        if tab == 0usize { try svg.draw(a, builder, photos_icon(), geometry.rect(cx - 12.0, 836.0, 24.0, 24.0), tone) }
        if tab == 1usize { try svg.draw(a, builder, albums_icon(), geometry.rect(cx - 12.0, 836.0, 24.0, 24.0), tone) }
        if tab == 2usize { try svg.draw(a, builder, heart_icon(tab == s.tab), geometry.rect(cx - 12.0, 836.0, 24.0, 24.0), tone) }
        try centred(a, builder, faces.jost, 13.0, label, cx, 866.0, tone)
        hit(s, 100usize + tab, cx - 68.0, 828.0, 136.0, 68.0)
        tab += 1usize
    }
    ret ok
}

// The grid: day headings and four columns of pictures, shifted up by the scroll.
fn draw_grid(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    build_list(s)
    var title = "Photos"
    if s.tab == 2usize { title = "Favorites" }
    if s.album_open != NONE {
        title = album_name(s.album_open)
        try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 28.0, 28.0, 28.0), light())
        hit(s, 500usize, 0.0, 14.0, 66.0, 56.0)
        try put(a, builder, faces.jost_bold, 28.0, title, 62.0, 22.0, light())
    } else {
        try put(a, builder, faces.jost_bold, 30.0, title, 20.0, 22.0, light())
        try disc(a, builder, 374.0, 42.0, 18.0, amber())
        try centred(a, builder, faces.jost_bold, 17.0, "N", 374.0, 31.0, ink())
    }
    var y: f32 = 92.0 - s.scroll
    var column = 0usize
    var last_day = 9999usize
    var pos = 0usize
    while pos < s.list_total {
        let index = s.list[pos]
        let p = s.photos[index]
        if p.days_ago != last_day {
            // A new day starts a new heading and a new row.
            if column != 0usize { y += 100.0 }
            column = 0usize
            if y >= 84.0 && y + 130.0 <= 826.0 { try put(a, builder, faces.jost, 15.0, day_text(a, s, p.days_ago), 12.0, y + 2.0, light_muted()) }
            y += 30.0
            last_day = p.days_ago
        }
        let x: f32 = 7.0 + f32(column) * 100.0
        if y >= 84.0 && y + 97.0 <= 826.0 {
            try picture(a, builder, scenes.scene_svg(a, p.kind, p.seed, 4usize, false, 97usize, 97usize), geometry.rect(x, y, 97.0, 97.0), light())
            if p.favorite { try svg.draw(a, builder, heart_icon(true), geometry.rect(x + 71.0, y + 71.0, 20.0, 20.0), amber()) }
            hit(s, 200usize + index, x, y, 97.0, 97.0)
        }
        column += 1usize
        if column == 4usize {
            column = 0usize
            y += 100.0
        }
        pos += 1usize
    }
    if column != 0usize { y += 100.0 }
    s.content = y + s.scroll - 92.0
    if s.list_total == 0usize {
        try centred(a, builder, faces.jost, 19.0, "Nothing here yet", 206.0, 300.0, light_muted())
    }
    // The scroll arrows, when the content is longer than the screen.
    if s.content > 734.0 {
        if s.scroll > 0.0 {
            try disc(a, builder, 380.0, 120.0, 20.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6 })
            try svg.draw(a, builder, chevron_icon(true), geometry.rect(368.0, 108.0, 24.0, 24.0), light())
            hit(s, 800usize, 356.0, 96.0, 48.0, 48.0)
        }
        if s.scroll + 734.0 < s.content {
            try disc(a, builder, 380.0, 786.0, 20.0, paint.Color { red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6 })
            try svg.draw(a, builder, chevron_icon(false), geometry.rect(368.0, 774.0, 24.0, 24.0), light())
            hit(s, 801usize, 356.0, 762.0, 48.0, 48.0)
        }
    }
    try draw_tabs(a, builder, s, faces)
    ret ok
}

fn draw_albums(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try put(a, builder, faces.jost_bold, 30.0, "Albums", 20.0, 22.0, light())
    var album = 0usize
    while album < ALBUMS {
        let x: f32 = 16.0 + f32(album % 2usize) * 198.0
        let y: f32 = 96.0 + f32(album / 2usize) * 220.0
        try card(a, builder, x, y, 190.0, 206.0, 18.0, cream())
        let cover = album_cover(s, album)
        if cover != NONE {
            let p = s.photos[cover]
            try picture(a, builder, scenes.scene_svg(a, p.kind, p.seed, 5usize, false, 190usize, 150usize), geometry.rect(x, y, 190.0, 150.0), light())
        }
        try put(a, builder, faces.jost, 17.0, album_name(album), x + 14.0, y + 158.0, ink())
        try put(a, builder, faces.grotesk, 13.0, join(a, number(a, album_count(s, album)), " items", ""), x + 14.0, y + 182.0, muted())
        hit(s, 300usize + album, x, y, 190.0, 206.0)
        album += 1usize
    }
    try draw_tabs(a, builder, s, faces)
    ret ok
}

fn draw_view(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    let index = s.list[s.view]
    let p = s.photos[index]
    try picture(a, builder, scenes.scene_svg(a, p.kind, p.seed, 1usize, false, 412usize, 560usize), geometry.rect(0.0, 84.0, 412.0, 560.0), light())
    try card(a, builder, 0.0, 0.0, 412.0, 84.0, 0.0, paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 })
    try svg.draw(a, builder, back_icon(), geometry.rect(18.0, 28.0, 28.0, 28.0), light())
    hit(s, 500usize, 0.0, 14.0, 66.0, 56.0)
    try centred(a, builder, faces.jost, 18.0, join(a, join(a, number(a, s.view + 1usize), " of ", number(a, s.list_total)), "", ""), 206.0, 30.0, light())
    var heart_tone = light()
    if p.favorite { heart_tone = amber() }
    try svg.draw(a, builder, heart_icon(p.favorite), geometry.rect(360.0, 28.0, 28.0, 28.0), heart_tone)
    hit(s, 510usize, 340.0, 14.0, 66.0, 56.0)
    // The details sheet over the picture.
    if s.info {
        try card(a, builder, 16.0, 380.0, 380.0, 252.0, 20.0, cream())
        let name = join(a, "IMG_", number(a, 3000usize + index * 17usize), ".jpg")
        var row = 0usize
        while row < 6usize {
            var label = "Name"
            var value = name
            if row == 1usize {
                label = "Date"
                value = day_text(a, s, p.days_ago)
            }
            if row == 2usize {
                label = "Time"
                value = clock_text(a, p.minute)
            }
            if row == 3usize {
                label = "Size"
                value = join(a, join(a, number(a, 2usize + p.seed % 4usize), ".", number(a, (p.seed * 7usize) % 10usize)), " MB", "")
            }
            if row == 4usize {
                label = "Pixels"
                value = "4032 x 3024"
            }
            if row == 5usize {
                label = "Album"
                value = album_name(p.album)
            }
            let y: f32 = 394.0 + f32(row) * 38.0
            try put(a, builder, faces.grotesk, 13.0, label, 36.0, y + 6.0, muted())
            try put_right(a, builder, faces.jost, 17.0, value, 376.0, y + 3.0, ink())
            row += 1usize
        }
    }
    // The bar under the picture: previous, details, delete, next.
    try card(a, builder, 0.0, 644.0, 412.0, 275.0, 0.0, paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 })
    try put(a, builder, faces.jost, 18.0, join(a, "IMG_", number(a, 3000usize + index * 17usize), ".jpg"), 24.0, 662.0, light())
    try put(a, builder, faces.grotesk, 13.0, join(a, join(a, day_text(a, s, p.days_ago), "  ", clock_text(a, p.minute)), "", ""), 24.0, 690.0, light_muted())
    try disc(a, builder, 56.0, 770.0, 26.0, paint.Color { red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0 })
    try svg.draw(a, builder, left_icon(), geometry.rect(42.0, 756.0, 28.0, 28.0), light())
    hit(s, 600usize, 24.0, 740.0, 64.0, 64.0)
    try disc(a, builder, 356.0, 770.0, 26.0, paint.Color { red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0 })
    try svg.draw(a, builder, right_icon(), geometry.rect(342.0, 756.0, 28.0, 28.0), light())
    hit(s, 601usize, 324.0, 740.0, 64.0, 64.0)
    var info_fill = soft()
    if s.info { info_fill = amber() }
    try pill(a, builder, s, faces, 610usize, 112.0, 748.0, 84.0, 44.0, "Details", info_fill, 15.0)
    try pill(a, builder, s, faces, 620usize, 204.0, 748.0, 84.0, 44.0, "Delete", soft(), 15.0)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.02, green: 0.02, blue: 0.03, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.screen == GRID_SCREEN {
        try draw_grid(a, builder, s, faces)
    } else if s.screen == ALBUMS_SCREEN {
        try draw_albums(a, builder, s, faces)
    } else {
        try draw_view(a, builder, s, faces)
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

fn remove_photo(s: *State, index: usize) {
    s.photos[index].used = false
}

// What a tap on button `id` did: true when the screen changed.
fn act(s: *State, id: usize) -> bool {
    if s.screen == VIEW_SCREEN {
        if id == 500usize {
            s.screen = GRID_SCREEN
            s.info = false
            say("photos back\n")
            ret true
        }
        if id == 510usize {
            let index = s.list[s.view]
            s.photos[index].favorite = !s.photos[index].favorite
            if s.photos[index].favorite { say("photos favorite on\n") } else { say("photos favorite off\n") }
            ret true
        }
        if id == 600usize {
            if s.view > 0usize { s.view -= 1usize }
            ret true
        }
        if id == 601usize {
            if s.view + 1usize < s.list_total { s.view += 1usize }
            ret true
        }
        if id == 610usize {
            s.info = !s.info
            say("photos details\n")
            ret true
        }
        if id == 620usize {
            remove_photo(s, s.list[s.view])
            say("photos deleted\n")
            build_list(s)
            if s.list_total == 0usize {
                s.screen = GRID_SCREEN
            } else if s.view >= s.list_total {
                s.view = s.list_total - 1usize
            }
            ret true
        }
        ret false
    }
    // The tabs, on the grid and the albums.
    if id >= 100usize && id < 103usize {
        s.tab = id - 100usize
        s.album_open = NONE
        s.scroll = 0.0
        if s.tab == 1usize { s.screen = ALBUMS_SCREEN } else { s.screen = GRID_SCREEN }
        if s.tab == 1usize { say("photos tab Albums\n") }
        if s.tab == 0usize { say("photos tab Photos\n") }
        if s.tab == 2usize { say("photos tab Favorites\n") }
        ret true
    }
    if s.screen == ALBUMS_SCREEN {
        if id >= 300usize && id < 300usize + ALBUMS {
            s.album_open = id - 300usize
            s.tab = 0usize
            s.screen = GRID_SCREEN
            s.scroll = 0.0
            say("photos album ")
            say(album_name(s.album_open))
            say("\n")
            ret true
        }
        ret false
    }
    if id == 500usize {
        s.album_open = NONE
        s.screen = ALBUMS_SCREEN
        s.tab = 1usize
        s.scroll = 0.0
        ret true
    }
    if id == 800usize {
        s.scroll -= 300.0
        if s.scroll < 0.0 { s.scroll = 0.0 }
        ret true
    }
    if id == 801usize {
        s.scroll += 300.0
        ret true
    }
    if id >= 200usize && id < 200usize + MAX_PHOTOS {
        build_list(s)
        var pos = 0usize
        while pos < s.list_total && s.list[pos] != id - 200usize { pos += 1usize }
        if pos < s.list_total {
            s.view = pos
            s.screen = VIEW_SCREEN
            s.info = false
            say("photos opened ")
            say_num(pos + 1usize)
            say("\n")
            ret true
        }
        ret false
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
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "photos")
    if kit_error != ok {
        say("photos open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("photos fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.album_open = NONE
    let (wall, wall_error) = time.now()
    if wall_error == ok { s.today = usize(wall.nanos / 1000000000i64) / 86400usize }
    if s.today < 40usize { s.today = 40usize }
    // Twenty sample pictures, newest first, over two weeks.
    let days: [20]usize = [20]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 2usize, 2usize, 3usize, 3usize, 5usize, 5usize, 5usize, 8usize, 8usize, 9usize, 12usize, 12usize, 12usize, 14usize }
    var i = 0usize
    while i < 20usize {
        let kind = i % 6usize
        var album = 1usize
        if kind == 0usize { album = 0usize }
        if kind == 1usize { album = 2usize }
        if kind == 2usize { album = 3usize }
        add_photo(&s, kind, 3usize + i * 7usize, days[i], (i * 137usize + 400usize) % 1440usize, album, i % 5usize == 1usize)
        i += 1usize
    }
    if !show(a, &kit, &s) {
        say("photos present failed\n")
        ret ok
    }
    say("photos shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("photos home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    say("photos present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
