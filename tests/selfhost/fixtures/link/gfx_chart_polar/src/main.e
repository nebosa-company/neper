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
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let values = [2]f32{ 1.0, 1.0 }
    var points: [256]chart.Coord = zero
    var layers: [2]chart.Layout = zero
    let (pie, pie_error) = chart.pie(values[..], bounds, 0.0, points[..], layers[..])
    if pie_error != ok || pie.len != 2usize || pie[0].kind != .Area || pie[0].coords.len != 102usize || !near(pie[0].coords[0usize].x, 50.0) || !near(pie[0].coords[0usize].y, 0.0) || !near(pie[0].coords[25usize].x, 100.0) || !near(pie[0].coords[25usize].y, 50.0) || !near(pie[0].coords[51usize].x, 50.0) || !near(pie[0].coords[51usize].y, 50.0) { ret chart.Invalid }
    let (donut, donut_error) = chart.pie(values[..], bounds, 0.5, points[..], layers[..])
    if donut_error != ok || donut.len != 2usize || !near(donut[0].coords[51usize].y, 75.0) || !near(donut[0].coords[101usize].y, 25.0) { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 2usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &donut[0], paint.Brush { Solid: paint.rgba(0.1, 0.3, 0.8, 1.0) })
    try chart_scene.append(a, &builder, &donut[1], paint.Brush { Solid: paint.rgba(0.9, 0.4, 0.1, 1.0) })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Donut", "Two equal slices")
    try chart_svg.append(&writer, &donut[0], paint.rgba(0.1, 0.3, 0.8, 1.0))
    try chart_svg.append(&writer, &donut[1], paint.rgba(0.9, 0.4, 0.1, 1.0))
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "Donut") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let zeros = [2]f32{ 0.0, 0.0 }
    let (_, zero_error) = chart.pie(zeros[..], bounds, 0.0, points[..], layers[..])
    if zero_error != chart.Invalid { ret chart.Invalid }
    let negative = [2]f32{ 1.0, -1.0 }
    let (_, negative_error) = chart.pie(negative[..], bounds, 0.0, points[..], layers[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let (_, hole_error) = chart.pie(values[..], bounds, 1.0, points[..], layers[..])
    if hole_error != chart.Invalid { ret chart.Invalid }
    let (_, short_error) = chart.pie(values[..], bounds, 0.5, points[..203usize], layers[..])
    if short_error != chart.TooLarge { ret chart.Invalid }
    let (_, layers_error) = chart.pie(values[..], bounds, 0.5, points[..], layers[..1usize])
    if layers_error != chart.TooLarge { ret chart.Invalid }
    let zero_slice = [2]f32{ 1.0, 0.0 }
    let (slices, zero_slice_error) = chart.pie(zero_slice[..], bounds, 0.5, points[..], layers[..])
    if zero_slice_error != ok || slices.len != 2usize || slices[1].coords.len != 6usize { ret chart.Invalid }
    try io.print("gfx chart polar ok\n")
    ret ok
}
