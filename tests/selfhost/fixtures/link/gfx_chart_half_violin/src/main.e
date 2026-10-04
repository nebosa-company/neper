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
    let values = [7]f64{ 1.0f64, 2.0f64, 2.0f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 160.0, 100.0)
    var grid: [33]f64 = zero
    var estimates: [33]f64 = zero
    var left_points: [35]chart.Coord = zero
    var right_points: [35]chart.Coord = zero
    let (left, left_error) = chart.half_violin(values[..], bounds, 0.7f64, false, grid[..], estimates[..], left_points[..])
    let (right, right_error) = chart.half_violin(values[..], bounds, 0.7f64, true, grid[..], estimates[..], right_points[..])
    if left_error != ok || right_error != ok || left.kind != .Violin || right.kind != .Violin || left.coords.len != 35usize || right.coords.len != 35usize || left.y_min >= 1.0 || left.y_max <= 6.0 { ret chart.Invalid }
    let center = bounds.x + bounds.width * 0.5
    if !near(left.coords[0usize].x, center) || !near(left.coords[0usize].y, bounds.y + bounds.height) || !near(left.coords[34usize].x, center) || !near(left.coords[34usize].y, bounds.y) { ret chart.Invalid }
    var i = 1usize
    var has_width = false
    while i < 34usize {
        if left.coords[i].x > center || right.coords[i].x < center || !near(left.coords[i].x + right.coords[i].x, center * 2.0) || !near(left.coords[i].y, right.coords[i].y) { ret chart.Invalid }
        if left.coords[i].x < center - 10.0 { has_width = true }
        i += 1usize
    }
    if !has_width { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &left, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &right, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 190.0, 140.0, "Half violin", "One-sided kernel density")
    try chart_svg.append(&writer, &left, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, empty_error) = chart.half_violin(values[..0usize], bounds, 0.7f64, false, grid[..], estimates[..], left_points[..])
    let (_, bandwidth_error) = chart.half_violin(values[..], bounds, -1.0f64, false, grid[..], estimates[..], left_points[..])
    let (_, bounds_error) = chart.half_violin(values[..], geometry.rect(0.0, 0.0, -1.0, 100.0), 0.7f64, false, grid[..], estimates[..], left_points[..])
    let (_, grid_error) = chart.half_violin(values[..], bounds, 0.7f64, false, grid[..1usize], estimates[..], left_points[..])
    let (_, estimates_error) = chart.half_violin(values[..], bounds, 0.7f64, false, grid[..], estimates[..32usize], left_points[..])
    let (_, outline_error) = chart.half_violin(values[..], bounds, 0.7f64, false, grid[..], estimates[..], left_points[..34usize])
    if empty_error != chart.Empty || bandwidth_error != chart.Invalid || bounds_error != chart.Invalid || grid_error != chart.TooLarge || estimates_error != chart.TooLarge || outline_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart half violin ok\n")
    ret ok
}
