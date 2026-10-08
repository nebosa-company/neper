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

fn zero_f32() -> f32 { ret 0.0 }

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
    // Selection identity: a card hit names its node; the node's subtree is the drill filter.
    let c2 = cards[2usize]
    let (card_hit, card_found, card_hit_error) = chart.hit_rect(cards[..6usize], zero, chart.Coord { x: c2.x + c2.width * 0.5, y: c2.y + c2.height * 0.5 })
    if card_hit_error != ok || !card_found || card_hit.mark_index != 2usize || card_hit.source_row != 2usize || card_hit.distance_squared > 0.001f64 { ret chart.Invalid }
    let (_, gap_found, gap_error) = chart.hit_rect(cards[..6usize], zero, chart.Coord { x: -5.0, y: -5.0 })
    if gap_error != ok || gap_found { ret chart.Invalid }
    let overlap = [2]geometry.Rect{ geometry.rect(0.0, 0.0, 10.0, 10.0), geometry.rect(5.0, 5.0, 10.0, 10.0) }
    let ids = [2]usize{ 40usize, 41usize }
    let (top_hit, top_found, top_error) = chart.hit_rect(overlap[..], ids[..], chart.Coord { x: 7.0, y: 7.0 })
    let (edge_hit, edge_found, edge_error) = chart.hit_rect(overlap[..], ids[..], chart.Coord { x: 5.0, y: 0.0 })
    if top_error != ok || !top_found || top_hit.mark_index != 1usize || top_hit.source_row != 41usize || edge_error != ok || !edge_found || edge_hit.source_row != 40usize { ret chart.Invalid }
    let (_, ids_error_hit, ids_error) = chart.hit_rect(overlap[..], ids[..1usize], chart.Coord { x: 7.0, y: 7.0 })
    let nan_value = 0.0 / zero_f32()
    let (_, nan_hit, nan_error) = chart.hit_rect(overlap[..], zero, chart.Coord { x: nan_value, y: 1.0 })
    if ids_error != chart.Invalid || ids_error_hit || nan_error != chart.Invalid || nan_hit { ret chart.Invalid }
    var mask: [6]bool = zero
    let (root_leaves, root_error) = chart.tree_subtree_mask(parents[..], 0usize, mask[..])
    if root_error != ok || root_leaves != 3usize || !mask[0usize] || !mask[5usize] { ret chart.Invalid }
    let (branch_leaves, branch_error) = chart.tree_subtree_mask(parents[..], 1usize, mask[..])
    if branch_error != ok || branch_leaves != 2usize || !mask[1usize] || !mask[2usize] || !mask[3usize] || mask[0usize] || mask[4usize] || mask[5usize] { ret chart.Invalid }
    let (leaf_leaves, leaf_error) = chart.tree_subtree_mask(parents[..], 5usize, mask[..])
    if leaf_error != ok || leaf_leaves != 1usize || !mask[5usize] || mask[4usize] || mask[1usize] { ret chart.Invalid }
    let (_, bad_node_leaves) = chart.tree_subtree_mask(parents[..], 6usize, mask[..])
    let (_, short_mask_leaves) = chart.tree_subtree_mask(parents[..], 0usize, mask[..5usize])
    let (_, empty_mask_leaves) = chart.tree_subtree_mask(parents[..0usize], 0usize, mask[..])
    let forward = [3]usize{ 0usize, 2usize, 0usize }
    let (_, order_mask_leaves) = chart.tree_subtree_mask(forward[..], 0usize, mask[..])
    if bad_node_leaves != chart.Invalid || short_mask_leaves != chart.TooLarge || empty_mask_leaves != chart.Empty || order_mask_leaves != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart aggregate tree ok\n")
    ret ok
}
