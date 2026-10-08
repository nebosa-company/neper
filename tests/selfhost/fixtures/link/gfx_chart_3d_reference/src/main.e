// The 3-D charts of e.gfx.chart against independent references (L069, D2253;
// scripts/chart_3d_reference.py writes this file): the cube frame under three cameras, a scatter cloud's
// projected points, depths and far-to-near order, the product-Gaussian density against a direct double sum,
// the bin counts of the 3-D histogram with out-of-range points dropped, and the refusals -- non-finite data,
// degenerate domains and bounds, out-of-range cameras and bandwidths, and each caller-storage array one
// element short. Every check has its own exit code.
use e.gfx.chart
use e.gfx.geometry
use e.math
use e.mem
use e.os

fn zero_f64() -> f64 {
    ret 0.0f64
}

fn abs64(v: f64) -> f64 {
    if v < 0.0f64 { ret 0.0f64 - v }
    ret v
}

fn corners_match(got: []const chart.Coord, want: []const f64) -> bool {
    if got.len != 8usize || want.len != 16usize { ret false }
    var i = 0usize
    while i < 8usize {
        if abs64(f64(got[i].x) - want[2usize * i]) > 0.002f64 || abs64(f64(got[i].y) - want[2usize * i + 1usize]) > 0.002f64 { ret false }
        i += 1usize
    }
    ret true
}

fn points_match(got: []const chart.Coord, want: []const f64) -> bool {
    if got.len * 2usize != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if abs64(f64(got[i].x) - want[2usize * i]) > 0.002f64 || abs64(f64(got[i].y) - want[2usize * i + 1usize]) > 0.002f64 { ret false }
        i += 1usize
    }
    ret true
}

fn depths_match(got: []const f64, want: []const f64) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if abs64(got[i] - want[i]) > 1e-12f64 { ret false }
        i += 1usize
    }
    ret true
}

fn same_order(got: []const usize, want: []const usize) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if got[i] != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn counts_match(got: []const u64, want: []const u64) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if got[i] != want[i] { ret false }
        i += 1usize
    }
    ret true
}

fn close_all(got: []const f64, want: []const f64, tolerance: f64) -> bool {
    if got.len != want.len { ret false }
    var i = 0usize
    while i < got.len {
        if abs64(got[i] - want[i]) > tolerance * (1.0f64 + abs64(want[i])) { ret false }
        i += 1usize
    }
    ret true
}

fn density_min(values: []const f64) -> f64 {
    var m = values[0usize]
    var i = 1usize
    while i < values.len {
        if values[i] < m { m = values[i] }
        i += 1usize
    }
    ret m
}

fn density_max(values: []const f64) -> f64 {
    var m = values[0usize]
    var i = 1usize
    while i < values.len {
        if values[i] > m { m = values[i] }
        i += 1usize
    }
    ret m
}

