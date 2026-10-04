use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool {
    let delta = a - b
    ret delta > -0.001 && delta < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [4]f32{ 1.0, 3.0, 2.0, 4.0 }
    let y = [4]f32{ 1.0, 4.0, 2.0, 3.0 }
    let bounds = geometry.rect(20.0, 30.0, 120.0, 90.0)
    var points: [4]chart.Coord = zero
    var lines: [3]chart.Segment = zero
    let (marks, marks_error) = chart.connected_scatter(x[..], y[..], bounds, points[..], lines[..])
    if marks_error != ok || marks.kind != .PointLine || marks.coords.len != 4usize || marks.segments.len != 3usize { ret chart.Invalid }
    if !near(points[0usize].x, 20.0) || !near(points[0usize].y, 120.0) || !near(points[1usize].x, 100.0) || !near(points[1usize].y, 30.0) || !near(points[2usize].x, 60.0) || !near(points[2usize].y, 90.0) { ret chart.Invalid }
    if !near(lines[1usize].from.x, 100.0) || !near(lines[1usize].to.x, 60.0) || !near(lines[2usize].to.x, 140.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 5usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 180.0, 150.0, "Connected scatter", "Observation order")
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, empty_error) = chart.connected_scatter(x[..0usize], y[..0usize], bounds, points[..], lines[..])
    let (_, one_error) = chart.connected_scatter(x[..1usize], y[..1usize], bounds, points[..], lines[..])
    let (_, lengths_error) = chart.connected_scatter(x[..], y[..3usize], bounds, points[..], lines[..])
    let (_, bounds_error) = chart.connected_scatter(x[..], y[..], geometry.rect(0.0, 0.0, -1.0, 10.0), points[..], lines[..])
    let (_, points_error) = chart.connected_scatter(x[..], y[..], bounds, points[..3usize], lines[..])
    let (_, lines_error) = chart.connected_scatter(x[..], y[..], bounds, points[..], lines[..2usize])
    if empty_error != chart.Empty || one_error != chart.Invalid || lengths_error != chart.Invalid || bounds_error != chart.Invalid || points_error != chart.TooLarge || lines_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart connected scatter ok\n")
    ret ok
}
