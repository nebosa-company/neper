use e.fs
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str
use e.text.shape

fn near(a: f32, b: f32) -> bool { ret a - b < 0.01 && b - a < 0.01 }

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret chart.Invalid }
    var panels: [4]geometry.Rect = zero
    let (placed, panel_error) = chart.facet_grid(geometry.rect(40.0, 45.0, 270.0, 140.0), 2usize, 4usize, 20.0, panels[..])
    if panel_error != ok { ret panel_error }
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_ticks: [3]chart.Tick = zero
    var y_ticks: [3]chart.Tick = zero
    let (_, x_error) = chart.ticks(linear, 0.0, 10.0, x_ticks[..])
    let (_, y_error) = chart.ticks(linear, 0.0, 10.0, y_ticks[..])
    if x_error != ok || y_error != ok { ret chart.Invalid }
    let text = [3]str{ "0", "5", "10" }
    var labels: [12]chart.Label = zero
    let (outer, guide_error) = chart.shared_facet_guide_labels(placed, 2usize, x_ticks[..], text[..], y_ticks[..], text[..], 8.0, labels[..])
    if guide_error != ok || outer.len != 12usize || !near(outer[0usize].anchor.x, 40.0) || !near(outer[0usize].anchor.y, 199.0) || !near(outer[3usize].anchor.x, 185.0) || !near(outer[6usize].anchor.x, 31.0) || !near(outer[9usize].anchor.y, 187.8) { ret chart.Invalid }
    if outer[0usize].align != .Center || outer[6usize].align != .Right { ret chart.Invalid }
    let x = [2]f32{ 0.0, 10.0 }
    let y = [2]f32{ 0.0, 10.0 }
    let limits = [2]f32{ 0.0, 10.0 }
    var points: [2]chart.Coord = zero
    var unused_lines: [1]chart.Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    let plot0 = chart.spec(.Scatter, placed[0usize], x[..], y[..])
    let plot1 = chart.spec(.Scatter, placed[1usize], x[..], y[..])
    let (first, first_error) = chart.layout_with_limits(&plot0, points[..], unused_lines[..0usize], unused_bars[..0usize], limits[..], limits[..])
    if first_error != ok || !near(first.coords[1usize].x, 165.0) { ret chart.Invalid }
    let (second, second_error) = chart.layout_with_limits(&plot1, points[..], unused_lines[..0usize], unused_bars[..0usize], limits[..], limits[..])
    if second_error != ok || !near(second.coords[1usize].x, 310.0) { ret chart.Invalid }
    let (font_bytes, font_error) = fs.read_file(a, args[1usize], 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let grid = paint.rgba(0.85, 0.88, 0.92, 1.0)
    let (made, builder_error) = scene.builder(a, 128usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    var i = 0usize
    while i < placed.len {
        try chart_scene.append_guides(&builder, placed[i], x_ticks[..], y_ticks[..], paint.Brush { Solid: grid }, paint.Brush { Solid: ink })
        i += 1usize
    }
    try chart_scene.append_labels(a, &builder, outer, font, 8.0, paint.Brush { Solid: ink })
    let display = scene.finish(&builder)
    var text_commands = 0usize
    i = 0usize
    while i < display.commands.len {
        if display.commands[i].tag == .Text { text_commands += 1usize }
        i += 1usize
    }
    if text_commands != 12usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0, 240.0, "Shared facet guides", "Outer tick labels only")
    i = 0usize
    while i < placed.len {
        try chart_svg.append_guides(&writer, placed[i], x_ticks[..], y_ticks[..], grid, ink)
        i += 1usize
    }
    try chart_svg.append_labels(&writer, outer, ink, 8.0)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "text-anchor=\"middle\"") || !str.contains(io.memory_bytes(&held), "text-anchor=\"end\"") { ret chart.Invalid }
    let (_, short_error) = chart.shared_facet_guide_labels(placed, 2usize, x_ticks[..], text[..], y_ticks[..], text[..], 8.0, labels[..11usize])
    let (_, partial_error) = chart.shared_facet_guide_labels(placed[..3usize], 2usize, x_ticks[..], text[..], y_ticks[..], text[..], 8.0, labels[..])
    var bad_panels = panels
    bad_panels[2usize].x += 1.0
    let (_, align_error) = chart.shared_facet_guide_labels(bad_panels[..], 2usize, x_ticks[..], text[..], y_ticks[..], text[..], 8.0, labels[..])
    let (_, text_error) = chart.shared_facet_guide_labels(placed, 2usize, x_ticks[..], text[..2usize], y_ticks[..], text[..], 8.0, labels[..])
    var bad_ticks = x_ticks
    bad_ticks[1usize].fraction = 1.2
    let (_, tick_error) = chart.shared_facet_guide_labels(placed, 2usize, bad_ticks[..], text[..], y_ticks[..], text[..], 8.0, labels[..])
    if short_error != chart.TooLarge || partial_error != chart.Invalid || align_error != chart.Invalid || text_error != chart.Invalid || tick_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart shared guides ok\n")
    ret ok
}
