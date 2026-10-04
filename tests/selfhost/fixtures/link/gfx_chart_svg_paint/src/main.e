use e.bytes
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn count(text: str, needle: str) -> usize {
    var n = 0usize
    var i = 0usize
    while i + needle.len <= text.len {
        if str.starts_with(text[i..], needle) { n += 1usize }
        i += 1usize
    }
    ret n
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [3]f32{ 0.0, 1.0, 2.0 }
    let y = [3]f32{ 2.0, 5.0, 3.0 }
    var bar_storage: [3]geometry.Rect = zero
    var point_storage: [8]chart.Coord = zero
    var unused_points: [1]chart.Coord = zero
    var unused_lines: [1]chart.Segment = zero
    var line_storage: [2]chart.Segment = zero
    var unused_bars: [1]geometry.Rect = zero
    let bounds = geometry.rect(0.0, 0.0, 120.0, 100.0)
    let bar_spec = chart.spec(.Bar, bounds, x[..], y[..])
    let (bars, bars_error) = chart.layout(&bar_spec, unused_points[..0usize], unused_lines[..0usize], bar_storage[..])
    let area_spec = chart.spec(.Area, bounds, x[..], y[..])
    let (area, area_error) = chart.layout(&area_spec, point_storage[..], unused_lines[..0usize], unused_bars[..0usize])
    let line_spec = chart.spec(.Line, bounds, x[..], y[..])
    let (trend, line_error) = chart.layout(&line_spec, unused_points[..0usize], line_storage[..], unused_bars[..0usize])
    if bars_error != ok || area_error != ok || line_error != ok { ret chart.Invalid }
    let fade = [2]paint.Stop{ paint.Stop { offset: 0.0, color: paint.rgba(0.1, 0.4, 0.8, 1.0) }, paint.Stop { offset: 1.0, color: paint.rgba(0.6, 0.8, 1.0, 0.5) } }
    let vertical = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: 0.0, y: 100.0 }, end: geometry.Point { x: 0.0, y: 0.0 }, stops: fade[..] } }
    let glow = paint.Brush { Radial: paint.RadialGradient { center: geometry.Point { x: 60.0, y: 50.0 }, radius: 40.0, stops: fade[..] } }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 100.0, "Paint", "Gradients and an embedded face")
    try chart_svg.append_brush(&writer, &bars, vertical, "fade")
    try chart_svg.append_brush(&writer, &area, glow, "glow")
    try chart_svg.append_brush(&writer, &trend, vertical, "stroke-fade")
    try chart_svg.append_brush(&writer, &bars, paint.Brush { Solid: paint.rgba(1.0, 0.0, 0.0, 1.0) }, "ignored")
    // 1,601 bytes cross two 765-byte encoder chunks and leave a two-byte tail.
    var face: [1601]u8 = zero
    face[1usize] = 1u8
    var i = 4usize
    while i < face.len {
        face[i] = u8((i * 7usize) % 256usize)
        i += 1usize
    }
    try chart_svg.embed_font(&writer, "Test Face", face[..])
    let labels = [1]chart.Label{ chart.Label { text: "a<b", anchor: chart.Coord { x: 4.0, y: 12.0 }, align: .Left } }
    try chart_svg.append_labels_in(&writer, labels[..], paint.rgba(0.0, 0.0, 0.0, 1.0), 9.0, "Test Face")
    try chart_svg.append_labels(&writer, labels[..], paint.rgba(0.0, 0.0, 0.0, 1.0), 9.0)
    try chart_svg.finish(&writer)
    let output = io.memory_bytes(&held)
    if !str.contains(output, "<defs><linearGradient id=\"fade\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"100\" x2=\"0\" y2=\"0\"><stop offset=\"0\" stop-color=\"rgb(26,102,204)\" stop-opacity=\"1\"/><stop offset=\"1\" stop-color=\"rgb(153,204,255)\" stop-opacity=\"0.5\"/></linearGradient></defs>") { ret chart.Invalid }
    if !str.contains(output, "<radialGradient id=\"glow\" gradientUnits=\"userSpaceOnUse\" cx=\"60\" cy=\"50\" r=\"40\">") { ret chart.Invalid }
    if count(output, " fill=\"url(#fade)\"") != 3usize || count(output, " fill=\"url(#glow)\"") != 1usize || count(output, " stroke=\"url(#stroke-fade)\"") != 1usize { ret chart.Invalid }
    if count(output, "fill=\"rgb(255,0,0)\"") != 3usize || str.contains(output, "ignored") { ret chart.Invalid }
    if !str.contains(output, "font-family=\"'Test Face', sans-serif\"") || !str.contains(output, "font-family=\"sans-serif\"") || !str.contains(output, ">a&lt;b</text>") { ret chart.Invalid }
    // The embedded payload decodes back to the font bytes.
    let prefix = "@font-face{font-family:\"Test Face\";src:url(data:font/ttf;base64,"
    let (start, found) = str.find(output, prefix)
    if !found { ret chart.Invalid }
    let payload_start = start + prefix.len
    let (close, closed) = str.find(output[payload_start..], ")}")
    if !closed || close != 2136usize { ret chart.Invalid }
    var decoded: [1601]u8 = zero
    let (back, decode_error) = bytes.base64_decode(decoded[..], output[payload_start..payload_start + close], .Standard)
    if decode_error != ok || back.len != face.len || !str.eq(back, face[..]) { ret chart.Invalid }
    // The scene adapter takes the same brushes.
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &bars, vertical)
    try chart_scene.append(a, &builder, &area, glow)
    if scene.builder_count(&builder) < 4usize { ret chart.Invalid }
    let unsorted = [2]paint.Stop{ fade[1usize], fade[0usize] }
    let flat = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: 5.0, y: 5.0 }, end: geometry.Point { x: 5.0, y: 5.0 }, stops: fade[..] } }
    let backwards = paint.Brush { Linear: paint.LinearGradient { start: geometry.Point { x: 0.0, y: 0.0 }, end: geometry.Point { x: 1.0, y: 0.0 }, stops: unsorted[..] } }
    let empty = paint.Brush { Radial: paint.RadialGradient { center: geometry.Point { x: 0.0, y: 0.0 }, radius: 4.0, stops: fade[..0usize] } }
    let bad_id = chart_svg.gradient(&writer, "1fade", vertical)
    let solid = chart_svg.gradient(&writer, "solid", paint.Brush { Solid: paint.rgba(0.0, 0.0, 0.0, 1.0) })
    let flat_error = chart_svg.gradient(&writer, "flat", flat)
    let order_error = chart_svg.gradient(&writer, "order", backwards)
    let empty_error = chart_svg.gradient(&writer, "empty", empty)
    if bad_id != chart_svg.Invalid || solid != chart_svg.Invalid || flat_error != chart_svg.Invalid || order_error != chart_svg.Invalid || empty_error != chart_svg.Invalid { ret chart.Invalid }
    var not_font: [16]u8 = zero
    not_font[0usize] = 80u8
    let magic_error = chart_svg.embed_font(&writer, "Test Face", not_font[..])
    let family_error = chart_svg.embed_font(&writer, "Bad\"Face", face[..])
    let short_error = chart_svg.embed_font(&writer, "Short", face[..8usize])
    let label_error = chart_svg.append_labels_in(&writer, labels[..], paint.rgba(0.0, 0.0, 0.0, 1.0), 9.0, "x;y")
    if magic_error != chart_svg.Invalid || family_error != chart_svg.Invalid || short_error != chart_svg.Invalid || label_error != chart_svg.Invalid { ret chart.Invalid }
    try io.print("gfx chart svg paint ok\n")
    ret ok
}
