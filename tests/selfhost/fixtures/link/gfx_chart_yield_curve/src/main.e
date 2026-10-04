use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.001f32 && b - a < 0.001f32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let tenors = [5]f64{ 0.25f64, 1.0f64, 2.0f64, 5.0f64, 10.0f64 }
    let rates = [5]f64{ 4.8f64, 4.1f64, 3.9f64, 4.0f64, 4.3f64 }
    let bounds = geometry.rect(50.0, 42.0, 280.0, 160.0)
    var points: [5]chart.Coord = zero
    var links: [4]chart.Segment = zero
    let (curve, curve_error) = chart.yield_curve(tenors[..], rates[..], 10.0f64, 3.5f64, 5.0f64, bounds, points[..], links[..])
    if curve_error != ok || curve.coords.len != 5usize || curve.segments.len != 4usize || curve.x_min != 0.0f32 || curve.x_max != 10.0f32 || curve.y_min != 3.5f32 || curve.y_max != 5.0f32 { ret chart.Invalid }
    if !near(points[0usize].x, 57.0f32) || !near(points[0usize].y, 63.33333f32) || !near(points[4usize].x, 330.0f32) || points[2usize].y <= points[1usize].y || points[3usize].y >= points[2usize].y { ret chart.Invalid }
    if !near(links[0usize].from.x, points[0usize].x) || !near(links[3usize].to.x, points[4usize].x) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &curve, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Yield curve", "Yield by time to maturity")
    try chart_svg.append(&writer, &curve, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "<rect") { ret chart.Invalid }
    let (_, empty_error) = chart.yield_curve(tenors[..0usize], rates[..0usize], 10.0f64, 3.5f64, 5.0f64, bounds, points[..], links[..])
    let (_, short_error) = chart.yield_curve(tenors[..], rates[..], 10.0f64, 3.5f64, 5.0f64, bounds, points[..], links[..3usize])
    let (_, domain_error) = chart.yield_curve(tenors[..], rates[..], 10.0f64, 5.0f64, 3.5f64, bounds, points[..], links[..])
    let unordered = [2]f64{ 1.0f64, 0.25f64 }
    let two_rates = [2]f64{ 4.0f64, 4.1f64 }
    let (_, order_error) = chart.yield_curve(unordered[..], two_rates[..], 10.0f64, 3.5f64, 5.0f64, bounds, points[..], links[..])
    let (_, outside_error) = chart.yield_curve(tenors[..], rates[..], 5.0f64, 3.5f64, 5.0f64, bounds, points[..], links[..])
    let negative = [2]f64{ -0.5f64, 0.2f64 }
    let positive_tenors = [2]f64{ 1.0f64, 2.0f64 }
    let (negative_curve, negative_error) = chart.yield_curve(positive_tenors[..], negative[..], 2.0f64, -1.0f64, 1.0f64, bounds, points[..], links[..])
    if empty_error != chart.Empty || short_error != chart.TooLarge || domain_error != chart.Invalid || order_error != chart.Invalid || outside_error != chart.Invalid || negative_error != ok || negative_curve.coords.len != 2usize { ret chart.Invalid }
    try io.print("gfx chart yield curve ok\n")
    ret ok
}
