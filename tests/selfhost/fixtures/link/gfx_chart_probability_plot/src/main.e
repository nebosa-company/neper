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
    ret delta > -0.002 && delta < 0.002
}

fn main(a: *mem.Arena, args: []str) -> err {
    let normal = [4]f64{ -1.0f64, 0.0f64, 0.0f64, 1.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 200.0, 100.0)
    var points: [4]chart.Coord = zero
    var line: [1]chart.Segment = zero
    var ticks: [7]chart.Tick = zero
    let (paper, result) = chart.probability_plot(normal[..], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, bounds, points[..], line[..], ticks[..])
    if result != ok || paper.observations.kind != .Scatter || paper.reference.kind != .Line || paper.observations.coords.len != 4usize || paper.reference.segments.len != 1usize || paper.probability_ticks.len != 7usize { ret chart.Invalid }
    if !near(points[0usize].x, 70.0) || !near(points[1usize].x, 110.0) || !near(points[2usize].x, 110.0) || !near(points[3usize].x, 150.0) || !(points[0usize].y > points[1usize].y && points[1usize].y > points[2usize].y && points[2usize].y > points[3usize].y) { ret chart.Invalid }
    if !near(ticks[0usize].value, 0.01) || !near(ticks[0usize].fraction, 0.0) || !near(ticks[3usize].value, 0.5) || !near(ticks[3usize].fraction, 0.5) || !near(ticks[6usize].fraction, 1.0) || !near(ticks[1usize].fraction, 1.0 - ticks[5usize].fraction) { ret chart.Invalid }
    if !near(line[0usize].from.x, 16.946) || !near(line[0usize].from.y, 120.0) || !near(line[0usize].to.x, 203.054) || !near(line[0usize].to.y, 20.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &paper.reference, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &paper.observations, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 5usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 230.0, 140.0, "Probability plot", "Normal probability paper")
    try chart_svg.append(&writer, &paper.reference, ink)
    try chart_svg.append(&writer, &paper.observations, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let exponential = [4]f64{ 0.0f64, 1.0f64, 2.0f64, 5.0f64 }
    let (exp_paper, exp_error) = chart.probability_plot(exponential[..], .Exponential, 0.0f64, 2.0f64, 0.0f64, 10.0f64, bounds, points[..], line[..], ticks[..])
    if exp_error != ok || exp_paper.probability_ticks.len != 7usize || !near(points[0usize].x, 10.0) || !near(points[3usize].x, 110.0) || !(ticks[3usize].fraction > 0.14 && ticks[3usize].fraction < 0.16) || !near(line[0usize].to.y, 20.0) || !(line[0usize].to.x > 190.0 && line[0usize].to.x < 200.0) { ret chart.Invalid }
    let unsorted = [2]f64{ 1.0f64, 0.0f64 }
    let outside = [2]f64{ -3.0f64, 0.0f64 }
    let (_, empty_error) = chart.probability_plot(normal[..1usize], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, bounds, points[..], line[..], ticks[..])
    let (_, order_error) = chart.probability_plot(unsorted[..], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, bounds, points[..], line[..], ticks[..])
    let (_, outside_error) = chart.probability_plot(outside[..], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, bounds, points[..], line[..], ticks[..])
    let (_, scale_error) = chart.probability_plot(normal[..], .Normal, 0.0f64, 0.0f64, -2.5f64, 2.5f64, bounds, points[..], line[..], ticks[..])
    let (_, domain_error) = chart.probability_plot(normal[..], .Normal, 0.0f64, 1.0f64, 2.5f64, 2.5f64, bounds, points[..], line[..], ticks[..])
    let (_, fit_error) = chart.probability_plot(normal[..], .Normal, 100.0f64, 1.0f64, -2.5f64, 2.5f64, bounds, points[..], line[..], ticks[..])
    let (_, bounds_error) = chart.probability_plot(normal[..], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, geometry.rect(0.0, 0.0, 0.0, 100.0), points[..], line[..], ticks[..])
    let (_, point_error) = chart.probability_plot(normal[..], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, bounds, points[..3usize], line[..], ticks[..])
    let (_, line_error) = chart.probability_plot(normal[..], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, bounds, points[..], line[..0usize], ticks[..])
    let (_, tick_error) = chart.probability_plot(normal[..], .Normal, 0.0f64, 1.0f64, -2.5f64, 2.5f64, bounds, points[..], line[..], ticks[..6usize])
    if empty_error != chart.Empty || order_error != chart.Invalid || outside_error != chart.Invalid || scale_error != chart.Invalid || domain_error != chart.Invalid || fit_error != chart.Invalid || bounds_error != chart.Invalid || point_error != chart.TooLarge || line_error != chart.TooLarge || tick_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart probability plot ok\n")
    ret ok
}
