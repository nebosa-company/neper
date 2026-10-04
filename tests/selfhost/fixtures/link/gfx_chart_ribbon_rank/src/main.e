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
    let values = [9]f32{ 9.0, 5.0, 1.0, 4.0, 8.0, 2.0, 3.0, 2.0, 10.0 }
    let bounds = geometry.rect(10.0, 20.0, 120.0, 90.0)
    var points: [18]chart.Coord = zero
    var storage: [3]chart.Layout = zero
    let (layers, layout_error) = chart.ribbon_rank(x[..], values[..], 3usize, bounds, 3.0, points[..], storage[..])
    if layout_error != ok || layers.len != 3usize || layers[0usize].kind != .Area || layers[0usize].coords.len != 6usize || !near(points[0usize].x, 10.0) || !near(points[0usize].y, 20.0) || !near(points[1usize].x, 70.0) || !near(points[1usize].y, 51.0) || !near(points[2usize].y, 51.0) || !near(points[3usize].y, 79.0) || !near(points[6usize].y, 51.0) || !near(points[7usize].y, 20.0) || !near(points[8usize].y, 82.0) || !near(points[12usize].y, 82.0) || !near(points[14usize].y, 20.0) { ret chart.Invalid }
    let ties = [9]f32{ 5.0, 5.0, 1.0, 5.0, 5.0, 1.0, 5.0, 5.0, 1.0 }
    let (_, tie_error) = chart.ribbon_rank(x[..], ties[..], 3usize, bounds, 3.0, points[..], storage[..])
    if tie_error != ok || !near(points[0usize].y, 20.0) || !near(points[6usize].y, 51.0) { ret chart.Invalid }
    let duplicate_x = [3]f32{ 0.0, 1.0, 1.0 }
    let (_, x_error) = chart.ribbon_rank(duplicate_x[..], values[..], 3usize, bounds, 3.0, points[..], storage[..])
    if x_error != chart.Invalid { ret chart.Invalid }
    let (_, shape_error) = chart.ribbon_rank(x[..], values[..8usize], 3usize, bounds, 3.0, points[..], storage[..])
    if shape_error != chart.Invalid { ret chart.Invalid }
    let (_, gap_error) = chart.ribbon_rank(x[..], values[..], 3usize, bounds, 45.0, points[..], storage[..])
    if gap_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.ribbon_rank(x[..], values[..], 3usize, bounds, 3.0, points[..17usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < layers.len {
        try chart_scene.append(a, &builder, &layers[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 3usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 140.0, 120.0, "Rank ribbons", "Equal-height ranks over time")
    i = 0usize
    while i < layers.len {
        try chart_svg.append(&writer, &layers[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart ribbon rank ok\n")
    ret ok
}
