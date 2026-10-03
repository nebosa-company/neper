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
    let base = 1700000000000.0f64
    let events = [3]chart.TimelineEvent{
        chart.TimelineEvent { time: base + 1000.0f64, row: 0usize },
        chart.TimelineEvent { time: base + 5000.0f64, row: 1usize },
        chart.TimelineEvent { time: base + 11000.0f64, row: 2usize },
    }
    let bounds = geometry.rect(10.0, 20.0, 120.0, 60.0)
    var points: [3]chart.Coord = zero
    var stems: [3]chart.Segment = zero
    let (timeline, timeline_error) = chart.event_timeline(events[..], 3usize, base, base + 12000.0f64, bounds, points[..], stems[..])
    if timeline_error != ok || timeline.kind != .Lollipop || timeline.coords.len != 3usize || timeline.segments.len != 3usize || !near(points[0usize].x, 20.0) || !near(points[0usize].y, 30.0) || !near(points[1usize].x, 60.0) || !near(points[1usize].y, 50.0) || !near(points[2usize].x, 120.0) || !near(points[2usize].y, 70.0) || !near(stems[0usize].from.y, 35.6) { ret chart.Invalid }
    let reversed = [2]chart.TimelineEvent{ events[1usize], events[0usize] }
    let (_, order_error) = chart.event_timeline(reversed[..], 3usize, base, base + 12000.0f64, bounds, points[..], stems[..])
    if order_error != chart.Invalid { ret chart.Invalid }
    let (_, domain_error) = chart.event_timeline(events[..], 3usize, base, base + 10000.0f64, bounds, points[..], stems[..])
    if domain_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.event_timeline(events[..], 3usize, base, base + 12000.0f64, bounds, points[..2usize], stems[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }

    let values = [3]f32{ 25.0, 50.0, 0.0 }
    let cells = [3]geometry.Rect{ geometry.rect(10.0, 10.0, 100.0, 20.0), geometry.rect(10.0, 40.0, 100.0, 20.0), geometry.rect(10.0, 70.0, 100.0, 20.0) }
    var rects: [3]geometry.Rect = zero
    let (bars, bars_error) = chart.in_cell_bars(values[..], 100.0, cells[..], 4.0, rects[..])
    if bars_error != ok || bars.kind != .Bar || bars.bars.len != 3usize || !near(rects[0usize].x, 14.0) || !near(rects[0usize].width, 23.0) || !near(rects[1usize].width, 46.0) || !near(rects[2usize].width, 0.0) || !near(rects[0usize].height, 12.0) { ret chart.Invalid }
    let invalid_values = [1]f32{ 101.0 }
    let (_, value_error) = chart.in_cell_bars(invalid_values[..], 100.0, cells[..1usize], 4.0, rects[..])
    if value_error != chart.Invalid { ret chart.Invalid }
    let (_, gap_error) = chart.in_cell_bars(values[..], 100.0, cells[..], 10.0, rects[..])
    if gap_error != chart.Invalid { ret chart.Invalid }
    let (_, bar_capacity_error) = chart.in_cell_bars(values[..], 100.0, cells[..], 4.0, rects[..2usize])
    if bar_capacity_error != chart.TooLarge { ret chart.Invalid }

    let (timeline_again, again_error) = chart.event_timeline(events[..], 3usize, base, base + 12000.0f64, bounds, points[..], stems[..])
    if again_error != ok { ret again_error }
    let (bars_again, bars_again_error) = chart.in_cell_bars(values[..], 100.0, cells[..], 4.0, rects[..])
    if bars_again_error != ok { ret bars_again_error }
    let (made, builder_error) = scene.builder(a, 12usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &timeline_again, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &bars_again, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 8usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 140.0, 100.0, "Events and data bars", "Shared marks")
    try chart_svg.append(&writer, &timeline_again, blue)
    try chart_svg.append(&writer, &bars_again, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart events cellbars ok\n")
    ret ok
}
