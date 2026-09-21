// `e.ml.cluster` on three blobs of eight points: k-means from seeds reaches
// scikit-learn's centroids and inertia, k-means++ seeds one centroid per
// blob, the online update and LBG quantisation partition the blobs,
// k-medoids climbs out of a bad start, agglomerative single, average and
// complete linkage match scikit-learn, GMM by EM reaches the same means,
// variances and log-likelihood, and neighbour joining reproduces the
// textbook five-taxon tree. Each check exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.ml.cluster
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

// Every point of blob `b` (rows 8b..8b+8) carries the same label, distinct per blob.
fn partitioned(labels: []const usize, blobs: usize) -> bool {
    var b = 0usize
    while b < blobs {
        var i = 1usize
        while i < 8usize {
            if labels[8usize * b + i] != labels[8usize * b] { ret false }
            i += 1usize
        }
        var c = 0usize
        while c < b {
            if labels[8usize * c] == labels[8usize * b] { ret false }
            c += 1usize
        }
        b += 1usize
    }
    ret true
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [48]f64 = zero
    var base: [16]f64 = zero
    base[2usize] = 1.0f64
    base[5usize] = 1.0f64
    base[6usize] = 1.0f64
    base[7usize] = 1.0f64
    base[8usize] = 0.5f64
    base[9usize] = 0.5f64
    base[10usize] = 0.2f64
    base[11usize] = 0.8f64
    base[12usize] = 0.8f64
    base[13usize] = 0.2f64
    base[14usize] = 0.5f64
    base[15usize] = 0.1f64
    var i = 0usize
    while i < 8usize {
        x[2usize * i] = base[2usize * i]
        x[2usize * i + 1usize] = base[2usize * i + 1usize]
        x[16usize + 2usize * i] = base[2usize * i] + 10.0f64
        x[16usize + 2usize * i + 1usize] = base[2usize * i + 1usize]
        x[32usize + 2usize * i] = base[2usize * i]
        x[32usize + 2usize * i + 1usize] = base[2usize * i + 1usize] + 10.0f64
        i += 1usize
    }
    var centroids: [8]f64 = zero
    var labels: [24]usize = zero
    var marks: [8]usize = zero
    var weights: [64]f64 = zero

    // 1: k-means from the blob corners.
    centroids[2usize] = 10.0f64
    centroids[5usize] = 10.0f64
    let (took, kmeans_error) = cluster.kmeans(x[..], 24usize, 2usize, 3usize, centroids[..6usize], labels[..], 100u32, marks[..])
    if kmeans_error != ok || took < 2u32 || took > 5u32 || !partitioned(labels[..], 3usize) { os.exit(1i32) }
    if !near(centroids[0usize], 0.5f64, 0.0000001f64) || !near(centroids[1usize], 0.45f64, 0.0000001f64) || !near(centroids[2usize], 10.5f64, 0.0000001f64) || !near(centroids[5usize], 10.45f64, 0.0000001f64) { os.exit(1i32) }
    var inertia = 0.0f64
    i = 0usize
    while i < 24usize {
        let (_, dist) = cluster.nearest(x[..], 2usize, i, centroids[..], 3usize)
        inertia += dist
        i += 1usize
    }
    if !near(inertia, 7.5f64, 0.0000001f64) { os.exit(1i32) }
    let (_, kmeans_invalid) = cluster.kmeans(x[..], 24usize, 2usize, 0usize, centroids[..], labels[..], 100u32, marks[..])
    if kmeans_invalid != cluster.Invalid { os.exit(1i32) }
    let (_, kmeans_room) = cluster.kmeans(x[..], 24usize, 2usize, 3usize, centroids[..], labels[..10usize], 100u32, marks[..])
    if kmeans_room != cluster.TooSmall { os.exit(1i32) }

    // 2: k-means++ seeds, then the online update and LBG.
    var r = rand.pcg64(2u64, 7u64)
    if cluster.kmeans_pp_init(x[..], 24usize, 2usize, 3usize, &r, centroids[..6usize], weights[..]) != ok { os.exit(2i32) }
    let (seeded, seeded_error) = cluster.kmeans(x[..], 24usize, 2usize, 3usize, centroids[..6usize], labels[..], 100u32, marks[..])
    if seeded_error != ok || seeded > 3u32 || !partitioned(labels[..], 3usize) { os.exit(2i32) }
    var counts: [3]usize = zero
    centroids[0usize] = 0.5f64
    centroids[1usize] = 0.5f64
    centroids[2usize] = 10.5f64
    centroids[3usize] = 0.5f64
    centroids[4usize] = 0.5f64
    centroids[5usize] = 10.5f64
    i = 0usize
    while i < 24usize {
        let (c, online_error) = cluster.kmeans_online(x[2usize * i..2usize * i + 2usize], 2usize, 3usize, centroids[..6usize], counts[..])
        if online_error != ok || c != i / 8usize { os.exit(2i32) }
        i += 1usize
    }
    if counts[0usize] != 8usize || counts[2usize] != 8usize || !near(centroids[0usize], 0.5f64, 0.0000001f64) || !near(centroids[5usize], 10.45f64, 0.0000001f64) { os.exit(2i32) }
    let (_, lbg_error) = cluster.vector_quantize(x[..], 24usize, 2usize, 4usize, 0.01f64, centroids[..], labels[..], 100u32, marks[..])
    if lbg_error != ok { os.exit(2i32) }
    // Four codewords over three blobs: every blob is uniform but one, and no blob shares a code.
    var uniform = 0usize
    var b = 0usize
    while b < 3usize {
        var all_same = true
        i = 1usize
        while i < 8usize {
            if labels[8usize * b + i] != labels[8usize * b] { all_same = false }
            i += 1usize
        }
        if all_same { uniform += 1usize }
        b += 1usize
    }
    if uniform < 2usize { os.exit(2i32) }
    let (_, lbg_invalid) = cluster.vector_quantize(x[..], 24usize, 2usize, 3usize, 0.01f64, centroids[..], labels[..], 100u32, marks[..])
    if lbg_invalid != cluster.Invalid { os.exit(2i32) }

    // 3: k-medoids from a bad start.
    var medoids: [3]usize = zero
    medoids[1usize] = 1usize
    medoids[2usize] = 2usize
    let (swaps, pam_error) = cluster.kmedoids(x[..], 24usize, 2usize, 3usize, medoids[..], labels[..], 20u32)
    if pam_error != ok || swaps < 2u32 || !partitioned(labels[..], 3usize) { os.exit(3i32) }
    if medoids[0usize] / 8usize == medoids[1usize] / 8usize || medoids[1usize] / 8usize == medoids[2usize] / 8usize || medoids[0usize] / 8usize == medoids[2usize] / 8usize { os.exit(3i32) }

    // 4: agglomerative linkages against scikit-learn (blob A first, then B, then C).
    var distances: [576]f64 = zero
    if cluster.agglomerative(x[..], 24usize, 2usize, .Single, 3usize, labels[..], distances[..]) != ok || !partitioned(labels[..], 3usize) || labels[0usize] != 0usize || labels[8usize] != 1usize || labels[16usize] != 2usize { os.exit(4i32) }
    if cluster.agglomerative(x[..], 24usize, 2usize, .Average, 3usize, labels[..], distances[..]) != ok || !partitioned(labels[..], 3usize) { os.exit(4i32) }
    if cluster.agglomerative(x[..], 24usize, 2usize, .Complete, 2usize, labels[..], distances[..]) != ok { os.exit(4i32) }
    // Complete linkage with two clusters keeps A with B (10 apart along one axis) against C.
    i = 0usize
    while i < 24usize {
        var want = 0usize
        if i >= 16usize { want = 1usize }
        if labels[i] != want { os.exit(4i32) }
        i += 1usize
    }
    if cluster.agglomerative(x[..], 24usize, 2usize, .Single, 24usize, labels[..], distances[..]) != ok || labels[23usize] != 23usize { os.exit(4i32) }
    if cluster.agglomerative(x[..], 24usize, 2usize, .Single, 0usize, labels[..], distances[..]) != cluster.Invalid { os.exit(4i32) }

    // 5: a Gaussian mixture by EM.
    var means: [6]f64 = zero
    means[2usize] = 10.0f64
    means[5usize] = 10.0f64
    var variances: [6]f64 = zero
    i = 0usize
    while i < 6usize {
        variances[i] = 1.0f64
        i += 1usize
    }
    var mixture: [3]f64 = zero
    mixture[0usize] = 1.0f64 / 3.0f64
    mixture[1usize] = 1.0f64 / 3.0f64
    mixture[2usize] = 1.0f64 / 3.0f64
    var responsibilities: [72]f64 = zero
    let (log_likelihood, em_iterations, em_error) = cluster.gmm_em(x[..], 24usize, 2usize, 3usize, means[..], variances[..], mixture[..], responsibilities[..], 0.000000001f64, 200u32)
    if em_error != ok || em_iterations < 2u32 || !near(log_likelihood, 0.0f64 - 49.8869016229489f64, 0.0001f64) { os.exit(5i32) }
    if !near(means[0usize], 0.5f64, 0.000001f64) || !near(means[1usize], 0.45f64, 0.000001f64) || !near(means[5usize], 10.45f64, 0.000001f64) { os.exit(5i32) }
    if !near(variances[0usize], 0.1475f64, 0.0001f64) || !near(variances[1usize], 0.165f64, 0.0001f64) || !near(mixture[2usize], 1.0f64 / 3.0f64, 0.000001f64) { os.exit(5i32) }
    if !near(responsibilities[0usize], 1.0f64, 0.000001f64) || !near(responsibilities[8usize * 3usize + 1usize], 1.0f64, 0.000001f64) { os.exit(5i32) }

    // 6: neighbour joining on the textbook five taxa.
    var matrix: [25]f64 = zero
    var rows: [25]f64 = zero
    matrix[1usize] = 5.0f64
    matrix[2usize] = 9.0f64
    matrix[3usize] = 9.0f64
    matrix[4usize] = 8.0f64
    matrix[7usize] = 10.0f64
    matrix[8usize] = 10.0f64
    matrix[9usize] = 9.0f64
    matrix[13usize] = 8.0f64
    matrix[14usize] = 7.0f64
    matrix[19usize] = 3.0f64
    i = 0usize
    while i < 5usize {
        var j = i + 1usize
        while j < 5usize {
            matrix[j * 5usize + i] = matrix[i * 5usize + j]
            j += 1usize
        }
        i += 1usize
    }
    var joins: [12]usize = zero
    var lengths: [8]f64 = zero
    var ids: [16]usize = zero
    let (steps, nj_error) = cluster.neighbor_joining(matrix[..], 5usize, rows[..], joins[..], lengths[..], ids[..])
    if nj_error != ok || steps != 4usize { os.exit(6i32) }
    if joins[0usize] != 0usize || joins[1usize] != 1usize || joins[2usize] != 5usize || lengths[0usize] != 2.0f64 || lengths[1usize] != 3.0f64 { os.exit(6i32) }
    if joins[3usize] != 5usize || joins[4usize] != 2usize || joins[5usize] != 6usize || lengths[2usize] != 3.0f64 || lengths[3usize] != 4.0f64 { os.exit(6i32) }
    if joins[6usize] != 6usize || joins[7usize] != 3usize || joins[8usize] != 7usize || lengths[4usize] != 2.0f64 || lengths[5usize] != 2.0f64 { os.exit(6i32) }
    if joins[9usize] != 7usize || joins[10usize] != 4usize || joins[11usize] != 8usize || lengths[6usize] != 0.5f64 || lengths[7usize] != 0.5f64 { os.exit(6i32) }
    let (_, nj_invalid) = cluster.neighbor_joining(matrix[..], 1usize, rows[..], joins[..], lengths[..], ids[..])
    if nj_invalid != cluster.Invalid { os.exit(6i32) }

    try io.print("ml cluster ok\n")
    ret ok
}
