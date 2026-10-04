use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f64, b: f64) -> bool { ret a - b < 0.00001f64 && b - a < 0.00001f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let current = [3]chart.ValueStreamStep{
        chart.ValueStreamStep { process_time: 2.0f64, value_added_time: 1.0f64, wait_before: 0.0f64, good_fraction: 0.98f64 },
        chart.ValueStreamStep { process_time: 5.0f64, value_added_time: 4.0f64, wait_before: 4.0f64, good_fraction: 0.95f64 },
        chart.ValueStreamStep { process_time: 3.0f64, value_added_time: 2.0f64, wait_before: 2.0f64, good_fraction: 0.99f64 },
    }
    let future = [3]chart.ValueStreamStep{
        chart.ValueStreamStep { process_time: 2.0f64, value_added_time: 1.5f64, wait_before: 0.0f64, good_fraction: 0.99f64 },
        chart.ValueStreamStep { process_time: 4.2f64, value_added_time: 3.5f64, wait_before: 1.0f64, good_fraction: 0.98f64 },
        chart.ValueStreamStep { process_time: 2.5f64, value_added_time: 2.0f64, wait_before: 0.5f64, good_fraction: 0.995f64 },
    }
    let links = [2]chart.ValueStreamFlow{ .Pull, .Fifo }
    var current_boxes: [3]geometry.Rect = zero
    var current_arrows: [6]chart.Segment = zero
    var current_process: [3]geometry.Rect = zero
    var current_wait: [3]geometry.Rect = zero
    var future_boxes: [3]geometry.Rect = zero
    var future_arrows: [6]chart.Segment = zero
    var future_process: [3]geometry.Rect = zero
    var future_wait: [3]geometry.Rect = zero
    var fifo: [2]geometry.Rect = zero
    var pull: [2]geometry.Rect = zero
    var over: [3]geometry.Rect = zero
    var pace: [1]geometry.Rect = zero
    var work = chart.FutureValueStreamWork {
        current: chart.ValueStreamWork { boxes: current_boxes[..], arrows: current_arrows[..], process_bars: current_process[..], wait_bars: current_wait[..] },
        future: chart.ValueStreamWork { boxes: future_boxes[..], arrows: future_arrows[..], process_bars: future_process[..], wait_bars: future_wait[..] },
        fifo_cues: fifo[..], pull_cues: pull[..], over_takt: over[..], pacemaker: pace[..],
    }
    let current_bounds = geometry.rect(18.0, 38.0, 324.0, 80.0)
    let future_bounds = geometry.rect(18.0, 130.0, 324.0, 80.0)
    let (map, result) = chart.future_value_stream_map(current[..], future[..], links[..], 8.0f64, 2.0f64, 1usize, current_bounds, future_bounds, &work)
    if result != ok || !near(map.takt_time, 4.0f64) || !near(map.current.summary.lead_time, 16.0f64) || !near(map.future.summary.lead_time, 10.2f64) || !near(map.lead_reduction, 5.8f64) || !near(map.future.summary.value_added_time, 7.0f64) || map.fifo.bars.len != 1usize || map.pull.bars.len != 1usize || map.over_takt.bars.len != 1usize || map.pacemaker.bars.len != 1usize { ret chart.Invalid }
    if map.lead_reduction <= 0.0f64 || map.pce_gain <= 0.0f64 || map.yield_gain <= 0.0f64 || !near(f64(map.pacemaker.bars[0usize].x), f64(map.future.nodes.bars[1usize].x)) || !near(f64(map.over_takt.bars[0usize].x), f64(map.future.nodes.bars[1usize].x)) { ret chart.Invalid }
    let blue = paint.rgba(0.16, 0.44, 0.75, 1.0)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.current.nodes, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.future.nodes, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.pull, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.fifo, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.over_takt, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.pacemaker, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Future-state value stream", "Takt and flow controls")
    try chart_svg.append(&writer, &map.current.nodes, blue)
    try chart_svg.append(&writer, &map.future.nodes, blue)
    try chart_svg.append(&writer, &map.pull, blue)
    try chart_svg.append(&writer, &map.fifo, blue)
    try chart_svg.append(&writer, &map.over_takt, blue)
    try chart_svg.append(&writer, &map.pacemaker, blue)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    let push_links = [2]chart.ValueStreamFlow{ .Push, .Push }
    let (push_map, push_error) = chart.future_value_stream_map(current[..], future[..], push_links[..], 8.0f64, 2.0f64, 1usize, current_bounds, future_bounds, &work)
    let (worse_map, worse_error) = chart.future_value_stream_map(future[..], current[..], links[..], 8.0f64, 2.0f64, 1usize, current_bounds, future_bounds, &work)
    if push_error != ok || push_map.pull.bars.len != 0usize || push_map.fifo.bars.len != 0usize || worse_error != ok || !near(worse_map.lead_reduction, -5.8f64) || worse_map.pce_gain >= 0.0f64 { ret chart.Invalid }
    let short_links = [1]chart.ValueStreamFlow{ .Pull }
    let (_, links_error) = chart.future_value_stream_map(current[..], future[..], short_links[..], 8.0f64, 2.0f64, 1usize, current_bounds, future_bounds, &work)
    let (_, demand_error) = chart.future_value_stream_map(current[..], future[..], links[..], 8.0f64, 0.0f64, 1usize, current_bounds, future_bounds, &work)
    let (_, pace_error) = chart.future_value_stream_map(current[..], future[..], links[..], 8.0f64, 2.0f64, 3usize, current_bounds, future_bounds, &work)
    var short_work = work
    short_work.pacemaker = pace[..0usize]
    let (_, storage_error) = chart.future_value_stream_map(current[..], future[..], links[..], 8.0f64, 2.0f64, 1usize, current_bounds, future_bounds, &short_work)
    if links_error != chart.Invalid || demand_error != chart.Invalid || pace_error != chart.Invalid || storage_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart future vsm ok\n")
    ret ok
}
