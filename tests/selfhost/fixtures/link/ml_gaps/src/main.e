// The planned names filled into `e.ml.*`: HNSW recall and structure, the
// IVF-PQ and MinHash LSH entries of `e.ml.ann`; `bayes.naive`; the density,
// streaming and BIRCH entries of `e.ml.cluster`; `loss.kl_divergence` and
// `js_divergence`; the margin and averaged perceptron and `autodiff` of
// `e.ml.nn`; `reduce.frequent_directions`; `sample.temperature` and
// `sample_temperature`. Expected values come from Python replicas of the
// same loops (scratchpad `ml_gaps/ref.py`), cross-checked against
// sklearn/numpy/scipy where they exist. Each check exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.ml.ann
use e.ml.bayes
use e.ml.cluster
use e.ml.cluster.density as density
use e.ml.loss
use e.ml.nn
use e.ml.reduce
use e.ml.sample
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn lcg(state: *u64) -> f64 {
    *state = *state *% 6364136223846793005u64 +% 1442695040888963407u64
    ret f64(*state >> 33u32) / 2147483648.0f64
}

// Is point `id` among the `k` nearest of `query` (distinct distances)?
fn in_top(x: []const f64, n: usize, d: usize, query: []const f64, id: u32, k: usize) -> bool {
    let mine = ann.distance_squared(x, d, usize(id), query, 0usize)
    var closer = 0usize
    var p = 0usize
    while p < n {
        if ann.distance_squared(x, d, p, query, 0usize) < mine { closer += 1usize }
        p += 1usize
    }
    ret closer < k
}

// Three blobs at (0,0), (5,5), (10,0) with `spread`, sample `i` in blob `i % 3`.
fn blobs(seed: u64, n: usize, spread: f64, out: []f64) {
    var state = seed
    var i = 0usize
    while i < n {
        let c = i % 3usize
        var cx = 0.0f64
        var cy = 0.0f64
        if c == 1usize {
            cx = 5.0f64
            cy = 5.0f64
        }
        if c == 2usize { cx = 10.0f64 }
        out[2usize * i] = cx + (lcg(&state) - 0.5f64) * 2.0f64 * spread
        out[2usize * i + 1usize] = cy + (lcg(&state) - 0.5f64) * 2.0f64 * spread
        i += 1usize
    }
}

