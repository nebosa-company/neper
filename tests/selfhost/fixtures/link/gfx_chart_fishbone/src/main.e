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
    let categories = [4]str{ "People", "Process", "Machine", "Material" }
    let causes = [5]chart.FishboneCause{
        chart.FishboneCause { category: 0usize, parent: -1i32, text: "Training" },
        chart.FishboneCause { category: 0usize, parent: 0i32, text: "Onboarding" },
        chart.FishboneCause { category: 0usize, parent: 1i32, text: "A&B" },
        chart.FishboneCause { category: 1usize, parent: -1i32, text: "Handoff" },
        chart.FishboneCause { category: 2usize, parent: -1i32, text: "Wear" },
    }
    let bounds = geometry.rect(10.0, 20.0, 300.0, 180.0)
    var spine: [3]chart.Segment = zero
    var ribs: [4]chart.Segment = zero
    var branches: [5]chart.Segment = zero
    var box: [1]geometry.Rect = zero
    var labels: [10]chart.Label = zero
    let (map, map_error) = chart.fishbone("Defects & waste", categories[..], causes[..], bounds, spine[..], ribs[..], branches[..], box[..], labels[..])
    if map_error != ok || map.spine.segments.len != 3usize || map.ribs.segments.len != 4usize || map.causes.segments.len != 5usize || map.head.bars.len != 1usize || map.labels.len != 10usize { ret chart.Invalid }
    if !near(spine[0usize].from.x, 25.0) || !near(spine[0usize].to.x, 253.0) || !near(spine[0usize].from.y, 110.0) || !near(ribs[0usize].from.x, ribs[1usize].from.x) || !near(ribs[0usize].to.y, 54.2) || !near(ribs[1usize].to.y, 165.8) { ret chart.Invalid }
    if !near(branches[1usize].from.x, (branches[0usize].from.x + branches[0usize].to.x) * 0.5) || !near(branches[2usize].from.x, (branches[1usize].from.x + branches[1usize].to.x) * 0.5) || !(branches[2usize].to.x > branches[2usize].from.x) || !str.eq(labels[0usize].text, "Defects & waste") || !str.eq(labels[3usize].text, "Machine") || !str.eq(labels[7usize].text, "A&B") { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.spine, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.ribs, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.causes, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.head, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 13usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 320.0, 220.0, "Fishbone", "Cause and effect")
    try chart_svg.append(&writer, &map.spine, blue)
    try chart_svg.append(&writer, &map.ribs, blue)
    try chart_svg.append(&writer, &map.causes, blue)
    try chart_svg.append(&writer, &map.head, blue)
    try chart_svg.append_labels(&writer, map.labels, blue, 8.0)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "Defects &amp; waste") || !str.contains(svg, "A&amp;B") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let (_, empty_error) = chart.fishbone("Defects", categories[..0usize], causes[..0usize], bounds, spine[..], ribs[..], branches[..], box[..], labels[..])
    let (_, short_error) = chart.fishbone("Defects", categories[..], causes[..], bounds, spine[..], ribs[..], branches[..4usize], box[..], labels[..])
    let (_, effect_error) = chart.fishbone("", categories[..], causes[..], bounds, spine[..], ribs[..], branches[..], box[..], labels[..])
    var forward = causes
    forward[1usize].parent = 2i32
    let (_, forward_error) = chart.fishbone("Defects", categories[..], forward[..], bounds, spine[..], ribs[..], branches[..], box[..], labels[..])
    var crossed = causes
    crossed[3usize].parent = 0i32
    let (_, crossed_error) = chart.fishbone("Defects", categories[..], crossed[..], bounds, spine[..], ribs[..], branches[..], box[..], labels[..])
    var out_of_range = causes
    out_of_range[4usize].category = 4usize
    let (_, category_error) = chart.fishbone("Defects", categories[..], out_of_range[..], bounds, spine[..], ribs[..], branches[..], box[..], labels[..])
    if empty_error != chart.Invalid || short_error != chart.TooLarge || effect_error != chart.Invalid || forward_error != chart.Invalid || crossed_error != chart.Invalid || category_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart fishbone ok\n")
    ret ok
}
