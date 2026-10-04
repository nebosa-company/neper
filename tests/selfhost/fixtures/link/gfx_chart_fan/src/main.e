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
    let x = [3]f32{ 0.0, 1.0, 3.0 }
    let median = [3]f32{ 5.0, 6.0, 8.0 }
    let lower = [6]f32{ 1.0, 2.0, 3.0, 3.0, 4.0, 6.0 }
    let upper = [6]f32{ 9.0, 10.0, 13.0, 7.0, 8.0, 10.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 120.0)
    var outlines: [12]chart.Coord = zero
    var segments: [2]chart.Segment = zero
    var storage: [2]chart.Layout = zero
    let (bands, center, chart_error) = chart.fan(x[..], median[..], lower[..], upper[..], 2usize, bounds, outlines[..], segments[..], storage[..])
    if chart_error != ok || bands.len != 2usize || bands[0usize].coords.len != 6usize || bands[1usize].coords.len != 6usize || center.segments.len != 2usize { ret chart.Invalid }
    if !near(bands[0usize].coords[0usize].y, 40.0) || !near(bands[1usize].coords[0usize].y, 60.0) || !near(bands[1usize].coords[5usize].y, 100.0) || !near(center.segments[0usize].from.y, 80.0) || !near(center.segments[0usize].to.x, 33.33333) { ret chart.Invalid }
    let crossed = [6]f32{ 1.0, 2.0, 3.0, 0.0, 4.0, 6.0 }
    let (_, _, crossing_error) = chart.fan(x[..], median[..], crossed[..], upper[..], 2usize, bounds, outlines[..], segments[..], storage[..])
    let bad_x = [3]f32{ 0.0, 3.0, 1.0 }
    let (_, _, order_error) = chart.fan(bad_x[..], median[..], lower[..], upper[..], 2usize, bounds, outlines[..], segments[..], storage[..])
    let bad_median = [3]f32{ 10.0, 6.0, 8.0 }
    let (_, _, median_error) = chart.fan(x[..], bad_median[..], lower[..], upper[..], 2usize, bounds, outlines[..], segments[..], storage[..])
    let (_, _, capacity_error) = chart.fan(x[..], median[..], lower[..], upper[..], 2usize, bounds, outlines[..6usize], segments[..], storage[..])
    let (_, _, no_bands_error) = chart.fan(x[..], median[..], lower[..], upper[..], 0usize, bounds, outlines[..], segments[..], storage[..])
    if crossing_error != chart.Invalid || order_error != chart.Invalid || median_error != chart.Invalid || capacity_error != chart.TooLarge || no_bands_error != chart.Invalid { ret chart.Invalid }
    let flat = [3]f32{ 7.0, 7.0, 7.0 }
    let (flat_bands, flat_line, flat_error) = chart.fan(x[..], flat[..], flat[..], flat[..], 1usize, bounds, outlines[..], segments[..], storage[..])
    if flat_error != ok || !near(flat_bands[0usize].coords[0usize].y, 60.0) || !near(flat_line.segments[0usize].from.y, 60.0) { ret chart.Invalid }
    let (again, again_line, again_error) = chart.fan(x[..], median[..], lower[..], upper[..], 2usize, bounds, outlines[..], segments[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let pale = paint.rgba(0.7, 0.8, 0.95, 1.0)
    let dark = paint.rgba(0.1, 0.3, 0.7, 1.0)
    try chart_scene.append(a, &builder, &again[0usize], paint.Brush { Solid: pale })
    try chart_scene.append(a, &builder, &again[1usize], paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &again_line, paint.Brush { Solid: dark })
    if scene.builder_count(&builder) != 3usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 120.0, "Forecast fan", "Nested intervals and median")
    try chart_svg.append(&writer, &again[0usize], pale)
    try chart_svg.append(&writer, &again[1usize], dark)
    try chart_svg.append(&writer, &again_line, dark)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart fan ok\n")
    ret ok
}
