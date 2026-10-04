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
    let camera = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 30.0f64, distance: 4.5f64 }
    let bounds = geometry.rect(20.0, 25.0, 240.0, 130.0)
    var points: [9]chart.Coord = zero
    var depths: [9]f64 = zero
    var face_vertices: [16]chart.Coord = zero
    var faces: [4]chart.Layout = zero
    var face_depths: [4]f64 = zero
    var face_values: [4]f64 = zero
    var order: [4]usize = zero
    var wires: [12]chart.Segment = zero
    var corners: [8]chart.Coord = zero
    var edges: [12]chart.Segment = zero
    var storage = chart.Surface3dStorage { points: points[..], depths: depths[..], face_vertices: face_vertices[..], faces: faces[..], face_depths: face_depths[..], face_values: face_values[..], order: order[..], wires: wires[..], corners: corners[..], edges: edges[..] }
    let values = [9]f64{ 0.0f64, 1.0f64, 0.0f64, 1.0f64, 2.0f64, 1.0f64, 0.0f64, 1.0f64, 0.0f64 }
    let (mesh, mesh_error) = chart.wireframe3d(values[..], 3usize, camera, bounds, &storage)
    if mesh_error != ok || mesh.columns != 3usize || mesh.rows != 3usize || mesh.value_min != 0.0f64 || mesh.value_max != 2.0f64 || mesh.faces.len != 4usize || mesh.wireframe.segments.len != 12usize || mesh.frame.segments.len != 12usize { ret chart.Invalid }
    if !(mesh.points[4usize].y < mesh.points[0usize].y && mesh.face_values[0usize] == 1.0f64 && mesh.faces[0usize].coords.len == 4usize) { ret chart.Invalid }
    var seen: [4]bool = zero
    var i = 0usize
    while i < mesh.order.len {
        if mesh.order[i] >= 4usize || seen[mesh.order[i]] { ret chart.Invalid }
        seen[mesh.order[i]] = true
        if i > 0usize && mesh.face_depths[mesh.order[i]] < mesh.face_depths[mesh.order[i - 1usize]] { ret chart.Invalid }
        i += 1usize
    }
    let saved_center = mesh.points[4usize]
    let (direct, direct_error) = chart.surface3d_grid(values[..], 3usize, camera, bounds, &storage)
    if direct_error != ok || direct.points[4usize].x != saved_center.x || direct.points[4usize].y != saved_center.y { ret chart.Invalid }
    let sample_x = [3]f64{ -0.25f64, 0.0f64, 0.25f64 }
    let sample_y = [3]f64{ 0.0f64, 0.0f64, 0.0f64 }
    var grid_x: [3]f64 = zero
    var grid_y: [3]f64 = zero
    var density: [9]f64 = zero
    let (surface, density_error) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.3f64, camera, bounds, grid_x[..], grid_y[..], density[..], &storage)
    if density_error != ok || surface.faces.len != 4usize || !(surface.value_max > surface.value_min && surface.value_min >= 0.0f64) || !(density[4usize] > density[0usize]) || grid_x[0usize] != -1.0f64 || grid_x[2usize] != 1.0f64 || grid_y[0usize] != 1.0f64 || grid_y[2usize] != -1.0f64 { ret chart.Invalid }
    let blue = paint.rgba(0.1, 0.4, 0.8, 1.0)
    let gray = paint.rgba(0.55, 0.62, 0.69, 1.0)
    let (made, builder_error) = scene.builder(a, 40usize)
    if builder_error != ok { ret builder_error }
    var builder = made
    try chart_scene.append(a, &builder, &surface.frame, paint.Brush { Solid: gray })
    i = 0usize
    while i < surface.order.len {
        try chart_scene.append(a, &builder, &surface.faces[surface.order[i]], paint.Brush { Solid: blue })
        i += 1usize
    }
    try chart_scene.append(a, &builder, &surface.wireframe, paint.Brush { Solid: gray })
    if scene.builder_count(&builder) != 28usize { ret chart.Invalid }
    let (state, unused, writer_error) = io.memory_writer(a, 0usize)
    if writer_error != ok { ret writer_error }
    var held = state
    var writer = io.writer(mem.cast[*void](&held), io.memory_write)
    try chart_svg.begin(&writer, 280.0, 180.0, "3-D surface", "Density quads and wireframe")
    try chart_svg.append(&writer, &surface.frame, gray)
    try chart_svg.append(&writer, &surface.faces[0usize], blue)
    try chart_svg.append(&writer, &surface.wireframe, gray)
    try chart_svg.finish(&writer)
    let svg = io.memory_bytes(&held)
    if !str.contains(svg, "<path") || !str.contains(svg, "<line") || !str.contains(svg, "</svg>") { ret chart.Invalid }
    let flat = [9]f64{ 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64, 1.0f64 }
    let (flat_map, flat_error) = chart.wireframe3d(flat[..], 3usize, camera, bounds, &storage)
    if flat_error != ok || flat_map.value_min != 1.0f64 || flat_map.value_max != 1.0f64 || flat_map.wireframe.segments.len != 12usize { ret chart.Invalid }
    let (_, shape_error) = chart.wireframe3d(values[..8usize], 3usize, camera, bounds, &storage)
    let (_, columns_error) = chart.wireframe3d(values[..], 1usize, camera, bounds, &storage)
    let bad_camera = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 30.0f64, distance: 1.0f64 }
    let (_, camera_error) = chart.wireframe3d(values[..], 3usize, bad_camera, bounds, &storage)
    let (_, bandwidth_error) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.0f64, 0.3f64, camera, bounds, grid_x[..], grid_y[..], density[..], &storage)
    let (_, domain_error) = chart.density_surface3d(sample_x[..], sample_y[..], -0.1f64, 0.1f64, -1.0f64, 1.0f64, 0.3f64, 0.3f64, camera, bounds, grid_x[..], grid_y[..], density[..], &storage)
    var short_storage = chart.Surface3dStorage { points: points[..], depths: depths[..], face_vertices: face_vertices[..15usize], faces: faces[..], face_depths: face_depths[..], face_values: face_values[..], order: order[..], wires: wires[..], corners: corners[..], edges: edges[..] }
    let (_, capacity_error) = chart.wireframe3d(values[..], 3usize, camera, bounds, &short_storage)
    if shape_error != chart.Invalid || columns_error != chart.Invalid || camera_error != chart.Invalid || bandwidth_error != chart.Invalid || domain_error != chart.Invalid || capacity_error != chart.TooLarge { ret chart.Invalid }
    try io.print("gfx chart surface3d ok\n")
    ret ok
}
