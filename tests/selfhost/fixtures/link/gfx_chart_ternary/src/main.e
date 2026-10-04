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
    let difference = a - b
    ret difference > -0.01 && difference < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let top = [5]f32{ 1.0, 0.0, 0.0, 1.0, 1.0 }
    let left = [5]f32{ 0.0, 1.0, 0.0, 1.0, 1.0 }
    let right = [5]f32{ 0.0, 0.0, 1.0, 1.0, 0.0 }
    var points: [5]chart.Coord = zero
    var lines: [9]chart.Segment = zero
    let (marks, grid, chart_error) = chart.ternary(top[..], left[..], right[..], bounds, 3usize, points[..], lines[..])
    if chart_error != ok || marks.kind != .Scatter || marks.coords.len != 5usize || grid.kind != .Rug || grid.segments.len != 9usize { ret chart.Invalid }
    if !near(points[0usize].x, 50.0) || !near(points[0usize].y, 6.70) || !near(points[1usize].x, 0.0) || !near(points[1usize].y, 93.30) || !near(points[2usize].x, 100.0) || !near(points[2usize].y, 93.30) { ret chart.Invalid }
    if !near(points[3usize].x, 50.0) || !near(points[3usize].y, 64.43) || !near(points[4usize].x, 25.0) || !near(points[4usize].y, 50.0) { ret chart.Invalid }
    if !near(lines[0usize].from.x, 0.0) || !near(lines[0usize].to.x, 100.0) || !near(lines[1usize].from.y, 6.70) || !near(lines[3usize].from.y, 64.43) { ret chart.Invalid }
    let bad = [5]f32{ -1.0, 0.0, 0.0, 1.0, 1.0 }
    let empty = [5]f32{ 0.0, 0.0, 0.0, 1.0, 1.0 }
    let (_, _, negative_error) = chart.ternary(bad[..], left[..], right[..], bounds, 3usize, points[..], lines[..])
    let (_, _, zero_error) = chart.ternary(empty[..], empty[..], empty[..], bounds, 3usize, points[..], lines[..])
    let (_, _, shape_error) = chart.ternary(top[..], left[..4usize], right[..], bounds, 3usize, points[..], lines[..])
    let (_, _, capacity_error) = chart.ternary(top[..], left[..], right[..], bounds, 3usize, points[..4usize], lines[..])
    let (_, _, grid_error) = chart.ternary(top[..], left[..], right[..], bounds, 3usize, points[..], lines[..8usize])
    if negative_error != chart.Invalid || zero_error != chart.Invalid || shape_error != chart.Invalid || capacity_error != chart.TooLarge || grid_error != chart.TooLarge { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &grid, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 14usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Ternary", "Three-part composition")
    try chart_svg.append(&writer, &grid, ink)
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart ternary ok\n")
    ret ok
}
