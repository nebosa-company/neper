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
    ret d > -0.001 && d < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let tasks = [3]chart.GanttTask{
        chart.GanttTask { row: 1usize, start: 2.0f64, end: 6.0f64, complete: 0.5 },
        chart.GanttTask { row: 0usize, start: 0.0f64, end: 4.0f64, complete: 1.0 },
        chart.GanttTask { row: 2usize, start: 8.0f64, end: 10.0f64, complete: 0.0 },
    }
    let bounds = geometry.rect(20.0, 10.0, 100.0, 78.0)
    var spans: [3]geometry.Rect = zero
    var completed: [3]geometry.Rect = zero
    let (whole, done, result) = chart.gantt(tasks[..], 3usize, 0.0f64, 10.0f64, bounds, 3.0, spans[..], completed[..])
    if result != ok || whole.kind != .Bar || done.kind != .Bar || whole.bars.len != 3usize || done.bars.len != 3usize { ret chart.Invalid }
    if !near(spans[0usize].x, 40.0) || !near(spans[0usize].width, 40.0) || !near(completed[0usize].width, 20.0) || !near(completed[1usize].width, spans[1usize].width) || !near(completed[2usize].width, 0.0) || !(spans[1usize].y < spans[0usize].y && spans[0usize].y < spans[2usize].y) { ret chart.Invalid }
    if !near(whole.x_min, 0.0) || !near(whole.x_max, 10.0) || !near(done.x_min, whole.x_min) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &whole, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &done, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) == 0usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 140.0, 100.0, "Gantt", "Task durations and completion")
    try chart_svg.append(&writer, &whole, ink)
    try chart_svg.append(&writer, &done, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let bad_range = [1]chart.GanttTask{ chart.GanttTask { row: 0usize, start: 5.0f64, end: 5.0f64, complete: 0.5 } }
    let bad_fraction = [1]chart.GanttTask{ chart.GanttTask { row: 0usize, start: 1.0f64, end: 3.0f64, complete: 1.1 } }
    let bad_row = [1]chart.GanttTask{ chart.GanttTask { row: 3usize, start: 1.0f64, end: 3.0f64, complete: 0.5 } }
    let (_, _, empty_error) = chart.gantt(tasks[..0usize], 3usize, 0.0f64, 10.0f64, bounds, 3.0, spans[..], completed[..])
    let (_, _, range_error) = chart.gantt(bad_range[..], 3usize, 0.0f64, 10.0f64, bounds, 3.0, spans[..], completed[..])
    let (_, _, fraction_error) = chart.gantt(bad_fraction[..], 3usize, 0.0f64, 10.0f64, bounds, 3.0, spans[..], completed[..])
    let (_, _, row_error) = chart.gantt(bad_row[..], 3usize, 0.0f64, 10.0f64, bounds, 3.0, spans[..], completed[..])
    let (_, _, capacity_error) = chart.gantt(tasks[..], 3usize, 0.0f64, 10.0f64, bounds, 3.0, spans[..2usize], completed[..])
    let (_, _, domain_error) = chart.gantt(tasks[..], 3usize, 4.0f64, 4.0f64, bounds, 3.0, spans[..], completed[..])
    if empty_error != chart.Empty || range_error != chart.Invalid || fraction_error != chart.Invalid || row_error != chart.Invalid || capacity_error != chart.TooLarge || domain_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart gantt ok\n")
    ret ok
}
