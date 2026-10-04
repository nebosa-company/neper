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
    let delta = a - b
    ret delta > -0.003f64 && delta < 0.003f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    // H(jw) = 1/(1+jw); the reflected branch is valid for real coefficients.
    let frequency = [3]f64{ 0.1f64, 1.0f64, 10.0f64 }
    let real = [3]f64{ 0.990099f64, 0.5f64, 0.009901f64 }
    let imag = [3]f64{ -0.09901f64, -0.5f64, -0.09901f64 }
    let bounds = geometry.rect(20.0, 30.0, 240.0, 120.0)
    var positive_points: [3]chart.Coord = zero
    var positive_segments: [2]chart.Segment = zero
    var negative_points: [3]chart.Coord = zero
    var negative_segments: [2]chart.Segment = zero
    var critical_point: [1]chart.Coord = zero
    var storage = chart.NyquistStorage { positive_points: positive_points[..], positive_segments: positive_segments[..], negative_points: negative_points[..], negative_segments: negative_segments[..], critical_point: critical_point[..] }
    let (map, result) = chart.nyquist(frequency[..], real[..], imag[..], bounds, &storage)
    if result != ok || map.positive.kind != .Line || map.negative.kind != .Line || map.critical.kind != .Scatter || map.positive.segments.len != 2usize || map.negative.segments.len != 2usize { ret chart.Invalid }
    if !near(map.frequency_min, 0.1f64) || !near(map.frequency_max, 10.0f64) || !near(f64(positive_points[1usize].x), f64(negative_points[1usize].x)) || !near(f64(positive_points[1usize].y + negative_points[1usize].y), 180.0f64) { ret chart.Invalid }
    if !(positive_points[1usize].y > negative_points[1usize].y && critical_point[0usize].x < positive_points[2usize].x && negative_points[0usize].x < negative_points[2usize].x) { ret chart.Invalid }
    let px_per_real = f64(positive_points[0usize].x - positive_points[1usize].x) / (real[0usize] - real[1usize])
    let px_per_imag = f64(positive_points[1usize].y - positive_points[0usize].y) / (imag[0usize] - imag[1usize])
    if !near(px_per_real, px_per_imag) || !near(f64(critical_point[0usize].y), 90.0f64) || !(map.positive.x_min < -1.0 && map.positive.x_max > 0.99) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.35, 0.15, 1.0)
    let red = paint.rgba(0.75, 0.1, 0.18, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.positive, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.negative, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &map.critical, paint.Brush { Solid: red })
    if scene.builder_count(&builder) != 3usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0, 180.0, "Nyquist plot", "Complex response and conjugate branch")
    try chart_svg.append(&writer, &map.positive, blue)
    try chart_svg.append(&writer, &map.negative, orange)
    try chart_svg.append(&writer, &map.critical, red)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad_frequency = [3]f64{ 0.1f64, 0.0f64, 10.0f64 }
    let unordered = [3]f64{ 0.1f64, 10.0f64, 1.0f64 }
    let (_, zero_error) = chart.nyquist(bad_frequency[..], real[..], imag[..], bounds, &storage)
    let (_, order_error) = chart.nyquist(unordered[..], real[..], imag[..], bounds, &storage)
    let (_, shape_error) = chart.nyquist(frequency[..], real[..2usize], imag[..], bounds, &storage)
    var short_storage = chart.NyquistStorage { positive_points: positive_points[..], positive_segments: positive_segments[..], negative_points: negative_points[..], negative_segments: negative_segments[..1usize], critical_point: critical_point[..] }
    let (_, capacity_error) = chart.nyquist(frequency[..], real[..], imag[..], bounds, &short_storage)
    if zero_error != chart.Invalid || order_error != chart.Invalid || shape_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart nyquist ok\n")
    ret ok
}
