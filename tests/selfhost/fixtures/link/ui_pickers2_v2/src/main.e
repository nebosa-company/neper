// The v2 time and duration fields (D960, widget plan P5-06, docs/ux/components)
// under the light theme at pointer density: a time field is the outlined field 40
// tall over the caller's text, its clock a 32 circle 4 in from the end, `primary`
// while the list is open; the list stands 4 below on `surface-container`, 8 above
// its 32 rows, 6 of them showing, scrolled to the selected `secondary-container`
// row. A duration field is the same field with a plain clock, its presets 32 chips
// 8 apart 12 under the supporting text, the matching one `secondary-container`;
// an invalid one has the 2px `error` outline. The typed forms read and write.

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

type Store = struct { press: widget.Submit, toggles: u32, picked: [8]u32, picks: [8]widget.Submit, times: [8]str, offsets: [8]str, presets: [3]str, clock: [8]u8, taken: [8]u8, cap: [8]u8 }

fn on_press(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.toggles += 1u32
    ret ok
}

fn on_pick(ctx: *void) -> err {
    let count = mem.cast[*u32](ctx)
    *count += 1u32
    ret ok
}

fn on_text(ctx: *void, value: str) -> err {
    ret ok
}

// (D1367) A field's text rewritten through its change, kept in its bytes.
type ClockText = struct { bytes: []u8, len: usize }

fn on_clock_text(ctx: *void, value: str) -> err {
    let r = mem.cast[*ClockText](ctx)
    var i = 0usize
    while i < value.len && i < r.bytes.len {
        r.bytes[i] = value[i]
        i += 1usize
    }
    r.len = i
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

// (D1294) The last choice a modal time picker reported.
type Chose = struct { count: usize, kind: overlay.TimeChoiceKind, value: u8 }

// (D1351) A date wheel's turn, kept.
fn on_wheel_date(ctx: *void, value: time.Date) -> err {
    let kept = mem.cast[*time.Date](ctx)
    *kept = value
    ret ok
}

// (D1350) A duration turn, kept as the unit and the value.
type SpanLog = struct { unit: u32, value: u32 }

fn on_span(ctx: *void, value: overlay.DurationChoice) -> err {
    let log = mem.cast[*SpanLog](ctx)
    log.unit = u32(value.unit)
    log.value = value.value
    ret ok
}

fn on_time(ctx: *void, value: overlay.TimeChoice) -> err {
    let c = mem.cast[*Chose](ctx)
    c.count += 1usize
    c.kind = value.kind
    c.value = value.value
    ret ok
}

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store, open: bool) -> (widget.Node, err) {
    let typed = widget.Change[str] { ctx: mem.cast[*void](s), invoke: on_text }
    var options = control.field_options()
    options.width = 200.0
    let (starts, e1) = overlay.time_field(a, 400u64, t, "Starts", s.clock[0usize..8usize], 5usize, typed, open, &s.press, s.times[0usize..8usize], s.offsets[0usize..8usize], 3usize, s.picks[0usize..8usize], "", options)
    let (timeout, e2) = overlay.duration_field(a, 500u64, t, "Build timeout", s.taken[0usize..8usize], 3usize, typed, "Reads as 45 min", s.presets[0usize..3usize], 2usize, s.picks[0usize..3usize], options)
    var wrong = options
    wrong.invalid = true
    var none: []const str = zero
    var no_picks: []const widget.Submit = zero
    let (cap, e3) = overlay.duration_field(a, 600u64, t, "Cache retention", s.cap[0usize..8usize], 4usize, typed, "Enter 999 hours or less", none, 0usize, no_picks, wrong)
    if e1 != ok { ret (zero, e1) }
    if e2 != ok { ret (zero, e2) }
    if e3 != ok { ret (zero, e3) }
    let (right, right_error) = mem.alloc[widget.Node](a, 2usize)
    if right_error != ok { ret (zero, right_error) }
    right[0usize] = timeout
    right[1usize] = cap
    let (columns, columns_error) = mem.alloc[widget.Node](a, 2usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = starts
    columns[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 24.0 }, style.defaults(), right[0usize..2usize])
    var page = style.defaults()
    page.width = style.Length { Px: 600.0 }
    page.height = style.Length { Px: 400.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 24.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 80.0 }, page, columns[0usize..2usize]), ok)
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 600usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

// An antialiased stroke: within 12 of the colour.
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

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
}

