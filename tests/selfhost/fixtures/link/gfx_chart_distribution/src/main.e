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
    let difference = a - b
    ret difference > -0.01 && difference < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let sample = [6]f32{ 0.0, 1.0, 1.0, 2.0, 3.0, 4.0 }
    var counts: [4]u64 = zero
    var bins: [4]geometry.Rect = zero
    var polygon_lines: [5]chart.Segment = zero
    let (polygon, polygon_error) = chart.frequency_polygon(sample[..], bounds, counts[..], bins[..], polygon_lines[..])
    if polygon_error != ok || polygon.kind != .FrequencyPolygon || polygon.segments.len != 5usize || !near(polygon.y_max, 2.0) || counts[1] != 2u64 || !near(polygon.segments[0].from.x, 0.0) || !near(polygon.segments[0].to.x, 12.5) || !near(polygon.segments[0].to.y, 50.0) || !near(polygon.segments[4].to.x, 100.0) || !near(polygon.segments[4].to.y, 100.0) { ret chart.Invalid }
    let (_, short_polygon) = chart.frequency_polygon(sample[..], bounds, counts[..], bins[..], polygon_lines[..4usize])
    if short_polygon != chart.TooLarge { ret chart.Invalid }
    let (_, empty_polygon) = chart.frequency_polygon(sample[..0usize], bounds, counts[..], bins[..], polygon_lines[..])
    if empty_polygon != chart.Empty { ret chart.Invalid }
    let rug_values = [4]f32{ 0.0, 1.0, 1.0, 2.0 }
    var rug_lines: [4]chart.Segment = zero
    let (rug, rug_error) = chart.rug(rug_values[..], bounds, 8.0, rug_lines[..])
    if rug_error != ok || rug.kind != .Rug || rug.segments.len != 4usize || !near(rug.segments[0].from.x, 0.0) || !near(rug.segments[1].from.x, 50.0) || !near(rug.segments[2].from.x, 50.0) || !near(rug.segments[3].from.x, 100.0) || !near(rug.segments[0].to.y, 92.0) { ret chart.Invalid }
    let (_, short_rug) = chart.rug(rug_values[..], bounds, 8.0, rug_lines[..3usize])
    if short_rug != chart.TooLarge { ret chart.Invalid }
    let (_, tall_rug) = chart.rug(rug_values[..], bounds, 101.0, rug_lines[..])
    if tall_rug != chart.Invalid { ret chart.Invalid }
    let same = [2]f32{ 7.0, 7.0 }
    let (constant, constant_error) = chart.rug(same[..], bounds, 8.0, rug_lines[..])
    if constant_error != ok || !near(constant.segments[0].from.x, 50.0) { ret chart.Invalid }
    var generic = chart.spec(.Rug, bounds, rug_values[..], rug_values[..])
    let (_, generic_error) = chart.layout(&generic, zero, zero, zero)
    if generic_error != chart.Invalid { ret chart.Invalid }
    var strip_points: [4]chart.Coord = zero
    let (strip, strip_error) = chart.strip(rug_values[..], bounds, 8.0, strip_points[..])
    if strip_error != ok || strip.kind != .Strip || strip.coords.len != 4usize || !near(strip.coords[1].x, 50.0) || !near(strip.coords[2].x, 50.0) || near(strip.coords[1].y, strip.coords[2].y) { ret chart.Invalid }
    let (_, short_strip) = chart.strip(rug_values[..], bounds, 8.0, strip_points[..3usize])
    if short_strip != chart.TooLarge { ret chart.Invalid }
    let (_, wide_strip) = chart.strip(rug_values[..], bounds, 51.0, strip_points[..])
    if wide_strip != chart.Invalid { ret chart.Invalid }
    let (constant_strip, constant_strip_error) = chart.strip(same[..], bounds, 8.0, strip_points[..])
    if constant_strip_error != ok || !near(constant_strip.coords[0].x, 50.0) { ret chart.Invalid }
    generic.kind = .Strip
    let (_, generic_strip_error) = chart.layout(&generic, zero, zero, zero)
    if generic_strip_error != chart.Invalid { ret chart.Invalid }
    let point_x = [4]f32{ 0.0, 1.0, 2.0, 3.0 }
    var point_line = chart.spec(.PointLine, bounds, point_x[..], rug_values[..])
    var line_points: [4]chart.Coord = zero
    var line_segments: [3]chart.Segment = zero
    let (joined, joined_error) = chart.layout(&point_line, line_points[..], line_segments[..], zero)
    if joined_error != ok || joined.kind != .PointLine || joined.coords.len != 4usize || joined.segments.len != 3usize || !near(joined.segments[0].to.x, joined.coords[1].x) || !near(joined.segments[2].to.y, joined.coords[3].y) { ret chart.Invalid }
    let (_, short_joined) = chart.layout(&point_line, line_points[..], line_segments[..2usize], zero)
    if short_joined != chart.TooLarge { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let ink = paint.rgba(0.07, 0.35, 0.76, 1.0)
    try chart_scene.append(a, &builder, &polygon, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &rug, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &strip, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &joined, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 14usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Chart variants", "Distribution and point-line marks")
    try chart_svg.append(&writer, &polygon, ink)
    try chart_svg.append(&writer, &rug, ink)
    try chart_svg.append(&writer, &strip, ink)
    try chart_svg.append(&writer, &joined, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path d=\"M") || !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart distribution ok\n")
    ret ok
}
