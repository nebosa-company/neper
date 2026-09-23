// `e.ui.control`'s numeric and shortcut input (D830, widget plan P2-02) under the
// light theme: a stepper's buttons and Up/Down move the caller's value within its
// bounds and disable at them; a spin box shows the value in a text field, steps it
// and reports what is typed; a dial turns to where the pointer points and by a
// hundredth on the arrow keys; a shortcut recorder names a chord, and while
// recording takes every key -- a lone modifier waited through, Escape as none.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.scene
use e.text.shape
use e.ui.accessibility
use e.ui.control
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { counts: usize, count: i64, quantities: usize, quantity: i64, typed_len: usize, turns: usize, level: f32, starts: usize, captures: usize, chord: control.Chord }

fn on_count(ctx: *void, value: i64) -> err {
    let log = mem.cast[*Log](ctx)
    log.counts += 1usize
    log.count = value
    ret ok
}

fn on_quantity(ctx: *void, value: i64) -> err {
    let log = mem.cast[*Log](ctx)
    log.quantities += 1usize
    log.quantity = value
    ret ok
}

fn on_typed(ctx: *void, value: str) -> err {
    let log = mem.cast[*Log](ctx)
    log.typed_len = value.len
    ret ok
}

fn on_level(ctx: *void, value: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.turns += 1usize
    log.level = value
    ret ok
}

fn on_start(ctx: *void) -> err {
    let log = mem.cast[*Log](ctx)
    log.starts += 1usize
    ret ok
}

