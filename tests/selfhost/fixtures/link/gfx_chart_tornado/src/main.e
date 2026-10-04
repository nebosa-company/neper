use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.0001f32 && b - a < 0.0001f32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let cases = [5]chart.TornadoCase{
        chart.TornadoCase { low_result: 88.0f64, high_result: 120.0f64 },
        chart.TornadoCase { low_result: 55.0f64, high_result: 145.0f64 },
        chart.TornadoCase { low_result: 80.0f64, high_result: 130.0f64 },
        chart.TornadoCase { low_result: 110.0f64, high_result: 90.0f64 },
        chart.TornadoCase { low_result: 90.0f64, high_result: 110.0f64 },
    }
    var order: [5]usize = zero
    var low: [5]geometry.Rect = zero
    var high: [5]geometry.Rect = zero
    var base: [1]chart.Segment = zero
    let bounds = geometry.rect(30.0, 40.0, 300.0, 150.0)
    let (tornado, chart_error) = chart.tornado_sensitivity(cases[..], 100.0f64, bounds, order[..], low[..], high[..], base[..])
    if chart_error != ok || tornado.low.bars.len != 5usize || tornado.high.bars.len != 5usize || tornado.baseline.segments.len != 1usize || tornado.minimum != 55.0f64 || tornado.maximum != 145.0f64 { ret chart.Invalid }
    if order[0usize] != 1usize || order[1usize] != 2usize || order[2usize] != 0usize || order[3usize] != 3usize || order[4usize] != 4usize { ret chart.Invalid }
    if !near(base[0usize].from.x, 180.0f32) || !near(base[0usize].to.x, 180.0f32) || !near(low[0usize].x, 30.0f32) || !near(low[0usize].width, 150.0f32) || !near(high[0usize].x, 180.0f32) || !near(high[0usize].width, 150.0f32) { ret chart.Invalid }
    if low[3usize].x != 180.0f32 || high[3usize].x >= 180.0f32 || low[3usize].y >= high[3usize].y { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &tornado.low, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &tornado.high, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &tornado.baseline, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Tornado sensitivity", "Paired low and high scenarios")
    try chart_svg.append(&writer, &tornado.low, ink)
    try chart_svg.append(&writer, &tornado.high, ink)
    try chart_svg.append(&writer, &tornado.baseline, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "<line") { ret chart.Invalid }
    let (_, empty_error) = chart.tornado_sensitivity(cases[..0usize], 100.0f64, bounds, order[..], low[..], high[..], base[..])
    let (_, short_error) = chart.tornado_sensitivity(cases[..], 100.0f64, bounds, order[..4usize], low[..], high[..], base[..])
    let (_, bounds_error) = chart.tornado_sensitivity(cases[..], 100.0f64, geometry.rect(30.0, 40.0, -1.0, 150.0), order[..], low[..], high[..], base[..])
    let flat = [1]chart.TornadoCase{ chart.TornadoCase { low_result: 100.0f64, high_result: 100.0f64 } }
    let (_, flat_error) = chart.tornado_sensitivity(flat[..], 100.0f64, bounds, order[..], low[..], high[..], base[..])
    let huge = [1]chart.TornadoCase{ chart.TornadoCase { low_result: 0.0f64, high_result: 1.0e100f64 } }
    let (_, huge_error) = chart.tornado_sensitivity(huge[..], 0.0f64, bounds, order[..], low[..], high[..], base[..])
    if empty_error != chart.Empty || short_error != chart.TooLarge || bounds_error != chart.Invalid || flat_error != chart.Invalid || huge_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart tornado ok\n")
    ret ok
}
