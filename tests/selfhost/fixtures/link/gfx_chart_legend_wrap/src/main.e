use e.gfx.chart
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn near(a: f32, b: f32) -> bool { ret a - b < 0.001f32 && b - a < 0.001f32 }

fn main(a: *mem.Arena, args: []str) -> err {
    let names = [3]str{ "Baseline", "Treatment A", "Treatment B" }
    let widths = [3]f32{ 37.0, 59.0, 59.0 }
    let bounds = geometry.rect(20.0, 150.0, 200.0, 50.0)
    var items: [3]chart.LegendItem = zero
    let (legend, legend_error) = chart.wrapped_legend_items(names[..], widths[..], bounds, 10.0, 8.0, 20.0, items[..])
    if legend_error != ok || legend.rows != 2usize || legend.items.len != 3usize { ret chart.Invalid }
    if !near(items[0usize].swatch.x, 20.0) || !near(items[1usize].swatch.x, 80.0) || !near(items[2usize].swatch.x, 20.0) || !near(items[0usize].swatch.y, 155.0) || !near(items[2usize].swatch.y, 175.0) || !near(items[1usize].label.anchor.x, 95.0) { ret chart.Invalid }
    if items[0usize].label.anchor.x + widths[0usize] + 8.0 > items[1usize].swatch.x || items[1usize].label.anchor.x + widths[1usize] > bounds.x + bounds.width { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 16usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    var i = 0usize
    while i < legend.items.len {
        try scene.push(&builder, scene.Command { FillRect: scene.FillRect { rect: legend.items[i].swatch, brush: paint.Brush { Solid: blue } } })
        i += 1usize
    }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 360.0f32, 240.0f32, "Wrapped legend", "Bounded legend rows")
    i = 0usize
    while i < legend.items.len {
        try chart_svg.rect(&writer, legend.items[i].swatch, blue, false)
        let one = [1]chart.Label{ legend.items[i].label }
        try chart_svg.append_labels(&writer, one[..], blue, 9.0)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "Treatment A") { ret chart.Invalid }
    let (_, short_error) = chart.wrapped_legend_items(names[..], widths[..], bounds, 10.0, 8.0, 20.0, items[..2usize])
    let (_, height_error) = chart.wrapped_legend_items(names[..], widths[..], geometry.rect(20.0, 150.0, 200.0, 20.0), 10.0, 8.0, 20.0, items[..])
    let (_, width_error) = chart.wrapped_legend_items(names[..], widths[..], geometry.rect(20.0, 150.0, 40.0, 50.0), 10.0, 8.0, 20.0, items[..])
    let bad_widths = [3]f32{ 37.0, 0.0, 59.0 }
    let (_, measure_error) = chart.wrapped_legend_items(names[..], bad_widths[..], bounds, 10.0, 8.0, 20.0, items[..])
    let bad_names = [3]str{ "Baseline", "", "Treatment B" }
    let (_, label_error) = chart.wrapped_legend_items(bad_names[..], widths[..], bounds, 10.0, 8.0, 20.0, items[..])
    if short_error != chart.TooLarge || height_error != chart.TooLarge || width_error != chart.TooLarge || measure_error != chart.Invalid || label_error != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart legend wrap ok\n")
    ret ok
}
