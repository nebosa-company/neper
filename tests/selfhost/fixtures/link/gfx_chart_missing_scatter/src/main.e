use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.001f32 && b - a < 0.001f32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [6]f32{ 1.0, 999.0, 3.0, 4.0, 5.0, 6.0 }
    let y = [6]f32{ 1.0, 2.0, 999.0, 4.0, 5.0, 6.0 }
    let x_present = [6]bool{ true, false, true, true, false, true }
    let y_present = [6]bool{ true, true, false, true, true, true }
    let bounds = geometry.rect(20.0, 30.0, 200.0, 100.0)
    var points: [3]chart.Coord = zero
    var row_ids: [3]usize = zero
    let (scatter, scatter_error) = chart.masked_scatter(x[..], y[..], x_present[..], y_present[..], bounds, 0.0, 10.0, 0.0, 10.0, points[..], row_ids[..])
    if scatter_error != ok || scatter.marks.coords.len != 3usize || scatter.row_ids.len != 3usize || scatter.omitted != 3usize { ret chart.Invalid }
    if row_ids[0usize] != 0usize || row_ids[1usize] != 3usize || row_ids[2usize] != 5usize || !near(points[0usize].x, 40.0) || !near(points[0usize].y, 120.0) || !near(points[1usize].x, 100.0) || !near(points[2usize].y, 70.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &scatter.marks, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Masked scatter", "Three complete rows")
    try chart_svg.append(&writer, &scatter.marks, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") { ret chart.Invalid }
    let (_, short_error) = chart.masked_scatter(x[..], y[..], x_present[..], y_present[..], bounds, 0.0, 10.0, 0.0, 10.0, points[..2usize], row_ids[..])
    let (_, ids_error) = chart.masked_scatter(x[..], y[..], x_present[..], y_present[..], bounds, 0.0, 10.0, 0.0, 10.0, points[..], row_ids[..2usize])
    let (_, mask_error) = chart.masked_scatter(x[..], y[..], x_present[..5usize], y_present[..], bounds, 0.0, 10.0, 0.0, 10.0, points[..], row_ids[..])
    let observed_x = [6]bool{ true, true, true, true, false, true }
    let (_, observed_error) = chart.masked_scatter(x[..], y[..], observed_x[..], y_present[..], bounds, 0.0, 10.0, 0.0, 10.0, points[..], row_ids[..])
    let none = [6]bool{ false, false, false, false, false, false }
    let (blank, blank_error) = chart.masked_scatter(x[..], y[..], none[..], y_present[..], bounds, 0.0, 10.0, 0.0, 10.0, points[..0usize], row_ids[..0usize])
    if short_error != chart.TooLarge || ids_error != chart.TooLarge || mask_error != chart.Invalid || observed_error != chart.Invalid || blank_error != ok || blank.marks.coords.len != 0usize || blank.omitted != 6usize { ret chart.Invalid }
    try io.print("gfx chart missing scatter ok\n")
    ret ok
}
