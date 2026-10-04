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
    ret delta > -0.01 && delta < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [3]f32{ -1.0, 0.0, 1.0 }
    let y = [3]f32{ 0.0, 0.0, 0.0 }
    let u = [3]f32{ 1.0, 0.0, 0.0 }
    let v = [3]f32{ 0.0, 1.0, 0.0 }
    var tails: [3]chart.Coord = zero
    var arrows: [9]chart.Segment = zero
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let (marks, chart_error) = chart.quiver(x[..], y[..], u[..], v[..], bounds, 20.0, 5.0, tails[..], arrows[..])
    if chart_error != ok || marks.kind != .Rug || marks.segments.len != 6usize || !near(marks.x_min, -1.0) || !near(marks.x_max, 1.0) { ret chart.Invalid }
    if !near(arrows[0usize].from.x, 0.0) || !near(arrows[0usize].to.x, 20.0) || !near(arrows[1usize].to.x, 15.0) || !near(arrows[1usize].to.y, 52.5) { ret chart.Invalid }
    if !near(arrows[3usize].from.x, 50.0) || !near(arrows[3usize].to.y, 30.0) || !near(arrows[4usize].to.x, 52.5) || !near(arrows[5usize].to.x, 47.5) { ret chart.Invalid }
    let bad = [3]f32{ 1.0, -1.0, 0.0 }
    let (_, shape_error) = chart.quiver(x[..], y[..], u[..2usize], v[..], bounds, 20.0, 5.0, tails[..], arrows[..])
    let (_, scale_error) = chart.quiver(x[..], y[..], u[..], v[..], bounds, 0.0, 5.0, tails[..], arrows[..])
    let (_, capacity_error) = chart.quiver(x[..], y[..], u[..], v[..], bounds, 20.0, 5.0, tails[..], arrows[..8usize])
    let (_, bounds_error) = chart.quiver(x[..], y[..], u[..], v[..], geometry.rect(0.0, 0.0, 0.0, 100.0), 20.0, 5.0, tails[..], arrows[..])
    let (negative, negative_error) = chart.quiver(x[..], y[..], bad[..], v[..], bounds, 20.0, 5.0, tails[..], arrows[..])
    if shape_error != chart.Invalid || scale_error != chart.Invalid || capacity_error != chart.TooLarge || bounds_error != chart.Invalid || negative_error != ok || negative.segments.len != 6usize { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 6usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Quiver", "Vector field arrows")
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart quiver ok\n")
    ret ok
}
