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
    let shares = [3]f32{ 1.0, 1.0, 2.0 }
    var cells: [8]geometry.Rect = zero
    var layers: [3]chart.Layout = zero
    let (waffle, waffle_error) = chart.waffle(shares[..], geometry.rect(0.0, 0.0, 80.0, 40.0), 4usize, 2usize, 1.0, cells[..], layers[..])
    if waffle_error != ok || waffle.len != 3usize || waffle[0].kind != .Bar || waffle[0].bars.len != 2usize || waffle[1].bars.len != 2usize || waffle[2].bars.len != 4usize || !near(cells[0usize].x, 0.5) || !near(cells[0usize].y, 20.5) || !near(cells[4usize].y, 0.5) || !near(cells[0usize].width, 19.0) { ret chart.Invalid }
    let zero_share = [2]f32{ 0.0, 0.0 }
    let (_, zero_error) = chart.waffle(zero_share[..], geometry.rect(0.0, 0.0, 80.0, 40.0), 4usize, 2usize, 1.0, cells[..], layers[..])
    if zero_error != chart.Invalid { ret chart.Invalid }
    let (_, short_error) = chart.waffle(shares[..], geometry.rect(0.0, 0.0, 80.0, 40.0), 4usize, 2usize, 1.0, cells[..7usize], layers[..])
    if short_error != chart.TooLarge { ret chart.Invalid }
    let (_, gap_error) = chart.waffle(shares[..], geometry.rect(0.0, 0.0, 80.0, 40.0), 4usize, 2usize, 20.0, cells[..], layers[..])
    if gap_error != chart.Invalid { ret chart.Invalid }
    let funnel_values = [3]f32{ 100.0, 60.0, 20.0 }
    var points: [12]chart.Coord = zero
    var funnel_layers: [3]chart.Layout = zero
    let (funnel, funnel_error) = chart.funnel(funnel_values[..], geometry.rect(0.0, 0.0, 100.0, 90.0), 3.0, points[..], funnel_layers[..])
    if funnel_error != ok || funnel.len != 3usize || funnel[0].kind != .Area || !near(points[0usize].x, 0.0) || !near(points[1usize].x, 100.0) || !near(points[2usize].x, 80.0) || !near(points[2usize].y, 27.0) || !near(points[8usize].x, 40.0) || !near(points[10usize].y, 87.0) { ret chart.Invalid }
    let ascending = [2]f32{ 10.0, 20.0 }
    let (_, ascending_error) = chart.funnel(ascending[..], geometry.rect(0.0, 0.0, 100.0, 90.0), 3.0, points[..], layers[..])
    if ascending_error != chart.Invalid { ret chart.Invalid }
    let (_, points_error) = chart.funnel(funnel_values[..], geometry.rect(0.0, 0.0, 100.0, 90.0), 3.0, points[..11usize], layers[..])
    if points_error != chart.TooLarge { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let (waffle_again, again_error) = chart.waffle(shares[..], geometry.rect(0.0, 0.0, 80.0, 40.0), 4usize, 2usize, 1.0, cells[..], layers[..])
    if again_error != ok { ret again_error }
    var i = 0usize
    while i < waffle_again.len {
        try chart_scene.append(a, &builder, &waffle_again[i], paint.Brush { Solid: paint.rgba(0.1, 0.3, 0.8, 1.0) })
        i += 1usize
    }
    let (funnel_again, funnel_again_error) = chart.funnel(funnel_values[..], geometry.rect(0.0, 0.0, 100.0, 90.0), 3.0, points[..], funnel_layers[..])
    if funnel_again_error != ok { ret funnel_again_error }
    i = 0usize
    while i < funnel_again.len {
        try chart_scene.append(a, &builder, &funnel_again[i], paint.Brush { Solid: paint.rgba(0.8, 0.3, 0.1, 1.0) })
        i += 1usize
    }
    if scene.builder_count(&builder) != 11usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 90.0, "Waffle and funnel", "Composition geometry")
    try chart_svg.append(&writer, &waffle_again[0usize], paint.rgba(0.1, 0.3, 0.8, 1.0))
    try chart_svg.append(&writer, &funnel_again[0usize], paint.rgba(0.8, 0.3, 0.1, 1.0))
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart funnel grid ok\n")
    ret ok
}
