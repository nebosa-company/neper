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
    let x = [5]f32{ 0.0, 1.0, 2.0, 3.0, 4.0 }
    let planned = [5]f32{ 0.0, 10.0, 20.0, 30.0, 40.0 }
    let earned = [3]f32{ 0.0, 8.0, 16.0 }
    let actual = [3]f32{ 0.0, 9.0, 20.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 80.0)
    var planned_segments: [4]chart.Segment = zero
    var earned_segments: [2]chart.Segment = zero
    var actual_segments: [2]chart.Segment = zero
    let (pv, ev, ac, result) = chart.earned_value(x[..], planned[..], earned[..], actual[..], bounds, planned_segments[..], earned_segments[..], actual_segments[..])
    if result != ok || pv.kind != .Line || ev.kind != .Line || ac.kind != .Line || pv.segments.len != 4usize || ev.segments.len != 2usize || ac.segments.len != 2usize { ret chart.Invalid }
    if !near(pv.x_max, 4.0) || !near(ev.x_max, 4.0) || !near(ac.x_max, 4.0) || !near(pv.y_max, 40.0) || !near(ev.y_max, 40.0) || !near(ac.y_max, 40.0) { ret chart.Invalid }
    if !near(pv.segments[3usize].to.x, 100.0) || !near(ev.segments[1usize].to.x, 50.0) || !near(ev.segments[1usize].to.y, 48.0) || !near(ac.segments[1usize].to.y, 40.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &pv, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &ev, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &ac, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) == 0usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 100.0, "Earned value", "PV EV AC")
    try chart_svg.append(&writer, &pv, ink)
    try chart_svg.append(&writer, &ev, ink)
    try chart_svg.append(&writer, &ac, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let flat = [5]f32{ 0.0, 0.0, 0.0, 0.0, 0.0 }
    let flat_short = [3]f32{ 0.0, 0.0, 0.0 }
    let (flat_pv, flat_ev, flat_ac, flat_error) = chart.earned_value(x[..], flat[..], flat_short[..], flat_short[..], bounds, planned_segments[..], earned_segments[..], actual_segments[..])
    if flat_error != ok || !near(flat_pv.y_max, 1.0) || !near(flat_ev.y_max, 1.0) || !near(flat_ac.y_max, 1.0) { ret chart.Invalid }
    let repeated = [5]f32{ 0.0, 1.0, 1.0, 3.0, 4.0 }
    let negative = [3]f32{ 0.0, -1.0, 2.0 }
    let (_, _, _, empty_error) = chart.earned_value(x[..0usize], planned[..0usize], earned[..0usize], actual[..0usize], bounds, planned_segments[..], earned_segments[..], actual_segments[..])
    let (_, _, _, order_error) = chart.earned_value(repeated[..], planned[..], earned[..], actual[..], bounds, planned_segments[..], earned_segments[..], actual_segments[..])
    let (_, _, _, negative_error) = chart.earned_value(x[..], planned[..], negative[..], actual[..], bounds, planned_segments[..], earned_segments[..], actual_segments[..])
    let (_, _, _, measured_error) = chart.earned_value(x[..], planned[..], earned[..1usize], actual[..1usize], bounds, planned_segments[..], earned_segments[..], actual_segments[..])
    let (_, _, _, capacity_error) = chart.earned_value(x[..], planned[..], earned[..], actual[..], bounds, planned_segments[..3usize], earned_segments[..], actual_segments[..])
    if empty_error != chart.Empty || order_error != chart.Invalid || negative_error != chart.Invalid || measured_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart earned value ok\n")
    ret ok
}
