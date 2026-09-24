// `e.ui.widget`'s viewports (D808, widget plan P0-05): a clamped viewport with a
// scrollbar moved by the wheel, dragged past the slop, carried by momentum over the
// frames after the drag and stopped at its end; scroll_to clamped; a bouncing
// viewport overshooting under a drag -- handed over by a tap-only region the drag
// left -- and springing back; and a lazy viewport building only the items
// visible_range names, recycled by key as it scrolls.

use e.gpu
use e.io
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.input
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.widget
use e.ui.window

type Log = struct { moves: usize, last: f32, taps: usize }

fn on_scroll(ctx: *void, offset: f32) -> err {
    let log = mem.cast[*Log](ctx)
    log.moves += 1usize
    log.last = offset
    ret ok
}

fn on_gesture(ctx: *void, g: widget.Gesture) -> err {
    let log = mem.cast[*Log](ctx)
    switch g {
    case .Tap as p:
        log.taps += 1usize
    default:
        log.taps = log.taps
    }
    ret ok
}

fn sized(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    ret s
}

fn pointer(x: f32, y: f32, device: u32) -> input.Pointer {
    ret input.Pointer { window: window.Id { slot: 0u32, generation: 0u32 }, device: device, pointer: 0u32, kind: .Mouse, position: geometry.Point { x: x, y: y }, buttons: 1u32, changed: .Primary }
}

fn frame_event() -> input.Event {
    ret input.Event { Frame: window.Id { slot: 0u32, generation: 0u32 } }
}

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

