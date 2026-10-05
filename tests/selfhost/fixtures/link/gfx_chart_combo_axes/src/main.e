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
    let delta = a - b
    ret delta > -0.01 && delta < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let missing = f32(math.nan64())
    let bar_x = [4]f32{ 0.0, 1.0, 2.0, 3.0 }
    let bar_y = [4]f32{ 2.0, 4.0, missing, 8.0 }
    let index_y = [4]f32{ 100.0, missing, 300.0, 400.0 }
    let rate_x = [2]f32{ 0.5, 2.5 }
    let rate_y = [2]f32{ -1.0, 1.0 }
    let gap_x = [5]f32{ 0.0, 0.75, 1.5, 2.25, 3.0 }
    let gap_y = [5]f32{ 1.0, 2.0, missing, 3.0, 4.0 }
    let series = [4]chart.ComboSeries{
        chart.ComboSeries { mark: .Bar, axis: 0usize, x: bar_x[..], y: bar_y[..] },
        chart.ComboSeries { mark: .PointLine, axis: 1usize, x: bar_x[..], y: index_y[..] },
        chart.ComboSeries { mark: .Line, axis: 2usize, x: rate_x[..], y: rate_y[..] },
        chart.ComboSeries { mark: .Line, axis: 0usize, x: gap_x[..], y: gap_y[..] },
    }
    var coords: [4]chart.Coord = zero
    var segments: [9]chart.Segment = zero
    var bars: [4]geometry.Rect = zero
    var layers: [4]chart.Layout = zero
    var axes: [3]chart.ComboAxis = zero
    let storage = chart.ComboStorage { coords: coords[..], segments: segments[..], bars: bars[..], layers: layers[..], axes: axes[..] }
    let (combo, combo_error) = chart.combo(series[..], 3usize, bounds, 0.0, storage)
    if combo_error != ok { ret combo_error }
    if combo.layers.len != 4usize || combo.axes.len != 3usize || combo.missing != 3usize || !near(combo.x_min, -0.5) || !near(combo.x_max, 3.5) { ret chart.Invalid }
    if !near(combo.axes[0usize].y_min, 0.0) || !near(combo.axes[0usize].y_max, 8.0) || !near(combo.axes[1usize].y_min, 100.0) || !near(combo.axes[1usize].y_max, 400.0) || !near(combo.axes[2usize].y_min, -1.0) || !near(combo.axes[2usize].y_max, 1.0) { ret chart.Invalid }
    let columns = combo.layers[0usize]
    if columns.kind != .Bar || columns.bars.len != 3usize || !near(columns.bars[0usize].x, 2.5) || !near(columns.bars[0usize].width, 20.0) || !near(columns.bars[0usize].y, 75.0) || !near(columns.bars[0usize].height, 25.0) || !near(columns.bars[2usize].x, 77.5) || !near(columns.bars[2usize].y, 0.0) { ret chart.Invalid }
    let index = combo.layers[1usize]
    if index.kind != .PointLine || index.coords.len != 3usize || index.segments.len != 1usize || !near(index.coords[0usize].x, 12.5) || !near(index.coords[0usize].y, 100.0) || !near(index.coords[1usize].y, 33.33) || !near(index.segments[0usize].from.x, 62.5) || !near(index.segments[0usize].to.y, 0.0) || !near(index.y_max, 400.0) { ret chart.Invalid }
    let rate = combo.layers[2usize]
    if rate.segments.len != 1usize || !near(rate.segments[0usize].from.x, 25.0) || !near(rate.segments[0usize].from.y, 100.0) || !near(rate.segments[0usize].to.x, 75.0) || !near(rate.segments[0usize].to.y, 0.0) { ret chart.Invalid }
    let broken = combo.layers[3usize]
    if broken.segments.len != 2usize || !near(broken.segments[0usize].to.x, 31.25) || !near(broken.segments[1usize].from.x, 68.75) || !near(broken.y_max, 8.0) { ret chart.Invalid }
    // Axis rules: left at the plot edge, right at its edge, a third right one 40 px out.
    var tick_storage: [4]chart.Tick = zero
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    let (index_ticks, tick_error) = chart.nice_ticks(linear, combo.axes[1usize].y_min, combo.axes[1usize].y_max, 4usize, tick_storage[..])
    if tick_error != ok { ret tick_error }
    var words: [4]str = zero
    var word_bytes: [64]u8 = zero
    let (index_words, word_error) = chart.format_ticks(index_ticks, words[..], word_bytes[..])
    if word_error != ok { ret word_error }
    var right_rules: [5]chart.Segment = zero
    var right_labels: [4]chart.Label = zero
    let (right_axis, right_text, right_error) = chart.side_axis(bounds, index_ticks, index_words, true, 0.0, 9.0, right_rules[..], right_labels[..])
    if right_error != ok { ret right_error }
    if right_axis.kind != .Rug || right_axis.segments.len != 5usize || right_text.len != 4usize || !near(right_axis.segments[0usize].from.x, 100.0) || !near(right_axis.segments[1usize].to.x, 105.0) || !near(right_axis.segments[1usize].to.y, 100.0) || !near(right_axis.segments[2usize].from.y, 66.67) || right_text[0usize].align != .Left || !near(right_text[0usize].anchor.x, 109.0) || !str.eq(right_text[3usize].text, "400") { ret chart.Invalid }
    var third_rules: [5]chart.Segment = zero
    var third_labels: [4]chart.Label = zero
    let (third_axis, _, third_error) = chart.side_axis(bounds, index_ticks, index_words, true, 40.0, 9.0, third_rules[..], third_labels[..])
    if third_error != ok || !near(third_axis.segments[0usize].from.x, 140.0) { ret chart.Invalid }
    var left_rules: [5]chart.Segment = zero
    var left_labels: [4]chart.Label = zero
    let (left_axis, left_text, left_error) = chart.side_axis(bounds, index_ticks, index_words, false, 0.0, 9.0, left_rules[..], left_labels[..])
    if left_error != ok || !near(left_axis.segments[1usize].to.x, -5.0) || left_text[0usize].align != .Right || !near(left_text[0usize].anchor.x, -9.0) { ret chart.Invalid }
    let (_, _, short_rules_error) = chart.side_axis(bounds, index_ticks, index_words, true, 0.0, 9.0, right_rules[..4usize], right_labels[..])
    if short_rules_error != chart.TooLarge { ret chart.Invalid }
    let (_, _, words_error) = chart.side_axis(bounds, index_ticks, index_words[..3usize], true, 0.0, 9.0, right_rules[..], right_labels[..])
    if words_error != chart.Invalid { ret chart.Invalid }
    // An axis table: each cell centred on its bar; an empty cell is a missing value.
    let titles = [2]str{ "n", "" }
    let cells = [8]str{ "12", "15", "", "18", "a", "b", "c", "d" }
    var table_labels: [8]chart.Label = zero
    let (table, table_error) = chart.axis_table(bar_x[..], &columns, bounds, titles[..], cells[..], 110.0, 12.0, table_labels[..])
    if table_error != ok { ret table_error }
    if table.len != 8usize || !str.eq(table[0usize].text, "n") || table[0usize].align != .Right || !near(table[0usize].anchor.y, 122.0) || !near(table[1usize].anchor.x, columns.bars[0usize].x + columns.bars[0usize].width / 2.0) || !near(table[3usize].anchor.x, 87.5) || table[3usize].align != .Center || !near(table[4usize].anchor.y, 134.0) || !str.eq(table[7usize].text, "d") { ret chart.Invalid }
    let (_, short_table_error) = chart.axis_table(bar_x[..], &columns, bounds, titles[..], cells[..], 110.0, 12.0, table_labels[..7usize])
    if short_table_error != chart.TooLarge { ret chart.Invalid }
    let (_, cells_error) = chart.axis_table(bar_x[..], &columns, bounds, titles[..], cells[..7usize], 110.0, 12.0, table_labels[..])
    if cells_error != chart.Invalid { ret chart.Invalid }
    let outside_x = [4]f32{ 0.0, 1.0, 2.0, 4.0 }
    let (_, outside_error) = chart.axis_table(outside_x[..], &columns, bounds, titles[..], cells[..], 110.0, 12.0, table_labels[..])
    if outside_error != chart.Invalid { ret chart.Invalid }
    // Refusals: an unknown axis, infinity, a missing x, unordered bars, an axis with no values, short pools.
    let wrong_axis = [1]chart.ComboSeries{ chart.ComboSeries { mark: .Bar, axis: 3usize, x: bar_x[..], y: bar_y[..] } }
    let (_, axis_error) = chart.combo(wrong_axis[..], 3usize, bounds, 0.0, storage)
    if axis_error != chart.Invalid { ret chart.Invalid }
    let endless_y = [2]f32{ 1.0, f32(math.inf64()) }
    let endless = [1]chart.ComboSeries{ chart.ComboSeries { mark: .Line, axis: 0usize, x: rate_x[..], y: endless_y[..] } }
    let (_, endless_error) = chart.combo(endless[..], 1usize, bounds, 0.0, storage)
    if endless_error != chart.Invalid { ret chart.Invalid }
    let unknown_x = [2]f32{ 0.5, missing }
    let unknown = [1]chart.ComboSeries{ chart.ComboSeries { mark: .Scatter, axis: 0usize, x: unknown_x[..], y: rate_y[..] } }
    let (_, unknown_error) = chart.combo(unknown[..], 1usize, bounds, 0.0, storage)
    if unknown_error != chart.Invalid { ret chart.Invalid }
    let backwards_x = [2]f32{ 2.5, 0.5 }
    let backwards = [1]chart.ComboSeries{ chart.ComboSeries { mark: .Bar, axis: 0usize, x: backwards_x[..], y: rate_y[..] } }
    let (_, backwards_error) = chart.combo(backwards[..], 1usize, bounds, 0.0, storage)
    if backwards_error != chart.Invalid { ret chart.Invalid }
    let empty_y = [2]f32{ missing, missing }
    let unused_axis = [2]chart.ComboSeries{ chart.ComboSeries { mark: .Line, axis: 0usize, x: rate_x[..], y: rate_y[..] }, chart.ComboSeries { mark: .Line, axis: 1usize, x: rate_x[..], y: empty_y[..] } }
    let (_, unused_axis_error) = chart.combo(unused_axis[..], 2usize, bounds, 0.0, storage)
    if unused_axis_error != chart.Invalid { ret chart.Invalid }
    let area = [1]chart.ComboSeries{ chart.ComboSeries { mark: .Area, axis: 0usize, x: rate_x[..], y: rate_y[..] } }
    let (_, area_error) = chart.combo(area[..], 1usize, bounds, 0.0, storage)
    if area_error != chart.Invalid { ret chart.Invalid }
    let short = chart.ComboStorage { coords: coords[..], segments: segments[..3usize], bars: bars[..], layers: layers[..], axes: axes[..] }
    let (_, short_error) = chart.combo(series[..], 3usize, bounds, 0.0, short)
    if short_error != chart.TooLarge { ret chart.Invalid }
    let few_axes = chart.ComboStorage { coords: coords[..], segments: segments[..], bars: bars[..], layers: layers[..], axes: axes[..2usize] }
    let (_, few_axes_error) = chart.combo(series[..], 3usize, bounds, 0.0, few_axes)
    if few_axes_error != chart.TooLarge { ret chart.Invalid }
    let (again, again_error) = chart.combo(series[..], 3usize, bounds, 0.0, storage)
    if again_error != ok { ret again_error }
    // Both adapters break the gapped line instead of bridging it.
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    var i = 0usize
    while i < again.layers.len {
        try chart_scene.append(a, &builder, &again.layers[i], paint.Brush { Solid: paint.rgba(0.1, 0.3, 0.8, 1.0) })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &right_axis, paint.Brush { Solid: paint.rgba(0.3, 0.3, 0.3, 1.0) })
    if scene.builder_count(&builder) != 14usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 160.0, 140.0, "Combo", "Bars, an index and a rate on three axes")
    try chart_svg.append(&writer, &again.layers[3usize], paint.rgba(0.1, 0.3, 0.8, 1.0))
    try chart_svg.append(&writer, &right_axis, paint.rgba(0.3, 0.3, 0.3, 1.0))
    try chart_svg.append_labels(&writer, table, paint.rgba(0.3, 0.3, 0.3, 1.0), 9.0)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path d=\"M12.5 87.5 L31.25 75 M68.75 62.5 L87.5 50\"") || !str.contains(svg, "<line") || !str.contains(svg, ">18<") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart combo axes ok\n")
    ret ok
}
