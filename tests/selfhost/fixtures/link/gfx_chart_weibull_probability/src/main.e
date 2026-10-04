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
    // NIST's 20-unit, 500-hour Type-I censored Weibull example.
    let failures = [10]f64{ 54.0f64, 187.0f64, 216.0f64, 240.0f64, 244.0f64, 335.0f64, 361.0f64, 373.0f64, 375.0f64, 386.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 200.0, 100.0)
    var points: [10]chart.Coord = zero
    var line: [1]chart.Segment = zero
    var ticks: [7]chart.Tick = zero
    let (paper, result) = chart.weibull_probability_plot(failures[..], 20usize, 1.5f64, 500.0f64, 50.0f64, 800.0f64, bounds, points[..], line[..], ticks[..])
    if result != ok || paper.observations.kind != .Scatter || paper.reference.kind != .Line || paper.observations.coords.len != 10usize || paper.reference.segments.len != 1usize || paper.probability_ticks.len != 7usize { ret chart.Invalid }
    if !(points[0usize].x < points[1usize].x && points[1usize].x < points[9usize].x) || !(points[0usize].y > points[1usize].y && points[1usize].y > points[9usize].y) { ret chart.Invalid }
    if !near(ticks[0usize].value, 0.01) || !near(ticks[0usize].fraction, 0.0) || !near(ticks[3usize].value, 0.5) || !near(ticks[6usize].fraction, 1.0) { ret chart.Invalid }
    if !(line[0usize].from.x >= bounds.x && line[0usize].to.x <= bounds.x + bounds.width && line[0usize].from.y > line[0usize].to.y) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &paper.reference, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &paper.observations, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 11usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 230.0, 140.0, "Weibull probability plot", "Type-I censored reliability sample")
    try chart_svg.append(&writer, &paper.reference, ink)
    try chart_svg.append(&writer, &paper.observations, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, complete_error) = chart.weibull_probability_plot(failures[..], failures.len, 1.5f64, 500.0f64, 50.0f64, 800.0f64, bounds, points[..], line[..], ticks[..])
    let (_, empty_error) = chart.weibull_probability_plot(failures[..1usize], 20usize, 1.5f64, 500.0f64, 50.0f64, 800.0f64, bounds, points[..], line[..], ticks[..])
    let (_, count_error) = chart.weibull_probability_plot(failures[..], 9usize, 1.5f64, 500.0f64, 50.0f64, 800.0f64, bounds, points[..], line[..], ticks[..])
    let (_, shape_error) = chart.weibull_probability_plot(failures[..], 20usize, 0.0f64, 500.0f64, 50.0f64, 800.0f64, bounds, points[..], line[..], ticks[..])
    let (_, scale_error) = chart.weibull_probability_plot(failures[..], 20usize, 1.5f64, 0.0f64, 50.0f64, 800.0f64, bounds, points[..], line[..], ticks[..])
    let (_, domain_error) = chart.weibull_probability_plot(failures[..], 20usize, 1.5f64, 500.0f64, 0.0f64, 800.0f64, bounds, points[..], line[..], ticks[..])
    let (_, point_error) = chart.weibull_probability_plot(failures[..], 20usize, 1.5f64, 500.0f64, 50.0f64, 800.0f64, bounds, points[..9usize], line[..], ticks[..])
    let (_, line_error) = chart.weibull_probability_plot(failures[..], 20usize, 1.5f64, 500.0f64, 50.0f64, 800.0f64, bounds, points[..], line[..0usize], ticks[..])
    let (_, tick_error) = chart.weibull_probability_plot(failures[..], 20usize, 1.5f64, 500.0f64, 50.0f64, 800.0f64, bounds, points[..], line[..], ticks[..6usize])
    if complete_error != ok || empty_error != chart.Empty || count_error != chart.Invalid || shape_error != chart.Invalid || scale_error != chart.Invalid || domain_error != chart.Invalid || point_error != chart.TooLarge || line_error != chart.TooLarge || tick_error != chart.TooLarge { ret chart.Invalid }
    var many: [100]f64 = zero
    var many_points: [100]chart.Coord = zero
    var i = 0usize
    while i < many.len {
        many[i] = f64(i + 1usize)
        i += 1usize
    }
    let (wide, wide_error) = chart.weibull_probability_plot(many[..], many.len, 1.5f64, 50.0f64, 1.0f64, 100.0f64, bounds, many_points[..], line[..], ticks[..])
    if wide_error != ok || many_points[0usize].y > bounds.y + bounds.height || many_points[99usize].y < bounds.y || !(wide.probability_ticks[0usize].fraction > 0.0 && wide.probability_ticks[6usize].fraction < 1.0) { ret chart.Invalid }
    try io.print("gfx chart weibull probability ok\n")
    ret ok
}