// The tree: viewport A (clamped, momentum, scrollbar) over a column of five boxes,
// viewport B (bouncing) over a column of a tap-only region and four boxes, and the lazy viewport C over
// the items `visible_range` names at `c_offset`.
fn build(a: *mem.Arena, ctx: *void, c_offset: f32) -> (widget.Node, err) {
    let (a_children, a_error) = mem.alloc[widget.Node](a, 5usize)
    if a_error != ok { ret (zero, a_error) }
    let (b_children, b_error) = mem.alloc[widget.Node](a, 5usize)
    if b_error != ok { ret (zero, b_error) }
    var i = 0usize
    while i < 5usize {
        a_children[i] = widget.box(11u64 + u64(i), sized(64.0, 20.0), zero)
        b_children[i] = widget.box(21u64 + u64(i), sized(64.0, 20.0), zero)
        i += 1usize
    }
    b_children[0usize] = widget.region(21u64, widget.Region { gesture: widget.GestureAction { ctx: ctx, invoke: on_gesture }, gestures: 1u8, enabled: true, focusable: false }, sized(64.0, 20.0), zero)
    let (first, count) = widget.visible_range(c_offset, 40.0, 100usize, 10.0)
    let (c_children, c_error) = mem.alloc[widget.Node](a, count)
    if c_error != ok { ret (zero, c_error) }
    i = 0usize
    while i < count {
        c_children[i] = widget.box(100u64 + u64(first + i), sized(64.0, 10.0), zero)
        i += 1usize
    }
    // A viewport stacks its children: the boxes go in a column each.
    let (columns, columns_error) = mem.alloc[widget.Node](a, 2usize)
    if columns_error != ok { ret (zero, columns_error) }
    columns[0usize] = widget.flex(10u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, sized(64.0, 100.0), a_children[0usize..5usize])
    columns[1usize] = widget.flex(20u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, sized(64.0, 100.0), b_children[0usize..5usize])
    let (top, top_error) = mem.alloc[widget.Node](a, 3usize)
    if top_error != ok { ret (zero, top_error) }
    let red = paint.rgba(1.0, 0.0, 0.0, 1.0)
    top[0usize] = widget.scroll(1u64, widget.Scroll { axis: .Vertical, offset: 0.0, overscroll: .Clamp, momentum: true, scrollbar: true, thumb: red, change: widget.Change[f32] { ctx: ctx, invoke: on_scroll }, virtual_first: 0usize, virtual_count: 0usize, virtual_extent: 0.0 }, sized(64.0, 40.0), columns[0usize..1usize])
    top[1usize] = widget.scroll(2u64, widget.Scroll { axis: .Vertical, offset: 0.0, overscroll: .Bounce, momentum: false, scrollbar: false, thumb: red, change: zero, virtual_first: 0usize, virtual_count: 0usize, virtual_extent: 0.0 }, sized(64.0, 40.0), columns[1usize..2usize])
    top[2usize] = widget.scroll(3u64, widget.Scroll { axis: .Vertical, offset: 0.0, overscroll: .Clamp, momentum: false, scrollbar: false, thumb: red, change: zero, virtual_first: first, virtual_count: 100usize, virtual_extent: 10.0 }, sized(64.0, 40.0), c_children[0usize..count])
    var column = style.defaults()
    column.width = style.Length { Px: 64.0 }
    column.height = style.Length { Px: 128.0 }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 4.0 }, column, top[0usize..3usize]), ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (t, target_error) = gpu.open_target(q, gpu.Surface { kind: .Offscreen, handle: zero, context: zero }, 64u32, 128u32, .Rgba8)
    if target_error != ok { os.exit(3i32) }
    let (canvas, canvas_error) = scene.target_of(a, t)
    if canvas_error != ok { os.exit(4i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(5i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 256usize })
    if runtime_error != ok { os.exit(6i32) }
    var runtime = rt
    var log: Log = zero
    let ctx = mem.cast[*void](&log)
    let (frame_storage, storage_error) = mem.alloc[u8](a, 1048576usize)
    if storage_error != ok { os.exit(7i32) }
    var frame = mem.arena_from(frame_storage)
    let limits = ui_layout.Constraints { min_width: 0.0, max_width: 64.0, min_height: 0.0, max_height: 128.0 }
    let (root, build_error) = build(&frame, ctx, 0.0)
    if build_error != ok { os.exit(8i32) }
    let (first_scene, first_error) = widget.reconcile(&runtime, &frame, root, limits)
    if first_error != ok { os.exit(9i32) }
    if scene.render(&renderer, first_scene, canvas, geometry.Size { width: 64.0, height: 128.0 }) != ok { os.exit(10i32) }
    let (shown, shown_error) = gpu.presented(t)
    if shown_error != ok { os.exit(11i32) }
    var pixels: [8192]u32 = zero
    if gpu.read_image(q, shown, pixels[0..]) != ok { os.exit(12i32) }
    // The thumb: 40 of 100 px of content is 16 px of a 40 px track, at the top,
    // held to the v2 minimum of 32 (D979), 4 wide and 2 from the edge.
    if pixels[8usize * 64usize + 60usize] != 4278190335u32 || pixels[8usize * 64usize + 63usize] != 0u32 { os.exit(13i32) }
    if pixels[36usize * 64usize + 60usize] != 0u32 { os.exit(14i32) }
    let state = mem.cast[*widget.State](runtime.state)
    let (va, va_count) = widget.find_by_key(state, 1u64)
    let (vb, vb_count) = widget.find_by_key(state, 2u64)
    let (vc, vc_count) = widget.find_by_key(state, 3u64)
    if va_count != 1usize || vb_count != 1usize || vc_count != 1usize { os.exit(15i32) }
    // The wheel: a notch is 40 px; the offset stops at the content's end (60) and
    // at the start; each move is reported.
    let down_notch = mem.bitcast[u32](-120i32)
    if widget.dispatch(&runtime, input.Event { Scroll: pointer(10.0, 10.0, down_notch) }) != ok { os.exit(16i32) }
    let (after_notch, has_a) = widget.scroll_offset_of(&runtime, va)
    if !has_a || !near(after_notch, 40.0) || log.moves != 1usize || !near(log.last, 40.0) { os.exit(17i32) }
    if widget.dispatch(&runtime, input.Event { Scroll: pointer(10.0, 10.0, down_notch) }) != ok { os.exit(18i32) }
    let (clamped, _) = widget.scroll_offset_of(&runtime, va)
    if !near(clamped, 60.0) || log.moves != 2usize { os.exit(19i32) }
    if widget.dispatch(&runtime, input.Event { Scroll: pointer(10.0, 10.0, 360u32) }) != ok { os.exit(20i32) }
    let (back, _) = widget.scroll_offset_of(&runtime, va)
    if !near(back, 0.0) || log.moves != 3usize { os.exit(21i32) }
    // A drag: nothing within the slop, then the content follows the pointer from
    // where it was pressed.
    if widget.dispatch(&runtime, input.Event { PointerDown: pointer(10.0, 20.0, 0u32) }) != ok { os.exit(22i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(10.0, 16.0, 0u32) }) != ok { os.exit(23i32) }
    let (within, _) = widget.scroll_offset_of(&runtime, va)
    if !near(within, 0.0) { os.exit(24i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(10.0, 6.0, 0u32) }) != ok { os.exit(25i32) }
    let (dragged, _) = widget.scroll_offset_of(&runtime, va)
    if !near(dragged, 14.0) { os.exit(26i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(10.0, 1.0, 0u32) }) != ok { os.exit(27i32) }
    let (dragged_more, _) = widget.scroll_offset_of(&runtime, va)
    if !near(dragged_more, 19.0) { os.exit(28i32) }
    if widget.dispatch(&runtime, input.Event { PointerUp: pointer(10.0, 1.0, 0u32) }) != ok { os.exit(29i32) }
    // Momentum: the last move's 5 px carry into the next frame and decay; the end
    // stops them.
    if widget.dispatch(&runtime, frame_event()) != ok { os.exit(30i32) }
    let (carried, _) = widget.scroll_offset_of(&runtime, va)
    if !near(carried, 24.0) { os.exit(31i32) }
    var n = 0usize
    while n < 80usize {
        if widget.dispatch(&runtime, frame_event()) != ok { os.exit(32i32) }
        n += 1usize
    }
    let (rested, _) = widget.scroll_offset_of(&runtime, va)
    if !near(rested, 60.0) { os.exit(33i32) }
    // scroll_to, clamped.
    if widget.scroll_to(&runtime, va, 999.0) != ok { os.exit(34i32) }
    let (far, _) = widget.scroll_offset_of(&runtime, va)
    if !near(far, 60.0) { os.exit(35i32) }
    if widget.scroll_to(&runtime, va, 0.0) != ok { os.exit(36i32) }
    // The bouncing viewport (y 44..84): a press on its tap-only region that travels
    // past the slop is the viewport's drag, at half speed past the start, and no
    // tap; once let go the offset springs back to the start.
    if widget.dispatch(&runtime, input.Event { PointerDown: pointer(10.0, 50.0, 0u32) }) != ok { os.exit(37i32) }
    if widget.dispatch(&runtime, input.Event { PointerMove: pointer(10.0, 70.0, 0u32) }) != ok { os.exit(38i32) }
    let (overshot, has_b) = widget.scroll_offset_of(&runtime, vb)
    if !has_b || !near(overshot, -10.0) { os.exit(39i32) }
    if widget.dispatch(&runtime, input.Event { PointerUp: pointer(10.0, 70.0, 0u32) }) != ok { os.exit(40i32) }
    if log.taps != 0usize { os.exit(41i32) }
    if widget.dispatch(&runtime, frame_event()) != ok { os.exit(42i32) }
    let (springing, _) = widget.scroll_offset_of(&runtime, vb)
    if !near(springing, -7.0) { os.exit(43i32) }
    n = 0usize
    while n < 40usize {
        if widget.dispatch(&runtime, frame_event()) != ok { os.exit(44i32) }
        n += 1usize
    }
    let (settled, _) = widget.scroll_offset_of(&runtime, vb)
    if !near(settled, 0.0) { os.exit(45i32) }
    // A tap on the region that stays within the slop is still a tap.
    if widget.dispatch(&runtime, input.Event { PointerDown: pointer(10.0, 50.0, 0u32) }) != ok { os.exit(46i32) }
    if widget.dispatch(&runtime, input.Event { PointerUp: pointer(11.0, 51.0, 0u32) }) != ok { os.exit(47i32) }
    if log.taps != 1usize { os.exit(48i32) }
    // The lazy viewport (y 88..128): six items built at the start, the fourth at
    // y 118; at offset 550 the items 54..60 are built, item 55 at the top, and the
    // first frame's elements are recycled.
    let (item_0, item_0_count) = widget.find_by_key(state, 100u64)
    let (_, item_50_count) = widget.find_by_key(state, 150u64)
    if item_0_count != 1usize || item_50_count != 0usize { os.exit(49i32) }
    let (item_3, item_3_count) = widget.find_by_key(state, 103u64)
    let (item_3_bounds, has_item_3) = widget.bounds_of(&runtime, item_3)
    if item_3_count != 1usize || !has_item_3 || !near(item_3_bounds.y, 118.0) { os.exit(50i32) }
    if widget.scroll_to(&runtime, vc, 550.0) != ok { os.exit(51i32) }
    let (moved_c, _) = widget.scroll_offset_of(&runtime, vc)
    if !near(moved_c, 550.0) { os.exit(52i32) }
    let (root_2, build_2_error) = build(&frame, ctx, moved_c)
    if build_2_error != ok { os.exit(53i32) }
    let (second_scene, second_error) = widget.reconcile(&runtime, &frame, root_2, limits)
    if second_error != ok { os.exit(54i32) }
    let (_, item_0_again) = widget.find_by_key(state, 100u64)
    let (item_55, item_55_count) = widget.find_by_key(state, 155u64)
    let (_, item_54_count) = widget.find_by_key(state, 154u64)
    let (_, item_61_count) = widget.find_by_key(state, 161u64)
    if item_0_again != 0usize || item_55_count != 1usize || item_54_count != 1usize || item_61_count != 0usize { os.exit(55i32) }
    let (item_55_bounds, has_item_55) = widget.bounds_of(&runtime, item_55)
    if !has_item_55 || !near(item_55_bounds.y, 88.0) { os.exit(56i32) }
    // The viewport's own offset survived the rebuild: the node still said 0.
    let (kept_c, _) = widget.scroll_offset_of(&runtime, vc)
    if !near(kept_c, 550.0) { os.exit(57i32) }
    if scene.render(&renderer, second_scene, canvas, geometry.Size { width: 64.0, height: 128.0 }) != ok { os.exit(58i32) }
    if widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(59i32) }
    try io.print("ui scroll ok\n")
    ret ok
}
