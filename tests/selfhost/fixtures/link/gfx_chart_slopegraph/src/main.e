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
    let before = [3]f32{ 10.0, 20.0, 30.0 }
    let after = [3]f32{ 30.0, 20.0, 10.0 }
    let bounds = geometry.rect(40.0, 50.0, 120.0, 100.0)
    var points: [6]chart.Coord = zero
    var lines: [3]chart.Segment = zero
    let (marks, marks_error) = chart.slopegraph(before[..], after[..], bounds, points[..], lines[..])
    if marks_error != ok || marks.kind != .SlopeGraph || marks.coords.len != 6usize || marks.segments.len != 3usize || !near(marks.y_min, 10.0) || !near(marks.y_max, 30.0) { ret chart.Invalid }
    if !near(points[0usize].x, 40.0) || !near(points[0usize].y, 150.0) || !near(points[1usize].x, 160.0) || !near(points[1usize].y, 50.0) { ret chart.Invalid }
    if !near(points[2usize].y, 100.0) || !near(points[3usize].y, 100.0) || !near(lines[2usize].from.y, 50.0) || !near(lines[2usize].to.y, 150.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 9usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 200.0, 180.0, "Slopegraph", "Paired changes")
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let flat = [2]f32{ 7.0, 7.0 }
    let (same, same_error) = chart.slopegraph(flat[..], flat[..], bounds, points[..], lines[..])
    if same_error != ok || !near(same.y_min, 6.5) || !near(same.y_max, 7.5) { ret chart.Invalid }
    let (_, empty_error) = chart.slopegraph(before[..0usize], after[..0usize], bounds, points[..], lines[..])
    let (_, lengths_error) = chart.slopegraph(before[..], after[..2usize], bounds, points[..], lines[..])
    let (_, bounds_error) = chart.slopegraph(before[..], after[..], geometry.rect(0.0, 0.0, 0.0, 20.0), points[..], lines[..])
    let (_, points_error) = chart.slopegraph(before[..], after[..], bounds, points[..5usize], lines[..])
    let (_, lines_error) = chart.slopegraph(before[..], after[..], bounds, points[..], lines[..2usize])
    if empty_error != chart.Empty || lengths_error != chart.Invalid || bounds_error != chart.Invalid || points_error != chart.TooLarge || lines_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart slopegraph ok\n")
    ret ok
}
