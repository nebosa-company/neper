use e.gfx.chart
use e.gfx.geometry
use e.io
use e.mem

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d < 0.01 && d > -0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [2]f32{ 0.0, 1.0 }
    let common = [2]f32{ 0.0, 2.0 }
    let bad = [2]f32{ 0.25, 2.0 }
    let backwards = [2]f32{ 2.0, 0.0 }
    var points: [2]chart.Coord = zero
    var lines: [1]chart.Segment = zero
    var bars: [2]geometry.Rect = zero
    var panels: [2]geometry.Rect = zero
    let (placed, panel_error) = chart.facet_grid(geometry.rect(0.0, 0.0, 210.0, 100.0), 2usize, 2usize, 10.0, panels[..])
    if panel_error != ok || !near(placed[1].x, 110.0) || !near(placed[1].width, 100.0) { ret chart.Invalid }
    var plot = chart.spec(.Scatter, placed[0], values[..], values[..])
    let (free_plot, free_error) = chart.layout(&plot, points[..], lines[..], bars[..])
    if free_error != ok || !near(free_plot.coords[1].x, 100.0) || !near(free_plot.coords[1].y, 0.0) { ret chart.Invalid }
    let (shared_plot, shared_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], common[..], common[..])
    if shared_error != ok || !near(shared_plot.coords[1].x, 50.0) || !near(shared_plot.coords[1].y, 50.0) || !near(shared_plot.x_max, 2.0) { ret chart.Invalid }
    let (free_x, free_x_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], values[..0usize], common[..])
    if free_x_error != ok || !near(free_x.coords[1].x, 100.0) || !near(free_x.coords[1].y, 50.0) { ret chart.Invalid }
    let (free_y, free_y_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], common[..], values[..0usize])
    if free_y_error != ok || !near(free_y.coords[1].x, 50.0) || !near(free_y.coords[1].y, 0.0) { ret chart.Invalid }
    let (_, excluded_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], bad[..], common[..])
    if excluded_error != chart.Invalid { ret chart.Invalid }
    let (_, reversed_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], backwards[..], common[..])
    if reversed_error != chart.Invalid { ret chart.Invalid }
    let (_, short_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], values[..1usize], common[..])
    if short_error != chart.Invalid { ret chart.Invalid }
    plot.x_scale.kind = .Log10
    let (_, log_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], common[..], common[..])
    if log_error != chart.Invalid { ret chart.Invalid }
    let constant = [2]f32{ 1.0, 1.0 }
    plot = chart.spec(.Scatter, placed[0], constant[..], constant[..])
    let (constant_plot, constant_error) = chart.layout_with_limits(&plot, points[..], lines[..], bars[..], common[..], common[..])
    if constant_error != ok || !near(constant_plot.coords[0].x, 50.0) || !near(constant_plot.coords[0].y, 50.0) { ret chart.Invalid }
    try io.print("gfx chart facet ok\n")
    ret ok
}
