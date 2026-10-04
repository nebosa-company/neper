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

fn near(a: f64, b: f64, tolerance: f64) -> bool {
    let delta = a - b
    ret delta > 0.0f64 - tolerance && delta < tolerance
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Minitab's published reduced-model crossed study: 10 parts, 3 operators,
    // 3 replicates. Its interaction is nonsignificant and pooled into error.
    let means = stat.GageRrMeanSquares { part: 9.81799f64, operator: 1.58363f64, interaction: 0.01994f64, repeatability: 0.03997f64 }
    let (components, component_error) = stat.gage_rr_variance_components(10usize, 3usize, 3usize, &means, false)
    if component_error != ok || !near(components.repeatability, 0.03997f64, 0.00001f64) || !near(components.operator, 0.05146f64, 0.00002f64) || components.interaction != 0.0f64 || !near(components.part, 1.08645f64, 0.00002f64) || !near(components.gage, 0.09143f64, 0.00002f64) || !near(components.total, 1.17788f64, 0.00003f64) { ret chart.Invalid }
    let bounds = geometry.rect(30.0, 20.0, 280.0, 150.0)
    var bars: [8]geometry.Rect = zero
    var percentages: [8]f32 = zero
    let (plot, plot_error) = chart.gage_rr_components(&components, bounds, bars[..], percentages[..])
    if plot_error != ok || plot.contribution.kind != .Bar || plot.study_variation.kind != .Bar || plot.contribution.bars.len != 4usize || plot.study_variation.bars.len != 4usize || plot.percentages.len != 8usize { ret chart.Invalid }
    let expected_contribution = [4]f64{ 7.76f64, 3.39f64, 4.37f64, 92.24f64 }
    let expected_study = [4]f64{ 27.86f64, 18.42f64, 20.90f64, 96.04f64 }
    var i = 0usize
    while i < 4usize {
        if !near(f64(percentages[i]), expected_contribution[i], 0.03f64) || !near(f64(percentages[4usize + i]), expected_study[i], 0.03f64) { ret chart.Invalid }
        if !(bars[i].x < bars[4usize + i].x && bars[i].y >= bounds.y && bars[4usize + i].y >= bounds.y) { ret chart.Invalid }
        i += 1usize
    }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.35, 0.15, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &plot.contribution, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &plot.study_variation, paint.Brush { Solid: orange })
    if scene.builder_count(&builder) != 8usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 340.0, 200.0, "Gage R&R", "Crossed variance components")
    try chart_svg.append(&writer, &plot.contribution, blue)
    try chart_svg.append(&writer, &plot.study_variation, orange)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let reduced_values = [12]f64{ 9.8f64, 10.2f64, 10.8f64, 11.2f64, 19.8f64, 20.2f64, 20.8f64, 21.2f64, 29.8f64, 30.2f64, 30.8f64, 31.2f64 }
    let interaction_values = [12]f64{ 9.8f64, 10.2f64, 10.8f64, 11.2f64, 19.8f64, 20.2f64, 20.8f64, 21.2f64, 29.8f64, 30.2f64, 33.8f64, 34.2f64 }
    var part_means: [3]f64 = zero
    var operator_means: [2]f64 = zero
    var cell_means: [6]f64 = zero
    var work = stat.GageRrWork { part_means: part_means[..], operator_means: operator_means[..], cell_means: cell_means[..] }
    let (reduced, reduced_error) = stat.gage_rr_crossed(reduced_values[..], 3usize, 2usize, 2usize, 0.05f64, &work)
    if reduced_error != ok || reduced.interaction_included || !near(reduced.interaction_p, 1.0f64, 0.000001f64) || !near(reduced.mean_squares.repeatability, 0.06f64, 0.000001f64) || !near(reduced.components.operator, 0.49f64, 0.000001f64) || !near(reduced.components.part, 99.985f64, 0.000001f64) { ret chart.Invalid }
    let (full, full_error) = stat.gage_rr_crossed(interaction_values[..], 3usize, 2usize, 2usize, 0.05f64, &work)
    if full_error != ok || !full.interaction_included || !(full.interaction_p < 0.05f64) || !(full.components.interaction > 0.0f64) { ret chart.Invalid }
    let (_, bad_length) = stat.gage_rr_crossed(reduced_values[..11usize], 3usize, 2usize, 2usize, 0.05f64, &work)
    let (_, bad_alpha) = stat.gage_rr_crossed(reduced_values[..], 3usize, 2usize, 2usize, 0.0f64, &work)
    var insufficient = stat.GageRrWork { part_means: part_means[..2usize], operator_means: operator_means[..], cell_means: cell_means[..] }
    let (_, short_work) = stat.gage_rr_crossed(reduced_values[..], 3usize, 2usize, 2usize, 0.05f64, &insufficient)
    let (_, bad_bars) = chart.gage_rr_components(&components, bounds, bars[..7usize], percentages[..])
    let (_, bad_percentages) = chart.gage_rr_components(&components, bounds, bars[..], percentages[..7usize])
    let (_, bad_bounds) = chart.gage_rr_components(&components, geometry.rect(0.0, 0.0, 0.0, 100.0), bars[..], percentages[..])
    var invalid_components = components
    invalid_components.part = -1.0f64
    let (_, bad_component) = chart.gage_rr_components(&invalid_components, bounds, bars[..], percentages[..])
    var invalid_means = means
    invalid_means.repeatability = -0.01f64
    let (_, bad_means) = stat.gage_rr_variance_components(10usize, 3usize, 3usize, &invalid_means, false)
    if bad_length != stat.Invalid || bad_alpha != stat.Invalid || short_work != stat.TooSmall || bad_bars != chart.TooLarge || bad_percentages != chart.TooLarge || bad_bounds != chart.Invalid || bad_component != chart.Invalid || bad_means != stat.Invalid { ret chart.Invalid }
    try io.print("gfx chart gage rr ok\n")
    ret ok
}
