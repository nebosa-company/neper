// `e.ui.overlay`'s pickers (D842, widget plan P2-10) under the light theme: a
// calendar lays a month out Monday first with its days as buttons, the selected
// one filled, and turns months from its header; a date picker opens it in a
// flyout and shows the value as digits; a range picker tints the days between; a
// time picker and a duration picker step their parts and report the whole; a
// colour picker's sliders move one channel each.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
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

type Log = struct { shows: usize, shown: time.Date, picks: usize, picked: time.Date, toggles: usize, times: usize, clock: time.Time, spans: usize, span: time.Duration, colours: usize, colour: paint.Color }

fn on_show(ctx: *void, value: time.Date) -> err {
    let log = mem.cast[*Log](ctx)
    log.shows += 1usize
    log.shown = value
    ret ok
}

fn on_pick(ctx: *void, value: time.Date) -> err {
    let log = mem.cast[*Log](ctx)
    log.picks += 1usize
    log.picked = value
    ret ok
}

fn on_toggle(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.toggles += 1usize
    ret ok
}

fn on_time(ctx: *void, value: time.Time) -> err {
    let log = mem.cast[*Log](ctx)
    log.times += 1usize
    log.clock = value
    ret ok
}

fn on_span(ctx: *void, value: time.Duration) -> err {
    let log = mem.cast[*Log](ctx)
    log.spans += 1usize
    log.span = value
    ret ok
}

fn on_colour(ctx: *void, value: paint.Color) -> err {
    let log = mem.cast[*Log](ctx)
    log.colours += 1usize
    log.colour = value
    ret ok
}

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn near(a: f32, b: f32, within: f32) -> bool {
    let d = a - b
    ret d < within && d > 0.0 - within
}

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, toggle: *const widget.Submit, open: bool, range_open: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 6usize)
    if parts_error != ok { ret (zero, parts_error) }
    // March 2026: the 1st is a Sunday, 31 days.
    let march = time.Date { year: 2026i32, month: 3u8, day: 1u8 }
    let chosen = time.Date { year: 2026i32, month: 3u8, day: 10u8 }
    let (month, month_error) = overlay.calendar(a, 1u64, t, "March", march, chosen, true, false, chosen, chosen, widget.Change[time.Date] { ctx: ctx, invoke: on_show }, widget.Change[time.Date] { ctx: ctx, invoke: on_pick })
    if month_error != ok { ret (zero, month_error) }
    parts[0usize] = month
    let (day, day_error) = overlay.date_picker(a, 100u64, t, "Due", chosen, true, open, toggle, march, widget.Change[time.Date] { ctx: ctx, invoke: on_show }, widget.Change[time.Date] { ctx: ctx, invoke: on_pick })
    if day_error != ok { ret (zero, day_error) }
    parts[1usize] = day
    let until = time.Date { year: 2026i32, month: 3u8, day: 14u8 }
    let (span, span_error) = overlay.date_range_picker(a, 200u64, t, "Stay", chosen, until, true, range_open, toggle, march, widget.Change[time.Date] { ctx: ctx, invoke: on_show }, widget.Change[time.Date] { ctx: ctx, invoke: on_pick })
    if span_error != ok { ret (zero, span_error) }
    parts[2usize] = span
    let (clock, clock_error) = overlay.time_picker(a, 300u64, t, "At", time.Time { hour: 9u8, minute: 30u8, second: 0u8, nanos: 0u32 }, false, widget.Change[time.Time] { ctx: ctx, invoke: on_time })
    if clock_error != ok { ret (zero, clock_error) }
    parts[3usize] = clock
    let (length, length_error) = overlay.duration_picker(a, 400u64, t, "For", time.Duration { nanos: 5445000000000i64 }, widget.Change[time.Duration] { ctx: ctx, invoke: on_span })
    if length_error != ok { ret (zero, length_error) }
    parts[4usize] = length
    let (tint, tint_error) = overlay.color_picker(a, 500u64, t, "Tint", paint.rgba(0.2, 0.4, 0.6, 1.0), false, widget.Change[paint.Color] { ctx: ctx, invoke: on_colour }, 240.0)
    if tint_error != ok { ret (zero, tint_error) }
    parts[5usize] = tint
    var column = style.defaults()
    column.width = style.Length { Px: 400.0 }
    column.height = style.Length { Px: 700.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, parts[0usize..6usize]), ok)
}

fn find(tree: accessibility.Tree, role: accessibility.Role, label: str) -> (accessibility.Node, bool) {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == role && same(tree.nodes[i].label, label) { ret (tree.nodes[i], true) }
        i += 1usize
    }
    ret (zero, false)
}

