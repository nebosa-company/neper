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

fn near(a: f64, b: f64, tolerance: f64) -> bool {
    let delta = a - b
    ret delta > 0.0f64 - tolerance && delta < tolerance
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (p01, e01) = stat.binomial_acceptance_probability(52usize, 3usize, 0.01f64)
    let (p07, e07) = stat.binomial_acceptance_probability(52usize, 3usize, 0.07f64)
    let (p12, e12) = stat.binomial_acceptance_probability(52usize, 3usize, 0.12f64)
    let (p0, e0) = stat.binomial_acceptance_probability(52usize, 3usize, 0.0f64)
    let (p1, e1) = stat.binomial_acceptance_probability(52usize, 3usize, 1.0f64)
    let (always, always_error) = stat.binomial_acceptance_probability(52usize, 52usize, 0.4f64)
    let (zero_accept, zero_error) = stat.binomial_acceptance_probability(10usize, 0usize, 0.1f64)
    if e01 != ok || e07 != ok || e12 != ok || e0 != ok || e1 != ok || always_error != ok || zero_error != ok { ret chart.Invalid }
    if !near(p01, 0.998f64, 0.001f64) || !near(p07, 0.502f64, 0.001f64) || !near(p12, 0.115f64, 0.001f64) || p0 != 1.0f64 || p1 != 0.0f64 || always != 1.0f64 || !near(zero_accept, 0.3486784401f64, 0.0000001f64) { ret chart.Invalid }
    let nist = [12]f64{ 0.998f64, 0.980f64, 0.930f64, 0.845f64, 0.739f64, 0.620f64, 0.502f64, 0.394f64, 0.300f64, 0.223f64, 0.162f64, 0.115f64 }
    var row = 0usize
    while row < nist.len {
        let (probability, model_error) = stat.binomial_acceptance_probability(52usize, 3usize, f64(row + 1usize) / 100.0f64)
        if model_error != ok || !near(probability, nist[row], 0.001f64) { ret chart.Invalid }
        row += 1usize
    }
    let (_, bad_n) = stat.binomial_acceptance_probability(0usize, 0usize, 0.1f64)
    let (_, bad_c) = stat.binomial_acceptance_probability(10usize, 11usize, 0.1f64)
    let (_, bad_p) = stat.binomial_acceptance_probability(10usize, 1usize, -0.1f64)
    if bad_n != stat.Invalid || bad_c != stat.Invalid || bad_p != stat.Invalid { ret chart.Invalid }

    let bounds = geometry.rect(20.0, 30.0, 300.0, 160.0)
    var points: [13]chart.Coord = zero
    var segments: [12]chart.Segment = zero
    let (curve, result) = chart.oc_curve(52usize, 3usize, 0.12f64, bounds, points[..], segments[..])
    if result != ok || curve.kind != .PointLine || curve.coords.len != 13usize || curve.segments.len != 12usize || curve.x_min != 0.0 || !near(f64(curve.x_max), 0.12f64, 0.000001f64) || curve.y_min != 0.0 || curve.y_max != 1.0 { ret chart.Invalid }
    if !near(f64(points[0usize].x), 20.0f64, 0.002f64) || !near(f64(points[0usize].y), 30.0f64, 0.002f64) || !near(f64(points[12usize].x), 320.0f64, 0.002f64) || !near(f64(points[7usize].y), 30.0f64 + 160.0f64 * (1.0f64 - p07), 0.003f64) { ret chart.Invalid }
    var i = 1usize
    while i < points.len {
        if !(points[i].x > points[i - 1usize].x && points[i].y >= points[i - 1usize].y) || segments[i - 1usize].from.x != points[i - 1usize].x || segments[i - 1usize].to.x != points[i].x { ret chart.Invalid }
        i += 1usize
    }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &curve, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 14usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 340.0, 210.0, "OC curve", "Binomial single-sample acceptance")
    try chart_svg.append(&writer, &curve, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let (_, empty_points) = chart.oc_curve(52usize, 3usize, 0.12f64, bounds, points[..1usize], segments[..])
    let (_, short_segments) = chart.oc_curve(52usize, 3usize, 0.12f64, bounds, points[..], segments[..11usize])
    let (_, bad_fraction) = chart.oc_curve(52usize, 3usize, 1.2f64, bounds, points[..], segments[..])
    let (_, bad_bounds) = chart.oc_curve(52usize, 3usize, 0.12f64, geometry.rect(0.0, 0.0, 0.0, 1.0), points[..], segments[..])
    if empty_points != chart.TooLarge || short_segments != chart.TooLarge || bad_fraction != chart.Invalid || bad_bounds != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart OC curve ok\n")
    ret ok
}
