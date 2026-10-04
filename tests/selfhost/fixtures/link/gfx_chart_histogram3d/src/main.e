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
    let x = [5]f32{ -0.8, -0.7, 0.7, 0.8, 1.0 }
    let y = [5]f32{ -0.8, -0.7, 0.8, 0.8, 1.0 }
    let camera = chart.Camera3d { azimuth_degrees: 45.0f64, elevation_degrees: 30.0f64, distance: 4.0f64 }
    let bounds = geometry.rect(20.0, 25.0, 240.0, 130.0)
    var counts: [4]u64 = zero
    var cells: [4]chart.Cell = zero
    var vertices: [48]chart.Coord = zero
    var faces: [12]chart.Layout = zero
    var depths: [12]f64 = zero
    var order: [12]usize = zero
    var kinds: [12]chart.Histogram3dFace = zero
    var corners: [8]chart.Coord = zero
    var edges: [12]chart.Segment = zero
    var storage = chart.Histogram3dStorage { counts: counts[..], cells: cells[..], vertices: vertices[..], faces: faces[..], depths: depths[..], order: order[..], face_kinds: kinds[..], corners: corners[..], edges: edges[..] }
    let (map, result) = chart.histogram3d(x[..], y[..], -1.0, 1.0, -1.0, 1.0, 2usize, 2usize, camera, bounds, &storage)
    if result != ok || map.columns != 2usize || map.rows != 2usize || map.max_count != 3u64 || map.total_count != 5u64 || map.faces.len != 6usize || map.frame.segments.len != 12usize { ret chart.Invalid }
    if map.counts[0usize] != 0u64 || map.counts[1usize] != 3u64 || map.counts[2usize] != 2u64 || map.counts[3usize] != 0u64 { ret chart.Invalid }
    var seen: [6]bool = zero
    var i = 0usize
    while i < map.faces.len {
        if map.faces[i].kind != .Area || map.faces[i].coords.len != 4usize || map.order[i] >= 6usize || seen[map.order[i]] { ret chart.Invalid }
        seen[map.order[i]] = true
        if i > 0usize && map.depths[map.order[i]] < map.depths[map.order[i - 1usize]] { ret chart.Invalid }
        i += 1usize
    }
    if map.face_kinds[0usize] != .Top || map.face_kinds[1usize] != .XSide || map.face_kinds[2usize] != .YSide || !(map.faces[0usize].coords[0usize].y < map.faces[3usize].coords[0usize].y) { ret chart.Invalid }
    let blue = paint.rgba(0.08, 0.39, 0.74, 1.0)
    let gray = paint.rgba(0.55, 0.62, 0.69, 1.0)
    let (made, builder_error) = scene.builder(a, 32usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &map.frame, paint.Brush { Solid: gray })
    i = 0usize
    while i < map.order.len {
        let face = map.order[i]
        try chart_scene.append(a, &builder, &map.faces[face], paint.Brush { Solid: blue })
        i += 1usize
    }
    if scene.builder_count(&builder) != 18usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0, 180.0, "3-D histogram", "Extruded joint bin counts")
    try chart_svg.append(&writer, &map.frame, gray)
    i = 0usize
    while i < map.order.len {
        let face = map.order[i]
        try chart_svg.append(&writer, &map.faces[face], blue)
        i += 1usize
    }
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let original_y_side_x = map.faces[2usize].coords[0usize].x
    let reversed = chart.Camera3d { azimuth_degrees: -45.0f64, elevation_degrees: 30.0f64, distance: 4.0f64 }
    let (reversed_map, reversed_error) = chart.histogram3d(x[..], y[..], -1.0, 1.0, -1.0, 1.0, 2usize, 2usize, reversed, bounds, &storage)
    if reversed_error != ok || reversed_map.counts[1usize] != 3u64 || reversed_map.faces[2usize].coords[0usize].x == original_y_side_x { ret chart.Invalid }
    let flat_camera = chart.Camera3d { azimuth_degrees: 45.0f64, elevation_degrees: 0.0f64, distance: 4.0f64 }
    let (_, camera_error) = chart.histogram3d(x[..], y[..], -1.0, 1.0, -1.0, 1.0, 2usize, 2usize, flat_camera, bounds, &storage)
    let (_, shape_error) = chart.histogram3d(x[..], y[..4usize], -1.0, 1.0, -1.0, 1.0, 2usize, 2usize, camera, bounds, &storage)
    let (_, range_error) = chart.histogram3d(x[..], y[..], -0.5, 0.5, -1.0, 1.0, 2usize, 2usize, camera, bounds, &storage)
    var short_storage = chart.Histogram3dStorage { counts: counts[..], cells: cells[..], vertices: vertices[..], faces: faces[..5usize], depths: depths[..], order: order[..], face_kinds: kinds[..], corners: corners[..], edges: edges[..] }
    let (_, capacity_error) = chart.histogram3d(x[..], y[..], -1.0, 1.0, -1.0, 1.0, 2usize, 2usize, camera, bounds, &short_storage)
    if camera_error != chart.Invalid || shape_error != chart.Invalid || range_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart histogram3d ok\n")
    ret ok
}
