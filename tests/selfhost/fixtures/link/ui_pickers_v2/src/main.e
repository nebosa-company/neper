// The v2 calendar, date picker and picker sheet (D959, widget plan P5-06,
// docs/ux/components) under the light theme at pointer density: a calendar's
// header is 32 tall over the weekday row, its days 32 discs, the selected one
// `primary`, today a 1px `primary` ring, a range banded in `primary-container`
// from the middle of one end to the middle of the other; a date picker's field is
// 40 tall in the 2px `primary` outline while open, its calendar 4 below on
// `surface-container-high`, 8 above and 12 beside the grid; a picker's sheet
// stands on the window's bottom edge over a scrim, `surface-container-low`, with
// a handle and rows 56 tall leading with a radio.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.image
use e.gfx.paint
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

// (D1366) A field's text rewritten through its change, kept in its bytes.
type Rewritten = struct { bytes: []u8, len: usize }

fn on_rewrite(ctx: *void, value: str) -> err {
    let r = mem.cast[*Rewritten](ctx)
    var i = 0usize
    while i < value.len && i < r.bytes.len {
        r.bytes[i] = value[i]
        i += 1usize
    }
    r.len = i
    ret ok
}

type Store = struct { press: widget.Submit, picks: [3]widget.Submit, words: [3]str, dates: usize, last_date: time.Date, toggles: usize }

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.toggles += 1usize
    ret ok
}

