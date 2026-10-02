use e.fs
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str
use e.text.shape

fn near(a: f32, b: f32) -> bool {
    let delta = a - b
    ret delta > -0.01 && delta < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret chart.Invalid }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let values = [8]f32{ 3.0, 2.0, 5.0, 4.0, 2.0, 6.0, 4.0, 3.0 }
    var bars: [8]geometry.Rect = zero
    var layers: [2]chart.Layout = zero
    let (grouped, grouped_error) = chart.grouped_bars(values[..], 4usize, 2usize, bounds, bars[..], layers[..])
    if grouped_error != ok || grouped.len != 2usize || grouped[0].kind != .Bar || grouped[0].bars.len != 4usize || !near(grouped[0].bars[0].x, 2.5) || !near(grouped[0].bars[0].y, 50.0) || !near(grouped[1].bars[0].x, 12.5) || !near(grouped[0].y_max, 6.0) { ret chart.Invalid }
    var category_ticks: [4]chart.Tick = zero
    let (centers, center_error) = chart.category_ticks(4usize, category_ticks[..])
    if center_error != ok || centers.len != 4usize || !near(centers[0].fraction, 0.125) || !near(centers[3].fraction, 0.875) { ret chart.Invalid }
    let names = [4]str{ "North", "South", "East", "West" }
    var category_labels: [4]chart.Label = zero
    let (_, label_error) = chart.guide_labels(bounds, centers, names[..], centers[..0usize], names[..0usize], 10.0, category_labels[..])
    if label_error != ok || !near(category_labels[0].anchor.x, 12.5) { ret chart.Invalid }
    let series_names = [2]str{ "A < B", "B & C" }
    var legend: [2]chart.LegendItem = zero
    let (entries, legend_error) = chart.legend_items(series_names[..], chart.Coord { x: 120.0, y: 20.0 }, 10.0, 20.0, legend[..])
    if legend_error != ok || entries.len != 2usize || !near(entries[1].swatch.y, 40.0) || !near(entries[0].label.anchor.x, 136.0) { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let (font_bytes, font_error) = fs.read_file(a, args[1usize], 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.4, 0.1, 1.0)
    try chart_scene.append(a, &builder, &grouped[0], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &grouped[1], paint.Brush { Solid: orange })
    try chart_scene.append_labels(a, &builder, category_labels[..], font, 10.0, paint.Brush { Solid: blue })
    var legend_labels: [2]chart.Label = zero
    legend_labels[0] = entries[0].label
    legend_labels[1] = entries[1].label
    try chart_scene.append_labels(a, &builder, legend_labels[..], font, 10.0, paint.Brush { Solid: blue })
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: entries[0].swatch, brush: paint.Brush { Solid: blue } } })
    try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: entries[1].swatch, brush: paint.Brush { Solid: orange } } })
    if scene.builder_count(&builder) != 16usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Bars", "Two series")
    try chart_svg.append(&writer, &grouped[0], blue)
    try chart_svg.append(&writer, &grouped[1], orange)
    try chart_svg.append_labels(&writer, category_labels[..], blue, 10.0)
    try chart_svg.rect(&writer, entries[0].swatch, blue, false)
    try chart_svg.rect(&writer, entries[1].swatch, orange, false)
    try chart_svg.append_labels(&writer, legend_labels[..], blue, 10.0)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "North") || !str.contains(svg, "A &lt; B") || !str.contains(svg, "B &amp; C") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let signed = [8]f32{ 3.0, 2.0, 5.0, -2.0, 2.0, 6.0, 4.0, -1.0 }
    let (stacked, stacked_error) = chart.stacked_bars(signed[..], 4usize, 2usize, bounds, false, bars[..], layers[..])
    if stacked_error != ok || stacked.len != 2usize || !near(stacked[0].y_min, -2.0) || !near(stacked[0].y_max, 8.0) || !near(stacked[1].bars[1].y, 80.0) || !near(stacked[1].bars[1].height, 20.0) { ret chart.Invalid }
    let (normalized, normalized_error) = chart.stacked_bars(values[..], 4usize, 2usize, bounds, true, bars[..], layers[..])
    if normalized_error != ok || !near(normalized[0].y_min, 0.0) || !near(normalized[0].y_max, 1.0) || !near(normalized[0].bars[0].y, 40.0) || !near(normalized[1].bars[0].height, 40.0) { ret chart.Invalid }
    let (_, bad_shape) = chart.grouped_bars(values[..7usize], 4usize, 2usize, bounds, bars[..], layers[..])
    if bad_shape != chart.Invalid { ret chart.Invalid }
    let (_, short_storage) = chart.grouped_bars(values[..], 4usize, 2usize, bounds, bars[..7usize], layers[..])
    if short_storage != chart.TooLarge { ret chart.Invalid }
    let (_, mixed_normalized) = chart.stacked_bars(signed[..], 4usize, 2usize, bounds, true, bars[..], layers[..])
    if mixed_normalized != chart.Invalid { ret chart.Invalid }
    let zeros = [2]f32{ 0.0, 0.0 }
    let (_, zero_normalized) = chart.stacked_bars(zeros[..], 1usize, 2usize, bounds, true, bars[..], layers[..])
    if zero_normalized != chart.Invalid { ret chart.Invalid }
    let bridge_values = [4]f32{ 10.0, 4.0, -6.0, 3.0 }
    var bridge_bars: [5]geometry.Rect = zero
    var bridge_links: [4]chart.Segment = zero
    let (bridge, bridge_error) = chart.waterfall(bridge_values[..], bounds, bridge_bars[..], bridge_links[..])
    if bridge_error != ok || bridge.kind != .Waterfall || bridge.bars.len != 5usize || bridge.segments.len != 4usize || !near(bridge.y_max, 14.0) || !near(bridge_bars[2].y, 0.0) || !near(bridge_bars[2].height, 42.86) || !near(bridge_bars[4].height, 78.57) || !near(bridge_links[2].from.y, bridge_links[2].to.y) { ret chart.Invalid }
    let (bridge_short, bridge_short_error) = chart.waterfall(bridge_values[..], bounds, bridge_bars[..4usize], bridge_links[..])
    if bridge_short_error != chart.TooLarge { ret chart.Invalid }
    let (_, bridge_links_error) = chart.waterfall(bridge_values[..], bounds, bridge_bars[..], bridge_links[..3usize])
    if bridge_links_error != chart.TooLarge { ret chart.Invalid }
    let invalid_bridge = [2]f32{ 10.0, 1.0 / 0.0 }
    let (_, bridge_invalid_error) = chart.waterfall(invalid_bridge[..], bounds, bridge_bars[..], bridge_links[..])
    if bridge_invalid_error != chart.Invalid { ret chart.Invalid }
    let (bridge_builder_made, bridge_builder_error) = scene.builder(a, 16usize)
    if bridge_builder_error != ok { ret bridge_builder_error }
    var bridge_builder = bridge_builder_made
    try chart_scene.append(a, &bridge_builder, &bridge, paint.Brush { Solid: blue })
    if scene.builder_count(&bridge_builder) != 9usize { ret chart.Invalid }
    let (bridge_state, bridge_writer_error_unused, bridge_writer_error) = io.memory_writer(a, 0usize)
    if bridge_writer_error != ok { ret bridge_writer_error }
    var bridge_held = bridge_state
    var bridge_writer = io.writer(mem.cast[*void](&bridge_held), io.memory_write)
    try chart_svg.append(&bridge_writer, &bridge, blue)
    let bridge_svg = io.memory_bytes(&bridge_held)
    if !str.contains(bridge_svg, "<rect") || !str.contains(bridge_svg, "<line") { ret chart.Invalid }
    let thresholds = [3]f32{ 40.0, 70.0, 100.0 }
    var bullet_bars: [4]geometry.Rect = zero
    var bullet_line: [1]chart.Segment = zero
    var bullet_layers: [5]chart.Layout = zero
    let (bullet, bullet_error) = chart.bullet(62.0, 80.0, thresholds[..], bounds, bullet_bars[..], bullet_line[..], bullet_layers[..])
    if bullet_error != ok || bullet.len != 5usize || bullet[4].kind != .Rug || !near(bullet_bars[0].width, 100.0) || !near(bullet_bars[1].width, 70.0) || !near(bullet_bars[2].width, 40.0) || !near(bullet_bars[3].width, 62.0) || !near(bullet_bars[3].y, 32.5) || !near(bullet_line[0].from.x, 80.0) { ret chart.Invalid }
    let (_, bullet_short) = chart.bullet(62.0, 80.0, thresholds[..], bounds, bullet_bars[..3usize], bullet_line[..], bullet_layers[..])
    if bullet_short != chart.TooLarge { ret chart.Invalid }
    let (_, bullet_target_outside) = chart.bullet(62.0, 101.0, thresholds[..], bounds, bullet_bars[..], bullet_line[..], bullet_layers[..])
    if bullet_target_outside != chart.Invalid { ret chart.Invalid }
    let descending = [3]f32{ 40.0, 70.0, 60.0 }
    let (_, bullet_bad_ranges) = chart.bullet(62.0, 80.0, descending[..], bounds, bullet_bars[..], bullet_line[..], bullet_layers[..])
    if bullet_bad_ranges != chart.Invalid { ret chart.Invalid }
    let (bullet_builder_made, bullet_builder_error) = scene.builder(a, 8usize)
    if bullet_builder_error != ok { ret bullet_builder_error }
    var bullet_builder = bullet_builder_made
    var bullet_i = 0usize
    while bullet_i < bullet.len {
        try chart_scene.append(a, &bullet_builder, &bullet[bullet_i], paint.Brush { Solid: blue })
        bullet_i += 1usize
    }
    if scene.builder_count(&bullet_builder) != 5usize { ret chart.Invalid }
    let (bullet_state, bullet_unused, bullet_writer_error) = io.memory_writer(a, 0usize)
    if bullet_writer_error != ok { ret bullet_writer_error }
    var bullet_held = bullet_state
    var bullet_writer = io.writer(mem.cast[*void](&bullet_held), io.memory_write)
    bullet_i = 0usize
    while bullet_i < bullet.len {
        try chart_svg.append(&bullet_writer, &bullet[bullet_i], blue)
        bullet_i += 1usize
    }
    if !str.contains(io.memory_bytes(&bullet_held), "<line") { ret chart.Invalid }
    let (_, short_ticks) = chart.category_ticks(4usize, category_ticks[..3usize])
    if short_ticks != chart.TooLarge { ret chart.Invalid }
    let (_, no_ticks) = chart.category_ticks(0usize, category_ticks[..])
    if no_ticks != chart.Empty { ret chart.Invalid }
    let (_, short_legend) = chart.legend_items(series_names[..], chart.Coord { x: 0.0, y: 0.0 }, 10.0, 20.0, legend[..1usize])
    if short_legend != chart.TooLarge { ret chart.Invalid }
    let invalid_names = [1]str{ "bad\nname" }
    let (_, invalid_legend) = chart.legend_items(invalid_names[..], chart.Coord { x: 0.0, y: 0.0 }, 10.0, 20.0, legend[..])
    if invalid_legend != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart composition ok\n")
    ret ok
}
