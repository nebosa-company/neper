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
    let historical = [16]f64{ 1.0f64, 1.0f64, -1.0f64, -1.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64, 1.0f64, 1.0f64, -1.0f64, -1.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64 }
    let monitored = [8]f64{ 0.0f64, 0.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 4.0f64, 4.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var means: [2]f64 = zero
    var covariance: [4]f64 = zero
    var factor: [4]f64 = zero
    var state: [2]f64 = zero
    var residual: [2]f64 = zero
    var smoothed: [16]f64 = zero
    var scores: [8]f64 = zero
    var points: [8]chart.Coord = zero
    var segments: [7]chart.Segment = zero
    var signals: [8]chart.Coord = zero
    var upper: [1]chart.Segment = zero
    var storage = chart.MewmaStorage { means: means[..], covariance: covariance[..], factor: factor[..], state: state[..], residual: residual[..], smoothed: smoothed[..], scores: scores[..], points: points[..], segments: segments[..], signals: signals[..], upper: upper[..] }
    let (map, result) = chart.mewma(monitored[..], 2usize, historical[..], 0.5f64, 10.0f64, bounds, &storage)
    if result != ok || !map.phase_two || map.historical_count != 8usize || map.trace.coords.len != 4usize || map.trace.segments.len != 3usize || map.signals.coords.len != 1usize || map.upper.segments.len != 1usize { ret chart.Invalid }
    if !near(map.means[0usize], 0.0f64) || !near(map.means[1usize], 0.0f64) || !near(map.covariance[0usize], 4.0f64 / 7.0f64) || !near(map.covariance[1usize], 4.0f64 / 7.0f64) { ret chart.Invalid }
    if !near(map.smoothed[2usize], 0.5f64) || !near(map.smoothed[4usize], 0.75f64) || !near(map.smoothed[6usize], 2.375f64) || !near(map.scores[0usize], 0.0f64) || !near(map.scores[1usize], 1.4f64) || !near(map.scores[2usize], 3.0f64) || !(map.scores[3usize] > 29.0f64 && map.scores[3usize] < 30.0f64) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let red = paint.rgba(0.8, 0.2, 0.2, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.trace, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.upper, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.signals, paint.Brush { Solid: red })
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (writer_state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = writer_state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "MEWMA", "Finite-time multivariate EWMA statistic")
    try chart_svg.append(&writer, &map.trace, blue)
    try chart_svg.append(&writer, &map.upper, red)
    try chart_svg.append(&writer, &map.signals, red)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (unit, unit_error) = chart.mewma(monitored[..], 2usize, historical[..], 1.0f64, 10.0f64, bounds, &storage)
    if unit_error != ok || !near(unit.scores[1usize], 1.75f64) || !near(unit.scores[2usize], 1.75f64) || !near(unit.scores[3usize], 28.0f64) { ret chart.Invalid }
    let (phase_one, phase_one_error) = chart.mewma(historical[..], 2usize, historical[..0usize], 0.5f64, 100.0f64, bounds, &storage)
    if phase_one_error != ok || phase_one.phase_two || phase_one.trace.coords.len != 8usize || phase_one.signals.coords.len != 0usize { ret chart.Invalid }
    let three = [24]f64{ 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64, 1.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let three_values = [6]f64{ 0.0f64, 0.0f64, 0.0f64, 2.0f64, 1.0f64, 0.0f64 }
    var three_means: [3]f64 = zero
    var three_covariance: [9]f64 = zero
    var three_factor: [9]f64 = zero
    var three_state: [3]f64 = zero
    var three_residual: [3]f64 = zero
    var three_smoothed: [6]f64 = zero
    var three_scores: [2]f64 = zero
    var three_points: [2]chart.Coord = zero
    var three_segments: [1]chart.Segment = zero
    var three_signals: [2]chart.Coord = zero
    var three_upper: [1]chart.Segment = zero
    var three_storage = chart.MewmaStorage { means: three_means[..], covariance: three_covariance[..], factor: three_factor[..], state: three_state[..], residual: three_residual[..], smoothed: three_smoothed[..], scores: three_scores[..], points: three_points[..], segments: three_segments[..], signals: three_signals[..], upper: three_upper[..] }
    let (three_map, three_error) = chart.mewma(three_values[..], 3usize, three[..], 0.25f64, 100.0f64, bounds, &three_storage)
    if three_error != ok || three_map.trace.coords.len != 2usize || !(three_map.scores[0usize] > 0.0f64) || !(three_map.scores[1usize] > three_map.scores[0usize]) { ret chart.Invalid }
    let singular = [12]f64{ 1.0f64, 2.0f64, 2.0f64, 4.0f64, 3.0f64, 6.0f64, 4.0f64, 8.0f64, 5.0f64, 10.0f64, 6.0f64, 12.0f64 }
    let (_, singular_error) = chart.mewma(monitored[..], 2usize, singular[..], 0.5f64, 10.0f64, bounds, &storage)
    let (_, bad_lambda) = chart.mewma(monitored[..], 2usize, historical[..], 0.0f64, 10.0f64, bounds, &storage)
    let (_, bad_limit) = chart.mewma(monitored[..], 2usize, historical[..], 0.5f64, 0.0f64, bounds, &storage)
    let (_, bad_shape) = chart.mewma(monitored[..7usize], 2usize, historical[..], 0.5f64, 10.0f64, bounds, &storage)
    var short = chart.MewmaStorage { means: means[..], covariance: covariance[..], factor: factor[..], state: state[..], residual: residual[..], smoothed: smoothed[..7usize], scores: scores[..], points: points[..], segments: segments[..], signals: signals[..], upper: upper[..] }
    let (_, short_error) = chart.mewma(monitored[..], 2usize, historical[..], 0.5f64, 10.0f64, bounds, &short)
    if singular_error != chart.Invalid || bad_lambda != chart.Invalid || bad_limit != chart.Invalid || bad_shape != chart.Invalid || short_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart mewma ok\n")
    ret ok
}
