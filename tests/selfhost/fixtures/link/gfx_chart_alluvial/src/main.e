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
    let columns = [8]usize{ 0usize, 0usize, 1usize, 1usize, 2usize, 2usize, 3usize, 3usize }
    let sources = [12]usize{ 0usize, 0usize, 1usize, 1usize, 2usize, 2usize, 3usize, 3usize, 4usize, 4usize, 5usize, 5usize }
    let targets = [12]usize{ 2usize, 3usize, 2usize, 3usize, 4usize, 5usize, 5usize, 4usize, 6usize, 7usize, 6usize, 7usize }
    let values = [12]f32{ 35.0, 25.0, 15.0, 25.0, 35.0, 15.0, 25.0, 25.0, 35.0, 25.0, 15.0, 25.0 }
    let bounds = geometry.rect(0.0, 0.0, 160.0, 100.0)
    var nodes: [8]chart.SankeyNode = zero
    var rects: [8]geometry.Rect = zero
    var points: [120]chart.Coord = zero
    var storage: [20]chart.Layout = zero
    let (layers, layout_error) = chart.alluvial(columns[..], 4usize, sources[..], targets[..], values[..], bounds, 20.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if layout_error != ok || layers.len != 20usize || layers[0usize].kind != .Area || layers[0usize].coords.len != 10usize || layers[12usize].kind != .Bar || !near(rects[0usize].height, 54.0) || !near(rects[1usize].y, 64.0) || !near(rects[2usize].x, 46.66667) || !near(rects[4usize].height, 54.0) || !near(rects[6usize].x, 140.0) || !near(f32(nodes[2usize].incoming), f32(nodes[2usize].outgoing)) || !near(f32(nodes[5usize].incoming), f32(nodes[5usize].outgoing)) { ret chart.Invalid }
    let skip_targets = [12]usize{ 4usize, 3usize, 2usize, 3usize, 4usize, 5usize, 5usize, 4usize, 6usize, 7usize, 6usize, 7usize }
    let (_, skip_error) = chart.alluvial(columns[..], 4usize, sources[..], skip_targets[..], values[..], bounds, 20.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if skip_error != chart.Invalid { ret chart.Invalid }
    let unbalanced = [12]f32{ 35.0, 25.0, 15.0, 25.0, 34.0, 15.0, 25.0, 25.0, 35.0, 25.0, 15.0, 25.0 }
    let (_, balance_error) = chart.alluvial(columns[..], 4usize, sources[..], targets[..], unbalanced[..], bounds, 20.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if balance_error != chart.Invalid { ret chart.Invalid }
    let negative = [12]f32{ -35.0, 25.0, 15.0, 25.0, 35.0, 15.0, 25.0, 25.0, 35.0, 25.0, 15.0, 25.0 }
    let (_, negative_error) = chart.alluvial(columns[..], 4usize, sources[..], targets[..], negative[..], bounds, 20.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.alluvial(columns[..], 4usize, sources[..], targets[..], values[..], bounds, 20.0, 10.0, 4usize, nodes[..], rects[..], points[..119usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 20usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 160.0, 100.0, "Alluvial", "Balanced staged flows")
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart alluvial ok\n")
    ret ok
}
