// `e.algo.geom` extensions: the Delaunay of 40 LCG points matching scipy's
// triangle set and Voronoi vertex sums; Graham and quickhull agreeing with the
// monotone chain; Lawson flips turning a fan into the Delaunay of the hull; a
// constrained edge forced in; calipers width and diameter; the largest empty
// circle; Voronoi cells clipped to a box (areas, centroids and Lloyd against a
// half-plane replica); a Minkowski sum against the hull of pairwise sums;
// Greiner-Hormann booleans against sampled membership; miter offsets against a
// closed form; pairwise segment crossings; monotone triangulation; and convex
// clipping. Each check exits with its own code.

use e.algo.geom
use e.io
use e.mem
use e.os

fn draw(state: *u64) -> f64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64((*state >> 33u32) % 100000u64) / 1000.0f64
}

fn near(x: f64, want: f64, tolerance: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d < tolerance
}

// An order-independent fold over sorted index triples, replicated in Python.
fn tri_fold(triangles: []const usize, written: usize) -> u64 {
    var h = 0u64
    var t = 0usize
    while t + 2usize < written {
        var a = triangles[t]
        var b = triangles[t + 1usize]
        var c = triangles[t + 2usize]
        if a > b {
            let s = a
            a = b
            b = s
        }
        if b > c {
            let s = b
            b = c
            c = s
        }
        if a > b {
            let s = a
            a = b
            b = s
        }
        let k = (u64(a) * 64u64 + u64(b)) * 64u64 + u64(c)
        h = h +% (k *% k *% 2654435761u64 +% k)
        t += 3usize
    }
    ret h
}

fn same_points(a: []const geom.Point, b: []const geom.Point) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i].x != b[i].x || a[i].y != b[i].y { ret false }
        i += 1usize
    }
    ret true
}

fn has_edge(triangles: []const usize, written: usize, a: usize, b: usize) -> bool {
    var t = 0usize
    while t + 2usize < written {
        var hits = 0usize
        var k = 0usize
        while k < 3usize {
            if triangles[t + k] == a || triangles[t + k] == b { hits += 1usize }
            k += 1usize
        }
        if hits == 2usize { ret true }
        t += 3usize
    }
    ret false
}

