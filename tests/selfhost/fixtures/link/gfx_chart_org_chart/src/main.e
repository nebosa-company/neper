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
    let links = [6]chart.OrgLink{
        chart.OrgLink { manager: 0usize, report: 1usize },
        chart.OrgLink { manager: 0usize, report: 2usize },
        chart.OrgLink { manager: 1usize, report: 3usize },
        chart.OrgLink { manager: 1usize, report: 4usize },
        chart.OrgLink { manager: 2usize, report: 5usize },
        chart.OrgLink { manager: 2usize, report: 6usize },
    }
    let bounds = geometry.rect(0.0, 0.0, 360.0, 180.0)
    var places: [7]chart.OrgPlacement = zero
    var indegree: [7]usize = zero
    var head: [7]usize = zero
    var next: [6]usize = zero
    var order: [7]usize = zero
    let work = chart.OrgWork { indegree: indegree[..], head: head[..], next: next[..], order: order[..] }
    var boxes: [7]geometry.Rect = zero
    var connectors: [18]chart.Segment = zero
    let (org, result) = chart.org_chart(7usize, links[..], bounds, places[..], work, boxes[..], connectors[..])
    if result != ok || org.levels != 3usize || org.leaves != 4usize || org.nodes.bars.len != 7usize || org.connectors.segments.len != 18usize { ret chart.Invalid }
    if places[0usize].direct_reports != 2usize || places[1usize].leaf_count != 2usize || places[2usize].leaf_start != 2usize || places[3usize].leaf_start != 0usize || places[4usize].leaf_start != 1usize || places[5usize].leaf_start != 2usize || places[6usize].leaf_start != 3usize { ret chart.Invalid }
    if !near(boxes[0usize].x, 147.6) || !near(boxes[0usize].y, 16.8) || !near(boxes[1usize].x, 57.6) || !near(boxes[2usize].x, 237.6) || !near(boxes[3usize].x, 12.6) || !near(boxes[6usize].x, 282.6) || boxes[0usize].y >= boxes[1usize].y || boxes[1usize].y >= boxes[3usize].y { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &org.nodes, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &org.connectors, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 25usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 180.0, "Org chart", "Reporting hierarchy")
    try chart_svg.append(&writer, &org.nodes, ink)
    try chart_svg.append(&writer, &org.connectors, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let duplicate = [2]chart.OrgLink{
        chart.OrgLink { manager: 0usize, report: 1usize },
        chart.OrgLink { manager: 0usize, report: 1usize },
    }
    let cycle = [2]chart.OrgLink{
        chart.OrgLink { manager: 1usize, report: 2usize },
        chart.OrgLink { manager: 2usize, report: 1usize },
    }
    let bad_index = [1]chart.OrgLink{ chart.OrgLink { manager: 0usize, report: 7usize } }
    let (_, empty_error) = chart.org_chart(0usize, links[..0usize], bounds, places[..], work, boxes[..], connectors[..])
    let (_, parent_error) = chart.org_chart(3usize, duplicate[..], bounds, places[..], work, boxes[..], connectors[..])
    let (_, cycle_error) = chart.org_chart(3usize, cycle[..], bounds, places[..], work, boxes[..], connectors[..])
    let (_, index_error) = chart.org_chart(7usize, bad_index[..], bounds, places[..], work, boxes[..], connectors[..])
    let (_, bounds_error) = chart.org_chart(7usize, links[..], geometry.rect(0.0, 0.0, -1.0, 180.0), places[..], work, boxes[..], connectors[..])
    let (_, width_error) = chart.org_chart(7usize, links[..], geometry.rect(0.0, 0.0, 120.0, 180.0), places[..], work, boxes[..], connectors[..])
    let (_, height_error) = chart.org_chart(7usize, links[..], geometry.rect(0.0, 0.0, 360.0, 60.0), places[..], work, boxes[..], connectors[..])
    let (_, box_error) = chart.org_chart(7usize, links[..], bounds, places[..], work, boxes[..6usize], connectors[..])
    let (_, connector_error) = chart.org_chart(7usize, links[..], bounds, places[..], work, boxes[..], connectors[..17usize])
    if empty_error != chart.Empty || parent_error != chart.Invalid || cycle_error != chart.Invalid || index_error != chart.Invalid || bounds_error != chart.Invalid || width_error != chart.TooLarge || height_error != chart.TooLarge || box_error != chart.TooLarge || connector_error != chart.TooLarge { ret chart.Invalid }
    let (single, single_error) = chart.org_chart(1usize, links[..0usize], bounds, places[..1usize], work, boxes[..1usize], connectors[..0usize])
    if single_error != ok || single.levels != 1usize || single.leaves != 1usize || single.connectors.segments.len != 0usize { ret chart.Invalid }
    try io.print("gfx chart org chart ok\n")
    ret ok
}
