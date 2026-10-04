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
    ret delta > -0.003f64 && delta < 0.003f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [9]f64{ 9.0f64, 10.0f64, 11.0f64, 10.0f64, 11.0f64, 12.0f64, 11.0f64, 12.0f64, 13.0f64 }
    let ids = [9]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var points: [3]chart.Coord = zero
    var signals: [3]chart.Coord = zero
    var upper: [3]chart.Segment = zero
    var lower: [3]chart.Segment = zero
    var center: [1]chart.Segment = zero
    var means: [3]f64 = zero
    var counts: [3]usize = zero
    var upper_limits: [3]f64 = zero
    var lower_limits: [3]f64 = zero
    var storage = chart.AnomStorage { points: points[..], signals: signals[..], upper: upper[..], lower: lower[..], center: center[..], means: means[..], counts: counts[..], upper_limits: upper_limits[..], lower_limits: lower_limits[..] }
    let (map, result) = chart.anom(values[..], ids[..], 3usize, 2.0f64, bounds, &storage)
    if result != ok || map.groups.coords.len != 3usize || map.signals.coords.len != 2usize || map.upper.segments.len != 3usize || map.lower.segments.len != 3usize || map.center.segments.len != 1usize { ret chart.Invalid }
    if !near(map.grand_mean, 11.0f64) || !near(map.pooled_sd, 1.0f64) || !near(map.means[0usize], 10.0f64) || !near(map.means[1usize], 11.0f64) || !near(map.means[2usize], 12.0f64) { ret chart.Invalid }
    if !near(map.upper_limits[0usize], 11.942809f64) || !near(map.lower_limits[2usize], 10.057191f64) || map.counts[0usize] != 3usize || map.counts[1usize] != 3usize || map.counts[2usize] != 3usize { ret chart.Invalid }
    if !near(f64(map.signals.coords[0usize].x), 50.0f64) || !near(f64(map.signals.coords[1usize].x), 210.0f64) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let red = paint.rgba(0.8, 0.2, 0.2, 1.0)
    let gray = paint.rgba(0.6, 0.7, 0.75, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.upper, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.lower, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &map.center, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.groups, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.signals, paint.Brush { Solid: red })
    if scene.builder_count(&builder) != 12usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "ANOM", "Decision limits and flagged group means")
    try chart_svg.append(&writer, &map.upper, red)
    try chart_svg.append(&writer, &map.lower, red)
    try chart_svg.append(&writer, &map.center, gray)
    try chart_svg.append(&writer, &map.groups, blue)
    try chart_svg.append(&writer, &map.signals, red)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let constant = [4]f64{ 10.0f64, 10.0f64, 10.0f64, 10.0f64 }
    let constant_ids = [4]usize{ 0usize, 0usize, 1usize, 1usize }
    let (flat, flat_error) = chart.anom(constant[..], constant_ids[..], 2usize, 2.0f64, bounds, &storage)
    if flat_error != ok || flat.signals.coords.len != 0usize || !(flat.groups.y_min < 10.0 && flat.groups.y_max > 10.0) { ret chart.Invalid }
    let unequal_ids = [9]usize{ 0usize, 0usize, 0usize, 0usize, 1usize, 1usize, 2usize, 2usize, 2usize }
    let (unequal, unequal_error) = chart.anom(values[..], unequal_ids[..], 3usize, 2.0f64, bounds, &storage)
    if unequal_error != ok || unequal.counts[0usize] != 4usize || unequal.counts[1usize] != 2usize || !(unequal.upper_limits[1usize] > unequal.upper_limits[0usize]) { ret chart.Invalid }
    let (_, bad_ids) = chart.anom(values[..], ids[..8usize], 3usize, 2.0f64, bounds, &storage)
    let (_, bad_critical) = chart.anom(values[..], ids[..], 3usize, 0.0f64, bounds, &storage)
    var short = chart.AnomStorage { points: points[..2usize], signals: signals[..], upper: upper[..], lower: lower[..], center: center[..], means: means[..], counts: counts[..], upper_limits: upper_limits[..], lower_limits: lower_limits[..] }
    let (_, short_storage) = chart.anom(values[..], ids[..], 3usize, 2.0f64, bounds, &short)
    let missing_ids = [9]usize{ 0usize, 0usize, 0usize, 0usize, 0usize, 0usize, 2usize, 2usize, 2usize }
    let (_, missing_group) = chart.anom(values[..], missing_ids[..], 3usize, 2.0f64, bounds, &storage)
    if bad_ids != chart.Invalid || bad_critical != chart.Invalid || short_storage != chart.TooLarge || missing_group != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart anom ok\n")
    ret ok
}
