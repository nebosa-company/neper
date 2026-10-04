use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.001f32 && b - a < 0.001f32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let parents = [6]usize{ 0usize, 0usize, 1usize, 1usize, 0usize, 4usize }
    let weights = [6]f32{ 0.0, 0.0, 30.0, 20.0, 0.0, 50.0 }
    let bounds = geometry.rect(10.0, 20.0, 330.0, 160.0)
    var totals: [6]f64 = zero
    var depths: [6]usize = zero
    var spans: [6]geometry.Rect = zero
    var cards: [6]geometry.Rect = zero
    var bars: [6]geometry.Rect = zero
    var links: [15]chart.Segment = zero
    let (tree, tree_error) = chart.aggregate_decomposition_tree(parents[..], weights[..], bounds, totals[..], depths[..], spans[..], cards[..], bars[..], links[..])
    if tree_error != ok || tree.levels != 3usize || tree.leaves != 3usize || tree.nodes.bars.len != 6usize || tree.connectors.segments.len != 15usize { ret chart.Invalid }
    if totals[0usize] != 100.0f64 || totals[1usize] != 50.0f64 || totals[4usize] != 50.0f64 || totals[2usize] != 30.0f64 { ret chart.Invalid }
    if depths[3usize] != 2usize || !near(spans[1usize].height, 2.0) || !near(bars[1usize].width / bars[0usize].width, 0.5) || !near(bars[2usize].width / bars[0usize].width, 0.6) { ret chart.Invalid }
    if cards[0usize].x >= cards[1usize].x || cards[1usize].x >= cards[2usize].x || cards[2usize].y >= cards[3usize].y { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &tree.connectors, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &tree.nodes, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &tree.value_bars, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Aggregate tree", "Roll-up values")
    try chart_svg.append(&writer, &tree.connectors, ink)
    try chart_svg.append(&writer, &tree.nodes, ink)
    try chart_svg.append(&writer, &tree.value_bars, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "<line") { ret chart.Invalid }
    let (_, empty_error) = chart.aggregate_decomposition_tree(parents[..0usize], weights[..0usize], bounds, totals[..], depths[..], spans[..], cards[..], bars[..], links[..])
    let (_, short_error) = chart.aggregate_decomposition_tree(parents[..], weights[..], bounds, totals[..], depths[..], spans[..], cards[..], bars[..], links[..14usize])
    let (_, small_error) = chart.aggregate_decomposition_tree(parents[..], weights[..], geometry.rect(0.0, 0.0, 50.0, 50.0), totals[..], depths[..], spans[..], cards[..], bars[..], links[..])
    let bad_order = [6]usize{ 0usize, 0usize, 0usize, 1usize, 1usize, 2usize }
    let reordered_weights = [6]f32{ 0.0, 0.0, 0.0, 30.0, 20.0, 50.0 }
    let (_, order_error) = chart.aggregate_decomposition_tree(bad_order[..], reordered_weights[..], bounds, totals[..], depths[..], spans[..], cards[..], bars[..], links[..])
    let bad_weights = [6]f32{ 0.0, 0.0, 30.0, -20.0, 0.0, 50.0 }
    let (_, weight_error) = chart.aggregate_decomposition_tree(parents[..], bad_weights[..], bounds, totals[..], depths[..], spans[..], cards[..], bars[..], links[..])
    if empty_error != chart.Empty || short_error != chart.TooLarge || small_error != chart.TooLarge || order_error != chart.Invalid || weight_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart aggregate tree ok\n")
    ret ok
}
