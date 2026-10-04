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
    let delta = a - b
    ret delta > -0.003f64 && delta < 0.003f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    // Machine-major, setting-major, two readings per cell.
    let values = [12]f64{ 8.0f64, 10.0f64, 10.0f64, 12.0f64, 12.0f64, 14.0f64, 9.0f64, 11.0f64, 14.0f64, 16.0f64, 15.0f64, 17.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 240.0, 120.0)
    var raw_points: [12]chart.Coord = zero
    var cell_points: [6]chart.Coord = zero
    var cell_lines: [4]chart.Segment = zero
    var group_points: [2]chart.Coord = zero
    var group_lines: [1]chart.Segment = zero
    var cell_means: [6]f64 = zero
    var group_means: [2]f64 = zero
    var storage = chart.MultiVariStorage { raw_points: raw_points[..], cell_points: cell_points[..], cell_lines: cell_lines[..], group_points: group_points[..], group_lines: group_lines[..], cell_means: cell_means[..], group_means: group_means[..] }
    let (map, result) = chart.multi_vari(values[..], 2usize, 3usize, 2usize, bounds, &storage)
    if result != ok || map.observations.kind != .Scatter || map.cells.kind != .Scatter || map.within.kind != .Rug || map.groups.kind != .PointLine || map.observations.coords.len != 12usize || map.cells.coords.len != 6usize || map.within.segments.len != 4usize || map.groups.coords.len != 2usize || map.groups.segments.len != 1usize { ret chart.Invalid }
    let expected_cells = [6]f64{ 9.0f64, 11.0f64, 13.0f64, 10.0f64, 15.0f64, 16.0f64 }
    var i = 0usize
    while i < expected_cells.len {
        if !near(map.cell_means[i], expected_cells[i]) { ret chart.Invalid }
        i += 1usize
    }
    if !near(map.group_means[0usize], 11.0f64) || !near(map.group_means[1usize], 13.6666667f64) { ret chart.Invalid }
    if !near(f64(cell_points[0usize].x), 30.0f64) || !near(f64(cell_points[1usize].x), 70.0f64) || !near(f64(cell_points[3usize].x), 150.0f64) || !near(f64(group_points[0usize].x), 70.0f64) || !near(f64(group_points[1usize].x), 190.0f64) { ret chart.Invalid }
    if !near(f64(raw_points[0usize].y), 140.0f64) || !near(f64(raw_points[11usize].y), 20.0f64) || !near(f64(cell_lines[1usize].to.x), 110.0f64) || !near(f64(cell_lines[2usize].from.x), 150.0f64) { ret chart.Invalid }
    if !(raw_points[0usize].x < raw_points[1usize].x && group_points[0usize].y > group_points[1usize].y) { ret chart.Invalid }

    let gray = paint.rgba(0.65, 0.7, 0.76, 1.0)
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.35, 0.15, 1.0)
    let (made, builder_error) = scene.builder(a, 40usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.observations, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.within, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.cells, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.groups, paint.Brush { Solid: orange })
    if scene.builder_count(&builder) != 25usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 270.0, 160.0, "Multi-vari chart", "Two-factor cell and group means")
    try chart_svg.append(&writer, &map.observations, gray)
    try chart_svg.append(&writer, &map.within, blue)
    try chart_svg.append(&writer, &map.cells, blue)
    try chart_svg.append(&writer, &map.groups, orange)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<rect") || !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }

    let constant = [4]f64{ 10.0f64, 10.0f64, 10.0f64, 10.0f64 }
    let (flat, flat_error) = chart.multi_vari(constant[..], 2usize, 2usize, 1usize, bounds, &storage)
    if flat_error != ok || !(flat.cells.y_min < 10.0 && flat.cells.y_max > 10.0) { ret chart.Invalid }
    let (_, bad_shape) = chart.multi_vari(values[..], 2usize, 2usize, 2usize, bounds, &storage)
    let (_, bad_levels) = chart.multi_vari(values[..], 1usize, 3usize, 4usize, bounds, &storage)
    var short_storage = chart.MultiVariStorage { raw_points: raw_points[..11usize], cell_points: cell_points[..], cell_lines: cell_lines[..], group_points: group_points[..], group_lines: group_lines[..], cell_means: cell_means[..], group_means: group_means[..] }
    let (_, short_points) = chart.multi_vari(values[..], 2usize, 3usize, 2usize, bounds, &short_storage)
    let (_, bad_bounds) = chart.multi_vari(values[..], 2usize, 3usize, 2usize, geometry.rect(0.0, 0.0, 0.0, 1.0), &storage)
    if bad_shape != chart.Invalid || bad_levels != chart.Invalid || short_points != chart.TooLarge || bad_bounds != chart.Invalid { ret chart.Invalid }
    try io.print("gfx chart multi vari ok\n")
    ret ok
}
