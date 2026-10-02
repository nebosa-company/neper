use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.001 && d > -0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(10.0, 20.0, 90.0, 40.0)
    let values = [6]f64{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0 }
    var tile_cells: [6]chart.Cell = zero
    let (tiles, tile_error) = chart.heatmap(values[..], 3usize, bounds, tile_cells[..])
    if tile_error != ok || tiles.kind != .Heatmap || tiles.columns != 3usize || tiles.rows != 2usize || tiles.cells.len != 6usize { ret chart.Invalid }
    if !near(tiles.value_min, 0.0) || !near(tiles.value_max, 5.0) || !near(tiles.cells[0].rect.x, 10.0) || !near(tiles.cells[0].rect.width, 30.0) || !near(tiles.cells[5].rect.y, 40.0) || !near(tiles.cells[5].rect.height, 20.0) { ret chart.Invalid }
    let (_, short_cells) = chart.heatmap(values[..], 3usize, bounds, tile_cells[..5usize])
    if short_cells != chart.TooLarge { ret chart.Invalid }
    let (_, bad_shape) = chart.heatmap(values[..], 4usize, bounds, tile_cells[..])
    if bad_shape != chart.Invalid { ret chart.Invalid }
    let observations = [12]f64{ 1.0, 1.0, 4.0, 2.0, 2.0, 3.0, 3.0, 3.0, 2.0, 4.0, 4.0, 1.0 }
    var x: [4]f64 = zero
    var y: [4]f64 = zero
    var corr_cells: [9]chart.Cell = zero
    let (corr, corr_error) = chart.correlation_matrix(observations[..], 3usize, bounds, x[..], y[..], corr_cells[..])
    if corr_error != ok || corr.kind != .Correlation || corr.cells.len != 9usize || !near(corr.value_min, -1.0) || !near(corr.value_max, 1.0) { ret chart.Invalid }
    if !near(corr.cells[0].value, 1.0) || !near(corr.cells[1].value, 1.0) || !near(corr.cells[2].value, -1.0) || !near(corr.cells[6].value, -1.0) { ret chart.Invalid }
    let (_, short_scratch) = chart.correlation_matrix(observations[..], 3usize, bounds, x[..3usize], y[..], corr_cells[..])
    if short_scratch != chart.TooLarge { ret chart.Invalid }
    let constant = [6]f64{ 1.0, 2.0, 1.0, 3.0, 1.0, 4.0 }
    let (_, undefined_corr) = chart.correlation_matrix(constant[..], 2usize, bounds, x[..], y[..], corr_cells[..])
    if undefined_corr != chart.Invalid { ret chart.Invalid }
    var panels: [3]geometry.Rect = zero
    let (grid, grid_error) = chart.facet_grid(geometry.rect(0.0, 0.0, 100.0, 60.0), 2usize, 3usize, 10.0, panels[..])
    if grid_error != ok || grid.len != 3usize || !near(grid[0].width, 45.0) || !near(grid[0].height, 25.0) || !near(grid[1].x, 55.0) || !near(grid[2].y, 35.0) { ret chart.Invalid }
    let (_, small_grid) = chart.facet_grid(bounds, 2usize, 3usize, 1.0, panels[..2usize])
    if small_grid != chart.TooLarge { ret chart.Invalid }
    let (made_builder, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made_builder
    let low = paint.rgba(0.1, 0.2, 0.8, 1.0)
    let middle = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let high = paint.rgba(0.9, 0.2, 0.1, 1.0)
    if chart_scene.append_matrix(&builder, &tiles, low, middle, high) != ok { ret chart.Invalid }
    if chart_scene.append_matrix(&builder, &corr, low, middle, high) != ok { ret chart.Invalid }
    if scene.builder_count(&builder) != 15usize { ret chart.Invalid }
    try io.print("gfx chart matrix ok\n")
    ret ok
}
