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
    let left = [2]f32{ 2.0, 4.0 }
    let right = [2]f32{ 3.0, 1.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    var bars: [4]geometry.Rect = zero
    var storage: [2]chart.Layout = zero
    let (layers, layout_error) = chart.population_pyramid(left[..], right[..], bounds, 20.0, 0.0, bars[..], storage[..])
    if layout_error != ok || layers.len != 2usize || layers[0usize].bars.len != 2usize || layers[1usize].bars.len != 2usize || !near(layers[0usize].x_min, -4.0) || !near(layers[1usize].x_max, 4.0) || !near(bars[0usize].x, 20.0) || !near(bars[0usize].y, 50.0) || !near(bars[0usize].width, 20.0) || !near(bars[1usize].x, 0.0) || !near(bars[2usize].x, 60.0) || !near(bars[2usize].width, 30.0) || !near(bars[3usize].y, 0.0) { ret chart.Invalid }
    let (_, length_error) = chart.population_pyramid(left[..1usize], right[..], bounds, 20.0, 0.0, bars[..], storage[..])
    if length_error != chart.Invalid { ret chart.Invalid }
    let negative = [2]f32{ 2.0, -1.0 }
    let (_, negative_error) = chart.population_pyramid(negative[..], right[..], bounds, 20.0, 0.0, bars[..], storage[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let zeros = [2]f32{ 0.0, 0.0 }
    let (_, zero_error) = chart.population_pyramid(zeros[..], zeros[..], bounds, 20.0, 0.0, bars[..], storage[..])
    if zero_error != chart.Invalid { ret chart.Invalid }
    let (_, gutter_error) = chart.population_pyramid(left[..], right[..], bounds, 100.0, 0.0, bars[..], storage[..])
    if gutter_error != chart.Invalid { ret chart.Invalid }
    let (_, gap_error) = chart.population_pyramid(left[..], right[..], bounds, 20.0, 50.0, bars[..], storage[..])
    if gap_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.population_pyramid(left[..], right[..], bounds, 20.0, 0.0, bars[..3usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.4, 0.1, 1.0)
    try chart_scene.append(a, &builder, &layers[0usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &layers[1usize], paint.Brush { Solid: orange })
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Population pyramid", "Two age series on a shared mirrored scale")
    try chart_svg.append(&writer, &layers[0usize], blue)
    try chart_svg.append(&writer, &layers[1usize], orange)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart population pyramid ok\n")
    ret ok
}
