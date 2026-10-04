use e.algo.stat
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool { ret a - b < 0.0001f64 && b - a < 0.0001f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let cross_rows = [9]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 1usize, 2usize, 2usize }
    let cross_columns = [9]usize{ 0usize, 1usize, 1usize, 0usize, 1usize, 2usize, 2usize, 1usize, 2usize }
    var counts: [9]u64 = zero
    var cross_row_totals: [3]u64 = zero
    var cross_column_totals: [3]u64 = zero
    var cross_cells: [25]chart.ReportCell = zero
    var cross_work = chart.CrossTabStorage { counts: counts[..], row_totals: cross_row_totals[..], column_totals: cross_column_totals[..], cells: cross_cells[..] }
    let bounds = geometry.rect(20.0, 20.0, 280.0, 180.0)
    let (cross, cross_error) = chart.cross_tab_report(cross_rows[..], cross_columns[..], 3usize, 3usize, bounds, 70.0f32, &cross_work)
    if cross_error != ok || cross.summary.total != 9u64 || cross.display_rows != 5usize || cross.display_columns != 5usize || counts[1usize] != 2u64 || counts[5usize] != 2u64 || cross_row_totals[1usize] != 4u64 || cross_column_totals[1usize] != 4u64 || !near(cross.cells[6usize].value, 1.0f64) || !near(f64(cross.cells[6usize].rect.x), 90.5f64) || cross.cells[24usize].kind != .GrandTotal || !near(cross.cells[24usize].value, 9.0f64) { ret chart.Invalid }
    let row_ids = [12]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 1usize, 2usize, 2usize, 2usize, 3usize, 3usize, 3usize }
    let column_ids = [12]usize{ 0usize, 1usize, 2usize, 0usize, 1usize, 2usize, 0usize, 1usize, 2usize, 0usize, 1usize, 2usize }
    let values = [12]f64{ 10.0f64, 20.0f64, 0.0f64, 5.0f64, 15.0f64, 25.0f64, 8.0f64, 0.0f64, 12.0f64, 7.0f64, 9.0f64, 14.0f64 }
    let present = [12]bool{ true, true, false, true, true, true, true, true, true, true, true, true }
    let groups = [4]usize{ 0usize, 0usize, 1usize, 1usize }
    var aggregates: [12]stat.ReportAggregate = zero
    var row_totals: [4]stat.ReportAggregate = zero
    var column_totals: [3]stat.ReportAggregate = zero
    var group_aggregates: [6]stat.ReportAggregate = zero
    var group_totals: [2]stat.ReportAggregate = zero
    var matrix_cells: [40]chart.ReportCell = zero
    var matrix_work = chart.MatrixReportStorage {
        aggregates: aggregates[..], row_totals: row_totals[..], column_totals: column_totals[..],
        group_aggregates: group_aggregates[..], group_totals: group_totals[..], cells: matrix_cells[..],
    }
    let (matrix, matrix_error) = chart.matrix_report(row_ids[..], column_ids[..], values[..], present[..], groups[..], 4usize, 3usize, bounds, 70.0f32, .Row, &matrix_work)
    if matrix_error != ok || matrix.display_rows != 8usize || matrix.display_columns != 5usize || matrix.group_count != 2usize || !near(matrix.grand.sum, 125.0f64) || matrix.grand.count != 11usize || !near(group_totals[0usize].sum, 75.0f64) || !near(group_totals[1usize].sum, 50.0f64) || matrix.cells[8usize].present || !matrix.cells[22usize].present || !near(matrix.cells[22usize].value, 0.0f64) || matrix.cells[19usize].kind != .GroupSubtotal || !near(matrix.cells[19usize].value, 75.0f64) || !near(matrix.cells[39usize].value, 125.0f64) || !near(f64(matrix.cells[6usize].bar.width * 2.0f32), f64(matrix.cells[7usize].bar.width)) { ret chart.Invalid }
    let pale = paint.rgba(0.95, 0.97, 1.0, 1.0)
    let blue = paint.rgba(0.20, 0.48, 0.75, 1.0)
    let fills = [10]paint.Color{ blue, blue, pale, pale, blue, blue, blue, blue, pale, pale }
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append_report_cells(&builder, cross.cells, fills[..], blue)
    try chart_scene.append_report_cells(&builder, matrix.cells, fills[..], blue)
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 320.0f32, 220.0f32, "Reports", "Totals and data bars")
    try chart_svg.append_report_cells(&writer, cross.cells, fills[..], blue)
    try chart_svg.append_report_cells(&writer, matrix.cells, fills[..], blue)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") { ret chart.Invalid }
    var short = cross_work
    short.cells = cross_cells[..24usize]
    let (_, short_error) = chart.cross_tab_report(cross_rows[..], cross_columns[..], 3usize, 3usize, bounds, 70.0f32, &short)
    let bad_groups = [4]usize{ 0usize, 1usize, 0usize, 1usize }
    let (_, group_error) = chart.matrix_report(row_ids[..], column_ids[..], values[..], present[..], bad_groups[..], 4usize, 3usize, bounds, 70.0f32, .Row, &matrix_work)
    let negative = [12]f64{ -10.0f64, 20.0f64, 0.0f64, 5.0f64, 15.0f64, 25.0f64, 8.0f64, 0.0f64, 12.0f64, 7.0f64, 9.0f64, 14.0f64 }
    let (_, negative_error) = chart.matrix_report(row_ids[..], column_ids[..], negative[..], present[..], groups[..], 4usize, 3usize, bounds, 70.0f32, .Row, &matrix_work)
    if short_error != chart.TooLarge || group_error != chart.Invalid || negative_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart reports ok\n")
    ret ok
}
