// Dimensionality reduction over row-major `f64` samples in caller storage:
// `pca` (the covariance eigendecomposition by cyclic Jacobi rotations,
// components by falling variance) with `pca_project`, `pca_online` (Oja's
// rule for the leading component from a stream), `frequent_directions` (the
// deterministic sketch shrinking by its middle singular value) and `tsne`
// (exact t-SNE with a perplexity search and momentum gradient descent).

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
