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
    let standard = [4]usize{ 0usize, 0usize, 1usize, 1usize }
    let ratings = [16]usize{
        0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 1usize, 1usize,
        0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 1usize, 1usize,
    }
    var within_rates: [2]stat.AttributeAgreementRate = zero
    var standard_rates: [2]stat.AttributeAgreementRate = zero
    let (summary, summary_error) = stat.attribute_agreement(standard[..], ratings[..], 2usize, 2usize, 2usize, 0.95f64, within_rates[..], standard_rates[..])
    if summary_error != ok || summary.items != 4usize || summary.appraisers != 2usize || summary.trials != 2usize || summary.between_matched != 2usize || summary.all_vs_standard_matched != 2usize { ret chart.Invalid }
    if within_rates[0usize].matched != 3usize || within_rates[1usize].matched != 4usize || standard_rates[0usize].matched != 3usize || standard_rates[1usize].matched != 3usize { ret chart.Invalid }
    if !near(summary.pooled_rating_fraction, 0.8125f64, 0.000001f64) || !summary.kappa_defined || !near(summary.pooled_rating_kappa, 0.625f64, 0.000001f64) { ret chart.Invalid }
    if !(within_rates[0usize].confidence.low > 0.19f64 && within_rates[0usize].confidence.low < 0.20f64) || !(within_rates[0usize].confidence.high > 0.99f64 && within_rates[0usize].confidence.high < 1.0f64) { ret chart.Invalid }
    var within_points: [2]chart.Coord = zero
    var standard_points: [2]chart.Coord = zero
    var within_intervals: [2]chart.Segment = zero
    var standard_intervals: [2]chart.Segment = zero
    var work = chart.AttributeAgreementStorage {
        within_rates: within_rates[..], standard_rates: standard_rates[..],
        within_points: within_points[..], standard_points: standard_points[..],
        within_intervals: within_intervals[..], standard_intervals: standard_intervals[..],
    }
    let panels = [2]geometry.Rect{ geometry.rect(10.0, 10.0, 260.0, 80.0), geometry.rect(10.0, 110.0, 260.0, 80.0) }
    let (report, report_error) = chart.attribute_agreement(standard[..], ratings[..], 2usize, 2usize, 2usize, 0.95f64, panels[..], &work)
    if report_error != ok || report.within.coords.len != 2usize || report.versus_standard.coords.len != 2usize || report.within_intervals.segments.len != 2usize || report.standard_intervals.segments.len != 2usize { ret chart.Invalid }
    if !(within_intervals[0usize].from.y > within_intervals[0usize].to.y) || !near(f64(within_points[0usize].y), 30.0f64, 0.0001f64) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, build_error) = scene.builder(a, 128usize)
    if build_error != ok { ret build_error }
    var builder = made
    try chart_scene.append(a, &builder, &report.within_intervals, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.standard_intervals, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.within, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.versus_standard, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0f32, 210.0f32, "Attribute agreement", "Within and against standard")
    try chart_svg.append(&writer, &report.within_intervals, blue)
    try chart_svg.append(&writer, &report.standard_intervals, blue)
    try chart_svg.append(&writer, &report.within, blue)
    try chart_svg.append(&writer, &report.versus_standard, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") { ret chart.Invalid }
    let bad_standard = [4]usize{ 0usize, 0usize, 2usize, 1usize }
    let (_, category_error) = stat.attribute_agreement(bad_standard[..], ratings[..], 2usize, 2usize, 2usize, 0.95f64, within_rates[..], standard_rates[..])
    let (_, bad_trials) = chart.attribute_agreement(standard[..], ratings[..], 2usize, 1usize, 2usize, 0.95f64, panels[..], &work)
    var short = work
    short.within_points = within_points[..1usize]
    let (_, short_error) = chart.attribute_agreement(standard[..], ratings[..], 2usize, 2usize, 2usize, 0.95f64, panels[..], &short)
    let uniform_standard = [4]usize{ 0usize, 0usize, 0usize, 0usize }
    let uniform_ratings = [16]usize{ 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 0usize }
    let (degenerate, degenerate_error) = stat.attribute_agreement(uniform_standard[..], uniform_ratings[..], 2usize, 2usize, 2usize, 0.95f64, within_rates[..], standard_rates[..])
    if category_error != stat.Invalid || bad_trials != chart.Invalid || short_error != chart.TooLarge || degenerate_error != ok || degenerate.kappa_defined { ret chart.Invalid }
    try io.print("gfx chart attribute agreement ok\n")
    ret ok
}