// 1, 2: HNSW and IVF-PQ over 500 LCG points in eight dimensions.
fn check_ann(a: *mem.Arena) -> err {
    let (x, x_error) = mem.alloc[f64](a, 4000usize)
    if x_error != ok { ret x_error }
    let (qs, qs_error) = mem.alloc[f64](a, 160usize)
    if qs_error != ok { ret qs_error }
    var state = 12345u64
    var i = 0usize
    while i < 4000usize {
        x[i] = lcg(&state)
        i += 1usize
    }
    i = 0usize
    while i < 160usize {
        qs[i] = lcg(&state)
        i += 1usize
    }
    let (g0, g_error) = ann.hnsw(a, 500usize, 8usize, 8usize, 4usize)
    if g_error != ok { os.exit(1i32) }
    var g = g0
    var r = rand.pcg64(7u64, 7u64)
    var scratch: [128]f64 = zero
    var visited: [500]u32 = zero
    i = 0usize
    while i < 500usize {
        if ann.hnsw_insert(&g, x, &r, 64usize, scratch[..], visited[..]) != ok { os.exit(1i32) }
        i += 1usize
    }
    if g.n != 500usize { os.exit(1i32) }
    if g.entry != 217usize { os.exit(1i32) }
    if g.level[217usize] != 3u32 { os.exit(1i32) }
    var above = 0usize
    var links0 = 0usize
    i = 0usize
    while i < 500usize {
        if g.level[i] > 0u32 { above += 1usize }
        links0 += usize(g.count[i * 5usize])
        i += 1usize
    }
    if above != 54usize { os.exit(1i32) }
    if links0 != 6349usize { os.exit(1i32) }
    var ids: [10]u32 = zero
    var dists: [10]f64 = zero
    let first = [10]u32{ 204u32, 179u32, 236u32, 433u32, 290u32, 313u32, 139u32, 410u32, 316u32, 175u32 }
    var hits = 0usize
    var q = 0usize
    while q < 20usize {
        let query = qs[q * 8usize..(q + 1usize) * 8usize]
        let (found, search_error) = ann.hnsw_search(&g, x, query, 10usize, 32usize, ids[..], dists[..], scratch[..], visited[..])
        if search_error != ok || found != 10usize { os.exit(1i32) }
        var k = 0usize
        while k < 10usize {
            if in_top(x, 500usize, 8usize, query, ids[k], 10usize) { hits += 1usize }
            if q == 0usize && ids[k] != first[k] { os.exit(1i32) }
            if k > 0usize && dists[k] < dists[k - 1usize] { os.exit(1i32) }
            k += 1usize
        }
        q += 1usize
    }
    if hits != 200usize { os.exit(1i32) }
    let (_, search_small) = ann.hnsw_search(&g, x, qs[..8usize], 10usize, 32usize, ids[..], dists[..], scratch[..10usize], visited[..])
    if search_small != ann.TooSmall { os.exit(1i32) }
    let (_, search_invalid) = ann.hnsw_search(&g, x, qs[..8usize], 10usize, 4usize, ids[..], dists[..], scratch[..], visited[..])
    if search_invalid != ann.Invalid { os.exit(1i32) }
    if ann.hnsw_insert(&g, x, &r, 64usize, scratch[..], visited[..]) != ann.Invalid { os.exit(1i32) }

    // 2: IVF-PQ, 8 cells, 4 subspaces of 32 codes, 4 probes: recall@10 >= 0.7.
    var labels: [500]usize = zero
    var marks: [32]usize = zero
    let (big, big_error) = mem.alloc[f64](a, 1540usize)
    if big_error != ok { ret big_error }
    var r2 = rand.pcg64(11u64, 11u64)
    let (index, train_error) = ann.ivf_pq(a, x, 500usize, 8usize, 8usize, 4usize, 32usize, &r2, big, labels[..], marks[..])
    if train_error != ok || index.cells != 8usize || index.cell_start[8usize] != 500usize { os.exit(2i32) }
    var qs2: [136]f64 = zero
    hits = 0usize
    q = 0usize
    while q < 20usize {
        let query = qs[q * 8usize..(q + 1usize) * 8usize]
        let (found, search_error) = ann.ivf_pq_search(&index, query, 4usize, 10usize, ids[..], dists[..], qs2[..])
        if search_error != ok || found != 10usize { os.exit(2i32) }
        var k = 0usize
        while k < 10usize {
            if in_top(x, 500usize, 8usize, query, ids[k], 10usize) { hits += 1usize }
            k += 1usize
        }
        q += 1usize
    }
    // 154 of 200 (0.77) exactly as the replica; the plan asks for 0.7.
    if hits != 154usize { os.exit(2i32) }
    ret ok
}

