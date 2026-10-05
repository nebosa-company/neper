use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.math
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool {
    let delta = a - b
    ret delta > -0.01 && delta < 0.01
}

// References: scripts/chart_loess_reference.py (statsmodels LOWESS it=0 for the
// fit; an explicit smoother matrix for s and |l(x0)|), critical 2, span 0.5.
fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let x = [12]f32{ 7.0, 1.0, 4.0, 9.0, 2.0, 11.0, 5.0, 0.0, 8.0, 3.0, 10.0, 6.0 }
    let y = [12]f32{ 4.1, 1.9, 3.8, 3.2, 2.7, 1.2, 4.6, 1.0, 3.9, 3.1, 2.0, 4.8 }
    var distances: [12]f64 = zero
    var outline: [10]chart.Coord = zero
    var curve_segments: [4]chart.Segment = zero
    let (ribbon, curve, loess_error) = chart.loess_interval(x[..], y[..], 0.5, 2.0, false, bounds, distances[..], outline[..], curve_segments[..])
    if loess_error != ok { ret loess_error }
    if ribbon.kind != .Band || curve.kind != .Line || ribbon.coords.len != 10usize || curve.segments.len != 4usize { ret chart.Invalid }
    if !near(ribbon.y_min, 0.6787) || !near(ribbon.y_max, 4.8) || curve.y_min != ribbon.y_min || !near(curve.x_max, 11.0) { ret chart.Invalid }
    let fit_y = [5]f32{ 89.774, 42.676, 8.441, 30.846, 86.909 }
    let upper_y = [5]f32{ 79.549, 36.263, 1.769, 24.434, 76.683 }
    let lower_y = [5]f32{ 100.0, 49.088, 15.112, 37.259, 97.134 }
    var i = 0usize
    while i < 5usize {
        var point = curve.segments[3usize].to
        if i < 4usize { point = curve.segments[i].from }
        if !near(point.x, 25.0 * f32(i)) || !near(point.y, fit_y[i]) || !near(ribbon.coords[i].y, upper_y[i]) || !near(ribbon.coords[9usize - i].y, lower_y[i]) || !near(ribbon.coords[9usize - i].x, 25.0 * f32(i)) { ret chart.Invalid }
        if i > 0usize && curve.segments[i - 1usize].to.y != point.y { ret chart.Invalid }
        i += 1usize
    }
    // A new observation's band is s * sqrt(1 + |l(x0)|^2) wide.
    let (wide, wide_curve, wide_error) = chart.loess_interval(x[..], y[..], 0.5, 2.0, true, bounds, distances[..], outline[..], curve_segments[..])
    if wide_error != ok { ret wide_error }
    if !near(wide.y_min, 0.4302) || !near(wide.y_max, 5.041) || !near(wide_curve.segments[2usize].from.y, 12.772) || !near(wide.coords[2usize].y, 0.0) || !near(wide.coords[7usize].y, 25.545) || !near(wide.coords[0usize].y, 70.94) || !near(wide.coords[5usize].y, 97.439) { ret chart.Invalid }
    let (_, _, narrow_error) = chart.loess_interval(x[..], y[..], 0.2, 2.0, false, bounds, distances[..], outline[..], curve_segments[..])
    if narrow_error != chart.Invalid { ret chart.Invalid }
    let flat_x = [8]f32{ 0.0, 0.0, 0.0, 0.0, 5.0, 5.0, 5.0, 5.0 }
    let (_, _, tied_error) = chart.loess_interval(flat_x[..], y[..8usize], 0.5, 2.0, false, bounds, distances[..], outline[..], curve_segments[..])
    if tied_error != chart.Invalid { ret chart.Invalid }
    let same_x = [4]f32{ 2.0, 2.0, 2.0, 2.0 }
    let (_, _, same_error) = chart.loess_interval(same_x[..], y[..4usize], 1.0, 2.0, false, bounds, distances[..], outline[..], curve_segments[..])
    if same_error != chart.Invalid { ret chart.Invalid }
    var gappy = y
    gappy[3usize] = f32(math.nan64())
    let (_, _, nan_error) = chart.loess_interval(x[..], gappy[..], 0.5, 2.0, false, bounds, distances[..], outline[..], curve_segments[..])
    if nan_error != chart.Invalid { ret chart.Invalid }
    let (_, _, critical_error) = chart.loess_interval(x[..], y[..], 0.5, 0.0, false, bounds, distances[..], outline[..], curve_segments[..])
    if critical_error != chart.Invalid { ret chart.Invalid }
    let (_, _, scratch_error) = chart.loess_interval(x[..], y[..], 0.5, 2.0, false, bounds, distances[..11usize], outline[..], curve_segments[..])
    if scratch_error != chart.TooLarge { ret chart.Invalid }
    let (_, _, outline_error) = chart.loess_interval(x[..], y[..], 0.5, 2.0, false, bounds, distances[..], outline[..9usize], curve_segments[..])
    if outline_error != chart.TooLarge { ret chart.Invalid }
    let (_, _, mismatch_error) = chart.loess_interval(x[..], y[..11usize], 0.5, 2.0, false, bounds, distances[..], outline[..], curve_segments[..])
    if mismatch_error != chart.Invalid { ret chart.Invalid }
    let (again_ribbon, again_curve, again_error) = chart.loess_interval(x[..], y[..], 0.5, 2.0, false, bounds, distances[..], outline[..], curve_segments[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &again_ribbon, paint.Brush { Solid: paint.rgba(0.7, 0.8, 0.9, 1.0) })
    try chart_scene.append(a, &builder, &again_curve, paint.Brush { Solid: paint.rgba(0.9, 0.4, 0.1, 1.0) })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "LOESS", "Local-linear fit with a confidence band")
    try chart_svg.append(&writer, &again_ribbon, paint.rgba(0.7, 0.8, 0.9, 1.0))
    try chart_svg.append(&writer, &again_curve, paint.rgba(0.9, 0.4, 0.1, 1.0))
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, " Z\"") || !str.contains(svg, "fill=\"none\"") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart loess ok\n")
    ret ok
}
