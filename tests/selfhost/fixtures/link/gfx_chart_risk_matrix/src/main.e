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
    ret d > -0.001 && d < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 90.0, 90.0)
    let ratings = [9]f64{ 3.0, 6.0, 9.0, 2.0, 4.0, 6.0, 1.0, 2.0, 3.0 }
    let risks = [4]chart.RiskPoint{
        chart.RiskPoint { likelihood: 1usize, impact: 3usize },
        chart.RiskPoint { likelihood: 3usize, impact: 3usize },
        chart.RiskPoint { likelihood: 3usize, impact: 3usize },
        chart.RiskPoint { likelihood: 2usize, impact: 1usize },
    }
    var counts: [9]u64 = zero
    var cells: [9]chart.Cell = zero
    let (matrix, matrix_error) = chart.risk_matrix(risks[..], ratings[..], 3usize, bounds, counts[..], cells[..])
    if matrix_error != ok || matrix.kind != .Heatmap || matrix.columns != 3usize || matrix.rows != 3usize || matrix.cells.len != 9usize { ret chart.Invalid }
    if !near(matrix.value_min, 1.0) || !near(matrix.value_max, 9.0) || !near(cells[2usize].rect.x, 60.0) || !near(cells[2usize].rect.y, 0.0) || !near(cells[7usize].rect.x, 30.0) || !near(cells[7usize].rect.y, 60.0) { ret chart.Invalid }
    if counts[0usize] != 1u64 || counts[2usize] != 2u64 || counts[7usize] != 1u64 || counts[1usize] != 0u64 { ret chart.Invalid }
    let low = paint.rgba(0.8, 0.9, 0.7, 1.0)
    let high = paint.rgba(0.9, 0.3, 0.2, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append_matrix(&builder, &matrix, low, low, high)
    if scene.builder_count(&builder) != 9usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 90.0, 90.0, "Risk matrix", "Likelihood and impact")
    try chart_svg.append_matrix(&writer, &matrix, low, low, high)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let bad_ratings = [3]f64{ 1.0, 2.0, 3.0 }
    let negative = [9]f64{ -1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0 }
    let invalid_risk = [1]chart.RiskPoint{ chart.RiskPoint { likelihood: 0usize, impact: 1usize } }
    let (_, shape_error) = chart.risk_matrix(risks[..], bad_ratings[..], 3usize, bounds, counts[..], cells[..])
    let (_, rating_error) = chart.risk_matrix(risks[..], negative[..], 3usize, bounds, counts[..], cells[..])
    let (_, risk_error) = chart.risk_matrix(invalid_risk[..], ratings[..], 3usize, bounds, counts[..], cells[..])
    let (_, capacity_error) = chart.risk_matrix(risks[..], ratings[..], 3usize, bounds, counts[..8usize], cells[..])
    if shape_error != chart.Invalid || rating_error != chart.Invalid || risk_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    if counts[2usize] != 2u64 { ret chart.Invalid }
    let (_, empty_error) = chart.risk_matrix(risks[..0usize], ratings[..], 3usize, bounds, counts[..], cells[..])
    if empty_error != ok || counts[2usize] != 0u64 { ret chart.Invalid }
    try io.print("gfx chart risk matrix ok\n")
    ret ok
}
