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
    let values = [16]f32{ 7.0, 12.0, 16.0, 11.0, 11.0, 16.0, 20.0, 15.0, 15.0, 20.0, 24.0, 19.0, 19.0, 24.0, 28.0, 23.0 }
    let bounds = geometry.rect(0.0, 0.0, 160.0, 160.0)
    var trend: [16]f32 = zero
    var seasonal: [16]f32 = zero
    var residual: [16]f32 = zero
    var segments: [60]chart.Segment = zero
    var storage: [4]chart.Layout = zero
    let (panels, first, end, chart_error) = chart.decomposition(values[..], 4usize, bounds, 4.0, trend[..], seasonal[..], residual[..], segments[..], storage[..])
    if chart_error != ok || panels.len != 4usize || first != 2usize || end != 14usize { ret chart.Invalid }
    if !near(trend[2usize], 12.0) || !near(trend[13usize], 23.0) || !near(seasonal[0usize], -3.0) || !near(seasonal[1usize], 1.0) || !near(seasonal[2usize], 4.0) || !near(seasonal[3usize], -2.0) || !near(seasonal[8usize], -3.0) || !near(residual[5usize], 0.0) { ret chart.Invalid }
    if panels[0usize].segments.len != 15usize || panels[1usize].segments.len != 11usize || panels[2usize].segments.len != 15usize || panels[3usize].segments.len != 11usize || !near(panels[1usize].segments[0usize].from.x, 21.33333) { ret chart.Invalid }
    let odd = [9]f32{ 3.0, 6.0, 9.0, 6.0, 9.0, 12.0, 9.0, 12.0, 15.0 }
    let (_, odd_first, odd_end, odd_error) = chart.decomposition(odd[..], 3usize, bounds, 4.0, trend[..], seasonal[..], residual[..], segments[..], storage[..])
    if odd_error != ok || odd_first != 1usize || odd_end != 8usize || !near(trend[1usize], 6.0) || !near(seasonal[0usize], -2.0) || !near(seasonal[1usize], 0.0) || !near(seasonal[2usize], 2.0) || !near(residual[4usize], 0.0) { ret chart.Invalid }
    let flat = [8]f32{ 7.0, 7.0, 7.0, 7.0, 7.0, 7.0, 7.0, 7.0 }
    let (flat_panels, _, _, flat_error) = chart.decomposition(flat[..], 4usize, bounds, 4.0, trend[..], seasonal[..], residual[..], segments[..], storage[..])
    if flat_error != ok || !near(flat_panels[0usize].segments[0usize].from.y, 18.5) || !near(seasonal[0usize], 0.0) || !near(residual[3usize], 0.0) { ret chart.Invalid }
    let (_, _, _, period_error) = chart.decomposition(values[..], 0usize, bounds, 4.0, trend[..], seasonal[..], residual[..], segments[..], storage[..])
    let (_, _, _, short_series_error) = chart.decomposition(values[..4usize], 4usize, bounds, 4.0, trend[..], seasonal[..], residual[..], segments[..], storage[..])
    let (_, _, _, capacity_error) = chart.decomposition(values[..], 4usize, bounds, 4.0, trend[..], seasonal[..], residual[..], segments[..15usize], storage[..])
    if period_error != chart.Invalid || short_series_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    let (again, _, _, again_error) = chart.decomposition(values[..], 4usize, bounds, 4.0, trend[..], seasonal[..], residual[..], segments[..], storage[..])
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
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 160.0, 160.0, "Additive decomposition", "Observed, trend, seasonal and remainder")
    i = 0usize
    while i < again.len {
        try chart_svg.append(&writer, &again[i], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart decomposition ok\n")
    ret ok
}
