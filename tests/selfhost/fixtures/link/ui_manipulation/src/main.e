// `e.ui.widget`'s content manipulation (D844, widget plan P2-11): a zoom view
// scales about the wheel's pointer within its limits, pans by a drag, keeps its
// content inside itself and reports every move; a drag begun with a payload from
// a drag source is dropped on the region under the release that takes drops; the
// clipboard commands copy, cut and paste the focused editor's selection and move
// any text through the clipboard.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.text.layout
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

type Log = struct { runtime: *widget.Runtime, zooms: usize, zoom: widget.ZoomState, starts: usize, drops: usize, dropped: u64, drop_x: f32 }

fn on_zoom(ctx: *void, value: widget.ZoomState) -> err {
    let log = mem.cast[*Log](ctx)
    log.zooms += 1usize
    log.zoom = value
    ret ok
}

// The drag source: its drag start begins a drag carrying 7.
fn on_source(ctx: *void, g: widget.Gesture) -> err {
    let log = mem.cast[*Log](ctx)
    switch g {
    case .DragStart as p:
        log.starts += 1usize
        ret widget.begin_drag(log.runtime, 7u64)
    default:
        ret ok
    }
}

// The drop target: it hears the drop with the payload.
fn on_target_drop(ctx: *void, g: widget.Gesture) -> err {
    let log = mem.cast[*Log](ctx)
    switch g {
    case .Drop as d:
        log.drops += 1usize
        log.dropped = d.payload
        log.drop_x = d.position.x
        ret ok
    default:
        ret ok
    }
}

