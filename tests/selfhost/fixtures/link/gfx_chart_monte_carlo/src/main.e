use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool { ret a - b < 0.00001f64 && b - a < 0.00001f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let outcomes = [9]f64{ 12.0f64, 4.0f64, 8.0f64, 2.0f64, 16.0f64, 6.0f64, 10.0f64, 4.0f64, 12.0f64 }
    var sorted: [9]f64 = zero
    var counts: [4]u64 = zero
    var bars: [4]geometry.Rect = zero
    var cdf_segments: [17]chart.Segment = zero
    var rules: [2]chart.Segment = zero
    let histogram_bounds = geometry.rect(40.0, 50.0, 280.0, 130.0)
    let cdf_bounds = geometry.rect(40.0, 50.0, 280.0, 130.0)
    let (distribution, distribution_error) = chart.monte_carlo_distribution(outcomes[..], 0.0f64, 16.0f64, 8.0f64, histogram_bounds, cdf_bounds, sorted[..], counts[..], bars[..], cdf_segments[..], rules[..])
    if distribution_error != ok || distribution.histogram.bars.len != 4usize || distribution.cdf.segments.len != 17usize || distribution.histogram_threshold.segments.len != 1usize || distribution.cdf_threshold.segments.len != 1usize || distribution.at_or_below != 5u64 || !near(distribution.probability, 5.0f64 / 9.0f64) { ret chart.Invalid }
    if counts[0usize] != 1u64 || counts[1usize] != 3u64 || counts[2usize] != 2u64 || counts[3usize] != 3u64 || sorted[0usize] != 2.0f64 || sorted[8usize] != 16.0f64 || sorted[2usize] != 4.0f64 { ret chart.Invalid }
    if !near(f64(bars[1usize].height), 130.0f64) || !near(f64(rules[0usize].from.x), 180.0f64) || !near(f64(rules[1usize].from.x), 180.0f64) || !near(f64(cdf_segments[16usize].to.y), 50.0f64) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &distribution.histogram, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &distribution.cdf, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &distribution.histogram_threshold, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &distribution.cdf_threshold, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Monte Carlo outcomes", "Histogram and empirical CDF")
    try chart_svg.append(&writer, &distribution.histogram, ink)
    try chart_svg.append(&writer, &distribution.cdf, ink)
    try chart_svg.append(&writer, &distribution.histogram_threshold, ink)
    try chart_svg.append(&writer, &distribution.cdf_threshold, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "<line") { ret chart.Invalid }
    let (_, empty_error) = chart.monte_carlo_distribution(outcomes[..0usize], 0.0f64, 16.0f64, 8.0f64, histogram_bounds, cdf_bounds, sorted[..], counts[..], bars[..], cdf_segments[..], rules[..])
    let (_, domain_error) = chart.monte_carlo_distribution(outcomes[..], 16.0f64, 0.0f64, 8.0f64, histogram_bounds, cdf_bounds, sorted[..], counts[..], bars[..], cdf_segments[..], rules[..])
    let (_, threshold_error) = chart.monte_carlo_distribution(outcomes[..], 0.0f64, 16.0f64, 17.0f64, histogram_bounds, cdf_bounds, sorted[..], counts[..], bars[..], cdf_segments[..], rules[..])
    let (_, short_error) = chart.monte_carlo_distribution(outcomes[..], 0.0f64, 16.0f64, 8.0f64, histogram_bounds, cdf_bounds, sorted[..], counts[..], bars[..], cdf_segments[..16usize], rules[..])
    let (_, bins_error) = chart.monte_carlo_distribution(outcomes[..], 0.0f64, 16.0f64, 8.0f64, histogram_bounds, cdf_bounds, sorted[..], counts[..0usize], bars[..0usize], cdf_segments[..], rules[..])
    let outlier = [1]f64{ 17.0f64 }
    let (_, outside_error) = chart.monte_carlo_distribution(outlier[..], 0.0f64, 16.0f64, 8.0f64, histogram_bounds, cdf_bounds, sorted[..], counts[..], bars[..], cdf_segments[..], rules[..])
    if empty_error != chart.Empty || domain_error != chart.Invalid || threshold_error != chart.Invalid || short_error != chart.TooLarge || bins_error != chart.Invalid || outside_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart monte carlo ok\n")
    ret ok
}
