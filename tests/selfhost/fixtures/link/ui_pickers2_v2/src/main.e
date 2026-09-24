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
use e.ui.layout as ui_layout
use e.ui.overlay
use e.ui.style
use e.ui.testing
use e.ui.widget

type Store = struct { press: widget.Submit, picked: u32, picks: [8]widget.Submit, times: [8]str, offsets: [8]str, presets: [3]str, clock: [8]u8, taken: [8]u8, cap: [8]u8 }

fn on_press(ctx: *void) -> err {
    ret ok
}

fn on_pick(ctx: *void) -> err {
    let s = mem.cast[*Store](ctx)
    s.picked += 1u32
    ret ok
}

fn on_text(ctx: *void, value: str) -> err {
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

fn build(a: *mem.Arena, t: *const control.Theme, s: *Store) -> (widget.Node, err) {
    let typed = widget.Change[str] { ctx: mem.cast[*void](s), invoke: on_text }
    var options = control.field_options()
    options.width = 200.0
    let (starts, e1) = overlay.time_field(a, 400u64, t, "Starts", s.clock[0usize..8usize], 5usize, typed, true, &s.press, s.times[0usize..8usize], s.offsets[0usize..8usize], 3usize, s.picks[0usize..8usize], "", options)
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
        s.picks[i] = widget.Submit { ctx: mem.cast[*void](s), invoke: on_pick }
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
    let (root, build_error) = build(&f, &theme, s)
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
    if s.picked != 1u32 { os.exit(19i32) }
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
    try io.print("ui pickers2 v2 ok\n")
    ret ok
}
