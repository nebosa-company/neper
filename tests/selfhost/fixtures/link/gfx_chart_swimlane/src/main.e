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
    let d = a - b
    ret d > -0.001 && d < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let steps = [4]chart.SwimlaneStep{
        chart.SwimlaneStep { lane: 0usize, stage: 0usize },
        chart.SwimlaneStep { lane: 1usize, stage: 1usize },
        chart.SwimlaneStep { lane: 1usize, stage: 2usize },
        chart.SwimlaneStep { lane: 2usize, stage: 3usize },
    }
    let links = [3]chart.SwimlaneLink{
        chart.SwimlaneLink { from: 0usize, to: 1usize },
        chart.SwimlaneLink { from: 1usize, to: 2usize },
        chart.SwimlaneLink { from: 2usize, to: 3usize },
    }
    let bounds = geometry.rect(0.0, 0.0, 240.0, 120.0)
    var lanes: [3]geometry.Rect = zero
    var boxes: [4]geometry.Rect = zero
    var arrows: [15]chart.Segment = zero
    let (nodes, connectors, result) = chart.swimlane(steps[..], links[..], 3usize, 4usize, bounds, lanes[..], boxes[..], arrows[..])
    if result != ok || nodes.kind != .Bar || connectors.kind != .Rug || nodes.bars.len != 4usize || connectors.segments.len != 15usize { ret chart.Invalid }
    if !near(lanes[0usize].height, 40.0) || !near(lanes[1usize].y, 40.0) || !near(lanes[2usize].y, 80.0) || !near(boxes[0usize].x, 8.4) || !near(boxes[0usize].y, 11.2) || !near(boxes[1usize].x, 68.4) || !near(boxes[1usize].y, 51.2) { ret chart.Invalid }
    if !near(arrows[0usize].from.x, 51.6) || !near(arrows[0usize].from.y, 20.0) || !near(arrows[0usize].to.x, 60.0) || !near(arrows[1usize].to.y, 60.0) || !near(arrows[2usize].to.x, 68.4) || !near(arrows[3usize].to.x, 68.4) || !near(arrows[6usize].from.y, arrows[6usize].to.y) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &connectors, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &nodes, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 19usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 240.0, 120.0, "Swimlane", "Role handoffs")
    try chart_svg.append(&writer, &connectors, ink)
    try chart_svg.append(&writer, &nodes, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<line") || !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let duplicate = [2]chart.SwimlaneStep{ steps[0usize], steps[0usize] }
    let backward = [1]chart.SwimlaneLink{ chart.SwimlaneLink { from: 1usize, to: 0usize } }
    let missing = [1]chart.SwimlaneLink{ chart.SwimlaneLink { from: 0usize, to: 4usize } }
    let outside = [1]chart.SwimlaneStep{ chart.SwimlaneStep { lane: 3usize, stage: 0usize } }
    let (_, _, empty_error) = chart.swimlane(steps[..0usize], links[..0usize], 3usize, 4usize, bounds, lanes[..], boxes[..], arrows[..])
    let (_, _, duplicate_error) = chart.swimlane(duplicate[..], links[..0usize], 3usize, 4usize, bounds, lanes[..], boxes[..], arrows[..])
    let (_, _, backward_error) = chart.swimlane(steps[..], backward[..], 3usize, 4usize, bounds, lanes[..], boxes[..], arrows[..])
    let (_, _, missing_error) = chart.swimlane(steps[..], missing[..], 3usize, 4usize, bounds, lanes[..], boxes[..], arrows[..])
    let (_, _, lane_error) = chart.swimlane(outside[..], links[..0usize], 3usize, 4usize, bounds, lanes[..], boxes[..], arrows[..])
    let (_, _, storage_error) = chart.swimlane(steps[..], links[..], 3usize, 4usize, bounds, lanes[..], boxes[..], arrows[..14usize])
    if empty_error != chart.Empty || duplicate_error != chart.Invalid || backward_error != chart.Invalid || missing_error != chart.Invalid || lane_error != chart.Invalid || storage_error != chart.TooLarge { ret chart.Invalid }
    let (isolated, none, no_link_error) = chart.swimlane(steps[..1usize], links[..0usize], 3usize, 4usize, bounds, lanes[..], boxes[..], arrows[..0usize])
    if no_link_error != ok || isolated.bars.len != 1usize || none.segments.len != 0usize { ret chart.Invalid }
    try io.print("gfx chart swimlane ok\n")
    ret ok
}
