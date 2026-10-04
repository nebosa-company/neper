use e.gfx.chart
use e.gfx.chart.widget as chart_widget
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gpu
use e.io
use e.mem
use e.os
use e.time
use e.ui.control
use e.ui.layout as ui_layout
use e.ui.style
use e.ui.testing
use e.ui.widget

fn near(a: f32, b: f32) -> bool { ret a - b < 0.01 && b - a < 0.01 }

fn main(a: *mem.Arena, args: []str) -> err {
    var x = [4]f32{ 1.0, 2.0, 3.0, 4.0 }
    let y = [4]f32{ 10.0, 30.0, 20.0, 40.0 }
    var coords: [4]chart.Coord = zero
    let blue = paint.rgba(0.0, 0.0, 1.0, 1.0)
    let spec = chart.spec(.Scatter, geometry.rect(0.0, 0.0, 1.0, 1.0), x[..], y[..])
    var v = chart_widget.view(a, spec, paint.Brush { Solid: blue }, coords[..], zero, zero)
    let custom = chart_widget.custom(&v)
    // Measure answers the preferred size inside the constraints.
    let free = custom.measure(custom.ctx, ui_layout.Constraints { min_width: 0.0, max_width: 1000.0, min_height: 0.0, max_height: 1000.0 })
    let narrow = custom.measure(custom.ctx, ui_layout.Constraints { min_width: 0.0, max_width: 200.0, min_height: 180.0, max_height: 1000.0 })
    if !near(free.width, 240.0) || !near(free.height, 160.0) || !near(narrow.width, 200.0) || !near(narrow.height, 180.0) { os.exit(1i32) }
    // Each paint lays the chart out inside the rectangle it is given.
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { os.exit(2i32) }
    var builder = made
    if custom.paint(custom.ctx, &builder, geometry.rect(0.0, 0.0, 240.0, 160.0)) != ok { os.exit(3i32) }
    if !near(v.plot.x, 16.0) || !near(v.plot.width, 208.0) || v.marks.coords.len != 4usize || !near(v.marks.coords[0usize].x, 16.0) || !near(v.marks.coords[3usize].x, 224.0) || !near(v.marks.coords[3usize].y, 16.0) { os.exit(4i32) }
    if custom.paint(custom.ctx, &builder, geometry.rect(100.0, 50.0, 480.0, 320.0)) != ok { os.exit(5i32) }
    if !near(v.marks.coords[0usize].x, 116.0) || !near(v.marks.coords[3usize].x, 564.0) || !near(v.marks.coords[0usize].y, 354.0) || scene.builder_count(&builder) < 8usize { os.exit(6i32) }
    if custom.paint(custom.ctx, &builder, geometry.rect(0.0, 0.0, 20.0, 20.0)) != ok || v.marks.coords.len != 0usize { os.exit(7i32) }
    // Through the widget runtime: a labelled canvas in a sized column.
    let (device, open_error) = gpu.open(a, .Cpu, 0u32)
    if open_error != ok { os.exit(8i32) }
    let (q, queue_error) = gpu.queue(device)
    if queue_error != ok { os.exit(9i32) }
    let (r, renderer_error) = scene.renderer(a, device, q, 4u32, 4u32)
    if renderer_error != ok { os.exit(10i32) }
    var renderer = r
    let (rt, runtime_error) = widget.runtime(a, &renderer, widget.Limits { max_elements: 16usize, max_states: 8usize, state_bytes: 256usize, state_classes: 2u16, max_depth: 8u16, max_commands: 64usize })
    if runtime_error != ok { os.exit(11i32) }
    var runtime = rt
    let (h, harness_error) = testing.harness(a, &runtime, 300u32, 200u32, 1.0)
    if harness_error != ok { os.exit(12i32) }
    var harness = h
    let (canvas, canvas_error) = control.canvas(a, 7u64, custom, "Quarterly revenue")
    if canvas_error != ok { os.exit(13i32) }
    let (children, children_error) = mem.alloc[widget.Node](a, 1usize)
    if children_error != ok { os.exit(14i32) }
    children[0usize] = canvas
    var column = style.defaults()
    column.width = style.Length { Px: 300.0 }
    column.height = style.Length { Px: 200.0 }
    let root = widget.flex(1u64, ui_layout.Flex { axis: .Vertical, main: .Start, cross: .Start, gap: 0.0 }, column, children[..1usize])
    let start = time.Instant { nanos: 1000000000i64 }
    if testing.pump(&harness, root, start) != ok { os.exit(15i32) }
    if testing.by_key(&harness, 7u64).count != 1usize || testing.by_label(&harness, "Quarterly revenue").count != 1usize { os.exit(16i32) }
    if !near(v.plot.x, 16.0) || !near(v.plot.y, 16.0) || !near(v.plot.width, 208.0) || !near(v.plot.height, 128.0) { os.exit(17i32) }
    // The pixel under the last point is the series colour.
    let (shot, shot_error) = testing.snapshot(&harness, a)
    if shot_error != ok { os.exit(18i32) }
    let last = v.marks.coords[3usize]
    let at = (usize(last.y) * usize(shot.width) + usize(last.x)) * 4usize
    if shot.pixels[at] != 0u8 || shot.pixels[at + 2usize] != 255u8 || shot.pixels[at + 3usize] != 255u8 { os.exit(19i32) }
    // An unchanged revision replays the last paint; a bumped one lays out again.
    x[3usize] = 2.5
    if testing.pump(&harness, root, time.instant_add(start, time.millis(16i64))) != ok || !near(v.marks.coords[3usize].x, 224.0) { os.exit(20i32) }
    v.revision += 1u64
    if testing.pump(&harness, root, time.instant_add(start, time.millis(32i64))) != ok || !near(v.marks.coords[3usize].x, 16.0 + 208.0 * 0.75) { os.exit(21i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(22i32) }
    try io.print("gfx chart widget ok\n")
    ret ok
}
