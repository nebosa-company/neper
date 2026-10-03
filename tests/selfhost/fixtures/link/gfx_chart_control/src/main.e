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

fn near(a: f64, b: f64) -> bool {
    let d = a - b
    ret d > -0.001f64 && d < 0.001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [10]f64{ 49.6, 47.6, 49.9, 51.3, 47.8, 51.2, 52.6, 52.4, 53.6, 52.1 }
    var moving: [9]f64 = zero
    let (individuals, mr, imr_error) = stat.imr_limits(values[..], moving[..])
    if imr_error != ok || !near(individuals.center, 50.81) || !near(mr.center, 1.8777778) || !near(individuals.upper, 55.80409) || !near(individuals.lower, 45.81591) || !near(mr.upper, 6.1346) || !near(moving[0usize], 2.0) || !near(moving[8usize], 1.5) { ret stat.Invalid }
    let (_, _, short_error) = stat.imr_limits(values[..], moving[..8usize])
    if short_error != stat.TooSmall { ret stat.Invalid }
    let short_values = [1]f64{ 1.0 }
    let (_, _, too_few_error) = stat.imr_limits(short_values[..], moving[..])
    if too_few_error != stat.Invalid { ret stat.Invalid }
    let bad_values = [2]f64{ 1.0, 0.0 / 0.0 }
    let (_, _, bad_error) = stat.imr_limits(bad_values[..], moving[..])
    if bad_error != stat.Invalid { ret stat.Invalid }

    let subgroups = [15]f64{ 10.0, 11.0, 9.0, 10.0, 10.0, 11.0, 13.0, 10.0, 11.0, 10.0, 9.0, 10.0, 8.0, 9.0, 9.0 }
    var means: [3]f64 = zero
    var ranges: [3]f64 = zero
    let (xbar, range, subgroup_error) = stat.xbar_r_limits(subgroups[..], 5usize, means[..], ranges[..])
    if subgroup_error != ok || !near(means[0usize], 10.0) || !near(means[1usize], 11.0) || !near(means[2usize], 9.0) || !near(ranges[1usize], 3.0) || !near(xbar.center, 10.0) || !near(xbar.upper, 11.346333) || !near(xbar.lower, 8.653667) || !near(range.center, 7.0f64 / 3.0f64) || !near(range.upper, 4.935) || !near(range.lower, 0.0) { ret stat.Invalid }
    let (_, _, subgroup_short_error) = stat.xbar_r_limits(subgroups[..], 5usize, means[..2usize], ranges[..])
    if subgroup_short_error != stat.TooSmall { ret stat.Invalid }
    let (_, _, size_error) = stat.xbar_r_limits(subgroups[..], 11usize, means[..], ranges[..])
    if size_error != stat.Invalid { ret stat.Invalid }
    let seven = [14]f64{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0 }
    let (_, seven_range, seven_error) = stat.xbar_r_limits(seven[..], 7usize, means[..], ranges[..])
    if seven_error != ok || !near(seven_range.lower, 0.076) || !near(seven_range.upper, 1.924) { ret stat.Invalid }

    let x = [3]f32{ 0.0, 0.5, 1.0 }
    let y = [3]f32{ 10.0, 11.0, 9.0 }
    var plot = chart.spec(.PointLine, geometry.rect(30.0, 20.0, 200.0, 100.0), x[..], y[..])
    var points: [3]chart.Coord = zero
    var segments: [2]chart.Segment = zero
    let x_limits = [2]f32{ 0.0, 1.0 }
    let y_limits = [2]f32{ 8.0, 12.0 }
    let (marks, layout_error) = chart.layout_with_limits(&plot, points[..], segments[..], zero, x_limits[..], y_limits[..])
    if layout_error != ok || marks.kind != .PointLine || marks.coords.len != 3usize || marks.segments.len != 2usize { ret chart.Invalid }
    var rule_segments = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: 30.0, y: 70.0 }, to: chart.Coord { x: 230.0, y: 70.0 } } }
    let rule = chart.Layout { kind: .Rug, coords: zero, segments: rule_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 8.0, y_max: 12.0 }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &rule, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 260.0, 160.0, "X-bar control", "Subgroup means and limits")
    try chart_svg.append(&writer, &rule, blue)
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "<line") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    try io.print("gfx chart control ok\n")
    ret ok
}
