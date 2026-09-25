// The v2 loading shapes (D970, widget plan P5-09, docs/ux/components/Placeholder,
// Skeleton) under the light theme: a region named and busy whose shapes are not
// in the tree; placeholder text lines 12 tall and fully rounded, circles and
// blocks in `surface-container-highest`, one sweep band in
// `surface-container-high` crossing them all at the same place; skeleton lines,
// circles, pills and rectangles, the lowest container on a highest ground, a
// 72 tall list row; a lone skeleton its own busy region at full opacity.

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
use e.ui.accessibility
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn close_to(value: u8, expected: f32) -> bool {
    let e = expected * 255.0
    let v = f32(value)
    ret v - e < 4.0 && e - v < 4.0
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

fn build(a: *mem.Arena, t: *const control.Theme) -> (widget.Node, err) {
    let (sweep, sweep_error) = control.placeholder_sweep(a, t, 0.5, 300.0, 0.45)
    if sweep_error != ok { ret (zero, sweep_error) }
    var lined = control.placeholder_options(t)
    lined.shape = .Line
    lined.sweep = sweep
    var round = control.placeholder_options(t)
    round.shape = .Circle
    round.sweep = sweep
    var blocked = control.placeholder_options(t)
    blocked.sweep = sweep
    let (p1, e1) = control.placeholder_of(a, 11u64, t, 200.0, 0.0, lined)
    let (p2, e2) = control.placeholder_of(a, 12u64, t, 40.0, 0.0, round)
    let (p3, e3) = control.placeholder_of(a, 13u64, t, 120.0, 60.0, blocked)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, e1) }
    let (shapes, shapes_error) = mem.alloc[widget.Node](a, 3usize)
    if shapes_error != ok { ret (zero, shapes_error) }
    shapes[0usize] = p1
    shapes[1usize] = p2
    shapes[2usize] = p3
    var column = style.defaults()
    column.width = style.Length { Px: 300.0 }
    let (region, region_error) = control.placeholder_region(a, 10u64, t, "Loading builds", sweep, widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 8.0 }, column, shapes[0usize..3usize]))
    if region_error != ok { ret (zero, region_error) }
    let (still, still_error) = control.placeholder_sweep(a, t, 0.0 - 1.0, 300.0, 0.4)
    if still_error != ok { ret (zero, still_error) }
    let (row, row_error) = control.skeleton_row(a, 30u64, t, 300.0, still)
    if row_error != ok { ret (zero, row_error) }
    let (people, people_error) = control.placeholder_region(a, 20u64, t, "Loading people", still, row)
    if people_error != ok { ret (zero, people_error) }
    var pill = control.skeleton_options()
    pill.shape = .Pill
    var lowest = control.skeleton_options()
    lowest.on_highest = true
    let (s1, e4) = control.skeleton_of(a, 40u64, t, 80.0, 40.0, pill)
    let (s2, e5) = control.skeleton_of(a, 41u64, t, 80.0, 40.0, lowest)
    let (s3, e6) = control.skeleton(a, 50u64, t, 120.0, 16.0, 0.0)
    let (angled_sweep, angled_sweep_error) = control.placeholder_sweep(a, t, 0.5, 120.0, 0.4)
    var angled_options = control.skeleton_options()
    angled_options.sweep = angled_sweep
    let (angled, angled_error) = control.skeleton_of(a, 60u64, t, 120.0, 60.0, angled_options)
    let (angled_region, angled_region_error) = control.placeholder_region(a, 61u64, t, "Loading angled", angled_sweep, angled)
    if e4 != ok || e5 != ok || e6 != ok || angled_sweep_error != ok || angled_error != ok || angled_region_error != ok { ret (zero, e4) }
    let (items, items_error) = mem.alloc[widget.Node](a, 6usize)
    if items_error != ok { ret (zero, items_error) }
    items[0usize] = region
    items[1usize] = people
    items[2usize] = s1
    items[3usize] = s2
    items[4usize] = s3
    items[5usize] = angled_region
    var page = style.defaults()
    page.width = style.Length { Px: 640.0 }
    page.height = style.Length { Px: 660.0 }
    page.background = paint.Brush { Solid: style.color(t.tokens, .Background) }
    let pad = style.Length { Px: 10.0 }
    page.padding = style.EdgeLengths { left: pad, top: pad, right: pad, bottom: pad }
    ret (widget.flex(0u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 12.0 }, page, items[0usize..6usize]), ok)
}

fn busy_group(tree: accessibility.Tree, label: str) -> bool {
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].role == .Group && tree.nodes[i].state.busy && same(tree.nodes[i].label, label) { ret true }
        i += 1usize
    }
    ret false
}

fn at(x: f32, y: f32) -> usize {
    ret (usize(y) * 640usize + usize(x)) * 4usize
}

fn is_color(shot: image.Image, i: usize, c: paint.Color) -> bool {
    ret close_to(shot.pixels[i], c.red) && close_to(shot.pixels[i + 1usize], c.green) && close_to(shot.pixels[i + 2usize], c.blue)
}

