// `e.ui.widget`'s primary layouts (D815, widget plan P1-03): a row lays its boxes
// across with a gap and a column down; a wrap breaks a line of boxes where the
// next would pass its width and stacks the lines; a positioned box sits at its
// offset in a stack; the grid and the stack of D799 still hold.

use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.gfx.geometry
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

fn boxes(a: *mem.Arena, first_key: widget.Key, count: usize) -> ([]widget.Node, err) {
    let (made, made_error) = mem.alloc[widget.Node](a, count)
    if made_error != ok { ret (zero, made_error) }
    var i = 0usize
    while i < count {
        made[i] = widget.box(first_key + u64(i), sized(10.0, 10.0), zero)
        i += 1usize
    }
    ret (made, ok)
}

fn expect_at(runtime: *widget.Runtime, h: *const testing.Harness, key: widget.Key, x: f32, y: f32, code: i32) {
    let (bounds, has_bounds) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    if !has_bounds || !near(bounds.x, x) || !near(bounds.y, y) { os.exit(code) }
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
    let (h, harness_error) = testing.harness(a, &runtime, 64u32, 120u32, 1.0)
    if harness_error != ok { os.exit(5i32) }
    var harness = h
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(6i32) }
    var frame = mem.arena_from(frame_storage)
    let (row_boxes, row_error) = boxes(&frame, 11u64, 3usize)
    if row_error != ok { os.exit(7i32) }
    let (column_boxes, column_error) = boxes(&frame, 21u64, 2usize)
    if column_error != ok { os.exit(8i32) }
    let (wrap_boxes, wrap_error) = boxes(&frame, 31u64, 5usize)
    if wrap_error != ok { os.exit(9i32) }
    let (inner, inner_error) = boxes(&frame, 41u64, 1usize)
    if inner_error != ok { os.exit(10i32) }
    let (placed, placed_error) = mem.alloc[widget.Node](&frame, 1usize)
    if placed_error != ok { os.exit(11i32) }
    placed[0usize] = widget.positioned(40u64, 5.0, 7.0, style.defaults(), inner[0usize..1usize])
    let (items, items_error) = mem.alloc[widget.Node](&frame, 4usize)
    if items_error != ok { os.exit(12i32) }
    items[0usize] = widget.row(1u64, 2.0, style.defaults(), row_boxes)
    items[1usize] = widget.column(2u64, 2.0, style.defaults(), column_boxes)
    items[2usize] = widget.wrap(3u64, ui_layout.Wrap { axis: .Horizontal, main_gap: 2.0, cross_gap: 2.0 }, sized(34.0, 22.0), wrap_boxes)
    items[3usize] = widget.stack(4u64, sized(30.0, 30.0), placed[0usize..1usize])
    let root = widget.column(0u64, 4.0, sized(64.0, 120.0), items[0usize..4usize])
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(13i32) }
    // The row: boxes 12 px apart across; 10 tall. The column below it: 12 apart down.
    expect_at(&runtime, &harness, 11u64, 0.0, 0.0, 14i32)
    expect_at(&runtime, &harness, 12u64, 12.0, 0.0, 15i32)
    expect_at(&runtime, &harness, 13u64, 24.0, 0.0, 16i32)
    let (row_bounds, has_row) = widget.bounds_of(&runtime, testing.by_key(&harness, 1u64).element)
    if !has_row || !near(row_bounds.width, 34.0) || !near(row_bounds.height, 10.0) { os.exit(17i32) }
    expect_at(&runtime, &harness, 21u64, 0.0, 14.0, 18i32)
    expect_at(&runtime, &harness, 22u64, 0.0, 26.0, 19i32)
    // The wrap at y 40: three boxes fit its 34 px, the fourth starts a line 12 below.
    expect_at(&runtime, &harness, 31u64, 0.0, 40.0, 20i32)
    expect_at(&runtime, &harness, 33u64, 24.0, 40.0, 21i32)
    expect_at(&runtime, &harness, 34u64, 0.0, 52.0, 22i32)
    expect_at(&runtime, &harness, 35u64, 12.0, 52.0, 23i32)
    let (wrap_bounds, has_wrap) = widget.bounds_of(&runtime, testing.by_key(&harness, 3u64).element)
    if !has_wrap || !near(wrap_bounds.height, 22.0) { os.exit(24i32) }
    // The positioned box sits 5 across and 7 down in the stack at y 66.
    expect_at(&runtime, &harness, 40u64, 5.0, 73.0, 25i32)
    expect_at(&runtime, &harness, 41u64, 5.0, 73.0, 26i32)
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(27i32) }
    try io.print("ui layout primary ok\n")
    ret ok
}
