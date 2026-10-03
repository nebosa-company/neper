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
    let prices = [5]f32{ 100.0, 110.0, 99.0, 108.9, 108.9 }
    var returns: [4]f32 = zero
    var volatility: [3]f32 = zero
    var return_segments: [3]chart.Segment = zero
    var volatility_segments: [2]chart.Segment = zero
    let bounds = geometry.rect(0.0, 0.0, 120.0, 100.0)
    let (return_marks, volatility_marks, chart_error) = chart.returns_volatility(x[..], prices[..], 2usize, bounds, 10.0, returns[..], volatility[..], return_segments[..], volatility_segments[..])
    if chart_error != ok || return_marks.kind != .Line || volatility_marks.kind != .Line || return_marks.segments.len != 3usize || volatility_marks.segments.len != 2usize { ret chart.Invalid }
    if !near(returns[0usize], 0.1) || !near(returns[1usize], -0.1) || !near(returns[2usize], 0.1) || !near(returns[3usize], 0.0) { ret chart.Invalid }
    if !near(volatility[0usize], 0.141421) || !near(volatility[1usize], 0.141421) || !near(volatility[2usize], 0.070711) { ret chart.Invalid }
    if !near(return_marks.y_min, -0.1) || !near(return_marks.y_max, 0.1) || !near(volatility_marks.y_min, 0.0) || !near(volatility_marks.y_max, 0.141421) { ret chart.Invalid }
    if !near(return_marks.x_min, 0.0) || !near(volatility_marks.x_min, 0.0) || !near(return_marks.x_max, 4.0) || !near(volatility_marks.x_max, 4.0) { ret chart.Invalid }
    if !near(return_segments[1usize].from.x, volatility_segments[0usize].from.x) { ret chart.Invalid }
    if !near(return_segments[0usize].from.y, 0.0) || !near(return_segments[0usize].to.y, 45.0) || !near(volatility_segments[0usize].from.y, 55.0) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &return_marks, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &volatility_marks, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 100.0, "Returns and volatility", "Unannualized simple returns and rolling sample SD")
    try chart_svg.append(&writer, &return_marks, ink)
    try chart_svg.append(&writer, &volatility_marks, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let flat = [5]f32{ 100.0, 100.0, 100.0, 100.0, 100.0 }
    let (flat_returns, flat_volatility, flat_error) = chart.returns_volatility(x[..], flat[..], 2usize, bounds, 10.0, returns[..], volatility[..], return_segments[..], volatility_segments[..])
    if flat_error != ok || !near(flat_returns.y_min, -0.5) || !near(flat_volatility.y_max, 0.5) { ret chart.Invalid }
    let invalid_prices = [5]f32{ 100.0, 110.0, 0.0, 108.9, 108.9 }
    let invalid_x = [5]f32{ 0.0, 1.0, 1.0, 3.0, 4.0 }
    let (_, _, window_error) = chart.returns_volatility(x[..], prices[..], 4usize, bounds, 10.0, returns[..], volatility[..], return_segments[..], volatility_segments[..])
    let (_, _, price_error) = chart.returns_volatility(x[..], invalid_prices[..], 2usize, bounds, 10.0, returns[..], volatility[..], return_segments[..], volatility_segments[..])
    let (_, _, order_error) = chart.returns_volatility(invalid_x[..], prices[..], 2usize, bounds, 10.0, returns[..], volatility[..], return_segments[..], volatility_segments[..])
    let (_, _, capacity_error) = chart.returns_volatility(x[..], prices[..], 2usize, bounds, 10.0, returns[..], volatility[..2usize], return_segments[..], volatility_segments[..])
    if window_error != chart.Invalid || price_error != chart.Invalid || order_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart returns volatility ok\n")
    ret ok
}