// 3: the MinHash LSH index over four sets, three overlapping.
fn check_lsh() {
    var sets: [160]u64 = zero
    var i = 0usize
    while i < 40usize {
        sets[i] = u64(i)
        sets[40usize + i] = u64(i + 10usize)
        sets[80usize + i] = u64(i + 1000usize)
        sets[120usize + i] = u64(i + 5usize)
        i += 1usize
    }
    var sigs: [240]u64 = zero
    var keys: [60]u64 = zero
    var ids: [60]u32 = zero
    let (index0, index_error) = ann.minhash_lsh(keys[..], ids[..], 15usize, 4usize, 4usize)
    if index_error != ok { os.exit(3i32) }
    var index = index0
    i = 0usize
    while i < 4usize {
        if ann.minhash(sets[40usize * i..40usize * (i + 1usize)], 7u64, sigs[60usize * i..60usize * (i + 1usize)]) != ok { os.exit(3i32) }
        if ann.minhash_lsh_insert(&index, sigs[60usize * i..60usize * (i + 1usize)], u32(i)) != ok { os.exit(3i32) }
        i += 1usize
    }
    if ann.minhash_lsh_insert(&index, sigs[..60usize], 9u32) != ann.Invalid { os.exit(3i32) }
    var out: [4]u32 = zero
    let (count, query_error) = ann.minhash_lsh_query(&index, sigs[..60usize], out[..])
    if query_error != ok || count != 3usize || out[0usize] != 0u32 || out[1usize] != 1u32 || out[2usize] != 3u32 { os.exit(3i32) }
    let (lone, lone_error) = ann.minhash_lsh_query(&index, sigs[120usize..180usize], out[..])
    if lone_error != ok || lone != 1usize || out[0usize] != 2u32 { os.exit(3i32) }
    let (_, full_error) = ann.minhash_lsh_query(&index, sigs[..60usize], out[..2usize])
    if full_error != ann.TooSmall { os.exit(3i32) }
    let (_, bad_error) = ann.minhash_lsh(keys[..], ids[..], 0usize, 4usize, 4usize)
    if bad_error != ann.Invalid { os.exit(3i32) }
}

// 4: naive Bayes in one call over two Gaussian classes.
fn check_bayes() {
    var state = 99u64
    var x: [48]f64 = zero
    var y: [24]usize = zero
    var i = 0usize
    while i < 24usize {
        let c = i % 2usize
        x[2usize * i] = lcg(&state) * 2.0f64 + 3.0f64 * f64(c)
        x[2usize * i + 1usize] = lcg(&state) * 2.0f64 - 3.0f64 * f64(c)
        y[i] = c
        i += 1usize
    }
    var queries: [12]f64 = zero
    i = 0usize
    while i < 6usize {
        let c = i % 2usize
        queries[2usize * i] = lcg(&state) * 2.0f64 + 3.0f64 * f64(c)
        queries[2usize * i + 1usize] = lcg(&state) * 2.0f64 - 3.0f64 * f64(c)
        i += 1usize
    }
    var means: [4]f64 = zero
    var variances: [4]f64 = zero
    var priors: [2]f64 = zero
    var out: [6]usize = zero
    var scratch: [2]usize = zero
    if bayes.naive(x[..], y[..], 24usize, 2usize, 2usize, queries[..], 6usize, means[..], variances[..], priors[..], out[..], scratch[..]) != ok { os.exit(4i32) }
    i = 0usize
    while i < 6usize {
        if out[i] != i % 2usize { os.exit(4i32) }
        i += 1usize
    }
    if !near(means[0usize], 0.9081677428136269f64, 0.000000001f64) || priors[0usize] != 0.5f64 { os.exit(4i32) }
    if bayes.naive(x[..], y[..], 24usize, 2usize, 2usize, queries[..], 6usize, means[..], variances[..], priors[..], out[..2usize], scratch[..]) != bayes.TooSmall { os.exit(4i32) }
}

