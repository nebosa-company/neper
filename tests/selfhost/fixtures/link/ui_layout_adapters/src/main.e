// `e.ui.widget`'s layout adapters (D816, widget plan P1-04): a child centred in its
// box; padded; a spacer taking the room a row leaves; a box constrained to a width;
// an aspect box as wide as its column and half as tall; a fitted box painting its
// too-large content scaled to fit; and a responsive choice by the width's size class.

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

fn red(width: f32, height: f32) -> style.Style {
    var s = sized(width, height)
    s.background = paint.Brush { Solid: paint.rgba(1.0, 0.0, 0.0, 1.0) }
    ret s
}

fn one(a: *mem.Arena, node: widget.Node) -> ([]widget.Node, err) {
    let (made, made_error) = mem.alloc[widget.Node](a, 1usize)
    if made_error != ok { ret (zero, made_error) }
    made[0usize] = node
    ret (made, ok)
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
    let (h, harness_error) = testing.harness(a, &runtime, 40u32, 160u32, 1.0)
    if harness_error != ok { os.exit(5i32) }
    var harness = h
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(6i32) }
    var frame = mem.arena_from(frame_storage)
    let (centred_child, e1) = one(&frame, widget.box(11u64, sized(10.0, 10.0), zero))
    if e1 != ok { os.exit(7i32) }
    let (padded_child, e2) = one(&frame, widget.box(21u64, sized(10.0, 10.0), zero))
    if e2 != ok { os.exit(8i32) }
    let (row_items, e3) = mem.alloc[widget.Node](&frame, 3usize)
    if e3 != ok { os.exit(9i32) }
    row_items[0usize] = widget.box(31u64, sized(10.0, 10.0), zero)
    row_items[1usize] = widget.spacer(32u64, 1.0)
    row_items[2usize] = widget.box(33u64, sized(10.0, 10.0), zero)
    let (wide_child, e4) = one(&frame, widget.box(41u64, sized(30.0, 10.0), zero))
    if e4 != ok { os.exit(10i32) }
    let (aspect_child, e5) = one(&frame, widget.box(51u64, sized(10.0, 10.0), zero))
    if e5 != ok { os.exit(11i32) }
    let (fitted_child, e6) = one(&frame, widget.box(61u64, red(40.0, 20.0), zero))
    if e6 != ok { os.exit(12i32) }
    let (items, items_error) = mem.alloc[widget.Node](&frame, 7usize)
    if items_error != ok { os.exit(13i32) }
    items[0usize] = widget.center(1u64, sized(30.0, 30.0), centred_child)
    items[1usize] = widget.padded(2u64, 4.0, 4.0, 4.0, 4.0, style.defaults(), padded_child)
    items[2usize] = widget.row(3u64, 0.0, sized(30.0, 10.0), row_items[0usize..3usize])
    items[3usize] = widget.constrained(4u64, 0.0, 20.0, 0.0, 100.0, style.defaults(), wide_child)
    items[4usize] = widget.aspect_ratio(5u64, 2.0, style.defaults(), aspect_child)
    items[5usize] = widget.fitted(6u64, sized(20.0, 20.0), fitted_child)
    items[6usize] = widget.responsive(320.0, widget.box(71u64, sized(5.0, 5.0), zero), widget.box(72u64, sized(5.0, 5.0), zero), widget.box(73u64, sized(5.0, 5.0), zero))
    let root = widget.column(0u64, 2.0, sized(40.0, 160.0), items[0usize..7usize])
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(14i32) }
    // Centred: the 10 px child sits 10 in from the 30 px box's corner.
    let centred = bounds(&runtime, &harness, 11u64, 15i32)
    if !near(centred.x, 10.0) || !near(centred.y, 10.0) { os.exit(i32(100.0 + centred.x * 10.0 + centred.y)) }
    // Padded: the child 4 in, the box 18 across; at y 32.
    let padded_box = bounds(&runtime, &harness, 2u64, 17i32)
    let padded_inner = bounds(&runtime, &harness, 21u64, 18i32)
    if !near(padded_box.width, 18.0) || !near(padded_inner.x, 4.0) || !near(padded_inner.y, 36.0) { os.exit(19i32) }
    // The spacer takes the 10 px the row leaves: the last box starts at 20.
    let last = bounds(&runtime, &harness, 33u64, 20i32)
    let spacer_bounds = bounds(&runtime, &harness, 32u64, 21i32)
    if !near(last.x, 20.0) || !near(spacer_bounds.width, 10.0) { os.exit(22i32) }
    // Constrained: a 30 px child in a box at most 20 wide.
    let limited = bounds(&runtime, &harness, 4u64, 23i32)
    if !near(limited.width, 20.0) { os.exit(24i32) }
    // Aspect: the column's 40 px across and 20 tall.
    let aspect = bounds(&runtime, &harness, 5u64, 25i32)
    if !near(aspect.width, 40.0) || !near(aspect.height, 20.0) { os.exit(26i32) }
    // Fitted: the 40 x 20 red child in a 20 px box paints at half size -- red at
    // (5, 5) inside, nothing at (15, 15) below the scaled content.
    let fitted_box = bounds(&runtime, &harness, 6u64, 27i32)
    if !near(fitted_box.width, 20.0) || !near(fitted_box.height, 20.0) { os.exit(28i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(29i32) }
    let fy = usize(fitted_box.y)
    if shot.pixels[((fy + 5usize) * 40usize + 5usize) * 4usize] != 255u8 { os.exit(30i32) }
    if shot.pixels[((fy + 15usize) * 40usize + 15usize) * 4usize + 3usize] != 0u8 { os.exit(31i32) }
    // Responsive: 320 px is compact; only the compact subtree exists.
    if testing.by_key(&harness, 71u64).count != 1usize || testing.by_key(&harness, 72u64).count != 0usize || testing.by_key(&harness, 73u64).count != 0usize { os.exit(32i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(33i32) }
    try io.print("ui layout adapters ok\n")
    ret ok
}
