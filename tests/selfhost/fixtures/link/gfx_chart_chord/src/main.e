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
    let matrix = [4]f32{ 0.0, 3.0, 1.0, 0.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    var totals: [2]f64 = zero
    var arcs: [2]chart.SunburstArc = zero
    var subarcs: [4]chart.SunburstArc = zero
    var points: [47]chart.Coord = zero
    var storage: [5]chart.Layout = zero
    let (layers, layout_error) = chart.chord(matrix[..], 2usize, bounds, 0.6, 0.0, 4usize, totals[..], arcs[..], subarcs[..], points[..], storage[..])
    if layout_error != ok || layers.len != 5usize || layers[0usize].kind != .Bar || layers[1usize].kind != .Area || layers[1usize].coords.len != 18usize || layers[2usize].kind != .Bar || layers[3usize].coords.len != 10usize {
        ret chart.Invalid
    }
    if !near(f32(totals[0usize]), 3.0) || !near(f32(totals[1usize]), 1.0) || !near(f32(arcs[0usize].end), 3.14159) || !near(f32(arcs[1usize].end), 4.71239) {
        ret chart.Invalid
    }
    if !near(points[0usize].x, 50.0) || !near(points[0usize].y, 20.0) || !near(points[4usize].x, 20.0) || !near(points[18usize].y, 0.0) || !near(points[28usize].x, 0.0) {
        ret chart.Invalid
    }
    let self_matrix = [4]f32{ 2.0, 1.0, 1.0, 0.0 }
    let (self_layers, self_error) = chart.chord(self_matrix[..], 2usize, bounds, 0.6, 0.0, 4usize, totals[..], arcs[..], subarcs[..], points[..], storage[..])
    if self_error != ok || self_layers[0usize].kind != .Area || self_layers[0usize].coords.len != 9usize || self_layers[1usize].coords.len != 18usize { ret chart.Invalid }
    let negative = [4]f32{ 0.0, -3.0, 1.0, 0.0 }
    let (_, negative_error) = chart.chord(negative[..], 2usize, bounds, 0.6, 0.0, 4usize, totals[..], arcs[..], subarcs[..], points[..], storage[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let empty = [4]f32{ 0.0, 0.0, 0.0, 0.0 }
    let (_, empty_error) = chart.chord(empty[..], 2usize, bounds, 0.6, 0.0, 4usize, totals[..], arcs[..], subarcs[..], points[..], storage[..])
    if empty_error != chart.Invalid { ret chart.Invalid }
    let (_, shape_error) = chart.chord(matrix[..3usize], 2usize, bounds, 0.6, 0.0, 4usize, totals[..], arcs[..], subarcs[..], points[..], storage[..])
    if shape_error != chart.Invalid { ret chart.Invalid }
    let (_, gap_error) = chart.chord(matrix[..], 2usize, bounds, 0.6, 4.0, 4usize, totals[..], arcs[..], subarcs[..], points[..], storage[..])
    if gap_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.chord(matrix[..], 2usize, bounds, 0.6, 0.0, 4usize, totals[..], arcs[..], subarcs[..], points[..37usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (again, again_error) = chart.chord(matrix[..], 2usize, bounds, 0.6, 0.0, 4usize, totals[..], arcs[..], subarcs[..], points[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < again.len {
        try chart_scene.append(a, &builder, &again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 3usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Chord", "Asymmetric pair weights")
    i = 0usize
    while i < again.len {
        try chart_svg.append(&writer, &again[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart chord ok\n")
    ret ok
}
