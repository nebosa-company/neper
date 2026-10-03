use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.math
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
    var association_cells: [4]chart.Cell = zero
    var association_baselines: [2]chart.Segment = zero
    let (association, association_error) = chart.association(counts[..], 2usize, bounds, 0.1, mosaic_columns[..], mosaic_rows[..], association_cells[..], association_baselines[..])
    if association_error != ok || association.kind != .Association || association.cells.len != 4usize { ret chart.Invalid }
    if !near(association.cells[0usize].value, 1.0328) || !near(association.cells[2usize].value, -0.8729) { ret chart.Invalid }
    if !near(association_baselines[0usize].from.y, 25.0) || !near(association_baselines[1usize].from.y, 75.0) || association.cells[0usize].rect.y >= 25.0 || association.cells[1usize].rect.y != 25.0 || association.cells[2usize].rect.y != 75.0 { ret chart.Invalid }
    let first_expected = 5.0f64 * 4.0f64 / 12.0f64
    let second_expected = 7.0f64 * 4.0f64 / 12.0f64
    if !near(association.cells[0usize].rect.width / association.cells[2usize].rect.width, f32(math.sqrt[f64](first_expected / second_expected))) { ret chart.Invalid }
    let first_area = association.cells[0usize].rect.width * association.cells[0usize].rect.height / f32(3.0f64 - first_expected)
    let fourth_expected = 7.0f64 * 8.0f64 / 12.0f64
    let fourth_area = association.cells[3usize].rect.width * association.cells[3usize].rect.height / f32(6.0f64 - fourth_expected)
    if !near(first_area, fourth_area) { ret chart.Invalid }
    let independent = [4]f64{ 1.0, 1.0, 1.0, 1.0 }
    let (independent_plot, independent_error) = chart.association(independent[..], 2usize, bounds, 0.1, mosaic_columns[..], mosaic_rows[..], association_cells[..], association_baselines[..])
    if independent_error != ok || independent_plot.cells.len != 0usize || !near(independent_plot.value_max, 1.0) { ret chart.Invalid }
    let zero_row = [4]f64{ 3.0, 0.0, 2.0, 0.0 }
    let (empty_row_plot, empty_row_error) = chart.association(zero_row[..], 2usize, bounds, 0.1, mosaic_columns[..], mosaic_rows[..], association_cells[..], association_baselines[..])
    if empty_row_error != ok || empty_row_plot.cells.len != 0usize || !near(association_baselines[1usize].from.y, 75.0) { ret chart.Invalid }
    let (_, association_negative) = chart.association(negative_counts[..], 2usize, bounds, 0.1, mosaic_columns[..], mosaic_rows[..], association_cells[..], association_baselines[..])
    if association_negative != chart.Invalid { ret chart.Invalid }
    let (_, association_empty) = chart.association(empty_counts[..], 2usize, bounds, 0.1, mosaic_columns[..], mosaic_rows[..], association_cells[..], association_baselines[..])
    if association_empty != chart.Empty { ret chart.Invalid }
    let (_, association_shape) = chart.association(counts[..3usize], 2usize, bounds, 0.1, mosaic_columns[..], mosaic_rows[..], association_cells[..], association_baselines[..])
    if association_shape != chart.Invalid { ret chart.Invalid }
    let (_, association_space) = chart.association(counts[..], 2usize, bounds, 1.0, mosaic_columns[..], mosaic_rows[..], association_cells[..], association_baselines[..])
    if association_space != chart.Invalid { ret chart.Invalid }
    let (_, association_short) = chart.association(counts[..], 2usize, bounds, 0.1, mosaic_columns[..], mosaic_rows[..], association_cells[..3usize], association_baselines[..])
    if association_short != chart.TooLarge { ret chart.Invalid }
    let (again_association, again_association_error) = chart.association(counts[..], 2usize, bounds, 0.1, mosaic_columns[..], mosaic_rows[..], association_cells[..], association_baselines[..])
    if again_association_error != ok { ret again_association_error }
    let fourfold_counts = [4]f64{ 10.0, 2.0, 4.0, 8.0 }
    var fourfold_points: [72]chart.Coord = zero
    var fourfold_rings: [128]chart.Segment = zero
    var fourfold_wedges: [4]chart.Layout = zero
    let (fourfold, fourfold_error) = chart.fourfold(fourfold_counts[..], bounds, 0.95, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if fourfold_error != ok || fourfold.wedges.len != 4usize || fourfold.rings.segments.len != 128usize || !near(f32(fourfold.odds_ratio), 10.0) || fourfold.ci_low <= 1.4f64 || fourfold.ci_low >= 1.5f64 || fourfold.ci_high <= 68.0f64 || fourfold.ci_high >= 70.0f64 { ret chart.Invalid }
    let same_radius = 50.0 - fourfold.wedges[0usize].coords[1usize].y
    let other_radius = 60.0 - fourfold.wedges[1usize].coords[1usize].x
    if !near(same_radius * same_radius / (other_radius * other_radius), f32(math.sqrt[f64](10.0f64))) { ret chart.Invalid }
    let fourfold_zero = [4]f64{ 10.0, 0.0, 4.0, 8.0 }
    let (corrected_fourfold, corrected_error) = chart.fourfold(fourfold_zero[..], bounds, 0.0, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if corrected_error != ok || corrected_fourfold.rings.segments.len != 0usize || corrected_fourfold.odds_ratio <= 0.0f64 { ret chart.Invalid }
    let (neutral_fourfold, neutral_error) = chart.fourfold(independent[..], bounds, 0.0, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if neutral_error != ok || !near(f32(neutral_fourfold.odds_ratio), 1.0) || !near(50.0 - neutral_fourfold.wedges[0usize].coords[1usize].y, 60.0 - neutral_fourfold.wedges[1usize].coords[1usize].x) { ret chart.Invalid }
    let no_counts: [0]f64 = zero
    let (_, fourfold_no_counts) = chart.fourfold(no_counts[..], bounds, 0.95, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if fourfold_no_counts != chart.Empty { ret chart.Invalid }
    let (_, fourfold_negative) = chart.fourfold(negative_counts[..], bounds, 0.95, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if fourfold_negative != chart.Invalid { ret chart.Invalid }
    let (_, fourfold_empty) = chart.fourfold(empty_counts[..], bounds, 0.95, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if fourfold_empty != chart.Empty { ret chart.Invalid }
    let (_, fourfold_confidence) = chart.fourfold(fourfold_counts[..], bounds, 1.0, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if fourfold_confidence != chart.Invalid { ret chart.Invalid }
    let (_, fourfold_shape) = chart.fourfold(fourfold_counts[..3usize], bounds, 0.95, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if fourfold_shape != chart.Invalid { ret chart.Invalid }
    let (_, fourfold_short) = chart.fourfold(fourfold_counts[..], bounds, 0.95, fourfold_points[..71usize], fourfold_rings[..], fourfold_wedges[..])
    if fourfold_short != chart.TooLarge { ret chart.Invalid }
    let (_, fourfold_short_rings) = chart.fourfold(fourfold_counts[..], bounds, 0.95, fourfold_points[..], fourfold_rings[..127usize], fourfold_wedges[..])
    if fourfold_short_rings != chart.TooLarge { ret chart.Invalid }
    let (no_rings, no_rings_error) = chart.fourfold(fourfold_counts[..], bounds, 0.0, fourfold_points[..], fourfold_rings[..0usize], fourfold_wedges[..])
    if no_rings_error != ok || no_rings.rings.segments.len != 0usize { ret chart.Invalid }
    let (again_fourfold, again_fourfold_error) = chart.fourfold(fourfold_counts[..], bounds, 0.95, fourfold_points[..], fourfold_rings[..], fourfold_wedges[..])
    if again_fourfold_error != ok { ret again_fourfold_error }
    let (made, builder_error) = scene.builder(a, 160usize)
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
    try chart_scene.append_matrix(&builder, &again_association, low, middle, blue)
    i = 0usize
    while i < again_fourfold.wedges.len {
        try chart_scene.append(a, &builder, &again_fourfold.wedges[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &again_fourfold.rings, paint.Brush { Solid: low })
    if scene.builder_count(&builder) != 144usize { ret chart.Invalid }
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
    try chart_svg.append_matrix(&writer, &again_association, low, middle, blue)
    try chart_svg.append_matrix(&writer, &independent_plot, low, middle, blue)
    i = 0usize
    while i < again_fourfold.wedges.len {
        try chart_svg.append(&writer, &again_fourfold.wedges[i], blue)
        i += 1usize
    }
    try chart_svg.append(&writer, &again_fourfold.rings, low)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart mekko ok\n")
    ret ok
}
