use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [5]f32{ 0.0, 1.0, 0.0, 1.0, 0.0 }
    let bounds = geometry.rect(0.0, 0.0, 80.0, 80.0)
    var cells: [16]chart.Cell = zero
    let (marks, chart_error) = chart.recurrence(values[..], 1usize, 0.0, bounds, cells[..])
    if chart_error != ok || marks.kind != .Heatmap || marks.columns != 4usize || marks.rows != 4usize || marks.cells.len != 16usize || marks.value_min != 0.0 || marks.value_max != 1.0 { ret chart.Invalid }
    if cells[0usize].value != 1.0 || cells[1usize].value != 0.0 || cells[2usize].value != 1.0 || cells[4usize].value != 0.0 || cells[5usize].value != 1.0 || cells[15usize].value != 1.0 || cells[6usize].rect.width != 20.0 || cells[6usize].rect.x != 40.0 { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let low = paint.rgba(0.9, 0.94, 0.98, 1.0)
    let high = paint.rgba(0.08, 0.34, 0.74, 1.0)
    try chart_scene.append_matrix(&builder, &marks, low, low, high)
    if scene.builder_count(&builder) != 16usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 80.0, 80.0, "Recurrence", "Thresholded phase-space distances")
    try chart_svg.append_matrix(&writer, &marks, low, low, high)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (all, all_error) = chart.recurrence(values[..], 1usize, 2.0, bounds, cells[..])
    if all_error != ok || all.cells[1usize].value != 1.0 { ret chart.Invalid }
    let (_, lag_error) = chart.recurrence(values[..], 0usize, 0.0, bounds, cells[..])
    let (_, radius_error) = chart.recurrence(values[..], 1usize, -1.0, bounds, cells[..])
    let (_, capacity_error) = chart.recurrence(values[..], 1usize, 0.0, bounds, cells[..15usize])
    if lag_error != chart.Invalid || radius_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart recurrence ok\n")
    ret ok
}
