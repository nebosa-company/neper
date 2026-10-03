use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool {
    let difference = a - b
    ret difference > -0.00001f64 && difference < 0.00001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [4]f32{ 1.0, 2.0, 3.0, 4.0 }
    let bounds = geometry.rect(0.0, 0.0, 160.0, 160.0)
    var acf: [3]f64 = zero
    var pacf: [3]f64 = zero
    var coefficients: [3]f64 = zero
    var next: [3]f64 = zero
    var stems: [5]chart.Segment = zero
    var guides: [6]chart.Segment = zero
    var storage: [2]chart.Layout = zero
    let (panels, guide_marks, chart_error) = chart.correlogram(values[..], 2usize, bounds, 8.0, acf[..], pacf[..], coefficients[..], next[..], stems[..], guides[..], storage[..])
    if chart_error != ok || panels.len != 2usize || guide_marks.segments.len != 6usize { ret chart.Invalid }
    if !near(acf[0usize], 1.0f64) || !near(acf[1usize], 0.25f64) || !near(acf[2usize], -0.3f64) || !near(pacf[1usize], 0.25f64) || !near(pacf[2usize], -0.3866666667f64) { ret chart.Invalid }
    if panels[0usize].segments.len != 3usize || panels[1usize].segments.len != 2usize || panels[0usize].segments[0usize].to.y != 0.0 || panels[1usize].segments[0usize].from.y != 122.0 { ret chart.Invalid }
    let flat = [4]f32{ 1.0, 1.0, 1.0, 1.0 }
    let (_, _, flat_error) = chart.correlogram(flat[..], 2usize, bounds, 8.0, acf[..], pacf[..], coefficients[..], next[..], stems[..], guides[..], storage[..])
    let (_, _, lag_error) = chart.correlogram(values[..], 4usize, bounds, 8.0, acf[..], pacf[..], coefficients[..], next[..], stems[..], guides[..], storage[..])
    let (_, _, capacity_error) = chart.correlogram(values[..], 2usize, bounds, 8.0, acf[..], pacf[..], coefficients[..], next[..], stems[..4usize], guides[..], storage[..])
    if flat_error != chart.Invalid || lag_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    let (again, rules, again_error) = chart.correlogram(values[..], 2usize, bounds, 8.0, acf[..], pacf[..], coefficients[..], next[..], stems[..], guides[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &rules, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &again[0usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &again[1usize], paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 11usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 160.0, 160.0, "ACF/PACF correlogram", "Autocorrelation and partial autocorrelation")
    try chart_svg.append(&writer, &rules, blue)
    try chart_svg.append(&writer, &again[0usize], blue)
    try chart_svg.append(&writer, &again[1usize], blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart correlogram ok\n")
    ret ok
}
