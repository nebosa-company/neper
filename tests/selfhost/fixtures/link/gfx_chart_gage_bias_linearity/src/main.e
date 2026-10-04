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

fn near(a: f64, b: f64, tolerance: f64) -> bool { ret a - b < tolerance && b - a < tolerance }

fn main(a: *mem.Arena, args: []str) -> err {
    let references = [5]f64{ 1.0f64, 2.0f64, 3.0f64, 4.0f64, 5.0f64 }
    let measured = [10]f64{ 0.85f64, 0.95f64, 1.95f64, 2.05f64, 3.05f64, 3.15f64, 4.15f64, 4.25f64, 5.25f64, 5.35f64 }
    var biases: [10]f64 = zero
    var means: [5]f64 = zero
    var fitted: [5]f64 = zero
    var lower: [5]f64 = zero
    var upper: [5]f64 = zero
    let (summary, summary_error) = stat.gage_linearity(references[..], measured[..], 2usize, 2.306f64, biases[..], means[..], fitted[..], lower[..], upper[..])
    if summary_error != ok || summary.reference_count != 5usize || summary.repeats != 2usize { ret chart.Invalid }
    if !near(summary.average_bias, 0.1f64, 0.000001f64) || !near(summary.intercept, -0.2f64, 0.000001f64) || !near(summary.slope, 0.1f64, 0.000001f64) || !near(summary.linearity, 0.4f64, 0.000001f64) { ret chart.Invalid }
    if !near(summary.residual_sigma, 0.0559016994f64, 0.000001f64) || !near(summary.slope_standard_error, 0.0125f64, 0.000001f64) || !(summary.slope_p < 0.001f64) { ret chart.Invalid }
    if !near(means[0usize], -0.1f64, 0.000001f64) || !near(fitted[4usize], 0.3f64, 0.000001f64) || !near(lower[0usize], -0.1706065418f64, 0.00001f64) || !near(upper[0usize], -0.0293934582f64, 0.00001f64) { ret chart.Invalid }
    var raw_points: [10]chart.Coord = zero
    var mean_points: [5]chart.Coord = zero
    var fit_segments: [4]chart.Segment = zero
    var ci_segments: [5]chart.Segment = zero
    var zero_guide: [1]chart.Segment = zero
    var work = chart.GageLinearityStorage {
        biases: biases[..], mean_biases: means[..], fitted_biases: fitted[..], ci_lower: lower[..], ci_upper: upper[..],
        raw_points: raw_points[..], mean_points: mean_points[..], fit_segments: fit_segments[..], ci_segments: ci_segments[..], zero_guide: zero_guide[..],
    }
    let plot = geometry.rect(10.0, 10.0, 260.0, 160.0)
    let (report, report_error) = chart.gage_linearity(references[..], measured[..], 2usize, 2.306f64, plot, &work)
    if report_error != ok || report.observations.coords.len != 10usize || report.means.coords.len != 5usize || report.fit.segments.len != 4usize || report.confidence.segments.len != 5usize || report.zero_line.segments.len != 1usize { ret chart.Invalid }
    if !near(f64(zero_guide[0usize].from.y), f64(zero_guide[0usize].to.y), 0.00001f64) || !(ci_segments[0usize].from.y > ci_segments[0usize].to.y) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, build_error) = scene.builder(a, 128usize)
    if build_error != ok { ret build_error }
    var builder = made
    try chart_scene.append(a, &builder, &report.observations, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.means, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.fit, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.confidence, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.zero_line, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0f32, 180.0f32, "Gage bias and linearity", "Bias versus reference with fitted mean confidence limits")
    try chart_svg.append(&writer, &report.observations, blue)
    try chart_svg.append(&writer, &report.means, blue)
    try chart_svg.append(&writer, &report.fit, blue)
    try chart_svg.append(&writer, &report.confidence, blue)
    try chart_svg.append(&writer, &report.zero_line, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "<line") { ret chart.Invalid }
    let unordered = [5]f64{ 1.0f64, 2.0f64, 2.0f64, 4.0f64, 5.0f64 }
    let (_, bad_reference) = stat.gage_linearity(unordered[..], measured[..], 2usize, 2.306f64, biases[..], means[..], fitted[..], lower[..], upper[..])
    let (_, bad_critical) = chart.gage_linearity(references[..], measured[..], 2usize, 0.0f64, plot, &work)
    let (_, bad_repeats) = chart.gage_linearity(references[..], measured[..], 1usize, 2.306f64, plot, &work)
    var short = work
    short.raw_points = raw_points[..9usize]
    let (_, short_error) = chart.gage_linearity(references[..], measured[..], 2usize, 2.306f64, plot, &short)
    if bad_reference != stat.Invalid || bad_critical != chart.Invalid || bad_repeats != chart.Invalid || short_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart gage bias linearity ok\n")
    ret ok
}
