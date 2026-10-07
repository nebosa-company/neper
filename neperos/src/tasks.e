// Tasks (D2211): the app behind the Tasks icon, after Google Tasks -- lists with a round check for each
// task, a title and a due-date chip, a star, a collapsible Completed section, a plus button that opens
// the add sheet (a title typed on an on-screen keyboard, a due date, a star), and a sheet to edit or
// delete a task by tapping its title. Cream rows and amber on the dark ground, like Calc and Clock
// (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on the bar at the bottom
// leaves the app.
// ponytail: the tasks live in this process (no storage yet), so they are the sample tasks again each
// time the app starts; no subtasks, repeats or reminders.
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
const MAX_TASKS: usize = 16usize
const MAX_HITS: usize = 96usize
const MAX_TITLE: usize = 44usize

fn say(line: str) {
    let (written, write_error) = os.write(os.stdout(), line)
}

fn say_text(value: str) {
    var buffer: [60]u8 = zero
    var n = 0usize
    while n < value.len && n < 60usize {
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

// ----------------------------------------------------------------------------------------------
// State.

type Task = struct { title: [44]u8, length: usize, due: usize, starred: bool, done: bool, list: usize, used: bool }
type Hit = struct { id: usize, x: f32, y: f32, w: f32, h: f32 }

type State = struct {
    tasks: [16]Task,
    list: usize,
    show_done: bool,
    today: usize,
    // The sheet that adds or edits a task.
    sheet: bool,
    editing: usize,
    draft: Task,
    visible: [16]usize,
    visible_total: usize,
    hits: [96]Hit,
    hit_total: usize,
}

fn list_name(list: usize) -> str {
    if list == 0usize { ret "My Tasks" }
    if list == 1usize { ret "Starred" }
    ret "Work"
}

// Does `task` belong on the list being shown?
fn shown_in(s: *State, task: Task) -> bool {
    if !task.used { ret false }
    if s.list == 1usize { ret task.starred }
    ret task.list == s.list
}

fn make_task(title: str, due: usize, starred: bool, list: usize) -> Task {
    var task: Task = zero
    var i = 0usize
    while i < title.len && i < MAX_TITLE {
        task.title[i] = title[i]
        i += 1usize
    }
    task.length = i
    task.due = due
    task.starred = starred
    task.list = list
    task.used = true
    ret task
}

fn add_task(s: *State, task: Task) -> bool {
    var i = 0usize
    while i < MAX_TASKS {
        if !s.tasks[i].used {
            s.tasks[i] = task
            ret true
        }
        i += 1usize
    }
    ret false
}

// A due date as a chip: Today, Tomorrow, a weekday and date, or a past date.
fn due_text(a: *mem.Arena, s: *State, due: usize) -> str {
    if due == 0usize { ret "" }
    if due == s.today { ret "Today" }
    if due == s.today + 1usize { ret "Tomorrow" }
    let seconds = due * 86400usize
    let (month, date) = lunar.month_day(seconds)
    let weekday = (due + 3usize) % 7usize
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

fn amber_dark() -> paint.Color {
    ret paint.Color { red: 0.78, green: 0.52, blue: 0.12, alpha: 1.0 }
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

fn pill(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, id: usize, x: f32, y: f32, w: f32, h: f32, label: str, fill: paint.Color, ink_color: paint.Color, size: f32) -> err {
    try card(a, builder, x, y, w, h, h / 2.0, fill)
    try centred(a, builder, faces.jost, size, label, x + w / 2.0, y + h / 2.0 - size * 0.62, ink_color)
    hit(s, id, x, y, w, h)
    ret ok
}

fn star_icon(filled: bool) -> str {
    if filled { ret "<svg viewBox='0 0 24 24'><path d='M12 2.8l2.8 6 6.5.8-4.8 4.5 1.3 6.5L12 17.4l-5.8 3.2 1.3-6.5L2.7 9.6l6.5-.8z' fill='currentColor' stroke='currentColor' stroke-width='1.6' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M12 2.8l2.8 6 6.5.8-4.8 4.5 1.3 6.5L12 17.4l-5.8 3.2 1.3-6.5L2.7 9.6l6.5-.8z' fill='none' stroke='currentColor' stroke-width='1.8' stroke-linejoin='round'/></svg>"
}

fn check_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M5.5 12.5l4.2 4.2L18.5 7.6' fill='none' stroke='currentColor' stroke-width='3' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

fn chevron_icon(open: bool) -> str {
    if open { ret "<svg viewBox='0 0 24 24'><path d='M6 15l6-6 6 6' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/></svg>" }
    ret "<svg viewBox='0 0 24 24'><path d='M6 9l6 6 6-6' fill='none' stroke='currentColor' stroke-width='2.4' stroke-linecap='round' stroke-linejoin='round'/></svg>"
}

// A round check: an empty ring, or a filled amber disc with a tick.
fn checkbox(a: *mem.Arena, builder: *scene.Builder, s: *State, id: usize, cx: f32, cy: f32, done: bool) -> err {
    if done {
        try disc(a, builder, cx, cy, 14.0, amber())
        try svg.draw(a, builder, check_icon(), geometry.rect(cx - 9.0, cy - 9.0, 18.0, 18.0), ink())
    } else {
        try disc(a, builder, cx, cy, 14.0, muted())
        try disc(a, builder, cx, cy, 11.5, cream())
    }
    hit(s, id, cx - 24.0, cy - 24.0, 48.0, 48.0)
    ret ok
}

fn draw_row(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces, slot: usize, y: f32, task: Task) -> err {
    try card(a, builder, 16.0, y, 380.0, 68.0, 20.0, cream())
    try checkbox(a, builder, s, 200usize + slot, 46.0, y + 34.0, task.done)
    var title_color = ink()
    if task.done { title_color = muted() }
    let title = text_of(a, task.title[0usize..], task.length)
    var title_y = y + 12.0
    if task.due == 0usize { title_y = y + 21.0 }
    try clipped(a, builder, faces.jost, 19.0, title, 74.0, title_y, 250.0, title_color)
    if task.done {
        // A line through the title.
        let width = text.measure(a, faces.jost, 19.0, title)
        var line_end = 74.0 + width
        if line_end > 324.0 { line_end = 324.0 }
        try card(a, builder, 74.0, title_y + 14.0, line_end - 74.0, 1.6, 0.8, muted())
    }
    if task.due != 0usize {
        var chip_color = amber_dark()
        if task.due < s.today && !task.done { chip_color = paint.Color { red: 0.72, green: 0.22, blue: 0.18, alpha: 1.0 } }
        if task.done { chip_color = muted() }
        try put(a, builder, faces.grotesk, 13.0, due_text(a, s, task.due), 74.0, y + 40.0, chip_color)
    }
    var star_color = soft()
    if task.starred { star_color = amber_dark() }
    try svg.draw(a, builder, star_icon(task.starred), geometry.rect(354.0, y + 22.0, 24.0, 24.0), star_color)
    hit(s, 300usize + slot, 338.0, y, 58.0, 68.0)
    hit(s, 400usize + slot, 70.0, y, 260.0, 68.0)
    ret ok
}

// The keyboard of the sheet: digits, three rows of letters, space.
fn key_label(key: usize) -> str {
    if key < 10usize { ret number_label(key) }
    ret ""
}

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
    // Digits.
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
    // Backspace at the end of the third row, then the space bar, a point and a comma.
    try key_cap(a, builder, s, faces, 1201usize, 18.0 + 52.0 + 7.0 * 38.0, 558.0 + 2.0 * 58.0, 52.0, "DEL", soft())
    try key_cap(a, builder, s, faces, 1203usize, 18.0, 732.0, 50.0, ",", soft())
    try key_cap(a, builder, s, faces, 1200usize, 76.0, 732.0, 228.0, "space", cream())
    try key_cap(a, builder, s, faces, 1202usize, 312.0, 732.0, 50.0, ".", soft())
    ret ok
}

fn draw_sheet(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    var heading = "New task"
    if s.editing != NONE { heading = "Edit task" }
    try put(a, builder, faces.jost_bold, 30.0, heading, 24.0, 36.0, light())
    // The title being typed, with a caret.
    try card(a, builder, 16.0, 92.0, 380.0, 64.0, 20.0, cream())
    let typed = text_of(a, s.draft.title[0usize..], s.draft.length)
    if s.draft.length == 0usize {
        try put(a, builder, faces.jost, 20.0, "Title", 34.0, 110.0, muted())
    } else {
        try clipped(a, builder, faces.jost, 20.0, typed, 34.0, 110.0, 330.0, ink())
    }
    var caret_x: f32 = 34.0
    if s.draft.length > 0usize { caret_x = 34.0 + text.measure(a, faces.jost, 20.0, typed) + 2.0 }
    if caret_x > 360.0 { caret_x = 360.0 }
    try card(a, builder, caret_x, 108.0, 2.0, 26.0, 1.0, amber_dark())
    // The due date.
    try put(a, builder, faces.exo, 13.0, "Due", 24.0, 174.0, light_muted())
    var chip = 0usize
    while chip < 4usize {
        var label = "None"
        if chip == 1usize { label = "Today" }
        if chip == 2usize { label = "Tomorrow" }
        if chip == 3usize { label = "Next week" }
        var chosen = false
        if chip == 0usize && s.draft.due == 0usize { chosen = true }
        if chip == 1usize && s.draft.due == s.today { chosen = true }
        if chip == 2usize && s.draft.due == s.today + 1usize { chosen = true }
        if chip == 3usize && s.draft.due == s.today + 7usize { chosen = true }
        var fill = soft()
        if chosen { fill = amber() }
        try pill(a, builder, s, faces, 1310usize + chip, 16.0 + f32(chip) * 96.0, 196.0, 90.0, 40.0, label, fill, ink(), 15.0)
        chip += 1usize
    }
    // Star and list.
    var star_label = "Star"
    if s.draft.starred { star_label = "Starred" }
    var star_fill = soft()
    if s.draft.starred { star_fill = amber() }
    try pill(a, builder, s, faces, 1320usize, 16.0, 252.0, 120.0, 40.0, star_label, star_fill, ink(), 15.0)
    var list_label = "My Tasks"
    if s.draft.list == 2usize { list_label = "Work" }
    try pill(a, builder, s, faces, 1321usize, 146.0, 252.0, 130.0, 40.0, list_label, soft(), ink(), 15.0)
    // Save, Delete (when editing) and Cancel.
    try pill(a, builder, s, faces, 1300usize, 16.0, 316.0, 186.0, 52.0, "Save", amber(), ink(), 18.0)
    if s.editing != NONE {
        try pill(a, builder, s, faces, 1301usize, 210.0, 316.0, 186.0, 52.0, "Delete", soft(), ink(), 18.0)
    } else {
        try pill(a, builder, s, faces, 1302usize, 210.0, 316.0, 186.0, 52.0, "Cancel", soft(), ink(), 18.0)
    }
    try draw_keyboard(a, builder, s, faces)
    ret ok
}

fn draw_list(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try put(a, builder, faces.jost_bold, 34.0, "Tasks", 24.0, 40.0, light())
    // The lists.
    var list = 0usize
    while list < 3usize {
        let x = 16.0 + f32(list) * 106.0
        var fill = soft()
        if list == s.list { fill = amber() }
        try pill(a, builder, s, faces, 100usize + list, x, 100.0, 98.0, 38.0, list_name(list), fill, ink(), 15.0)
        list += 1usize
    }
    // The open tasks, then the Completed section.
    s.visible_total = 0usize
    var y: f32 = 160.0
    var open_count = 0usize
    var done_count = 0usize
    var i = 0usize
    while i < MAX_TASKS {
        let task = s.tasks[i]
        if shown_in(s, task) {
            if task.done {
                done_count += 1usize
            } else {
                if s.visible_total < MAX_TASKS {
                    s.visible[s.visible_total] = i
                    s.visible_total += 1usize
                }
                try draw_row(a, builder, s, faces, s.visible_total - 1usize, y, task)
                y += 76.0
                open_count += 1usize
            }
        }
        i += 1usize
    }
    if open_count == 0usize && done_count == 0usize {
        try centred(a, builder, faces.jost, 20.0, "No tasks yet", 206.0, 300.0, light_muted())
    }
    if done_count > 0usize {
        y += 8.0
        try put(a, builder, faces.jost, 18.0, join(a, "Completed (", number(a, done_count), ")"), 28.0, y + 4.0, light())
        try svg.draw(a, builder, chevron_icon(s.show_done), geometry.rect(366.0, y + 2.0, 24.0, 24.0), light())
        hit(s, 150usize, 16.0, y - 6.0, 380.0, 40.0)
        y += 40.0
        if s.show_done {
            var j = 0usize
            while j < MAX_TASKS {
                let task = s.tasks[j]
                if shown_in(s, task) && task.done && s.visible_total < MAX_TASKS {
                    s.visible[s.visible_total] = j
                    s.visible_total += 1usize
                    try draw_row(a, builder, s, faces, s.visible_total - 1usize, y, task)
                    y += 76.0
                }
                j += 1usize
            }
        }
    }
    // The plus button.
    try disc(a, builder, 340.0, 800.0, 32.0, amber())
    try card(a, builder, 340.0 - 12.0, 800.0 - 2.0, 24.0, 4.0, 2.0, ink())
    try card(a, builder, 340.0 - 2.0, 800.0 - 12.0, 4.0, 24.0, 2.0, ink())
    hit(s, 160usize, 300.0, 760.0, 80.0, 80.0)
    ret ok
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hit_total = 0usize
    let faces = kit.faces
    // The ground; its alpha alternates by 0.2% a frame (invisible) so each frame differs in its first
    // command (the renderer's incremental redraw skips shapes under changed text otherwise).
    try scene.push(builder, scene.Command { FillRect: scene.FillRect { rect: geometry.rect(0.0, 0.0, 412.0, kit.logical_h), brush: paint.Brush { Solid: paint.Color { red: 0.08, green: 0.09, blue: 0.11, alpha: 1.0 - f32(kit.frame % 2usize) * 0.002 } } } })
    if s.sheet {
        try draw_sheet(a, builder, s, faces)
    } else {
        try draw_list(a, builder, s, faces)
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
    if s.draft.length >= MAX_TITLE { ret }
    var b = byte
    // The first letter of the title is a capital.
    if s.draft.length == 0usize && b >= 97u8 && b <= 122u8 { b = b - 32u8 }
    s.draft.title[s.draft.length] = b
    s.draft.length += 1usize
}

fn open_sheet(s: *State, index: usize) {
    s.sheet = true
    s.editing = index
    if index == NONE {
        s.draft = make_task("", 0usize, false, 0usize)
        s.draft.length = 0usize
        if s.list == 1usize { s.draft.starred = true }
        if s.list == 2usize { s.draft.list = 2usize }
    } else {
        s.draft = s.tasks[index]
    }
}

// What a tap on button `id` did: true when the screen changed.
fn act(s: *State, id: usize) -> bool {
    if s.sheet {
        if id >= 1000usize && id < 1026usize {
            type_key(s, u8(97usize + id - 1000usize))
            ret true
        }
        if id >= 1100usize && id < 1110usize {
            type_key(s, u8(48usize + (id - 1100usize + 1usize) % 10usize))
            ret true
        }
        if id == 1200usize {
            if s.draft.length > 0usize { type_key(s, 32u8) }
            ret true
        }
        if id == 1201usize {
            if s.draft.length > 0usize { s.draft.length -= 1usize }
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
        if id >= 1310usize && id < 1314usize {
            if id == 1310usize { s.draft.due = 0usize }
            if id == 1311usize { s.draft.due = s.today }
            if id == 1312usize { s.draft.due = s.today + 1usize }
            if id == 1313usize { s.draft.due = s.today + 7usize }
            ret true
        }
        if id == 1320usize {
            s.draft.starred = !s.draft.starred
            ret true
        }
        if id == 1321usize {
            if s.draft.list == 2usize { s.draft.list = 0usize } else { s.draft.list = 2usize }
            ret true
        }
        if id == 1300usize {
            if s.draft.length > 0usize {
                if s.editing == NONE {
                    let added = add_task(s, s.draft)
                    say("tasks added\n")
                } else {
                    s.tasks[s.editing] = s.draft
                    say("tasks saved\n")
                }
            }
            s.sheet = false
            ret true
        }
        if id == 1301usize {
            if s.editing != NONE { s.tasks[s.editing].used = false }
            s.sheet = false
            say("tasks deleted\n")
            ret true
        }
        if id == 1302usize {
            s.sheet = false
            ret true
        }
        ret false
    }
    if id >= 100usize && id < 103usize {
        s.list = id - 100usize
        ret true
    }
    if id == 150usize {
        s.show_done = !s.show_done
        ret true
    }
    if id == 160usize {
        open_sheet(s, NONE)
        ret true
    }
    if id >= 200usize && id < 216usize {
        let index = s.visible[id - 200usize]
        s.tasks[index].done = !s.tasks[index].done
        if s.tasks[index].done { say("tasks completed\n") } else { say("tasks reopened\n") }
        ret true
    }
    if id >= 300usize && id < 316usize {
        let index = s.visible[id - 300usize]
        s.tasks[index].starred = !s.tasks[index].starred
        ret true
    }
    if id >= 400usize && id < 416usize {
        open_sheet(s, s.visible[id - 400usize])
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

fn count_tasks(s: *State) -> usize {
    var n = 0usize
    var i = 0usize
    while i < MAX_TASKS {
        if s.tasks[i].used { n += 1usize }
        i += 1usize
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "tasks")
    if kit_error != ok {
        say("tasks open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        say("tasks fonts absent\n")
        ret ok
    }
    var s: State = zero
    let (wall, wall_error) = time.now()
    if wall_error == ok { s.today = usize(wall.nanos / 1000000000i64) / 86400usize }
    s.editing = NONE
    // The tasks it starts with.
    let t1 = add_task(&s, make_task("Collect crater samples", s.today, true, 0usize))
    let t2 = add_task(&s, make_task("Install seismometer unit 4", s.today + 1usize, false, 0usize))
    let t3 = add_task(&s, make_task("Maintain the rover", s.today + 3usize, false, 0usize))
    let t4 = add_task(&s, make_task("Calibrate communications array", 0usize, false, 2usize))
    let t5 = add_task(&s, make_task("Review last week's survey", s.today - 2usize, false, 2usize))
    var done_task = make_task("Charge the batteries", s.today - 1usize, false, 0usize)
    done_task.done = true
    let t6 = add_task(&s, done_task)
    if !show(a, &kit, &s) {
        say("tasks present failed\n")
        ret ok
    }
    say("tasks shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            appkit.answer(appkit.ANSWER_NONE)
        } else if tap.y >= 896.0 {
            say("tasks home\n")
            appkit.leave()
            running = false
        } else {
            let id = hit_at(&s, tap.x, tap.y)
            if id != NONE && act(&s, id) {
                if !show(a, &kit, &s) {
                    say("tasks present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
                say("tasks count ")
                say_num(count_tasks(&s))
                say("\n")
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
