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
    let y = [3]f32{ 0.0, 2.0, -2.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 10.0)
    var points: [40]chart.Coord = zero
    var storage: [10]chart.HorizonPatch = zero
    let (patches, layout_error) = chart.horizon(x[..], y[..], 0.0, 1.0, 2usize, bounds, points[..], storage[..])
    if layout_error != ok || patches.len != 9usize || patches[0usize].band != 0usize || patches[0usize].negative || patches[4usize].band != 1usize || patches[4usize].negative || patches[8usize].band != 1usize || !patches[8usize].negative { ret chart.Invalid }
    if !near(patches[0usize].layout.coords[0usize].x, 0.0) || !near(patches[0usize].layout.coords[2usize].x, 25.0) || !near(patches[0usize].layout.coords[2usize].y, 0.0) || !near(patches[8usize].layout.coords[0usize].x, 87.5) || !near(patches[8usize].layout.coords[2usize].x, 100.0) { ret chart.Invalid }
    let flat = [3]f32{ 0.0, 0.0, 0.0 }
    let (empty_marks, flat_error) = chart.horizon(x[..], flat[..], 0.0, 1.0, 2usize, bounds, points[..], storage[..])
    if flat_error != ok || empty_marks.len != 0usize { ret chart.Invalid }
    let unsorted = [3]f32{ 0.0, 2.0, 1.0 }
    let (_, order_error) = chart.horizon(unsorted[..], y[..], 0.0, 1.0, 2usize, bounds, points[..], storage[..])
    if order_error != chart.Invalid { ret chart.Invalid }
    let outside = [3]f32{ 0.0, 3.0, -2.0 }
    let (_, range_error) = chart.horizon(x[..], outside[..], 0.0, 1.0, 2usize, bounds, points[..], storage[..])
    if range_error != chart.Invalid { ret chart.Invalid }
    let (_, band_error) = chart.horizon(x[..], y[..], 0.0, 1.0, 0usize, bounds, points[..], storage[..])
    if band_error != chart.Invalid { ret chart.Invalid }
    let (_, storage_error) = chart.horizon(x[..], y[..], 0.0, 1.0, 2usize, bounds, points[..4usize], storage[..1usize])
    if storage_error != chart.TooLarge { ret chart.Invalid }
    let irregular = [3]f32{ 0.0, 1.0, 4.0 }
    let (irregular_marks, irregular_error) = chart.horizon(irregular[..], y[..], 0.0, 1.0, 2usize, bounds, points[..], storage[..])
    if irregular_error != ok || irregular_marks.len != 9usize || !near(irregular_marks[0usize].layout.coords[2usize].x, 12.5) { ret chart.Invalid }
    let (again, again_error) = chart.horizon(x[..], y[..], 0.0, 1.0, 2usize, bounds, points[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    let red = paint.rgba(0.85, 0.25, 0.3, 1.0)
    var i = 0usize
    while i < again.len {
        var ink = blue
        if again[i].negative { ink = red }
        try chart_scene.append(a, &builder, &again[i].layout, paint.Brush { Solid: ink })
        i += 1usize
    }
    if scene.builder_count(&builder) != again.len { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 10.0, "Horizon", "Folded positive and negative bands")
    i = 0usize
    while i < again.len {
        var ink = blue
        if again[i].negative { ink = red }
        try chart_svg.append(&writer, &again[i].layout, ink)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart horizon ok\n")
    ret ok
}
