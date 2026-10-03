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
    let d = a - b
    ret d > -0.001f64 && d < 0.001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [5]f64{ 0.0, 1.0, 2.0, 3.0, 4.0 }
    let y = [5]f64{ 1.0, 2.0, 3.0, 4.0, 7.0 }
    var values: [5]stat.RegressionDiagnostic = zero
    if stat.regression_diagnostics(x[..], y[..], values[..]) != ok { ret stat.Invalid }
    if !near(values[0usize].fitted, 0.6) || !near(values[0usize].residual, 0.4) || !near(values[0usize].leverage, 0.6) || !near(values[0usize].cook, 0.5625) || !near(values[4usize].fitted, 6.2) || !near(values[4usize].standardized, 1.7320508) || !near(values[4usize].cook, 2.25) { ret stat.Invalid }
    if stat.regression_diagnostics(x[..], y[..], values[..4usize]) != stat.TooSmall { ret stat.Invalid }
    let flat_x = [5]f64{ 1.0, 1.0, 1.0, 1.0, 1.0 }
    if stat.regression_diagnostics(flat_x[..], y[..], values[..]) != stat.Invalid { ret stat.Invalid }
    let exact_y = [5]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 }
    if stat.regression_diagnostics(x[..], exact_y[..], values[..]) != stat.Invalid { ret stat.Invalid }
    let bad_y = [5]f64{ 1.0, 2.0, 3.0, 4.0, 0.0 / 0.0 }
    if stat.regression_diagnostics(x[..], bad_y[..], values[..]) != stat.Invalid { ret stat.Invalid }
    let positions = [5]f32{ 1.0, 2.0, 3.0, 4.0, 5.0 }
    let cooks = [5]f32{ 0.5625, 0.0, 0.075, 0.5625, 2.25 }
    var spec = chart.spec(.Lollipop, geometry.rect(30.0, 20.0, 200.0, 100.0), positions[..], cooks[..])
    var points: [5]chart.Coord = zero
    var segments: [5]chart.Segment = zero
    let (marks, layout_error) = chart.layout(&spec, points[..], segments[..], zero)
    if layout_error != ok || marks.coords.len != 5usize || marks.segments.len != 5usize { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 20usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: blue })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 260.0, 160.0, "Cook's distance", "OLS influence")
    try chart_svg.append(&writer, &marks, blue)
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<line") || !str.contains(io.memory_bytes(&held), "</svg>") { ret chart.Invalid }
    try io.print("gfx chart regression diagnostics ok\n")
    ret ok
}
