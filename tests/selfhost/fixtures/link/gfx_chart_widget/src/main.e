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

fn near64(a: f64, b: f64) -> bool { ret a - b < 0.000001f64 && b - a < 0.000001f64 }

// A 3-D scatter painted with the orbit's camera; the first projected point is kept.
type Scene3d = struct { orbit: *chart_widget.Orbit, storage: chart.Scatter3dStorage, first: chart.Coord, paints: usize }

fn measure_3d(ctx: *void, limits: ui_layout.Constraints) -> geometry.Size {
    ret geometry.Size { width: 240.0, height: 160.0 }
}

fn paint_3d(ctx: *void, builder: *scene.Builder, area: geometry.Rect) -> err {
    let s = mem.cast[*Scene3d](ctx)
    let xs = [3]f64{ 0.0f64, 1.0f64, 0.5f64 }
    let ys = [3]f64{ 0.0f64, 0.5f64, 1.0f64 }
    let zs = [3]f64{ 1.0f64, 0.0f64, 0.5f64 }
    let (laid, laid_error) = chart.scatter3d(xs[..], ys[..], zs[..], s.orbit.camera, area, &s.storage)
    if laid_error != ok { ret laid_error }
    s.first = laid.points[0usize]
    s.paints += 1usize
    ret ok
}

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
    // Wrapped in its region the chart takes the pointer (D2114). The plot is still
    // 16..224 x 16..144; the last point sits at (172, 16).
    var region_style = style.defaults()
    region_style.width = style.Length { Px: 240.0 }
    region_style.height = style.Length { Px: 160.0 }
    let (wrapped, wrapped_error) = mem.alloc[widget.Node](a, 1usize)
    if wrapped_error != ok { os.exit(23i32) }
    wrapped[0usize] = canvas
    children[0usize] = widget.region(9u64, chart_widget.region(&v), region_style, wrapped[..1usize])
    var now = time.instant_add(start, time.millis(48i64))
    if testing.pump(&harness, root, now) != ok || !near(v.plot.x, 16.0) || !near(v.marks.coords[3usize].y, 16.0) { os.exit(24i32) }
    // Hovering near a point outlines it in orange; empty space clears it.
    let before_hover = v.revision
    if testing.hover(&harness, 170.0, 18.0) != ok || !v.has_hovered || v.hovered != 3usize || v.revision == before_hover { os.exit(25i32) }
    now = time.instant_add(now, time.millis(16i64))
    if testing.pump(&harness, root, now) != ok { os.exit(26i32) }
    let (lit, lit_error) = testing.snapshot(&harness, a)
    if lit_error != ok { os.exit(27i32) }
    let edge = (16usize * usize(lit.width) + 167usize) * 4usize
    if lit.pixels[edge] < 200u8 || lit.pixels[edge + 2usize] > 80u8 { os.exit(28i32) }
    if testing.hover(&harness, 60.0, 130.0) != ok || v.has_hovered { os.exit(29i32) }
    // Turning the wheel out over the whole plot changes nothing; in, it zooms about
    // the pointer: the point under it stays put.
    let before_wheel = v.revision
    if testing.wheel(&harness, 120.0, 80.0, -1i32) != ok || v.revision != before_wheel || v.window.width != 1.0 { os.exit(30i32) }
    var expected_width: f32 = 1.0
    var turns = 0usize
    while turns < 9usize {
        if testing.wheel(&harness, 120.0, 80.0, 1i32) != ok { os.exit(31i32) }
        expected_width = expected_width / 1.1
        turns += 1usize
    }
    if !near(v.window.width, expected_width) || !near(v.window.height, expected_width) || !near(v.window.x + 0.5 * v.window.width, 0.5) || !near(v.window.y + 0.5 * v.window.height, 0.5) { os.exit(32i32) }
    now = time.instant_add(now, time.millis(16i64))
    if testing.pump(&harness, root, now) != ok { os.exit(33i32) }
    if !near(v.marks.coords[3usize].x, 16.0 + (172.0 - 16.0 - v.window.x * 208.0) / v.window.width) || !near(v.marks.coords[3usize].y, 16.0 - v.window.y * 128.0 / v.window.height) { os.exit(34i32) }
    // A drag pans by what the pointer moved, measured from the press.
    let panned_from = v.window
    if testing.drag(&harness, geometry.Point { x: 120.0, y: 80.0 }, geometry.Point { x: 140.0, y: 70.0 }, 4usize) != ok { os.exit(35i32) }
    if !near(v.window.x, panned_from.x - 20.0 / 208.0 * panned_from.width) || !near(v.window.y, panned_from.y + 10.0 / 128.0 * panned_from.height) || v.window.width != panned_from.width { os.exit(36i32) }
    now = time.instant_add(now, time.millis(16i64))
    if testing.pump(&harness, root, now) != ok { os.exit(37i32) }
    // A double tap shows everything again; the zoom stops at `min_window`.
    if testing.tap(&harness, 120.0, 80.0) != ok || testing.tap(&harness, 120.0, 80.0) != ok || v.window.x != 0.0 || v.window.width != 1.0 || v.window.height != 1.0 { os.exit(38i32) }
    turns = 0usize
    while turns < 60usize {
        if testing.wheel(&harness, 30.0, 30.0, 1i32) != ok { os.exit(39i32) }
        turns += 1usize
    }
    if !near(v.window.width, 1.0 / 64.0) || !(v.window.x >= 0.0) || !(v.window.y >= 0.0) { os.exit(40i32) }
    now = time.instant_add(now, time.millis(16i64))
    if testing.pump(&harness, root, now) != ok { os.exit(41i32) }
    // A 3-D camera orbits (D2116): the azimuth wraps, the elevation is held.
    let (wrapped_turn, wrap_error) = chart.orbit(chart.Camera3d { azimuth_degrees: 170.0f64, elevation_degrees: 30.0f64, distance: 6.0f64 }, 20.0f64, 0.0f64, 5.0f64, 85.0f64)
    if wrap_error != ok || !near64(wrapped_turn.azimuth_degrees, -170.0f64) || !near64(wrapped_turn.distance, 6.0f64) { os.exit(42i32) }
    let (held, held_error) = chart.orbit(chart.Camera3d { azimuth_degrees: 0.0f64, elevation_degrees: 80.0f64, distance: 6.0f64 }, -540.0f64, 20.0f64, 5.0f64, 85.0f64)
    if held_error != ok || !near64(held.elevation_degrees, 85.0f64) || !near64(held.azimuth_degrees, -180.0f64) { os.exit(43i32) }
    let (_, crossed_error) = chart.orbit(held, 0.0f64, 0.0f64, 50.0f64, 40.0f64)
    let (_, beyond_error) = chart.orbit(held, 0.0f64, 0.0f64, 5.0f64, 95.0f64)
    if crossed_error != chart.Invalid || beyond_error != chart.Invalid { os.exit(44i32) }
    // Dragging a canvas in an orbit region turns the camera and repaints.
    var o = chart_widget.orbit(chart.Camera3d { azimuth_degrees: 30.0f64, elevation_degrees: 25.0f64, distance: 6.0f64 })
    var points3d: [3]chart.Coord = zero
    var depths3d: [3]f64 = zero
    var order3d: [3]usize = zero
    var bubbles3d: [3]geometry.Rect = zero
    var corners3d: [8]chart.Coord = zero
    var edges3d: [12]chart.Segment = zero
    var s3 = Scene3d { orbit: &o, storage: chart.Scatter3dStorage { points: points3d[..], depths: depths3d[..], order: order3d[..], bubbles: bubbles3d[..], corners: corners3d[..], edges: edges3d[..] }, first: zero, paints: 0usize }
    let (canvas3d, canvas3d_error) = control.canvas(a, 11u64, widget.Custom { ctx: mem.cast[*void](&s3), measure: measure_3d, paint: paint_3d, state: widget.bytes_of[u64](&o.revision) }, "Orbiting scatter")
    if canvas3d_error != ok { os.exit(45i32) }
    let (wrapped3d, wrapped3d_error) = mem.alloc[widget.Node](a, 1usize)
    if wrapped3d_error != ok { os.exit(46i32) }
    wrapped3d[0usize] = canvas3d
    children[0usize] = widget.region(12u64, chart_widget.orbit_region(&o), region_style, wrapped3d[..1usize])
    now = time.instant_add(now, time.millis(16i64))
    if testing.pump(&harness, root, now) != ok || s3.paints == 0usize { os.exit(47i32) }
    let first_before = s3.first
    let paints_before = s3.paints
    if testing.drag(&harness, geometry.Point { x: 120.0, y: 80.0 }, geometry.Point { x: 140.0, y: 90.0 }, 4usize) != ok { os.exit(48i32) }
    if !near64(o.camera.azimuth_degrees, 20.0f64) || !near64(o.camera.elevation_degrees, 30.0f64) { os.exit(49i32) }
    now = time.instant_add(now, time.millis(16i64))
    if testing.pump(&harness, root, now) != ok || s3.paints == paints_before || (near(s3.first.x, first_before.x) && near(s3.first.y, first_before.y)) { os.exit(50i32) }
    if testing.drag(&harness, geometry.Point { x: 120.0, y: 20.0 }, geometry.Point { x: 120.0, y: 150.0 }, 4usize) != ok || !near64(o.camera.elevation_degrees, 85.0f64) { os.exit(51i32) }
    if testing.tap(&harness, 120.0, 80.0) != ok || testing.tap(&harness, 120.0, 80.0) != ok || !near64(o.camera.azimuth_degrees, 30.0f64) || !near64(o.camera.elevation_degrees, 25.0f64) { os.exit(52i32) }
    if testing.close(&harness) != ok || widget.close(&runtime) != ok || scene.close(&renderer) != ok || gpu.close(device) != ok { os.exit(22i32) }
    try io.print("gfx chart widget ok\n")
    ret ok
}
