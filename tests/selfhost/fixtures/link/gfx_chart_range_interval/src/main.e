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
    let delta = a - b
    ret delta > -0.001 && delta < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let items = [3]chart.RangeInterval{
        chart.RangeInterval { row: 2usize, lower: 20.0f64, upper: 30.0f64 },
        chart.RangeInterval { row: 0usize, lower: -10.0f64, upper: 0.0f64 },
        chart.RangeInterval { row: 1usize, lower: 5.0f64, upper: 20.0f64 },
    }
    let bounds = geometry.rect(10.0, 20.0, 200.0, 90.0)
    var bands: [3]geometry.Rect = zero
    var caps: [6]chart.Segment = zero
    let (map, result) = chart.range_intervals(items[..], 3usize, -10.0f64, 30.0f64, bounds, 0.4, bands[..], caps[..])
    if result != ok || map.ranges.kind != .Bar || map.caps.kind != .Rug || map.ranges.bars.len != 3usize || map.caps.segments.len != 6usize || map.ranges.x_min != -10.0 || map.ranges.x_max != 30.0 { ret chart.Invalid }
    if !near(bands[0usize].x, 160.0) || !near(bands[0usize].y, 89.0) || !near(bands[0usize].width, 50.0) || !near(bands[0usize].height, 12.0) || !near(bands[1usize].x, 10.0) || !near(bands[1usize].y, 29.0) || !near(bands[2usize].x, 85.0) || !near(bands[2usize].width, 75.0) { ret chart.Invalid }
    if !near(caps[0usize].from.x, 160.0) || !near(caps[0usize].from.y, 83.0) || !near(caps[0usize].to.y, 107.0) || !near(caps[1usize].from.x, 210.0) || !near(caps[4usize].from.x, 85.0) || !near(caps[5usize].from.x, 160.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.ranges, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.caps, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 9usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 230.0, 130.0, "Range intervals", "Floating low-to-high spans")
    try chart_svg.append(&writer, &map.ranges, ink)
    try chart_svg.append(&writer, &map.caps, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad_row = [1]chart.RangeInterval{ chart.RangeInterval { row: 3usize, lower: 0.0f64, upper: 1.0f64 } }
    let reversed = [1]chart.RangeInterval{ chart.RangeInterval { row: 0usize, lower: 2.0f64, upper: 1.0f64 } }
    let zero_width = [1]chart.RangeInterval{ chart.RangeInterval { row: 0usize, lower: 1.0f64, upper: 1.0f64 } }
    let outside = [1]chart.RangeInterval{ chart.RangeInterval { row: 0usize, lower: -11.0f64, upper: 1.0f64 } }
    let (_, empty_error) = chart.range_intervals(items[..0usize], 3usize, -10.0f64, 30.0f64, bounds, 0.4, bands[..], caps[..])
    let (_, row_error) = chart.range_intervals(bad_row[..], 3usize, -10.0f64, 30.0f64, bounds, 0.4, bands[..], caps[..])
    let (_, reverse_error) = chart.range_intervals(reversed[..], 3usize, -10.0f64, 30.0f64, bounds, 0.4, bands[..], caps[..])
    let (_, width_error) = chart.range_intervals(zero_width[..], 3usize, -10.0f64, 30.0f64, bounds, 0.4, bands[..], caps[..])
    let (_, outside_error) = chart.range_intervals(outside[..], 3usize, -10.0f64, 30.0f64, bounds, 0.4, bands[..], caps[..])
    let (_, domain_error) = chart.range_intervals(items[..], 3usize, 30.0f64, 30.0f64, bounds, 0.4, bands[..], caps[..])
    let (_, bounds_error) = chart.range_intervals(items[..], 3usize, -10.0f64, 30.0f64, geometry.rect(0.0, 0.0, -1.0, 90.0), 0.4, bands[..], caps[..])
    let (_, thickness_error) = chart.range_intervals(items[..], 3usize, -10.0f64, 30.0f64, bounds, 1.1, bands[..], caps[..])
    let (_, band_error) = chart.range_intervals(items[..], 3usize, -10.0f64, 30.0f64, bounds, 0.4, bands[..2usize], caps[..])
    let (_, cap_error) = chart.range_intervals(items[..], 3usize, -10.0f64, 30.0f64, bounds, 0.4, bands[..], caps[..5usize])
    let (_, lane_error) = chart.range_intervals(items[..], 3usize, -10.0f64, 30.0f64, geometry.rect(10.0, 20.0, 200.0, 20.0), 0.4, bands[..], caps[..])
    if empty_error != chart.Empty || row_error != chart.Invalid || reverse_error != chart.Invalid || width_error != chart.Invalid || outside_error != chart.Invalid || domain_error != chart.Invalid || bounds_error != chart.Invalid || thickness_error != chart.Invalid || band_error != chart.TooLarge || cap_error != chart.TooLarge || lane_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart range interval ok\n")
    ret ok
}
