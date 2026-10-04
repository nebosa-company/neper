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
    let delta = a - b
    ret delta > -0.001 && delta < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let nodes = [7]chart.CauseTreeNode{
        chart.CauseTreeNode { parent: -1i32, text: "Delay" },
        chart.CauseTreeNode { parent: 0i32, text: "Supply" },
        chart.CauseTreeNode { parent: 0i32, text: "Process" },
        chart.CauseTreeNode { parent: 1i32, text: "Stock & flow" },
        chart.CauseTreeNode { parent: 1i32, text: "Transit" },
        chart.CauseTreeNode { parent: 2i32, text: "Rework" },
        chart.CauseTreeNode { parent: 3i32, text: "Vendor" },
    }
    let bounds = geometry.rect(10.0, 20.0, 320.0, 180.0)
    var placements: [7]chart.CauseTreePlacement = zero
    var cursor: [7]usize = zero
    var work = chart.CauseTreeWork { placements: placements[..], cursor: cursor[..] }
    var boxes: [7]geometry.Rect = zero
    var connectors: [18]chart.Segment = zero
    var labels: [7]chart.Label = zero
    let (map, map_error) = chart.cause_effect_tree(nodes[..], bounds, &work, boxes[..], connectors[..], labels[..])
    if map_error != ok || map.levels != 4usize || map.leaves != 3usize || map.nodes.bars.len != 7usize || map.connectors.segments.len != 18usize || map.labels.len != 7usize { ret chart.Invalid }
    if placements[0usize].leaf_count != 3usize || placements[1usize].leaf_count != 2usize || placements[2usize].leaf_start != 2usize || placements[4usize].leaf_start != 1usize || placements[6usize].depth != 3usize { ret chart.Invalid }
    if !near(boxes[0usize].x + boxes[0usize].width * 0.5, 290.0) || !near(boxes[0usize].y + boxes[0usize].height * 0.5, 110.0) || !near(boxes[6usize].x + boxes[6usize].width * 0.5, 50.0) || !near(boxes[6usize].y + boxes[6usize].height * 0.5, 50.0) { ret chart.Invalid }
    if !near(connectors[0usize].from.x, boxes[0usize].x) || !near(connectors[2usize].to.x, boxes[1usize].x + boxes[1usize].width) || !str.eq(labels[3usize].text, "Stock & flow") { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 40usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.connectors, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.nodes, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 25usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 350.0, 220.0, "Cause tree", "Effect and possible causes")
    try chart_svg.append(&writer, &map.connectors, ink)
    try chart_svg.append(&writer, &map.nodes, ink)
    try chart_svg.append_labels(&writer, map.labels, ink, 8.0)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "Stock &amp; flow") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, empty_error) = chart.cause_effect_tree(nodes[..0usize], bounds, &work, boxes[..], connectors[..], labels[..])
    let (_, short_error) = chart.cause_effect_tree(nodes[..], bounds, &work, boxes[..], connectors[..17usize], labels[..])
    let (_, small_error) = chart.cause_effect_tree(nodes[..], geometry.rect(10.0, 20.0, 100.0, 100.0), &work, boxes[..], connectors[..], labels[..])
    var bad_root = nodes
    bad_root[0usize].parent = 0i32
    let (_, root_error) = chart.cause_effect_tree(bad_root[..], bounds, &work, boxes[..], connectors[..], labels[..])
    var forward = nodes
    forward[2usize].parent = 3i32
    let (_, forward_error) = chart.cause_effect_tree(forward[..], bounds, &work, boxes[..], connectors[..], labels[..])
    var bad_label = nodes
    bad_label[5usize].text = ""
    let (_, label_error) = chart.cause_effect_tree(bad_label[..], bounds, &work, boxes[..], connectors[..], labels[..])
    if empty_error != chart.Empty || short_error != chart.TooLarge || small_error != chart.TooLarge || root_error != chart.Invalid || forward_error != chart.Invalid || label_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart cause effect tree ok\n")
    ret ok
}
