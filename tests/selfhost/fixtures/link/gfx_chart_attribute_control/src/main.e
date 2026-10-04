use e.algo.stat
use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool {
    let d = a - b
    ret d > -0.001f64 && d < 0.001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let counts = [4]usize{ 2usize, 5usize, 3usize, 8usize }
    let p_sizes = [4]usize{ 50usize, 100usize, 50usize, 100usize }
    let np_sizes = [4]usize{ 100usize, 100usize, 100usize, 100usize }
    let c_sizes = [4]usize{ 1usize, 1usize, 1usize, 1usize }
    let u_sizes = [4]usize{ 5usize, 10usize, 5usize, 10usize }
    var points: [4]stat.AttributeControlPoint = zero
    if stat.attribute_control(.P, counts[..], p_sizes[..], points[..]) != ok || !near(points[0usize].value, 0.04) || !near(points[0usize].center, 0.06) || !near(points[0usize].upper, 0.160757) || !near(points[1usize].upper, 0.131246) || !near(points[0usize].lower, 0.0) { ret stat.Invalid }
    if stat.attribute_control(.Np, counts[..], np_sizes[..], points[..]) != ok || !near(points[0usize].value, 2.0) || !near(points[0usize].center, 4.5) || !near(points[0usize].upper, 10.719124) { ret stat.Invalid }
    if stat.attribute_control(.C, counts[..], c_sizes[..], points[..]) != ok || !near(points[0usize].center, 4.5) || !near(points[0usize].upper, 10.863961) { ret stat.Invalid }
    if stat.attribute_control(.U, counts[..], u_sizes[..], points[..]) != ok || !near(points[0usize].value, 0.4) || !near(points[0usize].center, 0.6) || !near(points[0usize].upper, 1.63923) || !near(points[1usize].upper, 1.334847) { ret stat.Invalid }
    if stat.attribute_control(.P, counts[..], p_sizes[..], points[..3usize]) != stat.TooSmall { ret stat.Invalid }
    let invalid_counts = [4]usize{ 51usize, 5usize, 3usize, 8usize }
    if stat.attribute_control(.P, invalid_counts[..], p_sizes[..], points[..]) != stat.Invalid { ret stat.Invalid }
    if stat.attribute_control(.Np, counts[..], p_sizes[..], points[..]) != stat.Invalid { ret stat.Invalid }
    if stat.attribute_control(.C, counts[..], p_sizes[..], points[..]) != stat.Invalid { ret stat.Invalid }
    let zero_sizes = [4]usize{ 5usize, 0usize, 5usize, 10usize }
    if stat.attribute_control(.U, counts[..], zero_sizes[..], points[..]) != stat.Invalid { ret stat.Invalid }
    let over_unit = [4]usize{ 11usize, 5usize, 3usize, 8usize }
    if stat.attribute_control(.U, over_unit[..], u_sizes[..], points[..]) != ok || !near(points[0usize].value, 2.2) { ret stat.Invalid }
    let extremes = [2]usize{ 0usize, 1usize }
    let one_each = [2]usize{ 1usize, 1usize }
    if stat.attribute_control(.P, extremes[..], one_each[..], points[..]) != ok || !near(points[0usize].lower, 0.0) || !near(points[0usize].upper, 1.0) { ret stat.Invalid }

    let x = [4]f32{ 0.0, 0.333333, 0.666667, 1.0 }
    let y = [4]f32{ 0.04, 0.05, 0.06, 0.08 }
    var plot = chart.spec(.PointLine, geometry.rect(30.0, 20.0, 200.0, 100.0), x[..], y[..])
    var coords: [4]chart.Coord = zero
    var lines: [3]chart.Segment = zero
    let x_limits = [2]f32{ 0.0, 1.0 }
    let y_limits = [2]f32{ 0.0, 0.2 }
    let (marks, layout_error) = chart.layout_with_limits(&plot, coords[..], lines[..], zero, x_limits[..], y_limits[..])
    if layout_error != ok || marks.kind != .PointLine { ret chart.Invalid }
    var rule_segments = [1]chart.Segment{ chart.Segment { from: chart.Coord { x: 30.0, y: 40.0 }, to: chart.Coord { x: 230.0, y: 55.0 } } }
    let rule = chart.Layout { kind: .Rug, coords: zero, segments: rule_segments[..], bars: zero, x_min: 0.0, x_max: 1.0, y_min: 0.0, y_max: 0.2 }
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &rule, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 260.0, 160.0, "P chart", "Variable sample limits")
    try chart_svg.append(&writer, &rule, blue)
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "<line") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    try io.print("gfx chart attribute control ok\n")
    ret ok
}
