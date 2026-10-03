use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool {
    let delta = a - b
    ret delta > -0.001 && delta < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let counts = [4]f64{ 3.0f64, 1.0f64, 1.0f64, 3.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 160.0, 100.0)
    var totals: [2]f64 = zero
    var bars: [4]geometry.Rect = zero
    var layers: [2]chart.Layout = zero
    let (spine, result) = chart.spine_plot(counts[..], 2usize, bounds, 0.0, totals[..], bars[..], layers[..])
    if result != ok || spine.grand_total != 8.0f64 || spine.column_totals.len != 2usize || spine.column_totals[0usize] != 4.0f64 || spine.column_totals[1usize] != 4.0f64 || spine.categories.len != 2usize || spine.categories[0usize].kind != .Bar || spine.categories[0usize].bars.len != 2usize { ret chart.Invalid }
    if !near(bars[0usize].x, 10.0) || !near(bars[0usize].y, 45.0) || !near(bars[0usize].width, 80.0) || !near(bars[0usize].height, 75.0) || !near(bars[1usize].x, 90.0) || !near(bars[1usize].y, 95.0) || !near(bars[1usize].height, 25.0) || !near(bars[2usize].y, 20.0) || !near(bars[3usize].y, 20.0) || !near(bars[3usize].height, 75.0) { ret chart.Invalid }
    if !near(bars[0usize].width * bars[0usize].height / (bounds.width * bounds.height), 0.375) || !near(bars[1usize].width * bars[1usize].height / (bounds.width * bounds.height), 0.125) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &spine.categories[0usize], paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &spine.categories[1usize], paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 190.0, 140.0, "Spine plot", "Area is proportional to count")
    try chart_svg.append(&writer, &spine.categories[0usize], ink)
    try chart_svg.append(&writer, &spine.categories[1usize], ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let zeros = [4]f64{ 4.0f64, 0.0f64, 1.0f64, 3.0f64 }
    let (sparse, zero_error) = chart.spine_plot(zeros[..], 2usize, bounds, 0.0, totals[..], bars[..], layers[..])
    if zero_error != ok || sparse.grand_total != 8.0f64 || bars[2usize].height != 0.0 || !near(bars[0usize].height, 100.0) { ret chart.Invalid }
    let empty_column = [4]f64{ 0.0f64, 0.0f64, 1.0f64, 3.0f64 }
    let negative = [4]f64{ 3.0f64, -1.0f64, 1.0f64, 3.0f64 }
    let bad_shape = [3]f64{ 1.0f64, 2.0f64, 3.0f64 }
    let (_, empty_error) = chart.spine_plot(counts[..0usize], 2usize, bounds, 0.0, totals[..], bars[..], layers[..])
    let (_, column_error) = chart.spine_plot(empty_column[..], 2usize, bounds, 0.0, totals[..], bars[..], layers[..])
    let (_, negative_error) = chart.spine_plot(negative[..], 2usize, bounds, 0.0, totals[..], bars[..], layers[..])
    let (_, shape_error) = chart.spine_plot(bad_shape[..], 2usize, bounds, 0.0, totals[..], bars[..], layers[..])
    let (_, bounds_error) = chart.spine_plot(counts[..], 2usize, geometry.rect(0.0, 0.0, -1.0, 100.0), 0.0, totals[..], bars[..], layers[..])
    let (_, gutter_error) = chart.spine_plot(counts[..], 2usize, bounds, -1.0, totals[..], bars[..], layers[..])
    let (_, wide_gutter_error) = chart.spine_plot(counts[..], 2usize, bounds, 30.0, totals[..], bars[..], layers[..])
    let (_, totals_error) = chart.spine_plot(counts[..], 2usize, bounds, 0.0, totals[..1usize], bars[..], layers[..])
    let (_, bars_error) = chart.spine_plot(counts[..], 2usize, bounds, 0.0, totals[..], bars[..3usize], layers[..])
    let (_, layers_error) = chart.spine_plot(counts[..], 2usize, bounds, 0.0, totals[..], bars[..], layers[..1usize])
    if empty_error != chart.Empty || column_error != chart.Invalid || negative_error != chart.Invalid || shape_error != chart.Invalid || bounds_error != chart.Invalid || gutter_error != chart.Invalid || wide_gutter_error != chart.TooLarge || totals_error != chart.TooLarge || bars_error != chart.TooLarge || layers_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart spine plot ok\n")
    ret ok
}
