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
    let x = [4]f32{ 1.0, 2.0, 4.0, 7.0 }
    let prices = [4]f32{ 10.0, 12.0, 9.0, 13.0 }
    let volumes = [4]f32{ 100.0, 250.0, 0.0, 180.0 }
    var lines: [3]chart.Segment = zero
    var bars: [4]geometry.Rect = zero
    let bounds = geometry.rect(0.0, 0.0, 120.0, 100.0)
    let (price, volume, chart_error) = chart.price_volume(x[..], prices[..], volumes[..], bounds, 10.0, lines[..], bars[..])
    if chart_error != ok || price.kind != .Line || volume.kind != .Bar || price.segments.len != 3usize || volume.bars.len != 4usize { ret chart.Invalid }
    if !near(price.x_min, 0.5) || !near(price.x_max, 7.5) || !near(price.x_min, volume.x_min) || !near(price.x_max, volume.x_max) || !near(volume.y_min, 0.0) || !near(volume.y_max, 250.0) { ret chart.Invalid }
    if !near(lines[0usize].from.x, bars[0usize].x + bars[0usize].width * 0.5) || !near(bars[2usize].height, 0.0) || !(bars[1usize].height > bars[0usize].height) || !(bars[0usize].y > lines[0usize].from.y) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &price, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &volume, paint.Brush { Solid: ink })
    if scene.builder_count(&builder) == 0usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 100.0, "Price and volume", "Aligned numeric x positions")
    try chart_svg.append(&writer, &price, ink)
    try chart_svg.append(&writer, &volume, ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let bad_price = [4]f32{ 10.0, 0.0, 9.0, 13.0 }
    let bad_volume = [4]f32{ 100.0, -1.0, 0.0, 180.0 }
    let bad_x = [4]f32{ 1.0, 2.0, 2.0, 7.0 }
    let (_, _, price_error) = chart.price_volume(x[..], bad_price[..], volumes[..], bounds, 10.0, lines[..], bars[..])
    let (_, _, volume_error) = chart.price_volume(x[..], prices[..], bad_volume[..], bounds, 10.0, lines[..], bars[..])
    let (_, _, order_error) = chart.price_volume(bad_x[..], prices[..], volumes[..], bounds, 10.0, lines[..], bars[..])
    let (_, _, gap_error) = chart.price_volume(x[..], prices[..], volumes[..], bounds, 100.0, lines[..], bars[..])
    let (_, _, capacity_error) = chart.price_volume(x[..], prices[..], volumes[..], bounds, 10.0, lines[..2usize], bars[..])
    if price_error != chart.Invalid || volume_error != chart.Invalid || order_error != chart.Invalid || gap_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart price volume ok\n")
    ret ok
}
