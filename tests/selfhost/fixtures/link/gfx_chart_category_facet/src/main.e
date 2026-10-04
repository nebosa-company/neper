use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.001f32 && b - a < 0.001f32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let keys = [4]str{ "North", "South & East", "North", "South & East" }
    let x = [4]f32{ 0.0, 5.0, 10.0, 8.0 }
    let y = [4]f32{ 0.0, 5.0, 10.0, 7.0 }
    let levels = [3]str{ "North", "South & East", "West" }
    let bounds = geometry.rect(20.0, 30.0, 320.0, 180.0)
    var panels: [3]geometry.Rect = zero
    var points: [4]chart.Coord = zero
    var marks: [3]chart.Layout = zero
    var strips: [3]chart.Label = zero
    var counts: [3]usize = zero
    let (facets, facet_error) = chart.category_facet_scatter(keys[..], x[..], y[..], levels[..], bounds, 2usize, 10.0, 18.0, 0.0, 10.0, 0.0, 10.0, panels[..], points[..], marks[..], strips[..], counts[..])
    if facet_error != ok || facets.panels.len != 3usize || facets.marks.len != 3usize || counts[0usize] != 2usize || counts[1usize] != 2usize || counts[2usize] != 0usize { ret chart.Invalid }
    if !near(panels[0usize].width, 155.0) || !near(panels[1usize].x, 185.0) || !near(panels[2usize].y, 125.0) || !near(points[0usize].x, 25.0) || !near(points[0usize].y, 110.0) || !near(points[2usize].x, 262.5) { ret chart.Invalid }
    if facets.marks[2usize].coords.len != 0usize || !str.eq(facets.strips[1usize].text, "South & East") { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    var i = 0usize
    while i < facets.marks.len {
        try chart_scene.append(a, &builder, &facets.marks[i], paint.Brush { Solid: ink })
        i += 1usize
    }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Category facets", "Shared numeric scales")
    i = 0usize
    while i < facets.marks.len {
        try chart_svg.append(&writer, &facets.marks[i], ink)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, facets.strips, ink, 9.0)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "South &amp; East") { ret chart.Invalid }
    let (_, short_error) = chart.category_facet_scatter(keys[..], x[..], y[..], levels[..], bounds, 2usize, 10.0, 18.0, 0.0, 10.0, 0.0, 10.0, panels[..], points[..3usize], marks[..], strips[..], counts[..])
    let unknown = [4]str{ "North", "Other", "North", "South & East" }
    let (_, unknown_error) = chart.category_facet_scatter(unknown[..], x[..], y[..], levels[..], bounds, 2usize, 10.0, 18.0, 0.0, 10.0, 0.0, 10.0, panels[..], points[..], marks[..], strips[..], counts[..])
    let duplicate = [3]str{ "North", "North", "West" }
    let (_, duplicate_error) = chart.category_facet_scatter(keys[..], x[..], y[..], duplicate[..], bounds, 2usize, 10.0, 18.0, 0.0, 10.0, 0.0, 10.0, panels[..], points[..], marks[..], strips[..], counts[..])
    let (_, domain_error) = chart.category_facet_scatter(keys[..], x[..], y[..], levels[..], bounds, 2usize, 10.0, 18.0, 0.0, 9.0, 0.0, 10.0, panels[..], points[..], marks[..], strips[..], counts[..])
    let (_, panel_error) = chart.category_facet_scatter(keys[..], x[..], y[..], levels[..], geometry.rect(0.0, 0.0, 15.0, 20.0), 2usize, 2.0, 18.0, 0.0, 10.0, 0.0, 10.0, panels[..], points[..], marks[..], strips[..], counts[..])
    if short_error != chart.TooLarge || unknown_error != chart.Invalid || duplicate_error != chart.Invalid || domain_error != chart.Invalid || panel_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart category facet ok\n")
    ret ok
}
