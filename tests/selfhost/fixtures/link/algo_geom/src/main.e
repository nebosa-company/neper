// `e.algo.geom` and `e.algo.geom.clip`: orientation and in-circle predicates,
// segment intersection with touching cases, area, convexity and containment of
// a concave polygon, the two hulls agreeing on a point set with interior
// points, closest and farthest pairs, the smallest enclosing circle and
// bounding rectangle, Pick's count and Morton round trips; then clipping a
// polygon and lines to a window by both algorithms, ear clipping a concave
// polygon into triangles of the right total area, and the two simplifiers.
// Each check exits with its own code.

use e.algo.geom
use e.algo.geom.clip
use e.io
use e.mem
use e.os

fn near(x: f64, want: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < 0.000001f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let o = geom.point(0.0f64, 0.0f64)
    let px = geom.point(4.0f64, 0.0f64)
    let py = geom.point(0.0f64, 3.0f64)
    let far = geom.point(4.0f64, 3.0f64)

    // 1: predicates and segment intersection.
    if geom.orient(o, px, py) <= 0.0f64 || geom.orient(o, py, px) >= 0.0f64 || geom.orient(o, px, geom.point(8.0f64, 0.0f64)) != 0.0f64 { os.exit(1i32) }
    if !geom.in_circle(o, px, far, geom.point(2.0f64, 1.0f64)) || geom.in_circle(o, px, far, geom.point(9.0f64, 9.0f64)) { os.exit(1i32) }
    if !geom.segments_intersect(o, far, px, py) || geom.segments_intersect(o, px, py, far) { os.exit(1i32) }
    // Touching at an endpoint and collinear overlap both count.
    if !geom.segments_intersect(o, px, px, far) || !geom.segments_intersect(o, px, geom.point(2.0f64, 0.0f64), geom.point(9.0f64, 0.0f64)) { os.exit(1i32) }
    let (cross, crossed) = geom.segment_intersection(o, far, px, py)
    if !crossed || !near(cross.x, 2.0f64) || !near(cross.y, 1.5f64) { os.exit(1i32) }
    let (_, parallel) = geom.segment_intersection(o, px, py, far)
    if parallel { os.exit(1i32) }
    if !near(geom.distance_squared(o, far), 25.0f64) { os.exit(1i32) }

    // 2: polygons: area, convexity, containment.
    var star: [5]geom.Point = zero
    star[0usize] = geom.point(0.0f64, 0.0f64)
    star[1usize] = geom.point(6.0f64, 0.0f64)
    star[2usize] = geom.point(6.0f64, 4.0f64)
    star[3usize] = geom.point(3.0f64, 2.0f64)
    star[4usize] = geom.point(0.0f64, 4.0f64)
    if !near(geom.polygon_area(star[..]), 18.0f64) || geom.is_convex(star[..]) { os.exit(2i32) }
    var box: [4]geom.Point = zero
    box[0usize] = o
    box[1usize] = px
    box[2usize] = far
    box[3usize] = py
    if !near(geom.polygon_area(box[..]), 12.0f64) || !geom.is_convex(box[..]) { os.exit(2i32) }
    var reversed: [4]geom.Point = zero
    reversed[0usize] = py
    reversed[1usize] = far
    reversed[2usize] = px
    reversed[3usize] = o
    if !near(geom.polygon_area(reversed[..]), 0.0f64 - 12.0f64) || !geom.is_convex(reversed[..]) { os.exit(2i32) }
    if !geom.point_in_polygon(star[..], geom.point(1.0f64, 1.0f64)) || geom.point_in_polygon(star[..], geom.point(3.0f64, 3.5f64)) { os.exit(2i32) }
    if !geom.point_in_polygon(star[..], geom.point(3.0f64, 0.0f64)) || geom.point_in_polygon(star[..], geom.point(7.0f64, 1.0f64)) { os.exit(2i32) }
    if geom.winding_number(star[..], geom.point(1.0f64, 1.0f64)) != 1i32 || geom.winding_number(star[..], geom.point(3.0f64, 3.5f64)) != 0i32 { os.exit(2i32) }
    if geom.winding_number(reversed[..], geom.point(1.0f64, 1.0f64)) != 0i32 - 1i32 { os.exit(2i32) }

    // 3: hulls over a set with interior points.
    var cloud: [8]geom.Point = zero
    cloud[0usize] = geom.point(2.0f64, 1.0f64)
    cloud[1usize] = far
    cloud[2usize] = geom.point(1.0f64, 2.0f64)
    cloud[3usize] = o
    cloud[4usize] = geom.point(3.0f64, 1.0f64)
    cloud[5usize] = py
    cloud[6usize] = geom.point(2.0f64, 2.0f64)
    cloud[7usize] = px
    var jarvis_out: [8]geom.Point = zero
    let (jarvis_count, jarvis_error) = geom.hull_jarvis(cloud[..], jarvis_out[..])
    if jarvis_error != ok || jarvis_count != 4usize { os.exit(3i32) }
    var chain_out: [9]geom.Point = zero
    let (chain_count, chain_error) = geom.hull(cloud[..], chain_out[..])
    if chain_error != ok || chain_count != 4usize { os.exit(3i32) }
    if !near(geom.polygon_area(chain_out[..chain_count]), 12.0f64) || !near(geom.polygon_area(jarvis_out[..jarvis_count]), 12.0f64) { os.exit(3i32) }
    if !geom.is_convex(chain_out[..chain_count]) || chain_out[0usize].x != 0.0f64 || chain_out[0usize].y != 0.0f64 { os.exit(3i32) }
    let (_, chain_room) = geom.hull(cloud[..], chain_out[..8usize])
    if chain_room != geom.TooSmall { os.exit(3i32) }
    // Collinear points along an edge are dropped.
    var line: [4]geom.Point = zero
    line[0usize] = o
    line[1usize] = geom.point(1.0f64, 0.0f64)
    line[2usize] = geom.point(2.0f64, 0.0f64)
    line[3usize] = geom.point(1.0f64, 1.0f64)
    var tri_out: [5]geom.Point = zero
    let (tri_count, tri_error) = geom.hull(line[..], tri_out[..])
    if tri_error != ok || tri_count != 3usize { os.exit(3i32) }

    // 4: closest and farthest pairs, the enclosing circle and rectangle.
    let (ca, cb, closest, closest_error) = geom.closest_pair(cloud[..])
    if closest_error != ok || !near(closest, 1.0f64) || ca == cb { os.exit(4i32) }
    let (fa, fb, farthest, farthest_error) = geom.farthest_pair(chain_out[..chain_count])
    if farthest_error != ok || !near(farthest, 25.0f64) || fa == fb { os.exit(4i32) }
    let circle = geom.enclosing_circle(cloud[..])
    if !near(circle.center.x, 2.0f64) || !near(circle.center.y, 1.5f64) || !near(circle.radius, 2.5f64) { os.exit(4i32) }
    let lone = geom.enclosing_circle(cloud[..1usize])
    if lone.radius != 0.0f64 || lone.center.x != cloud[0usize].x || lone.center.y != cloud[0usize].y { os.exit(4i32) }
    var corners: [4]geom.Point = zero
    let (rect_area, rect_error) = geom.min_bounding_rect(chain_out[..chain_count], corners[..])
    if rect_error != ok || !near(rect_area, 12.0f64) { os.exit(4i32) }
    let (_, rect_room) = geom.min_bounding_rect(chain_out[..chain_count], corners[..3usize])
    if rect_room != geom.TooSmall { os.exit(4i32) }

    // 5: Pick's theorem and Morton codes.
    let (interior, boundary) = geom.lattice_points(box[..])
    if interior != 6i64 || boundary != 14i64 { os.exit(5i32) }
    let (star_interior, star_boundary) = geom.lattice_points(star[..])
    // Area 18 = I + B/2 - 1 with B = 6 + 4 + 1 + 1 + 4 = 16, so I = 11.
    if star_boundary != 16i64 || star_interior != 11i64 { os.exit(5i32) }
    if geom.morton_encode(0u32, 0u32) != 0u64 || geom.morton_encode(1u32, 0u32) != 1u64 || geom.morton_encode(0u32, 1u32) != 2u64 || geom.morton_encode(3u32, 3u32) != 15u64 { os.exit(5i32) }
    var v = 0u32
    while v < 200u32 {
        let (x, y) = geom.morton_decode(geom.morton_encode(v * 7919u32, v * 104729u32))
        if x != v * 7919u32 || y != v * 104729u32 { os.exit(5i32) }
        v += 1u32
    }
    let (x_max, y_max) = geom.morton_decode(geom.morton_encode(4294967295u32, 4294967295u32))
    if x_max != 4294967295u32 || y_max != 4294967295u32 { os.exit(5i32) }
    if geom.morton_encode(4294967295u32, 4294967295u32) != 18446744073709551615u64 { os.exit(5i32) }

    // 6: clipping.
    var window: [4]geom.Point = zero
    window[0usize] = geom.point(1.0f64, 1.0f64)
    window[1usize] = geom.point(5.0f64, 1.0f64)
    window[2usize] = geom.point(5.0f64, 3.0f64)
    window[3usize] = geom.point(1.0f64, 3.0f64)
    var clipped: [16]geom.Point = zero
    var scratch: [16]geom.Point = zero
    let (clip_count, clip_error) = clip.clip_convex(star[..], window[..], clipped[..], scratch[..])
    if clip_error != ok || clip_count < 4usize { os.exit(6i32) }
    // The window has area 8; the notch's tip (3,2) is inside it and its edges cross
    // y = 3 at x = 1.5 and 4.5, so the clipped polygon loses that triangle: 6.5.
    if !near(geom.polygon_area(clipped[..clip_count]), 6.5f64) { os.exit(6i32) }
    let (outside_count, outside_error) = clip.clip_convex(star[..], window[..], clipped[..], scratch[..])
    if outside_error != ok || outside_count != clip_count { os.exit(6i32) }
    var far_window: [4]geom.Point = zero
    far_window[0usize] = geom.point(10.0f64, 10.0f64)
    far_window[1usize] = geom.point(12.0f64, 10.0f64)
    far_window[2usize] = geom.point(12.0f64, 12.0f64)
    far_window[3usize] = geom.point(10.0f64, 12.0f64)
    let (none_count, none_error) = clip.clip_convex(star[..], far_window[..], clipped[..], scratch[..])
    if none_error != ok || none_count != 0usize { os.exit(6i32) }
    let (_, clip_room) = clip.clip_convex(star[..], window[..], clipped[..4usize], scratch[..])
    if clip_room != clip.TooSmall { os.exit(6i32) }
    let r = clip.Rect { min: geom.point(1.0f64, 1.0f64), max: geom.point(5.0f64, 3.0f64) }
    let (c1, c2, kept) = clip.clip_line(r, geom.point(0.0f64, 0.0f64), geom.point(6.0f64, 4.0f64))
    if !kept || !near(c1.x, 1.5f64) || !near(c1.y, 1.0f64) || !near(c2.x, 4.5f64) || !near(c2.y, 3.0f64) { os.exit(6i32) }
    let (l1, l2, kept_lb) = clip.clip_line_liang_barsky(r, geom.point(0.0f64, 0.0f64), geom.point(6.0f64, 4.0f64))
    if !kept_lb || !near(l1.x, c1.x) || !near(l1.y, c1.y) || !near(l2.x, c2.x) || !near(l2.y, c2.y) { os.exit(6i32) }
    let (_, _, missed) = clip.clip_line(r, geom.point(0.0f64, 4.0f64), geom.point(6.0f64, 4.0f64))
    let (_, _, missed_lb) = clip.clip_line_liang_barsky(r, geom.point(0.0f64, 4.0f64), geom.point(6.0f64, 4.0f64))
    if missed || missed_lb { os.exit(6i32) }
    let (i1, i2, inside) = clip.clip_line(r, geom.point(2.0f64, 2.0f64), geom.point(3.0f64, 2.5f64))
    if !inside || i1.x != 2.0f64 || i2.y != 2.5f64 { os.exit(6i32) }

    // 7: ear clipping of the concave star, in both windings.
    var triangles: [9]usize = zero
    var ring: [5]usize = zero
    let (written, ear_error) = clip.triangulate_ear_clip(star[..], triangles[..], ring[..])
    if ear_error != ok || written != 9usize { os.exit(7i32) }
    var total = 0.0f64
    var t = 0usize
    while t < 9usize {
        let area = geom.orient(star[triangles[t]], star[triangles[t + 1usize]], star[triangles[t + 2usize]]) / 2.0f64
        if area <= 0.0f64 { os.exit(7i32) }
        total += area
        t += 3usize
    }
    if !near(total, 18.0f64) { os.exit(7i32) }
    var star_cw: [5]geom.Point = zero
    var k = 0usize
    while k < 5usize {
        star_cw[k] = star[4usize - k]
        k += 1usize
    }
    let (written_cw, ear_cw_error) = clip.triangulate_ear_clip(star_cw[..], triangles[..], ring[..])
    if ear_cw_error != ok || written_cw != 9usize { os.exit(7i32) }
    let (_, ear_room) = clip.triangulate_ear_clip(star[..], triangles[..6usize], ring[..])
    if ear_room != clip.TooSmall { os.exit(7i32) }
    let (_, ear_invalid) = clip.triangulate_ear_clip(star[..2usize], triangles[..], ring[..])
    if ear_invalid != clip.Invalid { os.exit(7i32) }

    // 8: simplification keeps the corners of a noisy polyline.
    var path: [9]geom.Point = zero
    path[0usize] = geom.point(0.0f64, 0.0f64)
    path[1usize] = geom.point(1.0f64, 0.1f64)
    path[2usize] = geom.point(2.0f64, 0.0f64 - 0.1f64)
    path[3usize] = geom.point(3.0f64, 0.05f64)
    path[4usize] = geom.point(4.0f64, 0.0f64)
    path[5usize] = geom.point(4.0f64, 3.0f64)
    path[6usize] = geom.point(4.05f64, 6.0f64)
    path[7usize] = geom.point(4.0f64, 9.0f64)
    path[8usize] = geom.point(4.0f64, 12.0f64)
    var keep: [9]u8 = zero
    var stack: [18]usize = zero
    if clip.simplify_douglas_peucker(path[..], 0.5f64, keep[..], stack[..]) != ok { os.exit(8i32) }
    if keep[0usize] != 1u8 || keep[4usize] != 1u8 || keep[8usize] != 1u8 { os.exit(8i32) }
    var kept_count = 0usize
    k = 0usize
    while k < 9usize {
        if keep[k] == 1u8 { kept_count += 1usize }
        k += 1usize
    }
    if kept_count != 3usize { os.exit(8i32) }
    if clip.simplify_douglas_peucker(path[..], 0.01f64, keep[..], stack[..]) != ok { os.exit(8i32) }
    kept_count = 0usize
    k = 0usize
    while k < 9usize {
        if keep[k] == 1u8 { kept_count += 1usize }
        k += 1usize
    }
    if kept_count < 7usize { os.exit(8i32) }
    if clip.simplify_douglas_peucker(path[..], 0.5f64, keep[..], stack[..4usize]) != clip.TooSmall { os.exit(8i32) }
    if clip.simplify_visvalingam(path[..], 0.5f64, keep[..]) != ok { os.exit(8i32) }
    if keep[0usize] != 1u8 || keep[4usize] != 1u8 || keep[8usize] != 1u8 { os.exit(8i32) }
    kept_count = 0usize
    k = 0usize
    while k < 9usize {
        if keep[k] == 1u8 { kept_count += 1usize }
        k += 1usize
    }
    if kept_count != 3usize { os.exit(8i32) }

    try io.print("algo geom ok\n")
    ret ok
}
