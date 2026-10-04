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
    let keys = [5]str{ "North", "East", "North", "West", "South" }
    let values = [5]f64{ 7.0f64, 8.0f64, 5.0f64, 4.0f64, 6.0f64 }
    let levels = [5]str{ "North", "South", "East", "West", "Online" }
    let bounds = geometry.rect(40.0, 40.0, 250.0, 150.0)
    var sums: [5]f64 = zero
    var bars: [5]geometry.Rect = zero
    var ticks: [5]chart.Tick = zero
    let (plot, plot_error) = chart.discrete_axis_bars(keys[..], values[..], levels[..], 15.0f64, bounds, sums[..], bars[..], ticks[..])
    if plot_error != ok || plot.bars.len != 5usize || sums[0usize] != 12.0f64 || sums[1usize] != 6.0f64 || sums[2usize] != 8.0f64 || sums[3usize] != 4.0f64 || sums[4usize] != 0.0f64 { ret chart.Invalid }
    if !near(bars[0usize].height, 120.0) || !near(bars[4usize].height, 0.0) || !near(ticks[0usize].fraction, 0.1) || !near(ticks[4usize].fraction, 0.9) || bars[0usize].x >= bars[1usize].x { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &plot, paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Discrete bars", "Ordered categories")
    try chart_svg.append(&writer, &plot, ink)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") { ret chart.Invalid }
    let (_, short_error) = chart.discrete_axis_bars(keys[..], values[..], levels[..], 15.0f64, bounds, sums[..], bars[..4usize], ticks[..])
    let duplicate = [5]str{ "North", "South", "North", "West", "Online" }
    let (_, duplicate_error) = chart.discrete_axis_bars(keys[..], values[..], duplicate[..], 15.0f64, bounds, sums[..], bars[..], ticks[..])
    let unknown = [5]str{ "North", "East", "North", "Other", "South" }
    let (_, unknown_error) = chart.discrete_axis_bars(unknown[..], values[..], levels[..], 15.0f64, bounds, sums[..], bars[..], ticks[..])
    let negative = [5]f64{ 7.0f64, -8.0f64, 5.0f64, 4.0f64, 6.0f64 }
    let (_, negative_error) = chart.discrete_axis_bars(keys[..], negative[..], levels[..], 15.0f64, bounds, sums[..], bars[..], ticks[..])
    let (_, max_error) = chart.discrete_axis_bars(keys[..], values[..], levels[..], 10.0f64, bounds, sums[..], bars[..], ticks[..])
    if short_error != chart.TooLarge || duplicate_error != chart.Invalid || unknown_error != chart.Invalid || negative_error != chart.Invalid || max_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart discrete axis ok\n")
    ret ok
}
