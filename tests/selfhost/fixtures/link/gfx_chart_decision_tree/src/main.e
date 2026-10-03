use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool {
    let delta = a - b
    ret delta > -0.000001f64 && delta < 0.000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let nodes = [7]chart.DecisionNode{
        chart.DecisionNode { kind: .Choice, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Chance, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Chance, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 12.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 8.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 6.0f64 },
    }
    let edges = [6]chart.DecisionEdge{
        chart.DecisionEdge { from: 0usize, to: 1usize, probability: 0.0f64 },
        chart.DecisionEdge { from: 0usize, to: 2usize, probability: 0.0f64 },
        chart.DecisionEdge { from: 1usize, to: 3usize, probability: 0.7f64 },
        chart.DecisionEdge { from: 1usize, to: 4usize, probability: 0.3f64 },
        chart.DecisionEdge { from: 2usize, to: 5usize, probability: 0.5f64 },
        chart.DecisionEdge { from: 2usize, to: 6usize, probability: 0.5f64 },
    }
    var values: [7]chart.DecisionValue = zero
    var indegree: [7]usize = zero
    var head: [7]usize = zero
    var next: [6]usize = zero
    var order: [7]usize = zero
    let work = chart.DecisionTreeWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..] }
    let (summary, result) = chart.decision_tree_values(nodes[..], edges[..], values[..], work)
    if result != ok || !near(summary.expected, 8.4f64) || summary.depth != 3usize || summary.leaves != 4usize || !near(values[1usize].expected, 8.4f64) || !near(values[2usize].expected, 7.0f64) || values[0usize].selected_edge != 0usize || values[1usize].selected_edge != edges.len { ret chart.Invalid }
    if values[1usize].leaf_count != 2usize || values[2usize].leaf_start != 2usize || values[3usize].leaf_start != 0usize || values[4usize].leaf_start != 1usize || values[5usize].leaf_start != 2usize || values[6usize].leaf_start != 3usize { ret chart.Invalid }
    let bounds = geometry.rect(0.0, 0.0, 360.0, 160.0)
    var boxes: [7]geometry.Rect = zero
    var arrows: [30]chart.Segment = zero
    var chosen: [6]bool = zero
    let (node_layout, connectors, layout_error) = chart.decision_tree_layout(nodes[..], edges[..], values[..], summary, bounds, boxes[..], arrows[..], chosen[..])
    if layout_error != ok || node_layout.bars.len != 7usize || connectors.segments.len != 30usize || !chosen[0usize] || chosen[1usize] || chosen[2usize] { ret chart.Invalid }
    if boxes[0usize].x >= boxes[1usize].x || boxes[1usize].x >= boxes[3usize].x || boxes[3usize].y >= boxes[4usize].y || boxes[1usize].y >= boxes[2usize].y { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &node_layout, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &connectors, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 37usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 160.0, "Decision tree", "Expected value")
    try chart_svg.append(&writer, &node_layout, ink)
    try chart_svg.append(&writer, &connectors, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad_probability = [2]chart.DecisionEdge{
        chart.DecisionEdge { from: 0usize, to: 1usize, probability: 0.4f64 },
        chart.DecisionEdge { from: 0usize, to: 2usize, probability: 0.4f64 },
    }
    let chance_root = [3]chart.DecisionNode{
        chart.DecisionNode { kind: .Chance, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 1.0f64 },
        chart.DecisionNode { kind: .Outcome, payoff: 2.0f64 },
    }
    let duplicate_parent = [2]chart.DecisionEdge{
        chart.DecisionEdge { from: 0usize, to: 1usize, probability: 0.0f64 },
        chart.DecisionEdge { from: 0usize, to: 1usize, probability: 0.0f64 },
    }
    let detached_cycle = [2]chart.DecisionEdge{
        chart.DecisionEdge { from: 1usize, to: 2usize, probability: 0.0f64 },
        chart.DecisionEdge { from: 2usize, to: 1usize, probability: 0.0f64 },
    }
    let cycle_nodes = [3]chart.DecisionNode{
        chart.DecisionNode { kind: .Outcome, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Choice, payoff: 0.0f64 },
        chart.DecisionNode { kind: .Choice, payoff: 0.0f64 },
    }
    let bad_payoff = [1]chart.DecisionNode{ chart.DecisionNode { kind: .Choice, payoff: 3.0f64 } }
    let (_, empty_error) = chart.decision_tree_values(nodes[..0usize], edges[..0usize], values[..], work)
    let (_, chance_error) = chart.decision_tree_values(chance_root[..], bad_probability[..], values[..], work)
    let (_, parent_error) = chart.decision_tree_values(nodes[..], duplicate_parent[..], values[..], work)
    let (_, cycle_error) = chart.decision_tree_values(cycle_nodes[..], detached_cycle[..], values[..], work)
    let (_, payoff_error) = chart.decision_tree_values(bad_payoff[..], edges[..0usize], values[..], work)
    let (_, storage_error) = chart.decision_tree_values(nodes[..], edges[..], values[..6usize], work)
    if empty_error != chart.Empty || chance_error != chart.Invalid || parent_error != chart.Invalid || cycle_error != chart.Invalid || payoff_error != chart.Invalid || storage_error != chart.TooLarge { ret chart.Invalid }
    let (_, _, short_arrows) = chart.decision_tree_layout(nodes[..], edges[..], values[..], summary, bounds, boxes[..], arrows[..29usize], chosen[..])
    let (_, _, short_height) = chart.decision_tree_layout(nodes[..], edges[..], values[..], summary, geometry.rect(0.0, 0.0, 360.0, 70.0), boxes[..], arrows[..], chosen[..])
    if short_arrows != chart.TooLarge || short_height != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart decision tree ok\n")
    ret ok
}
