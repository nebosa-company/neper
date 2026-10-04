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
    // Deliberately unbalanced: A has 2/3 observations; B has 2/3.
    let values = [5]f64{ 2.0f64, 4.0f64, 6.0f64, 8.0f64, 10.0f64 }
    let ids = [10]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 0usize, 1usize, 1usize, 1usize, 1usize }
    let levels = [2]usize{ 2usize, 2usize }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var points: [4]chart.Coord = zero
    var lines: [2]chart.Segment = zero
    var references: [2]chart.Segment = zero
    var means: [4]f64 = zero
    var counts: [4]usize = zero
    var storage = chart.MainEffectsStorage { points: points[..], lines: lines[..], references: references[..], means: means[..], counts: counts[..] }
    let (map, result) = chart.main_effects(values[..], ids[..], levels[..], bounds, &storage)
    if result != ok || map.levels.kind != .Scatter || map.connections.kind != .Rug || map.reference.kind != .Rug || map.levels.coords.len != 4usize || map.connections.segments.len != 2usize || map.reference.segments.len != 2usize { ret chart.Invalid }
    if !near(map.grand_mean, 6.0f64) || !near(map.means[0usize], 3.0f64) || !near(map.means[1usize], 8.0f64) || !near(map.means[2usize], 4.0f64) || !near(map.means[3usize], 7.333333f64) { ret chart.Invalid }
    if map.counts[0usize] != 2usize || map.counts[1usize] != 3usize || map.counts[2usize] != 2usize || map.counts[3usize] != 3usize { ret chart.Invalid }
    if !near(f64(points[0usize].x), 40.0f64) || !near(f64(points[1usize].x), 100.0f64) || !near(f64(points[2usize].x), 160.0f64) || !near(f64(points[3usize].x), 220.0f64) || !near(f64(references[0usize].from.y), 80.0f64) { ret chart.Invalid }
    if lines[0usize].to.x >= lines[1usize].from.x || lines[0usize].to.x != points[1usize].x || lines[1usize].from.x != points[2usize].x { ret chart.Invalid }

    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let gray = paint.rgba(0.65, 0.7, 0.76, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.reference, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.connections, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.levels, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 8usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "Main effects plot", "Raw level means and overall mean")
    try chart_svg.append(&writer, &map.reference, gray)
    try chart_svg.append(&writer, &map.connections, blue)
    try chart_svg.append(&writer, &map.levels, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let constant = [4]f64{ 10.0f64, 10.0f64, 10.0f64, 10.0f64 }
    let constant_ids = [8]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 0usize, 1usize, 1usize }
    let (flat, flat_error) = chart.main_effects(constant[..], constant_ids[..], levels[..], bounds, &storage)
    if flat_error != ok || !(flat.levels.y_min < 10.0 && flat.levels.y_max > 10.0) { ret chart.Invalid }
    let three_levels = [3]usize{ 2usize, 2usize, 2usize }
    let three_ids = [15]usize{ 0usize, 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 0usize, 0usize, 1usize, 1usize, 1usize, 1usize, 1usize, 0usize }
    var three_points: [6]chart.Coord = zero
    var three_lines: [3]chart.Segment = zero
    var three_references: [3]chart.Segment = zero
    var three_means: [6]f64 = zero
    var three_counts: [6]usize = zero
    var three_storage = chart.MainEffectsStorage { points: three_points[..], lines: three_lines[..], references: three_references[..], means: three_means[..], counts: three_counts[..] }
    let (three, three_error) = chart.main_effects(values[..], three_ids[..], three_levels[..], bounds, &three_storage)
    if three_error != ok || three.levels.coords.len != 6usize || three.connections.segments.len != 3usize || three.reference.segments.len != 3usize || !near(three.means[4usize], 6.0f64) || !near(three.means[5usize], 6.0f64) { ret chart.Invalid }
    let (_, bad_shape) = chart.main_effects(values[..], ids[..9usize], levels[..], bounds, &storage)
    var bad_ids = [10]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 0usize, 1usize, 1usize, 2usize, 1usize }
    let (_, bad_id) = chart.main_effects(values[..], bad_ids[..], levels[..], bounds, &storage)
    let missing_ids = [10]usize{ 0usize, 0usize, 0usize, 0usize, 1usize, 0usize, 1usize, 0usize, 1usize, 0usize }
    let (_, missing_level) = chart.main_effects(values[..], missing_ids[..], levels[..], bounds, &storage)
    var short_storage = chart.MainEffectsStorage { points: points[..3usize], lines: lines[..], references: references[..], means: means[..], counts: counts[..] }
    let (_, short_points) = chart.main_effects(values[..], ids[..], levels[..], bounds, &short_storage)
    let (_, bad_bounds) = chart.main_effects(values[..], ids[..], levels[..], geometry.rect(0.0, 0.0, 0.0, 1.0), &storage)
    if bad_shape != chart.Invalid || bad_id != chart.Invalid || missing_level != chart.Invalid || short_points != chart.TooLarge || bad_bounds != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart main effects ok\n")
    ret ok
}
