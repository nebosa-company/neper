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

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d > -0.01 && d < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret chart.Invalid }
    let bounds = geometry.rect(20.0, 20.0, 80.0, 60.0)
    let linear = chart.Scale { kind: .Linear, reverse: false, linthresh: 1.0 }
    var x_ticks: [3]chart.Tick = zero
    var y_ticks: [3]chart.Tick = zero
    let (_, x_error) = chart.ticks(linear, 0.0, 2.0, x_ticks[..])
    if x_error != ok { ret x_error }
    let (_, y_error) = chart.ticks(linear, 0.0, 2.0, y_ticks[..])
    if y_error != ok { ret y_error }
    let x_text = [3]str{ "0", "1", "2" }
    let y_text = [3]str{ "0", "1", "2" }
    var labels: [7]chart.Label = zero
    let (guides, guide_error) = chart.guide_labels(bounds, x_ticks[..], x_text[..], y_ticks[..], y_text[..], 10.0, labels[..])
    if guide_error != ok || guides.len != 6usize || !near(guides[1usize].anchor.x, 60.0) || !near(guides[1usize].anchor.y, 96.0) || guides[1usize].align != .Center || guides[3usize].align != .Right { ret chart.Invalid }
    labels[6usize] = chart.Label { text: "A < B & C", anchor: chart.Coord { x: 60.0, y: 15.0 }, align: .Center }
    let (_, short_error) = chart.guide_labels(bounds, x_ticks[..], x_text[..], y_ticks[..], y_text[..], 10.0, labels[..5usize])
    if short_error != chart.TooLarge { ret chart.Invalid }
    let bad_text = [3]str{ "0", "bad\nlabel", "2" }
    let (_, text_error) = chart.guide_labels(bounds, x_ticks[..], bad_text[..], y_ticks[..], y_text[..], 10.0, labels[..])
    if text_error != chart.Invalid { ret chart.Invalid }
    let (font_bytes, font_error) = fs.read_file(a, args[1usize], 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append_labels(a, &builder, labels[..7usize], font, 10.0, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 110.0, "Labels", "Tick labels")
    try chart_svg.append_labels(&writer, labels[..7usize], ink, 10.0)
    try chart_svg.finish(&writer)
    let output = io.memory_bytes(&held)
    if !str.contains(output, "text-anchor=\"middle\"") || !str.contains(output, "text-anchor=\"end\"") || !str.contains(output, "A &lt; B &amp; C") || !str.contains(output, "</svg>") { ret chart.Invalid }
    let invalid = [1]chart.Label{ chart.Label { text: "bad\nlabel", anchor: chart.Coord { x: 0.0, y: 0.0 }, align: .Left } }
    if chart_svg.append_labels(&writer, invalid[..], ink, 10.0) != chart_svg.Invalid { ret chart.Invalid }
    try io.print("gfx chart labels ok\n")
    ret ok
}