fn main(a: *mem.Arena, args: []str) -> err {
    var state = 12345u64
    var pts: [40]geom.Point = zero
    var i = 0usize
    while i < 40usize {
        let x = draw(&state)
        let y = draw(&state)
        pts[i] = geom.point(x, y)
        i += 1usize
    }
    var star: [5]geom.Point = zero
    star[0usize] = geom.point(0.0f64, 0.0f64)
    star[1usize] = geom.point(6.0f64, 0.0f64)
    star[2usize] = geom.point(6.0f64, 4.0f64)
    star[3usize] = geom.point(3.0f64, 2.0f64)
    star[4usize] = geom.point(0.0f64, 4.0f64)

    // 1: Delaunay of 40 points and its Voronoi vertices against scipy.
    var tris: [240]usize = zero
    var tri_scratch: [240]usize = zero
    let (written, de) = geom.delaunay(pts[..], tris[..], tri_scratch[..])
    if de != ok || written != 207usize { os.exit(1i32) }
    if tri_fold(tris[..], written) != 15184427156052135426u64 { os.exit(1i32) }
    var sx = 0.0f64
    var sy = 0.0f64
    var t = 0usize
    while t < written {
        let c = geom.circumcircle(pts[tris[t]], pts[tris[t + 1usize]], pts[tris[t + 2usize]])
        sx += c.center.x
        sy += c.center.y
        t += 3usize
    }
    if !near(sx, 3287.575921574679f64, 0.000001f64) || !near(sy, 2661.3146428190857f64, 0.000001f64) { os.exit(1i32) }
    let (_, small) = geom.delaunay(pts[..], tris[..100usize], tri_scratch[..])
    if small != geom.TooSmall { os.exit(1i32) }
    let (_, flat) = geom.delaunay(star[..2usize], tris[..], tri_scratch[..])
    if flat != geom.Invalid { os.exit(1i32) }

    // 2: the three hulls agree.
    var sorted: [40]geom.Point = zero
    i = 0usize
    while i < 40usize {
        sorted[i] = pts[i]
        i += 1usize
    }
    var chain: [41]geom.Point = zero
    let (hn, he) = geom.hull(sorted[..], chain[..])
    if he != ok || hn != 9usize || chain[0usize].x != 0.343f64 || chain[0usize].y != 6.767f64 { os.exit(2i32) }
    i = 0usize
    while i < 40usize {
        sorted[i] = pts[i]
        i += 1usize
    }
    var graham: [40]geom.Point = zero
    let (gn, ge) = geom.hull_graham(sorted[..], graham[..])
    if ge != ok || gn != 9usize || !same_points(chain[..9usize], graham[..9usize]) { os.exit(2i32) }
    var quick: [40]geom.Point = zero
    let (qn, qe) = geom.hull_quick(pts[..], quick[..])
    if qe != ok || qn != 9usize || !same_points(chain[..9usize], quick[..9usize]) { os.exit(2i32) }
    let (_, graham_room) = geom.hull_graham(sorted[..], graham[..30usize])
    let (_, quick_room) = geom.hull_quick(pts[..], quick[..30usize])
    if graham_room != geom.TooSmall || quick_room != geom.TooSmall { os.exit(2i32) }

    // 3: Lawson flips turn a fan of the hull into its Delaunay.
    var fan: [21]usize = zero
    i = 1usize
    while i + 1usize < 9usize {
        fan[3usize * (i - 1usize)] = 0usize
        fan[3usize * (i - 1usize) + 1usize] = i
        fan[3usize * (i - 1usize) + 2usize] = i + 1usize
        i += 1usize
    }
    let flips = geom.delaunay_flip(chain[..9usize], fan[..], 21usize)
    if flips == 0usize || tri_fold(fan[..], 21usize) != 2843223553743810380u64 { os.exit(3i32) }
    if geom.delaunay_flip(chain[..9usize], fan[..], 21usize) != 0usize { os.exit(3i32) }

    // 4: the edge 0-1 forced into the triangulation.
    if has_edge(tris[..], written, 0usize, 1usize) { os.exit(4i32) }
    var constraint: [2]usize = zero
    constraint[1usize] = 1usize
    if geom.delaunay_constrained(pts[..], tris[..], written, constraint[..]) != ok { os.exit(4i32) }
    if !has_edge(tris[..], written, 0usize, 1usize) || tri_fold(tris[..], written) != 13402319167904438286u64 { os.exit(4i32) }
    let (again, de2) = geom.delaunay(pts[..], tris[..], tri_scratch[..])
    if de2 != ok || again != written || tri_fold(tris[..], written) != 15184427156052135426u64 { os.exit(4i32) }

    // 5: calipers width and diameter against numpy.
    let (width, diameter, ce) = geom.rotating_calipers(chain[..9usize])
    if ce != ok || !near(width, 93.34595433902557f64, 0.000001f64) || !near(diameter, 134.62756165065161f64, 0.000001f64) { os.exit(5i32) }
    let (_, _, calipers_invalid) = geom.rotating_calipers(chain[..2usize])
    if calipers_invalid != geom.Invalid { os.exit(5i32) }

    // 6: the largest empty circle.
    let (empty, ee) = geom.largest_empty_circle(pts[..], tris[..], written)
    if ee != ok || !near(empty.center.x, 36.37934362211776f64, 0.000001f64) || !near(empty.center.y, 82.32246449607841f64, 0.000001f64) { os.exit(6i32) }
    if !near(empty.radius, 24.049974794952853f64, 0.000001f64) { os.exit(6i32) }

    // 7: Voronoi cells clipped to [0,100]^2 against a half-plane replica, then Lloyd.
    var cells: [480]geom.Point = zero
    var starts: [41]usize = zero
    var cell_scratch: [240]geom.Point = zero
    let lo = geom.point(0.0f64, 0.0f64)
    let hi = geom.point(100.0f64, 100.0f64)
    if geom.voronoi_from_delaunay(pts[..], tris[..], written, lo, hi, cells[..], starts[..], cell_scratch[..]) != ok { os.exit(7i32) }
    if starts[40usize] != 218usize { os.exit(7i32) }
    var total = 0.0f64
    var fold = 0.0f64
    var cx = 0.0f64
    var cy = 0.0f64
    var cxi = 0.0f64
    i = 0usize
    while i < 40usize {
        let cell = cells[starts[i]..starts[i + 1usize]]
        let area = geom.polygon_area(cell)
        total += area
        fold += area * f64(i + 1usize)
        let c = geom.polygon_centroid(cell)
        cx += c.x
        cy += c.y
        cxi += c.x * f64(i + 1usize)
        i += 1usize
    }
    if !near(total, 10000.0f64, 0.000001f64) || !near(fold, 219214.81712587926f64, 0.0001f64) { os.exit(7i32) }
    if !near(cx, 2156.475631793937f64, 0.00001f64) || !near(cy, 1968.2541358442295f64, 0.00001f64) || !near(cxi, 45295.34823098784f64, 0.0001f64) { os.exit(7i32) }
    var cells2: [480]geom.Point = zero
    var starts2: [41]usize = zero
    if geom.voronoi(pts[..], lo, hi, cells2[..], starts2[..], tris[..], tri_scratch[..], cell_scratch[..]) != ok { os.exit(7i32) }
    if starts2[40usize] != 218usize || !same_points(cells[..218usize], cells2[..218usize]) { os.exit(7i32) }
    var moved: [40]geom.Point = zero
    var lloyd_scratch: [512]geom.Point = zero
    if geom.lloyd_relax(pts[..], lo, hi, moved[..], tris[..], tri_scratch[..], lloyd_scratch[..]) != ok { os.exit(7i32) }
    var mx = 0.0f64
    var my = 0.0f64
    i = 0usize
    while i < 40usize {
        mx += moved[i].x
        my += moved[i].y
        i += 1usize
    }
    if !near(mx, cx, 0.000000001f64) || !near(my, cy, 0.000000001f64) { os.exit(7i32) }

    // 8: the Minkowski sum of two hulls against the hull of all pairwise sums.
    var pa: [8]geom.Point = zero
    var pb: [8]geom.Point = zero
    i = 0usize
    while i < 8usize {
        let x = draw(&state)
        let y = draw(&state)
        pa[i] = geom.point(x, y)
        i += 1usize
    }
    i = 0usize
    while i < 8usize {
        let x = draw(&state) / 4.0f64
        let y = draw(&state) / 4.0f64
        pb[i] = geom.point(x, y)
        i += 1usize
    }
    var ha: [9]geom.Point = zero
    var hb: [9]geom.Point = zero
    let (han, hae) = geom.hull(pa[..], ha[..])
    let (hbn, hbe) = geom.hull(pb[..], hb[..])
    if hae != ok || hbe != ok || han != 6usize || hbn != 6usize { os.exit(8i32) }
    var mink: [12]geom.Point = zero
    let (mn, me) = geom.minkowski_sum(ha[..han], hb[..hbn], mink[..])
    if me != ok || mn != 12usize || !geom.is_convex(mink[..mn]) || !near(geom.polygon_area(mink[..mn]), 4270.756951750001f64, 0.000001f64) { os.exit(8i32) }
    if !near(mink[0usize].x, 49.594f64, 0.000000001f64) || !near(mink[0usize].y, 10.1275f64, 0.000000001f64) { os.exit(8i32) }
    let (_, concave) = geom.minkowski_sum(star[..], hb[..hbn], mink[..])
    if concave != geom.Invalid { os.exit(8i32) }

    // 9: Greiner-Hormann booleans of the star and a box.
    var box: [4]geom.Point = zero
    box[0usize] = geom.point(2.0f64, 1.0f64)
    box[1usize] = geom.point(7.0f64, 1.0f64)
    box[2usize] = geom.point(7.0f64, 3.0f64)
    box[3usize] = geom.point(2.0f64, 3.0f64)
    var bout: [64]geom.Point = zero
    var bstarts: [8]usize = zero
    var nodes: [64]geom.Node = zero
    let (union_count, union_error) = geom.polygon_boolean(star[..], box[..], .Union, bout[..], bstarts[..], nodes[..])
    if union_error != ok || union_count != 1usize || bstarts[1usize] != 11usize { os.exit(9i32) }
    if !near(geom.polygon_area(bout[..11usize]), 21.416666666666664f64, 0.000000001f64) { os.exit(9i32) }
    let (inter_count, inter_error) = geom.polygon_boolean(star[..], box[..], .Intersection, bout[..], bstarts[..], nodes[..])
    if inter_error != ok || inter_count != 1usize || bstarts[1usize] != 6usize { os.exit(9i32) }
    if !near(geom.polygon_area(bout[..6usize]), 6.583333333333334f64, 0.000000001f64) { os.exit(9i32) }
    let (diff_count, diff_error) = geom.polygon_boolean(star[..], box[..], .Difference, bout[..], bstarts[..], nodes[..])
    if diff_error != ok || diff_count != 2usize || bstarts[2usize] != 9usize { os.exit(9i32) }
    let diff_area = geom.polygon_area(bout[bstarts[0usize]..bstarts[1usize]]) + geom.polygon_area(bout[bstarts[1usize]..bstarts[2usize]])
    if !near(diff_area, 11.416666666666666f64, 0.000000001f64) || geom.polygon_area(bout[..bstarts[1usize]]) <= 0.0f64 { os.exit(9i32) }
    // A bar through the box splits the difference in two.
    var bar: [4]geom.Point = zero
    bar[0usize] = geom.point(4.0f64, 0.0f64)
    bar[1usize] = geom.point(5.0f64, 0.0f64)
    bar[2usize] = geom.point(5.0f64, 5.0f64)
    bar[3usize] = geom.point(4.0f64, 5.0f64)
    let (bar_count, bar_error) = geom.polygon_boolean(box[..], bar[..], .Difference, bout[..], bstarts[..], nodes[..])
    if bar_error != ok || bar_count != 2usize || bstarts[2usize] != 8usize { os.exit(9i32) }
    if !near(geom.polygon_area(bout[..4usize]) + geom.polygon_area(bout[4usize..8usize]), 8.0f64, 0.000000001f64) { os.exit(9i32) }
    // A triangle sharing part of an edge is degenerate.
    var wedge: [3]geom.Point = zero
    wedge[0usize] = geom.point(6.0f64, 0.0f64)
    wedge[1usize] = geom.point(8.0f64, 0.0f64)
    wedge[2usize] = geom.point(8.0f64, 2.0f64)
    let (_, degenerate) = geom.polygon_boolean(star[..], wedge[..], .Union, bout[..], bstarts[..], nodes[..])
    if degenerate != geom.Invalid { os.exit(9i32) }
    // Disjoint polygons: a union of both, an empty intersection, the difference unchanged.
    var apart: [4]geom.Point = zero
    apart[0usize] = geom.point(10.0f64, 10.0f64)
    apart[1usize] = geom.point(12.0f64, 10.0f64)
    apart[2usize] = geom.point(12.0f64, 12.0f64)
    apart[3usize] = geom.point(10.0f64, 12.0f64)
    let (apart_union, apart_union_error) = geom.polygon_boolean(star[..], apart[..], .Union, bout[..], bstarts[..], nodes[..])
    if apart_union_error != ok || apart_union != 2usize || bstarts[2usize] != 9usize { os.exit(9i32) }
    let (apart_inter, apart_inter_error) = geom.polygon_boolean(star[..], apart[..], .Intersection, bout[..], bstarts[..], nodes[..])
    if apart_inter_error != ok || apart_inter != 0usize { os.exit(9i32) }
    let (apart_diff, apart_diff_error) = geom.polygon_boolean(star[..], apart[..], .Difference, bout[..], bstarts[..], nodes[..])
    if apart_diff_error != ok || apart_diff != 1usize || !near(geom.polygon_area(bout[..5usize]), 18.0f64, 0.000000001f64) { os.exit(9i32) }
    let (_, boolean_room) = geom.polygon_boolean(star[..], box[..], .Union, bout[..], bstarts[..], nodes[..9usize])
    if boolean_room != geom.TooSmall { os.exit(9i32) }

    // 10: miter offsets against the closed form and a replica.
    var off: [9]geom.Point = zero
    let (on, oe) = geom.polygon_offset(chain[..9usize], 2.0f64, off[..])
    if oe != ok || on != 9usize || !near(geom.polygon_area(off[..9usize]), 9220.470503301913f64, 0.000001f64) { os.exit(10i32) }
    let (inset_count, inset_error) = geom.polygon_offset(star[..], 0.0f64 - 0.25f64, off[..])
    if inset_error != ok || inset_count != 5usize || !near(geom.polygon_area(off[..5usize]), 13.014122332079005f64, 0.000000001f64) { os.exit(10i32) }
    if !near(off[0usize].x, 0.25f64, 0.000000000001f64) || !near(off[0usize].y, 0.25f64, 0.000000000001f64) { os.exit(10i32) }
    let (_, offset_room) = geom.polygon_offset(star[..], 1.0f64, off[..4usize])
    if offset_room != geom.TooSmall { os.exit(10i32) }

    // 11: pairwise segment crossings of 20 LCG segments.
    var segs: [40]geom.Point = zero
    i = 0usize
    while i < 40usize {
        let x = draw(&state)
        let y = draw(&state)
        segs[i] = geom.point(x, y)
        i += 1usize
    }
    var pairs: [400]usize = zero
    var crossings: [200]geom.Point = zero
    let (crossing_count, crossing_error) = geom.segment_intersections(segs[..], pairs[..], crossings[..])
    if crossing_error != ok || crossing_count != 43usize || pairs[0usize] >= pairs[1usize] { os.exit(11i32) }
    sx = 0.0f64
    sy = 0.0f64
    i = 0usize
    while i < crossing_count {
        sx += crossings[i].x
        sy += crossings[i].y
        i += 1usize
    }
    if !near(sx, 2489.328540761988f64, 0.000001f64) || !near(sy, 1978.3929836624386f64, 0.000001f64) { os.exit(11i32) }
    let (_, crossing_room) = geom.segment_intersections(segs[..], pairs[..4usize], crossings[..])
    if crossing_room != geom.TooSmall { os.exit(11i32) }

    // 12: monotone triangulation of a zigzag against the replica.
    var mono: [11]geom.Point = zero
    mono[0usize] = geom.point(5.0f64, 10.0f64)
    mono[1usize] = geom.point(3.0f64, 8.0f64)
    mono[2usize] = geom.point(4.0f64, 6.0f64)
    mono[3usize] = geom.point(2.0f64, 4.0f64)
    mono[4usize] = geom.point(3.0f64, 2.0f64)
    mono[5usize] = geom.point(4.0f64, 0.0f64)
    mono[6usize] = geom.point(7.0f64, 1.0f64)
    mono[7usize] = geom.point(6.0f64, 3.0f64)
    mono[8usize] = geom.point(8.0f64, 5.0f64)
    mono[9usize] = geom.point(7.0f64, 7.0f64)
    mono[10usize] = geom.point(9.0f64, 9.0f64)
    if !geom.is_monotone(mono[..]) || geom.is_monotone(star[..]) { os.exit(12i32) }
    var mtris: [27]usize = zero
    var mscratch: [22]usize = zero
    let (mono_written, mono_error) = geom.triangulate_monotone(mono[..], mtris[..], mscratch[..])
    if mono_error != ok || mono_written != 27usize || tri_fold(mtris[..], 27usize) != 2831616120252949498u64 { os.exit(12i32) }
    var mono_area = 0.0f64
    t = 0usize
    while t < 27usize {
        let o = geom.orient(mono[mtris[t]], mono[mtris[t + 1usize]], mono[mtris[t + 2usize]])
        if o <= 0.0f64 { os.exit(12i32) }
        mono_area += o / 2.0f64
        t += 3usize
    }
    if !near(mono_area, geom.polygon_area(mono[..]), 0.000000001f64) { os.exit(12i32) }
    let (_, not_monotone) = geom.triangulate_monotone(star[..], mtris[..], mscratch[..])
    if not_monotone != geom.Invalid { os.exit(12i32) }

    // 13: convex clipping of the star to a window loses the notch: area 6.5.
    var window: [4]geom.Point = zero
    window[0usize] = geom.point(1.0f64, 1.0f64)
    window[1usize] = geom.point(5.0f64, 1.0f64)
    window[2usize] = geom.point(5.0f64, 3.0f64)
    window[3usize] = geom.point(1.0f64, 3.0f64)
    var clipped: [16]geom.Point = zero
    var clip_scratch: [16]geom.Point = zero
    let (clip_count, clip_error) = geom.clip_polygon(star[..], window[..], clipped[..], clip_scratch[..])
    if clip_error != ok || clip_count < 4usize || !near(geom.polygon_area(clipped[..clip_count]), 6.5f64, 0.000000001f64) { os.exit(13i32) }
    let (_, clip_room) = geom.clip_polygon(star[..], window[..], clipped[..4usize], clip_scratch[..])
    if clip_room != geom.TooSmall { os.exit(13i32) }

    try io.print("algo geom plan ok\n")
    ret ok
}
