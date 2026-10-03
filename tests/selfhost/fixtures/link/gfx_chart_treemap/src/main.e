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
    let parents = [7]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 2usize, 2usize }
    let weights = [7]f32{ 0.0, 0.0, 0.0, 4.0, 2.0, 3.0, 1.0 }
    var totals: [7]f64 = zero
    var rects: [7]geometry.Rect = zero
    var storage: [7]chart.Layout = zero
    let bounds = geometry.rect(0.0, 0.0, 100.0, 60.0)
    let (layers, layout_error) = chart.treemap(parents[..], weights[..], bounds, totals[..], rects[..], storage[..])
    if layout_error != ok || layers.len != 7usize || f32(totals[0usize]) != 10.0 || f32(totals[1usize]) != 6.0 || f32(totals[2usize]) != 4.0 || layers[1usize].bars.len != 0usize || layers[3usize].bars.len != 1usize || !near(rects[1usize].width, 60.0) || !near(rects[2usize].x, 60.0) || !near(rects[3usize].width, 40.0) || !near(rects[4usize].x, 40.0) || !near(rects[5usize].height, 45.0) || !near(rects[6usize].y, 45.0) { ret chart.Invalid }
    let invalid_parent = [7]usize{ 0usize, 0usize, 4usize, 1usize, 1usize, 2usize, 2usize }
    let (_, parent_error) = chart.treemap(invalid_parent[..], weights[..], bounds, totals[..], rects[..], storage[..])
    if parent_error != chart.Invalid { ret chart.Invalid }
    let invalid_weight = [7]f32{ 0.0, 1.0, 0.0, 4.0, 2.0, 3.0, 1.0 }
    let (_, weight_error) = chart.treemap(parents[..], invalid_weight[..], bounds, totals[..], rects[..], storage[..])
    if weight_error != chart.Invalid { ret chart.Invalid }
    let zero_weights = [7]f32{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 }
    let (_, zero_error) = chart.treemap(parents[..], zero_weights[..], bounds, totals[..], rects[..], storage[..])
    if zero_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.treemap(parents[..], weights[..], bounds, totals[..6usize], rects[..], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (_, mismatch_error) = chart.treemap(parents[..6usize], weights[..], bounds, totals[..], rects[..], storage[..])
    if mismatch_error != chart.Invalid { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 3usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 60.0, "Treemap", "Hierarchical proportional rectangles")
    i = 3usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart treemap ok\n")
    ret ok
}
