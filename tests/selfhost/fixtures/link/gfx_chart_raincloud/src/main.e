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
    let sample = [10]f64{ 1.0f64, 2.0f64, 2.0f64, 3.0f64, 4.0f64, 5.0f64, 6.0f64, 7.0f64, 8.0f64, 20.0f64 }
    let bounds = geometry.rect(10.0, 20.0, 200.0, 100.0)
    var grid: [65]f64 = zero
    var estimates: [65]f64 = zero
    var outline: [67]chart.Coord = zero
    var points: [10]chart.Coord = zero
    var lines: [5]chart.Segment = zero
    var boxes: [1]geometry.Rect = zero
    let (map, result) = chart.raincloud(sample[..], bounds, 1.0f64, grid[..], estimates[..], outline[..], points[..], lines[..], boxes[..])
    if result != ok || map.cloud.kind != .Violin || map.cloud.coords.len != 67usize || map.drops.kind != .Strip || map.drops.coords.len != sample.len || map.summary.kind != .Box || map.summary.segments.len != 5usize || map.summary.bars.len != 1usize { ret chart.Invalid }
    let lo = grid[0usize]
    let hi = grid[64usize]
    let upper_y = bounds.y + bounds.height * f32(1.0f64 - (8.0f64 - lo) / (hi - lo))
    let median_y = bounds.y + bounds.height * f32(1.0f64 - (4.5f64 - lo) / (hi - lo))
    let outlier_y = bounds.y + bounds.height * f32(1.0f64 - (20.0f64 - lo) / (hi - lo))
    if !near(map.summary.segments[1usize].to.y, upper_y) || !near(map.summary.segments[4usize].from.y, median_y) || !near(map.drops.coords[9usize].y, outlier_y) { ret chart.Invalid }
    if map.drops.coords[9usize].y >= map.summary.segments[1usize].to.y || map.cloud.coords[0usize].x != bounds.x + bounds.width * 0.5 { ret chart.Invalid }
    var i = 0usize
    while i < map.drops.coords.len {
        if map.drops.coords[i].x <= bounds.x + bounds.width * 0.6 || map.drops.coords[i].x >= bounds.x + bounds.width || map.drops.coords[i].y < bounds.y || map.drops.coords[i].y > bounds.y + bounds.height { ret chart.Invalid }
        i += 1usize
    }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let orange = paint.rgba(0.9, 0.3, 0.1, 1.0)
    let (made, builder_error) = scene.builder(a, 24usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.cloud, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.summary, paint.Brush { Solid: blue })
    try chart_scene.append(a, &builder, &map.drops, paint.Brush { Solid: orange })
    if scene.builder_count(&builder) != 17usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 220.0, 140.0, "Raincloud", "KDE, box and observations")
    try chart_svg.append(&writer, &map.cloud, blue)
    try chart_svg.append(&writer, &map.summary, blue)
    try chart_svg.append(&writer, &map.drops, orange)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<line") || !str.contains(svg, "<rect") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let unsorted = [3]f64{ 2.0f64, 1.0f64, 3.0f64 }
    let (_, empty_error) = chart.raincloud(sample[..0usize], bounds, 1.0f64, grid[..], estimates[..], outline[..], points[..], lines[..], boxes[..])
    let (_, order_error) = chart.raincloud(unsorted[..], bounds, 1.0f64, grid[..], estimates[..], outline[..], points[..], lines[..], boxes[..])
    let (_, bandwidth_error) = chart.raincloud(sample[..], bounds, -1.0f64, grid[..], estimates[..], outline[..], points[..], lines[..], boxes[..])
    let (_, points_error) = chart.raincloud(sample[..], bounds, 1.0f64, grid[..], estimates[..], outline[..], points[..9usize], lines[..], boxes[..])
    let (_, lines_error) = chart.raincloud(sample[..], bounds, 1.0f64, grid[..], estimates[..], outline[..], points[..], lines[..4usize], boxes[..])
    let (_, boxes_error) = chart.raincloud(sample[..], bounds, 1.0f64, grid[..], estimates[..], outline[..], points[..], lines[..], boxes[..0usize])
    if empty_error != chart.Empty || order_error != chart.Invalid || bandwidth_error != chart.Invalid || points_error != chart.TooLarge || lines_error != chart.TooLarge || boxes_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart raincloud ok\n")
    ret ok
}