fn main(a: *mem.Arena, args: []str) -> err {
    var s_points: [6]chart.Coord = zero
    var s_depths: [6]f64 = zero
    var s_order: [6]usize = zero
    var s_bubbles: [6]geometry.Rect = zero
    var s_corners: [8]chart.Coord = zero
    var s_edges: [12]chart.Segment = zero
    var scatter_storage = chart.Scatter3dStorage { points: s_points[..], depths: s_depths[..], order: s_order[..], bubbles: s_bubbles[..], corners: s_corners[..], edges: s_edges[..] }
    var u_points: [20]chart.Coord = zero
    var u_depths: [20]f64 = zero
    var u_face_vertices: [48]chart.Coord = zero
    var u_faces: [12]chart.Layout = zero
    var u_face_depths: [12]f64 = zero
    var u_face_values: [12]f64 = zero
    var u_order: [12]usize = zero
    var u_wires: [64]chart.Segment = zero
    var u_corners: [8]chart.Coord = zero
    var u_edges: [12]chart.Segment = zero
    var surface_storage = chart.Surface3dStorage { points: u_points[..], depths: u_depths[..], face_vertices: u_face_vertices[..], faces: u_faces[..], face_depths: u_face_depths[..], face_values: u_face_values[..], order: u_order[..], wires: u_wires[..], corners: u_corners[..], edges: u_edges[..] }
    var h_counts: [12]u64 = zero
    var h_cells: [12]chart.Cell = zero
    var h_vertices: [144]chart.Coord = zero
    var h_faces: [36]chart.Layout = zero
    var h_depths: [36]f64 = zero
    var h_order: [36]usize = zero
    var h_kinds: [36]chart.Histogram3dFace = zero
    var h_corners: [8]chart.Coord = zero
    var h_edges: [12]chart.Segment = zero
    var hist_storage = chart.Histogram3dStorage { counts: h_counts[..], cells: h_cells[..], vertices: h_vertices[..], faces: h_faces[..], depths: h_depths[..], order: h_order[..], face_kinds: h_kinds[..], corners: h_corners[..], edges: h_edges[..] }
    let bounds = geometry.rect(20.0, 25.0, 240.0, 130.0)
    let flat = [4]f64{ 0.0f64, 1.0f64, 1.0f64, 0.0f64 }
    let corners0 = [16]f64{ 138.99111938476562f64, 84.83251190185547f64, 94.61346435546875f64, 110.28123474121094f64, 186.0460205078125f64, 107.16658020019531f64, 144.0870361328125f64, 148.0357208251953f64, 138.62261962890625f64, 31.964284896850586f64, 82.849365234375f64, 46.58921432495117f64, 197.150634765625f64, 44.717254638671875f64, 145.22901916503906f64, 71.35723114013672f64 }
    let camera0 = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 30.0f64, distance: 4.5f64 }
    let (frame0, frame_error0) = chart.wireframe3d(flat[..], 2usize, camera0, bounds, &surface_storage)
    if frame_error0 != ok { os.exit(1) }
    if !corners_match(frame0.corners, corners0[..]) { os.exit(2) }
    let corners1 = [16]f64{ 113.45565032958984f64, 148.0357208251953f64, 182.29017639160156f64, 115.09870147705078f64, 93.66851043701172f64, 102.15415954589844f64, 141.52374267578125f64, 90.93326568603516f64, 106.2769775390625f64, 31.964284896850586f64, 192.9390106201172f64, 38.84375762939453f64, 87.06098937988281f64, 41.15732192993164f64, 142.58837890625f64, 43.015594482421875f64 }
    let camera1 = chart.Camera3d { azimuth_degrees: -120.0f64, elevation_degrees: 15.0f64, distance: 3.0f64 }
    let (frame1, frame_error1) = chart.wireframe3d(flat[..], 2usize, camera1, bounds, &surface_storage)
    if frame_error1 != ok { os.exit(3) }
    if !corners_match(frame1.corners, corners1[..]) { os.exit(4) }
    let corners2 = [16]f64{ 174.31849670410156f64, 90.39436340332031f64, 192.6162109375f64, 136.46246337890625f64, 87.38379669189453f64, 110.29559326171875f64, 123.91309356689453f64, 148.0357208251953f64, 167.5460968017578f64, 31.964284896850586f64, 183.9041290283203f64, 81.53874206542969f64, 99.25504302978516f64, 52.67928695678711f64, 127.3836669921875f64, 94.93529510498047f64 }
    let camera2 = chart.Camera3d { azimuth_degrees: 200.0f64, elevation_degrees: -40.0f64, distance: 6.0f64 }
    let (frame2, frame_error2) = chart.wireframe3d(flat[..], 2usize, camera2, bounds, &surface_storage)
    if frame_error2 != ok { os.exit(5) }
    if !corners_match(frame2.corners, corners2[..]) { os.exit(6) }
    let cloud_x = [6]f64{ -3.0f64, 2.5f64, 0.0f64, 4.0f64, -1.0f64, 1.0f64 }
    let cloud_y = [6]f64{ 1.0f64, -1.5f64, 0.0f64, 3.0f64, -2.0f64, 2.0f64 }
    let cloud_z = [6]f64{ 0.5f64, 2.0f64, -1.0f64, 1.0f64, 3.0f64, -2.0f64 }
    let cloud_points = [12]f64{ 167.2371368408203f64, 70.86863708496094f64, 104.11622619628906f64, 59.0163459777832f64, 139.20187377929688f64, 93.58834838867188f64, 144.68594360351562f64, 107.8212661743164f64, 125.70491027832031f64, 35.351585388183594f64, 153.34625244140625f64, 120.41297149658203f64 }
    let cloud_depths = [6]f64{ -0.5276854768430853f64, 0.2041740300430499f64, -0.5078371489333451f64, 1.323066401110833f64, -0.3553050882226179f64, -0.060369209644072275f64 }
    let cloud_order = [6]usize{ 0usize, 2usize, 4usize, 5usize, 1usize, 3usize }
    let (cloud, cloud_error) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &scatter_storage)
    if cloud_error != ok || cloud.points.len != 6usize { os.exit(7) }
    if !points_match(cloud.points, cloud_points[..]) { os.exit(8) }
    if !depths_match(cloud.depths, cloud_depths[..]) { os.exit(9) }
    if !same_order(cloud.order, cloud_order[..]) { os.exit(10) }
    if cloud.x_min != -3.0f64 || cloud.x_max != 4.0f64 || cloud.z_min != -2.0f64 || cloud.z_max != 3.0f64 { os.exit(11) }
    let sample_x = [5]f64{ -0.6f64, 0.1f64, 0.3f64, 0.7f64, -0.2f64 }
    let sample_y = [5]f64{ 0.2f64, -0.5f64, 0.4f64, 0.7f64, -0.1f64 }
    let density_want = [20]f64{ 0.014938661341707214f64, 0.040184966830394346f64, 0.07531477895852963f64, 0.22982349935623733f64, 0.12710905442222598f64, 0.10742981564480032f64, 0.3384624965070632f64, 0.3508439269212419f64, 0.3714585176863924f64, 0.12327638995981566f64, 0.051520849544253344f64, 0.273202401824416f64, 0.45457876655322277f64, 0.16193771081093852f64, 0.011744109608768104f64, 0.0019605375619542002f64, 0.03203987321316666f64, 0.13253260761691854f64, 0.0518078543680725f64, 0.0014135864382121706f64 }
    var grid_x: [5]f64 = zero
    var grid_y: [4]f64 = zero
    var density: [20]f64 = zero
    let (surface, surface_error) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if surface_error != ok || surface.columns != 5usize || surface.rows != 4usize { os.exit(12) }
    if !close_all(density[..], density_want[..], 1e-12f64) { os.exit(13) }
    if surface.value_min != density_min(density[..]) || surface.value_max != density_max(density[..]) { os.exit(14) }
    let grid_x_want = [5]f64{ -1.0f64, -0.5f64, 0.0f64, 0.5f64, 1.0f64 }
    let grid_y_want = [4]f64{ 1.0f64, 0.33333333333333337f64, -0.33333333333333326f64, -1.0f64 }
    if !close_all(grid_x[..], grid_x_want[..], 1e-15f64) || !close_all(grid_y[..], grid_y_want[..], 1e-15f64) { os.exit(15) }
    let hist_x = [10]f32{ -0.900, -0.500, -0.100, 0.300, 0.600, 1.000, 0.990, -1.000, 0.200, 0.250 }
    let hist_y = [10]f32{ -0.800, 0.100, 0.400, -0.300, 0.700, 1.000, 0.000, -1.000, -0.950, -0.900 }
    let hist_want = [12]u64{ 0u64, 1u64, 0u64, 2u64, 0u64, 1u64, 1u64, 1u64, 2u64, 0u64, 2u64, 0u64 }
    let (hist, hist_error) = chart.histogram3d(hist_x[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, 4usize, 3usize, camera0, bounds, &hist_storage)
    if hist_error != ok || hist.total_count != 10u64 || hist.max_count != 2u64 { os.exit(16) }
    if !counts_match(hist.counts, hist_want[..]) { os.exit(17) }
    var out_x = hist_x
    out_x[6] = 1.4
    let (_ho, e_hist_outside) = chart.histogram3d(out_x[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, 4usize, 3usize, camera0, bounds, &hist_storage)
    if e_hist_outside != chart.Invalid { os.exit(18) }
    let nan = 0.0f64 / zero_f64()
    let infinity = 1.0f64 / zero_f64()
    var bad_x = cloud_x
    bad_x[2] = nan
    let (_p0, e_nan_x) = chart.scatter3d(bad_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &scatter_storage)
    if e_nan_x != chart.Invalid { os.exit(19) }
    var bad_y = cloud_y
    bad_y[4] = infinity
    let (_p1, e_inf_y) = chart.scatter3d(cloud_x[..], bad_y[..], cloud_z[..], camera0, bounds, &scatter_storage)
    if e_inf_y != chart.Invalid { os.exit(20) }
    var bad_z = cloud_z
    bad_z[0] = -infinity
    let (_p2, e_inf_z) = chart.scatter3d(cloud_x[..], cloud_y[..], bad_z[..], camera0, bounds, &scatter_storage)
    if e_inf_z != chart.Invalid { os.exit(21) }
    let (_p3, e_len) = chart.scatter3d(cloud_x[..5usize], cloud_y[..], cloud_z[..], camera0, bounds, &scatter_storage)
    if e_len != chart.Invalid { os.exit(22) }
    let (_p4, e_empty) = chart.scatter3d(cloud_x[..0usize], cloud_y[..0usize], cloud_z[..0usize], camera0, bounds, &scatter_storage)
    if e_empty != chart.Invalid { os.exit(23) }
    let bad_az_high = chart.Camera3d { azimuth_degrees: 361.0f64, elevation_degrees: 30.0f64, distance: 4.5f64 }
    let (_c_az_high, e_az_high) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], bad_az_high, bounds, &scatter_storage)
    if e_az_high != chart.Invalid { os.exit(24) }
    let bad_az_low = chart.Camera3d { azimuth_degrees: -361.0f64, elevation_degrees: 30.0f64, distance: 4.5f64 }
    let (_c_az_low, e_az_low) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], bad_az_low, bounds, &scatter_storage)
    if e_az_low != chart.Invalid { os.exit(25) }
    let bad_el_high = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 91.0f64, distance: 4.5f64 }
    let (_c_el_high, e_el_high) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], bad_el_high, bounds, &scatter_storage)
    if e_el_high != chart.Invalid { os.exit(26) }
    let bad_el_low = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: -91.0f64, distance: 4.5f64 }
    let (_c_el_low, e_el_low) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], bad_el_low, bounds, &scatter_storage)
    if e_el_low != chart.Invalid { os.exit(27) }
    let bad_near = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 30.0f64, distance: 2.99f64 }
    let (_c_near, e_near) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], bad_near, bounds, &scatter_storage)
    if e_near != chart.Invalid { os.exit(28) }
    let bad_nan_camera = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 30.0f64, distance: nan }
    let (_c_nan_camera, e_nan_camera) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], bad_nan_camera, bounds, &scatter_storage)
    if e_nan_camera != chart.Invalid { os.exit(29) }
    let (_b0, e_bounds0) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, geometry.rect(20.0, 25.0, 0.0, 130.0), &scatter_storage)
    if e_bounds0 != chart.Invalid { os.exit(30) }
    let (_b1, e_bounds1) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, geometry.rect(20.0, 25.0, 240.0, -5.0), &scatter_storage)
    if e_bounds1 != chart.Invalid { os.exit(31) }
    let flat_camera = chart.Camera3d { azimuth_degrees: 42.0f64, elevation_degrees: 0.0f64, distance: 4.5f64 }
    let (_h0, e_hist_flat) = chart.histogram3d(hist_x[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, 4usize, 3usize, flat_camera, bounds, &hist_storage)
    if e_hist_flat != chart.Invalid { os.exit(32) }
    let (_h1, e_hist_zero) = chart.histogram3d(hist_x[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, 0usize, 3usize, camera0, bounds, &hist_storage)
    if e_hist_zero != chart.Invalid { os.exit(33) }
    let (_h2, e_hist_range) = chart.histogram3d(hist_x[..], hist_y[..], 1.0, -1.0, -1.0, 1.0, 4usize, 3usize, camera0, bounds, &hist_storage)
    if e_hist_range == ok { os.exit(34) }
    var bad_hist = hist_x
    bad_hist[3] = f32(nan)
    let (_h3, e_hist_nan) = chart.histogram3d(bad_hist[..], hist_y[..], -1.0, 1.0, -1.0, 1.0, 4usize, 3usize, camera0, bounds, &hist_storage)
    if e_hist_nan == ok { os.exit(35) }
    let (_d_domain_x, e_density_domain_x) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, -1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_domain_x != chart.Invalid { os.exit(36) }
    let (_d_domain_y, e_density_domain_y) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, 1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_domain_y != chart.Invalid { os.exit(37) }
    let (_d_bw_zero, e_density_bw_zero) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.0f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_bw_zero != chart.Invalid { os.exit(38) }
    let (_d_bw_negative, e_density_bw_negative) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, -0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_bw_negative != chart.Invalid { os.exit(39) }
    let (_d_bw_nan, e_density_bw_nan) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, nan, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_bw_nan != chart.Invalid { os.exit(40) }
    let (_d_narrow, e_density_narrow) = chart.density_surface3d(sample_x[..], sample_y[..], 0.0f64, 0.5f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_narrow != chart.Invalid { os.exit(41) }
    var bad_sample = sample_x
    bad_sample[1] = nan
    let (_d6, e_density_nan) = chart.density_surface3d(bad_sample[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_nan != chart.Invalid { os.exit(42) }
    var tiny_grid_x: [1]f64 = zero
    let (_d7, e_density_grid) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, tiny_grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_grid != chart.Invalid { os.exit(43) }
    let (_d8, e_density_short) = chart.density_surface3d(sample_x[..], sample_y[..], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..19usize], &surface_storage)
    if e_density_short != chart.TooLarge { os.exit(44) }
    let (_d9, e_density_empty) = chart.density_surface3d(sample_x[..0usize], sample_y[..0usize], -1.0f64, 1.0f64, -1.0f64, 1.0f64, 0.3f64, 0.4f64, camera0, bounds, grid_x[..], grid_y[..], density[..], &surface_storage)
    if e_density_empty != chart.Empty { os.exit(45) }
    var short_scatter_points = chart.Scatter3dStorage { points: s_points[..5usize], depths: s_depths[..6usize], order: s_order[..6usize], bubbles: s_bubbles[..6usize], corners: s_corners[..8usize], edges: s_edges[..12usize] }
    let (_s_points, e_short_points) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &short_scatter_points)
    if e_short_points != chart.TooLarge { os.exit(46) }
    var short_scatter_depths = chart.Scatter3dStorage { points: s_points[..6usize], depths: s_depths[..5usize], order: s_order[..6usize], bubbles: s_bubbles[..6usize], corners: s_corners[..8usize], edges: s_edges[..12usize] }
    let (_s_depths, e_short_depths) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &short_scatter_depths)
    if e_short_depths != chart.TooLarge { os.exit(47) }
    var short_scatter_order = chart.Scatter3dStorage { points: s_points[..6usize], depths: s_depths[..6usize], order: s_order[..5usize], bubbles: s_bubbles[..6usize], corners: s_corners[..8usize], edges: s_edges[..12usize] }
    let (_s_order, e_short_order) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &short_scatter_order)
    if e_short_order != chart.TooLarge { os.exit(48) }
    var short_scatter_bubbles = chart.Scatter3dStorage { points: s_points[..6usize], depths: s_depths[..6usize], order: s_order[..6usize], bubbles: s_bubbles[..5usize], corners: s_corners[..8usize], edges: s_edges[..12usize] }
    let (_s_bubbles, e_short_bubbles) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &short_scatter_bubbles)
    if e_short_bubbles != chart.TooLarge { os.exit(49) }
    var short_scatter_corners = chart.Scatter3dStorage { points: s_points[..6usize], depths: s_depths[..6usize], order: s_order[..6usize], bubbles: s_bubbles[..6usize], corners: s_corners[..7usize], edges: s_edges[..12usize] }
    let (_s_corners, e_short_corners) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &short_scatter_corners)
    if e_short_corners != chart.TooLarge { os.exit(50) }
    var short_scatter_edges = chart.Scatter3dStorage { points: s_points[..6usize], depths: s_depths[..6usize], order: s_order[..6usize], bubbles: s_bubbles[..6usize], corners: s_corners[..8usize], edges: s_edges[..11usize] }
    let (_s_edges, e_short_edges) = chart.scatter3d(cloud_x[..], cloud_y[..], cloud_z[..], camera0, bounds, &short_scatter_edges)
    if e_short_edges != chart.TooLarge { os.exit(51) }
    let (written, write_error) = os.write(os.stdout(), "gfx chart 3d reference ok\n")
    os.exit(0)
    ret ok
}