fn on_date(ctx: *void, value: time.Date) -> err {
    let s = mem.cast[*Store](ctx)
    s.dates += 1usize
    s.last_date = value
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, date_open: bool, sheet_open: bool) -> (widget.Node, err) {
    let march = time.Date { year: 2026i32, month: 3u8, day: 1u8 }
    let tenth = time.Date { year: 2026i32, month: 3u8, day: 10u8 }
    let twelfth = time.Date { year: 2026i32, month: 3u8, day: 12u8 }
    let from = time.Date { year: 2026i32, month: 3u8, day: 16u8 }
    let to = time.Date { year: 2026i32, month: 3u8, day: 19u8 }
    let dates = widget.Change[time.Date] { ctx: mem.cast[*void](s), invoke: on_date }
    let (single, e1) = overlay.calendar_marked(a, 1u64, t, "March", march, tenth, true, false, tenth, tenth, twelfth, true, dates, dates)
    let (span, e2) = overlay.calendar(a, 100u64, t, "Stay", march, from, true, true, from, to, dates, dates)
    let (due, e3) = overlay.date_picker(a, 200u64, t, "Due", tenth, true, date_open, &s.press, march, dates, dates)
    let (kind, e4) = control.picker(a, 300u64, t, "Kind", s.words[0usize..3usize], 1usize, sheet_open, &s.press, s.picks[0usize..3usize], .Sheet)
    if e1 != ok { ret (zero, e1) }
    if e2 != ok { ret (zero, e2) }
    if e3 != ok { ret (zero, e3) }
    if e4 != ok { ret (zero, e4) }
    let (left, left_error) = mem.alloc[widget.Node](a, 2usize)
    if left_error != ok { ret (zero, left_error) }
    left[0usize] = due
    left[1usize] = kind
    let (right, right_error) = mem.alloc[widget.Node](a, 2usize)
    if right_error != ok { ret (zero, right_error) }
    right[0usize] = single
    right[1usize] = span
    let (columns, columns_error) = mem.alloc[widget.Node](a, 2usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, control.sized_style(280.0, 680.0), left[0usize..2usize])
    columns[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, style.defaults(), right[0usize..2usize])
    var page = style.defaults()
    page.width = style.Length { Px: 600.0 }
    page.height = style.Length { Px: 720.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 12.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 8.0 }, page, columns[0usize..2usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 600usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

// A 1px antialiased ring: within 12 of the colour.
fn roughly(shot: image.Image, i: usize, c: paint.Color) -> bool {
    var k = 0usize
    while k < 3usize {
        var e = c.red
        if k == 1usize { e = c.green }
        if k == 2usize { e = c.blue }
        let d = f32(shot.pixels[i + k]) - e * 255.0
        if d > 12.0 || d < -12.0 { ret false }
        k += 1usize
    }
    ret true
}

fn over(under: paint.Color, top: paint.Color, share: f32) -> paint.Color {
    ret paint.rgba(under.red + (top.red - under.red) * share, under.green + (top.green - under.green) * share, under.blue + (top.blue - under.blue) * share, 1.0)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

// (D1307) The first node in the tree named `label`.
fn labelled(h: *testing.Harness, label: str) -> (accessibility.Node, bool) {
    let (tree, tree_error) = testing.semantics(h)
    if tree_error != ok { ret (zero, false) }
    var i = 0usize
    while i < tree.nodes.len {
        if testing.same_text(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

// (D1307) A tap at the middle of the element keyed `key`.
fn tap_key(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let (b, found) = bounds(h, runtime, key)
    ret found && testing.tap(h, b.x + b.width * 0.5, b.y + b.height * 0.5) == ok
}

fn focusable(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> bool {
    let match = testing.by_key(h, key)
    if match.count != 1usize { ret false }
    let (summary, found) = widget.summary_at(runtime, usize(match.element.slot))
    ret found && summary.focusable
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 1024usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 24u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 600u32, 720u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let press = widget.Submit { ctx: mem.cast[*void](&stores[0usize]), invoke: on_press }
    stores[0usize].press = press
    stores[0usize].picks[0usize] = press
    stores[0usize].picks[1usize] = press
    stores[0usize].picks[2usize] = press
    stores[0usize].words[0usize] = "Pear"
    stores[0usize].words[1usize] = "Plum"
    stores[0usize].words[2usize] = "Fig"
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, &stores[0usize], true, false)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let page = style.color(&tokens, .Background)
    let primary = style.color(&tokens, .Primary)
    let band = style.color(&tokens, .PrimaryContainer)
    // The calendar: Previous and Next 32 round buttons at the header's end; the 1st
    // (a Sunday) under Next, 32 + 8 + 32 below the header's top.
    let (back, has_back) = bounds(&harness, &runtime, 2u64)
    let (forward, has_forward) = bounds(&harness, &runtime, 3u64)
    let (first, has_first) = bounds(&harness, &runtime, 5u64)
    if !has_back || !has_forward || !has_first || !near(back.width, 32.0) || !near(back.height, 32.0) || !near(forward.x - back.x, 32.0) { os.exit(12i32) }
    if !near(first.x, forward.x) || !near(first.y - back.y, 72.0) || !near(first.width, 32.0) || !near(first.height, 32.0) { os.exit(13i32) }
    // The 10th selected: a primary disc; the 12th today: a 1px primary ring round the
    // page; the 11th plain.
    let (tenth, has_tenth) = bounds(&harness, &runtime, 14u64)
    let (eleventh, has_eleventh) = bounds(&harness, &runtime, 15u64)
    let (twelfth, has_twelfth) = bounds(&harness, &runtime, 16u64)
    if !has_tenth || !has_eleventh || !has_twelfth || !near(eleventh.x - tenth.x, 32.0) { os.exit(14i32) }
    if !is_color(shot, at(tenth.x + 16.0, tenth.y + 16.0), primary) || !is_color(shot, at(tenth.x + 2.0, tenth.y + 2.0), page) { os.exit(15i32) }
    if !roughly(shot, at(twelfth.x + 0.5, twelfth.y + 16.0), primary) || !is_color(shot, at(twelfth.x + 16.0, twelfth.y + 16.0), page) || !is_color(shot, at(eleventh.x + 16.0, eleventh.y + 16.0), page) { os.exit(16i32) }
    // The range from the 16th to the 19th: both ends primary discs, the band from
    // the middle of the 16th to the middle of the 19th.
    let (start, has_start) = bounds(&harness, &runtime, 119u64)
    let (inner, has_inner) = bounds(&harness, &runtime, 120u64)
    let (finish, has_finish) = bounds(&harness, &runtime, 122u64)
    if !has_start || !has_inner || !has_finish { os.exit(17i32) }
    if !is_color(shot, at(start.x + 16.0, start.y + 16.0), primary) || !is_color(shot, at(finish.x + 16.0, finish.y + 16.0), primary) || !is_color(shot, at(inner.x + 16.0, inner.y + 16.0), band) { os.exit(18i32) }
    if !is_color(shot, at(start.x + 31.0, start.y + 2.0), band) || !is_color(shot, at(start.x + 1.0, start.y + 2.0), page) || !is_color(shot, at(inner.x + 1.0, inner.y + 2.0), band) || !is_color(shot, at(finish.x + 1.0, finish.y + 2.0), band) || !is_color(shot, at(finish.x + 31.0, finish.y + 2.0), page) { os.exit(19i32) }
    // The open date picker: a 40 field in the 2px primary outline; the calendar 4
    // below on the high container, the grid 8 in from its top and 12 from its side.
    let (field, has_field) = bounds(&harness, &runtime, 200u64)
    let (grid, has_grid) = bounds(&harness, &runtime, 202u64)
    if !has_field || !has_grid || !near(field.height, 40.0) || !near(grid.y - field.y - field.height, 12.0) || !near(grid.x - field.x, 12.0) || !near(grid.width, 224.0) { os.exit(20i32) }
    if !is_color(shot, at(field.x + 0.5, field.y + 20.0), primary) || !is_color(shot, at(field.x + 1.5, field.y + 20.0), primary) { os.exit(21i32) }
    let high = style.color(&tokens, .SurfaceContainerHigh)
    if !is_color(shot, at(grid.x - 6.0, grid.y + 100.0), high) || !is_color(shot, at(grid.x + 230.0, grid.y + 100.0), high) || !is_color(shot, at(grid.x + 100.0, grid.y - 4.0), high) { os.exit(22i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 215u64).element) != ok { os.exit(29i32) }
    var shifted: input.Modifiers = zero
    shifted.shift = true
    if testing.press_key(&harness, 34u32, zero) != ok || stores[0usize].last_date.month != 4u8 || stores[0usize].last_date.year != 2026i32 { os.exit(30i32) }
    if testing.press_key(&harness, 33u32, zero) != ok || stores[0usize].last_date.month != 2u8 || stores[0usize].last_date.year != 2026i32 { os.exit(31i32) }
    if testing.press_key(&harness, 34u32, shifted) != ok || stores[0usize].last_date.month != 3u8 || stores[0usize].last_date.year != 2027i32 { os.exit(32i32) }
    if testing.press_key(&harness, 33u32, shifted) != ok || stores[0usize].last_date.month != 3u8 || stores[0usize].last_date.year != 2025i32 { os.exit(33i32) }
    if stores[0usize].dates != 4usize { os.exit(34i32) }
    // The picker's sheet: on the window's bottom edge across its width over the
    // scrim, rows 56 tall, the chosen one's radio dotted in primary, another's ring
    // in on-surface-variant round the sheet.
    let (root_2, build_2_error) = build(&f, &theme, &stores[0usize], false, true)
    if build_2_error != ok || testing.pump(&harness, root_2, time.Instant { nanos: 2000000000i64 }) != ok { os.exit(23i32) }
    let (shot_2, shot_2_error) = testing.snapshot(&harness, a)
    if shot_2_error != ok { os.exit(24i32) }
    let (pear, has_pear) = bounds(&harness, &runtime, 302u64)
    let (plum, has_plum) = bounds(&harness, &runtime, 303u64)
    let (fig, has_fig) = bounds(&harness, &runtime, 304u64)
    if !has_pear || !has_plum || !has_fig || !near(pear.height, 56.0) || !near(plum.y - pear.y, 56.0) || !near(pear.x, 0.0) || !near(pear.width, 600.0) || !near(fig.y + fig.height + 8.0, 720.0) { os.exit(25i32) }
    let low = style.color(&tokens, .SurfaceContainerLow)
    let dimmed = over(page, style.color(&tokens, .Scrim), tokens.states.scrim)
    if !is_color(shot_2, at(300.0, 4.0), dimmed) || !is_color(shot_2, at(500.0, pear.y + 4.0), low) { os.exit(26i32) }
    let top = pear.y - 44.0
    if !is_color(shot_2, at(300.0, top + 18.0), over(low, style.color(&tokens, .OnSurfaceVariant), 0.4)) || !is_color(shot_2, at(300.0, top + 10.0), low) { os.exit(27i32) }
    if !is_color(shot_2, at(36.0, plum.y + 28.0), primary) || !is_color(shot_2, at(36.0, pear.y + 28.0), low) || !is_color(shot_2, at(27.0, pear.y + 28.0), style.color(&tokens, .OnSurfaceVariant)) { os.exit(28i32) }
    let (closed, closed_error) = build(&f, &theme, &stores[0usize], false, false)
    if closed_error != ok || testing.pump(&harness, closed, time.Instant { nanos: 3000000000i64 }) != ok || widget.focus(&runtime, testing.by_key(&harness, 200u64).element) != ok { os.exit(35i32) }
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.press_key(&harness, 40u32, alt) != ok || stores[0usize].toggles != 1usize { os.exit(36i32) }
    let (reopened, reopened_error) = build(&f, &theme, &stores[0usize], true, false)
    if reopened_error != ok || testing.pump(&harness, reopened, time.Instant { nanos: 4000000000i64 }) != ok || !widget.focus_within(&runtime, 215u64) || !focusable(&harness, &runtime, 215u64) || focusable(&harness, &runtime, 214u64) || focusable(&harness, &runtime, 216u64) { os.exit(37i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !widget.focus_within(&runtime, 216u64) { os.exit(38i32) }
    let (moved, moved_error) = build(&f, &theme, &stores[0usize], true, false)
    if moved_error != ok || testing.pump(&harness, moved, time.Instant { nanos: 4100000000i64 }) != ok || !focusable(&harness, &runtime, 216u64) || focusable(&harness, &runtime, 215u64) { os.exit(43i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || !widget.focus_within(&runtime, 223u64) { os.exit(39i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || !widget.focus_within(&runtime, 221u64) { os.exit(40i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || !widget.focus_within(&runtime, 227u64) { os.exit(41i32) }
    let (clicked, has_clicked) = bounds(&harness, &runtime, 217u64)
    if !has_clicked || testing.tap(&harness, clicked.x + 16.0, clicked.y + 16.0) != ok || !widget.focus_within(&runtime, 217u64) { os.exit(44i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 206u64).element) != ok || testing.press_key(&harness, 37u32, zero) != ok || stores[0usize].last_date.year != 2026i32 || stores[0usize].last_date.month != 2u8 || stores[0usize].last_date.day != 1u8 || stores[0usize].dates != 6usize || !widget.focus_within(&runtime, 233u64) { os.exit(42i32) }
    // (D1229) The theme's language picks the week's first day: in "en-US" the 1st of
    // March 2026 (a Sunday) opens the first column under "Su", the 8th right below
    // it; in "ar-EG" (Saturday first) the same Sunday stands one column further in.
    let us_theme = control.Theme { tokens: &tokens, fonts: fonts, language: "en-US", runtime: &runtime }
    let eg_theme = control.Theme { tokens: &tokens, fonts: fonts, language: "ar-EG", runtime: &runtime }
    let first_of_march = time.Date { year: 2026i32, month: 3u8, day: 1u8 }
    let no_dates: widget.Change[time.Date] = zero
    var us_first_x: f32 = 0.0
    var locale_step = 0usize
    while locale_step < 2usize {
        var locale_theme = us_theme
        if locale_step == 1usize { locale_theme = eg_theme }
        f = mem.arena_from(frame_storage)
        let (week_cal, week_cal_error) = overlay.calendar(&f, 900u64, &locale_theme, "March", first_of_march, first_of_march, false, false, first_of_march, first_of_march, no_dates, no_dates)
        if week_cal_error != ok || testing.pump(&harness, week_cal, time.Instant { nanos: 3000000000i64 + i64(locale_step) }) != ok { os.exit(45i32) }
        let (day_one, has_day_one) = bounds(&harness, &runtime, 904u64)
        let (day_eight, has_day_eight) = bounds(&harness, &runtime, 911u64)
        if !has_day_one || !has_day_eight || !near(day_eight.y - day_one.y, 32.0) || !near(day_eight.x, day_one.x) { os.exit(46i32) }
        if locale_step == 0usize {
            let (day_two, has_day_two) = bounds(&harness, &runtime, 905u64)
            if !has_day_two || !near(day_two.x - day_one.x, 32.0) || !near(day_two.y, day_one.y) || testing.by_text(&harness, "Su").count == 0usize { os.exit(47i32) }
            us_first_x = day_one.x
        }
        if locale_step == 1usize && !near(day_one.x, us_first_x + 32.0) { os.exit(48i32) }
        locale_step += 1usize
    }
    // (D1244) Marks on March 2026, Monday first: week numbers 9 to 14 in a column
    // before Monday, a tertiary dot under the 10th, and the 12th and every day
    // before the 3rd unavailable -- a press on them picks nothing and the tree
    // calls them disabled.
    var event_days: [1]time.Date = zero
    event_days[0usize] = time.Date { year: 2026i32, month: 3u8, day: 10u8 }
    var closed_days: [1]time.Date = zero
    closed_days[0usize] = time.Date { year: 2026i32, month: 3u8, day: 12u8 }
    var marks: overlay.CalendarMarks = zero
    marks.week_numbers = true
    marks.events = event_days[..]
    marks.unavailable = closed_days[..]
    marks.earliest = time.Date { year: 2026i32, month: 3u8, day: 3u8 }
    marks.has_earliest = true
    let picked_dates = widget.Change[time.Date] { ctx: mem.cast[*void](&stores[0usize]), invoke: on_date }
    f = mem.arena_from(frame_storage)
    let (marked_cal, marked_cal_error) = overlay.calendar_with(&f, 900u64, &theme, "March", first_of_march, first_of_march, false, false, first_of_march, first_of_march, first_of_march, false, picked_dates, picked_dates, marks)
    let (marked_page, marked_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if marked_cal_error != ok || marked_page_error != ok { os.exit(82i32) }
    marked_page[0usize] = marked_cal
    var marked_ground = control.sized_style(600.0, 720.0)
    marked_ground.background = paint.Brush { Solid: style.color(&tokens, .Surface) }
    if testing.pump(&harness, widget.box(0u64, marked_ground, marked_page[0usize..1usize]), time.Instant { nanos: 3100000000i64 }) != ok { os.exit(83i32) }
    let (marked_box, has_marked_box) = bounds(&harness, &runtime, 900u64)
    let (monday_two, has_monday_two) = bounds(&harness, &runtime, 905u64)
    if !has_marked_box || !has_monday_two || !near(monday_two.x, marked_box.x + 32.0) || testing.by_text(&harness, "9").count != 2usize || testing.by_text(&harness, "14").count != 2usize { os.exit(84i32) }
    let (tenth_marked, has_tenth_marked) = bounds(&harness, &runtime, 913u64)
    let (open_day, has_open_day) = bounds(&harness, &runtime, 914u64)
    let (marked_shot, marked_shot_error) = testing.snapshot(&harness, a)
    if !has_tenth_marked || !has_open_day || marked_shot_error != ok { os.exit(85i32) }
    if !is_color(marked_shot, at(tenth_marked.x + 16.0, tenth_marked.y + 26.0), style.color(&tokens, .Tertiary)) || is_color(marked_shot, at(open_day.x + 16.0, open_day.y + 26.0), style.color(&tokens, .Tertiary)) { os.exit(86i32) }
    var no_date: time.Date = zero
    stores[0usize].last_date = no_date
    let (twelfth_marked, has_twelfth_marked) = bounds(&harness, &runtime, 915u64)
    if !has_twelfth_marked || testing.tap(&harness, twelfth_marked.x + 16.0, twelfth_marked.y + 16.0) != ok || testing.tap(&harness, monday_two.x + 16.0, monday_two.y + 16.0) != ok || stores[0usize].last_date.day != 0u8 { os.exit(87i32) }
    if testing.tap(&harness, open_day.x + 16.0, open_day.y + 16.0) != ok || stores[0usize].last_date.day != 11u8 { os.exit(88i32) }
    let (marked_tree, marked_tree_error) = testing.semantics(&harness)
    if marked_tree_error != ok { os.exit(89i32) }
    var disabled_days = 0usize
    var marked_node = 0usize
    while marked_node < marked_tree.nodes.len {
        if marked_tree.nodes[marked_node].role == .Button && marked_tree.nodes[marked_node].state.disabled { disabled_days += 1usize }
        marked_node += 1usize
    }
    if disabled_days != 3usize { os.exit(90i32) }
    // (D1257) A typed date in en-US: the hint below the field, Enter on "9/25/2026"
    // picks the 25th of September, and "13/45/2026" in an unfocused field says how to write
    // it, in `error`.
    let (typed_bytes, typed_bytes_error) = mem.alloc[u8](a, 32usize)
    if typed_bytes_error != ok { os.exit(91i32) }
    let typed_today = time.Date { year: 2026i32, month: 9u8, day: 1u8 }
    var typed_step = 0usize
    while typed_step < 2usize {
        var typed_text = "9/25/2026"
        if typed_step == 1usize { typed_text = "13/45/2026" }
        var tb = 0usize
        while tb < typed_text.len {
            typed_bytes[tb] = typed_text[tb]
            tb += 1usize
        }
        f = mem.arena_from(frame_storage)
        let (typed, typed_error) = overlay.date_entry(&f, 960u64 + 2u64 * u64(typed_step), &us_theme, "Release date", typed_bytes, typed_text.len, zero, picked_dates, typed_today, 280.0)
        let (typed_page, typed_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if typed_error != ok || typed_page_error != ok { os.exit(92i32) }
        typed_page[0usize] = typed
        var typed_ground = control.sized_style(600.0, 720.0)
        typed_ground.background = paint.Brush { Solid: style.color(&tokens, .Surface) }
        if testing.pump(&harness, widget.box(0u64, typed_ground, typed_page[0usize..1usize]), time.Instant { nanos: 3200000000i64 + i64(typed_step) }) != ok { os.exit(93i32) }
        if typed_step == 0usize {
            if testing.by_text(&harness, "mm/dd/yyyy").count == 0usize { os.exit(94i32) }
            var cleared: time.Date = zero
            stores[0usize].last_date = cleared
            if widget.focus(&runtime, testing.by_key(&harness, 960u64).element) != ok || testing.press_key(&harness, 13u32, zero) != ok || stores[0usize].last_date.month != 9u8 || stores[0usize].last_date.day != 25u8 { os.exit(95i32) }
        }
        if typed_step == 1usize && testing.by_text(&harness, "Enter a date as mm/dd/yyyy").count == 0usize { os.exit(97i32) }
        typed_step += 1usize
    }
    // (D1366) "25 sep" typed and the focus moved away: the field is rewritten
    // "9/25/2026".
    let (loose_bytes, loose_bytes_error) = mem.alloc[u8](a, 32usize)
    if loose_bytes_error != ok { os.exit(136i32) }
    let loose_text = "25 sep"
    var lb = 0usize
    while lb < loose_text.len {
        loose_bytes[lb] = loose_text[lb]
        lb += 1usize
    }
    var rewritten = Rewritten { bytes: loose_bytes, len: loose_text.len }
    var loose_step = 0usize
    while loose_step < 4usize {
        f = mem.arena_from(frame_storage)
        let (loose, loose_error) = overlay.date_entry(&f, 990u64, &us_theme, "Release date", loose_bytes, rewritten.len, widget.Change[str] { ctx: mem.cast[*void](&rewritten), invoke: on_rewrite }, picked_dates, typed_today, 280.0)
        let (loose_page, loose_page_error) = mem.alloc[widget.Node](&f, 2usize)
        if loose_error != ok || loose_page_error != ok { os.exit(137i32) }
        loose_page[0usize] = loose
        loose_page[1usize] = widget.region(995u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(40.0, 40.0), zero)
        if testing.pump(&harness, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, control.sized_style(600.0, 720.0), loose_page[0usize..2usize]), time.Instant { nanos: 3250000000i64 + i64(loose_step) }) != ok { os.exit(138i32) }
        if loose_step == 1usize && widget.focus(&runtime, testing.by_key(&harness, 990u64).element) != ok { os.exit(139i32) }
        if loose_step == 2usize && widget.focus(&runtime, testing.by_key(&harness, 995u64).element) != ok { os.exit(140i32) }
        loose_step += 1usize
    }
    if !testing.same_text(loose_bytes[0usize..rewritten.len], "9/25/2026") { os.exit(141i32) }
    // (D1258) The open picker's footer: Today picks today, Clear clears.
    let footer_today = time.Date { year: 2026i32, month: 9u8, day: 25u8 }
    var footer_marks: overlay.DateFooter = zero
    footer_marks.today = footer_today
    footer_marks.clear = &stores[0usize].press
    f = mem.arena_from(frame_storage)
    let (footed, footed_error) = overlay.date_picker_with(&f, 970u64, &theme, "Release date", footer_today, false, true, &stores[0usize].press, first_of_march, no_dates, picked_dates, footer_marks)
    let (footed_page, footed_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if footed_error != ok || footed_page_error != ok { os.exit(98i32) }
    footed_page[0usize] = footed
    if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 720.0), footed_page[0usize..1usize]), time.Instant { nanos: 3300000000i64 }) != ok { os.exit(99i32) }
    var reset_day: time.Date = zero
    stores[0usize].last_date = reset_day
    let (today_box, has_today_box) = bounds(&harness, &runtime, 1034u64)
    let (clear_box, has_clear_box) = bounds(&harness, &runtime, 1035u64)
    if !has_today_box || !has_clear_box || !(clear_box.x > today_box.x + today_box.width) { os.exit(100i32) }
    if testing.tap(&harness, today_box.x + today_box.width * 0.5, today_box.y + today_box.height * 0.5) != ok || stores[0usize].last_date.day != 25u8 || stores[0usize].last_date.month != 9u8 { os.exit(101i32) }
    let toggles_before_clear = stores[0usize].toggles
    if testing.tap(&harness, clear_box.x + clear_box.width * 0.5, clear_box.y + clear_box.height * 0.5) != ok || stores[0usize].toggles != toggles_before_clear + 1usize { os.exit(102i32) }
    // (D1277) With the week of the 16th to the 22nd unavailable, Down from the
    // 11th goes to the 25th.
    var closed_week: [7]time.Date = zero
    var cw = 0usize
    while cw < 7usize {
        closed_week[cw] = time.Date { year: 2026i32, month: 3u8, day: u8(16usize + cw) }
        cw += 1usize
    }
    var week_marks: overlay.CalendarMarks = zero
    week_marks.unavailable = closed_week[..]
    f = mem.arena_from(frame_storage)
    let (skipping, skipping_error) = overlay.calendar_with(&f, 1100u64, &theme, "March", first_of_march, first_of_march, false, false, first_of_march, first_of_march, first_of_march, false, picked_dates, picked_dates, week_marks)
    let (skipping_page, skipping_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if skipping_error != ok || skipping_page_error != ok { os.exit(103i32) }
    skipping_page[0usize] = skipping
    if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 720.0), skipping_page[0usize..1usize]), time.Instant { nanos: 3400000000i64 }) != ok { os.exit(104i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 1114u64).element) != ok || testing.press_key(&harness, 40u32, zero) != ok { os.exit(105i32) }
    let (skip_focus, has_skip_focus) = testing.focused(&harness)
    if !has_skip_focus || skip_focus.slot != testing.by_key(&harness, 1128u64).element.slot { os.exit(106i32) }
    // (D1332) Opened, the sheet slides up: part way its surface is not yet at the
    // window's foot, then it is. (D1360) Shut, it is still there a frame on, and
    // gone a second later.
    var rise_step = 0usize
    while rise_step < 6usize {
        var rise_at = 3700000000i64
        var rise_open = false
        if rise_step == 1usize { rise_at = 3716000000i64 }
        if rise_step == 2usize {
            rise_at = 3800000000i64
            rise_open = true
        }
        if rise_step == 3usize {
            rise_at = 4300000000i64
            rise_open = true
        }
        if rise_step == 4usize { rise_at = 4316000000i64 }
        if rise_step == 5usize { rise_at = 5400000000i64 }
        if testing.begin(&harness, time.Instant { nanos: rise_at }) != ok { os.exit(125i32) }
        f = mem.arena_from(frame_storage)
        let (rising, rising_error) = control.picker(&f, 1400u64, &theme, "Kind", stores[0usize].words[0usize..3usize], 0usize, rise_open, &stores[0usize].press, stores[0usize].picks[0usize..3usize], .Sheet)
        let (rise_page, rise_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if rising_error != ok || rise_page_error != ok { os.exit(126i32) }
        rise_page[0usize] = rising
        if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 720.0), rise_page[0usize..1usize]), time.Instant { nanos: rise_at }) != ok { os.exit(127i32) }
        if rise_step >= 2usize {
            let (rise_shot, rise_shot_error) = testing.snapshot(&harness, a)
            if rise_shot_error != ok { os.exit(128i32) }
            let at_foot = is_color(rise_shot, at(300.0, 715.0), style.color(&tokens, .SurfaceContainerLow))
            if rise_step == 2usize && at_foot { os.exit(129i32) }
            if rise_step == 3usize && !at_foot { os.exit(130i32) }
        }
        if rise_step == 4usize && testing.by_key(&harness, 1401u64).count != 1usize { os.exit(131i32) }
        if rise_step == 5usize && testing.by_key(&harness, 1401u64).count != 0usize { os.exit(132i32) }
        rise_step += 1usize
    }
    // (D1311) A sheet of twelve options in a 720 window scrolls past 60%: its rows
    // stand in a viewport 352 tall (432 less the 80 above and below).
    var many_words: [12]str = zero
    var many_picks: [12]widget.Submit = zero
    var mw = 0usize
    while mw < 12usize {
        many_words[mw] = "Choice"
        many_picks[mw] = stores[0usize].press
        mw += 1usize
    }
    f = mem.arena_from(frame_storage)
    let (tall_sheet, tall_sheet_error) = control.picker(&f, 1300u64, &theme, "Many", many_words[..], 0usize, true, &stores[0usize].press, many_picks[..], .Sheet)
    let (tall_page, tall_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if tall_sheet_error != ok || tall_page_error != ok { os.exit(122i32) }
    tall_page[0usize] = tall_sheet
    if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 720.0), tall_page[0usize..1usize]), time.Instant { nanos: 3600000000i64 }) != ok { os.exit(123i32) }
    let (tall_view, has_tall_view) = bounds(&harness, &runtime, 1300u64 + 1048576u64)
    if !has_tall_view || !near(tall_view.height, 352.0) { os.exit(124i32) }
    // (D1307) The month button toggles the year view; there, 2026 is chosen and
    // a press on 2030 shows March 2030 and leaves the view.
    var year_step = 0usize
    while year_step < 2usize {
        var year_marks: overlay.CalendarMarks = zero
        year_marks.toggle_years = &stores[0usize].press
        year_marks.year_view = year_step == 1usize
        f = mem.arena_from(frame_storage)
        let (yearly, yearly_error) = overlay.calendar_with(&f, 1200u64, &theme, "March", first_of_march, first_of_march, false, false, first_of_march, first_of_march, first_of_march, false, picked_dates, picked_dates, year_marks)
        let (yearly_page, yearly_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if yearly_error != ok || yearly_page_error != ok { os.exit(115i32) }
        yearly_page[0usize] = yearly
        if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 720.0), yearly_page[0usize..1usize]), time.Instant { nanos: 3500000000i64 + i64(year_step) }) != ok { os.exit(116i32) }
        let (month_button, has_month_button) = labelled(&harness, "March 2026")
        if !has_month_button { os.exit(118i32) }
        let toggles_before = stores[0usize].toggles
        if year_step == 0usize {
            if month_button.state.expanded || testing.by_key(&harness, 1215u64).count != 1usize || !tap_key(&harness, &runtime, 1200u64 + 4095u64) || stores[0usize].toggles != toggles_before + 1usize { os.exit(119i32) }
        }
        if year_step == 1usize {
            let (this_year, has_this_year) = labelled(&harness, "2026")
            if !month_button.state.expanded || !has_this_year || !this_year.state.selected || testing.by_key(&harness, 1215u64).count != 0usize { os.exit(120i32) }
            // (D1363) From 2026, Right focuses 2027 and Down from there 2030.
            if widget.focus(&runtime, testing.by_key(&harness, 1200u64 + 4096u64 + 7u64).element) != ok || testing.press_key(&harness, 39u32, zero) != ok { os.exit(133i32) }
            let (after_right, _) = widget.focused_key(&runtime)
            if after_right != 1200u64 + 4096u64 + 8u64 || testing.press_key(&harness, 40u32, zero) != ok { os.exit(134i32) }
            let (after_down, _) = widget.focused_key(&runtime)
            if after_down != 1200u64 + 4096u64 + 11u64 { os.exit(135i32) }
            if !tap_key(&harness, &runtime, 1200u64 + 4096u64 + 11u64) || stores[0usize].last_date.year != 2030i32 || stores[0usize].last_date.month != 3u8 || stores[0usize].toggles != toggles_before + 1usize { os.exit(121i32) }
        }
        year_step += 1usize
    }
    // (D1293) The touch picker: a dialog titled "Select date" saying "Tue, Sep 15",
    // a day press picking, OK confirming; in input mode its typed field stands in
    // the calendar's place.
    let modal_date = time.Date { year: 2026i32, month: 9u8, day: 15u8 }
    let (modal_bytes, modal_bytes_error) = mem.alloc[u8](a, 16usize)
    if modal_bytes_error != ok { os.exit(107i32) }
    var modal_step = 0usize
    while modal_step < 2usize {
        var modal_options: overlay.DateModalOptions = zero
        modal_options.typing = modal_step == 1usize
        modal_options.toggle_mode = &stores[0usize].press
        modal_options.buffer = modal_bytes
        modal_options.today = modal_date
        f = mem.arena_from(frame_storage)
        let (modal, modal_error) = overlay.date_picker_modal(&f, 1200u64, &theme, modal_date, true, modal_date, no_dates, picked_dates, true, &stores[0usize].press, &stores[0usize].press, modal_options)
        let (modal_page, modal_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if modal_error != ok || modal_page_error != ok { os.exit(108i32) }
        modal_page[0usize] = modal
        if testing.pump(&harness, widget.box(0u64, control.sized_style(600.0, 720.0), modal_page[0usize..1usize]), time.Instant { nanos: 3500000000i64 + i64(modal_step) }) != ok { os.exit(109i32) }
        // (D1369) "Select date" is a label-medium label, one 16 line tall.
        let (select_label, has_select_label) = bounds(&harness, &runtime, 1201u64)
        if !has_select_label || select_label.height > 17.0 { os.exit(142i32) }
        if modal_step == 0usize {
            if testing.by_text(&harness, "Tue, Sep 15").count == 0usize || testing.by_text(&harness, "Select date").count == 0usize { os.exit(110i32) }
            var no_day: time.Date = zero
            stores[0usize].last_date = no_day
            let (twentieth, has_twentieth) = bounds(&harness, &runtime, 1240u64 + 3u64 + 20u64)
            if !has_twentieth || testing.tap(&harness, twentieth.x + twentieth.width * 0.5, twentieth.y + twentieth.height * 0.5) != ok || stores[0usize].last_date.day != 20u8 { os.exit(111i32) }
            let (modal_tree, modal_tree_error) = testing.semantics(&harness)
            if modal_tree_error != ok { os.exit(112i32) }
            var ok_at = modal_tree.nodes.len
            var node_at = 0usize
            while node_at < modal_tree.nodes.len {
                if modal_tree.nodes[node_at].role == .Button && mem.eq[u8](modal_tree.nodes[node_at].label, "OK") { ok_at = node_at }
                node_at += 1usize
            }
            let confirms_before = stores[0usize].toggles
            if ok_at == modal_tree.nodes.len { os.exit(113i32) }
            let ok_box = modal_tree.nodes[ok_at].bounds
            if testing.tap(&harness, ok_box.x + ok_box.width * 0.5, ok_box.y + ok_box.height * 0.5) != ok || stores[0usize].toggles != confirms_before + 1usize { os.exit(113i32) }
        }
        if modal_step == 1usize && (testing.by_key(&harness, 1232u64).count != 1usize || testing.by_key(&harness, 1243u64).count != 0usize) { os.exit(114i32) }
        modal_step += 1usize
    }
    // (D1230) Times in the locale's clock, and typed times in any common form.
    let (clock_bytes, clock_bytes_error) = mem.alloc[u8](a, 16usize)
    if clock_bytes_error != ok { os.exit(50i32) }
    let half_past_two = time.Time { hour: 14u8, minute: 30u8, second: 0u8, nanos: 0u32 }
    let after_midnight = time.Time { hour: 0u8, minute: 5u8, second: 0u8, nanos: 0u32 }
    var clock_len = overlay.write_clock_in(clock_bytes, half_past_two, "en-US")
    if !mem.eq[u8](clock_bytes[0usize..clock_len], "2:30 PM") { os.exit(51i32) }
    clock_len = overlay.write_clock_in(clock_bytes, after_midnight, "en-US")
    if !mem.eq[u8](clock_bytes[0usize..clock_len], "12:05 AM") { os.exit(52i32) }
    clock_len = overlay.write_clock_in(clock_bytes, half_past_two, "de-DE")
    if !mem.eq[u8](clock_bytes[0usize..clock_len], "14:30") { os.exit(53i32) }
    clock_len = overlay.write_clock_in(clock_bytes, half_past_two, "")
    if !mem.eq[u8](clock_bytes[0usize..clock_len], "14:30") { os.exit(54i32) }
    var typed_forms: [7]str = zero
    typed_forms[0usize] = "1430"
    typed_forms[1usize] = "2:30 pm"
    typed_forms[2usize] = "14.30"
    typed_forms[3usize] = " 2:30PM "
    typed_forms[4usize] = "2:30 p.m."
    typed_forms[5usize] = "14:30"
    typed_forms[6usize] = "0230pm"
    var form = 0usize
    while form < 7usize {
        let (typed_time, typed_ok) = overlay.parse_clock(typed_forms[form])
        if !typed_ok || typed_time.hour != 14u8 || typed_time.minute != 30u8 { os.exit(i32(60usize + form)) }
        form += 1usize
    }
    let (noon, noon_ok) = overlay.parse_clock("Noon")
    let (midnight, midnight_ok) = overlay.parse_clock("midnight")
    let (early, early_ok) = overlay.parse_clock("12:15 am")
    let (nine, nine_ok) = overlay.parse_clock("9")
    if !noon_ok || noon.hour != 12u8 || !midnight_ok || midnight.hour != 0u8 || !early_ok || early.hour != 0u8 || early.minute != 15u8 || !nine_ok || nine.hour != 9u8 { os.exit(70i32) }
    let (_, late_ok) = overlay.parse_clock("25:00")
    let (_, minute_ok) = overlay.parse_clock("9:75")
    let (_, pm_ok) = overlay.parse_clock("13 pm")
    let (_, word_ok) = overlay.parse_clock("soon")
    if late_ok || minute_ok || pm_ok || word_ok { os.exit(71i32) }
    // (D1231) Dates in the locale's numeric form, its hint, and typed dates.
    let (date_bytes, date_bytes_error) = mem.alloc[u8](a, 24usize)
    if date_bytes_error != ok { os.exit(72i32) }
    let release = time.Date { year: 2026i32, month: 9u8, day: 5u8 }
    var date_len = overlay.write_date_in(date_bytes, release, "en-US")
    if !mem.eq[u8](date_bytes[0usize..date_len], "9/5/2026") || !mem.eq[u8](overlay.date_format_hint("en-US"), "mm/dd/yyyy") { os.exit(73i32) }
    date_len = overlay.write_date_in(date_bytes, release, "de-DE")
    if !mem.eq[u8](date_bytes[0usize..date_len], "05.09.2026") || !mem.eq[u8](overlay.date_format_hint("de-DE"), "dd.mm.yyyy") { os.exit(74i32) }
    date_len = overlay.write_date_in(date_bytes, release, "en-GB")
    if !mem.eq[u8](date_bytes[0usize..date_len], "05/09/2026") { os.exit(75i32) }
    date_len = overlay.write_date_in(date_bytes, release, "ja-JP")
    if !mem.eq[u8](date_bytes[0usize..date_len], "2026/09/05") { os.exit(76i32) }
    date_len = overlay.write_date_in(date_bytes, release, "")
    if !mem.eq[u8](date_bytes[0usize..date_len], "2026-09-05") { os.exit(77i32) }
    let today_date = time.Date { year: 2026i32, month: 9u8, day: 25u8 }
    let (us_date, us_ok) = overlay.parse_date("9/5/2026", "en-US", today_date)
    let (gb_date, gb_ok) = overlay.parse_date("5/9/2026", "en-GB", today_date)
    let (iso_date, iso_ok) = overlay.parse_date("2026-09-05", "en-US", today_date)
    let (named_date, named_ok) = overlay.parse_date("5 sep", "en-US", today_date)
    let (named_first, named_first_ok) = overlay.parse_date("Sep 5, 2026", "de-DE", today_date)
    let (short_date, short_ok) = overlay.parse_date("9/5", "en-US", today_date)
    if !us_ok || !gb_ok || !iso_ok || !named_ok || !named_first_ok || !short_ok { os.exit(78i32) }
    if us_date.month != 9u8 || us_date.day != 5u8 || gb_date.month != 9u8 || gb_date.day != 5u8 || iso_date.day != 5u8 || named_date.month != 9u8 || named_date.day != 5u8 || named_date.year != 2026i32 || named_first.day != 5u8 || short_date.day != 5u8 || short_date.year != 2026i32 { os.exit(79i32) }
    let (tomorrow, tomorrow_ok) = overlay.parse_date("Tomorrow", "", today_date)
    let (year_end, year_end_ok) = overlay.parse_date("tomorrow", "", time.Date { year: 2026i32, month: 12u8, day: 31u8 })
    if !tomorrow_ok || tomorrow.day != 26u8 || !year_end_ok || year_end.year != 2027i32 || year_end.month != 1u8 || year_end.day != 1u8 { os.exit(80i32) }
    let (_, feb_ok) = overlay.parse_date("30/2/2026", "en-GB", today_date)
    let (_, month_ok) = overlay.parse_date("13/13/2026", "en-GB", today_date)
    let (_, date_word_ok) = overlay.parse_date("someday", "en-US", today_date)
    let (leap, leap_ok) = overlay.parse_date("29.02.2028", "de-DE", today_date)
    if feb_ok || month_ok || date_word_ok || !leap_ok || leap.day != 29u8 { os.exit(81i32) }
    try io.print("ui pickers v2 ok\n")
    ret ok
}
