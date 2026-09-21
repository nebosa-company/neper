// `e.ui.widget`'s scrolling and insets (D817, widget plan P1-05): a scroll view
// stacks five boxes in a clamped viewport the wheel moves; a scrollbar beside it
// shows the thumb where the offset is and a drag of the thumb moves the viewport by
// the content's share; a safe area pads by the host's insets and a keyboard-avoiding
// box by the keyboard's height.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn sized(width: f32, height: f32) -> style.Style {
    var s = style.defaults()
    s.width = style.Length { Px: width }
    s.height = style.Length { Px: height }
    ret s
}

fn bounds(runtime: *widget.Runtime, h: *const testing.Harness, key: widget.Key, code: i32) -> geometry.Rect {
    let (r, has_r) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    if !has_r { os.exit(code) }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(1i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(2i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 2u32, 2u32)
    if renderer_error != ok { os.exit(3i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 64usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 128usize })
    if runtime_error != ok { os.exit(4i32) }
    var runtime = rt
    let (h, harness_error) = testing.harness(a, &runtime, 60u32, 120u32, 1.0)
    if harness_error != ok { os.exit(5i32) }
    var harness = h
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(6i32) }
    var frame = mem.arena_from(frame_storage)
    let (rows, rows_error) = mem.alloc[widget.Node](&frame, 5usize)
    if rows_error != ok { os.exit(7i32) }
    var i = 0usize
    while i < 5usize {
        rows[i] = widget.box(11u64 + u64(i), sized(40.0, 20.0), zero)
        i += 1usize
    }
    let (view, view_error) = widget.scroll_view(&frame, 1u64, .Vertical, sized(40.0, 40.0), rows[0usize..5usize])
    if view_error != ok { os.exit(8i32) }
    var bar_style = sized(6.0, 40.0)
    bar_style.background = paint.Brush { Solid: paint.rgba(0.9, 0.9, 0.9, 1.0) }
    bar_style.border = style.Border { width: 0.0, color: paint.rgba(1.0, 0.0, 0.0, 1.0) }
    let (pair, pair_error) = mem.alloc[widget.Node](&frame, 2usize)
    if pair_error != ok { os.exit(9i32) }
    pair[0usize] = view
    pair[1usize] = widget.scrollbar(2u64, 1u64, .Vertical, bar_style)
    let (safe_child, safe_child_error) = mem.alloc[widget.Node](&frame, 1usize)
    if safe_child_error != ok { os.exit(10i32) }
    safe_child[0usize] = widget.box(31u64, sized(10.0, 10.0), zero)
    let (keyboard_child, keyboard_child_error) = mem.alloc[widget.Node](&frame, 1usize)
    if keyboard_child_error != ok { os.exit(11i32) }
    keyboard_child[0usize] = widget.box(41u64, sized(10.0, 10.0), zero)
    let (items, items_error) = mem.alloc[widget.Node](&frame, 3usize)
    if items_error != ok { os.exit(12i32) }
    items[0usize] = widget.row(0u64, 2.0, style.defaults(), pair[0usize..2usize])
    items[1usize] = widget.safe_area(3u64, geometry.Insets { left: 2.0, top: 8.0, right: 0.0, bottom: 4.0 }, style.defaults(), safe_child[0usize..1usize])
    items[2usize] = widget.keyboard_avoiding(4u64, geometry.Insets { left: 0.0, top: 0.0, right: 0.0, bottom: 12.0 }, style.defaults(), keyboard_child[0usize..1usize])
    let root = widget.column(0u64, 2.0, sized(60.0, 120.0), items[0usize..3usize])
    let now = time.Instant { nanos: 1000000000i64 }
    if testing.pump(&harness, root, now) != ok { os.exit(13i32) }
    // The wheel moves the view; the thumb follows: 40 of 100 px is a 16 px thumb.
    let view_id = testing.by_key(&harness, 1u64).element
    let view_bounds = bounds(&runtime, &harness, 1u64, 14i32)
    if testing.wheel(&harness, 20.0, 20.0, -1i32) != ok { os.exit(15i32) }
    let (after_wheel, has_offset) = widget.scroll_offset_of(&runtime, view_id)
    if !has_offset || !near(after_wheel, 40.0) { os.exit(16i32) }
    if testing.pump(&harness, root, now) != ok { os.exit(17i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(18i32) }
    let bar = bounds(&runtime, &harness, 2u64, 19i32)
    if !near(bar.x, 42.0) || !near(bar.height, 40.0) { os.exit(20i32) }
    // At offset 40 of 100 the thumb starts 16 px down the 40 px bar: red at y 20, not at y 2.
    let bx = usize(bar.x + 3.0)
    if shot.pixels[(20usize * 60usize + bx) * 4usize] != 255u8 { os.exit(21i32) }
    if shot.pixels[(2usize * 60usize + bx) * 4usize] == 255u8 { os.exit(22i32) }
    // A drag of the thumb 8 px down moves the view 20 px (the content is 2.5 bars).
    if testing.drag(&harness, geometry.Point { x: bar.x + 3.0, y: bar.y + 20.0 }, geometry.Point { x: bar.x + 3.0, y: bar.y + 28.0 }, 1usize) != ok { os.exit(23i32) }
    let (after_drag, _) = widget.scroll_offset_of(&runtime, view_id)
    if !near(after_drag, 60.0) { os.exit(24i32) }
    if testing.drag(&harness, geometry.Point { x: bar.x + 3.0, y: bar.y + 28.0 }, geometry.Point { x: bar.x + 3.0, y: bar.y + 4.0 }, 2usize) != ok { os.exit(25i32) }
    let (dragged_back, _) = widget.scroll_offset_of(&runtime, view_id)
    if !near(dragged_back, 0.0) { os.exit(26i32) }
    // The safe area pads its child by the insets; the keyboard box by the keyboard.
    let safe = bounds(&runtime, &harness, 3u64, 27i32)
    let safe_inner = bounds(&runtime, &harness, 31u64, 28i32)
    if !near(safe_inner.x, safe.x + 2.0) || !near(safe_inner.y, safe.y + 8.0) || !near(safe.height, 22.0) || !near(safe.width, 12.0) { os.exit(29i32) }
    let avoiding = bounds(&runtime, &harness, 4u64, 30i32)
    if !near(avoiding.height, 22.0) || !near(avoiding.width, 10.0) { os.exit(31i32) }
    if !near(view_bounds.width, 40.0) { os.exit(32i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(33i32) }
    try io.print("ui scroll view ok\n")
    ret ok
}
