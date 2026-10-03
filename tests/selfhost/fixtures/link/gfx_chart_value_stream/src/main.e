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
    let delta = a - b
    ret delta > -0.000001f64 && delta < 0.000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let steps = [3]chart.ValueStreamStep{
        chart.ValueStreamStep { process_time: 2.0f64, value_added_time: 1.0f64, wait_before: 0.0f64, good_fraction: 0.98f64 },
        chart.ValueStreamStep { process_time: 5.0f64, value_added_time: 4.0f64, wait_before: 4.0f64, good_fraction: 0.95f64 },
        chart.ValueStreamStep { process_time: 3.0f64, value_added_time: 2.0f64, wait_before: 2.0f64, good_fraction: 0.99f64 },
    }
    let bounds = geometry.rect(0.0, 0.0, 320.0, 160.0)
    var boxes: [3]geometry.Rect = zero
    var arrows: [6]chart.Segment = zero
    var process_bars: [3]geometry.Rect = zero
    var wait_bars: [3]geometry.Rect = zero
    let (map, result) = chart.value_stream_map(steps[..], bounds, boxes[..], arrows[..], process_bars[..], wait_bars[..])
    if result != ok || map.nodes.bars.len != 3usize || map.connectors.segments.len != 6usize || map.process.bars.len != 3usize || map.waiting.bars.len != 2usize { ret chart.Invalid }
    if !near(map.summary.process_time, 10.0f64) || !near(map.summary.value_added_time, 7.0f64) || !near(map.summary.wait_time, 6.0f64) || !near(map.summary.lead_time, 16.0f64) || !near(map.summary.process_cycle_efficiency, 0.4375f64) || !near(map.summary.rolled_yield, 0.92169f64) { ret chart.Invalid }
    if !near(f64(process_bars[0usize].width), 40.0f64) || !near(f64(wait_bars[0usize].width), 80.0f64) || !near(f64(process_bars[1usize].x), 120.0f64) || !near(f64(wait_bars[1usize].x), 220.0f64) || !near(f64(process_bars[2usize].x), 260.0f64) || !near(f64(process_bars[2usize].width), 60.0f64) { ret chart.Invalid }
    if boxes[0usize].x >= boxes[1usize].x || boxes[1usize].x >= boxes[2usize].x || arrows[0usize].to.x != boxes[1usize].x { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.nodes, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.connectors, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.process, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &map.waiting, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 14usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 320.0, 160.0, "Value stream", "Lead and value-added time")
    try chart_svg.append(&writer, &map.nodes, ink)
    try chart_svg.append(&writer, &map.connectors, ink)
    try chart_svg.append(&writer, &map.process, ink)
    try chart_svg.append(&writer, &map.waiting, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad_wait = [1]chart.ValueStreamStep{ chart.ValueStreamStep { process_time: 1.0f64, value_added_time: 1.0f64, wait_before: -1.0f64, good_fraction: 1.0f64 } }
    let bad_value = [1]chart.ValueStreamStep{ chart.ValueStreamStep { process_time: 1.0f64, value_added_time: 2.0f64, wait_before: 0.0f64, good_fraction: 1.0f64 } }
    let bad_yield = [1]chart.ValueStreamStep{ chart.ValueStreamStep { process_time: 1.0f64, value_added_time: 1.0f64, wait_before: 0.0f64, good_fraction: 1.1f64 } }
    let zero_time = [1]chart.ValueStreamStep{ chart.ValueStreamStep { process_time: 0.0f64, value_added_time: 0.0f64, wait_before: 0.0f64, good_fraction: 1.0f64 } }
    let (_, empty_error) = chart.value_stream_map(steps[..0usize], bounds, boxes[..], arrows[..], process_bars[..], wait_bars[..])
    let (_, wait_error) = chart.value_stream_map(bad_wait[..], bounds, boxes[..], arrows[..], process_bars[..], wait_bars[..])
    let (_, value_error) = chart.value_stream_map(bad_value[..], bounds, boxes[..], arrows[..], process_bars[..], wait_bars[..])
    let (_, yield_error) = chart.value_stream_map(bad_yield[..], bounds, boxes[..], arrows[..], process_bars[..], wait_bars[..])
    let (_, zero_error) = chart.value_stream_map(zero_time[..], bounds, boxes[..], arrows[..], process_bars[..], wait_bars[..])
    let (_, bounds_error) = chart.value_stream_map(steps[..], geometry.rect(0.0, 0.0, -1.0, 160.0), boxes[..], arrows[..], process_bars[..], wait_bars[..])
    let (_, box_error) = chart.value_stream_map(steps[..], bounds, boxes[..2usize], arrows[..], process_bars[..], wait_bars[..])
    let (_, arrow_error) = chart.value_stream_map(steps[..], bounds, boxes[..], arrows[..5usize], process_bars[..], wait_bars[..])
    let (_, time_error) = chart.value_stream_map(steps[..], bounds, boxes[..], arrows[..], process_bars[..2usize], wait_bars[..])
    if empty_error != chart.Empty || wait_error != chart.Invalid || value_error != chart.Invalid || yield_error != chart.Invalid || zero_error != chart.Invalid || bounds_error != chart.Invalid || box_error != chart.TooLarge || arrow_error != chart.TooLarge || time_error != chart.TooLarge { ret chart.Invalid }
    let (single, single_error) = chart.value_stream_map(steps[..1usize], bounds, boxes[..1usize], arrows[..0usize], process_bars[..1usize], wait_bars[..1usize])
    if single_error != ok || single.connectors.segments.len != 0usize || single.waiting.bars.len != 0usize || !near(single.summary.process_cycle_efficiency, 0.5f64) { ret chart.Invalid }
    try io.print("gfx chart value stream ok\n")
    ret ok
}
