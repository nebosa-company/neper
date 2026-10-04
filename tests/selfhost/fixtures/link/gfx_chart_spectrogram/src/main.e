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
    // Two 4-bin FFT frames; only DC, positive frequency and Nyquist appear.
    let re = [8]f64{ 1.0f64, 2.0f64, 3.0f64, 0.0f64, 4.0f64, 0.0f64, 5.0f64, 0.0f64 }
    let im = [8]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 200.0, 120.0)
    var cells: [6]chart.Cell = zero
    let (map, result) = chart.spectrogram(re[..], im[..], 2usize, 4usize, 2usize, 8.0f64, 0.0001f64, bounds, cells[..])
    if result != ok || map.matrix.kind != .Heatmap || map.matrix.columns != 2usize || map.matrix.rows != 3usize || map.matrix.cells.len != 6usize { ret chart.Invalid }
    if !near(map.time_start, 0.25f64) || !near(map.time_end, 0.5f64) || !near(map.frequency_max, 4.0f64) { ret chart.Invalid }
    if !near(f64(cells[0usize].value), 9.542425f64) || !near(f64(cells[1usize].value), 13.9794f64) || !near(f64(cells[2usize].value), 6.0206f64) || !near(f64(cells[3usize].value), -40.0f64) || !near(f64(cells[4usize].value), 0.0f64) || !near(f64(cells[5usize].value), 12.0412f64) { ret chart.Invalid }
    if !near(f64(cells[0usize].rect.x), 10.0f64) || !near(f64(cells[0usize].rect.y), 20.0f64) || !near(f64(cells[0usize].rect.width), 100.0f64) || !near(f64(cells[0usize].rect.height), 40.0f64) || !near(f64(cells[5usize].rect.y), 100.0f64) { ret chart.Invalid }
    let dark = paint.rgba(0.1, 0.2, 0.35, 1.0)
    let mid = paint.rgba(0.1, 0.55, 0.8, 1.0)
    let warm = paint.rgba(0.98, 0.7, 0.2, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append_matrix(&builder, &map.matrix, dark, mid, warm)
    if scene.builder_count(&builder) != 6usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 220.0, 160.0, "Spectrogram", "One-sided STFT power")
    try chart_svg.append_matrix(&writer, &map.matrix, dark, mid, warm)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let (_, bad_shape) = chart.spectrogram(re[..7usize], im[..], 2usize, 4usize, 2usize, 8.0f64, 0.0001f64, bounds, cells[..])
    let (_, bad_floor) = chart.spectrogram(re[..], im[..], 2usize, 4usize, 2usize, 8.0f64, 0.0f64, bounds, cells[..])
    let (_, bad_rate) = chart.spectrogram(re[..], im[..], 2usize, 4usize, 2usize, 0.0f64, 0.0001f64, bounds, cells[..])
    var huge = re
    huge[0usize] = 1.0e308f64
    let (_, overflow) = chart.spectrogram(huge[..], im[..], 2usize, 4usize, 2usize, 8.0f64, 0.0001f64, bounds, cells[..])
    let (_, short_cells) = chart.spectrogram(re[..], im[..], 2usize, 4usize, 2usize, 8.0f64, 0.0001f64, bounds, cells[..5usize])
    if bad_shape != chart.Invalid || bad_floor != chart.Invalid || bad_rate != chart.Invalid || overflow != chart.Invalid || short_cells != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart spectrogram ok\n")
    ret ok
}
