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
    let bounds = geometry.rect(10.0, 20.0, 160.0, 100.0)
    let x = [7]f32{ 0.0, 10.0, 0.0, 10.0, 0.0, 5.0, 5.0 }
    let y = [7]f32{ 10.0, 10.0, 0.0, 0.0, 10.0, 5.0, 5.0 }
    var counts: [4]u64 = zero
    var cells: [4]chart.Cell = zero
    let (map, result) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, counts[..], cells[..])
    if result != ok || map.total_count != 7u64 || map.max_count != 3u64 || map.counts.len != 4usize || map.matrix.cells.len != 4usize || map.matrix.kind != .Heatmap || map.matrix.columns != 2usize || map.matrix.rows != 2usize || map.matrix.value_min != 0.0 || map.matrix.value_max != 3.0 { ret chart.Invalid }
    if counts[0usize] != 2u64 || counts[1usize] != 1u64 || counts[2usize] != 1u64 || counts[3usize] != 3u64 { ret chart.Invalid }
    var total = 0u64
    var i = 0usize
    while i < counts.len {
        total += counts[i]
        i += 1usize
    }
    if total != 7u64 { ret chart.Invalid }
    if !near(cells[0usize].rect.x, 10.0) || !near(cells[0usize].rect.y, 20.0) || !near(cells[0usize].rect.width, 80.0) || !near(cells[0usize].rect.height, 50.0) || !near(cells[3usize].rect.x, 90.0) || !near(cells[3usize].rect.y, 70.0) || !near(cells[3usize].value, 3.0) { ret chart.Invalid }
    let low = paint.rgba(0.93, 0.96, 0.99, 1.0)
    let high = paint.rgba(0.04, 0.33, 0.72, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append_matrix(&builder, &map.matrix, low, low, high)
    if scene.builder_count(&builder) != 4usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 190.0, 140.0, "2D bins", "Count by rectangle")
    try chart_svg.append_matrix(&writer, &map.matrix, low, low, high)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let other_x = [3]f32{ -2.0, 0.0, 2.0 }
    let other_y = [3]f32{ -2.0, 0.0, 2.0 }
    let (signed, signed_error) = chart.bin2d(other_x[..], other_y[..], -2.0, 2.0, -2.0, 2.0, bounds, 2usize, 2usize, counts[..], cells[..])
    if signed_error != ok || signed.total_count != 3u64 || counts[0usize] != 0u64 || counts[1usize] != 1u64 || counts[2usize] != 1u64 || counts[3usize] != 1u64 { ret chart.Invalid }
    let too_far = [1]f32{ 11.0 }
    let (_, outside_error) = chart.bin2d(too_far[..], y[..1usize], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, counts[..], cells[..])
    let (_, empty_error) = chart.bin2d(x[..0usize], y[..0usize], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, counts[..], cells[..])
    let (_, mismatch_error) = chart.bin2d(x[..], y[..6usize], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, counts[..], cells[..])
    let (_, domain_error) = chart.bin2d(x[..], y[..], 10.0, 0.0, 0.0, 10.0, bounds, 2usize, 2usize, counts[..], cells[..])
    let (_, bounds_error) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, geometry.rect(0.0, 0.0, -1.0, 100.0), 2usize, 2usize, counts[..], cells[..])
    let (_, narrow_error) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, geometry.rect(0.0, 0.0, 1.0, 1.0), 2usize, 2usize, counts[..], cells[..])
    let (_, precision_error) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, geometry.rect(100000000.0, 0.0, 2.0, 2.0), 2usize, 2usize, counts[..], cells[..])
    let (_, columns_error) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 0usize, 2usize, counts[..], cells[..])
    let (_, rows_error) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 0usize, counts[..], cells[..])
    let (_, counts_error) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, counts[..3usize], cells[..])
    let (_, cells_error) = chart.bin2d(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, counts[..], cells[..3usize])
    if outside_error != chart.Invalid || empty_error != chart.Empty || mismatch_error != chart.Invalid || domain_error != chart.Invalid || bounds_error != chart.Invalid || narrow_error != chart.TooLarge || precision_error != chart.TooLarge || columns_error != chart.Invalid || rows_error != chart.Invalid || counts_error != chart.TooLarge || cells_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart bin2d ok\n")
    ret ok
}
