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
    let spans = [3]chart.ResourceSpan{
        chart.ResourceSpan { start: 2.0f64, end: 7.0f64, units: 3.0f64 },
        chart.ResourceSpan { start: 6.0f64, end: 10.0f64, units: 1.0f64 },
        chart.ResourceSpan { start: 0.0f64, end: 4.0f64, units: 2.0f64 },
    }
    let bounds = geometry.rect(10.0, 20.0, 100.0, 100.0)
    var edges: [8]f64 = zero
    var loads: [7]f64 = zero
    var normal_bars: [7]geometry.Rect = zero
    var excess_bars: [7]geometry.Rect = zero
    var capacity_rule: [1]chart.Segment = zero
    let (normal, excess, limit, result) = chart.resource_histogram(spans[..], 0.0f64, 10.0f64, 4.0f64, bounds, edges[..], loads[..], normal_bars[..], excess_bars[..], capacity_rule[..])
    if result != ok || normal.kind != .Bar || excess.kind != .Bar || limit.kind != .Rug || normal.bars.len != 5usize || excess.bars.len != 5usize || limit.segments.len != 1usize { ret chart.Invalid }
    if !near(normal.y_max, 5.0) || !near(f32(edges[0usize]), 0.0) || !near(f32(edges[1usize]), 2.0) || !near(f32(edges[2usize]), 4.0) || !near(f32(edges[3usize]), 6.0) || !near(f32(edges[4usize]), 7.0) || !near(f32(edges[5usize]), 10.0) { ret chart.Invalid }
    if !near(f32(loads[0usize]), 2.0) || !near(f32(loads[1usize]), 5.0) || !near(f32(loads[2usize]), 3.0) || !near(f32(loads[3usize]), 4.0) || !near(f32(loads[4usize]), 1.0) { ret chart.Invalid }
    if !near(normal_bars[0usize].x, 10.0) || !near(normal_bars[0usize].height, 40.0) || !near(normal_bars[1usize].x, 30.0) || !near(normal_bars[1usize].height, 80.0) || !near(excess_bars[1usize].y, 20.0) || !near(excess_bars[1usize].height, 20.0) || !near(excess_bars[0usize].height, 0.0) || !near(limit.segments[0usize].from.y, 40.0) { ret chart.Invalid }
    let blue = paint.rgba(0.2, 0.4, 0.8, 1.0)
    let red = paint.rgba(0.9, 0.3, 0.2, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &normal, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &excess, paint.Brush { Solid: red })
    try chart_scene.append(a, &builder, &limit, paint.Brush { Solid: red })
    if scene.builder_count(&builder) != 7usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 130.0, "Resource histogram", "Load and capacity")
    try chart_svg.append(&writer, &normal, blue)
    try chart_svg.append(&writer, &excess, red)
    try chart_svg.append(&writer, &limit, red)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "<line") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let invalid = [1]chart.ResourceSpan{ chart.ResourceSpan { start: 4.0f64, end: 2.0f64, units: 1.0f64 } }
    let gap_spans = [2]chart.ResourceSpan{
        chart.ResourceSpan { start: 0.0f64, end: 2.0f64, units: 1.0f64 },
        chart.ResourceSpan { start: 4.0f64, end: 6.0f64, units: 1.0f64 },
    }
    let (_, _, _, empty_error) = chart.resource_histogram(spans[..0usize], 0.0f64, 10.0f64, 4.0f64, bounds, edges[..], loads[..], normal_bars[..], excess_bars[..], capacity_rule[..])
    let (_, _, _, span_error) = chart.resource_histogram(invalid[..], 0.0f64, 10.0f64, 4.0f64, bounds, edges[..], loads[..], normal_bars[..], excess_bars[..], capacity_rule[..])
    let (_, _, _, capacity_error) = chart.resource_histogram(spans[..], 0.0f64, 10.0f64, 0.0f64, bounds, edges[..], loads[..], normal_bars[..], excess_bars[..], capacity_rule[..])
    let (_, _, _, storage_error) = chart.resource_histogram(spans[..], 0.0f64, 10.0f64, 4.0f64, bounds, edges[..7usize], loads[..], normal_bars[..], excess_bars[..], capacity_rule[..])
    if empty_error != chart.Empty || span_error != chart.Invalid || capacity_error != chart.Invalid || storage_error != chart.TooLarge { ret chart.Invalid }
    let (gap_normal, gap_excess, gap_limit, gap_error) = chart.resource_histogram(gap_spans[..], 0.0f64, 6.0f64, 2.0f64, bounds, edges[..], loads[..], normal_bars[..], excess_bars[..], capacity_rule[..])
    if gap_error != ok || gap_normal.bars.len != 3usize || gap_excess.bars.len != 3usize || gap_limit.segments.len != 1usize || !near(f32(loads[1usize]), 0.0) { ret chart.Invalid }
    try io.print("gfx chart resource histogram ok\n")
    ret ok
}
