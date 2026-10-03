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

fn near(a: f32, b: f32) -> bool {
    let d = a - b
    ret d > -0.02 && d < 0.02
}

fn main(a: *mem.Arena, args: []str) -> err {
    let scores = [5]f64{ 0.9f64, 0.8f64, 0.8f64, 0.3f64, 0.1f64 }
    let positive = [5]bool{ true, false, true, false, true }
    var order: [5]usize = zero
    var points: [6]stat.BinaryPoint = zero
    let (curve, curve_error) = stat.binary_curve(scores[..], positive[..], order[..], points[..])
    if curve_error != ok || curve.positives != 3usize || curve.negatives != 2usize || curve.points.len != 5usize || points[0usize].tp != 0usize || points[1usize].tp != 1usize || points[1usize].fp != 0usize || points[2usize].tp != 2usize || points[2usize].fp != 1usize || points[3usize].tp != 2usize || points[3usize].fp != 2usize || points[4usize].tp != 3usize || points[4usize].fp != 2usize { ret chart.Invalid }
    let (auc, auc_ok) = stat.roc_auc(&curve)
    let (ap, ap_ok) = stat.average_precision(&curve)
    if !auc_ok || !ap_ok || !near(f32(auc), 0.583333) || !near(f32(ap), 0.755556) { ret chart.Invalid }
    let same_labels = [5]bool{ true, true, true, true, true }
    let (_, labels_error) = stat.binary_curve(scores[..], same_labels[..], order[..], points[..])
    if labels_error != stat.Invalid { ret chart.Invalid }
    let (_, capacity_error) = stat.binary_curve(scores[..], positive[..], order[..], points[..5usize])
    if capacity_error != stat.TooSmall { ret chart.Invalid }
    let (valid_curve, valid_error) = stat.binary_curve(scores[..], positive[..], order[..], points[..])
    if valid_error != ok { ret valid_error }
    let bounds = geometry.rect(10.0, 20.0, 120.0, 60.0)
    var x: [6]f32 = zero
    var y: [6]f32 = zero
    var lines: [5]chart.Segment = zero
    let (roc, roc_error) = chart.binary_metric_curve(&valid_curve, .Roc, bounds, x[..], y[..], lines[..])
    if roc_error != ok || roc.kind != .Line || roc.segments.len != 4usize || !near(roc.segments[0usize].from.x, 10.0) || !near(roc.segments[0usize].from.y, 80.0) || !near(roc.segments[1usize].to.x, 70.0) || !near(roc.segments[1usize].to.y, 40.0) || !near(roc.segments[3usize].to.x, 130.0) || !near(roc.segments[3usize].to.y, 20.0) { ret chart.Invalid }
    let (pr, pr_error) = chart.binary_metric_curve(&valid_curve, .PrecisionRecall, bounds, x[..], y[..], lines[..])
    if pr_error != ok || !near(pr.segments[0usize].from.y, 20.0) || !near(pr.segments[2usize].to.x, 90.0) || !near(pr.segments[2usize].to.y, 50.0) { ret chart.Invalid }
    let (gain, gain_error) = chart.binary_metric_curve(&valid_curve, .CumulativeGain, bounds, x[..], y[..], lines[..])
    if gain_error != ok || !near(gain.segments[0usize].to.x, 34.0) || !near(gain.segments[1usize].to.x, 82.0) { ret chart.Invalid }
    let (lift, lift_error) = chart.binary_metric_curve(&valid_curve, .Lift, bounds, x[..], y[..], lines[..])
    if lift_error != ok || !near(lift.y_max, 1.666667) || !near(lift.segments[0usize].to.y, 20.0) || !near(lift.segments[3usize].to.y, 44.0) { ret chart.Invalid }
    let (_, chart_capacity_error) = chart.binary_metric_curve(&valid_curve, .Roc, bounds, x[..], y[..], lines[..3usize])
    if chart_capacity_error != chart.TooLarge { ret chart.Invalid }
    let (roc_again, again_error) = chart.binary_metric_curve(&valid_curve, .Roc, bounds, x[..], y[..], lines[..])
    if again_error != ok { ret again_error }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &roc_again, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 1usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 150.0, 100.0, "Binary diagnostic", "Tie grouped")
    try chart_svg.append(&writer, &roc_again, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart binary curves ok\n")
    ret ok
}
