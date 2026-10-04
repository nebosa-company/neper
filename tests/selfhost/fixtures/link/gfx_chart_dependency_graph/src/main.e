use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let links = [6]chart.DependencyLink{
        chart.DependencyLink { from: 0usize, to: 2usize },
        chart.DependencyLink { from: 1usize, to: 2usize },
        chart.DependencyLink { from: 2usize, to: 3usize },
        chart.DependencyLink { from: 2usize, to: 4usize },
        chart.DependencyLink { from: 3usize, to: 5usize },
        chart.DependencyLink { from: 4usize, to: 5usize },
    }
    let bounds = geometry.rect(0.0, 0.0, 360.0, 180.0)
    var indegree: [6]usize = zero
    var head: [6]usize = zero
    var next: [6]usize = zero
    var order: [6]usize = zero
    var stage: [6]usize = zero
    var stage_counts: [6]usize = zero
    var stage_used: [6]usize = zero
    let work = chart.DependencyWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..], stage: stage[..], stage_counts: stage_counts[..], stage_used: stage_used[..] }
    var boxes: [6]geometry.Rect = zero
    var arrows: [30]chart.Segment = zero
    let (graph, result) = chart.dependency_graph(6usize, links[..], bounds, work, boxes[..], arrows[..])
    if result != ok || graph.stages != 4usize || graph.sources != 2usize || graph.nodes.bars.len != 6usize || graph.connectors.segments.len != 30usize { ret chart.Invalid }
    if stage[0usize] != 0usize || stage[1usize] != 0usize || stage[2usize] != 1usize || stage[3usize] != 2usize || stage[4usize] != 2usize || stage[5usize] != 3usize { ret chart.Invalid }
    if stage_counts[0usize] != 2usize || stage_counts[1usize] != 1usize || stage_counts[2usize] != 2usize || stage_counts[3usize] != 1usize { ret chart.Invalid }
    if boxes[0usize].x != boxes[1usize].x || boxes[0usize].y >= boxes[1usize].y || boxes[0usize].x >= boxes[2usize].x || boxes[2usize].x >= boxes[3usize].x || boxes[3usize].x >= boxes[5usize].x { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &graph.nodes, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &graph.connectors, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 36usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 180.0, "Dependency graph", "Directed acyclic graph")
    try chart_svg.append(&writer, &graph.nodes, ink)
    try chart_svg.append(&writer, &graph.connectors, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let cycle = [2]chart.DependencyLink{
        chart.DependencyLink { from: 0usize, to: 1usize },
        chart.DependencyLink { from: 1usize, to: 0usize },
    }
    let self_link = [1]chart.DependencyLink{ chart.DependencyLink { from: 0usize, to: 0usize } }
    let bad_index = [1]chart.DependencyLink{ chart.DependencyLink { from: 0usize, to: 6usize } }
    let (_, empty_error) = chart.dependency_graph(0usize, links[..0usize], bounds, work, boxes[..], arrows[..])
    let (_, cycle_error) = chart.dependency_graph(2usize, cycle[..], bounds, work, boxes[..], arrows[..])
    let (_, self_error) = chart.dependency_graph(1usize, self_link[..], bounds, work, boxes[..], arrows[..])
    let (_, index_error) = chart.dependency_graph(6usize, bad_index[..], bounds, work, boxes[..], arrows[..])
    let (_, bounds_error) = chart.dependency_graph(6usize, links[..], geometry.rect(0.0, 0.0, -1.0, 180.0), work, boxes[..], arrows[..])
    let (_, width_error) = chart.dependency_graph(6usize, links[..], geometry.rect(0.0, 0.0, 80.0, 180.0), work, boxes[..], arrows[..])
    let (_, height_error) = chart.dependency_graph(6usize, links[..], geometry.rect(0.0, 0.0, 360.0, 50.0), work, boxes[..], arrows[..])
    let (_, box_error) = chart.dependency_graph(6usize, links[..], bounds, work, boxes[..5usize], arrows[..])
    let (_, arrow_error) = chart.dependency_graph(6usize, links[..], bounds, work, boxes[..], arrows[..29usize])
    if empty_error != chart.Empty || cycle_error != chart.Invalid || self_error != chart.Invalid || index_error != chart.Invalid || bounds_error != chart.Invalid || width_error != chart.TooLarge || height_error != chart.TooLarge || box_error != chart.TooLarge || arrow_error != chart.TooLarge { ret chart.Invalid }
    let (disconnected, disconnected_error) = chart.dependency_graph(3usize, links[..0usize], bounds, work, boxes[..], arrows[..0usize])
    if disconnected_error != ok || disconnected.sources != 3usize || disconnected.stages != 1usize || disconnected.connectors.segments.len != 0usize { ret chart.Invalid }
    try io.print("gfx chart dependency graph ok\n")
    ret ok
}
