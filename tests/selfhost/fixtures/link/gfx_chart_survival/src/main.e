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

fn near(a: f64, b: f64) -> bool {
    let d = a - b
    ret d > -0.0001f64 && d < 0.0001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let times = [7]f64{ 1.0, 2.0, 2.0, 3.0, 4.0, 4.0, 5.0 }
    let event = [7]bool{ true, true, false, true, true, false, false }
    var storage: [8]stat.SurvivalPoint = zero
    let (curve, curve_error) = stat.survival_curve(times[..], event[..], storage[..])
    if curve_error != ok || curve.len != 6usize { ret stat.Invalid }
    if !near(curve[0usize].survival, 1.0) || curve[0usize].at_risk != 7usize || !near(curve[1usize].survival, 6.0f64 / 7.0f64) || !near(curve[2usize].survival, 5.0f64 / 7.0f64) || !near(curve[2usize].cumulative_hazard, 13.0f64 / 42.0f64) || curve[2usize].events != 1usize || curve[2usize].censored != 1usize || curve[2usize].at_risk != 6usize || !near(curve[4usize].survival, 5.0f64 / 14.0f64) || !near(curve[5usize].cumulative_hazard, 25.0f64 / 28.0f64) || curve[5usize].events != 0usize { ret stat.Invalid }
    let (_, short_error) = stat.survival_curve(times[..], event[..], storage[..7usize])
    if short_error != stat.TooSmall { ret stat.Invalid }
    let unsorted = [3]f64{ 1.0, 3.0, 2.0 }
    let three_events = [3]bool{ true, false, true }
    let (_, order_error) = stat.survival_curve(unsorted[..], three_events[..], storage[..])
    if order_error != stat.Invalid { ret stat.Invalid }
    let negative = [3]f64{ -1.0, 2.0, 3.0 }
    let (_, negative_error) = stat.survival_curve(negative[..], three_events[..], storage[..])
    if negative_error != stat.Invalid { ret stat.Invalid }
    let no_events = [3]bool{ false, false, false }
    let ordered = [3]f64{ 1.0, 2.0, 3.0 }
    let (flat, flat_error) = stat.survival_curve(ordered[..], no_events[..], storage[..])
    if flat_error != ok || !near(flat[3usize].survival, 1.0) || !near(flat[3usize].cumulative_hazard, 0.0) { ret stat.Invalid }
    let x = [6]f32{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0 }
    let y = [6]f32{ 1.0, 0.8571429, 0.7142857, 0.5357143, 0.3571429, 0.3571429 }
    var spec = chart.spec(.Step, geometry.rect(30.0, 20.0, 200.0, 100.0), x[..], y[..])
    var segments: [10]chart.Segment = zero
    let x_limits = [2]f32{ 0.0, 5.0 }
    let y_limits = [2]f32{ 0.0, 1.0 }
    let (marks, layout_error) = chart.layout_with_limits(&spec, zero, segments[..], zero, x_limits[..], y_limits[..])
    if layout_error != ok || marks.kind != .Step || marks.segments.len != 10usize { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 260.0, 160.0, "Survival", "Kaplan-Meier curve")
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    try io.print("gfx chart survival ok\n")
    ret ok
}
