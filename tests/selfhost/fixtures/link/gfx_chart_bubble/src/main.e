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
    let x = [3]f32{ 1.0, 10.0, 100.0 }
    let y = [3]f32{ 1.0, 10.0, 100.0 }
    let sizes = [3]f32{ 1.0, 4.0, 0.0 }
    var spec = chart.spec(.Bubble, geometry.rect(0.0, 0.0, 100.0, 100.0), x[..], y[..])
    spec.x_scale = chart.Scale { kind: .Log10, reverse: false, linthresh: 1.0 }
    spec.y_scale = chart.Scale { kind: .Log10, reverse: false, linthresh: 1.0 }
    var points: [3]chart.Coord = zero
    var circles: [3]geometry.Rect = zero
    let (marks, marks_error) = chart.bubble(&spec, sizes[..], 10.0, points[..], circles[..])
    if marks_error != ok || marks.kind != .Bubble || marks.bars.len != 3usize || !near(marks.coords[1usize].x, 50.0) || !near(marks.coords[1usize].y, 50.0) || !near(marks.bars[0usize].width, 10.0) || !near(marks.bars[1usize].width, 20.0) || marks.bars[2usize].width != 0.0 { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: paint.rgba(0.1, 0.3, 0.8, 1.0) })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Bubble", "Area proportional")
    try chart_svg.append(&writer, &marks, paint.rgba(0.1, 0.3, 0.8, 1.0))
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<circle") || !str.contains(svg, "r=\"10") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let negative = [3]f32{ 1.0, -1.0, 2.0 }
    let (_, negative_error) = chart.bubble(&spec, negative[..], 10.0, points[..], circles[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let zeros = [3]f32{ 0.0, 0.0, 0.0 }
    let (_, zeros_error) = chart.bubble(&spec, zeros[..], 10.0, points[..], circles[..])
    if zeros_error != chart.Invalid { ret chart.Invalid }
    let (_, short_error) = chart.bubble(&spec, sizes[..], 10.0, points[..], circles[..2usize])
    if short_error != chart.TooLarge { ret chart.Invalid }
    let (_, radius_error) = chart.bubble(&spec, sizes[..], 0.0, points[..], circles[..])
    if radius_error != chart.Invalid { ret chart.Invalid }
    let (_, direct_error) = chart.layout(&spec, points[..], zero, circles[..])
    if direct_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart bubble ok\n")
    ret ok
}