fn bounds(h: *testing.Harness, runtime: *widget.Runtime, key: widget.Key) -> (geometry.Rect, bool) {
    let (b, found) = widget.bounds_of(runtime, testing.by_key(h, key).element)
    ret (b, found)
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
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 600usize, max_states: 64usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 32u16, max_commands: 2048usize })
    if runtime_error != ok { os.exit(5i32) }
    var runtime = rt
    let theme = control.Theme { tokens: &tokens, fonts: fonts, language: "", runtime: &runtime }
    let (h, harness_error) = testing.harness(a, &runtime, 640u32, 660u32, 1.0)
    if harness_error != ok { os.exit(6i32) }
    var harness = h
    let (frame_storage, storage_error) = mem.alloc[u8](a, 2097152usize)
    if storage_error != ok { os.exit(7i32) }
    var f = mem.arena_from(frame_storage)
    let (root, build_error) = build(&f, &theme)
    if build_error != ok { os.exit(8i32) }
    if testing.pump(&harness, root, time.Instant { nanos: 1000000000i64 }) != ok { os.exit(9i32) }
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(10i32) }
    let (tree, tree_error) = testing.semantics(&harness)
    if tree_error != ok { os.exit(11i32) }
    let ground = style.color(&tokens, .Background)
    let highest = style.color(&tokens, .SurfaceContainerHighest)
    let high = style.color(&tokens, .SurfaceContainerHigh)
    // The region: named and busy; its shapes are not in the tree.
    if !busy_group(tree, "Loading builds") || !busy_group(tree, "Loading people") || !busy_group(tree, "") { os.exit(12i32) }
    var busy = 0usize
    var i = 0usize
    while i < tree.nodes.len {
        if tree.nodes[i].state.busy { busy += 1usize }
        i += 1usize
    }
    if busy != 4usize { os.exit(13i32) }
    // A text line 12 tall and fully rounded; the sweep's band at half its cycle
    // centred 150 into the region, `surface-container-high`, the rest
    // `surface-container-highest`.
    let (line, has_line) = bounds(&harness, &runtime, 11u64)
    if !has_line || !near(line.height, 12.0) || !near(line.width, 200.0) { os.exit(14i32) }
    if !is_color(shot, at(line.x + 150.0, line.y + 6.0), high) || !is_color(shot, at(line.x + 20.0, line.y + 6.0), highest) || !is_color(shot, at(line.x + 0.5, line.y + 0.5), ground) { os.exit(15i32) }
    // The block carries the same band (it too crosses x 150), the circle is round.
    let (block, has_block) = bounds(&harness, &runtime, 13u64)
    if !has_block || !near(block.height, 60.0) || !is_color(shot, at(block.x + 20.0, block.y + 30.0), highest) || !is_color(shot, at(block.x + 100.0, block.y + 30.0), style.mix(highest, high, 0.9)) { os.exit(16i32) }
    let (circle, has_circle) = bounds(&harness, &runtime, 12u64)
    if !has_circle || !near(circle.width, 40.0) || !near(circle.height, 40.0) || !is_color(shot, at(circle.x + 20.0, circle.y + 20.0), highest) || !is_color(shot, at(circle.x + 3.0, circle.y + 3.0), ground) { os.exit(17i32) }
    // The list row skeleton: 72 tall, a 40 circle 16 in, still (no band).
    let (row, has_row) = bounds(&harness, &runtime, 30u64)
    if !has_row || !near(row.height, 72.0) || !is_color(shot, at(row.x + 36.0, row.y + 36.0), highest) || !is_color(shot, at(row.x + 8.0, row.y + 36.0), ground) { os.exit(18i32) }
    // A pill fully rounded; a block on `surface-container-highest` takes the lowest.
    let (pill, has_pill) = bounds(&harness, &runtime, 40u64)
    if !has_pill || !is_color(shot, at(pill.x + 40.0, pill.y + 20.0), highest) || !is_color(shot, at(pill.x + 2.0, pill.y + 2.0), ground) { os.exit(19i32) }
    let (low, has_low) = bounds(&harness, &runtime, 41u64)
    if !has_low || !is_color(shot, at(low.x + 40.0, low.y + 20.0), style.color(&tokens, .SurfaceContainerLowest)) { os.exit(20i32) }
    // The lone skeleton: `surface-container-highest` at full opacity.
    let (lone, has_lone) = bounds(&harness, &runtime, 50u64)
    if !has_lone || !is_color(shot, at(lone.x + 60.0, lone.y + 8.0), highest) { os.exit(21i32) }
    let (angled, has_angled) = bounds(&harness, &runtime, 60u64)
    if !has_angled { os.exit(23i32) }
    if !is_color(shot, at(angled.x + 62.0, angled.y + 10.0), high) { os.exit(24i32) }
    if !is_color(shot, at(angled.x + 69.0, angled.y + 50.0), high) { os.exit(25i32) }
    if shot.pixels[at(angled.x + 62.0, angled.y + 10.0)] <= shot.pixels[at(angled.x + 62.0, angled.y + 50.0)] || shot.pixels[at(angled.x + 69.0, angled.y + 50.0)] <= shot.pixels[at(angled.x + 69.0, angled.y + 10.0)] { os.exit(26i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(22i32) }
    try io.print("ui status2 v2 ok\n")
    ret ok
}
