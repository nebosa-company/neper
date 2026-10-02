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
    let delta = a - b
    ret delta > -0.01 && delta < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let x = [3]f32{ 0.0, 1.0, 2.0 }
    let lower = [3]f32{ 1.0, 2.0, 1.0 }
    let upper = [3]f32{ 3.0, 4.0, 3.0 }
    var outline: [6]chart.Coord = zero
    let (ribbon, ribbon_error) = chart.band(x[..], lower[..], upper[..], bounds, outline[..])
    if ribbon_error != ok || ribbon.kind != .Band || ribbon.coords.len != 6usize || !near(ribbon.coords[1].x, 50.0) || !near(ribbon.coords[1].y, 0.0) || !near(ribbon.coords[4].y, 66.66667) { ret chart.Invalid }
    let unsorted = [3]f32{ 0.0, 2.0, 1.0 }
    let inverted = [3]f32{ 0.0, 5.0, 0.0 }
    let (_, sorted_error) = chart.band(unsorted[..], lower[..], upper[..], bounds, outline[..])
    if sorted_error != chart.Invalid { ret chart.Invalid }
    let (_, interval_error) = chart.band(x[..], inverted[..], upper[..], bounds, outline[..])
    if interval_error != chart.Invalid { ret chart.Invalid }
    let (_, short_error) = chart.band(x[..], lower[..], upper[..], bounds, outline[..5usize])
    if short_error != chart.TooLarge { ret chart.Invalid }
    let (_, mismatch_error) = chart.band(x[..], lower[..], upper[..2usize], bounds, outline[..])
    if mismatch_error != chart.Invalid { ret chart.Invalid }
    let position = [2]f32{ 0.0, 1.0 }
    let low = [2]f32{ 1.0, 2.0 }
    let high = [2]f32{ 3.0, 4.0 }
    var points: [4]chart.Coord = zero
    var lines: [2]chart.Segment = zero
    let (dumbbells, dumbbell_error) = chart.dumbbell(position[..], low[..], high[..], bounds, points[..], lines[..])
    if dumbbell_error != ok || dumbbells.kind != .Dumbbell || dumbbells.coords.len != 4usize || dumbbells.segments.len != 2usize || !near(dumbbells.coords[0].x, 0.0) || !near(dumbbells.coords[1].x, 66.66667) || !near(dumbbells.coords[2].y, 0.0) { ret chart.Invalid }
    let bad_high = [2]f32{ 0.0, 4.0 }
    let (_, bad_dumbbell) = chart.dumbbell(position[..], low[..], bad_high[..], bounds, points[..], lines[..])
    if bad_dumbbell != chart.Invalid { ret chart.Invalid }
    let (_, small_dumbbell) = chart.dumbbell(position[..], low[..], high[..], bounds, points[..3usize], lines[..])
    if small_dumbbell != chart.TooLarge { ret chart.Invalid }
    let constant_position = [1]f32{ 1.0 }
    let constant_value = [1]f32{ 2.0 }
    let (constant_plot, constant_error) = chart.dumbbell(constant_position[..], constant_value[..], constant_value[..], bounds, points[..], lines[..])
    if constant_error != ok || !near(constant_plot.coords[0].x, 50.0) || !near(constant_plot.coords[0].y, 50.0) { ret chart.Invalid }
    let (_, empty_error) = chart.dumbbell(position[..0usize], low[..0usize], high[..0usize], bounds, points[..], lines[..])
    if empty_error != chart.Empty { ret chart.Invalid }
    var spec = chart.spec(.Band, bounds, x[..], lower[..])
    var spare_lines: [2]chart.Segment = zero
    var spare_bars: [3]geometry.Rect = zero
    let (_, generic_error) = chart.layout(&spec, outline[..], spare_lines[..], spare_bars[..])
    if generic_error != chart.Invalid { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let brush = paint.Brush { Solid: paint.rgba(0.1, 0.3, 0.8, 1.0) }
    try chart_scene.append(a, &builder, &ribbon, brush)
    try chart_scene.append(a, &builder, &dumbbells, brush)
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_svg.begin(&writer, 100.0, 100.0, "Intervals", "Band and dumbbells")
    try chart_svg.append(&writer, &ribbon, ink)
    try chart_svg.append(&writer, &dumbbells, ink)
    try chart_svg.finish(&writer)
    let output = io.memory_bytes(&held)
    if !str.contains(output, "<path d=\"M") || !str.contains(output, "<line") || !str.contains(output, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart intervals ok\n")
    ret ok
}
