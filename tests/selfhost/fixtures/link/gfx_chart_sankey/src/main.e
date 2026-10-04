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
    let columns = [4]usize{ 0usize, 0usize, 1usize, 1usize }
    let sources = [4]usize{ 0usize, 0usize, 1usize, 1usize }
    let targets = [4]usize{ 2usize, 3usize, 2usize, 3usize }
    let values = [4]f32{ 3.0, 1.0, 2.0, 4.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    var nodes: [4]chart.SankeyNode = zero
    var rects: [4]geometry.Rect = zero
    var points: [40]chart.Coord = zero
    var storage: [8]chart.Layout = zero
    let (layers, layout_error) = chart.sankey(columns[..], 2usize, sources[..], targets[..], values[..], bounds, 10.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if layout_error != ok || layers.len != 8usize || layers[0usize].kind != .Area || layers[0usize].coords.len != 10usize || layers[4usize].kind != .Bar || layers[4usize].bars.len != 1usize || !near(rects[0usize].height, 36.0) || !near(rects[1usize].y, 46.0) || !near(rects[2usize].x, 90.0) || !near(rects[2usize].height, 45.0) || !near(rects[3usize].y, 55.0) || !near(points[0usize].x, 10.0) || !near(points[0usize].y, 0.0) || !near(points[5usize].x, 90.0) || !near(points[5usize].y, 27.0) || !near(f32(nodes[0usize].out_used), 4.0) || !near(f32(nodes[2usize].in_used), 5.0) { ret chart.Invalid }
    let bad_targets = [4]usize{ 2usize, 3usize, 0usize, 3usize }
    let (_, backward_error) = chart.sankey(columns[..], 2usize, sources[..], bad_targets[..], values[..], bounds, 10.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if backward_error != chart.Invalid { ret chart.Invalid }
    let negative = [4]f32{ 3.0, -1.0, 2.0, 4.0 }
    let (_, negative_error) = chart.sankey(columns[..], 2usize, sources[..], targets[..], negative[..], bounds, 10.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.sankey(columns[..], 2usize, sources[..], targets[..], values[..], bounds, 10.0, 10.0, 4usize, nodes[..], rects[..], points[..39usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (_, width_error) = chart.sankey(columns[..], 2usize, sources[..], targets[..], values[..], bounds, 50.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if width_error != chart.Invalid { ret chart.Invalid }
    let (_, gap_error) = chart.sankey(columns[..], 2usize, sources[..], targets[..], values[..], bounds, 10.0, 100.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if gap_error != chart.Invalid { ret chart.Invalid }
    let zero_link = [4]f32{ 3.0, 0.0, 2.0, 4.0 }
    let (zero_layers, zero_error) = chart.sankey(columns[..], 2usize, sources[..], targets[..], zero_link[..], bounds, 10.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if zero_error != ok || zero_layers[1usize].kind != .Bar || zero_layers[1usize].bars.len != 0usize { ret chart.Invalid }
    let chain_columns = [3]usize{ 0usize, 1usize, 2usize }
    let chain_sources = [2]usize{ 0usize, 1usize }
    let chain_targets = [2]usize{ 1usize, 2usize }
    let chain_values = [2]f32{ 5.0, 5.0 }
    let (chain, chain_error) = chart.sankey(chain_columns[..], 3usize, chain_sources[..], chain_targets[..], chain_values[..], bounds, 10.0, 0.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if chain_error != ok || chain.len != 5usize || !near(rects[1usize].x, 45.0) || !near(rects[2usize].x, 90.0) || !near(rects[1usize].height, 100.0) || !near(points[10usize].x, 55.0) { ret chart.Invalid }
    let (again, again_error) = chart.sankey(columns[..], 2usize, sources[..], targets[..], values[..], bounds, 10.0, 10.0, 4usize, nodes[..], rects[..], points[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 12usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < again.len {
        try chart_scene.append(a, &builder, &again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 8usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Sankey", "Weighted two-column flows")
    i = 0usize
    while i < again.len {
        try chart_svg.append(&writer, &again[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart sankey ok\n")
    ret ok
}
