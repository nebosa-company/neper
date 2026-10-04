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
    // x and y are correlated: y = x + independent z.
    let historical = [16]f64{ 1.0f64, 1.0f64, -1.0f64, -1.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64, 1.0f64, 1.0f64, -1.0f64, -1.0f64, 0.0f64, 1.0f64, 0.0f64, -1.0f64 }
    let monitored = [8]f64{ 0.0f64, 0.0f64, 1.0f64, 1.0f64, 0.0f64, 2.0f64, 4.0f64, 4.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var means: [2]f64 = zero
    var covariance: [4]f64 = zero
    var factor: [4]f64 = zero
    var residual: [2]f64 = zero
    var scores: [8]f64 = zero
    var points: [8]chart.Coord = zero
    var segments: [7]chart.Segment = zero
    var signals: [8]chart.Coord = zero
    var upper: [1]chart.Segment = zero
    var storage = chart.HotellingStorage { means: means[..], covariance: covariance[..], factor: factor[..], residual: residual[..], scores: scores[..], points: points[..], segments: segments[..], signals: signals[..], upper: upper[..] }
    let (phase_two, phase_two_error) = chart.hotelling_t2_individuals(monitored[..], 2usize, historical[..], 0.05f64, bounds, &storage)
    if phase_two_error != ok || !phase_two.phase_two || phase_two.historical_count != 8usize || phase_two.trace.coords.len != 4usize || phase_two.trace.segments.len != 3usize || phase_two.signals.coords.len != 1usize || phase_two.upper.segments.len != 1usize { ret chart.Invalid }
    if !near(phase_two.means[0usize], 0.0f64) || !near(phase_two.means[1usize], 0.0f64) || !near(phase_two.covariance[0usize], 4.0f64 / 7.0f64) || !near(phase_two.covariance[1usize], 4.0f64 / 7.0f64) || !near(phase_two.covariance[3usize], 8.0f64 / 7.0f64) { ret chart.Invalid }
    if !near(phase_two.scores[0usize], 0.0f64) || !near(phase_two.scores[1usize], 1.75f64) || !near(phase_two.scores[2usize], 7.0f64) || !near(phase_two.scores[3usize], 28.0f64) || !(phase_two.upper_limit > 18.0f64 && phase_two.upper_limit < 20.0f64) { ret chart.Invalid }
    if !near(f64(phase_two.signals.coords[0usize].x), 220.0f64) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let red = paint.rgba(0.8, 0.2, 0.2, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &phase_two.trace, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &phase_two.upper, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &phase_two.signals, paint.Brush { Solid: red })
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "Hotelling T2", "Phase II individual observations")
    try chart_svg.append(&writer, &phase_two.trace, blue)
    try chart_svg.append(&writer, &phase_two.upper, red)
    try chart_svg.append(&writer, &phase_two.signals, red)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (phase_one, phase_one_error) = chart.hotelling_t2_individuals(historical[..], 2usize, historical[..0usize], 0.05f64, bounds, &storage)
    if phase_one_error != ok || phase_one.phase_two || phase_one.trace.coords.len != 8usize || phase_one.signals.coords.len != 0usize || !(phase_one.upper_limit > 4.0f64 && phase_one.upper_limit < 5.0f64) || !near(phase_one.scores[0usize], 1.75f64) { ret chart.Invalid }
    let singular = [12]f64{ 1.0f64, 2.0f64, 2.0f64, 4.0f64, 3.0f64, 6.0f64, 4.0f64, 8.0f64, 5.0f64, 10.0f64, 6.0f64, 12.0f64 }
    let (_, singular_error) = chart.hotelling_t2_individuals(monitored[..], 2usize, singular[..], 0.05f64, bounds, &storage)
    let (_, bad_shape) = chart.hotelling_t2_individuals(monitored[..7usize], 2usize, historical[..], 0.05f64, bounds, &storage)
    let (_, bad_alpha) = chart.hotelling_t2_individuals(monitored[..], 2usize, historical[..], 1.0f64, bounds, &storage)
    var short = chart.HotellingStorage { means: means[..], covariance: covariance[..], factor: factor[..], residual: residual[..], scores: scores[..], points: points[..], segments: segments[..], signals: signals[..0usize], upper: upper[..] }
    let (_, short_error) = chart.hotelling_t2_individuals(monitored[..], 2usize, historical[..], 0.05f64, bounds, &short)
    if singular_error != chart.Invalid || bad_shape != chart.Invalid || bad_alpha != chart.Invalid || short_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart hotelling t2 ok\n")
    ret ok
}
