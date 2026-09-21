// `e.ml.reduce`: PCA of the classic ten-point set against NumPy (mean,
// variances, components up to sign, projection), Oja's rule converging on
// the leading component from a stream, frequent directions keeping the
// dominant direction of a sketch, and t-SNE keeping three separated groups
// apart. Each check exits with its own code.

use e.algo.rand
use e.io
use e.math
use e.mem
use e.ml.reduce
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

fn same_direction(a: []const f64, b: []const f64, eps: f64) -> bool {
    var dot = 0.0f64
    var i = 0usize
    while i < a.len {
        dot += a[i] * b[i]
        i += 1usize
    }
    if dot < 0.0f64 { dot = 0.0f64 - dot }
    ret near(dot, 1.0f64, eps)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var x: [20]f64 = zero
    x[0usize] = 2.5f64
    x[1usize] = 2.4f64
    x[2usize] = 0.5f64
    x[3usize] = 0.7f64
    x[4usize] = 2.2f64
    x[5usize] = 2.9f64
    x[6usize] = 1.9f64
    x[7usize] = 2.2f64
    x[8usize] = 3.1f64
    x[9usize] = 3.0f64
    x[10usize] = 2.3f64
    x[11usize] = 2.7f64
    x[12usize] = 2.0f64
    x[13usize] = 1.6f64
    x[14usize] = 1.0f64
    x[15usize] = 1.1f64
    x[16usize] = 1.5f64
    x[17usize] = 1.6f64
    x[18usize] = 1.1f64
    x[19usize] = 0.9f64
    var mean: [2]f64 = zero
    var variances: [2]f64 = zero
    var components: [4]f64 = zero
    var scratch: [512]f64 = zero

    // 1: PCA.
    if reduce.pca(x[..], 10usize, 2usize, mean[..], variances[..], components[..], scratch[..]) != ok { os.exit(1i32) }
    if !near(mean[0usize], 1.81f64, 0.000000001f64) || !near(mean[1usize], 1.91f64, 0.000000001f64) { os.exit(1i32) }
    if !near(variances[0usize], 1.28402771f64, 0.00000001f64) || !near(variances[1usize], 0.0490834f64, 0.00000001f64) { os.exit(1i32) }
    var first: [2]f64 = zero
    first[0usize] = 0.6778734f64
    first[1usize] = 0.73517866f64
    if !same_direction(components[..2usize], first[..], 0.00000001f64) { os.exit(1i32) }
    var projected: [2]f64 = zero
    if reduce.pca_project(x[..2usize], mean[..], components[..], 2usize, 2usize, projected[..]) != ok { os.exit(1i32) }
    var p0 = projected[0usize]
    if p0 < 0.0f64 { p0 = 0.0f64 - p0 }
    var p1 = projected[1usize]
    if p1 < 0.0f64 { p1 = 0.0f64 - p1 }
    if !near(p0, 0.82797019f64, 0.00000001f64) || !near(p1, 0.17511531f64, 0.00000001f64) { os.exit(1i32) }
    if reduce.pca(x[..], 1usize, 2usize, mean[..], variances[..], components[..], scratch[..]) != reduce.Invalid { os.exit(1i32) }
    if reduce.pca(x[..], 10usize, 2usize, mean[..], variances[..], components[..], scratch[..3usize]) != reduce.TooSmall { os.exit(1i32) }

    // 2: Oja's rule over the centred points, many passes.
    var w: [2]f64 = zero
    w[0usize] = 1.0f64
    var centred: [2]f64 = zero
    var pass = 0usize
    while pass < 200usize {
        var i = 0usize
        while i < 10usize {
            centred[0usize] = x[2usize * i] - mean[0usize]
            centred[1usize] = x[2usize * i + 1usize] - mean[1usize]
            let (_, oja_error) = reduce.pca_online(w[..], centred[..], 0.01f64)
            if oja_error != ok { os.exit(2i32) }
            i += 1usize
        }
        pass += 1usize
    }
    if !same_direction(w[..], first[..], 0.001f64) { os.exit(2i32) }
    let (_, oja_room) = reduce.pca_online(w[..], centred[..1usize], 0.01f64)
    if oja_room != reduce.TooSmall { os.exit(2i32) }

    // 3: frequent directions with a four-row sketch over the same points, twice through.
    var sketch: [8]f64 = zero
    var filled = 0usize
    pass = 0usize
    while pass < 2usize {
        var i = 0usize
        while i < 10usize {
            centred[0usize] = x[2usize * i] - mean[0usize]
            centred[1usize] = x[2usize * i + 1usize] - mean[1usize]
            if reduce.frequent_directions_insert(sketch[..], 4usize, 2usize, &filled, centred[..], scratch[..]) != ok { os.exit(3i32) }
            i += 1usize
        }
        pass += 1usize
    }
    if filled == 0usize || filled > 4usize { os.exit(3i32) }
    // The sketch covariance points along the first component: its leading eigenvector agrees.
    var gram: [4]f64 = zero
    var i = 0usize
    while i < filled {
        gram[0usize] += sketch[2usize * i] * sketch[2usize * i]
        gram[1usize] += sketch[2usize * i] * sketch[2usize * i + 1usize]
        gram[3usize] += sketch[2usize * i + 1usize] * sketch[2usize * i + 1usize]
        i += 1usize
    }
    gram[2usize] = gram[1usize]
    var gram_values: [2]f64 = zero
    var gram_vectors: [4]f64 = zero
    if reduce.symmetric_eigen(gram[..], 2usize, gram_values[..], gram_vectors[..], 0.000000000001f64, 50u32) != ok { os.exit(3i32) }
    if !same_direction(gram_vectors[..2usize], first[..], 0.05f64) { os.exit(3i32) }
    if reduce.frequent_directions_insert(sketch[..], 3usize, 2usize, &filled, centred[..], scratch[..]) != reduce.Invalid { os.exit(3i32) }

    // 4: t-SNE keeps three groups apart.
    var groups: [24]f64 = zero
    var r = rand.pcg64(5u64, 5u64)
    i = 0usize
    while i < 12usize {
        let g = i / 4usize
        groups[2usize * i] = f64(g) * 10.0f64 + rand.pcg64_f64(&r)
        groups[2usize * i + 1usize] = f64(g % 2usize) * 10.0f64 + rand.pcg64_f64(&r)
        i += 1usize
    }
    var y: [24]f64 = zero
    i = 0usize
    while i < 24usize {
        y[i] = 0.01f64 * (rand.pcg64_f64(&r) - 0.5f64)
        i += 1usize
    }
    let (big, big_error) = mem.alloc[f64](a, 2usize * 144usize + 7usize * 12usize)
    if big_error != ok { ret big_error }
    if reduce.tsne(groups[..], 12usize, 2usize, 3.0f64, 300u32, 10.0f64, 0.5f64, y[..], big) != ok { os.exit(4i32) }
    // Every within-group distance is smaller than every between-group distance.
    var largest_within = 0.0f64
    var smallest_between = 1.0e300f64
    i = 0usize
    while i < 12usize {
        var j = i + 1usize
        while j < 12usize {
            let dx = y[2usize * i] - y[2usize * j]
            let dy = y[2usize * i + 1usize] - y[2usize * j + 1usize]
            let dist = math.sqrt[f64](dx * dx + dy * dy)
            if i / 4usize == j / 4usize {
                if dist > largest_within { largest_within = dist }
            } else if dist < smallest_between {
                smallest_between = dist
            }
            j += 1usize
        }
        i += 1usize
    }
    if largest_within >= smallest_between { os.exit(4i32) }
    if reduce.tsne(groups[..], 12usize, 2usize, 12.0f64, 10u32, 10.0f64, 0.5f64, y[..], big) != reduce.Invalid { os.exit(4i32) }
    if reduce.tsne(groups[..], 12usize, 2usize, 3.0f64, 10u32, 10.0f64, 0.5f64, y[..], big[..10usize]) != reduce.TooSmall { os.exit(4i32) }

    try io.print("ml reduce ok\n")
    ret ok
}
