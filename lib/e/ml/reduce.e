// Dimensionality reduction over row-major `f64` samples in caller storage:
// `pca` (the covariance eigendecomposition by cyclic Jacobi rotations,
// components by falling variance) with `pca_project`, `pca_online` (Oja's
// rule for the leading component from a stream), `frequent_directions` (the
// deterministic sketch shrinking by its middle singular value), `tsne`
// (exact t-SNE with a perplexity search and momentum gradient descent) and
// `umap` (exact neighbourhoods, smooth-kNN fuzzy affinities, a PCA start
// and cross-entropy SGD with uniform negative samples).

use e.algo.rand
use e.math

error TooSmall
error Invalid

// Eigenvalues (falling) and eigenvectors (rows of `vectors`, matching order)
// of the symmetric `d × d` matrix `a`, which is destroyed; cyclic Jacobi
// until the off-diagonal mass is under `tolerance` or `sweeps` pass.
fn symmetric_eigen(a: []f64, d: usize, values: []f64, vectors: []f64, tolerance: f64, sweeps: u32) -> err {
    if a.len < d * d || values.len < d || vectors.len < d * d { ret TooSmall }
    var i = 0usize
    while i < d * d {
        vectors[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < d {
        vectors[i * d + i] = 1.0f64
        i += 1usize
    }
    var sweep = 0u32
    var off = tolerance + 1.0f64
    while sweep < sweeps && off > tolerance {
        off = 0.0f64
        var p = 0usize
        while p < d {
            var q = p + 1usize
            while q < d {
                let apq = a[p * d + q]
                off += apq * apq
                if math.abs[f64](apq) > 1.0e-300f64 {
                    let theta = (a[q * d + q] - a[p * d + p]) / (2.0f64 * apq)
                    var t = 1.0f64 / (math.abs[f64](theta) + math.sqrt[f64](theta * theta + 1.0f64))
                    if theta < 0.0f64 { t = 0.0f64 - t }
                    let c = 1.0f64 / math.sqrt[f64](t * t + 1.0f64)
                    let s = t * c
                    // Rotate rows and columns p, q.
                    var k = 0usize
                    while k < d {
                        let akp = a[k * d + p]
                        let akq = a[k * d + q]
                        a[k * d + p] = c * akp - s * akq
                        a[k * d + q] = s * akp + c * akq
                        k += 1usize
                    }
                    k = 0usize
                    while k < d {
                        let apk = a[p * d + k]
                        let aqk = a[q * d + k]
                        a[p * d + k] = c * apk - s * aqk
                        a[q * d + k] = s * apk + c * aqk
                        k += 1usize
                    }
                    k = 0usize
                    while k < d {
                        let vkp = vectors[p * d + k]
                        let vkq = vectors[q * d + k]
                        vectors[p * d + k] = c * vkp - s * vkq
                        vectors[q * d + k] = s * vkp + c * vkq
                        k += 1usize
                    }
                }
                q += 1usize
            }
            p += 1usize
        }
        sweep += 1u32
    }
    i = 0usize
    while i < d {
        values[i] = a[i * d + i]
        i += 1usize
    }
    // Sort by falling eigenvalue, carrying the vectors (selection sort).
    i = 0usize
    while i < d {
        var best = i
        var j = i + 1usize
        while j < d {
            if values[j] > values[best] { best = j }
            j += 1usize
        }
        if best != i {
            let t = values[i]
            values[i] = values[best]
            values[best] = t
            var k = 0usize
            while k < d {
                let v = vectors[i * d + k]
                vectors[i * d + k] = vectors[best * d + k]
                vectors[best * d + k] = v
                k += 1usize
            }
        }
        i += 1usize
    }
    ret ok
}

// PCA of `x` (`n × d`): `mean` (`d`), `variances` (`d`, falling) and
// `components` (`d × d`, one per row); `scratch.len >= d * d`.
fn pca(x: []const f64, n: usize, d: usize, mean: []f64, variances: []f64, components: []f64, scratch: []f64) -> err {
    if x.len < n * d || mean.len < d || variances.len < d || components.len < d * d || scratch.len < d * d { ret TooSmall }
    if n < 2usize || d == 0usize { ret Invalid }
    var j = 0usize
    while j < d {
        mean[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        j = 0usize
        while j < d {
            mean[j] += x[i * d + j] / f64(n)
            j += 1usize
        }
        i += 1usize
    }
    var covariance = scratch[..d * d]
    j = 0usize
    while j < d * d {
        covariance[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        var a = 0usize
        while a < d {
            var b = 0usize
            while b < d {
                covariance[a * d + b] += (x[i * d + a] - mean[a]) * (x[i * d + b] - mean[b]) / f64(n - 1usize)
                b += 1usize
            }
            a += 1usize
        }
        i += 1usize
    }
    ret symmetric_eigen(covariance, d, variances, components, 1.0e-20f64, 100u32)
}

// The first `k` coordinates of `sample` in the component basis.
fn pca_project(sample: []const f64, mean: []const f64, components: []const f64, d: usize, k: usize, out: []f64) -> err {
    if sample.len < d || mean.len < d || components.len < k * d || out.len < k { ret TooSmall }
    var c = 0usize
    while c < k {
        var s = 0.0f64
        var j = 0usize
        while j < d {
            s += (sample[j] - mean[j]) * components[c * d + j]
            j += 1usize
        }
        out[c] = s
        c += 1usize
    }
    ret ok
}

// Oja's rule: `w += rate y (x - y w)` with `y = w·x`, then normalised; the
// caller centres its stream. Answers `y`.
fn pca_online(w: []f64, sample: []const f64, rate: f64) -> (f64, err) {
    let d = w.len
    if sample.len < d { ret (0.0f64, TooSmall) }
    var y = 0.0f64
    var j = 0usize
    while j < d {
        y += w[j] * sample[j]
        j += 1usize
    }
    var norm = 0.0f64
    j = 0usize
    while j < d {
        w[j] += rate * y * (sample[j] - y * w[j])
        norm += w[j] * w[j]
        j += 1usize
    }
    if norm > 0.0f64 {
        norm = math.sqrt[f64](norm)
        j = 0usize
        while j < d {
            w[j] = w[j] / norm
            j += 1usize
        }
    }
    ret (y, ok)
}

// Frequent directions: `sketch` holds `rows × d` (`rows` even); `insert`
// appends `sample` and, when the sketch is full, shrinks it so its top half
// survives: with `S = U Σ Vᵀ`, `S' = sqrt(Σ² - σ²_{rows/2} I) Vᵀ`. `filled`
// counts the used rows. `scratch.len >= 2 rows² + rows + rows d`.
fn frequent_directions_insert(sketch: []f64, rows: usize, d: usize, filled: *usize, sample: []const f64, scratch: []f64) -> err {
    if sketch.len < rows * d || sample.len < d || scratch.len < 2usize * rows * rows + rows + rows * d { ret TooSmall }
    if rows < 2usize || rows % 2usize != 0usize { ret Invalid }
    if *filled >= rows {
        var gram = scratch[..rows * rows]
        var vectors = scratch[rows * rows..2usize * rows * rows]
        var values = scratch[2usize * rows * rows..2usize * rows * rows + rows]
        var fresh = scratch[2usize * rows * rows + rows..2usize * rows * rows + rows + rows * d]
        // S Sᵀ: its eigenvalues are σ² and its eigenvectors the left singular vectors.
        var a = 0usize
        while a < rows {
            var b = 0usize
            while b < rows {
                var s = 0.0f64
                var j = 0usize
                while j < d {
                    s += sketch[a * d + j] * sketch[b * d + j]
                    j += 1usize
                }
                gram[a * rows + b] = s
                b += 1usize
            }
            a += 1usize
        }
        let eigen_error = symmetric_eigen(gram, rows, values, vectors, 1.0e-24f64, 100u32)
        if eigen_error != ok { ret eigen_error }
        let delta = values[rows / 2usize]
        // Row i of the shrunk sketch: sqrt(σ_i² - δ) v_iᵀ = sqrt((σ_i² - δ) / σ_i²) (u_iᵀ S).
        var i = 0usize
        while i < rows {
            var factor = 0.0f64
            if i < rows / 2usize && values[i] > delta && values[i] > 0.0f64 { factor = math.sqrt[f64]((values[i] - delta) / values[i]) }
            var j = 0usize
            while j < d {
                var s = 0.0f64
                var b = 0usize
                while b < rows {
                    s += vectors[i * rows + b] * sketch[b * d + j]
                    b += 1usize
                }
                fresh[i * d + j] = s * factor
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < rows * d {
            sketch[i] = fresh[i]
            i += 1usize
        }
        *filled = rows / 2usize
    }
    var j = 0usize
    while j < d {
        sketch[*filled * d + j] = sample[j]
        j += 1usize
    }
    *filled += 1usize
    ret ok
}

// Exact t-SNE of `x` (`n × d`) into `y` (`n × 2`, started by the caller,
// e.g. small random values): Gaussian affinities at `perplexity` (a binary
// search per point over `steps` refinements), symmetrised, and
// `iterations` of gradient descent with `rate` and `momentum`.
// `scratch.len >= 2 n² + 3 n + 4 n`.
fn tsne(x: []const f64, n: usize, d: usize, perplexity: f64, iterations: u32, rate: f64, momentum: f64, y: []f64, scratch: []f64) -> err {
    if x.len < n * d || y.len < 2usize * n || scratch.len < 2usize * n * n + 7usize * n { ret TooSmall }
    if n < 3usize || perplexity <= 1.0f64 || perplexity >= f64(n) { ret Invalid }
    var p = scratch[..n * n]
    var q = scratch[n * n..2usize * n * n]
    var at = 2usize * n * n
    var distances = scratch[at..at + n]
    at += n
    var velocity = scratch[at..at + 2usize * n]
    at += 2usize * n
    var gradient = scratch[at..at + 2usize * n]
    at += 2usize * n
    let target_entropy = math.log[f64](perplexity)
    // Conditional affinities row by row with a precision found by bisection.
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = 0.0f64
            var k = 0usize
            while k < d {
                let t = x[i * d + k] - x[j * d + k]
                s += t * t
                k += 1usize
            }
            distances[j] = s
            j += 1usize
        }
        var beta = 1.0f64
        var low = 0.0f64
        var high = 0.0f64
        var have_high = false
        var tries = 0usize
        while tries < 50usize {
            var total = 0.0f64
            var weighted = 0.0f64
            j = 0usize
            while j < n {
                if j != i {
                    let w = math.exp[f64](0.0f64 - beta * distances[j])
                    p[i * n + j] = w
                    total += w
                    weighted += w * distances[j]
                } else {
                    p[i * n + j] = 0.0f64
                }
                j += 1usize
            }
            let entropy = math.log[f64](total) + beta * weighted / total
            j = 0usize
            while j < n {
                p[i * n + j] = p[i * n + j] / total
                j += 1usize
            }
            if math.abs[f64](entropy - target_entropy) < 1.0e-5f64 {
                tries = 50usize
            } else {
                if entropy > target_entropy {
                    low = beta
                    if have_high { beta = 0.5f64 * (beta + high) } else { beta = beta * 2.0f64 }
                } else {
                    high = beta
                    have_high = true
                    beta = 0.5f64 * (beta + low)
                }
                tries += 1usize
            }
        }
        i += 1usize
    }
    // Symmetrise: p_ij = (p_i|j + p_j|i) / 2n.
    i = 0usize
    while i < n {
        var j = i + 1usize
        while j < n {
            let v = (p[i * n + j] + p[j * n + i]) / (2.0f64 * f64(n))
            p[i * n + j] = v
            p[j * n + i] = v
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < 2usize * n {
        velocity[i] = 0.0f64
        i += 1usize
    }
    var iteration = 0u32
    while iteration < iterations {
        // Student-t affinities.
        var total = 0.0f64
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                if j != i {
                    let dx = y[2usize * i] - y[2usize * j]
                    let dy = y[2usize * i + 1usize] - y[2usize * j + 1usize]
                    q[i * n + j] = 1.0f64 / (1.0f64 + dx * dx + dy * dy)
                    total += q[i * n + j]
                } else {
                    q[i * n + j] = 0.0f64
                }
                j += 1usize
            }
            i += 1usize
        }
        i = 0usize
        while i < n {
            var gx = 0.0f64
            var gy = 0.0f64
            var j = 0usize
            while j < n {
                if j != i {
                    let kernel = q[i * n + j]
                    let coefficient = 4.0f64 * (p[i * n + j] - kernel / total) * kernel
                    gx += coefficient * (y[2usize * i] - y[2usize * j])
                    gy += coefficient * (y[2usize * i + 1usize] - y[2usize * j + 1usize])
                }
                j += 1usize
            }
            gradient[2usize * i] = gx
            gradient[2usize * i + 1usize] = gy
            i += 1usize
        }
        i = 0usize
        while i < 2usize * n {
            velocity[i] = momentum * velocity[i] - rate * gradient[i]
            y[i] += velocity[i]
            i += 1usize
        }
        iteration += 1u32
    }
    ret ok
}

// Frequent directions (Liberty) of `x` (`n × d`) into `sketch` (`rows ×
// d`, `rows = 2 ℓ` even): every row goes through
// `frequent_directions_insert`, so `‖AᵀA − BᵀB‖₂ <= ‖A‖²_F / ℓ` over the
// filled rows, whose count is answered. `scratch` as for the insert.
fn frequent_directions(x: []const f64, n: usize, d: usize, sketch: []f64, rows: usize, scratch: []f64) -> (usize, err) {
    if x.len < n * d { ret (0usize, TooSmall) }
    var filled = 0usize
    var i = 0usize
    while i < n {
        let insert_error = frequent_directions_insert(sketch, rows, d, &filled, x[i * d..(i + 1usize) * d], scratch)
        if insert_error != ok { ret (0usize, insert_error) }
        i += 1usize
    }
    ret (filled, ok)
}

// The fuzzy affinity of one row of `k` neighbour distances at `rho` and
// `sigma`: the `exp(-max(d - rho, 0) / sigma)` sum, `goal` (`log2(k)` in
// `umap`) at the right scale.
fn umap_affinity(dist: []const f64, k: usize, rho: f64, sigma: f64) -> f64 {
    var total = 0.0f64
    var t = 0usize
    while t < k {
        var excess = dist[t] - rho
        if excess < 0.0f64 { excess = 0.0f64 }
        total += math.exp[f64](0.0f64 - excess / sigma)
        t += 1usize
    }
    ret total
}

// The smooth-kNN scale with `affinity == goal`: halved from 1 until the
// sum obeys (at most 1024 halvings), then bisected 64 rounds; floored at
// 1e-12 so a duplicated neighbourhood stays finite.
fn umap_sigma(dist: []const f64, k: usize, rho: f64, goal: f64) -> f64 {
    var hi = 1.0f64
    while hi > 1.0e-300f64 && umap_affinity(dist, k, rho, hi) > goal {
        hi = hi / 2.0f64
    }
    var lo = 0.0f64
    var step = 0u32
    while step < 64u32 {
        let mid = (lo + hi) / 2.0f64
        if mid > 0.0f64 && umap_affinity(dist, k, rho, mid) > goal {
            hi = mid
        } else {
            lo = mid
        }
        step += 1u32
    }
    ret math.max[f64]((lo + hi) / 2.0f64, 0.000000000001f64)
}

// Uniform manifold approximation of `x` (`n × d`) into `y` (`n × 2`):
// exact `neighbors` neighbourhoods, smooth-kNN fuzzy affinities at
// `log2(neighbors)` symmetrized by `a + b - a b`, a PCA start scaled to
// span 10 per axis (not the spectral embedding), and `epochs` of
// cross-entropy SGD at a linearly decaying `rate` with `negatives` uniform
// negative samples drawn through `r` (head-point updates only, gradient
// coefficients clipped at 4). Attraction skips coincident pairs. Distances
// are squared throughout, and `a`/`b` are the curve pair directly (1.576
// and 0.895 at the usual spread). `fscratch.len >= n * n + n * neighbors +
// 2 * d * d + 2 * d + 2 * n` holds distances, the fuzzy matrix and the PCA
// and neighbourhood temporaries; `iscratch.len >= n * neighbors` the
// neighbour indices. Zero `epochs` keeps the PCA start.
fn umap(x: []const f64, n: usize, d: usize, neighbors: usize, a: f64, b: f64, epochs: u32, rate: f64, negatives: usize, y: []f64, r: *rand.Pcg64, fscratch: []f64, iscratch: []usize) -> err {
    let k = neighbors
    if x.len < n * d || y.len < 2usize * n || fscratch.len < n * n + n * k + 2usize * d * d + 2usize * d + 2usize * n || iscratch.len < n * k { ret TooSmall }
    if n == 0usize || d < 2usize || k < 2usize || k >= n || a <= 0.0f64 || b <= 0.0f64 { ret Invalid }
    var dists = fscratch[..n * k]
    var fuzzy = fscratch[n * k..n * k + n * n]
    var at = n * k + n * n
    var mean = fscratch[at..at + d]
    at += d
    var variances = fscratch[at..at + d]
    at += d
    var components = fscratch[at..at + d * d]
    at += d * d
    var workspace = fscratch[at..at + d * d]
    at += d * d
    var rho = fscratch[at..at + n]
    at += n
    var sigma = fscratch[at..at + n]
    var idx = iscratch[..n * k]
    // Exact neighbourhoods by sorted-prefix insertion, ties to the lower index.
    var i = 0usize
    while i < n {
        var count = 0usize
        var j = 0usize
        while j < n {
            if j != i {
                var dd = 0.0f64
                var c = 0usize
                while c < d {
                    let t = x[i * d + c] - x[j * d + c]
                    dd += t * t
                    c += 1usize
                }
                if count < k || dd < dists[i * k + k - 1usize] {
                    var place = count
                    if place == k { place = k - 1usize }
                    while place > 0usize && dists[i * k + place - 1usize] > dd {
                        dists[i * k + place] = dists[i * k + place - 1usize]
                        idx[i * k + place] = idx[i * k + place - 1usize]
                        place -= 1usize
                    }
                    dists[i * k + place] = dd
                    idx[i * k + place] = j
                    if count < k { count += 1usize }
                }
            }
            j += 1usize
        }
        rho[i] = dists[i * k]
        i += 1usize
    }
    // Fuzzy affinities, symmetrized in place.
    let goal = math.log2[f64](f64(k))
    i = 0usize
    while i < n * n {
        fuzzy[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        sigma[i] = umap_sigma(dists[i * k..(i + 1usize) * k], k, rho[i], goal)
        var t = 0usize
        while t < k {
            var excess = dists[i * k + t] - rho[i]
            if excess < 0.0f64 { excess = 0.0f64 }
            fuzzy[i * n + idx[i * k + t]] = math.exp[f64](0.0f64 - excess / sigma[i])
            t += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            let fwd = fuzzy[i * n + j]
            let bwd = fuzzy[j * n + i]
            fuzzy[i * n + j] = fwd + bwd - fwd * bwd
            j += 1usize
        }
        i += 1usize
    }
    // PCA start: every row projected once, then each axis scaled to span 10
    // (projecting per axis would clobber the scaled axes through the shared
    // rows, since one projection writes both coordinates).
    let pca_error = pca(x, n, d, mean, variances, components, workspace)
    if pca_error != ok { ret pca_error }
    i = 0usize
    while i < n {
        let project_error = pca_project(x[i * d..(i + 1usize) * d], mean, components, d, 2usize, y[i * 2usize..(i + 1usize) * 2usize])
        if project_error != ok { ret project_error }
        i += 1usize
    }
    var c = 0usize
    while c < 2usize {
        var lo = y[c]
        var hi = y[c]
        i = 1usize
        while i < n {
            if y[i * 2usize + c] < lo { lo = y[i * 2usize + c] }
            if y[i * 2usize + c] > hi { hi = y[i * 2usize + c] }
            i += 1usize
        }
        i = 0usize
        while i < n {
            if hi > lo {
                y[i * 2usize + c] = 10.0f64 * (y[i * 2usize + c] - lo) / (hi - lo) - 5.0f64
            } else {
                y[i * 2usize + c] = 0.0f64
            }
            i += 1usize
        }
        c += 1usize
    }
    // Cross-entropy SGD, head-point updates, linearly decaying rate.
    var ep = 0u32
    while ep < epochs {
        let step = rate * (1.0f64 - f64(ep) / f64(epochs))
        i = 0usize
        while i < n {
            var j = 0usize
            while j < n {
                let wgt = fuzzy[i * n + j]
                if wgt > 0.0f64 {
                    let dx = y[2usize * i] - y[2usize * j]
                    let dy = y[2usize * i + 1usize] - y[2usize * j + 1usize]
                    let d2 = dx * dx + dy * dy
                    if d2 >= 0.000000000001f64 {
                        var coeff = 2.0f64 * a * b * math.pow[f64](d2, b - 1.0f64) / (1.0f64 + a * math.pow[f64](d2, b)) * wgt
                        if coeff > 4.0f64 { coeff = 4.0f64 }
                        y[2usize * i] += step * coeff * (y[2usize * j] - y[2usize * i])
                        y[2usize * i + 1usize] += step * coeff * (y[2usize * j + 1usize] - y[2usize * i + 1usize])
                    }
                    var s = 0usize
                    while s < negatives {
                        let v = usize(rand.pcg64_bounded(r, u64(n)))
                        if v != i {
                            let ex = y[2usize * i] - y[2usize * v]
                            let ey = y[2usize * i + 1usize] - y[2usize * v + 1usize]
                            let e2 = ex * ex + ey * ey
                            var push = 2.0f64 * b / ((0.001f64 + e2) * (1.0f64 + a * math.pow[f64](e2, b)))
                            if push > 4.0f64 { push = 4.0f64 }
                            y[2usize * i] += step * push * (y[2usize * i] - y[2usize * v])
                            y[2usize * i + 1usize] += step * push * (y[2usize * i + 1usize] - y[2usize * v + 1usize])
                        }
                        s += 1usize
                    }
                }
                j += 1usize
            }
            i += 1usize
        }
        ep += 1u32
    }
    ret ok
}
