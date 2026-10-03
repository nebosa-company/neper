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
    ret d > -0.05 && d < 0.05
}

fn main(a: *mem.Arena, args: []str) -> err {
    let parents = [7]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 2usize, 2usize }
    let weights = [7]f32{ 0.0, 0.0, 0.0, 4.0, 2.0, 3.0, 1.0 }
    var totals: [7]f64 = zero
    var depths: [7]usize = zero
    var arcs: [7]chart.SunburstArc = zero
    var points: [1024]chart.Coord = zero
    var storage: [7]chart.Layout = zero
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let (rings, ring_error) = chart.sunburst(parents[..], weights[..], bounds, 0.2, totals[..], depths[..], arcs[..], points[..], storage[..])
    if ring_error != ok || rings.len != 7usize || rings[0usize].kind != .Area || rings[3usize].kind != .Area || !near(f32(totals[0usize]), 10.0) || !near(f32(totals[1usize]), 6.0) || depths[0usize] != 0usize || depths[3usize] != 2usize || !near(f32(arcs[1usize].end - arcs[1usize].start), 3.76991) || !near(f32(arcs[3usize].end - arcs[3usize].start), 2.51327) || !near(rings[0usize].coords[0usize].x, 50.0) || !near(rings[0usize].coords[0usize].y, 26.67) || !near(rings[3usize].coords[0usize].y, 0.0) { ret chart.Invalid }
    let bad_parents = [7]usize{ 0usize, 0usize, 4usize, 1usize, 1usize, 2usize, 2usize }
    let (_, parent_error) = chart.sunburst(bad_parents[..], weights[..], bounds, 0.2, totals[..], depths[..], arcs[..], points[..], storage[..])
    if parent_error != chart.Invalid { ret chart.Invalid }
    let bad_weights = [7]f32{ 0.0, 1.0, 0.0, 4.0, 2.0, 3.0, 1.0 }
    let (_, weight_error) = chart.sunburst(parents[..], bad_weights[..], bounds, 0.2, totals[..], depths[..], arcs[..], points[..], storage[..])
    if weight_error != chart.Invalid { ret chart.Invalid }
    let (_, hole_error) = chart.sunburst(parents[..], weights[..], bounds, 1.0, totals[..], depths[..], arcs[..], points[..], storage[..])
    if hole_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.sunburst(parents[..], weights[..], bounds, 0.2, totals[..], depths[..], arcs[..], points[..10usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let zero_leaf = [7]f32{ 0.0, 0.0, 0.0, 4.0, 2.0, 3.0, 0.0 }
    let (zero_rings, zero_error) = chart.sunburst(parents[..], zero_leaf[..], bounds, 0.2, totals[..], depths[..], arcs[..], points[..], storage[..])
    if zero_error != ok || zero_rings[6usize].kind != .Bar || zero_rings[6usize].bars.len != 0usize { ret chart.Invalid }
    var tree_rects: [7]geometry.Rect = zero
    let (tree, tree_error) = chart.treemap(parents[..], weights[..], bounds, totals[..], tree_rects[..], storage[..])
    if tree_error != ok || !near(tree_rects[1usize].width, 60.0) { ret chart.Invalid }
    let (rings_again, again_error) = chart.sunburst(parents[..], weights[..], bounds, 0.2, totals[..], depths[..], arcs[..], points[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 10usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < rings_again.len {
        try chart_scene.append(a, &builder, &rings_again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Sunburst", "Hierarchy in concentric rings")
    i = 0usize
    while i < rings_again.len {
        try chart_svg.append(&writer, &rings_again[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart sunburst ok\n")
    ret ok
}
