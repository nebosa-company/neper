use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool {
    let difference = a - b
    ret difference > -0.00001f64 && difference < 0.00001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [3]f32{ 0.0, 1.0, 2.0 }
    let y = [3]f32{ 0.0, 0.0, 0.0 }
    let values = [3]f32{ 1.0, 2.0, 4.0 }
    let bounds = geometry.rect(0.0, 0.0, 160.0, 100.0)
    var counts: [2]u64 = zero
    var distances: [2]f64 = zero
    var gamma: [2]f64 = zero
    var points: [2]chart.Coord = zero
    let (marks, chart_error) = chart.variogram(x[..], y[..], values[..], 2.0, bounds, counts[..], distances[..], gamma[..], points[..])
    if chart_error != ok || marks.kind != .Scatter || marks.coords.len != 2usize { ret chart.Invalid }
    if counts[0usize] != 2u64 || counts[1usize] != 1u64 || !near(distances[0usize], 1.0f64) || !near(distances[1usize], 2.0f64) || !near(gamma[0usize], 1.25f64) || !near(gamma[1usize], 4.5f64) { ret chart.Invalid }
    if !near(f64(marks.coords[0usize].x), 80.0f64) || !near(f64(marks.coords[1usize].x), 160.0f64) || !near(f64(marks.coords[1usize].y), 0.0f64) { ret chart.Invalid }
    let vertical_x = [2]f32{ 0.0, 0.0 }
    let vertical_y = [2]f32{ 0.0, 2.0 }
    let vertical_values = [2]f32{ 1.0, 3.0 }
    let (vertical, vertical_error) = chart.variogram(vertical_x[..], vertical_y[..], vertical_values[..], 2.0, bounds, counts[..], distances[..], gamma[..], points[..])
    if vertical_error != ok || vertical.coords.len != 1usize || counts[0usize] != 0u64 || counts[1usize] != 1u64 || !near(distances[1usize], 2.0f64) || !near(gamma[1usize], 2.0f64) { ret chart.Invalid }
    let (_, cutoff_error) = chart.variogram(x[..], y[..], values[..], 0.5, bounds, counts[..], distances[..], gamma[..], points[..])
    let (_, capacity_error) = chart.variogram(x[..], y[..], values[..], 2.0, bounds, counts[..], distances[..], gamma[..], points[..1usize])
    let (_, shape_error) = chart.variogram(x[..2usize], y[..], values[..], 2.0, bounds, counts[..], distances[..], gamma[..], points[..])
    if cutoff_error != chart.Empty || capacity_error != chart.TooLarge || shape_error != chart.Invalid { ret chart.Invalid }
    let (again, again_error) = chart.variogram(x[..], y[..], values[..], 2.0, bounds, counts[..], distances[..], gamma[..], points[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &again, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 160.0, 100.0, "Empirical variogram", "Distance-binned classical semivariance")
    try chart_svg.append(&writer, &again, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart variogram ok\n")
    ret ok
}
