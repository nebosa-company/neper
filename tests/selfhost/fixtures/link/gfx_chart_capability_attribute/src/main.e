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
    let defective = [4]usize{ 5usize, 7usize, 4usize, 8usize }
    let inspected = [4]usize{ 100usize, 80usize, 120usize, 100usize }
    var controls: [4]stat.AttributeControlPoint = zero
    var cumulative_rates: [4]f64 = zero
    let (summary, summary_error) = stat.binomial_capability(defective[..], inspected[..], 0.07f64, 0.95f64, controls[..], cumulative_rates[..])
    if summary_error != ok || summary.defective != 24u64 || summary.inspected != 400u64 || !near(summary.fraction, 0.06f64, 0.000001f64) || !near(summary.ppm, 60000.0f64, 0.001f64) { ret chart.Invalid }
    if !near(summary.confidence.low, 0.0406479701f64, 0.00001f64) || !near(summary.confidence.high, 0.0877228489f64, 0.00001f64) || !summary.meets_target || summary.upper_bound_meets_target || summary.beyond_limits != 0usize { ret chart.Invalid }
    if !near(cumulative_rates[0usize], 0.05f64, 0.000001f64) || !near(cumulative_rates[1usize], 12.0f64 / 180.0f64, 0.000001f64) || !near(cumulative_rates[2usize], 16.0f64 / 300.0f64, 0.000001f64) || !near(cumulative_rates[3usize], 0.06f64, 0.000001f64) { ret chart.Invalid }
    if !near(controls[1usize].upper, 0.06f64 + 3.0f64 * 0.0265518361f64, 0.00001f64) { ret chart.Invalid }
    var p_points: [4]chart.Coord = zero
    var p_lines: [3]chart.Segment = zero
    var cumulative_points: [4]chart.Coord = zero
    var cumulative_lines: [3]chart.Segment = zero
    var upper: [3]chart.Segment = zero
    var lower: [3]chart.Segment = zero
    var guides: [5]chart.Segment = zero
    var signals: [4]chart.Coord = zero
    var work = chart.BinomialCapabilityStorage {
        controls: controls[..], cumulative_rates: cumulative_rates[..], p_points: p_points[..], p_lines: p_lines[..],
        cumulative_points: cumulative_points[..], cumulative_lines: cumulative_lines[..],
        upper_limit: upper[..], lower_limit: lower[..], guides: guides[..], signal_points: signals[..],
    }
    let panels = [2]geometry.Rect{ geometry.rect(10.0, 10.0, 260.0, 80.0), geometry.rect(10.0, 110.0, 260.0, 80.0) }
    let (report, report_error) = chart.binomial_capability(defective[..], inspected[..], 0.07f64, 0.95f64, panels[..], &work)
    if report_error != ok || report.p_chart.kind != .PointLine || report.cumulative.kind != .PointLine || report.upper_limit.segments.len != 3usize || report.lower_limit.segments.len != 3usize || report.guides.segments.len != 5usize || report.signals.coords.len != 0usize { ret chart.Invalid }
    if !near(f64(guides[0usize].from.y), f64(guides[0usize].to.y), 0.0001f64) || !near(f64(guides[4usize].from.y), f64(guides[4usize].to.y), 0.0001f64) || near(f64(upper[0usize].from.y), f64(upper[0usize].to.y), 0.0001f64) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, build_error) = scene.builder(a, 128usize)
    if build_error != ok { ret build_error }
    var builder = made
    try chart_scene.append(a, &builder, &report.p_chart, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.cumulative, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.upper_limit, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.lower_limit, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0, 210.0, "Binomial capability", "P chart and cumulative defective rate")
    try chart_svg.append(&writer, &report.p_chart, blue)
    try chart_svg.append(&writer, &report.cumulative, blue)
    try chart_svg.append(&writer, &report.upper_limit, blue)
    try chart_svg.append(&writer, &report.lower_limit, blue)
    try chart_svg.append(&writer, &report.guides, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "<line") { ret chart.Invalid }
    let signal_data = [4]usize{ 5usize, 7usize, 4usize, 25usize }
    let (flagged, flagged_error) = chart.binomial_capability(signal_data[..], inspected[..], 0.07f64, 0.95f64, panels[..], &work)
    if flagged_error != ok || flagged.summary.beyond_limits != 1usize || flagged.signals.coords.len != 1usize || flagged.summary.meets_target { ret chart.Invalid }
    let impossible = [4]usize{ 5usize, 81usize, 4usize, 8usize }
    let (_, bad_count) = stat.binomial_capability(impossible[..], inspected[..], 0.07f64, 0.95f64, controls[..], cumulative_rates[..])
    let (_, bad_target) = chart.binomial_capability(defective[..], inspected[..], 1.1f64, 0.95f64, panels[..], &work)
    let (_, bad_bounds) = chart.binomial_capability(defective[..], inspected[..], 0.07f64, 0.95f64, panels[..1usize], &work)
    var short = work
    short.p_points = p_points[..3usize]
    let (_, short_error) = chart.binomial_capability(defective[..], inspected[..], 0.07f64, 0.95f64, panels[..], &short)
    if bad_count != stat.Invalid || bad_target != chart.Invalid || bad_bounds != chart.Invalid || short_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart capability attribute ok\n")
    ret ok
}
