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

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d > -0.01 && d < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let scores = [8]f64{ 0.05f64, 0.15f64, 0.25f64, 0.35f64, 0.55f64, 0.65f64, 0.85f64, 1.0f64 }
    let positive = [8]bool{ false, false, true, false, true, true, false, true }
    var bins: [4]stat.CalibrationBin = zero
    try stat.binary_calibration(scores[..], positive[..], bins[..])
    if bins[0usize].count != 2usize || bins[0usize].positives != 0usize || !near(f32(bins[0usize].score_sum), 0.2) || bins[1usize].count != 2usize || bins[1usize].positives != 1usize || !near(f32(bins[1usize].score_sum), 0.6) || bins[2usize].count != 2usize || bins[2usize].positives != 2usize || !near(f32(bins[2usize].score_sum), 1.2) || bins[3usize].count != 2usize || bins[3usize].positives != 1usize || !near(f32(bins[3usize].score_sum), 1.85) { ret chart.Invalid }
    let invalid_scores = [1]f64{ 1.1f64 }
    let one_label = [1]bool{ true }
    if stat.binary_calibration(invalid_scores[..], one_label[..], bins[..]) != stat.Invalid || bins[0usize].count != 2usize { ret chart.Invalid }
    if stat.binary_calibration(scores[..], positive[..], bins[..0usize]) != stat.TooSmall { ret chart.Invalid }
    let (counts, counts_error) = stat.binary_confusion(scores[..], positive[..], 0.5f64)
    if counts_error != ok || counts.true_negative != 3usize || counts.false_positive != 1usize || counts.false_negative != 1usize || counts.true_positive != 3usize { ret chart.Invalid }
    let (_, invalid_counts) = stat.binary_confusion(scores[..], one_label[..], 0.5f64)
    if invalid_counts != stat.Invalid { ret chart.Invalid }
    let bounds = geometry.rect(10.0, 20.0, 120.0, 60.0)
    let limits = [2]f32{ 0.0, 1.0 }
    var x: [4]f32 = zero
    var y: [4]f32 = zero
    var i = 0usize
    while i < bins.len {
        x[i] = f32(bins[i].score_sum / f64(bins[i].count))
        y[i] = f32(f64(bins[i].positives) / f64(bins[i].count))
        i += 1usize
    }
    let spec = chart.spec(.PointLine, bounds, x[..], y[..])
    var coords: [4]chart.Coord = zero
    var segments: [3]chart.Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    let (calibration, calibration_error) = chart.layout_with_limits(&spec, coords[..], segments[..], unused_bars[..0usize], limits[..], limits[..])
    if calibration_error != ok || calibration.coords.len != 4usize || calibration.segments.len != 3usize || !near(calibration.coords[0usize].x, 22.0) || !near(calibration.coords[0usize].y, 80.0) || !near(calibration.coords[3usize].x, 121.0) || !near(calibration.coords[3usize].y, 50.0) { ret chart.Invalid }
    let values = [4]f64{ f64(counts.true_negative), f64(counts.false_positive), f64(counts.false_negative), f64(counts.true_positive) }
    var cells: [4]chart.Cell = zero
    let (matrix, matrix_error) = chart.heatmap(values[..], 2usize, bounds, cells[..])
    if matrix_error != ok || matrix.rows != 2usize || matrix.columns != 2usize || matrix.cells.len != 4usize || !near(matrix.cells[0usize].rect.width, 60.0) || !near(matrix.cells[3usize].rect.y, 50.0) || !near(matrix.cells[3usize].value, 3.0) { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &calibration, paint.Brush { Solid: blue })
    try chart_scene.append_matrix(&builder, &matrix, blue, blue, blue)
    if scene.builder_count(&builder) != 9usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 150.0, 100.0, "Classifier diagnostics", "Calibration and confusion")
    try chart_svg.append(&writer, &calibration, blue)
    try chart_svg.append_matrix(&writer, &matrix, blue, blue, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart diagnostic tables ok\n")
    ret ok
}
