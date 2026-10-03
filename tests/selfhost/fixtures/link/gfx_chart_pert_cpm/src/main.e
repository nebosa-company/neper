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
    let activities = [4]chart.CpmActivity{
        chart.CpmActivity { optimistic: 2.0f64, likely: 2.0f64, pessimistic: 2.0f64 },
        chart.CpmActivity { optimistic: 3.0f64, likely: 3.0f64, pessimistic: 3.0f64 },
        chart.CpmActivity { optimistic: 0.0f64, likely: 1.0f64, pessimistic: 2.0f64 },
        chart.CpmActivity { optimistic: 4.0f64, likely: 4.0f64, pessimistic: 4.0f64 },
    }
    let links = [4]chart.CpmDependency{
        chart.CpmDependency { from: 0usize, to: 1usize },
        chart.CpmDependency { from: 0usize, to: 2usize },
        chart.CpmDependency { from: 1usize, to: 3usize },
        chart.CpmDependency { from: 2usize, to: 3usize },
    }
    var timings: [4]chart.CpmTiming = zero
    var indegree: [4]usize = zero
    var head: [4]usize = zero
    var next: [4]usize = zero
    var order: [4]usize = zero
    let work = chart.CpmWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..] }
    let (summary, schedule_error) = chart.pert_cpm_schedule(activities[..], links[..], timings[..], work)
    if schedule_error != ok || !near(summary.duration, 9.0f64) || summary.critical_count != 3usize || summary.stages != 3usize { ret chart.Invalid }
    if !near(timings[0usize].earliest_finish, 2.0f64) || !near(timings[1usize].latest_start, 2.0f64) || !near(timings[2usize].expected, 1.0f64) || !near(timings[2usize].variance, 1.0f64 / 9.0f64) || !near(timings[2usize].slack, 2.0f64) || timings[2usize].critical || !timings[3usize].critical { ret chart.Invalid }
    let bounds = geometry.rect(10.0, 20.0, 300.0, 150.0)
    var stage_counts: [4]usize = zero
    var stage_used: [4]usize = zero
    var boxes: [4]geometry.Rect = zero
    var arrows: [20]chart.Segment = zero
    var critical_links: [4]bool = zero
    let (nodes, connectors, layout_error) = chart.pert_cpm_network(links[..], timings[..], summary, bounds, stage_counts[..], stage_used[..], boxes[..], arrows[..], critical_links[..])
    if layout_error != ok || nodes.bars.len != 4usize || connectors.segments.len != 20usize { ret chart.Invalid }
    if !critical_links[0usize] || critical_links[1usize] || !critical_links[2usize] || critical_links[3usize] || boxes[1usize].y >= boxes[2usize].y || boxes[0usize].x >= boxes[1usize].x { ret chart.Invalid }
    let ink = paint.rgba(0.8, 0.2, 0.2, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &nodes, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &connectors, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 24usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 320.0, 190.0, "PERT CPM", "Critical path")
    try chart_svg.append(&writer, &nodes, ink)
    try chart_svg.append(&writer, &connectors, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let cycle = [2]chart.CpmDependency{
        chart.CpmDependency { from: 0usize, to: 1usize },
        chart.CpmDependency { from: 1usize, to: 0usize },
    }
    let bad_edge = [1]chart.CpmDependency{ chart.CpmDependency { from: 0usize, to: 9usize } }
    let bad_activities = [1]chart.CpmActivity{ chart.CpmActivity { optimistic: 3.0f64, likely: 2.0f64, pessimistic: 4.0f64 } }
    let (_, empty_error) = chart.pert_cpm_schedule(activities[..0usize], links[..0usize], timings[..], work)
    let (_, cycle_error) = chart.pert_cpm_schedule(activities[..2usize], cycle[..], timings[..], work)
    let (_, edge_error) = chart.pert_cpm_schedule(activities[..], bad_edge[..], timings[..], work)
    let (_, estimate_error) = chart.pert_cpm_schedule(bad_activities[..], links[..0usize], timings[..], work)
    let (_, capacity_error) = chart.pert_cpm_schedule(activities[..], links[..], timings[..3usize], work)
    if empty_error != chart.Empty || cycle_error != chart.Invalid || edge_error != chart.Invalid || estimate_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    let (_, _, short_boxes) = chart.pert_cpm_network(links[..], timings[..], summary, bounds, stage_counts[..], stage_used[..], boxes[..3usize], arrows[..], critical_links[..])
    let (_, _, short_edges) = chart.pert_cpm_network(links[..], timings[..], summary, bounds, stage_counts[..], stage_used[..], boxes[..], arrows[..19usize], critical_links[..])
    if short_boxes != chart.TooLarge || short_edges != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart pert cpm ok\n")
    ret ok
}