fn centre_of(h: *testing.Harness, runtime: *const widget.Runtime, key: widget.Key) -> (geometry.Point, bool) {
    let found = testing.by_key(h, key)
    if found.count != 1usize { ret (zero, false) }
    let (area, has_area) = widget.bounds_of(runtime, found.element)
    if !has_area { ret (zero, false) }
    ret (geometry.Point { x: area.x + area.width * 0.5, y: area.y + area.height * 0.5 }, true)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 512usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 16u16, max_commands: 1024usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 400u32, 700u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (toggles, toggles_error) = mem.alloc[widget.Submit](a, 1usize)
    if toggles_error != ok { os.exit(8i32) }
    toggles[0usize] = widget.Submit { ctx: ctx, invoke: on_toggle }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(9i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, ctx, &toggles[0usize], false, false)
    if build_error != ok { os.exit(10i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(12i32) }
    // The calendar: a grid of seven columns and six weeks (a Sunday start and 31
    // days), the 10th selected; the 1st stands in the last column of the first
    // week and the 2nd starts the second; the 10th's button says selected; the
    // 25th picks; Next shows April the 1st, Previous February.
    let (grid, has_grid) = find(tree, .Grid, "March")
    if !has_grid || grid.position.column_count != 7u32 || grid.position.row_count != 6u32 { os.exit(13i32) }
    let (first_bounds, has_first) = widget.bounds_of(&runtime, testing.by_key(&harness, 5u64).element)
    let (second_bounds, has_second) = widget.bounds_of(&runtime, testing.by_key(&harness, 6u64).element)
    let (eighth_bounds, has_eighth) = widget.bounds_of(&runtime, testing.by_key(&harness, 12u64).element)
    if !has_first || !has_second || !has_eighth { os.exit(14i32) }
    if second_bounds.y <= first_bounds.y || second_bounds.x >= first_bounds.x || eighth_bounds.y != second_bounds.y || eighth_bounds.x <= second_bounds.x { os.exit(15i32) }
    let (tenth, has_tenth) = find(tree, .Button, "10")
    if !has_tenth || !tenth.state.selected { os.exit(16i32) }
    let (day_25, has_25) = centre_of(&harness, &runtime, 29u64)
    if !has_25 || testing.tap(&harness, day_25.x, day_25.y) != ok || logs[0usize].picks != 1usize || logs[0usize].picked.day != 25u8 || logs[0usize].picked.month != 3u8 { os.exit(17i32) }
    let (next_at, has_next) = centre_of(&harness, &runtime, 3u64)
    if !has_next || testing.tap(&harness, next_at.x, next_at.y) != ok || logs[0usize].shows != 1usize || logs[0usize].shown.month != 4u8 || logs[0usize].shown.day != 1u8 { os.exit(18i32) }
    let (previous_at, has_previous) = centre_of(&harness, &runtime, 2u64)
    if !has_previous || testing.tap(&harness, previous_at.x, previous_at.y) != ok || logs[0usize].shows != 2usize || logs[0usize].shown.month != 2u8 || logs[0usize].shown.year != 2026i32 { os.exit(19i32) }
    // The date picker: its button reads the date; a tap toggles; open, a calendar
    // stands in a flyout below and a day picks; Escape toggles.
    if testing.by_text(&harness, "2026-03-10").count == 0usize { os.exit(20i32) }
    let (due_at, has_due) = centre_of(&harness, &runtime, 100u64)
    if !has_due || testing.tap(&harness, due_at.x, due_at.y) != ok || logs[0usize].toggles != 1usize { os.exit(21i32) }
    let (root_2, build_2_error) = build(&frame, &theme, ctx, &toggles[0usize], true, false)
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(22i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(23i32) }
    let (due_group, has_due_group) = find(tree_2, .Group, "Due")
    if !has_due_group || !due_group.state.expanded || testing.by_role(&harness, .Grid).count != 2usize { os.exit(24i32) }
    let (day_3, has_3) = centre_of(&harness, &runtime, 100u64 + 2u64 + 3u64 + 3u64)
    if !has_3 || testing.tap(&harness, day_3.x, day_3.y) != ok || logs[0usize].picks != 2usize || logs[0usize].picked.day != 3u8 { os.exit(25i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].toggles != 2usize { os.exit(26i32) }
    // The range picker: the button reads both dates.
    if testing.by_text(&harness, "2026-03-10 - 2026-03-14").count == 0usize { os.exit(27i32) }
    // The time picker: the hour's plus reports 10:30, the minute's minus 9:29.
    let (root_3, build_3_error) = build(&frame, &theme, ctx, &toggles[0usize], false, false)
    if build_3_error != ok || testing.pump(&harness, root_3, now) != ok { os.exit(28i32) }
    let (hour_plus, has_hour_plus) = centre_of(&harness, &runtime, 303u64)
    if !has_hour_plus || testing.tap(&harness, hour_plus.x, hour_plus.y) != ok || logs[0usize].times != 1usize || logs[0usize].clock.hour != 10u8 || logs[0usize].clock.minute != 30u8 { os.exit(29i32) }
    let (minute_minus, has_minute_minus) = centre_of(&harness, &runtime, 305u64)
    if !has_minute_minus || testing.tap(&harness, minute_minus.x, minute_minus.y) != ok || logs[0usize].clock.hour != 9u8 || logs[0usize].clock.minute != 29u8 { os.exit(30i32) }
    // The duration picker over 1:30:45: the minutes' plus reports 1:31:45.
    let (tree_3, tree_3_error) = testing.semantics(&harness)
    if tree_3_error != ok { os.exit(31i32) }
    let (hours_node, has_hours) = find(tree_3, .Slider, "Hours")
    if !has_hours || !same(hours_node.value, "1") { os.exit(32i32) }
    let (minutes_plus, has_minutes_plus) = centre_of(&harness, &runtime, 406u64)
    if !has_minutes_plus || testing.tap(&harness, minutes_plus.x, minutes_plus.y) != ok || logs[0usize].spans != 1usize || logs[0usize].span.nanos != 5505000000000i64 { os.exit(33i32) }
    // The colour picker: End on the focused red slider reports red 1 with the
    // other channels kept.
    let (red_at, has_red) = centre_of(&harness, &runtime, 501u64)
    if !has_red || testing.tap(&harness, red_at.x, red_at.y) != ok || testing.press_key(&harness, 35u32, zero) != ok { os.exit(34i32) }
    if logs[0usize].colours == 0usize || !near(logs[0usize].colour.red, 1.0, 0.001) || !near(logs[0usize].colour.green, 0.4, 0.001) || !near(logs[0usize].colour.blue, 0.6, 0.001) { os.exit(35i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(36i32) }
    try io.print("ui pickers ok\n")
    ret ok
}
