use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [3]f32{ 0.0, 1.0, 2.0 }
    let y = [3]f32{ 1.0, 3.0, 2.0 }
    let bounds = geometry.rect(10.0, 20.0, 100.0, 60.0)
    var area_points: [6]chart.Coord = zero
    var stem_points: [3]chart.Coord = zero
    var stem_lines: [3]chart.Segment = zero
    var interval_points: [3]chart.Coord = zero
    var interval_lines: [9]chart.Segment = zero
    var bars: [3]geometry.Rect = zero
    var area = chart.spec(.Area, bounds, x[..], y[..])
    let (filled, area_error) = chart.layout(&area, area_points[..], stem_lines[..], bars[..])
    if area_error != ok || filled.kind != .Area || filled.coords.len != 6usize || filled.segments.len != 0usize { ret chart.Invalid }
    if !near(filled.coords[0].x, 10.0) || !near(filled.coords[0].y, 60.0) || !near(filled.coords[1].y, 20.0) || !near(filled.coords[3].x, 110.0) || !near(filled.coords[5].y, 80.0) { ret chart.Invalid }
    let (_, short_area) = chart.layout(&area, area_points[..5usize], stem_lines[..], bars[..])
    if short_area != chart.TooLarge { ret chart.Invalid }
    let unordered = [3]f32{ 0.0, 2.0, 1.0 }
    var bad_area = chart.spec(.Area, bounds, unordered[..], y[..])
    var bad_area_points: [6]chart.Coord = zero
    let (_, unsorted_area) = chart.layout(&bad_area, bad_area_points[..], stem_lines[..], bars[..])
    if unsorted_area != chart.Invalid { ret chart.Invalid }
    var lollipop = chart.spec(.Lollipop, bounds, x[..], y[..])
    let (stems, stems_error) = chart.layout(&lollipop, stem_points[..], stem_lines[..], bars[..])
    if stems_error != ok || stems.kind != .Lollipop || stems.coords.len != 3usize || stems.segments.len != 3usize { ret chart.Invalid }
    if !near(stems.coords[1].x, 60.0) || !near(stems.coords[1].y, 20.0) || !near(stems.segments[1].from.y, 80.0) { ret chart.Invalid }
    let (_, short_stems) = chart.layout(&lollipop, stem_points[..], stem_lines[..2usize], bars[..])
    if short_stems != chart.TooLarge { ret chart.Invalid }
    let lower = [3]f32{ 1.0, 2.0, 0.0 }
    let upper = [3]f32{ 3.0, 4.0, 2.0 }
    let (intervals, interval_error) = chart.error_bars(x[..], y[..], lower[..], upper[..], bounds, interval_points[..], interval_lines[..])
    if interval_error != ok || intervals.kind != .ErrorBar || intervals.coords.len != 3usize || intervals.segments.len != 9usize { ret chart.Invalid }
    if !near(intervals.coords[0].y, 65.0) || !near(intervals.segments[0].from.y, 35.0) || !near(intervals.segments[0].to.y, 65.0) || !near(intervals.segments[1].from.x, 5.0) { ret chart.Invalid }
    let (_, short_intervals) = chart.error_bars(x[..], y[..], lower[..], upper[..], bounds, interval_points[..], interval_lines[..8usize])
    if short_intervals != chart.TooLarge { ret chart.Invalid }
    let bad_upper = [3]f32{ 3.0, 2.0, 2.0 }
    let (_, invalid_interval) = chart.error_bars(x[..], y[..], lower[..], bad_upper[..], bounds, interval_points[..], interval_lines[..])
    if invalid_interval != chart.Invalid { ret chart.Invalid }
    let (made_builder, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made_builder
    let blue = paint.Brush { Solid: paint.rgba(0.1, 0.3, 0.8, 1.0) }
    if chart_scene.append(a, &builder, &filled, blue) != ok { ret chart.Invalid }
    if chart_scene.append(a, &builder, &stems, blue) != ok { ret chart.Invalid }
    if chart_scene.append(a, &builder, &intervals, blue) != ok { ret chart.Invalid }
    if scene.builder_count(&builder) != 19usize { ret chart.Invalid }
    try io.print("gfx chart cartesian ok\n")
    ret ok
}
