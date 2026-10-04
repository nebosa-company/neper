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
    ret delta > -0.001 && delta < 0.001
}

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [5]f64{ -2.0, -1.0, 0.0, 1.0, 2.0 }
    var points: [5]chart.Coord = zero
    var reference: [1]chart.Segment = zero
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let (plot, plot_error) = chart.qq_normal(values[..], bounds, points[..], reference[..])
    if plot_error != ok || plot.kind != .Qq || plot.coords.len != 5usize || plot.segments.len != 1usize { ret chart.Invalid }
    if !near(plot.coords[2].x, 50.0) || !near(plot.coords[2].y, 50.0) || !(plot.segments[0].from.x < plot.segments[0].to.x) { ret chart.Invalid }
    let (_, short_error) = chart.qq_normal(values[..], bounds, points[..4usize], reference[..])
    if short_error != chart.TooLarge { ret chart.Invalid }
    let descending = [2]f64{ 2.0, 1.0 }
    let (_, sorted_error) = chart.qq_normal(descending[..], bounds, points[..], reference[..])
    if sorted_error != chart.Invalid { ret chart.Invalid }
    let (pp, pp_error) = chart.pp_normal(values[..], 0.0f64, 1.0f64, bounds, points[..], reference[..])
    if pp_error != ok || pp.kind != .Pp || pp.coords.len != 5usize || pp.segments.len != 1usize || !near(pp.coords[1].x, 15.8655) || !near(pp.coords[1].y, 70.0) || !near(pp.coords[2].x, 50.0) || !near(pp.coords[2].y, 50.0) || !near(pp.segments[0].from.y, 100.0) || !near(pp.segments[0].to.y, 0.0) { ret chart.Invalid }
    let (_, pp_short) = chart.pp_normal(values[..], 0.0f64, 1.0f64, bounds, points[..4usize], reference[..])
    if pp_short != chart.TooLarge { ret chart.Invalid }
    let (_, pp_scale) = chart.pp_normal(values[..], 0.0f64, 0.0f64, bounds, points[..], reference[..])
    if pp_scale != chart.Invalid { ret chart.Invalid }
    let (_, pp_sorted) = chart.pp_normal(descending[..], 0.0f64, 1.0f64, bounds, points[..], reference[..])
    if pp_sorted != chart.Invalid { ret chart.Invalid }
    let boxen_values = [16]f64{ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0 }
    var boxen_tails: [4]chart.Coord = zero
    var boxen_lines: [1]chart.Segment = zero
    var boxen_boxes: [4]geometry.Rect = zero
    let (boxen, boxen_error) = chart.boxen_plot(boxen_values[..], bounds, 3usize, boxen_tails[..], boxen_lines[..], boxen_boxes[..])
    if boxen_error != ok || boxen.kind != .Box || boxen.bars.len != 3usize || boxen.coords.len != 2usize || !near(boxen.bars[0usize].x, 14.0) || !near(boxen.bars[0usize].y, 25.0) || !near(boxen.bars[0usize].height, 50.0) || !near(boxen.bars[2usize].x, 38.0) || !near(boxen.segments[0usize].from.y, 50.0) || !near(boxen.coords[0usize].y, 100.0) { ret chart.Invalid }
    let (_, boxen_short) = chart.boxen_plot(boxen_values[..], bounds, 3usize, boxen_tails[..], boxen_lines[..], boxen_boxes[..2usize])
    if boxen_short != chart.TooLarge { ret chart.Invalid }
    let (_, boxen_tail_short) = chart.boxen_plot(boxen_values[..], bounds, 3usize, boxen_tails[..1usize], boxen_lines[..], boxen_boxes[..])
    if boxen_tail_short != chart.TooLarge { ret chart.Invalid }
    let (_, boxen_deep) = chart.boxen_plot(boxen_values[..], bounds, 4usize, boxen_tails[..], boxen_lines[..], boxen_boxes[..])
    if boxen_deep != chart.Invalid { ret chart.Invalid }
    let (_, boxen_zero) = chart.boxen_plot(boxen_values[..], bounds, 0usize, boxen_tails[..], boxen_lines[..], boxen_boxes[..])
    if boxen_zero != chart.Invalid { ret chart.Invalid }
    let (_, boxen_empty) = chart.boxen_plot(boxen_values[..3usize], bounds, 1usize, boxen_tails[..], boxen_lines[..], boxen_boxes[..])
    if boxen_empty != chart.Empty { ret chart.Invalid }
    let boxen_unsorted = [4]f64{ 2.0, 1.0, 3.0, 4.0 }
    let (_, boxen_order) = chart.boxen_plot(boxen_unsorted[..], bounds, 1usize, boxen_tails[..], boxen_lines[..], boxen_boxes[..])
    if boxen_order != chart.Invalid { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.Brush { Solid: paint.rgba(0.1, 0.3, 0.8, 1.0) }
    if chart_scene.append(a, &builder, &plot, blue) != ok || scene.builder_count(&builder) != 6usize { ret chart.Invalid }
    if chart_scene.append(a, &builder, &pp, blue) != ok || scene.builder_count(&builder) != 12usize { ret chart.Invalid }
    if chart_scene.append(a, &builder, &boxen, blue) != ok || scene.builder_count(&builder) != 18usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Normal P-P", "Normal probability plot")
    try chart_svg.append(&writer, &pp, paint.rgba(0.1, 0.3, 0.8, 1.0))
    try chart_svg.append(&writer, &boxen, paint.rgba(0.1, 0.3, 0.8, 1.0))
    try chart_svg.finish(&writer)
    if !str.contains(io.memory_bytes(&held), "<rect") || !str.contains(io.memory_bytes(&held), "<line") { ret chart.Invalid }
    try io.print("gfx chart qq ok\n")
    ret ok
}