// 5, 6: DBSCAN and OPTICS on three blobs plus a stray, against sklearn.
fn check_density() {
    var x: [60]f64 = zero
    blobs(2024u64, 30usize, 0.6f64, x[..])
    x[58usize] = 2.5f64
    x[59usize] = 2.5f64
    var labels: [30]usize = zero
    var scratch: [30]usize = zero
    let (clusters, dbscan_error) = cluster.dbscan(x[..], 30usize, 2usize, 0.8f64, 3usize, labels[..], scratch[..])
    if dbscan_error != ok || clusters != 3usize { os.exit(5i32) }
    var i = 0usize
    while i < 29usize {
        if labels[i] != i % 3usize { os.exit(5i32) }
        i += 1usize
    }
    if labels[29usize] != density.NOISE { os.exit(5i32) }
    // OPTICS with no distance cap: sklearn's ordering, reachability and core distances.
    var order: [30]usize = zero
    var reach: [30]f64 = zero
    var core: [30]f64 = zero
    var work: [3]f64 = zero
    if cluster.optics(x[..], 30usize, 2usize, 1.0e9f64, 3usize, order[..], reach[..], core[..], work[..], scratch[..]) != ok { os.exit(6i32) }
    let want = [30]usize{ 0usize, 3usize, 15usize, 12usize, 9usize, 27usize, 24usize, 6usize, 18usize, 21usize, 29usize, 16usize, 19usize, 22usize, 13usize, 25usize, 1usize, 4usize, 10usize, 28usize, 7usize, 5usize, 14usize, 20usize, 17usize, 26usize, 11usize, 8usize, 2usize, 23usize }
    var reach_sum = 0.0f64
    var core_sum = 0.0f64
    var finite = 0usize
    i = 0usize
    while i < 30usize {
        if order[i] != want[i] { os.exit(6i32) }
        if reach[i] < 1.0e300f64 {
            reach_sum += reach[i]
            finite += 1usize
        }
        core_sum += core[i]
        i += 1usize
    }
    if finite != 29usize || !near(reach_sum, 22.60228383063079f64, 0.000000001f64) || !near(core_sum, 14.805734790999793f64, 0.000000001f64) { os.exit(6i32) }
    let (cut, cut_error) = cluster.optics_cut(order[..], reach[..], core[..], 30usize, 0.8f64, labels[..])
    if cut_error != ok || cut != 3usize { os.exit(6i32) }
    i = 0usize
    while i < 29usize {
        if labels[i] != i % 3usize { os.exit(6i32) }
        i += 1usize
    }
    if labels[29usize] != density.NOISE { os.exit(6i32) }
}

// 7: BIRCH with branching 3 and threshold 1 over wide blobs.
fn check_birch(a: *mem.Arena) {
    var x: [90]f64 = zero
    blobs(777u64, 45usize, 1.5f64, x[..])
    var path: [200]usize = zero
    let (t, fit_error) = cluster.birch_fit(a, x[..], 45usize, 2usize, 3usize, 1.0f64, 200usize, path[..])
    if fit_error != ok || t.nodes != 13usize || t.root != 6usize || t.height[6usize] != 2u32 { os.exit(7i32) }
    var centroids: [40]f64 = zero
    var sizes: [20]f64 = zero
    let (k, centroid_error) = cluster.birch_centroids(&t, centroids[..], sizes[..])
    if centroid_error != ok || k != 9usize { os.exit(7i32) }
    var checksum = 0.0f64
    var total = 0.0f64
    var i = 0usize
    while i < k {
        checksum += f64(i + 1usize) * (centroids[2usize * i] + 2.0f64 * centroids[2usize * i + 1usize])
        total += sizes[i]
        i += 1usize
    }
    if !near(checksum, 466.9847614153133f64, 0.000000001f64) || total != 45.0f64 { os.exit(7i32) }
    let (_, room_error) = cluster.birch_centroids(&t, centroids[..4usize], sizes[..])
    if room_error != cluster.TooSmall { os.exit(7i32) }
    let (_, tiny_error) = cluster.birch_fit(a, x[..], 45usize, 2usize, 3usize, 1.0f64, 4usize, path[..])
    if tiny_error != cluster.Invalid { os.exit(7i32) }
}

