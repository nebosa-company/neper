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
    let x = [4]f32{ 0.0, 1.0, 3.0, 4.0 }
    let remaining = [4]f32{ 12.0, 10.0, 6.0, 3.0 }
    let completed = [4]f32{ 0.0, 3.0, 7.0, 9.0 }
    let scope = [4]f32{ 12.0, 12.0, 14.0, 14.0 }
    let bounds = geometry.rect(10.0, 20.0, 100.0, 80.0)
    var ideal: [4]f32 = zero
    var actual_segments: [3]chart.Segment = zero
    var reference_segments: [3]chart.Segment = zero
    let (down, ideal_marks, down_error) = chart.burndown(x[..], remaining[..], bounds, ideal[..], actual_segments[..], reference_segments[..])
    if down_error != ok || down.kind != .Line || ideal_marks.kind != .Line || down.segments.len != 3usize || ideal_marks.segments.len != 3usize { ret chart.Invalid }
    if !near(ideal[0usize], 12.0) || !near(ideal[1usize], 9.0) || !near(ideal[2usize], 3.0) || !near(ideal[3usize], 0.0) || !near(ideal_marks.segments[2usize].to.y, 100.0) || !near(down.segments[2usize].to.y, 80.0) || !near(down.x_min, ideal_marks.x_min) || !near(down.y_max, ideal_marks.y_max) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &down, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &ideal_marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) == 0usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 140.0, 120.0, "Burndown", "Actual and ideal remaining work")
    try chart_svg.append(&writer, &down, ink)
    try chart_svg.append(&writer, &ideal_marks, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let (up, scope_line, up_error) = chart.burnup(x[..], completed[..], scope[..], bounds, actual_segments[..], reference_segments[..])
    if up_error != ok || up.kind != .Line || scope_line.kind != .Line || !near(up.y_max, 14.0) || !near(scope_line.y_max, 14.0) || !near(scope_line.segments[2usize].to.y, 20.0) || !near(up.segments[2usize].to.x, 110.0) { ret chart.Invalid }
    let flat = [4]f32{ 0.0, 0.0, 0.0, 0.0 }
    let (flat_up, flat_scope, flat_error) = chart.burnup(x[..], flat[..], flat[..], bounds, actual_segments[..], reference_segments[..])
    if flat_error != ok || !near(flat_up.y_max, 1.0) || !near(flat_scope.y_max, 1.0) { ret chart.Invalid }
    let backwards = [4]f32{ 0.0, 1.0, 1.0, 4.0 }
    let negative = [4]f32{ 12.0, -1.0, 6.0, 3.0 }
    let too_complete = [4]f32{ 0.0, 13.0, 7.0, 9.0 }
    let (_, _, empty_error) = chart.burndown(x[..0usize], remaining[..0usize], bounds, ideal[..], actual_segments[..], reference_segments[..])
    let (_, _, order_error) = chart.burndown(backwards[..], remaining[..], bounds, ideal[..], actual_segments[..], reference_segments[..])
    let (_, _, negative_error) = chart.burndown(x[..], negative[..], bounds, ideal[..], actual_segments[..], reference_segments[..])
    let (_, _, overflow_error) = chart.burnup(x[..], too_complete[..], scope[..], bounds, actual_segments[..], reference_segments[..])
    let (_, _, capacity_error) = chart.burndown(x[..], remaining[..], bounds, ideal[..3usize], actual_segments[..], reference_segments[..])
    let (_, _, segment_error) = chart.burnup(x[..], completed[..], scope[..], bounds, actual_segments[..2usize], reference_segments[..])
    if empty_error != chart.Empty || order_error != chart.Invalid || negative_error != chart.Invalid || overflow_error != chart.Invalid || capacity_error != chart.TooLarge || segment_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart burn ok\n")
    ret ok
}
