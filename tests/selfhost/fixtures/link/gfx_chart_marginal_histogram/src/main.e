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
    let x = [6]f32{ 0.0, 0.0, 1.0, 2.0, 4.0, 5.0 }
    let y = [6]f32{ 0.0, 0.0, 0.0, 1.0, 1.0, 2.0 }
    let bounds = geometry.rect(50.0, 60.0, 120.0, 90.0)
    var points: [6]chart.Coord = zero
    var x_counts: [3]u64 = zero
    var y_counts: [3]u64 = zero
    var x_bars: [3]geometry.Rect = zero
    var y_bars: [3]geometry.Rect = zero
    let (map, map_error) = chart.marginal_histogram(x[..], y[..], bounds, 30.0, 40.0, 5.0, points[..], x_counts[..], x_bars[..], y_counts[..], y_bars[..])
    if map_error != ok || map.scatter.kind != .Scatter || map.top.kind != .Histogram || map.right.kind != .Histogram || map.scatter.coords.len != 6usize { ret chart.Invalid }
    if x_counts[0usize] != 3u64 || x_counts[1usize] != 1u64 || x_counts[2usize] != 2u64 || y_counts[0usize] != 3u64 || y_counts[1usize] != 2u64 || y_counts[2usize] != 1u64 { ret chart.Invalid }
    if !near(x_bars[0usize].x, bounds.x) || !near(x_bars[0usize].y, 25.0) || !near(x_bars[0usize].width, 40.0) || !near(y_bars[0usize].x, 175.0) || !near(y_bars[0usize].y, 120.0) || !near(y_bars[0usize].width, 40.0) || !near(y_bars[2usize].y, 60.0) { ret chart.Invalid }
    if !near(map.scatter.coords[0usize].x, bounds.x) || !near(map.scatter.coords[0usize].y, 150.0) || !near(map.top.x_min, map.scatter.x_min) || !near(map.right.y_max, map.scatter.y_max) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.top, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.right, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.scatter, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 12usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 240.0, 180.0, "Marginal histogram", "Aligned x and y frequencies")
    try chart_svg.append(&writer, &map.top, ink)
    try chart_svg.append(&writer, &map.right, ink)
    try chart_svg.append(&writer, &map.scatter, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let flat = [2]f32{ 7.0, 7.0 }
    let (same, same_error) = chart.marginal_histogram(flat[..], flat[..], bounds, 30.0, 40.0, 5.0, points[..], x_counts[..], x_bars[..], y_counts[..], y_bars[..])
    if same_error != ok || !near(same.scatter.x_min, same.top.x_min) || !near(same.scatter.y_max, same.right.y_max) { ret chart.Invalid }
    let (_, empty_error) = chart.marginal_histogram(x[..0usize], y[..0usize], bounds, 30.0, 40.0, 5.0, points[..], x_counts[..], x_bars[..], y_counts[..], y_bars[..])
    let (_, lengths_error) = chart.marginal_histogram(x[..], y[..5usize], bounds, 30.0, 40.0, 5.0, points[..], x_counts[..], x_bars[..], y_counts[..], y_bars[..])
    let (_, gap_error) = chart.marginal_histogram(x[..], y[..], bounds, 30.0, 40.0, -1.0, points[..], x_counts[..], x_bars[..], y_counts[..], y_bars[..])
    let (_, points_error) = chart.marginal_histogram(x[..], y[..], bounds, 30.0, 40.0, 5.0, points[..5usize], x_counts[..], x_bars[..], y_counts[..], y_bars[..])
    let (_, bins_error) = chart.marginal_histogram(x[..], y[..], bounds, 30.0, 40.0, 5.0, points[..], x_counts[..0usize], x_bars[..0usize], y_counts[..], y_bars[..])
    if empty_error != chart.Empty || lengths_error != chart.Invalid || gap_error != chart.Invalid || points_error != chart.TooLarge || bins_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart marginal histogram ok\n")
    ret ok
}