// 8: streaming k-means from the first three samples.
fn check_stream() {
    var x: [60]f64 = zero
    blobs(4242u64, 30usize, 0.6f64, x[..])
    var centres: [6]f64 = zero
    var counts: [3]usize = zero
    var labels: [30]usize = zero
    var i = 0usize
    while i < 6usize {
        centres[i] = x[i]
        i += 1usize
    }
    if cluster.kmeans_streaming(x[..], 30usize, 2usize, 3usize, centres[..], counts[..], labels[..]) != ok { os.exit(8i32) }
    var checksum = 0.0f64
    i = 0usize
    while i < 6usize {
        checksum += f64(i + 1usize) * centres[i]
        i += 1usize
    }
    if counts[0usize] != 10usize || counts[1usize] != 10usize || counts[2usize] != 10usize || !near(checksum, 85.94861056223512f64, 0.000000001f64) { os.exit(8i32) }
    i = 0usize
    while i < 30usize {
        if labels[i] != i % 3usize { os.exit(8i32) }
        i += 1usize
    }
    let (c, update_error) = cluster.kmeans_streaming_update(centres[..], counts[..], x[..2usize])
    if update_error != ok || c != 0usize || counts[0usize] != 11usize { os.exit(8i32) }
}

// 9: KL and JS divergences against scipy.
fn check_kl() {
    let p = [4]f64{ 0.1f64, 0.2f64, 0.3f64, 0.4f64 }
    let q = [4]f64{ 0.25f64, 0.25f64, 0.25f64, 0.25f64 }
    let (kl, kl_error) = loss.kl_divergence(p[..], q[..], 4usize, false, 0.0f64)
    if kl_error != ok || !near(kl, 0.1064401352862232f64, 0.000000000001f64) { os.exit(9i32) }
    let (reverse, reverse_error) = loss.kl_divergence(p[..], q[..], 4usize, true, 0.0f64)
    if reverse_error != ok || !near(reverse, 0.12177727428716867f64, 0.000000000001f64) { os.exit(9i32) }
    var scratch: [4]f64 = zero
    let (js, js_error) = loss.js_divergence(p[..], q[..], 4usize, 0.0f64, scratch[..])
    if js_error != ok || !near(js, 0.02786561345727674f64, 0.000000000001f64) { os.exit(9i32) }
    let p2 = [3]f64{ 0.0f64, 0.5f64, 0.5f64 }
    let q2 = [3]f64{ 0.5f64, 0.5f64, 0.0f64 }
    let (smoothed, smoothed_error) = loss.kl_divergence(p2[..], q2[..], 3usize, false, 0.000001f64)
    if smoothed_error != ok || !near(smoothed, 6.561182688701164f64, 0.000000001f64) { os.exit(9i32) }
    let (same, _) = loss.kl_divergence(p[..], p[..], 4usize, false, 0.0f64)
    if same != 0.0f64 { os.exit(9i32) }
    let (_, empty_error) = loss.kl_divergence(p[..], q[..], 0usize, false, 0.0f64)
    if empty_error != loss.Invalid { os.exit(9i32) }
}

// 10: the margin perceptron and its averaged form on a separable set.
fn check_perceptron() {
    var state = 31337u64
    var x: [40]f64 = zero
    var y: [20]f64 = zero
    var i = 0usize
    while i < 20usize {
        let p = lcg(&state) * 4.0f64 - 2.0f64
        let q = lcg(&state) * 4.0f64 - 2.0f64
        x[2usize * i] = p
        x[2usize * i + 1usize] = q
        y[i] = 0.0f64 - 1.0f64
        if p + 0.5f64 * q > 0.2f64 { y[i] = 1.0f64 }
        i += 1usize
    }
    var w: [3]f64 = zero
    let (epochs, perceptron_error) = nn.perceptron(x[..], y[..], 20usize, 2usize, w[..], 0.5f64, 0.1f64, 100usize)
    if perceptron_error != ok || epochs != 16usize { os.exit(10i32) }
    if !near(w[0usize], 4.516910512000322f64, 0.000000000001f64) || !near(w[1usize], 2.3063859287649393f64, 0.000000000001f64) || w[2usize] != 0.0f64 - 1.0f64 { os.exit(10i32) }
    var w2: [3]f64 = zero
    var averaged: [3]f64 = zero
    let (epochs2, averaged_error) = nn.perceptron_averaged(x[..], y[..], 20usize, 2usize, w2[..], averaged[..], 0.5f64, 0.1f64, 100usize)
    if averaged_error != ok || epochs2 != 16usize || w2[0usize] != w[0usize] { os.exit(10i32) }
    if !near(averaged[0usize], 2.9881362330692354f64, 0.000000000001f64) || !near(averaged[1usize], 1.608001551864436f64, 0.000000000001f64) || averaged[2usize] != 0.0f64 - 0.9359375f64 { os.exit(10i32) }
    var right = 0usize
    i = 0usize
    while i < 20usize {
        if nn.perceptron_predict(x[2usize * i..2usize * i + 2usize], averaged[..]) == y[i] { right += 1usize }
        i += 1usize
    }
    if right != 19usize { os.exit(10i32) }
    let (_, small_error) = nn.perceptron(x[..], y[..], 20usize, 2usize, w[..2usize], 0.5f64, 0.1f64, 100usize)
    if small_error != nn.TooSmall { os.exit(10i32) }
}

