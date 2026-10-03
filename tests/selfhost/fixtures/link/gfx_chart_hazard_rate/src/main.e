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

fn near(value: f64, expected: f64) -> bool {
    let delta = value - expected
    ret delta > -0.0001f64 && delta < 0.0001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let times = [6]f64{ 1.0f64, 2.0f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64 }
    let event = [6]bool{ true, true, true, false, true, false }
    let edges = [4]f64{ 0.0f64, 2.0f64, 4.0f64, 6.0f64 }
    var counts: [3]u64 = zero
    var exposure: [3]f64 = zero
    var rates: [3]f64 = zero
    try stat.interval_hazard(times[..], event[..], edges[..], counts[..], exposure[..], rates[..])
    if counts[0usize] != 2u64 || counts[1usize] != 1u64 || counts[2usize] != 1u64 || !near(exposure[0usize], 11.0f64) || !near(exposure[1usize], 7.0f64) || !near(exposure[2usize], 3.0f64) || !near(rates[0usize], 2.0f64 / 11.0f64) || !near(rates[1usize], 1.0f64 / 7.0f64) || !near(rates[2usize], 1.0f64 / 3.0f64) { ret chart.Invalid }
    let bounds = geometry.rect(20.0, 30.0, 120.0, 90.0)
    var lines: [5]chart.Segment = zero
    let (marks, marks_error) = chart.hazard_rate(edges[..], rates[..], bounds, lines[..])
    if marks_error != ok || marks.kind != .Step || marks.segments.len != 5usize || !near(f64(lines[0usize].from.x), 20.0f64) || !near(f64(lines[0usize].to.x), 60.0f64) || !near(f64(lines[1usize].from.x), 60.0f64) || !near(f64(lines[1usize].to.x), 60.0f64) || !near(f64(lines[4usize].to.x), 140.0f64) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 3usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 1usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 170.0, 150.0, "Interval hazard", "Events per observed person-time")
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<path") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let bad_edges = [4]f64{ 0.0f64, 2.0f64, 2.0f64, 6.0f64 }
    let (_, empty_error) = chart.hazard_rate(edges[..1usize], rates[..0usize], bounds, lines[..])
    let (_, edges_error) = chart.hazard_rate(bad_edges[..], rates[..], bounds, lines[..])
    let (_, capacity_error) = chart.hazard_rate(edges[..], rates[..], bounds, lines[..4usize])
    let stat_edges_error = stat.interval_hazard(times[..], event[..], bad_edges[..], counts[..], exposure[..], rates[..])
    let stat_capacity_error = stat.interval_hazard(times[..], event[..], edges[..], counts[..2usize], exposure[..], rates[..])
    let short_times = [1]f64{ 1.0f64 }
    let short_event = [1]bool{ false }
    let no_exposure_error = stat.interval_hazard(short_times[..], short_event[..], edges[..], counts[..], exposure[..], rates[..])
    if empty_error != chart.Empty || edges_error != chart.Invalid || capacity_error != chart.TooLarge || stat_edges_error != stat.Invalid || stat_capacity_error != stat.TooSmall || no_exposure_error != stat.Invalid { ret chart.Invalid }
    try io.print("gfx chart hazard rate ok\n")
    ret ok
}
