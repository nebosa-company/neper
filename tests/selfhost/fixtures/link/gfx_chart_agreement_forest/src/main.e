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

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d > -0.02 && d < 0.02
}

fn main(a: *mem.Arena, args: []str) -> err {
    let estimates = [3]f32{ 1.0, 1.4, 1.6 }
    let lows = [3]f32{ 0.8, 1.0, 1.2 }
    let highs = [3]f32{ 1.2, 1.8, 2.2 }
    let bounds = geometry.rect(40.0, 30.0, 240.0, 120.0)
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    let log_scale = chart.Scale { kind: .Log10, reverse: false, linthresh: 1.0 }
    var points: [4]chart.Coord = zero
    var intervals: [3]chart.Segment = zero
    var reference: [1]chart.Segment = zero
    let (forest, rule, forest_error) = chart.forest_plot(estimates[..], lows[..], highs[..], 1.0, linear, bounds, points[..], intervals[..], reference[..])
    if forest_error != ok || forest.kind != .Dumbbell || rule.kind != .Rug || forest.coords.len != 3usize || forest.segments.len != 3usize || !near(forest.x_min, 0.8) || !near(forest.x_max, 2.2) || !near(points[0usize].x, 74.2857) || !near(points[0usize].y, 50.0) || !near(points[2usize].y, 130.0) || !near(reference[0usize].from.x, 74.2857) { ret chart.Invalid }
    let (log_forest, log_rule, log_error) = chart.forest_plot(estimates[..], lows[..], highs[..], 1.0, log_scale, bounds, points[..], intervals[..], reference[..])
    if log_error != ok || !near(log_forest.coords[0usize].x, log_rule.segments[0usize].from.x) || !(log_forest.coords[2usize].x > log_forest.coords[1usize].x) { ret chart.Invalid }
    let wrong = [1]f32{ 0.5 }
    let (_, _, containment_error) = chart.forest_plot(wrong[..], lows[..1usize], highs[..1usize], 1.0, linear, bounds, points[..], intervals[..], reference[..])
    if containment_error != chart.Invalid { ret chart.Invalid }
    let (_, _, log_domain_error) = chart.forest_plot(estimates[..], lows[..], highs[..], 0.0, log_scale, bounds, points[..], intervals[..], reference[..])
    if log_domain_error != chart.Invalid { ret chart.Invalid }
    let (_, _, forest_capacity_error) = chart.forest_plot(estimates[..], lows[..], highs[..], 1.0, linear, bounds, points[..2usize], intervals[..], reference[..])
    if forest_capacity_error != chart.TooLarge { ret chart.Invalid }

    let left = [4]f64{ 2.0f64, 4.0f64, 6.0f64, 8.0f64 }
    let right = [4]f64{ 1.0f64, 2.0f64, 4.0f64, 5.0f64 }
    let (agreement, defined) = stat.agreement_limits(left[..], right[..], 1.96f64)
    if !defined || !near(f32(agreement.bias), 2.0) || !near(f32(agreement.lower), 0.3997) || !near(f32(agreement.upper), 3.6003) { ret chart.Invalid }
    let (_, short_defined) = stat.agreement_limits(left[..1usize], right[..1usize], 1.96f64)
    if short_defined { ret chart.Invalid }
    var means: [4]f32 = zero
    var differences: [4]f32 = zero
    var dots: [4]chart.Coord = zero
    var guides: [3]chart.Segment = zero
    let (scatter, limits, agreement_error) = chart.bland_altman(left[..], right[..], 1.96f64, bounds, means[..], differences[..], dots[..], guides[..])
    if agreement_error != ok || scatter.kind != .Scatter || scatter.coords.len != 4usize || limits.kind != .Rug || limits.segments.len != 3usize || !near(means[0usize], 1.5) || !near(differences[3usize], 3.0) || !near(dots[0usize].x, 40.0) || !near(guides[0usize].from.y, 150.0) || !near(guides[1usize].from.y, 90.0) || !near(guides[2usize].from.y, 30.0) { ret chart.Invalid }
    let (_, _, agreement_capacity_error) = chart.bland_altman(left[..], right[..], 1.96f64, bounds, means[..], differences[..], dots[..], guides[..2usize])
    if agreement_capacity_error != chart.TooLarge { ret chart.Invalid }
    let (_, _, invalid_critical_error) = chart.bland_altman(left[..], right[..], 0.0f64, bounds, means[..], differences[..], dots[..], guides[..])
    if invalid_critical_error != chart.Invalid { ret chart.Invalid }

    let (forest_again, reference_again, again_error) = chart.forest_plot(estimates[..], lows[..], highs[..], 1.0, linear, bounds, points[..], intervals[..], reference[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &forest_again, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &reference_again, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &scatter, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &limits, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 14usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 320.0, 180.0, "Forest and Bland Altman", "Statistical diagrams")
    try chart_svg.append(&writer, &forest_again, blue)
    try chart_svg.append(&writer, &reference_again, blue)
    try chart_svg.append(&writer, &scatter, blue)
    try chart_svg.append(&writer, &limits, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart agreement forest ok\n")
    ret ok
}
