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
    let values = [6]f64{ 1.0f64, 2.0f64, 4.0f64, 8.0f64, 16.0f64, 32.0f64 }
    let (summary, summary_error) = stat.lognormal_capability(values[..], 2.0f64, 16.0f64)
    if summary_error != ok || !near(summary.log_mean, 1.7328679514f64, 0.00001f64) || !near(summary.log_sigma, 1.1837741721f64, 0.00001f64) || !near(summary.median, 5.6568542495f64, 0.00001f64) { ret chart.Invalid }
    if !near(summary.pp, 0.2927700219f64, 0.00001f64) || !near(summary.ppk, summary.pp, 0.00001f64) || !near(summary.observed_below_ppm, 166666.6666667f64, 0.001f64) || !near(summary.observed_above_ppm, 166666.6666667f64, 0.001f64) { ret chart.Invalid }
    if !near(summary.expected_below_ppm, 189887.73742f64, 0.1f64) || !near(summary.expected_above_ppm, 189887.73742f64, 0.1f64) { ret chart.Invalid }
    var counts: [8]u64 = zero
    var bars: [8]geometry.Rect = zero
    var curve: [63]chart.Segment = zero
    var guides: [3]chart.Segment = zero
    var work = chart.LognormalCapabilityStorage { counts: counts[..], bars: bars[..], fit_curve: curve[..], guides: guides[..] }
    let bounds = geometry.rect(12.0, 20.0, 250.0, 150.0)
    let (report, report_error) = chart.lognormal_capability(values[..], 2.0f64, 16.0f64, bounds, &work)
    if report_error != ok || report.histogram.kind != .Histogram || report.fit_curve.kind != .Line || report.guides.kind != .Rug || report.fit_curve.segments.len != 63usize || report.guides.segments.len != 3usize { ret chart.Invalid }
    var total = 0u64
    var i = 0usize
    while i < counts.len {
        total += counts[i]
        i += 1usize
    }
    if total != 6u64 || report.histogram.x_min > 1.0 || report.histogram.x_max < 32.0 || guides[0usize].from.x >= guides[1usize].from.x || guides[1usize].from.x >= guides[2usize].from.x { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, build_error) = scene.builder(a, 128usize)
    if build_error != ok { ret build_error }
    var builder = made
    try chart_scene.append(a, &builder, &report.histogram, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.fit_curve, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0, 210.0, "Lognormal capability", "Fitted nonnormal distribution and specifications")
    try chart_svg.append(&writer, &report.histogram, blue)
    try chart_svg.append(&writer, &report.fit_curve, blue)
    try chart_svg.append(&writer, &report.guides, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "<line") { ret chart.Invalid }
    let bad_values = [6]f64{ 1.0f64, 2.0f64, 0.0f64, 8.0f64, 16.0f64, 32.0f64 }
    let flat = [6]f64{ 2.0f64, 2.0f64, 2.0f64, 2.0f64, 2.0f64, 2.0f64 }
    let (_, zero_error) = stat.lognormal_capability(bad_values[..], 2.0f64, 16.0f64)
    let (_, flat_error) = stat.lognormal_capability(flat[..], 1.0f64, 3.0f64)
    let (_, spec_error) = chart.lognormal_capability(values[..], 16.0f64, 2.0f64, bounds, &work)
    let (_, bounds_error) = chart.lognormal_capability(values[..], 2.0f64, 16.0f64, geometry.rect(0.0, 0.0, 0.0, 100.0), &work)
    var short = work
    short.fit_curve = curve[..62usize]
    let (_, storage_error) = chart.lognormal_capability(values[..], 2.0f64, 16.0f64, bounds, &short)
    if zero_error != stat.Invalid || flat_error != stat.Invalid || spec_error != chart.Invalid || bounds_error != chart.Invalid || storage_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart capability nonnormal ok\n")
    ret ok
}
