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
    let bounds = geometry.rect(0.0, 0.0, 100.0, 90.0)
    var totals: [7]f64 = zero
    var depths: [7]usize = zero
    var rects: [7]geometry.Rect = zero
    var storage: [7]chart.Layout = zero
    let (layers, layout_error) = chart.icicle(parents[..], weights[..], bounds, totals[..], depths[..], rects[..], storage[..])
    if layout_error != ok || layers.len != 7usize || !near(f32(totals[0usize]), 10.0) || depths[3usize] != 2usize || !near(rects[0usize].height, 30.0) || !near(rects[1usize].width, 60.0) || !near(rects[2usize].x, 60.0) || !near(rects[3usize].width, 40.0) || !near(rects[4usize].x, 40.0) || !near(rects[5usize].width, 30.0) || !near(rects[6usize].x, 90.0) || !near(rects[6usize].height, 30.0) { ret chart.Invalid }
    let bad_parents = [7]usize{ 0usize, 0usize, 4usize, 1usize, 1usize, 2usize, 2usize }
    let (_, parent_error) = chart.icicle(bad_parents[..], weights[..], bounds, totals[..], depths[..], rects[..], storage[..])
    if parent_error != chart.Invalid { ret chart.Invalid }
    let bad_weights = [7]f32{ 0.0, 1.0, 0.0, 4.0, 2.0, 3.0, 1.0 }
    let (_, weight_error) = chart.icicle(parents[..], bad_weights[..], bounds, totals[..], depths[..], rects[..], storage[..])
    if weight_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.icicle(parents[..], weights[..], bounds, totals[..], depths[..6usize], rects[..], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let zero_leaf = [7]f32{ 0.0, 0.0, 0.0, 4.0, 2.0, 3.0, 0.0 }
    let (zero_layers, zero_error) = chart.icicle(parents[..], zero_leaf[..], bounds, totals[..], depths[..], rects[..], storage[..])
    if zero_error != ok || zero_layers[6usize].bars.len != 0usize { ret chart.Invalid }
    let uneven_parents = [4]usize{ 0usize, 0usize, 1usize, 0usize }
    let uneven_weights = [4]f32{ 0.0, 0.0, 2.0, 3.0 }
    let (uneven, uneven_error) = chart.icicle(uneven_parents[..], uneven_weights[..], bounds, totals[..], depths[..], rects[..], storage[..])
    if uneven_error != ok || uneven.len != 4usize || !near(rects[3usize].x, 40.0) || !near(rects[3usize].height, 60.0) { ret chart.Invalid }
    let (again, again_error) = chart.icicle(parents[..], weights[..], bounds, totals[..], depths[..], rects[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 10usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < again.len {
        try chart_scene.append(a, &builder, &again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 90.0, "Icicle", "Hierarchy in proportional depth bands")
    i = 0usize
    while i < again.len {
        try chart_svg.append(&writer, &again[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart icicle ok\n")
    ret ok
}
