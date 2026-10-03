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
    let steps = [6]chart.BranchStep{
        chart.BranchStep { process_time: 1.0f64, good_fraction: 0.99f64 },
        chart.BranchStep { process_time: 2.0f64, good_fraction: 0.98f64 },
        chart.BranchStep { process_time: 1.0f64, good_fraction: 0.99f64 },
        chart.BranchStep { process_time: 3.0f64, good_fraction: 0.90f64 },
        chart.BranchStep { process_time: 2.0f64, good_fraction: 0.97f64 },
        chart.BranchStep { process_time: 0.5f64, good_fraction: 1.0f64 },
    }
    let routes = [6]chart.BranchRoute{
        chart.BranchRoute { from: 0usize, to: 1usize, fraction: 1.0f64 },
        chart.BranchRoute { from: 1usize, to: 2usize, fraction: 0.7f64 },
        chart.BranchRoute { from: 1usize, to: 3usize, fraction: 0.3f64 },
        chart.BranchRoute { from: 2usize, to: 4usize, fraction: 1.0f64 },
        chart.BranchRoute { from: 3usize, to: 4usize, fraction: 1.0f64 },
        chart.BranchRoute { from: 4usize, to: 5usize, fraction: 1.0f64 },
    }
    let bounds = geometry.rect(12.0, 48.0, 336.0, 165.0)
    var indegree: [6]usize = zero
    var head: [6]usize = zero
    var next: [6]usize = zero
    var order: [6]usize = zero
    var stage: [6]usize = zero
    var counts: [6]usize = zero
    var used: [6]usize = zero
    var flow: [6]f64 = zero
    var sum: [6]f64 = zero
    let work = chart.BranchWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..], stage: stage[..], stage_counts: counts[..], stage_used: used[..], flow: flow[..], branch_sum: sum[..] }
    var boxes: [6]geometry.Rect = zero
    var arrows: [30]chart.Segment = zero
    let (map, result) = chart.branching_process_map(steps[..], routes[..], bounds, work, boxes[..], arrows[..])
    if result != ok || map.summary.stages != 5usize || map.summary.sinks != 1usize || map.nodes.bars.len != 6usize || map.connectors.segments.len != 30usize { ret chart.Invalid }
    if !near(flow[0usize], 1.0f64) || !near(flow[1usize], 0.99f64) || !near(flow[2usize], 0.67914f64) || !near(flow[3usize], 0.29106f64) || !near(flow[4usize], 0.9343026f64) || !near(flow[5usize], 0.906273522f64) || !near(map.summary.output_fraction, 0.906273522f64) || !near(map.summary.expected_processing_time, 6.854061961f64) { ret chart.Invalid }
    if stage[0usize] != 0usize || stage[1usize] != 1usize || stage[2usize] != 2usize || stage[3usize] != 2usize || stage[4usize] != 3usize || stage[5usize] != 4usize || counts[2usize] != 2usize || boxes[2usize].y >= boxes[3usize].y { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.nodes, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.connectors, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 36usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 250.0, "Branching process", "Split and merge throughput")
    try chart_svg.append(&writer, &map.nodes, ink)
    try chart_svg.append(&writer, &map.connectors, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad_fraction = [2]chart.BranchRoute{
        chart.BranchRoute { from: 0usize, to: 1usize, fraction: 0.4f64 },
        chart.BranchRoute { from: 0usize, to: 2usize, fraction: 0.5f64 },
    }
    let split = [2]chart.BranchRoute{
        chart.BranchRoute { from: 0usize, to: 1usize, fraction: 0.4f64 },
        chart.BranchRoute { from: 0usize, to: 2usize, fraction: 0.6f64 },
    }
    let cycle = [3]chart.BranchRoute{
        chart.BranchRoute { from: 0usize, to: 1usize, fraction: 1.0f64 },
        chart.BranchRoute { from: 1usize, to: 2usize, fraction: 1.0f64 },
        chart.BranchRoute { from: 2usize, to: 1usize, fraction: 1.0f64 },
    }
    let bad_index = [1]chart.BranchRoute{ chart.BranchRoute { from: 0usize, to: 6usize, fraction: 1.0f64 } }
    let bad_step = [1]chart.BranchStep{ chart.BranchStep { process_time: -1.0f64, good_fraction: 1.0f64 } }
    let all_good = [3]chart.BranchStep{
        chart.BranchStep { process_time: 1.0f64, good_fraction: 1.0f64 },
        chart.BranchStep { process_time: 2.0f64, good_fraction: 1.0f64 },
        chart.BranchStep { process_time: 3.0f64, good_fraction: 1.0f64 },
    }
    let (_, empty_error) = chart.branching_process_map(steps[..0usize], routes[..0usize], bounds, work, boxes[..], arrows[..])
    let (_, fraction_error) = chart.branching_process_map(all_good[..], bad_fraction[..], bounds, work, boxes[..], arrows[..])
    let (_, cycle_error) = chart.branching_process_map(all_good[..], cycle[..], bounds, work, boxes[..], arrows[..])
    let (_, index_error) = chart.branching_process_map(steps[..], bad_index[..], bounds, work, boxes[..], arrows[..])
    let (_, step_error) = chart.branching_process_map(bad_step[..], routes[..0usize], bounds, work, boxes[..], arrows[..])
    let (_, bounds_error) = chart.branching_process_map(steps[..], routes[..], geometry.rect(0.0, 0.0, -1.0, 165.0), work, boxes[..], arrows[..])
    let (_, width_error) = chart.branching_process_map(steps[..], routes[..], geometry.rect(0.0, 0.0, 100.0, 165.0), work, boxes[..], arrows[..])
    let (_, height_error) = chart.branching_process_map(steps[..], routes[..], geometry.rect(0.0, 0.0, 336.0, 50.0), work, boxes[..], arrows[..])
    let (_, box_error) = chart.branching_process_map(steps[..], routes[..], bounds, work, boxes[..5usize], arrows[..])
    let (_, arrow_error) = chart.branching_process_map(steps[..], routes[..], bounds, work, boxes[..], arrows[..29usize])
    let (two_sinks, split_error) = chart.branching_process_map(all_good[..], split[..], bounds, work, boxes[..], arrows[..])
    if empty_error != chart.Empty || fraction_error != chart.Invalid || cycle_error != chart.Invalid || index_error != chart.Invalid || step_error != chart.Invalid || bounds_error != chart.Invalid || width_error != chart.TooLarge || height_error != chart.TooLarge || box_error != chart.TooLarge || arrow_error != chart.TooLarge || split_error != ok || two_sinks.summary.sinks != 2usize || !near(two_sinks.summary.output_fraction, 1.0f64) || !near(flow[1usize], 0.4f64) || !near(flow[2usize], 0.6f64) { ret chart.Invalid }
    try io.print("gfx chart branching process ok\n")
    ret ok
}
