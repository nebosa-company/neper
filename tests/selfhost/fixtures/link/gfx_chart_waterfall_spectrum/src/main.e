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
    // Three time frames by three frequencies, in top/high-frequency row order.
    let levels = [9]f32{ 0.0, 1.0, 2.0, 4.0, 5.0, 6.0, 8.0, 9.0, 10.0 }
    var cells: [9]chart.Cell = zero
    var i = 0usize
    while i < cells.len {
        cells[i] = chart.Cell { rect: geometry.rect(0.0, 0.0, 1.0, 1.0), value: levels[i] }
        i += 1usize
    }
    let matrix = chart.MatrixLayout { kind: .Heatmap, cells: cells[..], columns: 3usize, rows: 3usize, value_min: 0.0, value_max: 10.0 }
    let spectrum = chart.SpectrogramLayout { matrix: matrix, time_start: 0.25f64, time_end: 0.75f64, frequency_max: 4.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 200.0, 100.0)
    var points: [9]chart.Coord = zero
    var segments: [6]chart.Segment = zero
    var traces: [3]chart.Layout = zero
    var indices: [3]usize = zero
    var storage = chart.WaterfallSpectrumStorage { points: points[..], segments: segments[..], traces: traces[..], frame_indices: indices[..] }
    let (map, result) = chart.waterfall_spectrum(&spectrum, 1usize, bounds, &storage)
    if result != ok || map.traces.len != 3usize || map.traces[0usize].kind != .Line || map.traces[1usize].coords.len != 3usize || map.traces[2usize].segments.len != 2usize { ret chart.Invalid }
    if map.frame_indices[0usize] != 0usize || map.frame_indices[1usize] != 1usize || map.frame_indices[2usize] != 2usize || !near(f64(map.value_min), 0.0f64) || !near(f64(map.value_max), 10.0f64) { ret chart.Invalid }
    if !near(f64(points[0usize].x), 28.0f64) || !near(f64(points[0usize].y), 82.4f64) || !near(f64(points[1usize].x), 96.0f64) || !near(f64(points[1usize].y), 95.2f64) || !near(f64(points[8usize].x), 200.0f64) || !near(f64(points[8usize].y), 63.6f64) { ret chart.Invalid }
    if segments[1usize].to.x != points[2usize].x || segments[2usize].from.x != points[3usize].x || !(points[0usize].y > points[6usize].y) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.35, 0.15, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.traces[0usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.traces[1usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.traces[2usize], paint.Brush { Solid: orange })
    if scene.builder_count(&builder) != 3usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 220.0, 150.0, "Waterfall spectrum", "Three frequency spectra over time")
    try chart_svg.append(&writer, &map.traces[0usize], blue)
    try chart_svg.append(&writer, &map.traces[1usize], blue)
    try chart_svg.append(&writer, &map.traces[2usize], orange)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let (sampled, sampled_error) = chart.waterfall_spectrum(&spectrum, 2usize, bounds, &storage)
    if sampled_error != ok || sampled.traces.len != 2usize || sampled.frame_indices[1usize] != 2usize { ret chart.Invalid }
    let (_, bad_step) = chart.waterfall_spectrum(&spectrum, 0usize, bounds, &storage)
    let (_, one_trace) = chart.waterfall_spectrum(&spectrum, 3usize, bounds, &storage)
    var bad_matrix = chart.MatrixLayout { kind: .Heatmap, cells: cells[..8usize], columns: 3usize, rows: 3usize, value_min: 0.0, value_max: 10.0 }
    var bad_spectrum = chart.SpectrogramLayout { matrix: bad_matrix, time_start: 0.25f64, time_end: 0.75f64, frequency_max: 4.0f64 }
    let (_, bad_shape) = chart.waterfall_spectrum(&bad_spectrum, 1usize, bounds, &storage)
    var short_storage = chart.WaterfallSpectrumStorage { points: points[..8usize], segments: segments[..], traces: traces[..], frame_indices: indices[..] }
    let (_, short_points) = chart.waterfall_spectrum(&spectrum, 1usize, bounds, &short_storage)
    if bad_step != chart.Invalid || one_trace != chart.Invalid || bad_shape != chart.Invalid || short_points != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart waterfall spectrum ok\n")
    ret ok
}