// `tanh(a b + exp c) / (a + ln b) - relu(a - c) b` on a fresh tape; answers the root.
fn expression(t: *nn.Tape, av: f64, bv: f64, cv: f64) -> usize {
    t.count = 0usize
    let (a, _) = nn.variable(t, av)
    let (b, _) = nn.variable(t, bv)
    let (c, _) = nn.variable(t, cv)
    let (ab, _) = nn.mul(t, a, b)
    let (ec, _) = nn.exp(t, c)
    let (u, _) = nn.add(t, ab, ec)
    let (th, _) = nn.tanh(t, u)
    let (lb, _) = nn.log(t, b)
    let (v, _) = nn.add(t, a, lb)
    let (left, _) = nn.div(t, th, v)
    let (ac, _) = nn.sub(t, a, c)
    let (rl, _) = nn.relu(t, ac)
    let (right, _) = nn.mul(t, rl, b)
    let (root, _) = nn.sub(t, left, right)
    ret root
}

// A two-layer network's squared loss on a fresh tape; `params` has nine weights.
fn network(t: *nn.Tape, params: []const f64) -> usize {
    t.count = 0usize
    var ids: [9]usize = zero
    var i = 0usize
    while i < 9usize {
        let (id, _) = nn.variable(t, params[i])
        ids[i] = id
        i += 1usize
    }
    let (x0, _) = nn.variable(t, 0.8f64)
    let (x1, _) = nn.variable(t, 0.0f64 - 0.3f64)
    let (y, _) = nn.variable(t, 0.4f64)
    let (p00, _) = nn.mul(t, ids[0usize], x0)
    let (p01, _) = nn.mul(t, ids[1usize], x1)
    let (s0, _) = nn.add(t, p00, p01)
    let (z0, _) = nn.add(t, s0, ids[2usize])
    let (h0, _) = nn.tanh(t, z0)
    let (p10, _) = nn.mul(t, ids[3usize], x0)
    let (p11, _) = nn.mul(t, ids[4usize], x1)
    let (s1, _) = nn.add(t, p10, p11)
    let (z1, _) = nn.add(t, s1, ids[5usize])
    let (h1, _) = nn.tanh(t, z1)
    let (o0, _) = nn.mul(t, ids[6usize], h0)
    let (o1, _) = nn.mul(t, ids[7usize], h1)
    let (so, _) = nn.add(t, o0, o1)
    let (out, _) = nn.add(t, so, ids[8usize])
    let (diff, _) = nn.sub(t, out, y)
    let (root, _) = nn.mul(t, diff, diff)
    ret root
}

