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
    let d = a - b
    ret d > -0.01f64 && d < 0.01f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let field = [4]f64{ 0.0f64, 2.0f64, 0.0f64, 2.0f64 }
    let levels = [1]f64{ 1.0f64 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 80.0)
    var points: [40]chart.Coord = zero
    var storage: [8]chart.Layout = zero
    var band_ids: [8]usize = zero
    let (layers, fill_error) = chart.filled_contour(field[..], 2usize, 2usize, levels[..], bounds, points[..], storage[..], band_ids[..])
    if fill_error != ok || layers.len != 4usize { ret chart.Invalid }
    var seen: [2]usize = zero
    var total_area = 0.0f64
    var i = 0usize
    while i < layers.len {
        if layers[i].kind != .Area || layers[i].coords.len < 4usize || band_ids[i] > 1usize { ret chart.Invalid }
        seen[band_ids[i]] += 1usize
        var twice = 0.0f64
        var j = 0usize
        while j + 1usize < layers[i].coords.len {
            let p = layers[i].coords[j]
            let q = layers[i].coords[j + 1usize]
            twice += f64(p.x) * f64(q.y) - f64(q.x) * f64(p.y)
            j += 1usize
        }
        if twice < 0.0f64 { twice = 0.0f64 - twice }
        total_area += twice * 0.5f64
        i += 1usize
    }
    if seen[0usize] != 2usize || seen[1usize] != 2usize || !near(total_area, 8000.0f64) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.5, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let colors = [2]paint.Color{ ink, paint.rgba(0.7, 0.2, 0.2, 1.0) }
    try chart_scene.append_filled_contour(a, &builder, layers, band_ids[..layers.len], colors[..])
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 80.0, "Filled contour", "Clipped scalar bands")
    try chart_svg.append_filled_contour(&writer, layers, band_ids[..layers.len], colors[..])
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let invalid_levels = [1]f64{ 0.0f64 }
    let (_, order_error) = chart.filled_contour(field[..], 2usize, 2usize, invalid_levels[..], bounds, points[..], storage[..], band_ids[..])
    let (_, shape_error) = chart.filled_contour(field[..], 2usize, 3usize, levels[..], bounds, points[..], storage[..], band_ids[..])
    let (_, points_error) = chart.filled_contour(field[..], 2usize, 2usize, levels[..], bounds, points[..4usize], storage[..], band_ids[..])
    let (_, layers_error) = chart.filled_contour(field[..], 2usize, 2usize, levels[..], bounds, points[..], storage[..1usize], band_ids[..])
    let (_, bands_error) = chart.filled_contour(field[..], 2usize, 2usize, levels[..], bounds, points[..], storage[..], band_ids[..1usize])
    if order_error != chart.Invalid || shape_error != chart.Invalid || points_error != chart.TooLarge || layers_error != chart.TooLarge || bands_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart filled contour ok\n")
    ret ok
}
