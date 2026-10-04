use e.algo.stat
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
    ret delta > -0.00000001f64 && delta < 0.00000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [1]f64{ 0.0f64 }
    let y = [1]f64{ 0.0f64 }
    let domain_x = [3]f64{ -1.0f64, 0.0f64, 1.0f64 }
    let domain_y = [3]f64{ 1.0f64, 0.0f64, -1.0f64 }
    var reference: [9]f64 = zero
    let stat_error = stat.kde2d(x[..], y[..], 1.0f64, 1.0f64, domain_x[..], domain_y[..], reference[..])
    let peak = 0.15915494309189535f64
    if stat_error != ok || !near(reference[4usize], peak) || !near(reference[0usize], peak * 0.36787944117144233f64) || !near(reference[1usize], peak * 0.6065306597126334f64) || !near(reference[7usize], reference[1usize]) { ret chart.Invalid }
    let short_error = stat.kde2d(x[..], y[..], 1.0f64, 1.0f64, domain_x[..], domain_y[..], reference[..8usize])
    let bad_bandwidth = stat.kde2d(x[..], y[..], 0.0f64, 1.0f64, domain_x[..], domain_y[..], reference[..])
    if short_error != stat.TooSmall || bad_bandwidth != stat.Invalid { ret chart.Invalid }
    let bounds = geometry.rect(10.0, 20.0, 100.0, 100.0)
    let fractions = [1]f64{ 0.75f64 }
    var grid_x: [3]f64 = zero
    var grid_y: [3]f64 = zero
    var values: [9]f64 = zero
    var cutoffs: [2]f64 = zero
    var segments: [16]chart.Segment = zero
    var layers: [2]chart.Layout = zero
    let (density, result) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    if result != ok || density.contours.len != 1usize || density.grid.len != 9usize || density.cutoffs.len != 1usize || density.contours[0usize].kind != .Rug || density.contours[0usize].segments.len != 4usize { ret chart.Invalid }
    if !near(density.peak, peak) || !near(density.cutoffs[0usize], peak * 0.75f64) || !near(grid_x[0usize], -1.0f64) || !near(grid_x[2usize], 1.0f64) || !near(grid_y[0usize], 1.0f64) || !near(grid_y[2usize], -1.0f64) { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &density.contours[0usize], paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 120.0, 140.0, "2D density", "Gaussian KDE contours")
    try chart_svg.append(&writer, &density.contours[0usize], ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let outside = [1]f64{ 2.0f64 }
    let invalid_fractions = [2]f64{ 0.75f64, 0.50f64 }
    let zero_fraction = [1]f64{ 0.0f64 }
    let (_, empty_error) = chart.density2d(x[..0usize], y[..0usize], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    let (_, levels_empty_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..0usize], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    let (_, mismatch_error) = chart.density2d(x[..], y[..0usize], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    let (_, outside_error) = chart.density2d(outside[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    let (_, bandwidth_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, -1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    let (_, order_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, invalid_fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    let (_, level_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, zero_fraction[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    let (_, grid_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..1usize], grid_y[..], values[..], cutoffs[..], segments[..], layers[..])
    let (_, values_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..8usize], cutoffs[..], segments[..], layers[..])
    let (_, cutoffs_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..0usize], segments[..], layers[..])
    let (_, segments_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..1usize], layers[..])
    let (_, layers_error) = chart.density2d(x[..], y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, bounds, 1.0f64, 1.0f64, fractions[..], grid_x[..], grid_y[..], values[..], cutoffs[..], segments[..], layers[..0usize])
    if empty_error != chart.Empty || levels_empty_error != chart.Empty || mismatch_error != chart.Invalid || outside_error != chart.Invalid || bandwidth_error != chart.Invalid || order_error != chart.Invalid || level_error != chart.Invalid || grid_error != chart.Invalid || values_error != chart.TooLarge || cutoffs_error != chart.TooLarge || segments_error != chart.TooLarge || layers_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart density2d ok\n")
    ret ok
}
