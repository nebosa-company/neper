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

fn main(a: *mem.Arena, args: []str) -> err {
    if args.len < 2usize { ret chart.Invalid }
    let clip = geometry.rect(20.0, 30.0, 80.0, 50.0)
    let labels = [1]chart.Label{
        chart.Label { text: "Beyond <panel> & clipped", anchor: chart.Coord { x: 82.0, y: 53.0 }, align: .Left },
    }
    let ink = paint.rgba(0.1, 0.3, 0.8, 1.0)
    let (font_bytes, font_error) = fs.read_file(a, args[1usize], 1048576usize)
    if font_error != ok { ret font_error }
    let font = shape.Font { id: 17u32, data: font_bytes, face_index: 0u32 }
    let (made, builder_error) = scene.builder(a, 5usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.begin_clip(&builder, clip)
    try chart_scene.append_labels(a, &builder, labels[..], font, 10.0, paint.Brush { Solid: ink })
    try chart_scene.end_clip(&builder)
    if scene.builder_count(&builder) != 4usize || scene.builder_remaining(&builder) != 1usize { ret chart.Invalid }
    let list = scene.finish(&builder)
    if list.commands.len != 4usize || list.commands[0usize].tag != .Save || list.commands[1usize].tag != .Clip || list.commands[2usize].tag != .Text || list.commands[3usize].tag != .Restore { ret chart.Invalid }
    let (short_made, short_builder_error) = scene.builder(a, 1usize)
    if short_builder_error != ok { ret short_builder_error }
    var short_builder = short_made
    if chart_scene.begin_clip(&short_builder, clip) != chart.TooLarge || scene.builder_count(&short_builder) != 0usize { ret chart.Invalid }
    if chart_scene.begin_clip(&short_builder, geometry.rect(20.0, 30.0, 0.0, 50.0)) != chart.Invalid { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 100.0, "Clipped annotation", "Rectangular clipping")
    try chart_svg.begin_clip(&writer, clip, "panel-1")
    try chart_svg.append_labels(&writer, labels[..], ink, 10.0)
    try chart_svg.end_clip(&writer)
    try chart_svg.finish(&writer)
    let output = io.memory_bytes(&held)
    if !str.contains(output, "<clipPath id=\"panel-1\"><rect x=\"20") || !str.contains(output, "clip-path=\"url(#panel-1)\"") || !str.contains(output, "Beyond &lt;panel&gt; &amp; clipped") || !str.contains(output, "</g>\n</svg>") { ret chart.Invalid }
    if chart_svg.begin_clip(&writer, clip, "bad\"id") != chart_svg.Invalid || chart_svg.begin_clip(&writer, clip, "1bad") != chart_svg.Invalid || chart_svg.begin_clip(&writer, geometry.rect(0.0, 0.0, 0.0, 1.0), "good") != chart_svg.Invalid { ret chart.Invalid }
    try io.print("gfx chart clipped annotation ok\n")
    ret ok
}
