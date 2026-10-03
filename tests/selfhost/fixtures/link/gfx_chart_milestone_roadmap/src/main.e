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
    let events = [3]chart.TimelineEvent{
        chart.TimelineEvent { time: 2.0f64, row: 0usize },
        chart.TimelineEvent { time: 5.0f64, row: 2usize },
        chart.TimelineEvent { time: 8.0f64, row: 1usize },
    }
    let bounds = geometry.rect(20.0, 10.0, 100.0, 60.0)
    var centers: [3]chart.Coord = zero
    var stems: [3]chart.Segment = zero
    var diamonds: [12]chart.Coord = zero
    var layers: [3]chart.Layout = zero
    let (marks, result) = chart.milestone_roadmap(events[..], 3usize, 0.0f64, 10.0f64, bounds, 5.0, centers[..], stems[..], diamonds[..], layers[..])
    if result != ok || marks.len != 3usize || marks[0usize].kind != .Area || marks[0usize].coords.len != 4usize { ret chart.Invalid }
    if !near(centers[0usize].x, 40.0) || !near(centers[0usize].y, 20.0) || !near(diamonds[0usize].x, 40.0) || !near(diamonds[0usize].y, 15.0) || !near(diamonds[1usize].x, 45.0) || !near(diamonds[3usize].x, 35.0) || !near(marks[1usize].coords[0usize].x, 70.0) { ret chart.Invalid }
    if !near(marks[0usize].x_min, 0.0) || !near(marks[0usize].x_max, 10.0) || !near(marks[2usize].coords[0usize].x, 100.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 12usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &marks[0usize], paint.Brush { Solid: ink })
    if scene.builder_count(&builder) == 0usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 140.0, 90.0, "Milestones", "Timeline diamonds")
    try chart_svg.append(&writer, &marks[0usize], ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let backwards = [2]chart.TimelineEvent{ events[1usize], events[0usize] }
    let bad_row = [1]chart.TimelineEvent{ chart.TimelineEvent { time: 2.0f64, row: 3usize } }
    let (_, empty_error) = chart.milestone_roadmap(events[..0usize], 3usize, 0.0f64, 10.0f64, bounds, 5.0, centers[..], stems[..], diamonds[..], layers[..])
    let (_, order_error) = chart.milestone_roadmap(backwards[..], 3usize, 0.0f64, 10.0f64, bounds, 5.0, centers[..], stems[..], diamonds[..], layers[..])
    let (_, row_error) = chart.milestone_roadmap(bad_row[..], 3usize, 0.0f64, 10.0f64, bounds, 5.0, centers[..], stems[..], diamonds[..], layers[..])
    let (_, size_error) = chart.milestone_roadmap(events[..], 3usize, 0.0f64, 10.0f64, bounds, 11.0, centers[..], stems[..], diamonds[..], layers[..])
    let (_, capacity_error) = chart.milestone_roadmap(events[..], 3usize, 0.0f64, 10.0f64, bounds, 5.0, centers[..], stems[..], diamonds[..11usize], layers[..])
    let (_, domain_error) = chart.milestone_roadmap(events[..], 3usize, 2.0f64, 2.0f64, bounds, 5.0, centers[..], stems[..], diamonds[..], layers[..])
    if empty_error != chart.Empty || order_error != chart.Invalid || row_error != chart.Invalid || size_error != chart.Invalid || capacity_error != chart.TooLarge || domain_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart milestone roadmap ok\n")
    ret ok
}
