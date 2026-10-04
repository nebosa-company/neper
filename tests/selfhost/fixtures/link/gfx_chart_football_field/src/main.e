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
    let methods = [4]chart.RangeInterval{
        chart.RangeInterval { row: 0usize, lower: 70.0f64, upper: 115.0f64 },
        chart.RangeInterval { row: 1usize, lower: 100.0f64, upper: 150.0f64 },
        chart.RangeInterval { row: 2usize, lower: 85.0f64, upper: 145.0f64 },
        chart.RangeInterval { row: 3usize, lower: 60.0f64, upper: 95.0f64 },
    }
    let bounds = geometry.rect(108.0, 50.0, 230.0, 136.0)
    var bands: [4]geometry.Rect = zero
    var caps: [8]chart.Segment = zero
    var benchmark: [1]chart.Segment = zero
    let (field, field_error) = chart.football_field(methods[..], 50.0f64, 160.0f64, 100.0f64, bounds, bands[..], caps[..], benchmark[..])
    if field_error != ok || field.ranges.bars.len != 4usize || field.caps.segments.len != 8usize || field.benchmark.segments.len != 1usize { ret chart.Invalid }
    if !near(bands[0usize].x, 149.81818f32) || !near(bands[0usize].width, 94.09091f32) || !near(benchmark[0usize].from.x, 212.54546f32) || !near(benchmark[0usize].to.x, 212.54546f32) { ret chart.Invalid }
    if !near(caps[0usize].from.x, bands[0usize].x) || !near(caps[1usize].from.x, bands[0usize].x + bands[0usize].width) || bands[0usize].y >= bands[1usize].y { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &field.ranges, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &field.caps, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &field.benchmark, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Football field", "Common-basis valuation ranges")
    try chart_svg.append(&writer, &field.ranges, ink)
    try chart_svg.append(&writer, &field.caps, ink)
    try chart_svg.append(&writer, &field.benchmark, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "<line") { ret chart.Invalid }
    let (_, empty_error) = chart.football_field(methods[..0usize], 50.0f64, 160.0f64, 100.0f64, bounds, bands[..], caps[..], benchmark[..])
    let (_, benchmark_error) = chart.football_field(methods[..], 50.0f64, 160.0f64, 170.0f64, bounds, bands[..], caps[..], benchmark[..])
    let (_, domain_error) = chart.football_field(methods[..], 160.0f64, 50.0f64, 100.0f64, bounds, bands[..], caps[..], benchmark[..])
    let (_, short_error) = chart.football_field(methods[..], 50.0f64, 160.0f64, 100.0f64, bounds, bands[..], caps[..7usize], benchmark[..])
    let (_, rule_error) = chart.football_field(methods[..], 50.0f64, 160.0f64, 100.0f64, bounds, bands[..], caps[..], benchmark[..0usize])
    let unordered = [1]chart.RangeInterval{ chart.RangeInterval { row: 2usize, lower: 70.0f64, upper: 115.0f64 } }
    let (_, row_error) = chart.football_field(unordered[..], 50.0f64, 160.0f64, 100.0f64, bounds, bands[..], caps[..], benchmark[..])
    let reversed = [1]chart.RangeInterval{ chart.RangeInterval { row: 0usize, lower: 115.0f64, upper: 70.0f64 } }
    let (_, interval_error) = chart.football_field(reversed[..], 50.0f64, 160.0f64, 100.0f64, bounds, bands[..], caps[..], benchmark[..])
    if empty_error != chart.Empty || benchmark_error != chart.Invalid || domain_error != chart.Invalid || short_error != chart.TooLarge || rule_error != chart.TooLarge || row_error != chart.Invalid || interval_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart football field ok\n")
    ret ok
}
