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
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let x = [4]f32{ 0.0, 1.0, 2.0, 3.0 }
    let y = [4]f32{ 1.0, 3.0, 5.0, 7.0 }
    var fit_segments: [1]chart.Segment = zero
    let (fit, fit_error) = chart.regression_line(x[..], y[..], bounds, fit_segments[..])
    if fit_error != ok || fit.kind != .Line || fit.segments.len != 1usize || !near(fit.segments[0usize].from.x, 0.0) || !near(fit.segments[0usize].from.y, 100.0) || !near(fit.segments[0usize].to.x, 100.0) || !near(fit.segments[0usize].to.y, 0.0) || !near(fit.y_min, 1.0) || !near(fit.y_max, 7.0) { ret chart.Invalid }
    let singular_x = [3]f32{ 1.0, 1.0, 1.0 }
    let singular_y = [3]f32{ 1.0, 2.0, 3.0 }
    let (_, singular_error) = chart.regression_line(singular_x[..], singular_y[..], bounds, fit_segments[..])
    if singular_error != chart.Invalid { ret chart.Invalid }
    let (_, fit_short_error) = chart.regression_line(x[..], y[..], bounds, fit_segments[..0usize])
    if fit_short_error != chart.TooLarge { ret chart.Invalid }
    let flat_y = [4]f32{ 2.0, 2.0, 2.0, 2.0 }
    var flat_segments: [1]chart.Segment = zero
    let (flat, flat_error) = chart.regression_line(x[..], flat_y[..], bounds, flat_segments[..])
    if flat_error != ok || !near(flat.segments[0usize].from.y, 50.0) || !near(flat.segments[0usize].to.y, 50.0) { ret chart.Invalid }
    let ellipse_x = [4]f32{ -1.0, 1.0, 0.0, 0.0 }
    let ellipse_y = [4]f32{ 0.0, 0.0, -1.0, 1.0 }
    var ellipse_segments: [64]chart.Segment = zero
    let (ellipse, ellipse_error) = chart.covariance_ellipse(ellipse_x[..], ellipse_y[..], bounds, 1.0, ellipse_segments[..])
    if ellipse_error != ok || ellipse.kind != .Line || ellipse.segments.len != 64usize || !near(ellipse.segments[0usize].from.x, 90.82) || !near(ellipse.segments[0usize].from.y, 50.0) || !near(ellipse.segments[15usize].to.x, 50.0) || !near(ellipse.segments[15usize].to.y, 9.18) || !near(ellipse.segments[63usize].to.x, ellipse.segments[0usize].from.x) { ret chart.Invalid }
    let diagonal_x = [3]f32{ 0.0, 1.0, 2.0 }
    let diagonal_y = [3]f32{ 0.0, 2.0, 4.0 }
    let (_, diagonal_error) = chart.covariance_ellipse(diagonal_x[..], diagonal_y[..], bounds, 1.0, ellipse_segments[..])
    if diagonal_error != chart.Invalid { ret chart.Invalid }
    let (_, ellipse_short_error) = chart.covariance_ellipse(ellipse_x[..], ellipse_y[..], bounds, 1.0, ellipse_segments[..7usize])
    if ellipse_short_error != chart.TooLarge { ret chart.Invalid }
    let (_, radius_error) = chart.covariance_ellipse(ellipse_x[..], ellipse_y[..], bounds, 0.0, ellipse_segments[..])
    if radius_error != chart.Invalid { ret chart.Invalid }
    let tilted_y = [4]f32{ -1.0, 1.0, -1.0, 1.0 }
    let (tilted, tilted_error) = chart.covariance_ellipse(ellipse_x[..], tilted_y[..], bounds, 1.0, ellipse_segments[..])
    if tilted_error != ok || tilted.segments[0usize].from.y >= 50.0 { ret chart.Invalid }
    let (ellipse_again, ellipse_again_error) = chart.covariance_ellipse(ellipse_x[..], ellipse_y[..], bounds, 1.0, ellipse_segments[..])
    if ellipse_again_error != ok { ret ellipse_again_error }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &fit, paint.Brush { Solid: paint.rgba(0.9, 0.4, 0.1, 1.0) })
    try chart_scene.append(a, &builder, &ellipse_again, paint.Brush { Solid: paint.rgba(0.1, 0.3, 0.8, 1.0) })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Overlays", "Regression and covariance ellipse")
    try chart_svg.append(&writer, &fit, paint.rgba(0.9, 0.4, 0.1, 1.0))
    try chart_svg.append(&writer, &ellipse_again, paint.rgba(0.1, 0.3, 0.8, 1.0))
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart overlays ok\n")
    ret ok
}
