use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.02 && b - a < 0.02 }

fn main(a: *mem.Arena, args: []str) -> err {
    let columns = [2]f32{ 2.0, 1.0 }
    let rows = [2]f32{ 1.0, 3.0 }
    let bounds = geometry.rect(10.0, 20.0, 230.0, 140.0)
    var panels: [4]geometry.Rect = zero
    let (placed, grid_error) = chart.plot_grid(bounds, columns[..], rows[..], 10.0, 20.0, panels[..])
    if grid_error != ok || placed.len != 4usize || !near(placed[0usize].width, 146.667) || !near(placed[1usize].x, 166.667) || !near(placed[1usize].width, 73.333) || !near(placed[2usize].y, 70.0) || !near(placed[2usize].height, 90.0) || !near(placed[3usize].x + placed[3usize].width, 240.0) || !near(placed[3usize].y + placed[3usize].height, 160.0) { ret chart.Invalid }
    let scatter_x = [3]f32{ 1.0, 2.0, 3.0 }
    let scatter_y = [3]f32{ 2.0, 4.0, 3.0 }
    let bar_x = [3]f32{ 0.0, 1.0, 2.0 }
    let bar_y = [3]f32{ 2.0, 3.0, 4.0 }
    var scatter_points: [3]chart.Coord = zero
    var bar_rects: [3]geometry.Rect = zero
    var unused_lines: [1]chart.Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    var unused_points: [1]chart.Coord = zero
    let scatter_spec = chart.spec(.Scatter, placed[0usize], scatter_x[..], scatter_y[..])
    let bar_spec = chart.spec(.Bar, placed[1usize], bar_x[..], bar_y[..])
    let (scatter, scatter_error) = chart.layout(&scatter_spec, scatter_points[..], unused_lines[..0usize], unused_bars[..0usize])
    let (bars, bars_error) = chart.layout(&bar_spec, unused_points[..0usize], unused_lines[..0usize], bar_rects[..])
    if scatter_error != ok || bars_error != ok || !near(scatter.coords[0usize].x, placed[0usize].x) || bars.bars[2usize].x + bars.bars[2usize].width >= placed[1usize].x + placed[1usize].width { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &scatter, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &bars, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) < 6usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 260.0, 180.0, "Plot grid", "Independent scatter and bars")
    try chart_svg.append(&writer, &scatter, blue)
    try chart_svg.append(&writer, &bars, blue)
    try chart_svg.finish(&writer)
    let output = io.memory_bytes(&held)
    if !str.contains(output, "<rect") || !str.contains(output, "</svg>") { ret chart.Invalid }
    let (_, short_error) = chart.plot_grid(bounds, columns[..], rows[..], 10.0, 20.0, panels[..3usize])
    let bad_columns = [2]f32{ 1.0, 0.0 }
    let (_, weight_error) = chart.plot_grid(bounds, bad_columns[..], rows[..], 10.0, 20.0, panels[..])
    let (_, gap_error) = chart.plot_grid(bounds, columns[..], rows[..], 230.0, 20.0, panels[..])
    let (_, negative_error) = chart.plot_grid(bounds, columns[..], rows[..], -1.0, 20.0, panels[..])
    let (_, empty_error) = chart.plot_grid(bounds, columns[..0usize], rows[..], 10.0, 20.0, panels[..])
    if short_error != chart.TooLarge || weight_error != chart.Invalid || gap_error != chart.Invalid || negative_error != chart.Invalid || empty_error != chart.Empty { ret chart.Invalid }
    try io.print("gfx chart plot grid ok\n")
    ret ok
}
