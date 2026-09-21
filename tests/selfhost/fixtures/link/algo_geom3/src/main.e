// `e.algo.geom3`: ray casts against a box, triangle, sphere, plane and disk
// (hand cases, then 100 LCG rays counted and summed against a Python
// replica); the fifteen box axes and the separating axis test; hull faces,
// face/edge axes, SAT and GJK agreeing on 50 LCG tetrahedron pairs with the
// hit count from a linear program and the distance sum from brute force; EPA
// depth on overlapping LCG boxes against the least separating axis push; Barnes-Hut
// forces exact at theta 0 and within 2% in aggregate at theta 0.5 over 200
// masses; Kabsch alignment matching scipy's RMSD; and the quickhull of 100
// points matching scipy's face count, volume and area. Each check exits with
// its own code.

use e.algo.geom3 as g
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> f64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64((*state >> 33u32) % 1000u64) / 10.0f64
}

fn draw3(state: *u64) -> g.Vec3 {
    let x = draw(state)
    let y = draw(state)
    let z = draw(state)
    ret g.vec3(x, y, z)
}

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tolerance
}

fn box_corners(lo: g.Vec3, hi: g.Vec3, out: []g.Vec3) {
    var k = 0usize
    while k < 8usize {
        var p = lo
        if k % 2usize == 1usize { p.x = hi.x }
        if (k / 2usize) % 2usize == 1usize { p.y = hi.y }
        if k >= 4usize { p.z = hi.z }
        out[k] = p
        k += 1usize
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 42u64
    let zero3 = g.vec3(0.0f64, 0.0f64, 0.0f64)
    let one3 = g.vec3(1.0f64, 1.0f64, 1.0f64)
    let ex = g.vec3(1.0f64, 0.0f64, 0.0f64)
    let ey = g.vec3(0.0f64, 1.0f64, 0.0f64)
    let ez = g.vec3(0.0f64, 0.0f64, 1.0f64)

    // 1: rays, hand cases.
    let (box_hit, box_t) = g.ray_box(g.vec3(0.0f64 - 2.0f64, 0.5f64, 0.5f64), ex, zero3, one3)
    if !box_hit || !near(box_t, 2.0f64, 1.0e-12f64) { os.exit(1i32) }
    let (inside_hit, inside_t) = g.ray_box(g.vec3(0.5f64, 0.5f64, 0.5f64), ex, zero3, one3)
    if !inside_hit || !near(inside_t, 0.0f64 - 0.5f64, 1.0e-12f64) { os.exit(1i32) }
    let (box_miss, _) = g.ray_box(g.vec3(0.0f64 - 2.0f64, 0.5f64, 0.5f64), ey, zero3, one3)
    if box_miss { os.exit(1i32) }
    let (tri_hit, tri_t, tri_u, tri_v) = g.ray_triangle(g.vec3(0.25f64, 0.25f64, 0.0f64 - 1.0f64), ez, zero3, ex, ey)
    if !tri_hit || !near(tri_t, 1.0f64, 1.0e-12f64) || !near(tri_u, 0.25f64, 1.0e-12f64) || !near(tri_v, 0.25f64, 1.0e-12f64) { os.exit(1i32) }
    let (tri_miss, _, _, _) = g.ray_triangle(g.vec3(1.0f64, 1.0f64, 0.0f64 - 1.0f64), ez, zero3, ex, ey)
    if tri_miss { os.exit(1i32) }
    let (sphere_hit, sphere_t) = g.ray_sphere(g.vec3(0.0f64 - 3.0f64, 0.0f64, 0.0f64), ex, zero3, 1.0f64)
    if !sphere_hit || !near(sphere_t, 2.0f64, 1.0e-12f64) { os.exit(1i32) }
    let (sphere_inside, sphere_exit) = g.ray_sphere(zero3, ex, zero3, 1.0f64)
    if !sphere_inside || !near(sphere_exit, 1.0f64, 1.0e-12f64) { os.exit(1i32) }
    let (sphere_miss, _) = g.ray_sphere(g.vec3(0.0f64 - 3.0f64, 2.0f64, 0.0f64), ex, zero3, 1.0f64)
    if sphere_miss { os.exit(1i32) }
    let top = g.vec3(0.0f64, 0.0f64, 3.0f64)
    let down = g.vec3(0.0f64, 0.0f64, 0.0f64 - 1.0f64)
    let (plane_hit, plane_t) = g.ray_plane(top, down, ez, ez)
    if !plane_hit || !near(plane_t, 2.0f64, 1.0e-12f64) { os.exit(1i32) }
    let (plane_parallel, _) = g.ray_plane(top, ex, ez, ez)
    let (plane_behind, _) = g.ray_plane(top, ez, ez, ez)
    if plane_parallel || plane_behind { os.exit(1i32) }
    let (disk_hit, disk_t) = g.ray_disk(g.vec3(1.5f64, 0.0f64, 3.0f64), down, ez, ez, 2.0f64)
    if !disk_hit || !near(disk_t, 2.0f64, 1.0e-12f64) { os.exit(1i32) }
    let (disk_miss, _) = g.ray_disk(g.vec3(3.0f64, 0.0f64, 3.0f64), down, ez, ez, 2.0f64)
    if disk_miss { os.exit(1i32) }

    // 2: 100 LCG rays at five targets: hit counts and parameter sums.
    var counts: [5]usize = zero
    var sums: [5]f64 = zero
    var i = 0usize
    while i < 100usize {
        let origin = g.sub(g.scale(draw3(&state), 0.1f64), g.vec3(5.0f64, 5.0f64, 5.0f64))
        let direction = g.sub(g.sub(g.scale(draw3(&state), 0.02f64), one3), origin)
        let (h0, t0) = g.ray_box(origin, direction, g.scale(one3, 0.0f64 - 1.0f64), one3)
        let (h1, t1, _, _) = g.ray_triangle(origin, direction, g.scale(ex, 2.0f64), g.scale(ey, 2.0f64), g.scale(ez, 2.0f64))
        let (h2, t2) = g.ray_sphere(origin, direction, zero3, 1.5f64)
        let (h3, t3) = g.ray_plane(origin, direction, ez, ez)
        let (h4, t4) = g.ray_disk(origin, direction, ez, ez, 2.0f64)
        if h0 { counts[0usize] += 1usize }
        if h1 { counts[1usize] += 1usize }
        if h2 { counts[2usize] += 1usize }
        if h3 { counts[3usize] += 1usize }
        if h4 { counts[4usize] += 1usize }
        sums[0usize] += t0
        sums[1usize] += t1
        sums[2usize] += t2
        sums[3usize] += t3
        sums[4usize] += t4
        i += 1usize
    }
    if counts[0usize] != 100usize || counts[1usize] != 26usize || counts[2usize] != 100usize || counts[3usize] != 91usize || counts[4usize] != 50usize { os.exit(2i32) }
    if !near(sums[0usize], 78.941716400f64, 1.0e-6f64) || !near(sums[1usize], 25.274998338f64, 1.0e-6f64) || !near(sums[2usize], 72.969096189f64, 1.0e-6f64) { os.exit(2i32) }
    if !near(sums[3usize], 154.497394116f64, 1.0e-6f64) || !near(sums[4usize], 52.245117864f64, 1.0e-6f64) { os.exit(2i32) }

    // 3: box axes and the separating axis test on axis-aligned boxes.
    var unit_axes: [3]g.Vec3 = zero
    unit_axes[0usize] = ex
    unit_axes[1usize] = ey
    unit_axes[2usize] = ez
    var axes: [48]g.Vec3 = zero
    let (axis_count, axis_error) = g.obb_axes(unit_axes[..], unit_axes[..], axes[..])
    if axis_error != ok || axis_count != 15usize { os.exit(3i32) }
    var box_a: [8]g.Vec3 = zero
    var box_b: [8]g.Vec3 = zero
    box_corners(zero3, one3, box_a[..])
    box_corners(g.scale(one3, 0.5f64), g.scale(one3, 1.5f64), box_b[..])
    if !g.separating_axis(box_a[..], box_b[..], axes[..15usize]) { os.exit(3i32) }
    box_corners(g.scale(one3, 2.0f64), g.scale(one3, 3.0f64), box_b[..])
    if g.separating_axis(box_a[..], box_b[..], axes[..15usize]) { os.exit(3i32) }
    let (_, small_error) = g.obb_axes(unit_axes[..], unit_axes[..], axes[..10usize])
    if small_error != g.TooSmall { os.exit(3i32) }

    // 4: GJK hand cases: separated cubes at a corner and along a face.
    var simplex: [4]g.Vec3 = zero
    let (corner_hit, corner_distance, _, corner_error) = g.gjk(box_a[..], box_b[..], simplex[..])
    if corner_error != ok || corner_hit || !near(corner_distance, 1.7320508075688772f64, 1.0e-9f64) { os.exit(4i32) }
    box_corners(g.vec3(2.0f64, 0.0f64, 0.0f64), g.vec3(3.0f64, 1.0f64, 1.0f64), box_b[..])
    let (face_hit, face_distance, _, face_error) = g.gjk(box_a[..], box_b[..], simplex[..])
    if face_error != ok || face_hit || !near(face_distance, 1.0f64, 1.0e-9f64) { os.exit(4i32) }
    box_corners(g.scale(one3, 0.5f64), g.scale(one3, 1.5f64), box_b[..])
    let (overlap_hit, overlap_distance, overlap_count, overlap_error) = g.gjk(box_a[..], box_b[..], simplex[..])
    if overlap_error != ok || !overlap_hit || overlap_distance != 0.0f64 { os.exit(4i32) }
    var vertices: [64]g.Vec3 = zero
    var poly_faces: [384]u32 = zero
    var poly_edges: [384]u32 = zero
    let (hand_normal, hand_depth, hand_error) = g.epa(box_a[..], box_b[..], simplex[..], overlap_count, vertices[..], poly_faces[..], poly_edges[..], 1.0e-9f64, 64usize)
    if hand_error != ok || !near(hand_depth, 0.5f64, 1.0e-9f64) || !near(g.length(hand_normal), 1.0f64, 1.0e-9f64) { os.exit(4i32) }

    // 5: 50 LCG tetrahedron pairs: hull, face/edge axes, SAT and GJK agree; the
    // hit count and distance sum match the Python reference.
    var tetra_a: [4]g.Vec3 = zero
    var tetra_b: [4]g.Vec3 = zero
    var faces_a: [24]u32 = zero
    var faces_b: [24]u32 = zero
    var edges: [24]u32 = zero
    var hits = 0usize
    var distance_sum = 0.0f64
    i = 0usize
    while i < 50usize {
        var k = 0usize
        while k < 4usize {
            tetra_a[k] = draw3(&state)
            k += 1usize
        }
        k = 0usize
        while k < 4usize {
            tetra_b[k] = draw3(&state)
            k += 1usize
        }
        let (count_a, error_a) = g.hull(tetra_a[..], faces_a[..], edges[..], 1.0e-9f64)
        let (count_b, error_b) = g.hull(tetra_b[..], faces_b[..], edges[..], 1.0e-9f64)
        if error_a != ok || error_b != ok || count_a != 4usize || count_b != 4usize { os.exit(5i32) }
        let (pair_axes, pair_axes_error) = g.polytope_axes(tetra_a[..], faces_a[..12usize], tetra_b[..], faces_b[..12usize], axes[..])
        if pair_axes_error != ok || pair_axes != 44usize { os.exit(5i32) }
        let sat = g.separating_axis(tetra_a[..], tetra_b[..], axes[..pair_axes])
        let (hit, distance, _, gjk_error) = g.gjk(tetra_a[..], tetra_b[..], simplex[..])
        if gjk_error != ok || sat != hit { os.exit(5i32) }
        if hit { hits += 1usize } else { distance_sum += distance }
        i += 1usize
    }
    if hits != 30usize || !near(distance_sum, 166.473938673f64, 1.0e-6f64) { os.exit(6i32) }

    // 6: EPA depth on overlapping LCG boxes equals the least axis push that
    // separates them, and the normal is an axis.
    var overlaps = 0usize
    var depth_sum = 0.0f64
    i = 0usize
    while i < 30usize {
        let lo_a = g.scale(draw3(&state), 0.5f64)
        let hi_a = g.add(lo_a, g.add(g.scale(one3, 2.0f64), draw3(&state)))
        let lo_b = g.scale(draw3(&state), 0.5f64)
        let hi_b = g.add(lo_b, g.add(g.scale(one3, 2.0f64), draw3(&state)))
        var least = 1.0e300f64
        var axis = 0usize
        while axis < 3usize {
            // The least push of A along this axis that separates the boxes.
            var push = g.component(hi_a, axis) - g.component(lo_b, axis)
            if g.component(hi_b, axis) - g.component(lo_a, axis) < push { push = g.component(hi_b, axis) - g.component(lo_a, axis) }
            if push < least { least = push }
            axis += 1usize
        }
        if least > 0.0f64 {
            overlaps += 1usize
            box_corners(lo_a, hi_a, box_a[..])
            box_corners(lo_b, hi_b, box_b[..])
            let (hit, _, count, gjk_error) = g.gjk(box_a[..], box_b[..], simplex[..])
            if gjk_error != ok || !hit { os.exit(7i32) }
            let (normal, depth, epa_error) = g.epa(box_a[..], box_b[..], simplex[..], count, vertices[..], poly_faces[..], poly_edges[..], 1.0e-9f64, 64usize)
            if epa_error != ok { os.exit(7i32) }
            if !near(depth, least, 1.0e-6f64) { os.exit(7i32) }
            // A unit vector whose components sum to one in magnitude is an axis.
            var axis_sum = 0.0f64
            axis = 0usize
            while axis < 3usize {
                var c = g.component(normal, axis)
                if c < 0.0f64 { c = 0.0f64 - c }
                axis_sum += c
                axis += 1usize
            }
            if !near(g.length(normal), 1.0f64, 1.0e-9f64) || !near(axis_sum, 1.0f64, 1.0e-6f64) { os.exit(7i32) }
            depth_sum += depth
        }
        i += 1usize
    }
    if overlaps != 18usize || !near(depth_sum, 228.65f64, 1.0e-6f64) { os.exit(7i32) }

    // 7: Barnes-Hut over 200 masses: exact at theta 0, within 2% at theta 0.5.
    var xs: [200]f64 = zero
    var ys: [200]f64 = zero
    var zs: [200]f64 = zero
    var masses: [200]f64 = zero
    i = 0usize
    while i < 200usize {
        let p = draw3(&state)
        xs[i] = p.x
        ys[i] = p.y
        zs[i] = p.z
        i += 1usize
    }
    i = 0usize
    while i < 200usize {
        masses[i] = 1.0f64 + draw(&state) / 100.0f64
        i += 1usize
    }
    var child: [32768]u32 = zero
    var body: [4096]u32 = zero
    var node_mass: [4096]f64 = zero
    var cx: [4096]f64 = zero
    var cy: [4096]f64 = zero
    var cz: [4096]f64 = zero
    let (tree, tree_error) = g.barnes_hut_build(xs[..], ys[..], zs[..], masses[..], child[..], body[..], node_mass[..], cx[..], cy[..], cz[..])
    if tree_error != ok || tree.used != 865usize { os.exit(8i32) }
    var exact_sum = 0.0f64
    var rough_sum = 0.0f64
    var error_sum = 0.0f64
    i = 0usize
    while i < 200usize {
        let exact = g.barnes_hut_force(&tree, i, 0.0f64)
        let rough = g.barnes_hut_force(&tree, i, 0.5f64)
        exact_sum += g.length(exact)
        rough_sum += g.length(rough)
        error_sum += g.length(g.sub(rough, exact))
        i += 1usize
    }
    if !near(exact_sum, 23.754500023f64, 1.0e-6f64) || !near(rough_sum, 23.765609021f64, 1.0e-6f64) { os.exit(8i32) }
    if error_sum > 0.02f64 * exact_sum { os.exit(8i32) }

    // 8: Kabsch: a cyclic permutation plus translation and noise, RMSD as scipy.
    var p: [20]g.Vec3 = zero
    var q: [20]g.Vec3 = zero
    i = 0usize
    while i < 20usize {
        p[i] = draw3(&state)
        i += 1usize
    }
    i = 0usize
    while i < 20usize {
        let noise = g.sub(g.scale(draw3(&state), 0.001f64), g.scale(one3, 0.05f64))
        q[i] = g.add(g.add(g.vec3(p[i].z, p[i].x, p[i].y), g.vec3(1.0f64, 2.0f64, 3.0f64)), noise)
        i += 1usize
    }
    var rotation: [9]f64 = zero
    let (translation, kabsch_error) = g.kabsch(p[..], q[..], rotation[..])
    if kabsch_error != ok || !near(rotation[2usize], 1.0f64, 1.0e-3f64) || !near(rotation[3usize], 1.0f64, 1.0e-3f64) || !near(rotation[7usize], 1.0f64, 1.0e-3f64) { os.exit(9i32) }
    if !near(translation.x, 1.016226f64, 1.0e-5f64) || !near(translation.y, 2.000618f64, 1.0e-5f64) || !near(translation.z, 2.982846f64, 1.0e-5f64) { os.exit(9i32) }
    if !near(g.kabsch_rmsd(p[..], q[..], rotation[..], translation), 0.050505426f64, 1.0e-6f64) { os.exit(9i32) }
    let (_, empty_error) = g.kabsch(p[..0usize], q[..0usize], rotation[..])
    if empty_error != g.Invalid { os.exit(9i32) }

    // 9: quickhull of 100 points against scipy; a cube; degenerate inputs.
    var cloud: [100]g.Vec3 = zero
    i = 0usize
    while i < 100usize {
        cloud[i] = draw3(&state)
        i += 1usize
    }
    var hull_faces: [600]u32 = zero
    var hull_edges: [600]u32 = zero
    let (face_count, hull_error) = g.hull(cloud[..], hull_faces[..], hull_edges[..], 1.0e-9f64)
    if hull_error != ok || face_count != 68usize { os.exit(10i32) }
    if !near(g.hull_volume(cloud[..], hull_faces[..], face_count), 672516.903f64, 1.0e-3f64) { os.exit(10i32) }
    if !near(g.hull_area(cloud[..], hull_faces[..], face_count), 41292.322377852f64, 1.0e-4f64) { os.exit(10i32) }
    box_corners(zero3, one3, box_a[..])
    let (cube_count, cube_error) = g.hull(box_a[..], hull_faces[..], hull_edges[..], 1.0e-9f64)
    if cube_error != ok || cube_count != 12usize || !near(g.hull_volume(box_a[..], hull_faces[..], cube_count), 1.0f64, 1.0e-12f64) { os.exit(11i32) }
    if !near(g.hull_area(box_a[..], hull_faces[..], cube_count), 6.0f64, 1.0e-12f64) { os.exit(11i32) }
    let (_, flat_error) = g.hull(box_a[..4usize], hull_faces[..], hull_edges[..], 1.0e-9f64)
    let (_, few_error) = g.hull(box_a[..3usize], hull_faces[..], hull_edges[..], 1.0e-9f64)
    if flat_error != g.Invalid || few_error != g.Invalid { os.exit(11i32) }

    try io.print("algo geom3 ok\n")
    ret ok
}
