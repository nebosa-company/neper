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
    ret d > -0.01 && d < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [6]f32{ 2.0, 10.0, 4.0, 12.0, 6.0, 14.0 }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    var segments: [4]chart.Segment = zero
    var means: [2]chart.Segment = zero
    var storage: [2]chart.Layout = zero
    let (layers, baselines, layout_error) = chart.seasonal_subseries(values[..], 2usize, bounds, segments[..], means[..], storage[..])
    if layout_error != ok || layers.len != 2usize || layers[0usize].segments.len != 2usize || layers[1usize].segments.len != 2usize || baselines.segments.len != 2usize { ret chart.Invalid }
    if !near(layers[0usize].segments[0usize].from.x, 5.0) || !near(layers[0usize].segments[0usize].to.x, 25.0) || !near(layers[1usize].segments[1usize].to.x, 95.0) || !near(baselines.segments[0usize].from.y, 83.33333) || !near(baselines.segments[1usize].from.y, 16.66667) { ret chart.Invalid }
    let ragged = [5]f32{ 2.0, 10.0, 4.0, 12.0, 6.0 }
    let (partial, partial_means, partial_error) = chart.seasonal_subseries(ragged[..], 2usize, bounds, segments[..], means[..], storage[..])
    if partial_error != ok || partial[0usize].segments.len != 2usize || partial[1usize].segments.len != 1usize || !near(partial_means.segments[1usize].from.y, 10.0) { ret chart.Invalid }
    let flat = [4]f32{ 7.0, 7.0, 7.0, 7.0 }
    let (_, flat_means, flat_error) = chart.seasonal_subseries(flat[..], 2usize, bounds, segments[..], means[..], storage[..])
    if flat_error != ok || !near(flat_means.segments[0usize].from.y, 50.0) { ret chart.Invalid }
    let (_, _, invalid_period) = chart.seasonal_subseries(values[..], 0usize, bounds, segments[..], means[..], storage[..])
    let (_, _, short_series) = chart.seasonal_subseries(values[..2usize], 2usize, bounds, segments[..], means[..], storage[..])
    let (_, _, short_storage) = chart.seasonal_subseries(values[..], 2usize, bounds, segments[..2usize], means[..], storage[..])
    if invalid_period != chart.Invalid || short_series != chart.Invalid || short_storage != chart.TooLarge { ret chart.Invalid }
    let (again, again_means, again_error) = chart.seasonal_subseries(values[..], 2usize, bounds, segments[..], means[..], storage[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    let red = paint.rgba(0.85, 0.25, 0.3, 1.0)
    var i = 0usize
    while i < again.len {
        try chart_scene.append(a, &builder, &again[i], paint.Brush { Solid: blue })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &again_means, paint.Brush { Solid: red })
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Seasonal subseries", "Seasonal traces and means")
    i = 0usize
    while i < again.len {
        try chart_svg.append(&writer, &again[i], blue)
        i += 1usize
    }
    try chart_svg.append(&writer, &again_means, red)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart seasonal ok\n")
    ret ok
}
