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
    let values = [6]f64{ 1.0f64, 2.0f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64 }
    var batch_means: [3]f64 = zero
    var batch_spreads: [3]f64 = zero
    let (summary, summary_error) = stat.batch_capability(values[..], 2usize, 0.0f64, 7.0f64, batch_means[..], batch_spreads[..])
    if summary_error != ok || summary.batches != 3usize || summary.batch_size != 2usize || !near(summary.mean, 3.5f64, 0.000001f64) { ret chart.Invalid }
    if !near(summary.within_sigma, 0.7071067812f64, 0.000001f64) || !near(summary.between_sigma, 1.9364916731f64, 0.000001f64) || !near(summary.between_within_sigma, 2.0615528128f64, 0.000001f64) || !near(summary.overall_sigma, 1.8708286934f64, 0.000001f64) { ret chart.Invalid }
    if !near(summary.cp, 0.5659164584f64, 0.000001f64) || !near(summary.cpk, summary.cp, 0.000001f64) || !near(summary.pp, 0.6236095645f64, 0.000001f64) || !near(summary.ppk, summary.pp, 0.000001f64) || summary.observed_ppm != 0.0f64 { ret chart.Invalid }
    if !near(batch_means[0usize], 1.5f64, 0.000001f64) || !near(batch_means[2usize], 5.5f64, 0.000001f64) || !near(batch_spreads[1usize], 0.7071067812f64, 0.000001f64) { ret chart.Invalid }
    var mean_points: [3]chart.Coord = zero
    var mean_lines: [2]chart.Segment = zero
    var spread_bars: [3]geometry.Rect = zero
    var guides: [3]chart.Segment = zero
    var work = chart.BatchCapabilityStorage { batch_means: batch_means[..], batch_spreads: batch_spreads[..], mean_points: mean_points[..], mean_lines: mean_lines[..], spread_bars: spread_bars[..], guides: guides[..] }
    let panels = [2]geometry.Rect{ geometry.rect(10.0, 10.0, 260.0, 80.0), geometry.rect(10.0, 110.0, 260.0, 80.0) }
    let (report, report_error) = chart.batch_capability(values[..], 2usize, 0.0f64, 7.0f64, panels[..], &work)
    if report_error != ok || report.means.kind != .PointLine || report.spreads.kind != .Bar || report.guides.segments.len != 3usize || report.spreads.bars.len != 3usize || !(report.spreads.bars[0usize].height > 0.0f32) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, build_error) = scene.builder(a, 128usize)
    if build_error != ok { ret build_error }
    var builder = made
    try chart_scene.append(a, &builder, &report.means, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.spreads, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0f32, 210.0f32, "Batch capability", "Balanced subgroup means and spreads")
    try chart_svg.append(&writer, &report.means, blue)
    try chart_svg.append(&writer, &report.spreads, blue)
    try chart_svg.append(&writer, &report.guides, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "<line") { ret chart.Invalid }
    let (_, bad_size) = stat.batch_capability(values[..], 4usize, 0.0f64, 7.0f64, batch_means[..], batch_spreads[..])
    let (_, bad_spec) = chart.batch_capability(values[..], 2usize, 7.0f64, 0.0f64, panels[..], &work)
    let (_, bad_panels) = chart.batch_capability(values[..], 2usize, 0.0f64, 7.0f64, panels[..1usize], &work)
    var short = work
    short.mean_points = mean_points[..2usize]
    let (_, short_error) = chart.batch_capability(values[..], 2usize, 0.0f64, 7.0f64, panels[..], &short)
    let flat = [6]f64{ 3.0f64, 3.0f64, 3.0f64, 3.0f64, 3.0f64, 3.0f64 }
    let (_, flat_error) = stat.batch_capability(flat[..], 2usize, 0.0f64, 7.0f64, batch_means[..], batch_spreads[..])
    if bad_size != stat.Invalid || bad_spec != chart.Invalid || bad_panels != chart.Invalid || short_error != chart.TooLarge || flat_error != stat.Invalid { ret chart.Invalid }
    let no_between = [6]f64{ 1.0f64, 3.0f64, 1.0f64, 3.0f64, 1.0f64, 3.0f64 }
    let (pooled, pooled_error) = stat.batch_capability(no_between[..], 2usize, 0.0f64, 4.0f64, batch_means[..], batch_spreads[..])
    if pooled_error != ok || pooled.between_sigma != 0.0f64 || !near(pooled.within_sigma, pooled.between_within_sigma, 0.000001f64) { ret chart.Invalid }
    try io.print("gfx chart capability batch ok\n")
    ret ok
}
