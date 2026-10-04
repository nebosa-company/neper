use e.gfx.chart
use e.gfx.chart.scene as chart_scene
use e.gfx.chart.svg as chart_svg
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.io
use e.mem
use e.str

fn main(a: *mem.Arena, args: []str) -> err {
    let x = [8]f64{ -1.0f64, 1.0f64, -1.0f64, 1.0f64, -1.0f64, 1.0f64, -1.0f64, 1.0f64 }
    let y = [8]f64{ -1.0f64, -1.0f64, 1.0f64, 1.0f64, -1.0f64, -1.0f64, 1.0f64, 1.0f64 }
    let z = [8]f64{ -1.0f64, -1.0f64, -1.0f64, -1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64 }
    let camera = chart.Camera3d { azimuth_degrees: 45.0f64, elevation_degrees: 30.0f64, distance: 4.0f64 }
    let bounds = geometry.rect(20.0, 25.0, 240.0, 130.0)
    var points: [8]chart.Coord = zero
    var depths: [8]f64 = zero
    var order: [8]usize = zero
    var bubbles: [8]geometry.Rect = zero
    var corners: [8]chart.Coord = zero
    var edges: [12]chart.Segment = zero
    var storage = chart.Scatter3dStorage { points: points[..], depths: depths[..], order: order[..], bubbles: bubbles[..], corners: corners[..], edges: edges[..] }
    let (map, result) = chart.scatter3d(x[..], y[..], z[..], camera, bounds, &storage)
    if result != ok || map.marks.kind != .Bubble || map.frame.kind != .Rug || map.marks.bars.len != 8usize || map.frame.segments.len != 12usize || map.corners.len != 8usize { ret chart.Invalid }
    if map.x_min != -1.0f64 || map.x_max != 1.0f64 || map.y_min != -1.0f64 || map.y_max != 1.0f64 || map.z_min != -1.0f64 || map.z_max != 1.0f64 { ret chart.Invalid }
    var seen: [8]bool = zero
    var i = 0usize
    while i < order.len {
        if order[i] >= 8usize || seen[order[i]] || points[i].x < bounds.x || points[i].x > bounds.x + bounds.width || points[i].y < bounds.y || points[i].y > bounds.y + bounds.height { ret chart.Invalid }
        seen[order[i]] = true
        if i > 0usize && depths[order[i]] < depths[order[i - 1usize]] { ret chart.Invalid }
        i += 1usize
    }
    if !(bubbles[0usize].width < bubbles[7usize].width && corners[0usize].x != corners[1usize].x && corners[0usize].y != corners[4usize].y) { ret chart.Invalid }
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let gray = paint.rgba(0.55, 0.62, 0.69, 1.0)
    let (made, builder_error) = scene.builder(a, 64usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.frame, paint.Brush { Solid: gray })
    try chart_scene.append(a, &builder, &map.marks, paint.Brush { Solid: blue })
    if scene.builder_count(&builder) != 20usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0, 180.0, "3-D scatter", "Perspective points in a cube")
    try chart_svg.append(&writer, &map.frame, gray)
    try chart_svg.append(&writer, &map.marks, blue)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<circle") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let flat = [1]f64{ 7.0f64 }
    let (flat_map, flat_error) = chart.scatter3d(flat[..], flat[..], flat[..], camera, bounds, &storage)
    if flat_error != ok || flat_map.marks.bars.len != 1usize || flat_map.points[0usize].x < bounds.x { ret chart.Invalid }
    let bad_camera = chart.Camera3d { azimuth_degrees: 45.0f64, elevation_degrees: 30.0f64, distance: 2.0f64 }
    let (_, camera_error) = chart.scatter3d(x[..], y[..], z[..], bad_camera, bounds, &storage)
    let (_, shape_error) = chart.scatter3d(x[..], y[..7usize], z[..], camera, bounds, &storage)
    var short_storage = chart.Scatter3dStorage { points: points[..], depths: depths[..], order: order[..], bubbles: bubbles[..7usize], corners: corners[..], edges: edges[..] }
    let (_, capacity_error) = chart.scatter3d(x[..], y[..], z[..], camera, bounds, &short_storage)
    if camera_error != chart.Invalid || shape_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart scatter3d ok\n")
    ret ok
}
