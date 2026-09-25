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
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

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
    try io.print("ui pickers v2 ok\n")
    ret ok
}
