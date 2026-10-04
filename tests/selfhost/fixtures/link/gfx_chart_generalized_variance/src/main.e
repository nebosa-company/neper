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
    ret difference > -0.003f64 && difference < 0.003f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let phase_one = [20]f64{ 1.0f64, 0.0f64, -1.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64, 0.0f64, 0.0f64 }
    let phase_two = [10]f64{ 3.0f64, 0.0f64, -3.0f64, 0.0f64, 0.0f64, 3.0f64, 0.0f64, -3.0f64, 0.0f64, 0.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var covariance: [9]f64 = zero
    var pooled: [9]f64 = zero
    var factor: [9]f64 = zero
    var determinants: [4]f64 = zero
    var points: [4]chart.Coord = zero
    var segments: [3]chart.Segment = zero
    var signals: [4]chart.Coord = zero
    var upper: [1]chart.Segment = zero
    var lower: [1]chart.Segment = zero
    var center: [1]chart.Segment = zero
    var storage = chart.GeneralizedVarianceStorage { covariance: covariance[..], pooled: pooled[..], factor: factor[..], determinants: determinants[..], points: points[..], segments: segments[..], signals: signals[..], upper: upper[..], lower: lower[..], center: center[..] }
    let (map, result) = chart.generalized_variance(phase_one[..], phase_two[..], 5usize, 2usize, 0.0027f64, false, bounds, &storage)
    if result != ok || map.phase_one_count != 2usize || map.phase_two_count != 1usize || map.trace.coords.len != 3usize || map.trace.segments.len != 2usize || map.signals.coords.len != 1usize { ret chart.Invalid }
    if !near(map.determinants[0usize], 0.25f64) || !near(map.determinants[1usize], 0.25f64) || !near(map.determinants[2usize], 20.25f64) || !near(map.pooled_covariance[0usize], 0.5f64) || !near(map.pooled_covariance[3usize], 0.5f64) { ret chart.Invalid }
    if !near(map.b1, 0.75f64) || !near(map.b2, 0.84375f64) || !near(map.b3, 0.875f64) || !near(map.center_value, 0.2142857f64) || !(map.upper_limit > 0.94f64 && map.upper_limit < 0.95f64) || !near(map.lower_limit, 0.0f64) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let red = paint.rgba(0.8, 0.2, 0.2, 1.0)
    let gray = paint.rgba(0.6, 0.7, 0.75, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.upper, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.center, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.trace, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.signals, paint.Brush { Solid: red })
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "Generalized variance", "Moment-normal upper control limit")
    try chart_svg.append(&writer, &map.upper, red)
    try chart_svg.append(&writer, &map.center, gray)
    try chart_svg.append(&writer, &map.trace, blue)
    try chart_svg.append(&writer, &map.signals, red)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (two_sided, two_sided_error) = chart.generalized_variance(phase_one[..], phase_two[..0usize], 5usize, 2usize, 0.1f64, true, bounds, &storage)
    if two_sided_error != ok || two_sided.phase_two_count != 0usize || two_sided.lower_limit < 0.0f64 || two_sided.upper_limit <= two_sided.center_value { ret chart.Invalid }
    let singular_group = [10]f64{ 0.0f64, 0.0f64, 1.0f64, 1.0f64, 2.0f64, 2.0f64, 3.0f64, 3.0f64, 4.0f64, 4.0f64 }
    let (flat, flat_error) = chart.generalized_variance(phase_one[..], singular_group[..], 5usize, 2usize, 0.0027f64, false, bounds, &storage)
    if flat_error != ok || !near(flat.determinants[2usize], 0.0f64) { ret chart.Invalid }
    let three = [24]f64{ 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let (three_map, three_error) = chart.generalized_variance(three[..], three[..0usize], 4usize, 3usize, 0.0027f64, false, bounds, &storage)
    if three_error != ok || !near(three_map.b1, 2.0f64 / 9.0f64) || !(three_map.determinants[0usize] > 0.0f64) { ret chart.Invalid }
    let (_, bad_size) = chart.generalized_variance(phase_one[..], phase_two[..], 2usize, 2usize, 0.0027f64, false, bounds, &storage)
    let (_, bad_shape) = chart.generalized_variance(phase_one[..19usize], phase_two[..], 5usize, 2usize, 0.0027f64, false, bounds, &storage)
    let (_, bad_alpha) = chart.generalized_variance(phase_one[..], phase_two[..], 5usize, 2usize, 0.0f64, false, bounds, &storage)
    var short = chart.GeneralizedVarianceStorage { covariance: covariance[..], pooled: pooled[..], factor: factor[..], determinants: determinants[..2usize], points: points[..], segments: segments[..], signals: signals[..], upper: upper[..], lower: lower[..], center: center[..] }
    let (_, short_error) = chart.generalized_variance(phase_one[..], phase_two[..], 5usize, 2usize, 0.0027f64, false, bounds, &short)
    if bad_size != chart.Invalid || bad_shape != chart.Invalid || bad_alpha != chart.Invalid || short_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart generalized variance ok\n")
    ret ok
}
