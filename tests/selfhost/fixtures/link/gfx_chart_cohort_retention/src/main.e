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
    let counts = [10]f64{ 100.0f64, 80.0f64, 60.0f64, 50.0f64, 50.0f64, 40.0f64, 30.0f64, 25.0f64, 20.0f64, 10.0f64 }
    var cells: [10]chart.Cell = zero
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let (marks, chart_error) = chart.cohort_retention(counts[..], 4usize, bounds, 2.0, cells[..])
    if chart_error != ok || marks.kind != .Heatmap || marks.cells.len != 10usize || marks.columns != 4usize || marks.rows != 4usize || !near(marks.value_min, 0.0) || !near(marks.value_max, 1.0) { ret chart.Invalid }
    if !near(cells[0usize].value, 1.0) || !near(cells[3usize].value, 0.5) || !near(cells[6usize].value, 0.6) || !near(cells[9usize].value, 1.0) { ret chart.Invalid }
    if !near(cells[4usize].rect.x, 1.0) || !near(cells[4usize].rect.y, 26.0) || !near(cells[9usize].rect.y, 76.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.3, 0.7, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append_matrix(&builder, &marks, ink, paint.rgba(1.0, 1.0, 1.0, 1.0), ink)
    if scene.builder_count(&builder) != 10usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Cohort retention", "Active share by cohort age")
    try chart_svg.append_matrix(&writer, &marks, ink, paint.rgba(1.0, 1.0, 1.0, 1.0), ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad = [3]f64{ 10.0f64, 11.0f64, 5.0f64 }
    let (_, growth_error) = chart.cohort_retention(bad[..], 2usize, bounds, 0.0, cells[..])
    let (_, shape_error) = chart.cohort_retention(counts[..9usize], 4usize, bounds, 0.0, cells[..])
    let (_, gap_error) = chart.cohort_retention(counts[..], 4usize, bounds, 25.0, cells[..])
    let (_, capacity_error) = chart.cohort_retention(counts[..], 4usize, bounds, 0.0, cells[..9usize])
    if growth_error != chart.Invalid || shape_error != chart.Invalid || gap_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart cohort retention ok\n")
    ret ok
}
