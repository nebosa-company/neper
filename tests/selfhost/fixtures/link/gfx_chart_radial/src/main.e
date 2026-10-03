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
    let difference = a - b
    ret difference > -0.01 && difference < 0.01
}

fn main(a: *mem.Arena, args: []str) -> err {
    let bounds = geometry.rect(0.0, 0.0, 100.0, 100.0)
    let values = [4]f32{ 10.0, 5.0, 0.0, 8.0 }
    let minimum = [4]f32{ 0.0, 0.0, 0.0, 0.0 }
    let maximum = [4]f32{ 10.0, 5.0, 10.0, 10.0 }
    var polygon_points: [5]chart.Coord = zero
    var guide_segments: [12]chart.Segment = zero
    let (polygon, guides, radar_error) = chart.radar(values[..], minimum[..], maximum[..], bounds, 2usize, polygon_points[..], guide_segments[..])
    if radar_error != ok || polygon.kind != .Area || polygon.coords.len != 5usize || guides.segments.len != 12usize { ret chart.Invalid }
    if !near(polygon.coords[0usize].x, 50.0) || !near(polygon.coords[0usize].y, 0.0) || !near(polygon.coords[1usize].x, 100.0) || !near(polygon.coords[1usize].y, 50.0) || !near(polygon.coords[2usize].x, 50.0) || !near(polygon.coords[2usize].y, 50.0) || !near(polygon.coords[3usize].x, 10.0) || !near(polygon.coords[4usize].y, 0.0) { ret chart.Invalid }
    if !near(guides.segments[4usize].from.y, 25.0) || !near(guides.segments[4usize].to.x, 75.0) { ret chart.Invalid }
    let (_, _, range_error) = chart.radar(values[..], minimum[..], maximum[..3usize], bounds, 2usize, polygon_points[..], guide_segments[..])
    let (_, _, capacity_error) = chart.radar(values[..], minimum[..], maximum[..], bounds, 2usize, polygon_points[..4usize], guide_segments[..])
    let (_, _, level_error) = chart.radar(values[..], minimum[..], maximum[..], bounds, 0usize, polygon_points[..], guide_segments[..])
    if range_error != chart.Invalid || capacity_error != chart.TooLarge || level_error != chart.Invalid { ret chart.Invalid }
    let rose_values = [4]f32{ 1.0, 4.0, 0.0, 1.0 }
    var sector_points: [112]chart.Coord = zero
    var sectors: [4]chart.Layout = zero
    let (rose_layers, rose_error) = chart.rose(rose_values[..], bounds, sector_points[..], sectors[..])
    if rose_error != ok || rose_layers.len != 4usize || rose_layers[0usize].coords.len != 28usize || rose_layers[1usize].coords.len != 28usize { ret chart.Invalid }
    if !near(rose_layers[0usize].coords[14usize].x, 50.0) || !near(rose_layers[0usize].coords[14usize].y, 25.0) || !near(rose_layers[1usize].coords[14usize].x, 100.0) || !near(rose_layers[1usize].coords[14usize].y, 50.0) || !near(rose_layers[2usize].coords[14usize].x, 50.0) { ret chart.Invalid }
    let flat = [4]f32{ 0.0, 0.0, 0.0, 0.0 }
    let (_, flat_error) = chart.rose(flat[..], bounds, sector_points[..], sectors[..])
    let (_, rose_capacity_error) = chart.rose(rose_values[..], bounds, sector_points[..111usize], sectors[..])
    if flat_error != chart.Invalid || rose_capacity_error != chart.TooLarge { ret chart.Invalid }
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    let blue = paint.rgba(0.1, 0.3, 0.8, 1.0)
    try chart_scene.append(a, &builder, &guides, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &polygon, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &rose_layers[0usize], paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 14usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 100.0, 100.0, "Radar and rose", "Per-axis radar and area-scaled rose")
    try chart_svg.append(&writer, &guides, blue)
    try chart_svg.append(&writer, &polygon, blue)
    try chart_svg.append(&writer, &rose_layers[0usize], blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<line") || !str.contains(svg, "<path") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    try io.print("gfx chart radial ok\n")
    ret ok
}
