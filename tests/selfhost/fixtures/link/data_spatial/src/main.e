// `e.data.spatial`: over 200 pseudo-random points, the k-d tree's nearest
// point, the quadtree and octree range counts, the interval tree's
// overlaps and the hash grid's neighbours all agree with brute force
// computed ahead of time. Each check exits with its own code.

use e.data.spatial as spatial
use e.io
use e.mem
use e.os

fn main(a: *mem.Arena, args: []str) -> err {
    var points: [600]f64 = zero
    var xs: [200]f64 = zero
    var ys: [200]f64 = zero
    var zs: [200]f64 = zero
    var state = 42u64
    var i = 0usize
    while i < 200usize {
        var k = 0usize
        while k < 3usize {
            state = state *% 6364136223846793005u64 +% 1442695040888963407u64
            points[i * 3usize + k] = f64((state >> 33u32) % 1000u64) / 10.0f64
            k += 1usize
        }
        xs[i] = points[i * 3usize]
        ys[i] = points[i * 3usize + 1usize]
        zs[i] = points[i * 3usize + 2usize]
        i += 1usize
    }

    // 1: k-d tree nearest.
    var order: [200]usize = zero
    let (tree, build_error) = spatial.kd_build(points[..], 200usize, 3usize, order[..])
    if build_error != ok { os.exit(1i32) }
    var query: [3]f64 = zero
    query[0usize] = 50.0f64
    query[1usize] = 50.0f64
    query[2usize] = 50.0f64
    let (best, distance, near_error) = spatial.kd_nearest(&tree, query[..])
    if near_error != ok || best != 118usize || distance < 37.93f64 || distance > 37.95f64 { os.exit(1i32) }
    // A permutation.
    var seen: [200]u8 = zero
    i = 0usize
    while i < 200usize {
        if seen[order[i]] != 0u8 { os.exit(1i32) }
        seen[order[i]] = 1u8
        i += 1usize
    }
    let (_, _, small_error) = spatial.kd_nearest(&tree, query[..2usize])
    if small_error != spatial.TooSmall { os.exit(1i32) }

    // 2: quadtree range.
    var child: [1024]u32 = zero
    var first: [256]u32 = zero
    var count: [256]u32 = zero
    var next: [200]u32 = zero
    var qxs: [200]f64 = zero
    var qys: [200]f64 = zero
    let (q0, q_error) = spatial.quadtree(0.0f64, 0.0f64, 100.0f64, 4usize, child[..], first[..], count[..], next[..], qxs[..], qys[..])
    if q_error != ok { os.exit(2i32) }
    var q = q0
    i = 0usize
    while i < 200usize {
        let (item, insert_error) = spatial.quadtree_insert(&q, xs[i], ys[i])
        if insert_error != ok || item != i { os.exit(2i32) }
        i += 1usize
    }
    if q.used <= 1usize { os.exit(2i32) }
    var out: [64]usize = zero
    let (found, range_error) = spatial.quadtree_range(&q, 20.0f64, 30.0f64, 40.0f64, 60.0f64, out[..])
    if range_error != ok || found != 10usize { os.exit(2i32) }
    let (_, outside) = spatial.quadtree_insert(&q, 101.0f64, 0.0f64)
    if outside != spatial.Invalid { os.exit(2i32) }
    let (_, tiny_error) = spatial.quadtree_range(&q, 0.0f64, 0.0f64, 100.0f64, 100.0f64, out[..4usize])
    if tiny_error != spatial.TooSmall { os.exit(2i32) }

    // 3: octree range.
    var child8: [2048]u32 = zero
    var first8: [256]u32 = zero
    var count8: [256]u32 = zero
    var next8: [200]u32 = zero
    var oxs: [200]f64 = zero
    var oys: [200]f64 = zero
    var ozs: [200]f64 = zero
    let (o0, o_error) = spatial.octree(0.0f64, 0.0f64, 0.0f64, 100.0f64, 4usize, child8[..], first8[..], count8[..], next8[..], oxs[..], oys[..], ozs[..])
    if o_error != ok { os.exit(3i32) }
    var o = o0
    i = 0usize
    while i < 200usize {
        let (_, insert_error) = spatial.octree_insert(&o, xs[i], ys[i], zs[i])
        if insert_error != ok { os.exit(3i32) }
        i += 1usize
    }
    let (found8, range8_error) = spatial.octree_range(&o, 20.0f64, 30.0f64, 10.0f64, 40.0f64, 60.0f64, 50.0f64, out[..])
    if range8_error != ok || found8 != 4usize { os.exit(3i32) }

    // 4: interval tree.
    var starts: [200]f64 = zero
    var ends: [200]f64 = zero
    i = 0usize
    while i < 200usize {
        starts[i] = xs[i]
        ends[i] = xs[i] + ys[i] / 5.0f64
        i += 1usize
    }
    var iorder: [200]usize = zero
    var left: [201]u32 = zero
    var right: [201]u32 = zero
    var centre: [201]f64 = zero
    var ifirst: [201]u32 = zero
    var icount: [201]u32 = zero
    let (it, it_error) = spatial.interval_build(starts[..], ends[..], 200usize, iorder[..], left[..], right[..], centre[..], ifirst[..], icount[..])
    if it_error != ok { os.exit(4i32) }
    let (overlaps, overlap_error) = spatial.interval_overlap(&it, 40.0f64, 45.0f64, out[..])
    if overlap_error != ok || overlaps != 19usize { os.exit(4i32) }
    // Every answer really overlaps.
    i = 0usize
    while i < overlaps {
        if starts[out[i]] > 45.0f64 || ends[out[i]] < 40.0f64 { os.exit(4i32) }
        i += 1usize
    }
    let (none, none_error) = spatial.interval_overlap(&it, 500.0f64, 600.0f64, out[..])
    if none_error != ok || none != 0usize { os.exit(4i32) }

    // 5: hash grid.
    var head: [100]u32 = zero
    var gnext: [200]u32 = zero
    var gxs: [200]f64 = zero
    var gys: [200]f64 = zero
    let (g0, g_error) = spatial.hash_grid(0.0f64, 0.0f64, 10.0f64, 10usize, 10usize, head[..], gnext[..], gxs[..], gys[..])
    if g_error != ok { os.exit(5i32) }
    var g = g0
    i = 0usize
    while i < 200usize {
        let (_, insert_error) = spatial.hash_grid_insert(&g, xs[i], ys[i])
        if insert_error != ok { os.exit(5i32) }
        i += 1usize
    }
    let (near, grid_error) = spatial.hash_grid_near(&g, 50.0f64, 50.0f64, 8.0f64, out[..])
    if grid_error != ok || near != 2usize { os.exit(5i32) }
    let (_, bad_error) = spatial.hash_grid(0.0f64, 0.0f64, 0.0f64, 10usize, 10usize, head[..], gnext[..], gxs[..], gys[..])
    if bad_error != spatial.Invalid { os.exit(5i32) }

    // 6: R-tree by insertion and by Hilbert packing against brute force.
    var rects: [800]f64 = zero
    i = 0usize
    while i < 200usize {
        rects[i * 4usize] = xs[i]
        rects[i * 4usize + 1usize] = ys[i]
        rects[i * 4usize + 2usize] = xs[i] + zs[i] / 10.0f64
        rects[i * 4usize + 3usize] = ys[i] + zs[i] / 10.0f64
        i += 1usize
    }
    var rbox: [1024]f64 = zero
    var rchild: [1024]u32 = zero
    var rcount: [256]u32 = zero
    var rleaf: [256]u8 = zero
    let (r0, r_error) = spatial.rtree(rects[..], 4usize, rbox[..], rchild[..], rcount[..], rleaf[..])
    if r_error != ok { os.exit(6i32) }
    var r = r0
    i = 0usize
    while i < 200usize {
        if spatial.rtree_insert(&r, i) != ok { os.exit(6i32) }
        i += 1usize
    }
    if r.root == 0usize || r.leaf[r.root] != 0u8 { os.exit(6i32) }
    let (rfound, rs_error) = spatial.rtree_search(&r, 20.0f64, 30.0f64, 40.0f64, 60.0f64, out[..])
    if rs_error != ok || rfound != 19usize { os.exit(6i32) }
    // Every item is reachable.
    let (all, all_error) = spatial.rtree_search(&r, 0.0f64, 0.0f64, 200.0f64, 200.0f64, out[..])
    if all_error != spatial.TooSmall { os.exit(6i32) }
    var big: [200]usize = zero
    let (all2, all2_error) = spatial.rtree_search(&r, 0.0f64, 0.0f64, 200.0f64, 200.0f64, big[..])
    if all2_error != ok || all2 != 200usize { os.exit(6i32) }
    var keys: [200]u64 = zero
    var horder: [200]usize = zero
    let (h0, h_error) = spatial.rtree_hilbert(rects[..], 200usize, 4usize, rbox[..], rchild[..], rcount[..], rleaf[..], keys[..], horder[..])
    if h_error != ok { os.exit(6i32) }
    let (hfound, hs_error) = spatial.rtree_search(&h0, 20.0f64, 30.0f64, 40.0f64, 60.0f64, out[..])
    if hs_error != ok || hfound != 19usize { os.exit(6i32) }
    if spatial.hilbert_index(2u32, 1u64, 1u64) != 2u64 || spatial.hilbert_index(2u32, 3u64, 0u64) != 15u64 { os.exit(6i32) }

    // 7: BVH traversal by a ray.
    var boxes: [1200]f64 = zero
    i = 0usize
    while i < 200usize {
        boxes[i * 6usize] = xs[i]
        boxes[i * 6usize + 1usize] = ys[i]
        boxes[i * 6usize + 2usize] = zs[i]
        boxes[i * 6usize + 3usize] = xs[i] + 2.0f64
        boxes[i * 6usize + 4usize] = ys[i] + 2.0f64
        boxes[i * 6usize + 5usize] = zs[i] + 2.0f64
        i += 1usize
    }
    var border: [200]usize = zero
    var bbox: [2400]f64 = zero
    var bleft: [400]u32 = zero
    var bright: [400]u32 = zero
    var bfirst: [400]u32 = zero
    var bcount: [400]u32 = zero
    let (bvh, bvh_error) = spatial.bvh_build(boxes[..], 200usize, 4usize, border[..], bbox[..], bleft[..], bright[..], bfirst[..], bcount[..])
    if bvh_error != ok { os.exit(7i32) }
    var origin: [3]f64 = zero
    origin[1usize] = 79.5f64
    origin[2usize] = 21.5f64
    var direction: [3]f64 = zero
    direction[0usize] = 1.0f64
    let (hits, hit_error) = spatial.bvh_traverse(&bvh, origin[..], direction[..], out[..])
    if hit_error != ok || hits != 3usize { os.exit(7i32) }
    origin[1usize] = 50.0f64
    origin[2usize] = 50.0f64
    let (one, one_error) = spatial.bvh_traverse(&bvh, origin[..], direction[..], out[..])
    if one_error != ok || one != 1usize || out[0usize] != 43usize { os.exit(7i32) }
    // Backwards misses everything.
    direction[0usize] = 0.0f64 - 1.0f64
    let (miss, miss_error) = spatial.bvh_traverse(&bvh, origin[..], direction[..], out[..])
    if miss_error != ok || miss != 0usize { os.exit(7i32) }

    // 8: range tree.
    var rt_order: [200]usize = zero
    var rt_pool: [2000]usize = zero
    let (rt, rt_error) = spatial.range_tree_build(xs[..], ys[..], 200usize, rt_order[..], rt_pool[..])
    if rt_error != ok { os.exit(8i32) }
    let (rt_found, rq_error) = spatial.range_tree_query(&rt, 20.0f64, 30.0f64, 40.0f64, 60.0f64, out[..])
    if rq_error != ok || rt_found != 10usize { os.exit(8i32) }
    i = 0usize
    while i < rt_found {
        if xs[out[i]] < 20.0f64 || xs[out[i]] > 40.0f64 || ys[out[i]] < 30.0f64 || ys[out[i]] > 60.0f64 { os.exit(8i32) }
        i += 1usize
    }

    // 9: ball tree agrees with the k-d tree.
    var bt_order: [200]usize = zero
    var centres: [600]f64 = zero
    var radius: [200]f64 = zero
    let (ball, ball_error) = spatial.ball_tree_build(points[..], 200usize, 3usize, bt_order[..], centres[..], radius[..])
    if ball_error != ok { os.exit(9i32) }
    query[0usize] = 50.0f64
    query[1usize] = 50.0f64
    query[2usize] = 50.0f64
    let (ball_best, ball_distance, ball_near_error) = spatial.ball_tree_nearest(&ball, query[..])
    if ball_near_error != ok || ball_best != 118usize || ball_distance < 37.93f64 || ball_distance > 37.95f64 { os.exit(9i32) }
    // Every point is its own nearest.
    i = 0usize
    while i < 200usize {
        let (self_best, self_distance, self_error) = spatial.ball_tree_nearest(&ball, points[i * 3usize..i * 3usize + 3usize])
        if self_error != ok || self_distance != 0.0f64 { os.exit(9i32) }
        i += 1usize
    }

    try io.print("data spatial ok\n")
    ret ok
}
