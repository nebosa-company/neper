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
    ret d > -0.01 && d < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [3]f32{ 0.0, 1.0, 2.0 }
    let values = [6]f32{ 2.0, 1.0, 4.0, 2.0, 2.0, 1.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 60.0)
    var totals: [3]f64 = zero
    var cumulative: [3]f64 = zero
    var points: [12]chart.Coord = zero
    var storage: [2]chart.Layout = zero
    let (layers, layout_error) = chart.streamgraph(x[..], values[..], 2usize, bounds, totals[..], cumulative[..], points[..], storage[..])
    if layout_error != ok || layers.len != 2usize || layers[0usize].kind != .Area || layers[0usize].coords.len != 6usize || !near(f32(totals[0usize]), 3.0) || !near(f32(totals[1usize]), 6.0) || !near(points[0usize].y, 25.0) || !near(points[1usize].x, 50.0) || !near(points[1usize].y, 20.0) || !near(points[4usize].y, 60.0) || !near(points[6usize].y, 15.0) || !near(points[7usize].y, 0.0) || !near(f32(cumulative[0usize]), 4.5) { ret chart.Invalid }
    let duplicate_x = [3]f32{ 0.0, 1.0, 1.0 }
    let (_, x_error) = chart.streamgraph(duplicate_x[..], values[..], 2usize, bounds, totals[..], cumulative[..], points[..], storage[..])
    if x_error != chart.Invalid { ret chart.Invalid }
    let negative = [6]f32{ 2.0, -1.0, 4.0, 2.0, 2.0, 1.0 }
    let (_, negative_error) = chart.streamgraph(x[..], negative[..], 2usize, bounds, totals[..], cumulative[..], points[..], storage[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let (_, shape_error) = chart.streamgraph(x[..], values[..5usize], 2usize, bounds, totals[..], cumulative[..], points[..], storage[..])
    if shape_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.streamgraph(x[..], values[..], 2usize, bounds, totals[..], cumulative[..], points[..11usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let empty_values = [6]f32{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
    let (_, empty_error) = chart.streamgraph(x[..], empty_values[..], 2usize, bounds, totals[..], cumulative[..], points[..], storage[..])
    if empty_error != chart.Empty { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 60.0, "Streamgraph", "Centered stacked areas")
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart streamgraph ok\n")
    ret ok
}
