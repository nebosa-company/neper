use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.01 && b - a < 0.01 }

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [6]f32{ 1.0, 3.0, 999.0, 6.0, 8.0, 9.0 }
    let y = [6]f32{ 2.0, 5.0, 7.0, 6.0, 999.0, 8.0 }
    let x_present = [6]bool{ true, true, false, true, true, true }
    let y_present = [6]bool{ true, true, true, true, false, true }
    var points: [4]chart.Coord = zero
    var row_ids: [4]usize = zero
    let (scatter, scatter_error) = chart.masked_scatter(x[..], y[..], x_present[..], y_present[..], geometry.rect(20.0, 20.0, 100.0, 80.0), 0.0, 10.0, 0.0, 10.0, points[..], row_ids[..])
    if scatter_error != ok || scatter.omitted != 2usize || row_ids[2usize] != 3usize { ret chart.Invalid }
    let (hit, found, hit_error) = chart.hit_scatter(&scatter.marks, scatter.row_ids, chart.Coord { x: 82.0, y: 51.0 }, 7.0)
    if hit_error != ok || !found || hit.mark_index != 2usize || hit.source_row != 3usize || hit.distance_squared != 5.0f64 { ret chart.Invalid }
    let (_, far_found, far_error) = chart.hit_scatter(&scatter.marks, scatter.row_ids, chart.Coord { x: 0.0, y: 0.0 }, 5.0)
    if far_error != ok || far_found { ret chart.Invalid }
    var outline_storage: [1]geometry.Rect = zero
    let (outline, outline_error) = chart.selected_point_outline(&scatter.marks, hit.mark_index, 5.0, outline_storage[..])
    if outline_error != ok || outline.kind != .Box || !near(outline.bars[0usize].x, 72.0) || !near(outline.bars[0usize].y, 44.0) || !near(outline.bars[0usize].width, 16.0) { ret chart.Invalid }
    let (_, short_error) = chart.selected_point_outline(&scatter.marks, hit.mark_index, 5.0, outline_storage[..0usize])
    let (_, index_error) = chart.selected_point_outline(&scatter.marks, 9usize, 5.0, outline_storage[..])
    let (_, _, rows_error) = chart.hit_scatter(&scatter.marks, scatter.row_ids[..2usize], chart.Coord { x: 80.0, y: 52.0 }, 7.0)
    if short_error != chart.TooLarge || index_error != chart.Invalid || rows_error != chart.Invalid { ret chart.Invalid }
    var tied_points = [2]chart.Coord{ chart.Coord { x: 40.0, y: 40.0 }, chart.Coord { x: 40.0, y: 40.0 } }
    let tied = chart.Layout { kind: .Scatter, coords: tied_points[..], segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    let (tie, tie_found, tie_error) = chart.hit_scatter(&tied, row_ids[..0usize], chart.Coord { x: 40.0, y: 40.0 }, 0.0)
    if tie_error != ok || !tie_found || tie.mark_index != 0usize || tie.source_row != 0usize { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.3, 0.1, 1.0)
    let (made, builder_error) = scene.builder(a, 12usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &scatter.marks, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &outline, paint.Brush { Solid: orange })
    if scene.builder_count(&builder) != 5usize { ret chart.Invalid }
    let descriptions = [4]str{ "Row 0", "Row 1 & value", "Row 3 selected", "Row 5" }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 150.0, 120.0, "Interactive selection", "Click or focus points")
    try chart_svg.append_selectable_scatter(&writer, &scatter.marks, scatter.row_ids, descriptions[..], blue, orange, "point")
    try chart_svg.finish(&writer)
    let output = io.memory_bytes(&held)
    if !str.contains(output, "href=\"#point-2\"") || !str.contains(output, "data-row-id=\"3\"") || !str.contains(output, "Row 1 &amp; value") || !str.contains(output, "a:target .np-selection-halo") { ret chart.Invalid }
    if chart_svg.append_selectable_scatter(&writer, &scatter.marks, scatter.row_ids, descriptions[..], blue, orange, "bad\"id") != chart_svg.Invalid { ret chart.Invalid }
    if chart_svg.append_selectable_scatter(&writer, &scatter.marks, scatter.row_ids, descriptions[..2usize], blue, orange, "point") != chart_svg.Invalid { ret chart.Invalid }
    try io.print("gfx chart selection ok\n")
    ret ok
}