// 11, 12: autodiff gradients against the closed form and finite differences.
fn check_autodiff() {
    var op: [64]nn.Op = zero
    var left: [64]usize = zero
    var right: [64]usize = zero
    var value: [64]f64 = zero
    var gradient: [64]f64 = zero
    var t = nn.tape(op[..], left[..], right[..], value[..], gradient[..])
    let root = expression(&t, 0.7f64, 1.9f64, 0.0f64 - 0.4f64)
    let (fv, ad_error) = nn.autodiff(&t, root)
    if ad_error != ok || !near(fv, 0.0f64 - 1.371553532354307f64, 0.000000001f64) { os.exit(11i32) }
    if !near(gradient[0usize], 0.0f64 - 2.335436909146085f64, 0.000000001f64) || !near(gradient[1usize], 0.0f64 - 1.3449630724500623f64, 0.000000001f64) || !near(gradient[2usize], 1.9352716863489798f64, 0.000000001f64) { os.exit(11i32) }
    let ga = gradient[0usize]
    let gb = gradient[1usize]
    let gc = gradient[2usize]
    let h = 0.000001f64
    let fap = value[expression(&t, 0.7f64 + h, 1.9f64, 0.0f64 - 0.4f64)]
    let fam = value[expression(&t, 0.7f64 - h, 1.9f64, 0.0f64 - 0.4f64)]
    let fbp = value[expression(&t, 0.7f64, 1.9f64 + h, 0.0f64 - 0.4f64)]
    let fbm = value[expression(&t, 0.7f64, 1.9f64 - h, 0.0f64 - 0.4f64)]
    let fcp = value[expression(&t, 0.7f64, 1.9f64, 0.0f64 - 0.4f64 + h)]
    let fcm = value[expression(&t, 0.7f64, 1.9f64, 0.0f64 - 0.4f64 - h)]
    if !near((fap - fam) / (2.0f64 * h), ga, 0.000001f64) || !near((fbp - fbm) / (2.0f64 * h), gb, 0.000001f64) || !near((fcp - fcm) / (2.0f64 * h), gc, 0.000001f64) { os.exit(11i32) }
    let (_, bad_error) = nn.autodiff(&t, 200usize)
    if bad_error != nn.Invalid { os.exit(11i32) }

    // 12: the network, nine parameters against Python's finite differences and our own.
    var params = [9]f64{ 0.3f64, 0.0f64 - 0.2f64, 0.5f64, 0.1f64, 0.0f64 - 0.4f64, 0.2f64, 0.6f64, 0.0f64 - 0.5f64, 0.05f64 }
    let want = [9]f64{ 0.0f64 - 0.075970186875704f64, 0.028488820079039523f64, 0.0f64 - 0.09496273359159424f64, 0.09689419194422455f64, 0.0f64 - 0.036335321973446355f64, 0.1211177399346175f64, 0.0f64 - 0.18799202222870293f64, 0.0f64 - 0.10756538937686799f64, 0.0f64 - 0.2831048379354356f64 }
    let net_root = network(&t, params[..])
    let (loss_value, net_error) = nn.autodiff(&t, net_root)
    if net_error != ok || !near(loss_value, 0.020037087315381674f64, 0.000000001f64) { os.exit(12i32) }
    var grads: [9]f64 = zero
    var i = 0usize
    while i < 9usize {
        grads[i] = gradient[i]
        if !near(grads[i], want[i], 0.000001f64) { os.exit(12i32) }
        i += 1usize
    }
    i = 0usize
    while i < 9usize {
        let keep = params[i]
        params[i] = keep + h
        let up_root = network(&t, params[..])
        let up = value[up_root]
        params[i] = keep - h
        let down_root = network(&t, params[..])
        let down = value[down_root]
        params[i] = keep
        if !near((up - down) / (2.0f64 * h), grads[i], 0.000001f64) { os.exit(12i32) }
        i += 1usize
    }
}

