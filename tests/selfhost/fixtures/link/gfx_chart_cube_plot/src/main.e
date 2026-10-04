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
    // A/B/C combinations are bits 0/1/2; vertex zero has two readings.
    let values = [9]f64{ 1.0f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64, 7.0f64, 8.0f64, 9.0f64, 10.0f64 }
    let ids = [27]usize{
        0usize, 0usize, 0usize, 0usize, 0usize, 0usize,
        1usize, 0usize, 0usize, 0usize, 1usize, 0usize,
        1usize, 1usize, 0usize, 0usize, 0usize, 1usize,
        1usize, 0usize, 1usize, 0usize, 1usize, 1usize,
        1usize, 1usize, 1usize,
    }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var vertices: [8]chart.Coord = zero
    var edges: [12]chart.Segment = zero
    var means: [8]f64 = zero
    var counts: [8]usize = zero
    var storage = chart.CubePlotStorage { vertices: vertices[..], edges: edges[..], means: means[..], counts: counts[..] }
    let (map, result) = chart.cube_plot(values[..], ids[..], bounds, &storage)
    if result != ok || map.vertices.kind != .Scatter || map.frame.kind != .Rug || map.vertices.coords.len != 8usize || map.frame.segments.len != 12usize { ret chart.Invalid }
    let expected = [8]f64{ 2.0f64, 4.0f64, 5.0f64, 6.0f64, 7.0f64, 8.0f64, 9.0f64, 10.0f64 }
    var i = 0usize
    while i < expected.len {
        if !near(map.means[i], expected[i]) { ret chart.Invalid }
        i += 1usize
    }
    if map.counts[0usize] != 2usize || map.counts[7usize] != 1usize { ret chart.Invalid }
    if !near(f64(vertices[0usize].x), 48.4f64) || !near(f64(vertices[0usize].y), 125.6f64) || !near(f64(vertices[7usize].x), 230.8f64) || !near(f64(vertices[7usize].y), 34.4f64) { ret chart.Invalid }
    if edges[0usize].from.x != vertices[0usize].x || edges[0usize].to.x != vertices[1usize].x || edges[1usize].to.y != vertices[2usize].y || edges[2usize].to.x != vertices[4usize].x { ret chart.Invalid }

    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let gray = paint.rgba(0.65, 0.7, 0.76, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.frame, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.vertices, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 20usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "Cube plot", "Three two-level factor means")
    try chart_svg.append(&writer, &map.frame, gray)
    try chart_svg.append(&writer, &map.vertices, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let flat_values = [8]f64{ 7.0f64, 7.0f64, 7.0f64, 7.0f64, 7.0f64, 7.0f64, 7.0f64, 7.0f64 }
    let (flat, flat_error) = chart.cube_plot(flat_values[..], ids[3usize..], bounds, &storage)
    if flat_error != ok || !(flat.vertices.y_min < 7.0 && flat.vertices.y_max > 7.0) { ret chart.Invalid }
    let (_, bad_shape) = chart.cube_plot(values[..], ids[..26usize], bounds, &storage)
    var bad_ids = ids
    bad_ids[0usize] = 2usize
    let (_, bad_id) = chart.cube_plot(values[..], bad_ids[..], bounds, &storage)
    let (_, missing_cell) = chart.cube_plot(values[..8usize], ids[..24usize], bounds, &storage)
    var short_storage = chart.CubePlotStorage { vertices: vertices[..7usize], edges: edges[..], means: means[..], counts: counts[..] }
    let (_, short_vertices) = chart.cube_plot(values[..], ids[..], bounds, &short_storage)
    let (_, bad_bounds) = chart.cube_plot(values[..], ids[..], geometry.rect(0.0, 0.0, 0.0, 1.0), &storage)
    if bad_shape != chart.Invalid || bad_id != chart.Invalid || missing_cell != chart.Invalid || short_vertices != chart.TooLarge || bad_bounds != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart cube plot ok\n")
    ret ok
}
