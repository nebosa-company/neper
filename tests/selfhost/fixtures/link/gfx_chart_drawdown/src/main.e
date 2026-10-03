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
    let x = [5]f32{ 0.0, 1.0, 2.0, 3.0, 4.0 }
    let prices = [5]f32{ 100.0, 80.0, 120.0, 90.0, 130.0 }
    var losses: [5]f32 = zero
    var points: [10]chart.Coord = zero
    let bounds = geometry.rect(0.0, 0.0, 100.0, 80.0)
    let (marks, chart_error) = chart.drawdown(x[..], prices[..], bounds, losses[..], points[..])
    if chart_error != ok || marks.kind != .Area || marks.coords.len != 10usize || !near(marks.y_min, -0.25) || !near(marks.y_max, 0.0) { ret chart.Invalid }
    if !near(losses[0usize], 0.0) || !near(losses[1usize], -0.2) || !near(losses[2usize], 0.0) || !near(losses[3usize], -0.25) || !near(losses[4usize], 0.0) { ret chart.Invalid }
    if !near(points[0usize].y, 0.0) || !near(points[3usize].y, 80.0) || !near(points[9usize].y, 0.0) { ret chart.Invalid }
    let ink = paint.rgba(0.7, 0.2, 0.3, 1.0)
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) == 0usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 80.0, "Drawdown", "Loss from running high")
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let invalid_price = [2]f32{ 100.0, 0.0 }
    let reversed_x = [2]f32{ 1.0, 0.0 }
    let (_, price_error) = chart.drawdown(x[..2usize], invalid_price[..], bounds, losses[..], points[..])
    let (_, order_error) = chart.drawdown(reversed_x[..], prices[..2usize], bounds, losses[..], points[..])
    let (_, capacity_error) = chart.drawdown(x[..], prices[..], bounds, losses[..4usize], points[..])
    let (_, empty_error) = chart.drawdown(x[..1usize], prices[..1usize], bounds, losses[..], points[..])
    if price_error != chart.Invalid || order_error != chart.Invalid || capacity_error != chart.TooLarge || empty_error != chart.Empty { ret chart.Invalid }
    try io.print("gfx chart drawdown ok\n")
    ret ok
}
