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
    let d = a - b
    ret d > -0.001 && d < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let field = [4]f64{ 0.0f64, 2.0f64, 0.0f64, 2.0f64 }
    let levels = [2]f64{ 0.5f64, 1.5f64 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 80.0)
    var segments: [4]chart.Segment = zero
    var storage: [2]chart.Layout = zero
    let (layers, contour_error) = chart.contour(field[..], 2usize, 2usize, levels[..], bounds, segments[..], storage[..])
    if contour_error != ok || layers.len != 2usize || layers[0usize].kind != .Rug || layers[0usize].segments.len != 1usize || layers[1usize].segments.len != 1usize { ret chart.Invalid }
    if !near(segments[0usize].from.x, 25.0) || !near(segments[0usize].to.x, 25.0) || !near(segments[1usize].from.x, 75.0) || !near(segments[1usize].to.x, 75.0) { ret chart.Invalid }
    if !near(segments[0usize].from.y, 0.0) || !near(segments[0usize].to.y, 80.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &layers[0usize], paint.Brush { Solid: ink })
    if scene.builder_count(&builder) == 0usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 80.0, "Contour", "Interpolated isoline")
    try chart_svg.append(&writer, &layers[0usize], ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let saddle = [4]f64{ 2.0f64, 0.0f64, 0.0f64, 2.0f64 }
    let one = [1]f64{ 1.0f64 }
    let (connected, saddle_error) = chart.contour(saddle[..], 2usize, 2usize, one[..], bounds, segments[..], storage[..])
    if saddle_error != ok || connected[0usize].segments.len != 2usize { ret chart.Invalid }
    if !near(segments[0usize].from.x, 50.0) || !near(segments[0usize].to.x, 100.0) || !near(segments[1usize].from.x, 50.0) || !near(segments[1usize].to.x, 0.0) { ret chart.Invalid }
    let high = [1]f64{ 1.5f64 }
    let (disconnected, high_error) = chart.contour(saddle[..], 2usize, 2usize, high[..], bounds, segments[..], storage[..])
    if high_error != ok || disconnected[0usize].segments.len != 2usize { ret chart.Invalid }
    if !near(segments[0usize].from.x, 25.0) || !near(segments[0usize].to.x, 0.0) || !near(segments[1usize].from.x, 100.0) || !near(segments[1usize].to.x, 75.0) { ret chart.Invalid }
    let invalid_levels = [2]f64{ 1.0f64, 1.0f64 }
    let (_, order_error) = chart.contour(field[..], 2usize, 2usize, invalid_levels[..], bounds, segments[..], storage[..])
    let (_, shape_error) = chart.contour(field[..], 2usize, 3usize, one[..], bounds, segments[..], storage[..])
    let (_, capacity_error) = chart.contour(field[..], 2usize, 2usize, levels[..], bounds, segments[..1usize], storage[..])
    if order_error != chart.Invalid || shape_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart contour ok\n")
    ret ok
}
