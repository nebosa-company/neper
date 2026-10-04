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
    // Unit-gain first-order low-pass with corner at 10 rad/s.
    let frequency = [4]f64{ 0.1f64, 1.0f64, 10.0f64, 100.0f64 }
    let real = [4]f64{ 0.99990001f64, 0.99009901f64, 0.5f64, 0.00990099f64 }
    let imag = [4]f64{ -0.009999f64, -0.0990099f64, -0.5f64, -0.0990099f64 }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var mag_points: [4]chart.Coord = zero
    var mag_segments: [3]chart.Segment = zero
    var phase_points: [4]chart.Coord = zero
    var phase_segments: [3]chart.Segment = zero
    var mag_db: [4]f64 = zero
    var phase_deg: [4]f64 = zero
    var storage = chart.BodeStorage { magnitude_points: mag_points[..], magnitude_segments: mag_segments[..], phase_points: phase_points[..], phase_segments: phase_segments[..], magnitude_db: mag_db[..], phase_degrees: phase_deg[..] }
    let (map, result) = chart.bode(frequency[..], real[..], imag[..], 0.000001f64, bounds, &storage)
    if result != ok || map.magnitude.kind != .Line || map.phase.kind != .Line || map.magnitude.segments.len != 3usize || map.phase.coords.len != 4usize { ret chart.Invalid }
    if !near(map.frequency_min, 0.1f64) || !near(map.frequency_max, 100.0f64) || !near(map.magnitude_db[0usize], -0.000434f64) || !near(map.magnitude_db[2usize], -3.0103f64) || !near(map.magnitude_db[3usize], -20.0432f64) { ret chart.Invalid }
    if !near(map.phase_degrees[0usize], -0.57294f64) || !near(map.phase_degrees[2usize], -45.0f64) || !near(map.phase_degrees[3usize], -84.2894f64) { ret chart.Invalid }
    if !near(f64(mag_points[0usize].x), 10.0f64) || !near(f64(mag_points[1usize].x), 90.0f64) || !near(f64(mag_points[2usize].x), 170.0f64) || !near(f64(mag_points[3usize].x), 250.0f64) { ret chart.Invalid }
    if !near(f64(map.magnitude_bounds.height), 48.0f64) || !near(f64(map.phase_bounds.y), 84.8f64) || !(mag_points[0usize].y < mag_points[3usize].y && phase_points[0usize].y < phase_points[3usize].y) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.35, 0.15, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.magnitude, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.phase, paint.Brush { Solid: orange })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "Bode plot", "Magnitude and unwrapped phase")
    try chart_svg.append(&writer, &map.magnitude, blue)
    try chart_svg.append(&writer, &map.phase, orange)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let wrap_frequency = [3]f64{ 1.0f64, 10.0f64, 100.0f64 }
    let wrap_real = [3]f64{ -1.0f64, -1.0f64, -1.0f64 }
    let wrap_imag = [3]f64{ 0.1f64, -0.1f64, -0.2f64 }
    let (unwrapped, wrap_error) = chart.bode(wrap_frequency[..], wrap_real[..], wrap_imag[..], 0.000001f64, bounds, &storage)
    if wrap_error != ok || !(unwrapped.phase_degrees[0usize] < unwrapped.phase_degrees[1usize] && unwrapped.phase_degrees[1usize] < unwrapped.phase_degrees[2usize]) || !near(unwrapped.phase_degrees[1usize], 185.7106f64) { ret chart.Invalid }
    let zeros = [3]f64{ 0.0f64, 0.0f64, 0.0f64 }
    let (flat, flat_error) = chart.bode(wrap_frequency[..], zeros[..], zeros[..], 0.001f64, bounds, &storage)
    if flat_error != ok || !near(flat.magnitude_db[0usize], -60.0f64) || !(flat.magnitude.y_min < -60.0 && flat.magnitude.y_max > -60.0) { ret chart.Invalid }
    let unsorted = [4]f64{ 0.1f64, 10.0f64, 1.0f64, 100.0f64 }
    let (_, bad_order) = chart.bode(unsorted[..], real[..], imag[..], 0.000001f64, bounds, &storage)
    let (_, bad_shape) = chart.bode(frequency[..], real[..3usize], imag[..], 0.000001f64, bounds, &storage)
    let (_, bad_floor) = chart.bode(frequency[..], real[..], imag[..], 0.0f64, bounds, &storage)
    var short_storage = chart.BodeStorage { magnitude_points: mag_points[..3usize], magnitude_segments: mag_segments[..], phase_points: phase_points[..], phase_segments: phase_segments[..], magnitude_db: mag_db[..], phase_degrees: phase_deg[..] }
    let (_, short_points) = chart.bode(frequency[..], real[..], imag[..], 0.000001f64, bounds, &short_storage)
    if bad_order != chart.Invalid || bad_shape != chart.Invalid || bad_floor != chart.Invalid || short_points != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart bode ok\n")
    ret ok
}
