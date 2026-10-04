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

fn near(a: f64, b: f64) -> bool { ret a - b < 0.00001f64 && b - a < 0.00001f64 }

fn main(a: *mem.Arena, args: []str) -> err {
    let values = [12]f64{
        10.0f64, 12.0f64, 11.0f64, 13.0f64,
        20.0f64, 22.0f64, 21.0f64, 23.0f64,
        30.0f64, 32.0f64, 31.0f64, 33.0f64,
    }
    let (summary, summary_error) = stat.gage_run_summary(values[..], 3usize, 2usize, 2usize)
    if summary_error != ok || summary.parts != 3usize || summary.operators != 2usize || summary.repeats != 2usize || !near(summary.grand_mean, 21.5f64) || !near(summary.minimum, 10.0f64) || !near(summary.maximum, 33.0f64) || !near(summary.max_repeat_range, 2.0f64) { ret chart.Invalid }
    var points: [12]chart.Coord = zero
    var layouts: [2]chart.Layout = zero
    var centers: [3]chart.Coord = zero
    var dividers: [2]chart.Segment = zero
    var mean_guide: [1]chart.Segment = zero
    var work = chart.GageRunStorage {
        operator_points: points[..], operator_layouts: layouts[..],
        part_centers: centers[..], part_dividers: dividers[..], mean_guide: mean_guide[..],
    }
    let bounds = geometry.rect(10.0, 20.0, 300.0, 180.0)
    let (report, report_error) = chart.gage_run(values[..], 3usize, 2usize, 2usize, bounds, &work)
    if report_error != ok || report.operators.len != 2usize || report.operators[0usize].coords.len != 6usize || report.operators[1usize].coords.len != 6usize || report.dividers.segments.len != 2usize || report.part_centers.len != 3usize { ret chart.Invalid }
    if !near(f64(centers[0usize].x), 60.0f64) || !near(f64(dividers[0usize].from.x), 110.0f64) || !near(f64(mean_guide[0usize].from.y), 110.0f64) || !near(f64(points[0usize].x), 22.5f64) || !near(f64(points[6usize].x), 72.5f64) { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.4, 0.15, 1.0)
    let (made, build_error) = scene.builder(a, 128usize)
    if build_error != ok { ret build_error }
    var builder = made
    try chart_scene.append(a, &builder, &report.dividers, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.reference, paint.Brush { Solid: orange })
    try chart_scene.append(a, &builder, &report.operators[0usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &report.operators[1usize], paint.Brush { Solid: orange })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 320.0f32, 220.0f32, "Gage run", "Parts and operators")
    try chart_svg.append(&writer, &report.dividers, blue)
    try chart_svg.append(&writer, &report.reference, orange)
    try chart_svg.append(&writer, &report.operators[0usize], blue)
    try chart_svg.append(&writer, &report.operators[1usize], orange)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<line") { ret chart.Invalid }
    let (_, bad_count) = stat.gage_run_summary(values[..11usize], 3usize, 2usize, 2usize)
    let (_, bad_parts) = chart.gage_run(values[..], 1usize, 2usize, 2usize, bounds, &work)
    var nonfinite: [12]f64 = zero
    var index = 0usize
    while index < values.len {
        nonfinite[index] = values[index]
        index += 1usize
    }
    nonfinite[5usize] = 1.0f64 / 0.0f64
    let (_, bad_value) = stat.gage_run_summary(nonfinite[..], 3usize, 2usize, 2usize)
    let (_, bad_bounds) = chart.gage_run(values[..], 3usize, 2usize, 2usize, geometry.rect(10.0, 20.0, 0.0, 180.0), &work)
    var short = work
    short.operator_points = points[..11usize]
    let (_, short_error) = chart.gage_run(values[..], 3usize, 2usize, 2usize, bounds, &short)
    let constant = [12]f64{ 4.0f64, 4.0f64, 4.0f64, 4.0f64, 4.0f64, 4.0f64, 4.0f64, 4.0f64, 4.0f64, 4.0f64, 4.0f64, 4.0f64 }
    let (flat, flat_error) = chart.gage_run(constant[..], 3usize, 2usize, 2usize, bounds, &work)
    if bad_count != stat.Invalid || bad_parts != chart.Invalid || bad_value != stat.Invalid || bad_bounds != chart.Invalid || short_error != chart.TooLarge || flat_error != ok || !near(flat.summary.grand_mean, 4.0f64) || !near(f64(mean_guide[0usize].from.y), 110.0f64) { ret chart.Invalid }
    try io.print("gfx chart gage run ok\n")
    ret ok
}
