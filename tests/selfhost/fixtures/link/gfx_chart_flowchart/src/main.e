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
    let nodes = [6]chart.FlowNode{
        chart.FlowNode { kind: .Terminal, center: chart.Coord { x: 180.0, y: 58.0 } },
        chart.FlowNode { kind: .Process, center: chart.Coord { x: 180.0, y: 105.0 } },
        chart.FlowNode { kind: .Decision, center: chart.Coord { x: 180.0, y: 160.0 } },
        chart.FlowNode { kind: .Process, center: chart.Coord { x: 292.0, y: 160.0 } },
        chart.FlowNode { kind: .Process, center: chart.Coord { x: 62.0, y: 105.0 } },
        chart.FlowNode { kind: .Terminal, center: chart.Coord { x: 292.0, y: 207.0 } },
    }
    let links = [6]chart.FlowLink{
        chart.FlowLink { from: 0usize, to: 1usize, exit: .Bottom, entry: .Top },
        chart.FlowLink { from: 1usize, to: 2usize, exit: .Bottom, entry: .Top },
        chart.FlowLink { from: 2usize, to: 3usize, exit: .Right, entry: .Left },
        chart.FlowLink { from: 3usize, to: 5usize, exit: .Bottom, entry: .Top },
        chart.FlowLink { from: 2usize, to: 4usize, exit: .Left, entry: .Right },
        chart.FlowLink { from: 4usize, to: 1usize, exit: .Right, entry: .Left },
    }
    let bounds = geometry.rect(12.0, 42.0, 336.0, 185.0)
    var boxes: [6]geometry.Rect = zero
    var outlines: [48]chart.Coord = zero
    var shapes: [6]chart.Layout = zero
    var arrows: [30]chart.Segment = zero
    let (flow, result) = chart.flowchart(nodes[..], links[..], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    if result != ok || flow.nodes.len != 6usize || flow.connectors.segments.len != 30usize { ret chart.Invalid }
    if shapes[0usize].kind != .Area || shapes[0usize].coords.len != 8usize || shapes[1usize].kind != .Bar || shapes[2usize].kind != .Area || shapes[2usize].coords.len != 4usize || shapes[5usize].coords.len != 8usize { ret chart.Invalid }
    if arrows[25usize].from.x >= arrows[27usize].to.x || arrows[20usize].from.x <= arrows[22usize].to.x { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 48usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    var i = 0usize
    while i < flow.nodes.len {
        try chart_scene.append(a, &builder, &flow.nodes[i], paint.Brush { Solid: ink })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &flow.connectors, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 36usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 250.0, "Flowchart", "Decision loop")
    i = 0usize
    while i < flow.nodes.len {
        try chart_svg.append(&writer, &flow.nodes[i], ink)
        i += 1usize
    }
    try chart_svg.append(&writer, &flow.connectors, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let overlap = [2]chart.FlowNode{ nodes[0usize], nodes[0usize] }
    let wrong_port = [1]chart.FlowLink{ chart.FlowLink { from: 0usize, to: 1usize, exit: .Top, entry: .Top } }
    let backward = [1]chart.FlowLink{ chart.FlowLink { from: 0usize, to: 1usize, exit: .Top, entry: .Bottom } }
    let self_link = [1]chart.FlowLink{ chart.FlowLink { from: 0usize, to: 0usize, exit: .Right, entry: .Left } }
    let bad_index = [1]chart.FlowLink{ chart.FlowLink { from: 0usize, to: 6usize, exit: .Right, entry: .Left } }
    let (_, empty_error) = chart.flowchart(nodes[..0usize], links[..0usize], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    let (_, overlap_error) = chart.flowchart(overlap[..], links[..0usize], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    let (_, port_error) = chart.flowchart(nodes[..], wrong_port[..], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    let (_, backward_error) = chart.flowchart(nodes[..], backward[..], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    let (_, self_error) = chart.flowchart(nodes[..], self_link[..], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    let (_, index_error) = chart.flowchart(nodes[..], bad_index[..], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    let (_, bounds_error) = chart.flowchart(nodes[..], links[..], geometry.rect(0.0, 0.0, -1.0, 250.0), 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    let (_, width_error) = chart.flowchart(nodes[..], links[..], bounds, 10.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..])
    let (_, box_error) = chart.flowchart(nodes[..], links[..], bounds, 72.0, 32.0, boxes[..5usize], outlines[..], shapes[..], arrows[..])
    let (_, outline_error) = chart.flowchart(nodes[..], links[..], bounds, 72.0, 32.0, boxes[..], outlines[..47usize], shapes[..], arrows[..])
    let (_, shape_error) = chart.flowchart(nodes[..], links[..], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..5usize], arrows[..])
    let (_, arrow_error) = chart.flowchart(nodes[..], links[..], bounds, 72.0, 32.0, boxes[..], outlines[..], shapes[..], arrows[..29usize])
    if empty_error != chart.Empty || overlap_error != chart.Invalid || port_error != chart.Invalid || backward_error != chart.Invalid || self_error != chart.Invalid || index_error != chart.Invalid || bounds_error != chart.Invalid || width_error != chart.Invalid || box_error != chart.TooLarge || outline_error != chart.TooLarge || shape_error != chart.TooLarge || arrow_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart flowchart ok\n")
    ret ok
}
