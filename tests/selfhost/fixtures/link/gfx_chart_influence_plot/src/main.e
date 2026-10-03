use e.algo.stat
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
    let x = [5]f64{ 0.0f64, 1.0f64, 2.0f64, 3.0f64, 4.0f64 }
    let y = [5]f64{ 1.0f64, 2.0f64, 3.0f64, 4.0f64, 7.0f64 }
    var diagnostics: [5]stat.RegressionDiagnostic = zero
    try stat.regression_diagnostics(x[..], y[..], diagnostics[..])
    let bounds = geometry.rect(20.0, 30.0, 120.0, 90.0)
    var points: [5]chart.Coord = zero
    var circles: [5]geometry.Rect = zero
    var guides: [5]chart.Segment = zero
    let (map, map_error) = chart.influence_plot(diagnostics[..], bounds, 10.0, points[..], circles[..], guides[..])
    if map_error != ok || map.points.kind != .Scatter || map.points.coords.len != 5usize || map.bubbles.kind != .Bubble || map.guides.kind != .Rug || map.bubbles.bars.len != 5usize || map.guides.segments.len != 4usize || map.max_cook < 2.24f64 { ret chart.Invalid }
    if !near(circles[4usize].width, 20.0) || !near(circles[0usize].width, 10.0) || circles[1usize].width != 0.0 || !near(guides[1usize].from.y, 75.0) || !near(guides[3usize].from.x, 20.0 + 120.0 * 0.8 / 1.08) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let gray = paint.rgba(0.7, 0.7, 0.7, 1.0)
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.guides, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.points, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.bubbles, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 13usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 170.0, 150.0, "Influence", "Leverage, standardized residual, Cook area")
    try chart_svg.append(&writer, &map.guides, gray)
    try chart_svg.append(&writer, &map.points, ink)
    try chart_svg.append(&writer, &map.bubbles, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "<circle") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, empty_error) = chart.influence_plot(diagnostics[..0usize], bounds, 10.0, points[..], circles[..], guides[..])
    let (_, radius_error) = chart.influence_plot(diagnostics[..], bounds, 0.0, points[..], circles[..], guides[..])
    let (_, capacity_error) = chart.influence_plot(diagnostics[..], bounds, 10.0, points[..4usize], circles[..], guides[..])
    let (_, guide_error) = chart.influence_plot(diagnostics[..], bounds, 10.0, points[..], circles[..], guides[..4usize])
    var invalid = diagnostics
    invalid[0usize].leverage = 1.0f64
    let (_, leverage_error) = chart.influence_plot(invalid[..], bounds, 10.0, points[..], circles[..], guides[..])
    if empty_error != chart.Empty || radius_error != chart.Invalid || capacity_error != chart.TooLarge || guide_error != chart.TooLarge || leverage_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart influence plot ok\n")
    ret ok
}
