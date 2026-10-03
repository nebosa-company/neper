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
    let x = [5]f32{ 0.0, 10.0, 0.0, 10.0, 0.0 }
    let y = [5]f32{ 10.0, 10.0, 0.0, 0.0, 10.0 }
    var cells: [4]chart.HexCell = zero
    var vertices: [24]chart.Coord = zero
    var layers: [4]chart.Layout = zero
    let (map, result) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, cells[..], vertices[..], layers[..])
    if result != ok || map.cells.len != 4usize || map.hexes.len != 4usize || map.total_count != 5u64 || map.max_count != 2u64 { ret chart.Invalid }
    if cells[0usize].count != 2u64 || cells[1usize].count != 1u64 || cells[2usize].count != 1u64 || cells[3usize].count != 1u64 { ret chart.Invalid }
    var total = 0u64
    var i = 0usize
    while i < map.cells.len {
        total += map.cells[i].count
        if map.hexes[i].kind != .Area || map.hexes[i].coords.len != 6usize { ret chart.Invalid }
        if !near(map.hexes[i].coords[0usize].x, map.cells[i].center.x) || map.hexes[i].coords[0usize].y >= map.cells[i].center.y { ret chart.Invalid }
        i += 1usize
    }
    if total != 5u64 { ret chart.Invalid }
    let (wide, wide_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, geometry.rect(0.0, 0.0, 1000.0, 100.0), 2usize, 2usize, cells[..], vertices[..], layers[..])
    if wide_error != ok || wide.total_count != 5u64 { ret chart.Invalid }
    total = 0u64
    i = 0usize
    while i < cells.len {
        total += cells[i].count
        i += 1usize
    }
    if total != 5u64 { ret chart.Invalid }
    let (tall, tall_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, geometry.rect(0.0, 0.0, 100.0, 1000.0), 2usize, 2usize, cells[..], vertices[..], layers[..])
    if tall_error != ok || tall.total_count != 5u64 { ret chart.Invalid }
    total = 0u64
    i = 0usize
    while i < cells.len {
        total += cells[i].count
        i += 1usize
    }
    if total != 5u64 { ret chart.Invalid }
    let ink = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let (made, builder_error) = scene.builder(a, 8usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.hexes[0usize], paint.Brush { Solid: ink })
    if scene.builder_count(&builder) != 1usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 190.0, 140.0, "Hexbin", "Count by hexagon")
    try chart_svg.append(&writer, &map.hexes[0usize], ink)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let too_far = [1]f32{ 11.0 }
    let (_, outside_error) = chart.hexbin(too_far[..], y[..1usize], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, cells[..], vertices[..], layers[..])
    let (_, empty_error) = chart.hexbin(x[..0usize], y[..0usize], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, cells[..], vertices[..], layers[..])
    let (_, mismatch_error) = chart.hexbin(x[..], y[..4usize], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, cells[..], vertices[..], layers[..])
    let (_, domain_error) = chart.hexbin(x[..], y[..], 10.0, 0.0, 0.0, 10.0, bounds, 2usize, 2usize, cells[..], vertices[..], layers[..])
    let (_, bounds_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, geometry.rect(0.0, 0.0, -1.0, 100.0), 2usize, 2usize, cells[..], vertices[..], layers[..])
    let (_, narrow_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, geometry.rect(0.0, 0.0, 2.0, 2.0), 2usize, 2usize, cells[..], vertices[..], layers[..])
    let (_, columns_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 0usize, 2usize, cells[..], vertices[..], layers[..])
    let (_, rows_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 0usize, cells[..], vertices[..], layers[..])
    let (_, cells_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, cells[..3usize], vertices[..], layers[..])
    let (_, vertices_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, cells[..], vertices[..23usize], layers[..])
    let (_, layers_error) = chart.hexbin(x[..], y[..], 0.0, 10.0, 0.0, 10.0, bounds, 2usize, 2usize, cells[..], vertices[..], layers[..3usize])
    if outside_error != chart.Invalid || empty_error != chart.Empty || mismatch_error != chart.Invalid || domain_error != chart.Invalid || bounds_error != chart.Invalid || narrow_error != chart.TooLarge || columns_error != chart.Invalid || rows_error != chart.Invalid || cells_error != chart.TooLarge || vertices_error != chart.TooLarge || layers_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart hexbin ok\n")
    ret ok
}