// 13: frequent directions of a 40 × 10 matrix with l = 4 meets Liberty's bound.
fn check_fd() {
    var state = 555u64
    var x: [400]f64 = zero
    var i = 0usize
    while i < 40usize {
        var j = 0usize
        while j < 10usize {
            x[i * 10usize + j] = lcg(&state) * f64(j + 1usize)
            j += 1usize
        }
        i += 1usize
    }
    var sketch: [80]f64 = zero
    var scratch: [256]f64 = zero
    let (filled, fd_error) = reduce.frequent_directions(x[..], 40usize, 10usize, sketch[..], 8usize, scratch[..])
    if fd_error != ok || filled != 8usize { os.exit(13i32) }
    // G = AᵀA − BᵀB, its spectral norm by the symmetric eigenvalues.
    var g: [100]f64 = zero
    var frobenius = 0.0f64
    var p = 0usize
    while p < 10usize {
        var q = 0usize
        while q < 10usize {
            var s = 0.0f64
            i = 0usize
            while i < 40usize {
                s += x[i * 10usize + p] * x[i * 10usize + q]
                i += 1usize
            }
            i = 0usize
            while i < 8usize {
                s -= sketch[i * 10usize + p] * sketch[i * 10usize + q]
                i += 1usize
            }
            g[p * 10usize + q] = s
            q += 1usize
        }
        p += 1usize
    }
    i = 0usize
    while i < 400usize {
        frobenius += x[i] * x[i]
        i += 1usize
    }
    var values: [10]f64 = zero
    var vectors: [100]f64 = zero
    if reduce.symmetric_eigen(g[..], 10usize, values[..], vectors[..], 0.000000000000000000000001f64, 100u32) != ok { os.exit(13i32) }
    var spectral = 0.0f64
    i = 0usize
    while i < 10usize {
        var v = values[i]
        if v < 0.0f64 { v = 0.0f64 - v }
        if v > spectral { spectral = v }
        i += 1usize
    }
    if !near(spectral, 139.25699650686727f64, 0.000001f64) || !near(frobenius / 4.0f64, 1202.5965552560854f64, 0.000001f64) || spectral > frobenius / 4.0f64 { os.exit(13i32) }
    let (_, odd_error) = reduce.frequent_directions(x[..], 40usize, 10usize, sketch[..], 7usize, scratch[..])
    if odd_error != reduce.Invalid { os.exit(13i32) }
}

// 14: temperature scaling and draws against a PCG64 replica.
fn check_temperature() {
    let logits = [6]f64{ 1.0f64, 2.5f64, 0.0f64 - 0.5f64, 0.3f64, 3.0f64, 0.0f64 }
    var scaled: [6]f64 = zero
    if sample.temperature(logits[..], 0.7f64, scaled[..]) != ok { os.exit(14i32) }
    var i = 0usize
    while i < 6usize {
        if scaled[i] != logits[i] / 0.7f64 { os.exit(14i32) }
        i += 1usize
    }
    if sample.temperature(logits[..], 0.0f64, scaled[..]) != sample.Invalid || sample.temperature(logits[..], 0.7f64, scaled[..3usize]) != sample.TooSmall { os.exit(14i32) }
    var r = rand.pcg64(3u64, 3u64)
    var probabilities: [6]f64 = zero
    let want = [8]usize{ 1usize, 1usize, 4usize, 5usize, 4usize, 4usize, 4usize, 4usize }
    i = 0usize
    while i < 8usize {
        let (token, draw_error) = sample.sample_temperature(&r, logits[..], 0.7f64, probabilities[..])
        if draw_error != ok || token != want[i] { os.exit(14i32) }
        i += 1usize
    }
    if !near(probabilities[4usize], 0.6294833803233586f64, 0.000000000001f64) { os.exit(14i32) }
}

fn main(a: *mem.Arena, args: []str) -> err {
    try check_ann(a)
    check_lsh()
    check_bayes()
    check_density()
    check_birch(a)
    check_stream()
    check_kl()
    check_perceptron()
    check_autodiff()
    check_fd()
    check_temperature()
    try io.print("ml gaps ok\n")
    ret ok
}
