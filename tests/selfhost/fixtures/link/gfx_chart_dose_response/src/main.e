use e.algo.stat
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(value: f64, expected: f64) -> bool {
    let delta = value - expected
    ret delta > -0.001f64 && delta < 0.001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (mid, mid_error) = stat.log_logistic4(10.0f64, 0.0f64, 100.0f64, 10.0f64, -2.0f64)
    let (low, low_error) = stat.log_logistic4(1.0f64, 0.0f64, 100.0f64, 10.0f64, -2.0f64)
    let (high, high_error) = stat.log_logistic4(100.0f64, 0.0f64, 100.0f64, 10.0f64, -2.0f64)
    let (decreasing, decreasing_error) = stat.log_logistic4(1.0f64, 0.0f64, 100.0f64, 10.0f64, 2.0f64)
    if mid_error != ok || low_error != ok || high_error != ok || decreasing_error != ok || !near(mid, 50.0f64) || !near(low, 0.990099f64) || !near(high, 99.009901f64) || !near(decreasing, 99.009901f64) { ret chart.Invalid }
    let doses = [5]f64{ 1.0f64, 3.16227766f64, 10.0f64, 31.6227766f64, 100.0f64 }
    let responses = [5]f64{ 1.0f64, 9.0f64, 50.0f64, 91.0f64, 99.0f64 }
    let bounds = geometry.rect(20.0, 30.0, 200.0, 100.0)
    var grid: [5]f64 = zero
    var estimates: [5]f64 = zero
    var points: [5]chart.Coord = zero
    var segments: [4]chart.Segment = zero
    let (map, map_error) = chart.dose_response(doses[..], responses[..], 0.0f64, 100.0f64, 10.0f64, -2.0f64, bounds, grid[..], estimates[..], points[..], segments[..])
    if map_error != ok || map.observations.coords.len != 5usize || map.curve.segments.len != 4usize || map.observations.kind != .Scatter || map.curve.kind != .Line { ret chart.Invalid }
    if !near(grid[0usize], 1.0f64) || !near(grid[2usize], 10.0f64) || !near(grid[4usize], 100.0f64) || !near(estimates[2usize], 50.0f64) || !near(f64(points[2usize].x), 120.0f64) || !near(f64(points[2usize].y), 80.0f64) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.curve, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.observations, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 6usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 240.0, 160.0, "Dose response", "Log-dose LL.4 curve and observations")
    try chart_svg.append(&writer, &map.curve, ink)
    try chart_svg.append(&writer, &map.observations, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, model_invalid) = stat.log_logistic4(0.0f64, 0.0f64, 100.0f64, 10.0f64, -2.0f64)
    let (_, slope_invalid) = stat.log_logistic4(1.0f64, 0.0f64, 100.0f64, 10.0f64, 0.0f64)
    let (_, empty_error) = chart.dose_response(doses[..0usize], responses[..0usize], 0.0f64, 100.0f64, 10.0f64, -2.0f64, bounds, grid[..], estimates[..], points[..], segments[..])
    let (_, lengths_error) = chart.dose_response(doses[..], responses[..4usize], 0.0f64, 100.0f64, 10.0f64, -2.0f64, bounds, grid[..], estimates[..], points[..], segments[..])
    let (_, capacity_error) = chart.dose_response(doses[..], responses[..], 0.0f64, 100.0f64, 10.0f64, -2.0f64, bounds, grid[..], estimates[..], points[..], segments[..3usize])
    if model_invalid != stat.Invalid || slope_invalid != stat.Invalid || empty_error != chart.Empty || lengths_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart dose response ok\n")
    ret ok
}
