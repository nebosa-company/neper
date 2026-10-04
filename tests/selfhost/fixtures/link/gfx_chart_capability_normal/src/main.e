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

fn close(a: f64, b: f64) -> bool { ret a - b < 0.0001f64 && b - a < 0.0001f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [8]f64{ 9.0f64, 10.0f64, 11.0f64, 10.0f64, 10.0f64, 9.0f64, 11.0f64, 10.0f64 }
    var moving: [7]f64 = zero
    var counts: [6]u64 = zero
    var bars: [6]geometry.Rect = zero
    var within: [63]chart.Segment = zero
    var overall: [63]chart.Segment = zero
    var guides: [3]chart.Segment = zero
    var work = chart.NormalCapabilityStorage { moving: moving[..], counts: counts[..], bars: bars[..], within_curve: within[..], overall_curve: overall[..], guides: guides[..] }
    let bounds = geometry.rect(12.0, 20.0, 250.0, 150.0)
    let (report, report_error) = chart.normal_capability(values[..], 8.5f64, 11.5f64, bounds, &work)
    if report_error != ok || report.histogram.kind != .Histogram || report.within_curve.segments.len != 63usize || report.guides.segments.len != 3usize || !close(report.summary.mean, 10.0f64) { ret chart.Invalid }
    if report.performance.observed_below_ppm != 0.0f64 || report.performance.observed_above_ppm != 0.0f64 || !(report.performance.overall_below_ppm > 0.0f64) || !(report.performance.within_below_ppm > 0.0f64) { ret chart.Invalid }
    var total = 0u64
    var i = 0usize
    while i < counts.len {
        total += counts[i]
        i += 1usize
    }
    if total != 8u64 || report.histogram.x_min > 8.5 || report.histogram.x_max < 11.5 { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, build_error) = scene.builder(a, 256usize)
    if build_error != ok { ret build_error }
    var builder = made
    try chart_scene.append(a, &builder, &report.histogram, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.within_curve, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.overall_curve, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0, 210.0, "Normal capability", "Normal fit and specification limits")
    try chart_svg.append(&writer, &report.histogram, blue)
    try chart_svg.append(&writer, &report.within_curve, blue)
    try chart_svg.append(&writer, &report.overall_curve, blue)
    try chart_svg.append(&writer, &report.guides, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "<line") { ret chart.Invalid }
    let (_, bad_specs) = chart.normal_capability(values[..], 12.0f64, 8.0f64, bounds, &work)
    var short = work
    short.counts = counts[..1usize]
    let (_, short_error) = chart.normal_capability(values[..], 8.5f64, 11.5f64, bounds, &short)
    let flat = [8]f64{ 10.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64 }
    let (_, flat_error) = chart.normal_capability(flat[..], 8.5f64, 11.5f64, bounds, &work)
    if bad_specs != chart.Invalid || short_error != chart.TooLarge || flat_error != chart.Invalid { ret chart.Invalid }
    let (perf, perf_error) = stat.normal_capability_performance(values[..], 9.5f64, 10.5f64, report.summary)
    if perf_error != ok || !close(perf.observed_below_ppm, 250000.0f64) || !close(perf.observed_above_ppm, 250000.0f64) { ret chart.Invalid }
    try io.print("gfx chart capability normal ok\n")
    ret ok
}
