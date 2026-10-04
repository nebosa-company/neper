use e.gfx.chart
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn same(a: paint.Color, b: paint.Color) -> bool { ret a.red == b.red && a.green == b.green && a.blue == b.blue && a.alpha == b.alpha }

// Every color clears 4.5:1 on the bytes the adapters write.
fn readable(background: paint.Color, colors: []paint.Color) -> bool {
    var i = 0usize
    while i < colors.len {
        if !paint.color_ok(colors[i]) || colors[i].alpha != 1.0 { ret false }
        let (ratio, ratio_error) = chart.rendered_contrast_ratio(colors[i], background)
        if ratio_error != ok || ratio < 4.5f64 { ret false }
        i += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    let white = paint.rgba(1.0, 1.0, 1.0, 1.0)
    let black = paint.rgba(0.0, 0.0, 0.0, 1.0)
    let gray = paint.rgba(0.46, 0.46, 0.46, 1.0)
    let (extremes, extremes_error) = chart.rendered_contrast_ratio(white, black)
    if extremes_error != ok || extremes < 20.99f64 || extremes > 21.01f64 { ret chart.Invalid }
    var on_white: [6]paint.Color = zero
    let (light, light_error) = chart.accessible_palette(white, on_white[..])
    if light_error != ok || light.len != 6usize { ret chart.Invalid }
    // Blue already passes on white and stays; vermillion fails and darkens only to the threshold.
    if !same(light[0usize], paint.rgba(0.0, 114.0 / 255.0, 178.0 / 255.0, 1.0)) || light[1usize].red >= 213.0 / 255.0 { ret chart.Invalid }
    let (adjusted, adjusted_error) = chart.rendered_contrast_ratio(light[1usize], white)
    if !readable(white, light) || adjusted_error != ok || adjusted >= 4.65f64 { ret chart.Invalid }
    var on_black: [6]paint.Color = zero
    let (dark, dark_error) = chart.accessible_palette(black, on_black[..])
    if dark_error != ok || dark.len != 6usize || dark[0usize].blue <= 178.0 / 255.0 || dark[0usize].red <= 0.0 || !readable(black, dark) { ret chart.Invalid }
    // Mid-gray is the hardest background: neither black nor white reaches 5:1.
    var on_gray: [7]paint.Color = zero
    let (middle, middle_error) = chart.accessible_palette(gray, on_gray[..])
    if middle_error != ok || middle.len != 6usize || !readable(gray, middle) { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 40.0, "Accessible palette", "Six series colors on white")
    var i = 0usize
    while i < light.len {
        let swatch = geometry.rect(4.0 + f32(i) * 19.0, 10.0, 16.0, 16.0)
        try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: swatch, brush: paint.Brush { Solid: light[i] } } })
        try chart_svg.rect(&writer, swatch, light[i], false)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let output = io.memory_bytes(&held)
    if scene.builder_count(&builder) != 6usize || !str.contains(output, "fill=\"rgb(0,114,178)\"") || !str.contains(output, "</svg>") { ret chart.Invalid }
    let (_, short_error) = chart.accessible_palette(white, on_white[..5usize])
    let (_, clear_error) = chart.accessible_palette(paint.rgba(1.0, 1.0, 1.0, 0.5), on_white[..])
    let (_, range_error) = chart.accessible_palette(paint.rgba(1.5, 1.0, 1.0, 1.0), on_white[..])
    let (_, ratio_error) = chart.rendered_contrast_ratio(paint.rgba(0.0, 0.0, 0.0, 0.25), white)
    if short_error != chart.TooLarge || clear_error != chart.Invalid || range_error != chart.Invalid || ratio_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart accessible palette ok\n")
    ret ok
}