fn same(a: []const u8, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn reads(text: str, secs: i64) -> bool {
    let (d, fine) = overlay.read_duration(text)
    ret fine && d.nanos == secs * 1000000000i64
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The typed forms: read, then written with units.
    if !reads("90m", 5400i64) || !reads("90 min", 5400i64) || !reads("1h30", 5400i64) || !reads("1.5h", 5400i64) || !reads("1:30", 5400i64) || !reads("1:30:00", 5400i64) || !reads("2 hours", 7200i64) || !reads("45 s", 45i64) || !reads("45", 2700i64) { os.exit(40i32) }
    let (junk_value, junk) = overlay.read_duration("soon")
    let (empty_value, empty) = overlay.read_duration("")
    if junk || empty { os.exit(41i32) }
    var written: [32]u8 = zero
    let n1 = overlay.write_duration(written[0usize..32usize], time.Duration { nanos: 5400000000000i64 })
    if !same(written[0usize..n1], "1 h 30 min") { os.exit(42i32) }
    let n2 = overlay.write_duration(written[0usize..32usize], time.Duration { nanos: 45000000000i64 })
    if !same(written[0usize..n2], "45 s") { os.exit(43i32) }
    let n3 = overlay.write_clock(written[0usize..32usize], time.Time { hour: 9u8, minute: 5u8, second: 0u8, nanos: 0u32 })
    if !same(written[0usize..n3], "09:05") { os.exit(44i32) }
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
    let (h, harness_error) = testing.harness(a, &runtime, 600u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (stores, stores_error) = mem.alloc[Store](a, 1usize)
    if stores_error != ok { os.exit(7i32) }
    var store: Store = zero
    stores[0usize] = store
    let s = &stores[0usize]
    s.press = widget.Submit { ctx: mem.cast[*void](s), invoke: on_press }
    var i = 0usize
    while i < 8usize {
        s.picks[i] = widget.Submit { ctx: mem.cast[*void](&s.picked[i]), invoke: on_pick }
        i += 1usize
    }
    s.times[0usize] = "13:00"
    s.times[1usize] = "13:30"
    s.times[2usize] = "14:00"
    s.times[3usize] = "14:30"
    s.times[4usize] = "15:00"
    s.times[5usize] = "15:30"
    s.times[6usize] = "16:00"
    s.times[7usize] = "16:30"
    s.offsets[4usize] = "30 min"
    s.offsets[5usize] = "1 h"
    s.offsets[6usize] = "1.5 h"
    s.offsets[7usize] = "2 h"
    s.presets[0usize] = "15 min"
    s.presets[1usize] = "30 min"
    s.presets[2usize] = "45 min"
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(8i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme, s, true)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(10i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(11i32) }
    let page = style.color(&tokens, .Background)
    let primary = style.color(&tokens, .Primary)
    let muted = style.color(&tokens, .OnSurfaceVariant)
    // The time field: 200 by 40 in its 1px outline, the clock a 32 circle 4 in from
    // the end, its face and hands primary while the list is open.
    let (frame, has_frame) = bounds(&harness, &runtime, 402u64)
    let (clock, has_clock) = bounds(&harness, &runtime, 401u64)
    if !has_frame || !has_clock || !near(frame.width, 200.0) || !near(frame.height, 40.0) || !near(clock.width, 32.0) || !near(clock.height, 32.0) { os.exit(12i32) }
    if !near(clock.x + 32.0 + 4.0, frame.x + 200.0) || !near(clock.y, frame.y + 4.0) { os.exit(13i32) }
    if !roughly(shot, at(frame.x + 0.5, frame.y + 20.0), style.color(&tokens, .Outline)) || !is_color(shot, at(frame.x + 4.0, frame.y + 20.0), page) { os.exit(14i32) }
    let cx = clock.x + 16.0
    let cy = clock.y + 16.0
    if !roughly(shot, at(cx - 7.5, cy), primary) || !roughly(shot, at(cx - 0.5, cy - 3.0), primary) || !is_color(shot, at(cx - 3.5, cy + 3.5), page) { os.exit(15i32) }
    // The list: 4 below the field and as wide, 8 above six 32 rows on the container,
    // scrolled so the selected 14:30 (index 3) is the second row showing.
    let (view, has_view) = bounds(&harness, &runtime, 404u64)
    let (row, has_row) = bounds(&harness, &runtime, 405u64)
    if !has_view || !has_row || !near(view.width, 200.0) || !near(view.height, 192.0) || !near(view.x, frame.x) || !near(view.y, frame.y + 40.0 + 4.0 + 8.0) || !near(row.height, 32.0) { os.exit(16i32) }
    let menu = style.color(&tokens, .SurfaceContainer)
    let chosen = style.color(&tokens, .SecondaryContainer)
    if !is_color(shot, at(view.x + 100.0, view.y - 4.0), menu) || !is_color(shot, at(view.x + 100.0, view.y + 16.0), menu) || !is_color(shot, at(view.x + 100.0, view.y + 48.0), chosen) || !is_color(shot, at(view.x + 100.0, view.y + 80.0), menu) { os.exit(17i32) }
    // A press on the third row showing (15:00) fires its pick.
    if testing.tap(&harness, view.x + 100.0, view.y + 80.0) != ok { os.exit(18i32) }
    if s.picked[4usize] != 1u32 { os.exit(19i32) }
    // Up and Down report the rows around the caller-owned selected index.
    if testing.press_key(&harness, 38u32, zero) != ok || s.picked[2usize] != 1u32 { os.exit(45i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || s.picked[4usize] != 2u32 { os.exit(46i32) }
    // The duration field: the same 40 frame with a plain clock in on-surface-variant;
    // its chips 32 tall, 8 apart, 12 under the 4 + 16 supporting text, the 45 min
    // one secondary-container, the others outlined round the page.
    let (dframe, has_dframe) = bounds(&harness, &runtime, 502u64)
    let (dclock, has_dclock) = bounds(&harness, &runtime, 501u64)
    let (quarter, has_quarter) = bounds(&harness, &runtime, 503u64)
    let (half, has_half) = bounds(&harness, &runtime, 504u64)
    let (most, has_most) = bounds(&harness, &runtime, 505u64)
    if !has_dframe || !has_dclock || !has_quarter || !has_half || !has_most || !near(dframe.height, 40.0) || !near(dclock.x + 36.0, dframe.x + 200.0) { os.exit(20i32) }
    if !roughly(shot, at(dclock.x + 16.0 - 7.5, dclock.y + 16.0), muted) { os.exit(21i32) }
    if !near(quarter.height, 32.0) || !near(half.x - quarter.x - quarter.width, 8.0) || !near(quarter.y, dframe.y + 40.0 + 20.0 + 12.0) || !near(quarter.x, dframe.x) { os.exit(22i32) }
    if !is_color(shot, at(most.x + most.width - 6.0, most.y + 16.0), chosen) || !is_color(shot, at(quarter.x + quarter.width - 6.0, quarter.y + 16.0), page) || !roughly(shot, at(quarter.x + 0.5, quarter.y + 16.0), style.color(&tokens, .Outline)) { os.exit(23i32) }
    // The invalid field: the 2px error outline.
    let (bad, has_bad) = bounds(&harness, &runtime, 602u64)
    let error_color = style.color(&tokens, .Error)
    if !has_bad || !near(bad.height, 40.0) || !is_color(shot, at(bad.x + 0.5, bad.y + 20.0), error_color) || !is_color(shot, at(bad.x + 1.5, bad.y + 20.0), error_color) { os.exit(24i32) }
    // Alt+Down on the closed field reports its existing open toggle.
    let (closed, closed_error) = build(&f, &theme, s, false)
    if closed_error != ok || testing.pump(&harness, closed, time.Instant { nanos: 1100000000i64 }) != ok || testing.tap(&harness, frame.x + 40.0, frame.y + 20.0) != ok { os.exit(47i32) }
    var alt: input.Modifiers = zero
    alt.alt = true
    if testing.press_key(&harness, 40u32, alt) != ok || s.toggles != 1u32 { os.exit(48i32) }
    // (D1275) Unfocused the list is whole; typing "15" in the focused field
    // keeps only 15:00 and 15:30.
    let (typed_clock, typed_clock_error) = mem.alloc[u8](a, 8usize)
    if typed_clock_error != ok { os.exit(49i32) }
    typed_clock[0usize] = 49u8
    typed_clock[1usize] = 53u8
    var filter_options = control.field_options()
    filter_options.width = 200.0
    var filter_step = 0usize
    while filter_step < 2usize {
        f = mem.arena_from(frame_storage)
        let (filtered, filtered_error) = overlay.time_field(&f, 900u64, &theme, "Starts", typed_clock, 2usize, zero, true, &s.press, s.times[0usize..8usize], s.offsets[0usize..8usize], 3usize, s.picks[0usize..8usize], "", filter_options)
        let (filtered_page, filtered_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if filtered_error != ok || filtered_page_error != ok { os.exit(50i32) }
        filtered_page[0usize] = filtered
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 400.0), filtered_page[0usize..1usize]), time.Instant { nanos: 6000000000i64 + i64(filter_step) }) != ok { os.exit(51i32) }
        if filter_step == 0usize && (testing.by_key(&harness, 905u64).count != 1usize || widget.focus(&runtime, testing.by_key(&harness, 900u64).element) != ok) { os.exit(53i32) }
        filter_step += 1usize
    }
    if testing.by_key(&harness, 909u64).count != 1usize || testing.by_key(&harness, 910u64).count != 1usize || testing.by_key(&harness, 905u64).count != 0usize || testing.by_key(&harness, 908u64).count != 0usize { os.exit(52i32) }
    // (D1367) "230 pm" typed and the focus moved away: the field is rewritten
    // "14:30" on the 24-hour clock.
    let (loose_clock, loose_clock_error) = mem.alloc[u8](a, 16usize)
    if loose_clock_error != ok { os.exit(99i32) }
    let loose_words = "230 pm"
    var lc = 0usize
    while lc < loose_words.len {
        loose_clock[lc] = loose_words[lc]
        lc += 1usize
    }
    var clock_text = ClockText { bytes: loose_clock, len: loose_words.len }
    var clock_step = 0usize
    while clock_step < 5usize {
        f = mem.arena_from(frame_storage)
        let (loose_field, loose_field_error) = overlay.time_field(&f, 1900u64, &theme, "Starts", loose_clock, clock_text.len, widget.Change[str] { ctx: mem.cast[*void](&clock_text), invoke: on_clock_text }, false, &s.press, s.times[0usize..8usize], s.offsets[0usize..8usize], 3usize, s.picks[0usize..8usize], "", filter_options)
        let (clock_page, clock_page_error) = mem.alloc[widget.Node](&f, 2usize)
        if loose_field_error != ok || clock_page_error != ok { os.exit(100i32) }
        clock_page[0usize] = loose_field
        clock_page[1usize] = widget.region(1995u64, widget.Region { gesture: zero, gestures: 0u8, enabled: true, focusable: true }, control.sized_style(40.0, 40.0), zero)
        if testing.pump(&harness, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, control.sized_style(400.0, 400.0), clock_page[0usize..2usize]), time.Instant { nanos: 6050000000i64 + i64(clock_step) }) != ok { os.exit(101i32) }
        if clock_step == 1usize && widget.focus(&runtime, testing.by_key(&harness, 1900u64).element) != ok { os.exit(102i32) }
        if clock_step == 2usize && widget.focus(&runtime, testing.by_key(&harness, 1995u64).element) != ok { os.exit(103i32) }
        clock_step += 1usize
    }
    if !testing.same_text(loose_clock[0usize..clock_text.len], "14:30") { os.exit(104i32) }
    // (D1368) Focused with the caret at the end, Up makes 14:31; at the start, Up
    // steps the hour to 15:31 (the field reads the caller's buffer).
    if widget.focus(&runtime, testing.by_key(&harness, 1900u64).element) != ok || testing.press_key(&harness, 35u32, zero) != ok || testing.press_key(&harness, 38u32, zero) != ok { os.exit(105i32) }
    if !testing.same_text(loose_clock[0usize..clock_text.len], "14:31") { os.exit(106i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || testing.press_key(&harness, 38u32, zero) != ok { os.exit(107i32) }
    if !testing.same_text(loose_clock[0usize..clock_text.len], "15:31") { os.exit(108i32) }
    // (D1294) The dial picker at 14:30 on a 12-hour clock: the hour box says 02
    // and PM is chosen; the dial's 3 sets 15, the minute box asks to be edited,
    // and on the minute dial the sixth number sets 30.
    var chose: Chose = zero
    let time_change = widget.Change[overlay.TimeChoice] { ctx: mem.cast[*void](&chose), invoke: on_time }
    var dial_step = 0usize
    while dial_step < 2usize {
        f = mem.arena_from(frame_storage)
        let (dial_modal, dial_modal_error) = overlay.time_picker_modal(&f, 1300u64, &theme, 14u8, 30u8, dial_step == 1usize, true, true, time_change, &s.press, &s.press)
        let (dial_page, dial_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if dial_modal_error != ok || dial_page_error != ok { os.exit(59i32) }
        dial_page[0usize] = dial_modal
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 400.0), dial_page[0usize..1usize]), time.Instant { nanos: 6100000000i64 + i64(dial_step) }) != ok { os.exit(54i32) }
        if dial_step == 0usize {
            if testing.by_text(&harness, "02").count == 0usize || testing.by_text(&harness, "30").count == 0usize { os.exit(55i32) }
            let (three, has_three) = bounds(&harness, &runtime, 1313u64)
            if !has_three || testing.tap(&harness, three.x + 24.0, three.y + 24.0) != ok || chose.kind != .Hour || chose.value != 15u8 { os.exit(56i32) }
            let (minute_box, has_minute_box) = bounds(&harness, &runtime, 1302u64)
            if !has_minute_box || testing.tap(&harness, minute_box.x + 40.0, minute_box.y + 32.0) != ok || chose.kind != .EditMinute { os.exit(57i32) }
            // (D1306) Focused, the dial's Up sets 15 and Down 13.
            if widget.focus(&runtime, testing.by_key(&harness, 1307u64).element) != ok || testing.press_key(&harness, 38u32, zero) != ok || chose.kind != .Hour || chose.value != 15u8 { os.exit(67i32) }
            if testing.press_key(&harness, 40u32, zero) != ok || chose.value != 13u8 { os.exit(68i32) }
            // (D1362) Dragged from the top round to three o'clock the hour is 15;
            // released, the minutes are asked for.
            let (ring, has_ring) = bounds(&harness, &runtime, 1307u64)
            if !has_ring { os.exit(95i32) }
            let hub = geometry.Point { x: ring.x + ring.width * 0.5, y: ring.y + ring.height * 0.5 }
            if testing.send(&harness, input.Event { PointerDown: testing.pointer_at(hub.x, hub.y - 50.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(hub.x + 10.0, hub.y - 50.0) }) != ok || testing.send(&harness, input.Event { PointerMove: testing.pointer_at(hub.x + 50.0, hub.y) }) != ok { os.exit(96i32) }
            if chose.kind != .Hour || chose.value != 15u8 { os.exit(97i32) }
            if testing.send(&harness, input.Event { PointerUp: testing.pointer_at(hub.x + 50.0, hub.y) }) != ok || chose.kind != .EditMinute { os.exit(98i32) }
        }
        if dial_step == 1usize {
            let (thirty, has_thirty) = bounds(&harness, &runtime, 1316u64)
            if !has_thirty || testing.tap(&harness, thirty.x + 24.0, thirty.y + 24.0) != ok || chose.kind != .Minute || chose.value != 30u8 { os.exit(58i32) }
            // (D1306) On the minute dial Page Up sets 35 and Left 29.
            if widget.focus(&runtime, testing.by_key(&harness, 1307u64).element) != ok || testing.press_key(&harness, 33u32, zero) != ok || chose.kind != .Minute || chose.value != 35u8 { os.exit(69i32) }
            if testing.press_key(&harness, 37u32, zero) != ok || chose.value != 29u8 { os.exit(70i32) }
        }
        dial_step += 1usize
    }
    // (D1295) Input mode: the boxes are typed fields, the dial gives way, and the
    // mode toggle is there to switch back.
    let (hour_text, hour_text_error) = mem.alloc[u8](a, 4usize)
    let (minute_text, minute_text_error) = mem.alloc[u8](a, 4usize)
    if hour_text_error != ok || minute_text_error != ok { os.exit(60i32) }
    var typing_options: overlay.TimeModalOptions = zero
    typing_options.typing = true
    typing_options.toggle_mode = &s.press
    typing_options.hour_text = hour_text
    typing_options.minute_text = minute_text
    f = mem.arena_from(frame_storage)
    let (typing_modal, typing_error) = overlay.time_picker_modal_with(&f, 1300u64, &theme, 14u8, 30u8, false, true, true, time_change, &s.press, &s.press, typing_options)
    let (typing_page, typing_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if typing_error != ok || typing_page_error != ok { os.exit(61i32) }
    typing_page[0usize] = typing_modal
    if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 400.0), typing_page[0usize..1usize]), time.Instant { nanos: 6200000000i64 }) != ok { os.exit(62i32) }
    let (_, _, has_typed_hour) = widget.edit_selection(&runtime, testing.by_key(&harness, 1301u64).element)
    if !has_typed_hour || testing.by_key(&harness, 1305u64).count != 0usize || testing.by_key(&harness, 1306u64).count != 1usize { os.exit(63i32) }
    // (D1296) In a field 70 wide the three presets wrap: the third chip stands
    // on a row below the first.
    var narrow_duration = control.field_options()
    narrow_duration.width = 70.0
    f = mem.arena_from(frame_storage)
    let (wrapped, wrapped_error) = overlay.duration_field(&f, 1400u64, &theme, "Build timeout", s.taken[0usize..8usize], 3usize, zero, "", s.presets[0usize..3usize], 0usize, s.picks[0usize..3usize], narrow_duration)
    let (wrapped_page, wrapped_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if wrapped_error != ok || wrapped_page_error != ok { os.exit(64i32) }
    wrapped_page[0usize] = wrapped
    if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 400.0), wrapped_page[0usize..1usize]), time.Instant { nanos: 6300000000i64 }) != ok { os.exit(65i32) }
    let (first_chip, has_first_chip) = bounds(&harness, &runtime, 1403u64)
    let (third_chip, has_third_chip) = bounds(&harness, &runtime, 1405u64)
    if !has_first_chip || !has_third_chip || !(third_chip.y > first_chip.y + 1.0) { os.exit(66i32) }
    // (D1349) The time wheels at 14:30 on a 12-hour clock: a tap on the row
    // under the hour's picks 3 PM (15); Down on the minutes sets 31; a drag of
    // two rows up turns the hours to 4 PM (16).
    var wheel_step = 0usize
    while wheel_step < 2usize {
        f = mem.arena_from(frame_storage)
        let (wheels, wheels_error) = overlay.time_wheels(&f, 1500u64, &theme, 14u8, 30u8, true, time_change)
        let (wheel_page, wheel_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if wheels_error != ok || wheel_page_error != ok { os.exit(71i32) }
        wheel_page[0usize] = wheels
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 400.0), wheel_page[0usize..1usize]), time.Instant { nanos: 6400000000i64 + i64(wheel_step) }) != ok { os.exit(72i32) }
        wheel_step += 1usize
    }
    if testing.by_text(&harness, "02").count == 0usize || testing.by_text(&harness, "PM").count == 0usize { os.exit(73i32) }
    let (next_hour, has_next_hour) = bounds(&harness, &runtime, 1504u64)
    if !has_next_hour || testing.tap(&harness, next_hour.x + 20.0, next_hour.y + 18.0) != ok || chose.kind != .Hour || chose.value != 15u8 { os.exit(74i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 1516u64).element) != ok || testing.press_key(&harness, 40u32, zero) != ok || chose.kind != .Minute || chose.value != 31u8 { os.exit(75i32) }
    let (hour_wheel, has_hour_wheel) = bounds(&harness, &runtime, 1500u64)
    if !has_hour_wheel { os.exit(76i32) }
    let turn_from = geometry.Point { x: hour_wheel.x + 36.0, y: hour_wheel.y + 150.0 }
    if testing.drag(&harness, turn_from, geometry.Point { x: turn_from.x, y: turn_from.y - 72.0 }, 8usize) != ok || chose.kind != .Hour || chose.value != 16u8 { os.exit(77i32) }
    // (D1350) Duration wheels at 1 h 20 min 5 s: Down on the seconds sets 6, a
    // press under the minutes picks 21.
    var span_log: SpanLog = zero
    var span_step = 0usize
    while span_step < 2usize {
        f = mem.arena_from(frame_storage)
        let (spans, spans_error) = overlay.duration_wheels(&f, 1600u64, &theme, 1u32, 20u32, 5u32, widget.Change[overlay.DurationChoice] { ctx: mem.cast[*void](&span_log), invoke: on_span })
        let (span_page, span_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if spans_error != ok || span_page_error != ok { os.exit(78i32) }
        span_page[0usize] = spans
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 400.0), span_page[0usize..1usize]), time.Instant { nanos: 6500000000i64 + i64(span_step) }) != ok { os.exit(79i32) }
        span_step += 1usize
    }
    if widget.focus(&runtime, testing.by_key(&harness, 1632u64).element) != ok || testing.press_key(&harness, 40u32, zero) != ok || span_log.unit != 2u32 || span_log.value != 6u32 { os.exit(80i32) }
    let (next_minute, has_next_minute) = bounds(&harness, &runtime, 1620u64)
    if !has_next_minute || testing.tap(&harness, next_minute.x + 20.0, next_minute.y + 18.0) != ok || span_log.unit != 1u32 || span_log.value != 21u32 { os.exit(81i32) }
    // (D1351) Date wheels on 31 January 2026: Down on the month lands on 28
    // February; Up on the year sets 2025.
    var wheel_date: time.Date = zero
    var date_step = 0usize
    while date_step < 2usize {
        f = mem.arena_from(frame_storage)
        let (dates, dates_error) = overlay.date_wheels(&f, 1700u64, &theme, time.Date { year: 2026i32, month: 1u8, day: 31u8 }, widget.Change[time.Date] { ctx: mem.cast[*void](&wheel_date), invoke: on_wheel_date })
        let (date_page, date_page_error) = mem.alloc[widget.Node](&f, 1usize)
        if dates_error != ok || date_page_error != ok { os.exit(82i32) }
        date_page[0usize] = dates
        if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 400.0), date_page[0usize..1usize]), time.Instant { nanos: 6600000000i64 + i64(date_step) }) != ok { os.exit(83i32) }
        date_step += 1usize
    }
    if testing.by_text(&harness, "January").count == 0usize { os.exit(84i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 1700u64).element) != ok || testing.press_key(&harness, 40u32, zero) != ok || wheel_date.month != 2u8 || wheel_date.day != 28u8 { os.exit(85i32) }
    if widget.focus(&runtime, testing.by_key(&harness, 1732u64).element) != ok || testing.press_key(&harness, 38u32, zero) != ok || wheel_date.year != 2025i32 || wheel_date.month != 1u8 { os.exit(86i32) }
    // (D1352) Unit boxes: three editable boxes; 75 min rolls to 1 h 15 min, and
    // 30 h 90 min holds at 24 h.
    let (unit_bytes, unit_bytes_error) = mem.alloc[u8](a, 12usize)
    if unit_bytes_error != ok { os.exit(87i32) }
    var unit_boxes: overlay.DurationBoxes = zero
    unit_boxes.hours = unit_bytes[0usize..4usize]
    unit_boxes.minutes = unit_bytes[4usize..8usize]
    unit_boxes.seconds = unit_bytes[8usize..12usize]
    f = mem.arena_from(frame_storage)
    let (units_node, units_error) = overlay.duration_boxes(&f, 1800u64, &theme, unit_boxes)
    let (units_page, units_page_error) = mem.alloc[widget.Node](&f, 1usize)
    if units_error != ok || units_page_error != ok { os.exit(88i32) }
    units_page[0usize] = units_node
    if testing.pump(&harness, widget.box(0u64, control.sized_style(400.0, 400.0), units_page[0usize..1usize]), time.Instant { nanos: 6700000000i64 }) != ok { os.exit(89i32) }
    var unit_key = 1801u64
    while unit_key <= 1803u64 {
        let (_, _, has_unit_edit) = widget.edit_selection(&runtime, testing.by_key(&harness, unit_key).element)
        if !has_unit_edit { os.exit(90i32) }
        unit_key += 1u64
    }
    // (D1354) Two digits in the hours box move focus to the minutes box.
    if widget.focus(&runtime, testing.by_key(&harness, 1801u64).element) != ok || testing.type_text(&harness, "1") != ok { os.exit(92i32) }
    let (after_one, _) = widget.focused_key(&runtime)
    if after_one != 1801u64 || testing.type_text(&harness, "2") != ok { os.exit(93i32) }
    let (after_two, _) = widget.focused_key(&runtime)
    if after_two != 1802u64 { os.exit(94i32) }
    let (rolled_h, rolled_m, rolled_s) = overlay.duration_roll(0u32, 75u32, 0u32, 999u32)
    let (held_h, _, _) = overlay.duration_roll(30u32, 90u32, 0u32, 24u32)
    if rolled_h != 1u32 || rolled_m != 15u32 || rolled_s != 0u32 || held_h != 24u32 { os.exit(91i32) }
    try io.print("ui pickers2 v2 ok\n")
    ret ok
}
