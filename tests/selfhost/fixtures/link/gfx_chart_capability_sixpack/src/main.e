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
    let delta = a - b
    ret delta > -0.0001f64 && delta < 0.0001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [8]f64{ 9.0f64, 10.0f64, 11.0f64, 10.0f64, 10.0f64, 9.0f64, 11.0f64, 10.0f64 }
    let sorted = [8]f64{ 9.0f64, 9.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64, 11.0f64, 11.0f64 }
    let panels = [6]geometry.Rect{
        geometry.rect(10.0, 10.0, 120.0, 50.0), geometry.rect(150.0, 10.0, 120.0, 50.0),
        geometry.rect(10.0, 80.0, 120.0, 50.0), geometry.rect(150.0, 80.0, 120.0, 50.0),
        geometry.rect(10.0, 150.0, 120.0, 50.0), geometry.rect(150.0, 150.0, 120.0, 50.0),
    }
    var moving: [25]f64 = zero
    var individual_points: [26]chart.Coord = zero
    var individual_lines: [25]chart.Segment = zero
    var range_points: [25]chart.Coord = zero
    var range_lines: [24]chart.Segment = zero
    var recent_points: [25]chart.Coord = zero
    var counts: [4]u64 = zero
    var bars: [4]geometry.Rect = zero
    var within_curve: [31]chart.Segment = zero
    var overall_curve: [31]chart.Segment = zero
    var probability_points: [26]chart.Coord = zero
    var probability_reference: [1]chart.Segment = zero
    var interval_bars: [3]geometry.Rect = zero
    var guides: [11]chart.Segment = zero
    var work = chart.CapabilitySixpackStorage {
        moving: moving[..], individual_points: individual_points[..], individual_lines: individual_lines[..],
        range_points: range_points[..], range_lines: range_lines[..], recent_points: recent_points[..],
        histogram_counts: counts[..], histogram_bars: bars[..], within_curve: within_curve[..], overall_curve: overall_curve[..],
        probability_points: probability_points[..], probability_reference: probability_reference[..],
        interval_bars: interval_bars[..], guides: guides[..],
    }
    let (report, report_error) = chart.capability_sixpack(values[..], sorted[..], 8.0f64, 12.0f64, panels[..], &work)
    if report_error != ok { ret report_error }
    if !near(report.summary.mean, 10.0f64) || !near(report.summary.within_sigma, 1.0f64 / 1.128f64) || !near(report.summary.overall_sigma, 0.7559289460184545f64) { ret chart.Invalid }
    if !near(report.summary.cp, 4.0f64 / (6.0f64 * report.summary.within_sigma)) || !near(report.summary.cpk, 2.0f64 / (3.0f64 * report.summary.within_sigma)) || !near(report.summary.pp, 4.0f64 / (6.0f64 * report.summary.overall_sigma)) || !near(report.summary.ppk, 2.0f64 / (3.0f64 * report.summary.overall_sigma)) { ret chart.Invalid }
    if report.individuals.kind != .PointLine || report.moving_range.kind != .PointLine || report.recent.kind != .Scatter || report.histogram.kind != .Histogram || report.probability.kind != .Qq || report.intervals.kind != .Bar || report.guides.kind != .Rug { ret chart.Invalid }
    if report.individuals.coords.len != 8usize || report.moving_range.coords.len != 7usize || report.recent.coords.len != 8usize || report.histogram.bars.len != 4usize || report.within_curve.segments.len != 31usize || report.overall_curve.segments.len != 31usize || report.probability.coords.len != 8usize || report.intervals.bars.len != 3usize || report.guides.segments.len != 11usize { ret chart.Invalid }
    if !near(moving[4usize], 1.0f64) || !near(moving[5usize], 2.0f64) || !near(f64(guides[5usize].from.y), f64(guides[5usize].to.y)) { ret chart.Invalid }
    var count_sum = 0u64
    var i = 0usize
    while i < counts.len {
        count_sum += counts[i]
        i += 1usize
    }
    if count_sum != 8u64 || report.histogram.x_min > 8.0 || report.histogram.x_max < 12.0 { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &report.guides, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.individuals, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.moving_range, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.recent, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.histogram, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.within_curve, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.overall_curve, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.probability, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.intervals, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) < 30usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0, 210.0, "Capability", "Six normal capability panels")
    try chart_svg.append(&writer, &report.guides, blue)
    try chart_svg.append(&writer, &report.individuals, blue)
    try chart_svg.append(&writer, &report.moving_range, blue)
    try chart_svg.append(&writer, &report.recent, blue)
    try chart_svg.append(&writer, &report.histogram, blue)
    try chart_svg.append(&writer, &report.within_curve, blue)
    try chart_svg.append(&writer, &report.overall_curve, blue)
    try chart_svg.append(&writer, &report.probability, blue)
    try chart_svg.append(&writer, &report.intervals, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, bad_specs) = chart.capability_sixpack(values[..], sorted[..], 12.0f64, 8.0f64, panels[..], &work)
    var short_work = work
    short_work.moving = moving[..6usize]
    let (_, short_storage) = chart.capability_sixpack(values[..], sorted[..], 8.0f64, 12.0f64, panels[..], &short_work)
    let flat = [8]f64{ 10.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64 }
    let (_, flat_error) = chart.capability_sixpack(flat[..], flat[..], 8.0f64, 12.0f64, panels[..], &work)
    let unsorted = [8]f64{ 10.0f64, 9.0f64, 10.0f64, 10.0f64, 10.0f64, 10.0f64, 11.0f64, 11.0f64 }
    let (_, unsorted_error) = chart.capability_sixpack(values[..], unsorted[..], 8.0f64, 12.0f64, panels[..], &work)
    if bad_specs != chart.Invalid || short_storage != chart.TooLarge || flat_error != chart.Invalid || unsorted_error != chart.Invalid { ret chart.Invalid }
    var long_values: [26]f64 = zero
    var long_sorted: [26]f64 = zero
    i = 0usize
    while i < 26usize {
        long_values[i] = 9.0f64 + f64(i % 3usize)
        long_sorted[i] = 11.0f64
        if i < 18usize { long_sorted[i] = 10.0f64 }
        if i < 9usize { long_sorted[i] = 9.0f64 }
        i += 1usize
    }
    let (long_report, long_error) = chart.capability_sixpack(long_values[..], long_sorted[..], 8.0f64, 12.0f64, panels[..], &work)
    if long_error != ok || long_report.recent.coords.len != 25usize || long_report.recent.x_min != 2.0 || long_report.recent.x_max != 26.0 || long_report.recent.coords[0usize].y != long_report.recent.coords[24usize].y { ret chart.Invalid }
    try io.print("gfx chart capability sixpack ok\n")
    ret ok
}
