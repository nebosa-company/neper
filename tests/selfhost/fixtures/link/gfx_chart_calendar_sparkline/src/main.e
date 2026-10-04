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
    let values = [4]f32{ 2.0, 4.0, 3.0, 5.0 }
    var x: [4]f32 = zero
    var segments: [3]chart.Segment = zero
    let (line, line_error) = chart.sparkline(values[..], geometry.rect(10.0, 20.0, 120.0, 60.0), x[..], segments[..])
    if line_error != ok || line.kind != .Line || line.segments.len != 3usize || !near(line.segments[0usize].from.x, 10.0) || !near(line.segments[0usize].from.y, 80.0) || !near(line.segments[2usize].to.x, 130.0) || !near(line.segments[2usize].to.y, 20.0) { ret chart.Invalid }
    let (_, empty_error) = chart.sparkline(values[..1usize], geometry.rect(10.0, 20.0, 120.0, 60.0), x[..], segments[..])
    if empty_error != chart.Empty { ret chart.Invalid }
    let (_, line_capacity_error) = chart.sparkline(values[..], geometry.rect(10.0, 20.0, 120.0, 60.0), x[..3usize], segments[..])
    if line_capacity_error != chart.TooLarge { ret chart.Invalid }

    let days = [3]chart.CalendarDay{
        chart.CalendarDay { offset: 0usize, value: 2.0f64 },
        chart.CalendarDay { offset: 1usize, value: 8.0f64 },
        chart.CalendarDay { offset: 8usize, value: 5.0f64 },
    }
    var cells: [3]chart.Cell = zero
    let bounds = geometry.rect(10.0, 20.0, 140.0, 70.0)
    let (calendar, calendar_error) = chart.calendar_heatmap(days[..], 10usize, 2usize, bounds, 0.0, cells[..])
    if calendar_error != ok || calendar.kind != .Heatmap || calendar.columns != 2usize || calendar.rows != 7usize || calendar.cells.len != 3usize || !near(cells[0usize].rect.x, 10.0) || !near(cells[0usize].rect.y, 40.0) || !near(cells[1usize].rect.y, 50.0) || !near(cells[2usize].rect.x, 80.0) || !near(cells[2usize].rect.y, 50.0) || !near(calendar.value_min, 2.0) || !near(calendar.value_max, 8.0) { ret chart.Invalid }
    let duplicate = [2]chart.CalendarDay{ days[0usize], days[0usize] }
    let (_, duplicate_error) = chart.calendar_heatmap(duplicate[..], 10usize, 2usize, bounds, 0.0, cells[..])
    if duplicate_error != chart.Invalid { ret chart.Invalid }
    let (_, domain_error) = chart.calendar_heatmap(days[..], 8usize, 2usize, bounds, 0.0, cells[..])
    if domain_error != chart.Invalid { ret chart.Invalid }
    let (_, weekday_error) = chart.calendar_heatmap(days[..], 10usize, 7usize, bounds, 0.0, cells[..])
    if weekday_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.calendar_heatmap(days[..], 10usize, 2usize, bounds, 0.0, cells[..2usize])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (_, gap_error) = chart.calendar_heatmap(days[..], 10usize, 2usize, bounds, 10.0, cells[..])
    if gap_error != chart.Invalid { ret chart.Invalid }

    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &line, paint.Brush { Solid: blue })
    try chart_scene.append_matrix(&builder, &calendar, blue, blue, blue)
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 160.0, 100.0, "Calendar and sparkline", "Sparse days")
    try chart_svg.append(&writer, &line, blue)
    try chart_svg.append_matrix(&writer, &calendar, blue, blue, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart calendar sparkline ok\n")
    ret ok
}
