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
    let values = [4]f64{ 0.0, 0.0, 2.0, 4.0 }
    let lengths = [2]usize{ 2usize, 2usize }
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    var grid: [11]f64 = zero
    var estimates: [22]f64 = zero
    var bandwidths: [2]f64 = zero
    var outline: [26]chart.Coord = zero
    var storage: [2]chart.Layout = zero
    let (ridges, ridge_error) = chart.ridgeline(values[..], lengths[..], bounds, 1.0f64, 1.5, grid[..], estimates[..], bandwidths[..], outline[..], storage[..])
    if ridge_error != ok || ridges.len != 2usize || ridges[0].kind != .Area || !near(ridges[0].x_min, -3.0) || !near(ridges[0].x_max, 7.0) || !near(f32(grid[3usize]), 0.0) || !near(f32(estimates[3usize]), 0.39894) || !near(f32(estimates[17usize]), 0.24197) || !near(ridges[0].coords[0usize].y, 60.0) || !near(ridges[0].coords[4usize].y, 0.0) || !near(ridges[1].coords[0usize].y, 100.0) || !near(ridges[1].coords[7usize].y, 63.61) { ret chart.Invalid }
    let short_counts = [2]usize{ 2usize, 1usize }
    let (_, count_error) = chart.ridgeline(values[..], short_counts[..], bounds, 1.0f64, 1.5, grid[..], estimates[..], bandwidths[..], outline[..], storage[..])
    if count_error != chart.Invalid { ret chart.Invalid }
    let empty_group = [2]usize{ 4usize, 0usize }
    let (_, empty_error) = chart.ridgeline(values[..], empty_group[..], bounds, 1.0f64, 1.5, grid[..], estimates[..], bandwidths[..], outline[..], storage[..])
    if empty_error != chart.Invalid { ret chart.Invalid }
    let (_, overlap_error) = chart.ridgeline(values[..], lengths[..], bounds, 1.0f64, 0.0, grid[..], estimates[..], bandwidths[..], outline[..], storage[..])
    if overlap_error != chart.Invalid { ret chart.Invalid }
    let (_, storage_error) = chart.ridgeline(values[..], lengths[..], bounds, 1.0f64, 1.5, grid[..], estimates[..21usize], bandwidths[..], outline[..], storage[..])
    if storage_error != chart.TooLarge { ret chart.Invalid }
    let bad_values = [4]f64{ 0.0, 0.0, 1.0 / 0.0, 4.0 }
    let (_, bad_error) = chart.ridgeline(bad_values[..], lengths[..], bounds, 1.0f64, 1.5, grid[..], estimates[..], bandwidths[..], outline[..], storage[..])
    if bad_error != chart.Invalid { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 4usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &ridges[1usize], paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &ridges[0usize], paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 2usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Ridgeline", "Two shared-scale density ridges")
    try chart_svg.append(&writer, &ridges[1usize], blue)
    try chart_svg.append(&writer, &ridges[0usize], blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart ridgeline ok\n")
    ret ok
}
