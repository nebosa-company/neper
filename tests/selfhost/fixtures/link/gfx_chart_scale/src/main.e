use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [3]f32{ 1.0, 10.0, 100.0 }
    var points: [3]chart.Coord = zero
    var lines: [2]chart.Segment = zero
    var bars: [3]geometry.Rect = zero
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let logarithmic = chart.Scale { kind: .Log10, reverse: false, linthresh: 1.0 }
    var scatter = chart.spec(.Scatter, bounds, values[..], values[..])
    scatter.x_scale = logarithmic
    scatter.y_scale = logarithmic
    let (log_plot, log_error) = chart.layout(&scatter, points[..], lines[..], bars[..])
    if log_error != ok || !near(log_plot.coords[0].x, 0.0) || !near(log_plot.coords[0].y, 100.0) || !near(log_plot.coords[1].x, 50.0) || !near(log_plot.coords[1].y, 50.0) || !near(log_plot.coords[2].x, 100.0) || !near(log_plot.coords[2].y, 0.0) { ret chart.Invalid }
    scatter.x_scale = chart.Scale { kind: .Log10, reverse: true, linthresh: 1.0 }
    let (reversed, reverse_error) = chart.layout(&scatter, points[..], lines[..], bars[..])
    if reverse_error != ok || !near(reversed.coords[0].x, 100.0) || !near(reversed.coords[2].x, 0.0) { ret chart.Invalid }
    let bad_values = [3]f32{ 0.0, 10.0, 100.0 }
    var bad = chart.spec(.Scatter, bounds, bad_values[..], values[..])
    bad.x_scale = logarithmic
    let (_, bad_error) = chart.layout(&bad, points[..], lines[..], bars[..])
    if bad_error != chart.Invalid { ret chart.Invalid }
    let signed = [3]f32{ -100.0, 0.0, 100.0 }
    var symmetric = chart.spec(.Line, bounds, bad_values[..], signed[..])
    symmetric.y_scale = chart.Scale { kind: .Symlog, reverse: false, linthresh: 10.0 }
    let (symlog_plot, symlog_error) = chart.layout(&symmetric, points[..], lines[..], bars[..])
    if symlog_error != ok || !near(symlog_plot.segments[0].from.y, 100.0) || !near(symlog_plot.segments[0].to.y, 50.0) || !near(symlog_plot.segments[1].to.y, 0.0) { ret chart.Invalid }
    symmetric.y_scale.linthresh = 0.0
    let (_, threshold_error) = chart.layout(&symmetric, points[..], lines[..], bars[..])
    if threshold_error != chart.Invalid { ret chart.Invalid }
    var bar = chart.spec(.Bar, bounds, values[..], values[..])
    bar.y_scale = logarithmic
    let (_, baseline_error) = chart.layout(&bar, points[..], lines[..], bars[..])
    if baseline_error != chart.Invalid { ret chart.Invalid }
    bar.baseline = 1.0
    bar.y_scale.reverse = true
    let (reversed_bars, bar_error) = chart.layout(&bar, points[..], lines[..], bars[..])
    if bar_error != ok || reversed_bars.bars[2].height <= 0.0 { ret chart.Invalid }
    var x_ticks: [4]chart.Tick = zero
    let (ticks, tick_error) = chart.ticks(logarithmic, 1.0, 1000.0, x_ticks[..])
    if tick_error != ok || !near(ticks[1].value, 10.0) || !near(ticks[2].value, 100.0) || !near(ticks[1].fraction, 0.333333) { ret chart.Invalid }
    var y_ticks: [5]chart.Tick = zero
    let symlog_scale = chart.Scale { kind: .Symlog, reverse: false, linthresh: 1.0 }
    let (symmetric_ticks, symmetric_tick_error) = chart.ticks(symlog_scale, -99.0, 99.0, y_ticks[..])
    if symmetric_tick_error != ok || !near(symmetric_ticks[2].value, 0.0) || !near(symmetric_ticks[2].fraction, 0.5) { ret chart.Invalid }
    let (_, short_ticks) = chart.ticks(logarithmic, 1.0, 100.0, x_ticks[..1usize])
    if short_ticks != chart.TooLarge { ret chart.Invalid }
    let (made_builder, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made_builder
    let grid = paint.Brush { Solid: paint.rgba(0.8, 0.8, 0.8, 1.0) }
    let axis = paint.Brush { Solid: paint.rgba(0.2, 0.2, 0.2, 1.0) }
    if chart_scene.append_guides(&builder, bounds, x_ticks[..], y_ticks[..4usize], grid, axis) != ok { ret chart.Invalid }
    if scene.builder_count(&builder) != 18usize { ret chart.Invalid }
    if chart_scene.append_guides(&builder, geometry.rect(0.0, 0.0, 0.0, 100.0), x_ticks[..], y_ticks[..4usize], grid, axis) != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart scale ok\n")
    ret ok
}