fn on_change(ctx: *void, value: str) -> err {
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

fn sized(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    ret s
}

fn build(a: *mem.Arena, ctx: *void, buffer: []u8, len: usize, state: widget.ZoomState) -> (widget.Node, err) {
    let (parts, parts_error) = mem.alloc[widget.Node](a, 4usize)
    if parts_error != ok { ret (zero, parts_error) }
    // The zoom view: 200 by 120 over a 400 by 300 picture.
    let (picture, picture_error) = mem.alloc[widget.Node](a, 1usize)
    if picture_error != ok { ret (zero, picture_error) }
    var big = sized(400.0, 300.0)
    big.background = paint.Brush { Solid: paint.rgba(0.2, 0.6, 0.2, 1.0) }
    picture[0usize] = widget.box(2u64, big, zero)
    parts[0usize] = widget.zoom(1u64, widget.Zoom { state: state, min_scale: 0.5, max_scale: 4.0, change: widget.Change[widget.ZoomState] { ctx: ctx, invoke: on_zoom } }, sized(200.0, 120.0), picture[0usize..1usize])
    // A drag source and a drop target side by side.
    let (pair, pair_error) = mem.alloc[widget.Node](a, 2usize)
    if pair_error != ok { ret (zero, pair_error) }
    var source_style = sized(60.0, 40.0)
    source_style.background = paint.Brush { Solid: paint.rgba(0.8, 0.3, 0.3, 1.0) }
    pair[0usize] = widget.region(10u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_source }, gestures: 2u8, enabled: true, focusable: false }, source_style, zero)
    var target_style = sized(60.0, 40.0)
    target_style.background = paint.Brush { Solid: paint.rgba(0.3, 0.3, 0.8, 1.0) }
    pair[1usize] = widget.region(20u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_target_drop }, gestures: 8u8, enabled: true, focusable: false }, target_style, zero)
    parts[1usize] = widget.flex(0u64, ui_layout.Flex { axis: .Horizontal, main: .Start, cross: .Start, gap: 40.0 }, style.defaults(), pair[0usize..2usize])
    // An editor for the clipboard commands.
    var no_fonts: []const layout.FontChoice = zero
    let text_style = layout.Style { fonts: no_fonts, language: "", line_height: 16.0 }
    parts[2usize] = widget.edit(30u64, widget.Edit { buffer: buffer, len: len, style: text_style, color: paint.rgba(0.0, 0.0, 0.0, 1.0), selection: paint.rgba(0.5, 0.5, 1.0, 1.0), change: widget.Change[str] { ctx: ctx, invoke: on_change }, submit: zero, enabled: true, read_only: false, multiline: false, secret: false }, sized(120.0, 20.0))
    parts[3usize] = widget.box(0u64, sized(10.0, 10.0), zero)
    var column = style.defaults()
    column.width = style.Length { Px: 320.0 }
    column.height = style.Length { Px: 320.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 20.0 }, column, parts[0usize..4usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 10u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let (h, harness_error) = testing.harness(a, &runtime, 320u32, 320u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (logs, logs_error) = mem.alloc[Log](a, 1usize)
    if logs_error != ok { os.exit(7i32) }
    var log: Log = zero
    log.runtime = &runtime
    logs[0usize] = log
    let ctx = mem.cast[*void](&logs[0usize])
    let (buffer, buffer_error) = mem.alloc[u8](a, 32usize)
    if buffer_error != ok { os.exit(8i32) }
    buffer[0usize] = 104u8
    buffer[1usize] = 101u8
    buffer[2usize] = 108u8
    buffer[3usize] = 108u8
    buffer[4usize] = 111u8
    let (frame_storage, storage_error) = mem.alloc[u8](a, 524288usize)
    if storage_error != ok { os.exit(9i32) }
    var frame = mem.arena_from(frame_storage)
    let now = time.Instant { nanos: 1000000000i64 }
    let (root, build_error) = build(&frame, ctx, buffer, 5usize, widget.ZoomState { scale: 1.0, offset: zero })
    if build_error != ok { os.exit(10i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(11i32) }
    // The zoom view: a notch up at (50, 50) inside it scales to 1.1 about that
    // point, so the offset moves by a tenth of the point's distance from the
    // origin; the runtime keeps the state and reports it.
    let view = testing.by_key(&harness, 1u64).element
    let (view_bounds, has_view) = widget.bounds_of(&runtime, view)
    if !has_view || !near(view_bounds.width, 200.0, 0.5) || !near(view_bounds.height, 120.0, 0.5) { os.exit(12i32) }
    if testing.wheel(&harness, view_bounds.x + 50.0, view_bounds.y + 50.0, 1i32) != ok || logs[0usize].zooms != 1usize { os.exit(13i32) }
    if !near(logs[0usize].zoom.scale, 1.1, 0.001) || !near(logs[0usize].zoom.offset.x, -5.0, 0.01) || !near(logs[0usize].zoom.offset.y, -5.0, 0.01) { os.exit(14i32) }
    let (kept, has_kept) = widget.zoom_state_of(&runtime, view)
    if !has_kept || !near(kept.scale, 1.1, 0.001) { os.exit(15i32) }
    // A drag of 30 left and 10 up pans by that; a drag far right stops at the
    // origin; a drag far left stops where the content's end meets the view's.
    if testing.drag(&harness, geometry.Point { x: view_bounds.x + 100.0, y: view_bounds.y + 60.0 }, geometry.Point { x: view_bounds.x + 70.0, y: view_bounds.y + 50.0 }, 3usize) != ok { os.exit(16i32) }
    if !near(logs[0usize].zoom.offset.x, -35.0, 0.01) || !near(logs[0usize].zoom.offset.y, -15.0, 0.01) { os.exit(17i32) }
    if testing.drag(&harness, geometry.Point { x: view_bounds.x + 20.0, y: view_bounds.y + 20.0 }, geometry.Point { x: view_bounds.x + 190.0, y: view_bounds.y + 110.0 }, 4usize) != ok { os.exit(18i32) }
    if !near(logs[0usize].zoom.offset.x, 0.0, 0.01) || !near(logs[0usize].zoom.offset.y, 0.0, 0.01) { os.exit(19i32) }
    if testing.drag(&harness, geometry.Point { x: view_bounds.x + 190.0, y: view_bounds.y + 110.0 }, geometry.Point { x: view_bounds.x + 10.0, y: view_bounds.y + 10.0 }, 4usize) != ok { os.exit(20i32) }
    if testing.drag(&harness, geometry.Point { x: view_bounds.x + 190.0, y: view_bounds.y + 110.0 }, geometry.Point { x: view_bounds.x + 10.0, y: view_bounds.y + 10.0 }, 4usize) != ok { os.exit(21i32) }
    if testing.drag(&harness, geometry.Point { x: view_bounds.x + 190.0, y: view_bounds.y + 110.0 }, geometry.Point { x: view_bounds.x + 10.0, y: view_bounds.y + 10.0 }, 4usize) != ok { os.exit(21i32) }
    if !near(logs[0usize].zoom.offset.x, 200.0 - 440.0, 0.01) || !near(logs[0usize].zoom.offset.y, 120.0 - 330.0, 0.01) { os.exit(22i32) }
    // Ten notches down cannot go under the minimum scale; at the minimum the
    // content is smaller than the view and sits at the origin.
    var i = 0usize
    while i < 10usize {
        if testing.wheel(&harness, view_bounds.x + 50.0, view_bounds.y + 50.0, -1i32) != ok { os.exit(23i32) }
        i += 1usize
    }
    if !near(logs[0usize].zoom.scale, 0.5, 0.001) || !near(logs[0usize].zoom.offset.x, 0.0, 0.01) { os.exit(24i32) }
    // The caller's state is taken when it changes: rebuilt at scale 2, the view
    // says 2.
    let (root_2, build_2_error) = build(&frame, ctx, buffer, 5usize, widget.ZoomState { scale: 2.0, offset: zero })
    if build_2_error != ok || testing.pump(&harness, root_2, now) != ok { os.exit(25i32) }
    let (taken, has_taken) = widget.zoom_state_of(&runtime, view)
    if !has_taken || !near(taken.scale, 2.0, 0.001) { os.exit(26i32) }
    // The drag and the drop: a drag from the source to the target begins a drag
    // with 7 (seen while it lasts) and drops it on the target; a drag released
    // elsewhere drops nowhere and the drag is over.
    let (source_bounds, has_source) = widget.bounds_of(&runtime, testing.by_key(&harness, 10u64).element)
    let (target_bounds, has_target) = widget.bounds_of(&runtime, testing.by_key(&harness, 20u64).element)
    if !has_source || !has_target { os.exit(27i32) }
    let from = geometry.Point { x: source_bounds.x + 30.0, y: source_bounds.y + 20.0 }
    let onto = geometry.Point { x: target_bounds.x + 30.0, y: target_bounds.y + 20.0 }
    if testing.drag(&harness, from, onto, 5usize) != ok { os.exit(28i32) }
    if logs[0usize].starts != 1usize || logs[0usize].drops != 1usize || logs[0usize].dropped != 7u64 || !near(logs[0usize].drop_x, onto.x, 0.01) { os.exit(29i32) }
    let (_, still_dragging) = widget.dragging(&runtime)
    if still_dragging { os.exit(30i32) }
    if testing.drag(&harness, from, geometry.Point { x: from.x + 30.0, y: from.y + 80.0 }, 3usize) != ok || logs[0usize].starts != 2usize || logs[0usize].drops != 1usize { os.exit(31i32) }
    // The clipboard commands over the editor holding "hello": nothing selected,
    // only paste applies; all selected, copy and cut apply; copy then get reads
    // "hello"; set "xy" then paste replaces the selection; cut empties.
    let editor = testing.by_key(&harness, 30u64).element
    let (editor_bounds, has_editor) = widget.bounds_of(&runtime, editor)
    if !has_editor || testing.tap(&harness, editor_bounds.x + 2.0, editor_bounds.y + 2.0) != ok { os.exit(32i32) }
    let none = widget.clipboard_commands(&runtime)
    if none.copy || none.cut || !none.paste { os.exit(33i32) }
    var control: input.Modifiers = zero
    control.control = true
    if testing.press_key(&harness, 65u32, control) != ok { os.exit(34i32) }
    let all = widget.clipboard_commands(&runtime)
    if !all.copy || !all.cut || !all.paste { os.exit(35i32) }
    if widget.clipboard_copy(&runtime) != ok { os.exit(36i32) }
    let (got, got_error) = widget.clipboard_get(&runtime, &frame)
    if got_error != ok || !same(got, "hello") { os.exit(37i32) }
    if widget.clipboard_set(&runtime, "xy") != ok || widget.clipboard_paste(&runtime) != ok { os.exit(38i32) }
    let (pasted, has_pasted) = widget.edit_value(&runtime, editor)
    if !has_pasted || !same(pasted, "xy") { os.exit(39i32) }
    if testing.press_key(&harness, 65u32, control) != ok || widget.clipboard_cut(&runtime) != ok { os.exit(40i32) }
    let (emptied, has_emptied) = widget.edit_value(&runtime, editor)
    let (cut_text, cut_error) = widget.clipboard_get(&runtime, &frame)
    if !has_emptied || emptied.len != 0usize || cut_error != ok || !same(cut_text, "xy") { os.exit(41i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(42i32) }
    try io.print("ui manipulation ok\n")
    ret ok
}
