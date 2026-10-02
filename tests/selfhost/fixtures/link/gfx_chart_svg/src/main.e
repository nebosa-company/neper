use e.gfx.chart
use e.gfx.chart.svg as svg
use e.gfx.geometry
use e.gfx.paint
use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [3]f32{ 0.0, 1.0, 2.0 }
    let y = [3]f32{ 1.0, 3.0, 2.0 }
    let bounds = geometry.rect(10.0, 10.0, 100.0, 70.0)
    var points: [3]chart.Coord = zero
    var segments: [2]chart.Segment = zero
    var bars: [3]geometry.Rect = zero
    var line_spec = chart.spec(.Line, bounds, x[..], y[..])
    let (marks, layout_error) = chart.layout(&line_spec, points[..], segments[..], bars[..])
    if layout_error != ok { ret layout_error }
    var x_ticks: [3]chart.Tick = zero
    var y_ticks: [3]chart.Tick = zero
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    let (_, tx_error) = chart.ticks(linear, marks.x_min, marks.x_max, x_ticks[..])
    if tx_error != ok { ret tx_error }
    let (_, ty_error) = chart.ticks(linear, marks.y_min, marks.y_max, y_ticks[..])
    if ty_error != ok { ret ty_error }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try svg.begin(&writer, 120.0, 100.0, "A < B & C", "A line with guides")
    try svg.append_guides(&writer, bounds, x_ticks[..], y_ticks[..], paint.rgba(0.8, 0.8, 0.8, 1.0), blue)
    try svg.append(&writer, &marks, blue)
    try svg.finish(&writer)
    let output = io.memory_bytes(&held)
    if !str.contains(output, "<svg xmlns=\"http://www.w3.org/2000/svg\"") || !str.contains(output, "<title>A &lt; B &amp; C</title>") || !str.contains(output, "<path d=\"M") || !str.contains(output, "stroke=\"rgb(") || !str.contains(output, "</svg>") { ret svg.Invalid }
    let values = [4]f64{ 0.0, 1.0, 2.0, 3.0 }
    var cells: [4]chart.Cell = zero
    let (matrix, matrix_error) = chart.heatmap(values[..], 2usize, bounds, cells[..])
    if matrix_error != ok { ret matrix_error }
    let (matrix_state, matrix_unused, matrix_writer_error) = io.memory_writer(a, 0usize)
    if matrix_writer_error != ok { ret matrix_writer_error }
    var matrix_held = matrix_state
    var matrix_writer = io.writer(mem.cast[*void](&matrix_held), io.memory_write)
    try svg.begin(&matrix_writer, 120.0, 100.0, "Matrix", "Four cells")
    try svg.append_matrix(&matrix_writer, &matrix, blue, paint.rgba(1.0, 1.0, 1.0, 1.0), paint.rgba(0.9, 0.2, 0.1, 1.0))
    try svg.finish(&matrix_writer)
    let matrix_output = io.memory_bytes(&matrix_held)
    if !str.contains(matrix_output, "<rect") || !str.contains(matrix_output, "fill=\"rgb(") || !str.contains(matrix_output, "</svg>") { ret svg.Invalid }
    let invalid_layout = chart.Layout { kind: .Heatmap, coords: zero, segments: zero, bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 1.0 }
    if svg.append(&matrix_writer, &invalid_layout, blue) != svg.Invalid { ret svg.Invalid }
    try io.print("gfx chart svg ok\n")
    ret ok
}