fn on_capture(ctx: *void, value: control.Chord) -> err {
    let log = mem.cast[*Log](ctx)
    log.captures += 1usize
    log.chord = value
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

fn build(a: *mem.Arena, t: *const control.Theme, ctx: *void, buffer: []u8, start: *const widget.Submit, count: i64, quantity: i64, level: f32, chord: control.Chord, recording: bool) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, parts_error) }
    let (counter, counter_error) = control.stepper(a, 1u64, t, "Count", count, 0i64, 5i64, 1i64, widget.Change[i64] { ctx: ctx, invoke: on_count })
    if counter_error != ok { ret (zero, counter_error) }
    parts[0usize] = counter
    let (spinner, spinner_error) = control.spin_box(a, 10u64, t, "Qty", buffer, quantity, 0i64, 99i64, 1i64, widget.Change[i64] { ctx: ctx, invoke: on_quantity }, widget.Change[str] { ctx: ctx, invoke: on_typed })
    if spinner_error != ok { ret (zero, spinner_error) }
    parts[1usize] = spinner
    let (knob, knob_error) = control.dial(a, 20u64, t, "Volume", level, 0.0, 100.0, widget.Change[f32] { ctx: ctx, invoke: on_level }, 60.0)
    if knob_error != ok { ret (zero, knob_error) }
    parts[2usize] = knob
    let (recorder, recorder_error) = control.shortcut_recorder(a, 30u64, t, "Shortcut", chord, recording, start, widget.Change[control.Chord] { ctx: ctx, invoke: on_capture })
    if recorder_error != ok { ret (zero, recorder_error) }
    parts[3usize] = recorder
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 16.0 }, column, parts[0usize..4usize]), ok)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 128usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 12u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 400u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (starts, starts_error) = mem.alloc[widget.Submit](a, 1usize)
    if starts_error != ok { os.exit(8i32) }
    starts[0usize] = widget.Submit { ctx: ctx, invoke: on_start }
    let (buffer, buffer_error) = mem.alloc[u8](a, 16usize)
    if buffer_error != ok { os.exit(9i32) }
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(10i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    var control_s = control.Chord { key: 83u32, modifiers: zero }
    control_s.modifiers.control = true
    let (root, build_error) = build(&frame, &theme, ctx, buffer, &starts[0usize], 3i64, 42i64, 50.0, control_s, false)
    if build_error != ok { os.exit(11i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(12i32) }
    // The stepper: a slider valued 3; plus reports 4, minus 2 (from the caller's
    // 3), Down from the focused button 2 again.
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(13i32) }
    let (counter, has_counter) = find(tree, .Slider, "Count")
    if !has_counter || !same(counter.value, "3") { os.exit(14i32) }
    let (plus_at, has_plus) = centre_of(&harness, &runtime, 3u64)
    if !has_plus || testing.tap(&harness, plus_at.x, plus_at.y) != ok || logs[0usize].count != 4i64 { os.exit(15i32) }
    let (minus_at, has_minus) = centre_of(&harness, &runtime, 2u64)
    if !has_minus || testing.tap(&harness, minus_at.x, minus_at.y) != ok || logs[0usize].count != 2i64 { os.exit(16i32) }
    if testing.press_key(&harness, 40u32, zero) != ok || logs[0usize].counts != 3usize || logs[0usize].count != 2i64 { os.exit(17i32) }
    // The spin box: a field valued "42" named Qty; plus reports 43; typed, the
    // text reaches the caller; Up in the field reports 43 too.
    let (spun, has_spun) = find(tree, .Group, "Qty")
    if !has_spun || !same(spun.value, "42") { os.exit(18i32) }
    let field = testing.by_key(&harness, 10u64).element
    let (shown, has_shown) = widget.edit_value(&runtime, field)
    if !has_shown || !same(shown, "42") { os.exit(19i32) }
    let (more_at, has_more) = centre_of(&harness, &runtime, 12u64)
    if !has_more || testing.tap(&harness, more_at.x, more_at.y) != ok || logs[0usize].quantity != 43i64 { os.exit(20i32) }
    let (field_bounds, has_field) = widget.bounds_of(&runtime, field)
    if !has_field || testing.tap(&harness, field_bounds.x + field_bounds.width - 2.0, field_bounds.y + 2.0) != ok { os.exit(21i32) }
    if testing.press_key(&harness, 35u32, zero) != ok || testing.type_text(&harness, "7") != ok || logs[0usize].typed_len != 3usize { os.exit(22i32) }
    if testing.press_key(&harness, 38u32, zero) != ok || logs[0usize].quantities != 2usize || logs[0usize].quantity != 43i64 { os.exit(23i32) }
    // The dial: a slider valued 50; a press to the right of its middle turns it to
    // five sixths of the range; Right from the focused knob adds a hundredth of it
    // to the caller's 50.
    let (volume, has_volume) = find(tree, .Slider, "Volume")
    if !has_volume || !same(volume.value, "50") { os.exit(24i32) }
    let (knob_at, has_knob) = centre_of(&harness, &runtime, 20u64)
    if !has_knob || testing.tap(&harness, knob_at.x + 25.0, knob_at.y) != ok || !near(logs[0usize].level, 83.333, 1.0) { os.exit(25i32) }
    if testing.press_key(&harness, 39u32, zero) != ok || !near(logs[0usize].level, 51.0, 0.01) { os.exit(26i32) }
    if testing.drag(&harness, geometry.Point { x: knob_at.x + 25.0, y: knob_at.y }, geometry.Point { x: knob_at.x, y: knob_at.y - 25.0 }, 4usize) != ok || !near(logs[0usize].level, 50.0, 1.0) { os.exit(27i32) }
    // The recorder: named Shortcut, valued "Ctrl+S"; a press starts; recording, it
    // says so, a lone Shift is waited through, Ctrl+Shift+S is captured; Escape
    // captures none.
    let (recorder, has_recorder) = find(tree, .Group, "Shortcut")
    // v2 (D953): the chord shows as key caps, one per part.
    if !has_recorder || !same(recorder.value, "Ctrl+S") || testing.by_text(&harness, "Ctrl").count == 0usize || testing.by_text(&harness, "S").count == 0usize { os.exit(28i32) }
    let (recorder_at, has_recorder_at) = centre_of(&harness, &runtime, 30u64)
    if !has_recorder_at || testing.tap(&harness, recorder_at.x, recorder_at.y) != ok || logs[0usize].starts != 1usize { os.exit(29i32) }
    let (root_2, build_2_error) = build(&frame, &theme, ctx, buffer, &starts[0usize], 5i64, 43i64, 50.0, control_s, true)
    if build_2_error != ok { os.exit(30i32) }
    if testing.pump(&harness, root_2, now) != ok { os.exit(31i32) }
    if testing.by_text(&harness, "Press keys").count == 0usize { os.exit(32i32) }
    let (tree_2, tree_2_error) = testing.semantics(&harness)
    if tree_2_error != ok { os.exit(33i32) }
    let (plus_node, has_plus_node) = find(tree_2, .Button, "+")
    if !has_plus_node || !plus_node.state.disabled { os.exit(34i32) }
    if testing.press_key(&harness, 65505u32, zero) != ok || logs[0usize].captures != 0usize { os.exit(35i32) }
    var held: input.Modifiers = zero
    held.control = true
    held.shift = true
    if testing.press_key(&harness, 115u32, held) != ok || logs[0usize].captures != 1usize || logs[0usize].chord.key != 83u32 || !logs[0usize].chord.modifiers.shift || !logs[0usize].chord.modifiers.control { os.exit(36i32) }
    if testing.press_key(&harness, 27u32, zero) != ok || logs[0usize].captures != 2usize || logs[0usize].chord.key != 0u32 { os.exit(37i32) }
    var captured = control.Chord { key: 83u32, modifiers: held }
    let (root_3, build_3_error) = build(&frame, &theme, ctx, buffer, &starts[0usize], 5i64, 43i64, 50.0, captured, false)
    if build_3_error != ok { os.exit(38i32) }
    if testing.pump(&harness, root_3, now) != ok { os.exit(39i32) }
    if testing.by_text(&harness, "Ctrl").count == 0usize || testing.by_text(&harness, "Shift").count == 0usize || testing.by_text(&harness, "S").count == 0usize { os.exit(40i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(41i32) }
    try io.print("ui numeric ok\n")
    ret ok
}
