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
    ret delta > -0.01 && delta < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [5]f32{ 0.0, 1.0, 0.0, -1.0, 0.0 }
    var points: [4]chart.Coord = zero
    var segments: [3]chart.Segment = zero
    let bounds = geometry.rect(0.0, 0.0, 100.0, 80.0)
    let (marks, chart_error) = chart.phase_space(values[..], 1usize, bounds, points[..], segments[..])
    if chart_error != ok || marks.kind != .PointLine || marks.coords.len != 4usize || marks.segments.len != 3usize || !near(marks.x_min, -1.0) || !near(marks.y_max, 1.0) { ret chart.Invalid }
    if !near(points[0usize].x, 50.0) || !near(points[0usize].y, 0.0) || !near(points[1usize].x, 90.0) || !near(points[1usize].y, 40.0) || !near(points[2usize].y, 80.0) || !near(points[3usize].x, 10.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 5usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 80.0, "Phase space", "Two-dimensional delay embedding")
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, lag_error) = chart.phase_space(values[..], 0usize, bounds, points[..], segments[..])
    let (_, count_error) = chart.phase_space(values[..], 4usize, bounds, points[..], segments[..])
    let (_, capacity_error) = chart.phase_space(values[..], 1usize, bounds, points[..3usize], segments[..])
    let constant = [4]f32{ 2.0, 2.0, 2.0, 2.0 }
    let (flat, flat_error) = chart.phase_space(constant[..], 1usize, bounds, points[..], segments[..])
    if lag_error != chart.Invalid || count_error != chart.Invalid || capacity_error != chart.TooLarge || flat_error != ok || !near(flat.coords[0usize].x, 50.0) || !near(flat.coords[0usize].y, 40.0) { ret chart.Invalid }
    try io.print("gfx chart phase space ok\n")
    ret ok
}
