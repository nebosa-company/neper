// `e.ui.control`'s range selection (D820, widget plan P1-08) under the light theme:
// a slider sets its value from a press along the track, follows a drag, snaps to
// its step, moves by the arrow keys and jumps by Home and End when focused, and
// reports each change; a range slider moves the thumb nearer the press; the tree
// says slider; the filled part of the track paints in the primary colour up to
// the thumb.

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
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { value: f32, changes: usize, first: f32, second: f32, range_changes: usize }

fn on_value(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.value = value
    log.changes += 1usize
    ret ok
}

fn on_first(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.first = value
    log.range_changes += 1usize
    ret ok
}

fn on_second(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.second = value
    log.range_changes += 1usize
    ret ok
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn build(a: *mem.Arena, t: *const control.Theme, log: *const Log, ctx: *void) -> (widget.Node, err) {
    let (items, items_error) = mem.alloc[widget.Node](a, 2usize)
    if items_error != ok { ret (zero, items_error) }
    let (volume, volume_error) = control.slider(a, 1u64, t, "Volume", log.value, 0.0, 100.0, 5.0, widget.Change[f32] { ctx: ctx, invoke: on_value }, true)
    if volume_error != ok { ret (zero, volume_error) }
    items[0usize] = volume
    let (span, span_error) = control.range_slider(a, 2u64, t, "Span", log.first, log.second, 0.0, 100.0, 0.0, widget.Change[f32] { ctx: ctx, invoke: on_first }, widget.Change[f32] { ctx: ctx, invoke: on_second }, true)
    if span_error != ok { ret (zero, span_error) }
    items[1usize] = span
    var column = style.defaults()
    column.width = style.Length { Px: 200.0 }
    column.height = style.Length { Px: 100.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, column, items[0usize..2usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    var tokens = style.reference(.Light)
    let (fonts, fonts_error) = mem.alloc[shape.Font](a, 0usize)
    if fonts_error != ok { os.exit(4i32) }
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 32usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 128usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 200u32, 100u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    logs[0usize] = Log { value: 20.0, changes: 0usize, first: 20.0, second: 80.0, range_changes: 0usize }
    let ctx = mem.cast[*void](&logs[0usize])
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(8i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, &theme, &logs[0usize], ctx)
    if build_error != ok { os.exit(9i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(10i32) }
    if testing.by_role(&harness, .Slider).count != 2usize { os.exit(11i32) }
    // The track spans the 120 px box less the 16 px thumb: 104 px from x + 8. A press
    // at 60% of it sets 60 (snapped to the step of 5) and reports it.
    let volume = testing.by_key(&harness, 1u64).element
    let (track, has_track) = widget.bounds_of(&runtime, volume)
    if !has_track || !near(track.width, 120.0) { os.exit(12i32) }
    let mid_y = track.y + track.height * 0.5
    if testing.tap(&harness, track.x + 8.0 + 104.0 * 0.6, mid_y) != ok { os.exit(13i32) }
    let (after_tap, _, has_value) = widget.slider_value_of(&runtime, volume)
    if !has_value || !near(after_tap, 60.0) || logs[0usize].changes != 1usize || !near(logs[0usize].value, 60.0) { os.exit(14i32) }
    // A press between steps snaps: 63% is 65 (the nearer step).
    if testing.tap(&harness, track.x + 8.0 + 104.0 * 0.63, mid_y) != ok { os.exit(15i32) }
    let (snapped, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(snapped, 65.0) { os.exit(16i32) }
    // A drag from the thumb to the start takes the value to 0; past the end, 100.
    if testing.drag(&harness, geometry.Point { x: track.x + 8.0 + 104.0 * 0.65, y: mid_y }, geometry.Point { x: track.x - 10.0, y: mid_y }, 3usize) != ok { os.exit(17i32) }
    let (dragged, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(dragged, 0.0) { os.exit(18i32) }
    if testing.drag(&harness, geometry.Point { x: track.x + 8.0, y: mid_y }, geometry.Point { x: track.x + 200.0, y: mid_y }, 2usize) != ok { os.exit(19i32) }
    let (dragged_far, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(dragged_far, 100.0) { os.exit(20i32) }
    // Focused by the press, the keys move it: Left twice is 90, Home 0, End 100,
    // Right 5 -- hmm, Right from 100 stays; so Home then Right is 5.
    if testing.press_key(&harness, 37u32, zero) != ok || testing.press_key(&harness, 37u32, zero) != ok { os.exit(21i32) }
    let (keyed, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(keyed, 90.0) { os.exit(22i32) }
    if testing.press_key(&harness, 36u32, zero) != ok || testing.press_key(&harness, 39u32, zero) != ok { os.exit(23i32) }
    let (homed, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(homed, 5.0) { os.exit(24i32) }
    if testing.press_key(&harness, 35u32, zero) != ok { os.exit(25i32) }
    let (ended, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(ended, 100.0) { os.exit(26i32) }
    // The caller keeps the value: a frame built with 50 shows 50; the fill reaches
    // half the track in the primary colour and no further.
    logs[0usize].value = 50.0
    let (root_2, build_2_error) = build(&frame, &theme, &logs[0usize], ctx)
    if build_2_error != ok { os.exit(27i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(28i32) }
    let (shown, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(shown, 50.0) { os.exit(29i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(30i32) }
    let primary = style.color(&tokens, .Primary)
    let y = usize(mid_y)
    let inside = (y * 200usize + usize(track.x + 8.0 + 104.0 * 0.25)) * 4usize
    let beyond = (y * 200usize + usize(track.x + 8.0 + 104.0 * 0.75)) * 4usize
    if !(f32(shot.pixels[inside + 2usize]) > primary.blue * 255.0 - 3.0) || !(f32(shot.pixels[inside]) < primary.red * 255.0 + 3.0) { os.exit(31i32) }
    if !(shot.pixels[beyond] > shot.pixels[inside] + 40u8) { os.exit(32i32) }
    // The range slider: a press near the second thumb moves that one.
    let span = testing.by_key(&harness, 2u64).element
    let (span_track, has_span) = widget.bounds_of(&runtime, span)
    if !has_span { os.exit(33i32) }
    let span_y = span_track.y + span_track.height * 0.5
    if testing.tap(&harness, span_track.x + 8.0 + 104.0 * 0.9, span_y) != ok { os.exit(34i32) }
    let (first_now, second_now, _) = widget.slider_value_of(&runtime, span)
    if !near(first_now, 20.0) || !near(second_now, 90.0) || logs[0usize].range_changes != 1usize || !near(logs[0usize].second, 90.0) { os.exit(35i32) }
    if testing.tap(&harness, span_track.x + 8.0 + 104.0 * 0.1, span_y) != ok { os.exit(36i32) }
    let (first_2, second_2, _) = widget.slider_value_of(&runtime, span)
    if !near(first_2, 10.0) || !near(second_2, 90.0) || !near(logs[0usize].first, 10.0) { os.exit(37i32) }
    // RTL swaps only horizontal arrows. Page Up/Down remain logical ten-percent
    // moves, while vertical arrows retain increase/decrease.
    tokens.direction = .RightToLeft
    logs[0usize].value = 50.0
    let (rtl_root, rtl_error) = build(&frame, &theme, &logs[0usize], ctx)
    if rtl_error != ok || testing.pump(&harness, rtl_root, time.Instant { nanos: 2000000000i64 }) != ok { os.exit(39i32) }
    if testing.tap(&harness, track.x + 8.0 + 104.0 * 0.5, mid_y) != ok { os.exit(40i32) }
    if testing.press_key(&harness, 37u32, zero) != ok { os.exit(41i32) }
    let (rtl_left, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(rtl_left, 55.0) { os.exit(42i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || testing.press_key(&harness, 33u32, zero) != ok { os.exit(43i32) }
    let (rtl_page_up, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(rtl_page_up, 60.0) { os.exit(44i32) }
    if testing.press_key(&harness, 34u32, zero) != ok || testing.press_key(&harness, 38u32, zero) != ok { os.exit(45i32) }
    let (rtl_vertical, _, _) = widget.slider_value_of(&runtime, volume)
    if !near(rtl_vertical, 55.0) { os.exit(46i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(38i32) }
    try io.print("ui slider ok\n")
    ret ok
}
