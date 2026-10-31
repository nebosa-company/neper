// A row wider than its space shrinks its flexible child first: a share-wide box holding a child that asks for 100 % of the
// width (the address field of the browser, `FieldOptions.fill`) takes what the fixed boxes leave, and the fixed boxes keep
// their size and place. The row is 200 wide; three fixed boxes of 40 and three gaps of 2 leave 74.

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

fn expect_box(runtime: *widget.Runtime, h: *const testing.Harness, key: widget.Key, x: f32, width: f32, code: i32) {
    let (bounds, has_bounds) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    if !has_bounds || !near(bounds.x, x) || !near(bounds.width, width) { os.exit(code) }
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
    let (h, harness_error) = testing.harness(a, &runtime, 200u32, 40u32, 1.0)
    if harness_error != ok { os.exit(5i32) }
    var harness = h
    let (frame_storage, storage_error) = mem.alloc[u8](a, 262144usize)
    if storage_error != ok { os.exit(6i32) }
    var frame = mem.arena_from(frame_storage)
    let (items, items_error) = mem.alloc[widget.Node](&frame, 4usize)
    if items_error != ok { os.exit(7i32) }
    items[0usize] = widget.box(11u64, sized(40.0, 10.0), zero)
    items[1usize] = widget.box(12u64, sized(40.0, 10.0), zero)
    items[2usize] = widget.box(13u64, sized(40.0, 10.0), zero)
    // The share-wide slot holds a box of 100 %, which measures as the whole row until the slot is placed.
    let (inner, inner_error) = mem.alloc[widget.Node](&frame, 1usize)
    if inner_error != ok { os.exit(8i32) }
    var fill = style.defaults()
    fill.width = style.Length { Percent: 100.0 }
    fill.height = style.Length { Px: 10.0 }
    inner[0usize] = widget.box(15u64, fill, zero)
    var slot = style.defaults()
    slot.width = style.Length { Flex: 1.0 }
    items[3usize] = widget.box(14u64, slot, inner[0usize..1usize])
    let root = widget.row(0u64, 2.0, sized(200.0, 40.0), items[0usize..4usize])
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(9i32) }
    expect_box(&runtime, &harness, 11u64, 0.0, 40.0, 10i32)
    expect_box(&runtime, &harness, 12u64, 42.0, 40.0, 11i32)
    expect_box(&runtime, &harness, 13u64, 84.0, 40.0, 12i32)
    expect_box(&runtime, &harness, 14u64, 126.0, 74.0, 13i32)
    expect_box(&runtime, &harness, 15u64, 126.0, 74.0, 14i32)
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(15i32) }
    try io.print("ui layout fill ok\n")
    ret ok
}
