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
    let values = [8]f64{ 2.0f64, 4.0f64, 5.0f64, 9.0f64, 10.0f64, 8.0f64, 3.0f64, 5.0f64 }
    let x_ids = [8]usize{ 0usize, 0usize, 1usize, 2usize, 0usize, 1usize, 2usize, 2usize }
    let series_ids = [8]usize{ 0usize, 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 1usize }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var points: [6]chart.Coord = zero
    var lines: [4]chart.Segment = zero
    var means: [6]f64 = zero
    var counts: [6]usize = zero
    var series: [2]chart.Layout = zero
    var storage = chart.InteractionStorage { points: points[..], lines: lines[..], means: means[..], counts: counts[..], series: series[..] }
    let (map, result) = chart.interaction_plot(values[..], x_ids[..], series_ids[..], 3usize, 2usize, bounds, &storage)
    if result != ok || map.series.len != 2usize || map.series[0usize].kind != .PointLine || map.series[1usize].kind != .PointLine || map.series[0usize].coords.len != 3usize || map.series[1usize].segments.len != 2usize { ret chart.Invalid }
    let expected = [6]f64{ 3.0f64, 5.0f64, 9.0f64, 10.0f64, 8.0f64, 4.0f64 }
    var i = 0usize
    while i < expected.len {
        if !near(map.means[i], expected[i]) { ret chart.Invalid }
        i += 1usize
    }
    if map.counts[0usize] != 2usize || map.counts[5usize] != 2usize || map.counts[1usize] != 1usize || map.counts[4usize] != 1usize { ret chart.Invalid }
    if !near(f64(points[0usize].x), 50.0f64) || !near(f64(points[1usize].x), 130.0f64) || !near(f64(points[2usize].x), 210.0f64) || !near(f64(points[3usize].y), 20.0f64) || !near(f64(points[0usize].y), 125.0f64) { ret chart.Invalid }
    if lines[1usize].to.x != points[2usize].x || lines[2usize].from.x != points[3usize].x || !(points[0usize].y > points[3usize].y && points[2usize].y < points[5usize].y) { ret chart.Invalid }

    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.35, 0.15, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.series[0usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.series[1usize], paint.Brush { Solid: orange })
    if scene.builder_count(&builder) != 8usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "Interaction plot", "Raw response means for two factors")
    try chart_svg.append(&writer, &map.series[0usize], blue)
    try chart_svg.append(&writer, &map.series[1usize], orange)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let flat_values = [4]f64{ 7.0f64, 7.0f64, 7.0f64, 7.0f64 }
    let flat_x = [4]usize{ 0usize, 1usize, 0usize, 1usize }
    let flat_series = [4]usize{ 0usize, 0usize, 1usize, 1usize }
    let (flat, flat_error) = chart.interaction_plot(flat_values[..], flat_x[..], flat_series[..], 2usize, 2usize, bounds, &storage)
    if flat_error != ok || !(flat.series[0usize].y_min < 7.0 && flat.series[0usize].y_max > 7.0) { ret chart.Invalid }
    let (_, bad_shape) = chart.interaction_plot(values[..], x_ids[..7usize], series_ids[..], 3usize, 2usize, bounds, &storage)
    var bad_x = [8]usize{ 0usize, 0usize, 1usize, 3usize, 0usize, 1usize, 2usize, 2usize }
    let (_, bad_id) = chart.interaction_plot(values[..], bad_x[..], series_ids[..], 3usize, 2usize, bounds, &storage)
    let missing_x = [4]usize{ 0usize, 1usize, 0usize, 0usize }
    let (_, missing_cell) = chart.interaction_plot(flat_values[..], missing_x[..], flat_series[..], 2usize, 2usize, bounds, &storage)
    var short_storage = chart.InteractionStorage { points: points[..5usize], lines: lines[..], means: means[..], counts: counts[..], series: series[..] }
    let (_, short_points) = chart.interaction_plot(values[..], x_ids[..], series_ids[..], 3usize, 2usize, bounds, &short_storage)
    let (_, bad_bounds) = chart.interaction_plot(values[..], x_ids[..], series_ids[..], 3usize, 2usize, geometry.rect(0.0, 0.0, 0.0, 1.0), &storage)
    if bad_shape != chart.Invalid || bad_id != chart.Invalid || missing_cell != chart.Invalid || short_points != chart.TooLarge || bad_bounds != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart interaction plot ok\n")
    ret ok
}
