// `e.ml.ann`: MinHash signatures estimate the Jaccard similarity of two
// overlapping sets and LSH banding matches the similar pair but not the
// disjoint one, the small-world graph answers exact nearest neighbours on
// a small cloud, and IVF-PQ over three clusters finds the true nearest
// among the probed cells. Each check exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.ml.ann
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: MinHash and LSH.
    var set_a: [40]u64 = zero
    var set_b: [40]u64 = zero
    var set_c: [40]u64 = zero
    var i = 0usize
    while i < 40usize {
        set_a[i] = u64(i)
        set_b[i] = u64(i + 10usize)
        set_c[i] = u64(i + 1000usize)
        i += 1usize
    }
    var sig_a: [200]u64 = zero
    var sig_b: [200]u64 = zero
    var sig_c: [200]u64 = zero
    if ann.minhash(set_a[..], 7u64, sig_a[..]) != ok || ann.minhash(set_b[..], 7u64, sig_b[..]) != ok || ann.minhash(set_c[..], 7u64, sig_c[..]) != ok { os.exit(1i32) }
    // |A ∩ B| = 30 of |A ∪ B| = 50: Jaccard 0.6.
    let estimate = ann.jaccard_estimate(sig_a[..], sig_b[..])
    if !near(estimate, 0.6f64, 0.1f64) || ann.jaccard_estimate(sig_a[..], sig_c[..]) > 0.05f64 || ann.jaccard_estimate(sig_a[..], sig_a[..]) != 1.0f64 { os.exit(1i32) }
    if !ann.lsh_match(sig_a[..], sig_b[..], 50usize, 4usize) || ann.lsh_match(sig_a[..], sig_c[..], 50usize, 4usize) { os.exit(1i32) }
    if ann.lsh_match(sig_a[..], sig_b[..], 1usize, 200usize) { os.exit(1i32) }
    if ann.minhash(set_a[..], 7u64, sig_a[..0usize]) != ann.Invalid { os.exit(1i32) }

    // 2: the small-world graph on a cloud of forty points.
    var r = rand.pcg64(21u64, 21u64)
    var cloud: [80]f64 = zero
    i = 0usize
    while i < 80usize {
        cloud[i] = rand.pcg64_f64(&r) * 10.0f64
        i += 1usize
    }
    var scratch: [256]f64 = zero
    var visited: [40]u32 = zero
    let (g, build_error) = ann.graph_build(a, cloud[..], 40usize, 2usize, 5usize, 12usize, scratch[..], visited[..])
    if build_error != ok || g.n != 40usize { os.exit(2i32) }
    var ids: [12]f64 = zero
    var dists: [12]f64 = zero
    var query: [2]f64 = zero
    var misses = 0usize
    var trial = 0usize
    while trial < 20usize {
        query[0usize] = rand.pcg64_f64(&r) * 10.0f64
        query[1usize] = rand.pcg64_f64(&r) * 10.0f64
        let (found, search_error) = ann.graph_search(&g, cloud[..], 2usize, query[..], 3usize, 12usize, ids[..], dists[..], scratch[..], visited[..])
        if search_error != ok || found != 3usize { os.exit(2i32) }
        // The exact nearest by a scan.
        var best = 0usize
        var best_dist = 1.0e300f64
        var p = 0usize
        while p < 40usize {
            let dist = ann.distance_squared(cloud[..], 2usize, p, query[..], 0usize)
            if dist < best_dist {
                best_dist = dist
                best = p
            }
            p += 1usize
        }
        if usize(ids[0usize]) != best || !near(dists[0usize], best_dist, 0.000000001f64) { misses += 1usize }
        if dists[1usize] < dists[0usize] || dists[2usize] < dists[1usize] { os.exit(2i32) }
        trial += 1usize
    }
    if misses > 1usize { os.exit(2i32) }
    let (_, search_room) = ann.graph_search(&g, cloud[..], 2usize, query[..], 3usize, 12usize, ids[..], dists[..], scratch[..5usize], visited[..])
    if search_room != ann.TooSmall { os.exit(2i32) }
    let (_, build_invalid) = ann.graph_build(a, cloud[..], 40usize, 2usize, 0usize, 12usize, scratch[..], visited[..])
    if build_invalid != ann.Invalid { os.exit(2i32) }

    // 3: IVF-PQ over three clusters of sixteen points in four dimensions.
    var points: [192]f64 = zero
    i = 0usize
    while i < 48usize {
        let c = i / 16usize
        var j = 0usize
        while j < 4usize {
            points[4usize * i + j] = f64(c) * 20.0f64 + rand.pcg64_f64(&r)
            j += 1usize
        }
        i += 1usize
    }
    var labels: [48]usize = zero
    var marks: [8]usize = zero
    let (big, big_error) = mem.alloc[f64](a, 48usize * 2usize + 48usize + 3usize + 4usize)
    if big_error != ok { ret big_error }
    let (index, train_error) = ann.ivf_pq_train(a, points[..], 48usize, 4usize, 3usize, 2usize, 4usize, &r, big, labels[..], marks[..])
    if train_error != ok || index.cells != 3usize || index.subspaces != 2usize { os.exit(3i32) }
    if index.cell_start[3usize] != 48usize { os.exit(3i32) }
    var qv: [4]f64 = zero
    var found_ids: [4]u32 = zero
    var found_dists: [4]f64 = zero
    var qs: [32]f64 = zero
    trial = 0usize
    misses = 0usize
    while trial < 10usize {
        let c = trial % 3usize
        var j = 0usize
        while j < 4usize {
            qv[j] = f64(c) * 20.0f64 + rand.pcg64_f64(&r)
            j += 1usize
        }
        let (found, search_error) = ann.ivf_pq_search(&index, qv[..], 1usize, 4usize, found_ids[..], found_dists[..], qs[..])
        if search_error != ok || found != 4usize { os.exit(3i32) }
        // The probed cell is the right cluster: every answer comes from it.
        var k = 0usize
        while k < 4usize {
            if usize(found_ids[k]) / 16usize != c { misses += 1usize }
            k += 1usize
        }
        trial += 1usize
    }
    if misses != 0usize { os.exit(3i32) }
    let (all, all_error) = ann.ivf_pq_search(&index, qv[..], 3usize, 4usize, found_ids[..], found_dists[..], qs[..])
    if all_error != ok || all != 4usize { os.exit(3i32) }
    let (_, probe_invalid) = ann.ivf_pq_search(&index, qv[..], 4usize, 4usize, found_ids[..], found_dists[..], qs[..])
    if probe_invalid != ann.Invalid { os.exit(3i32) }
    let (_, train_invalid) = ann.ivf_pq_train(a, points[..], 48usize, 4usize, 3usize, 3usize, 4usize, &r, big, labels[..], marks[..])
    if train_invalid != ann.Invalid { os.exit(3i32) }

    try io.print("ml ann ok\n")
    ret ok
}
