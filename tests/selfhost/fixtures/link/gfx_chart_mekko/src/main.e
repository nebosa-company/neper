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
    let values = [4]f32{ 3.0, 1.0, 2.0, 6.0 }
    let bounds = geometry.rect(0.0, 0.0, 120.0, 100.0)
    var totals: [3]f64 = zero
    var bars: [6]geometry.Rect = zero
    var storage: [2]chart.Layout = zero
    let (layers, layout_error) = chart.mekko(values[..], 2usize, 2usize, bounds, totals[..], bars[..], storage[..])
    if layout_error != ok || layers.len != 2usize || layers[0usize].kind != .Bar || layers[0usize].bars.len != 2usize || !near(layers[0usize].x_max, 1.0) || !near(layers[0usize].y_max, 1.0) || !near(f32(totals[0usize]), 4.0) || !near(f32(totals[1usize]), 8.0) || !near(bars[0usize].width, 40.0) || !near(bars[1usize].x, 40.0) || !near(bars[1usize].width, 80.0) || !near(bars[0usize].y, 25.0) || !near(bars[0usize].height, 75.0) || !near(bars[3usize].y, 0.0) || !near(bars[3usize].height, 75.0) || !near(bars[0usize].width * bars[0usize].height / (bounds.width * bounds.height), 0.25) { ret chart.Invalid }
    let with_zero = [6]f32{ 3.0, 1.0, 0.0, 0.0, 2.0, 6.0 }
    let (zero_layers, zero_error) = chart.mekko(with_zero[..], 3usize, 2usize, bounds, totals[..], bars[..], storage[..])
    if zero_error != ok || zero_layers.len != 2usize || !near(bars[1usize].width, 0.0) || !near(bars[4usize].height, 0.0) || !near(bars[2usize].x, 40.0) { ret chart.Invalid }
    let negative = [4]f32{ 3.0, -1.0, 2.0, 6.0 }
    let (_, negative_error) = chart.mekko(negative[..], 2usize, 2usize, bounds, totals[..], bars[..], storage[..])
    if negative_error != chart.Invalid { ret chart.Invalid }
    let empty = [4]f32{ 0.0, 0.0, 0.0, 0.0 }
    let (_, empty_error) = chart.mekko(empty[..], 2usize, 2usize, bounds, totals[..], bars[..], storage[..])
    if empty_error != chart.Empty { ret chart.Invalid }
    let (_, shape_error) = chart.mekko(values[..3usize], 2usize, 2usize, bounds, totals[..], bars[..], storage[..])
    if shape_error != chart.Invalid { ret chart.Invalid }
    let (_, capacity_error) = chart.mekko(values[..], 2usize, 2usize, bounds, totals[..], bars[..3usize], storage[..])
    if capacity_error != chart.TooLarge { ret chart.Invalid }
    let (again, again_error) = chart.mekko(values[..], 2usize, 2usize, bounds, totals[..], bars[..], storage[..])
    if again_error != ok { ret again_error }
    let counts = [4]f64{ 3.0, 1.0, 2.0, 6.0 }
    var mosaic_columns: [2]f64 = zero
    var mosaic_rows: [2]f64 = zero
    var mosaic_cells: [4]chart.Cell = zero
    let (mosaic, mosaic_error) = chart.mosaic(counts[..], 2usize, bounds, 2.0, mosaic_columns[..], mosaic_rows[..], mosaic_cells[..])
    if mosaic_error != ok || mosaic.kind != .Mosaic || mosaic.cells.len != 4usize || !near(f32(mosaic_columns[0usize]), 4.0) || !near(f32(mosaic_rows[0usize]), 5.0) || !near(mosaic.cells[0usize].rect.x, 1.0) || !near(mosaic.cells[0usize].rect.y, 26.0) || !near(mosaic.cells[0usize].rect.width, 38.0) || !near(mosaic.cells[0usize].rect.height, 73.0) || !near(mosaic.cells[0usize].value, 1.0328) || !near(mosaic.cells[1usize].value, -0.8729) || !near(mosaic.value_max, 1.0328) { ret chart.Invalid }
    let sparse = [4]f64{ 3.0, 0.0, 0.0, 6.0 }
    let (sparse_mosaic, sparse_error) = chart.mosaic(sparse[..], 2usize, bounds, 2.0, mosaic_columns[..], mosaic_rows[..], mosaic_cells[..])
    if sparse_error != ok || sparse_mosaic.cells.len != 2usize { ret chart.Invalid }
    let negative_counts = [4]f64{ 3.0, -1.0, 2.0, 6.0 }
    let (_, mosaic_negative) = chart.mosaic(negative_counts[..], 2usize, bounds, 2.0, mosaic_columns[..], mosaic_rows[..], mosaic_cells[..])
    if mosaic_negative != chart.Invalid { ret chart.Invalid }
    let empty_counts = [4]f64{ 0.0, 0.0, 0.0, 0.0 }
    let (_, mosaic_empty) = chart.mosaic(empty_counts[..], 2usize, bounds, 2.0, mosaic_columns[..], mosaic_rows[..], mosaic_cells[..])
    if mosaic_empty != chart.Empty { ret chart.Invalid }
    let (_, mosaic_short) = chart.mosaic(counts[..], 2usize, bounds, 2.0, mosaic_columns[..], mosaic_rows[..], mosaic_cells[..3usize])
    if mosaic_short != chart.TooLarge { ret chart.Invalid }
    let (_, mosaic_gutter) = chart.mosaic(counts[..], 2usize, bounds, 26.0, mosaic_columns[..], mosaic_rows[..], mosaic_cells[..])
    if mosaic_gutter != chart.Invalid { ret chart.Invalid }
    let (again_mosaic, again_mosaic_error) = chart.mosaic(counts[..], 2usize, bounds, 2.0, mosaic_columns[..], mosaic_rows[..], mosaic_cells[..])
    if again_mosaic_error != ok { ret again_mosaic_error }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    var i = 0usize
    while i < again.len {
        try chart_scene.append(a, &builder, &again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    let low = paint.rgba(0.85, 0.25, 0.25, 1.0)
    let middle = paint.rgba(0.96, 0.96, 0.96, 1.0)
    try chart_scene.append_matrix(&builder, &again_mosaic, low, middle, blue)
    if scene.builder_count(&builder) != 8usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 100.0, "Mekko", "Area-proportional cells")
    i = 0usize
    while i < again.len {
        try chart_svg.append(&writer, &again[i], blue)
        i += 1usize
    }
    try chart_svg.append_matrix(&writer, &again_mosaic, low, middle, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart mekko ok\n")
    ret ok
}
