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
    ret delta > -0.05 && delta < 0.05
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [3]f32{ 1.0, 3.0, 6.0 }
    let opens = [3]f32{ 10.0, 12.0, 14.0 }
    let highs = [3]f32{ 13.0, 15.0, 16.0 }
    let lows = [3]f32{ 9.0, 10.0, 12.0 }
    let closes = [3]f32{ 12.0, 11.0, 14.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    var wicks: [6]chart.Segment = zero
    var rising: [3]geometry.Rect = zero
    var falling: [3]geometry.Rect = zero
    var storage: [3]chart.Layout = zero
    let (candles, candle_error) = chart.candlestick(x[..], opens[..], highs[..], lows[..], closes[..], bounds, 0.6, wicks[..], rising[..], falling[..], storage[..])
    if candle_error != ok || candles.len != 3usize || candles[0usize].kind != .Rug || candles[0usize].segments.len != 4usize || candles[1usize].bars.len != 1usize || candles[2usize].bars.len != 1usize || !near(candles[0usize].x_min, 0.0) || !near(candles[0usize].x_max, 7.0) || !near(candles[0usize].y_min, 9.0) || !near(candles[0usize].y_max, 16.0) || !near(candles[1usize].bars[0usize].height, 28.57) || !near(candles[2usize].bars[0usize].height, 14.29) || !near(candles[0usize].segments[3usize].from.y, 28.57) { ret chart.Invalid }
    var ohlc_lines: [9]chart.Segment = zero
    let (ticks, tick_error) = chart.ohlc(x[..], opens[..], highs[..], lows[..], closes[..], bounds, 0.6, ohlc_lines[..])
    if tick_error != ok || ticks.segments.len != 9usize || !near(ticks.segments[0usize].from.y, 42.86) || !near(ticks.segments[1usize].to.x, 14.29) || !near(ticks.segments[2usize].from.y, 57.14) { ret chart.Invalid }
    let bad_highs = [3]f32{ 11.0, 15.0, 16.0 }
    let (_, high_error) = chart.candlestick(x[..], opens[..], bad_highs[..], lows[..], closes[..], bounds, 0.6, wicks[..], rising[..], falling[..], storage[..])
    if high_error != chart.Invalid { ret chart.Invalid }
    let bad_x = [3]f32{ 1.0, 1.0, 6.0 }
    let (_, x_error) = chart.ohlc(bad_x[..], opens[..], highs[..], lows[..], closes[..], bounds, 0.6, ohlc_lines[..])
    if x_error != chart.Invalid { ret chart.Invalid }
    let (_, short_error) = chart.ohlc(x[..], opens[..], highs[..], lows[..], closes[..], bounds, 0.6, ohlc_lines[..8usize])
    if short_error != chart.TooLarge { ret chart.Invalid }
    let (_, fraction_error) = chart.candlestick(x[..], opens[..], highs[..], lows[..], closes[..], bounds, 1.0, wicks[..], rising[..], falling[..], storage[..])
    if fraction_error != chart.Invalid { ret chart.Invalid }
    let (_, length_error) = chart.candlestick(x[..], opens[..2usize], highs[..], lows[..], closes[..], bounds, 0.6, wicks[..], rising[..], falling[..], storage[..])
    if length_error != chart.Invalid { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let dark = paint.rgba(0.2, 0.2, 0.2, 1.0)
    try chart_scene.append(a, &builder, &candles[0usize], paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &candles[1usize], paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &candles[2usize], paint.Brush { Solid: dark })
    try chart_scene.append(a, &builder, &ticks, paint.Brush { Solid: dark })
    if scene.builder_count(&builder) != 15usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Finance", "Candlestick and OHLC")
    try chart_svg.append(&writer, &candles[0usize], dark)
    try chart_svg.append(&writer, &candles[1usize], dark)
    try chart_svg.append(&writer, &candles[2usize], dark)
    try chart_svg.append(&writer, &ticks, dark)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart finance ok\n")
    ret ok
}
