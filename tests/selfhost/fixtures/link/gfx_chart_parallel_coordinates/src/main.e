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
    let values = [12]f64{ 0.0, 10.0, 5.0, 7.0, 5.0, 20.0, 5.0, 8.0, 10.0, 30.0, 5.0, 9.0 }
    let bounds = geometry.rect(10.0, 20.0, 300.0, 100.0)
    var minimums: [4]f64 = zero
    var maximums: [4]f64 = zero
    var segments: [9]chart.Segment = zero
    var axes: [4]chart.Segment = zero
    let (marks, guides, layout_error) = chart.parallel_coordinates(values[..], 4usize, bounds, minimums[..], maximums[..], segments[..], axes[..])
    if layout_error != ok || marks.kind != .Rug || marks.segments.len != 9usize || guides.segments.len != 4usize { ret chart.Invalid }
    if minimums[0usize] != 0.0 || maximums[1usize] != 30.0 || minimums[2usize] != 5.0 || maximums[2usize] != 5.0 { ret chart.Invalid }
    if !near(axes[0usize].from.x, 10.0) || !near(axes[3usize].from.x, 310.0) || !near(segments[0usize].from.y, 120.0) || !near(segments[1usize].to.y, 70.0) || !near(segments[8usize].to.y, 20.0) { ret chart.Invalid }
    let (_, _, short_lines) = chart.parallel_coordinates(values[..], 4usize, bounds, minimums[..], maximums[..], segments[..8usize], axes[..])
    if short_lines != chart.TooLarge { ret chart.Invalid }
    let (_, _, short_axes) = chart.parallel_coordinates(values[..], 4usize, bounds, minimums[..], maximums[..], segments[..], axes[..3usize])
    if short_axes != chart.TooLarge { ret chart.Invalid }
    let (_, _, malformed) = chart.parallel_coordinates(values[..11usize], 4usize, bounds, minimums[..], maximums[..], segments[..], axes[..])
    if malformed != chart.Invalid { ret chart.Invalid }
    let (_, _, empty_error) = chart.parallel_coordinates(values[..0usize], 4usize, bounds, minimums[..], maximums[..], segments[..], axes[..])
    if empty_error != chart.Empty { ret chart.Invalid }
    let bad = [4]f64{ 0.0, 1.0, 0.0 / 0.0, 3.0 }
    let (_, _, nonfinite) = chart.parallel_coordinates(bad[..], 2usize, bounds, minimums[..], maximums[..], segments[..], axes[..])
    if nonfinite != chart.Invalid { ret chart.Invalid }
    var panels: [16]geometry.Rect = zero
    var pair_points: [36]chart.Coord = zero
    var pair_layers: [16]chart.Layout = zero
    let (pairs, pairs_error) = chart.scatterplot_matrix(values[..], 4usize, bounds, 10.0, minimums[..], maximums[..], panels[..], pair_points[..], pair_layers[..])
    if pairs_error != ok || pairs.len != 16usize || pairs[0usize].coords.len != 0usize || pairs[1usize].coords.len != 3usize || pairs[2usize].coords.len != 3usize { ret chart.Invalid }
    if !near(pairs[1usize].coords[0usize].x, panels[1usize].x) || !near(pairs[1usize].coords[0usize].y, panels[1usize].y + panels[1usize].height) || !near(pairs[1usize].coords[2usize].x, panels[1usize].x + panels[1usize].width) || !near(pairs[1usize].coords[2usize].y, panels[1usize].y) { ret chart.Invalid }
    if !near(pairs[2usize].coords[0usize].x, panels[2usize].x + panels[2usize].width / 2.0) || !near(pairs[2usize].coords[2usize].x, pairs[2usize].coords[0usize].x) { ret chart.Invalid }
    let (_, short_pairs) = chart.scatterplot_matrix(values[..], 4usize, bounds, 10.0, minimums[..], maximums[..], panels[..], pair_points[..35usize], pair_layers[..])
    if short_pairs != chart.TooLarge { ret chart.Invalid }
    let (_, bad_gap) = chart.scatterplot_matrix(values[..], 4usize, bounds, 40.0, minimums[..], maximums[..], panels[..], pair_points[..], pair_layers[..])
    if bad_gap != chart.Invalid { ret chart.Invalid }
    let (_, bad_shape) = chart.scatterplot_matrix(values[..11usize], 4usize, bounds, 10.0, minimums[..], maximums[..], panels[..], pair_points[..], pair_layers[..])
    if bad_shape != chart.Invalid { ret chart.Invalid }
    let (_, bad_pairs) = chart.scatterplot_matrix(bad[..], 2usize, bounds, 10.0, minimums[..], maximums[..], panels[..], pair_points[..], pair_layers[..])
    if bad_pairs != chart.Invalid { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let ink = paint.rgba(0.07, 0.35, 0.76, 1.0)
    try chart_scene.append(a, &builder, &guides, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &marks, paint.Brush { Solid: ink })
    try chart_scene.append(a, &builder, &pairs[1usize], paint.Brush { Solid: ink })
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 340.0, 160.0, "Parallel coordinates", "Independent axis ranges")
    try chart_svg.append(&writer, &guides, ink)
    try chart_svg.append(&writer, &marks, ink)
    try chart_svg.append(&writer, &pairs[1usize], ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart parallel coordinates ok\n")
    ret ok
}
