// Classical multivariate analysis over row-major `f64` samples in caller
// storage: linear and quadratic discriminant analysis (Gaussian classes with a
// pooled or a per-class covariance, posteriors by softmax), maximum-likelihood
// factor analysis (scikit-learn's SVD iteration, with a varimax rotation),
// canonical correlation analysis with Bartlett's test, and one-way MANOVA
// with Wilks, Pillai, Hotelling-Lawley and Roy statistics and their F
// approximations.
//
// Everything sits on one symmetric eigen solver (`e.ml.reduce`) and a Cholesky
// factorisation, so eigenvectors are only defined up to sign: loadings and
// canonical weights are normalised so the entry of largest magnitude in each
// row is positive. Group labels are `usize` in `0..groups`.

use e.math
use e.math.special
use e.ml.reduce as reduce

error TooSmall
error Invalid
error Singular

type Discriminant = struct { classes: usize, features: usize, quadratic: bool, means: []f64, priors: []f64, factors: []f64, log_det: []f64 }
type FactorFit = struct { iterations: u32, log_likelihood: f64 }
type ManovaTest = struct { statistic: f64, f: f64, df1: f64, df2: f64, p_value: f64 }
type Manova = struct { wilks: ManovaTest, pillai: ManovaTest, hotelling: ManovaTest, roy: ManovaTest }

// In-place lower Cholesky factor of the symmetric positive definite `d x d`
// matrix `a` (the upper triangle is zeroed); `Singular` when it is not.
fn cholesky_in_place(a: []f64, d: usize) -> err {
    var j = 0usize
    while j < d {
        var s = a[j * d + j]
        let original = s
        var k = 0usize
        while k < j {
            s -= a[j * d + k] * a[j * d + k]
            k += 1usize
        }
        if !(s > 1.0e-12f64 * math.abs[f64](original)) || !(s > 0.0f64) { ret Singular }
        let root = math.sqrt[f64](s)
        a[j * d + j] = root
        var i = j + 1usize
        while i < d {
            var t = a[i * d + j]
            k = 0usize
            while k < j {
                t -= a[i * d + k] * a[j * d + k]
                k += 1usize
            }
            a[i * d + j] = t / root
            i += 1usize
        }
        k = j + 1usize
        while k < d {
            a[j * d + k] = 0.0f64
            k += 1usize
        }
        j += 1usize
    }
    ret ok
}

// Solve `L x = b` for the lower triangle `l`, in place.
fn solve_lower(l: []const f64, d: usize, b: []f64) {
    var i = 0usize
    while i < d {
        var s = b[i]
        var k = 0usize
        while k < i {
            s -= l[i * d + k] * b[k]
            k += 1usize
        }
        b[i] = s / l[i * d + i]
        i += 1usize
    }
}

// Solve `Lᵀ x = b` for the lower triangle `l`, in place.
fn solve_lower_transpose(l: []const f64, d: usize, b: []f64) {
    var i = d
    while i > 0usize {
        i -= 1usize
        var s = b[i]
        var k = i + 1usize
        while k < d {
            s -= l[k * d + i] * b[k]
            k += 1usize
        }
        b[i] = s / l[i * d + i]
    }
}

// Column means and the `d x d` covariance of `n` rows, divided by `n - 1`
// when `unbiased` and by `n` otherwise.
fn covariance_matrix(x: []const f64, n: usize, d: usize, unbiased: bool, mean: []f64, cov: []f64) -> err {
    if n < 2usize || d == 0usize { ret Invalid }
    if x.len < n * d || mean.len < d || cov.len < d * d { ret TooSmall }
    var j = 0usize
    while j < d {
        mean[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        j = 0usize
        while j < d {
            mean[j] += x[i * d + j]
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < d {
        mean[j] = mean[j] / f64(n)
        j += 1usize
    }
    i = 0usize
    while i < d * d {
        cov[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var a = 0usize
        while a < d {
            let da = x[i * d + a] - mean[a]
            var b = 0usize
            while b <= a {
                cov[a * d + b] += da * (x[i * d + b] - mean[b])
                b += 1usize
            }
            a += 1usize
        }
        i += 1usize
    }
    var divisor = f64(n)
    if unbiased { divisor = f64(n - 1usize) }
    var a = 0usize
    while a < d {
        var b = 0usize
        while b <= a {
            cov[a * d + b] = cov[a * d + b] / divisor
            cov[b * d + a] = cov[a * d + b]
            b += 1usize
        }
        a += 1usize
    }
    ret ok
}

// Flip each of the `rows` vectors of length `width` so that its entry of
// largest magnitude is positive.
fn normalize_signs(values: []f64, rows: usize, width: usize) {
    var r = 0usize
    while r < rows {
        var big = 0usize
        var c = 1usize
        while c < width {
            if math.abs[f64](values[r * width + c]) > math.abs[f64](values[r * width + big]) { big = c }
            c += 1usize
        }
        if values[r * width + big] < 0.0f64 {
            c = 0usize
            while c < width {
                values[r * width + c] = 0.0f64 - values[r * width + c]
                c += 1usize
            }
        }
        r += 1usize
    }
}

// Fit a Gaussian discriminant model. `model` carries the caller's slices:
// `means` (classes * d), `priors` (classes), `factors` (d * d, or classes * d * d
// when `quadratic`), `log_det` (1, or classes). `class_priors` is empty for the
// empirical priors. Linear pools the within-class scatter and quadratic uses each
// class's own, divided by `n - classes` (`n_k - 1`) when `unbiased` and by `n`
// (`n_k`) otherwise -- the maximum-likelihood form scikit-learn's solvers and
// `QuadraticDiscriminantAnalysis` use -- the quadratic ones shrunk toward the
// identity by `reg` (`reg_param`).
// `scratch.len >= classes + d * d`.
fn discriminant_fit(x: []const f64, labels: []const usize, n: usize, d: usize, classes: usize, quadratic: bool, unbiased: bool, reg: f64, class_priors: []const f64, model: *Discriminant, scratch: []f64) -> err {
    if n == 0usize || d == 0usize || classes < 2usize || n <= classes { ret Invalid }
    if x.len < n * d || labels.len < n || scratch.len < classes + d * d || reg < 0.0f64 || reg > 1.0f64 { ret TooSmall }
    if model.means.len < classes * d || model.priors.len < classes { ret TooSmall }
    var need = d * d
    var dets = 1usize
    if quadratic {
        need = classes * d * d
        dets = classes
    }
    if model.factors.len < need || model.log_det.len < dets { ret TooSmall }
    if class_priors.len != 0usize && class_priors.len < classes { ret TooSmall }
    var counts = scratch[..classes]
    var c = 0usize
    while c < classes {
        counts[c] = 0.0f64
        c += 1usize
    }
    var j = 0usize
    while j < classes * d {
        model.means[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        if labels[i] >= classes { ret Invalid }
        counts[labels[i]] += 1.0f64
        j = 0usize
        while j < d {
            model.means[labels[i] * d + j] += x[i * d + j]
            j += 1usize
        }
        i += 1usize
    }
    c = 0usize
    while c < classes {
        if counts[c] < 2.0f64 { ret Invalid }
        j = 0usize
        while j < d {
            model.means[c * d + j] = model.means[c * d + j] / counts[c]
            j += 1usize
        }
        if class_priors.len == 0usize { model.priors[c] = counts[c] / f64(n) } else { model.priors[c] = class_priors[c] }
        c += 1usize
    }
    // Scatter into `factors`: one pooled block, or one block per class.
    j = 0usize
    while j < need {
        model.factors[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        var block = 0usize
        if quadratic { block = labels[i] * d * d }
        var a = 0usize
        while a < d {
            let da = x[i * d + a] - model.means[labels[i] * d + a]
            var b = 0usize
            while b <= a {
                model.factors[block + a * d + b] += da * (x[i * d + b] - model.means[labels[i] * d + b])
                b += 1usize
            }
            a += 1usize
        }
        i += 1usize
    }
    var blocks = 1usize
    if quadratic { blocks = classes }
    var blk = 0usize
    while blk < blocks {
        var divisor = f64(n)
        if unbiased { divisor = f64(n - classes) }
        if quadratic {
            divisor = counts[blk]
            if unbiased { divisor = counts[blk] - 1.0f64 }
        }
        var a = 0usize
        while a < d {
            var b = 0usize
            while b <= a {
                var v = model.factors[blk * d * d + a * d + b] / divisor
                if quadratic && reg > 0.0f64 {
                    v = (1.0f64 - reg) * v
                    if a == b { v += reg }
                }
                model.factors[blk * d * d + a * d + b] = v
                model.factors[blk * d * d + b * d + a] = v
                b += 1usize
            }
            a += 1usize
        }
        if cholesky_in_place(model.factors[blk * d * d..blk * d * d + d * d], d) != ok { ret Singular }
        var log_det = 0.0f64
        a = 0usize
        while a < d {
            log_det += 2.0f64 * math.log[f64](model.factors[blk * d * d + a * d + a])
            a += 1usize
        }
        model.log_det[blk] = log_det
        blk += 1usize
    }
    model.classes = classes
    model.features = d
    model.quadratic = quadratic
    ret ok
}

// Per-class log joint `ln prior - (Mahalanobis^2 + ln det) / 2` of `sample`
// (the shared `d ln 2 pi / 2` dropped); `out.len >= classes`,
// `work.len >= d`.
fn discriminant_scores(model: *const Discriminant, sample: []const f64, out: []f64, work: []f64) -> err {
    let d = model.features
    if sample.len < d || out.len < model.classes || work.len < d { ret TooSmall }
    var c = 0usize
    while c < model.classes {
        var j = 0usize
        while j < d {
            work[j] = sample[j] - model.means[c * d + j]
            j += 1usize
        }
        var block = 0usize
        var det = model.log_det[0usize]
        if model.quadratic {
            block = c * d * d
            det = model.log_det[c]
        }
        solve_lower(model.factors[block..block + d * d], d, work[..d])
        var maha = 0.0f64
        j = 0usize
        while j < d {
            maha += work[j] * work[j]
            j += 1usize
        }
        out[c] = math.log[f64](model.priors[c]) - 0.5f64 * (maha + det)
        c += 1usize
    }
    ret ok
}

// Posterior class probabilities of `sample` (softmax of the scores).
fn discriminant_posterior(model: *const Discriminant, sample: []const f64, out: []f64, work: []f64) -> err {
    let e = discriminant_scores(model, sample, out, work)
    if e != ok { ret e }
    var top = out[0usize]
    var c = 1usize
    while c < model.classes {
        if out[c] > top { top = out[c] }
        c += 1usize
    }
    var total = 0.0f64
    c = 0usize
    while c < model.classes {
        out[c] = math.exp[f64](out[c] - top)
        total += out[c]
        c += 1usize
    }
    c = 0usize
    while c < model.classes {
        out[c] = out[c] / total
        c += 1usize
    }
    ret ok
}

// The most probable class of `sample`; `out.len >= classes`, `work.len >= d`.
fn discriminant_predict(model: *const Discriminant, sample: []const f64, out: []f64, work: []f64) -> (usize, err) {
    let e = discriminant_scores(model, sample, out, work)
    if e != ok { ret (0usize, e) }
    var best = 0usize
    var c = 1usize
    while c < model.classes {
        if out[c] > out[best] { best = c }
        c += 1usize
    }
    ret (best, ok)
}

// The orthogonal polar factor of the `c x c` matrix `m` (U Vᵀ of its SVD) into
// `rotation`, and the sum of its singular values; `scratch.len >= 3 c^2 + c`.
fn polar_factor(m: []const f64, c: usize, rotation: []f64, scratch: []f64) -> (f64, err) {
    var gram = scratch[..c * c]
    var values = scratch[c * c..c * c + c]
    var vectors = scratch[c * c + c..2usize * c * c + c]
    var inner = scratch[2usize * c * c + c..3usize * c * c + c]
    var i = 0usize
    while i < c {
        var j = 0usize
        while j < c {
            var s = 0.0f64
            var k = 0usize
            while k < c {
                s += m[k * c + i] * m[k * c + j]
                k += 1usize
            }
            gram[i * c + j] = s
            j += 1usize
        }
        i += 1usize
    }
    if reduce.symmetric_eigen(gram, c, values, vectors, 1.0e-26f64, 100u32) != ok { ret (0.0f64, Invalid) }
    var total = 0.0f64
    i = 0usize
    while i < c {
        if !(values[i] > 1.0e-300f64) { ret (0.0f64, Singular) }
        total += math.sqrt[f64](values[i])
        i += 1usize
    }
    // inner = V diag(lambda^-1/2) Vᵀ (vectors hold V as rows).
    i = 0usize
    while i < c {
        var j = 0usize
        while j < c {
            var s = 0.0f64
            var k = 0usize
            while k < c {
                s += vectors[k * c + i] * vectors[k * c + j] / math.sqrt[f64](values[k])
                k += 1usize
            }
            inner[i * c + j] = s
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < c {
        var j = 0usize
        while j < c {
            var s = 0.0f64
            var k = 0usize
            while k < c {
                s += m[i * c + k] * inner[k * c + j]
                k += 1usize
            }
            rotation[i * c + j] = s
            j += 1usize
        }
        i += 1usize
    }
    ret (total, ok)
}

// Maximum-likelihood factor analysis of `n` rows of `d` features into
// `components` factors, the iteration of scikit-learn's `FactorAnalysis`
// (SVD of the noise-scaled data, loadings `sqrt(max(s - 1, 0))`, noise
// variances from the unexplained diagonal) until the log-likelihood gain is
// under `tolerance`. `loadings` is `components x d` (rows sign-normalised),
// `noise` is `d`. `scratch.len >= 3 d^2 + 3 d + 1`.
fn factor_analysis(x: []const f64, n: usize, d: usize, components: usize, tolerance: f64, max_iterations: u32, loadings: []f64, noise: []f64, scratch: []f64) -> (FactorFit, err) {
    if components == 0usize || components >= d || n <= d { ret (zero, Invalid) }
    if x.len < n * d || loadings.len < components * d || noise.len < d || scratch.len < 3usize * d * d + 3usize * d + 1usize { ret (zero, TooSmall) }
    var mean = scratch[..d]
    var cov = scratch[d..d + d * d]
    var scaled = scratch[d + d * d..d + 2usize * d * d]
    var values = scratch[d + 2usize * d * d..2usize * d + 2usize * d * d]
    var vectors = scratch[2usize * d + 2usize * d * d..2usize * d + 3usize * d * d]
    var variance = scratch[2usize * d + 3usize * d * d..3usize * d + 3usize * d * d]
    if covariance_matrix(x, n, d, false, mean, cov) != ok { ret (zero, Invalid) }
    var j = 0usize
    while j < d {
        variance[j] = cov[j * d + j]
        noise[j] = 1.0f64
        j += 1usize
    }
    let small = 1.0e-12f64
    let llconst = f64(d) * 1.8378770664093453f64 + f64(components)
    var old = 0.0f64 - 1.0e300f64
    var fit: FactorFit = zero
    var iteration = 0u32
    while iteration < max_iterations {
        // Z = D^-1/2 S D^-1/2 with D = psi (+ small on the root).
        var a = 0usize
        while a < d {
            var b = 0usize
            while b < d {
                scaled[a * d + b] = cov[a * d + b] / ((math.sqrt[f64](noise[a]) + small) * (math.sqrt[f64](noise[b]) + small))
                b += 1usize
            }
            a += 1usize
        }
        if reduce.symmetric_eigen(scaled, d, values, vectors, 1.0e-26f64, 100u32) != ok { ret (zero, Invalid) }
        var c = 0usize
        while c < components {
            var shrink = values[c] - 1.0f64
            if shrink < 0.0f64 { shrink = 0.0f64 }
            let root = math.sqrt[f64](shrink)
            j = 0usize
            while j < d {
                loadings[c * d + j] = root * vectors[c * d + j] * (math.sqrt[f64](noise[j]) + small)
                j += 1usize
            }
            c += 1usize
        }
        var ll = llconst
        c = 0usize
        while c < components {
            ll += math.log[f64](values[c])
            c += 1usize
        }
        while c < d {
            ll += values[c]
            c += 1usize
        }
        j = 0usize
        while j < d {
            ll += math.log[f64](noise[j])
            j += 1usize
        }
        ll = ll * (0.0f64 - f64(n) / 2.0f64)
        iteration += 1u32
        fit.iterations = iteration
        fit.log_likelihood = ll
        if ll - old < tolerance { break }
        old = ll
        j = 0usize
        while j < d {
            var explained = 0.0f64
            c = 0usize
            while c < components {
                explained += loadings[c * d + j] * loadings[c * d + j]
                c += 1usize
            }
            var v = variance[j] - explained
            if v < small { v = small }
            noise[j] = v
            j += 1usize
        }
    }
    normalize_signs(loadings, components, d)
    ret (fit, ok)
}

// Varimax rotation (scikit-learn's SVD iteration with `gamma = 1`) of the
// `c x d` loadings in place, until the criterion gains less than a factor
// `1 + tolerance`; `scratch.len >= 6 c^2 + 2 c + c d`.
fn varimax(loadings: []f64, c: usize, d: usize, tolerance: f64, max_iterations: u32, scratch: []f64) -> err {
    if c == 0usize || d == 0usize || loadings.len < c * d { ret Invalid }
    let need = 6usize * c * c + 2usize * c + c * d
    if scratch.len < need { ret TooSmall }
    var rotation = scratch[..c * c]
    var next = scratch[c * c..2usize * c * c]
    var m = scratch[2usize * c * c..3usize * c * c]
    var rotated = scratch[3usize * c * c..3usize * c * c + c * d]
    var weights = scratch[3usize * c * c + c * d..3usize * c * c + c * d + c]
    var polar = scratch[3usize * c * c + c * d + c..need]
    var i = 0usize
    while i < c * c {
        rotation[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < c {
        rotation[i * c + i] = 1.0f64
        i += 1usize
    }
    var criterion = 0.0f64
    var iteration = 0u32
    while iteration < max_iterations {
        // rotated (d x c, stored feature-major) = components R, components = loadings transposed.
        var f = 0usize
        while f < d {
            var k = 0usize
            while k < c {
                var s = 0.0f64
                var t = 0usize
                while t < c {
                    s += loadings[t * d + f] * rotation[t * c + k]
                    t += 1usize
                }
                rotated[f * c + k] = s
                k += 1usize
            }
            f += 1usize
        }
        var k = 0usize
        while k < c {
            var s = 0.0f64
            f = 0usize
            while f < d {
                s += rotated[f * c + k] * rotated[f * c + k]
                f += 1usize
            }
            weights[k] = s / f64(d)
            k += 1usize
        }
        // M = componentsᵀ (rotated^3 - rotated * weights).
        var a = 0usize
        while a < c {
            var b = 0usize
            while b < c {
                var s = 0.0f64
                f = 0usize
                while f < d {
                    let r = rotated[f * c + b]
                    s += loadings[a * d + f] * (r * r * r - r * weights[b])
                    f += 1usize
                }
                m[a * c + b] = s
                b += 1usize
            }
            a += 1usize
        }
        let (total, e) = polar_factor(m, c, next, polar)
        if e != ok { ret e }
        i = 0usize
        while i < c * c {
            rotation[i] = next[i]
            i += 1usize
        }
        iteration += 1u32
        if criterion != 0.0f64 && total < criterion * (1.0f64 + tolerance) { break }
        criterion = total
    }
    // loadings <- (components R)ᵀ.
    var f = 0usize
    while f < d {
        var k = 0usize
        while k < c {
            var s = 0.0f64
            var t = 0usize
            while t < c {
                s += loadings[t * d + f] * rotation[t * c + k]
                t += 1usize
            }
            rotated[f * c + k] = s
            k += 1usize
        }
        f += 1usize
    }
    f = 0usize
    while f < d {
        var k = 0usize
        while k < c {
            loadings[k * d + f] = rotated[f * c + k]
            k += 1usize
        }
        f += 1usize
    }
    normalize_signs(loadings, c, d)
    ret ok
}

// Canonical correlation analysis of `x` (`n x p`) against `y` (`n x q`).
// `correlations` receives `min(p, q)` correlations falling; `x_weights`
// (`k x p`) and `y_weights` (`k x q`) the weights whose variates have unit
// sample variance, sign-normalised. `scratch.len >= 4 (p^2 + q^2 + p q) + 3 (p + q)`.
fn canonical_correlation(x: []const f64, y: []const f64, n: usize, p: usize, q: usize, correlations: []f64, x_weights: []f64, y_weights: []f64, scratch: []f64) -> err {
    if p == 0usize || q == 0usize || n <= p + q { ret Invalid }
    var k = p
    if q < k { k = q }
    if x.len < n * p || y.len < n * q || correlations.len < k || x_weights.len < k * p || y_weights.len < k * q { ret TooSmall }
    if scratch.len < 4usize * (p * p + q * q + p * q) + 3usize * (p + q) { ret TooSmall }
    var off = 0usize
    var mean_x = scratch[off..off + p]
    off += p
    var mean_y = scratch[off..off + q]
    off += q
    var sxx = scratch[off..off + p * p]
    off += p * p
    var syy = scratch[off..off + q * q]
    off += q * q
    var sxy = scratch[off..off + p * q]
    off += p * q
    var kmat = scratch[off..off + p * q]
    off += p * q
    var gram = scratch[off..off + p * p]
    off += p * p
    var values = scratch[off..off + p]
    off += p
    var vectors = scratch[off..off + p * p]
    off += p * p
    var column = scratch[off..off + p + q]
    off += p + q
    if covariance_matrix(x, n, p, true, mean_x, sxx) != ok { ret Invalid }
    if covariance_matrix(y, n, q, true, mean_y, syy) != ok { ret Invalid }
    var a = 0usize
    while a < p {
        var b = 0usize
        while b < q {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += (x[i * p + a] - mean_x[a]) * (y[i * q + b] - mean_y[b])
                i += 1usize
            }
            sxy[a * q + b] = s / f64(n - 1usize)
            b += 1usize
        }
        a += 1usize
    }
    if cholesky_in_place(sxx, p) != ok { ret Singular }
    if cholesky_in_place(syy, q) != ok { ret Singular }
    // K = Lx^-1 Sxy Ly^-T: solve column by column, then row by row.
    var b = 0usize
    while b < q {
        a = 0usize
        while a < p {
            column[a] = sxy[a * q + b]
            a += 1usize
        }
        solve_lower(sxx, p, column[..p])
        a = 0usize
        while a < p {
            kmat[a * q + b] = column[a]
            a += 1usize
        }
        b += 1usize
    }
    a = 0usize
    while a < p {
        var j = 0usize
        while j < q {
            column[j] = kmat[a * q + j]
            j += 1usize
        }
        solve_lower(syy, q, column[..q])
        j = 0usize
        while j < q {
            kmat[a * q + j] = column[j]
            j += 1usize
        }
        a += 1usize
    }
    a = 0usize
    while a < p {
        var c = 0usize
        while c < p {
            var s = 0.0f64
            var j = 0usize
            while j < q {
                s += kmat[a * q + j] * kmat[c * q + j]
                j += 1usize
            }
            gram[a * p + c] = s
            c += 1usize
        }
        a += 1usize
    }
    if reduce.symmetric_eigen(gram, p, values, vectors, 1.0e-26f64, 100u32) != ok { ret Invalid }
    var pair = 0usize
    while pair < k {
        var r2 = values[pair]
        if r2 < 0.0f64 { r2 = 0.0f64 }
        var r = math.sqrt[f64](r2)
        if r > 1.0f64 { r = 1.0f64 }
        correlations[pair] = r
        // x weights: Lx^-T u.
        a = 0usize
        while a < p {
            x_weights[pair * p + a] = vectors[pair * p + a]
            a += 1usize
        }
        solve_lower_transpose(sxx, p, x_weights[pair * p..pair * p + p])
        // y weights: Ly^-T (Kᵀ u / r).
        var j = 0usize
        while j < q {
            var s = 0.0f64
            a = 0usize
            while a < p {
                s += kmat[a * q + j] * vectors[pair * p + a]
                a += 1usize
            }
            if r > 1.0e-300f64 { y_weights[pair * q + j] = s / r } else { y_weights[pair * q + j] = 0.0f64 }
            j += 1usize
        }
        solve_lower_transpose(syy, q, y_weights[pair * q..pair * q + q])
        pair += 1usize
    }
    normalize_signs(x_weights, k, p)
    normalize_signs(y_weights, k, q)
    // Match the y signs to the x signs through the variate correlation's sign.
    pair = 0usize
    while pair < k {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            var vx = 0.0f64
            var a2 = 0usize
            while a2 < p {
                vx += x_weights[pair * p + a2] * (x[i * p + a2] - mean_x[a2])
                a2 += 1usize
            }
            var vy = 0.0f64
            var b2 = 0usize
            while b2 < q {
                vy += y_weights[pair * q + b2] * (y[i * q + b2] - mean_y[b2])
                b2 += 1usize
            }
            s += vx * vy
            i += 1usize
        }
        if s < 0.0f64 {
            var b3 = 0usize
            while b3 < q {
                y_weights[pair * q + b3] = 0.0f64 - y_weights[pair * q + b3]
                b3 += 1usize
            }
        }
        pair += 1usize
    }
    ret ok
}

// Bartlett's chi-squared test that the canonical correlations from index
// `first` on are all zero: statistic, degrees of freedom and p-value.
fn canonical_test(correlations: []const f64, n: usize, p: usize, q: usize, first: usize) -> (f64, f64, f64) {
    var sum = 0.0f64
    var i = first
    while i < correlations.len {
        sum += math.log[f64](1.0f64 - correlations[i] * correlations[i])
        i += 1usize
    }
    let statistic = 0.0f64 - (f64(n) - 1.0f64 - (f64(p) + f64(q) + 1.0f64) / 2.0f64) * sum
    let df = f64(p - first) * f64(q - first)
    if df <= 0.0f64 { ret (statistic, 0.0f64, 1.0f64) }
    ret (statistic, df, special.gamma_q(df / 2.0f64, statistic / 2.0f64))
}

// One-way MANOVA of `n` rows of `p` responses over `groups` labelled groups.
// `eigenvalues` (`p`) receives the eigenvalues of E^-1 H, falling.
// `scratch.len >= 4 p^2 + p + groups p + groups`.
fn manova_oneway(x: []const f64, labels: []const usize, n: usize, p: usize, groups: usize, result: *Manova, eigenvalues: []f64, scratch: []f64) -> err {
    if p == 0usize || groups < 2usize || n <= groups + p { ret Invalid }
    if x.len < n * p || labels.len < n || eigenvalues.len < p || scratch.len < 4usize * p * p + p + groups * p + groups { ret TooSmall }
    var within = scratch[..p * p]
    var between = scratch[p * p..2usize * p * p]
    var vectors = scratch[2usize * p * p..3usize * p * p]
    var work = scratch[3usize * p * p..4usize * p * p]
    var grand = scratch[4usize * p * p..4usize * p * p + p]
    var means = scratch[4usize * p * p + p..4usize * p * p + p + groups * p]
    var counts = scratch[4usize * p * p + p + groups * p..4usize * p * p + p + groups * p + groups]
    var g = 0usize
    while g < groups {
        counts[g] = 0.0f64
        g += 1usize
    }
    var j = 0usize
    while j < p {
        grand[j] = 0.0f64
        j += 1usize
    }
    j = 0usize
    while j < groups * p {
        means[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    while i < n {
        if labels[i] >= groups { ret Invalid }
        counts[labels[i]] += 1.0f64
        j = 0usize
        while j < p {
            means[labels[i] * p + j] += x[i * p + j]
            grand[j] += x[i * p + j]
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < p {
        grand[j] = grand[j] / f64(n)
        j += 1usize
    }
    g = 0usize
    while g < groups {
        if counts[g] < 1.0f64 { ret Invalid }
        j = 0usize
        while j < p {
            means[g * p + j] = means[g * p + j] / counts[g]
            j += 1usize
        }
        g += 1usize
    }
    j = 0usize
    while j < p * p {
        within[j] = 0.0f64
        between[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        var a = 0usize
        while a < p {
            var b = 0usize
            while b < p {
                within[a * p + b] += (x[i * p + a] - means[labels[i] * p + a]) * (x[i * p + b] - means[labels[i] * p + b])
                b += 1usize
            }
            a += 1usize
        }
        i += 1usize
    }
    g = 0usize
    while g < groups {
        var a = 0usize
        while a < p {
            var b = 0usize
            while b < p {
                between[a * p + b] += counts[g] * (means[g * p + a] - grand[a]) * (means[g * p + b] - grand[b])
                b += 1usize
            }
            a += 1usize
        }
        g += 1usize
    }
    // Eigenvalues of E^-1 H as those of L^-1 H L^-T with E = L Lᵀ.
    if cholesky_in_place(within, p) != ok { ret Singular }
    var col = 0usize
    while col < p {
        var r = 0usize
        while r < p {
            work[r] = between[r * p + col]
            r += 1usize
        }
        solve_lower(within, p, work[..p])
        r = 0usize
        while r < p {
            vectors[r * p + col] = work[r]
            r += 1usize
        }
        col += 1usize
    }
    var row = 0usize
    while row < p {
        j = 0usize
        while j < p {
            work[j] = vectors[row * p + j]
            j += 1usize
        }
        solve_lower(within, p, work[..p])
        j = 0usize
        while j < p {
            between[row * p + j] = work[j]
            j += 1usize
        }
        row += 1usize
    }
    // Symmetrise against rounding, then take the eigenvalues.
    var a = 0usize
    while a < p {
        var b = a + 1usize
        while b < p {
            let m = 0.5f64 * (between[a * p + b] + between[b * p + a])
            between[a * p + b] = m
            between[b * p + a] = m
            b += 1usize
        }
        a += 1usize
    }
    if reduce.symmetric_eigen(between, p, eigenvalues, vectors, 1.0e-26f64, 100u32) != ok { ret Invalid }
    i = 0usize
    while i < p {
        if eigenvalues[i] < 0.0f64 { eigenvalues[i] = 0.0f64 }
        i += 1usize
    }
    let pf = f64(p)
    let q = f64(groups - 1usize)
    let v = f64(n - groups)
    var s = pf
    if q < s { s = q }
    let m = (math.abs[f64](pf - q) - 1.0f64) / 2.0f64
    let nn = (v - pf - 1.0f64) / 2.0f64
    var wilks = 1.0f64
    var pillai = 0.0f64
    var trace = 0.0f64
    i = 0usize
    while i < p {
        wilks = wilks / (1.0f64 + eigenvalues[i])
        pillai += eigenvalues[i] / (1.0f64 + eigenvalues[i])
        trace += eigenvalues[i]
        i += 1usize
    }
    // Wilks: Rao's F.
    var t = 1.0f64
    if pf * pf + q * q - 5.0f64 > 0.0f64 { t = math.sqrt[f64]((pf * pf * q * q - 4.0f64) / (pf * pf + q * q - 5.0f64)) }
    let w = v - (pf - q + 1.0f64) / 2.0f64
    var df1 = pf * q
    var df2 = w * t - (pf * q - 2.0f64) / 2.0f64
    var root = math.exp[f64](math.log[f64](wilks) / t)
    var f = (1.0f64 - root) / root * df2 / df1
    result.wilks = ManovaTest { statistic: wilks, f: f, df1: df1, df2: df2, p_value: 1.0f64 - special.f_cdf(f, df1, df2) }
    // Pillai.
    df1 = s * (2.0f64 * m + s + 1.0f64)
    df2 = s * (2.0f64 * nn + s + 1.0f64)
    f = (2.0f64 * nn + s + 1.0f64) / (2.0f64 * m + s + 1.0f64) * pillai / (s - pillai)
    result.pillai = ManovaTest { statistic: pillai, f: f, df1: df1, df2: df2, p_value: 1.0f64 - special.f_cdf(f, df1, df2) }
    // Hotelling-Lawley trace: McKeon's F approximation (SAS's `2 (s n + 1)`
    // denominator degrees of freedom when `n <= 1`).
    df1 = pf * q
    if nn > 1.0f64 {
        let b = (pf + 2.0f64 * nn) * (q + 2.0f64 * nn) / (2.0f64 * (2.0f64 * nn + 1.0f64) * (nn - 1.0f64))
        df2 = 4.0f64 + (pf * q + 2.0f64) / (b - 1.0f64)
        f = df2 / df1 * trace / ((df2 - 2.0f64) / (2.0f64 * nn))
    } else {
        df1 = s * (2.0f64 * m + s + 1.0f64)
        df2 = 2.0f64 * (s * nn + 1.0f64)
        f = df2 / (s * df1) * trace
    }
    result.hotelling = ManovaTest { statistic: trace, f: f, df1: df1, df2: df2, p_value: 1.0f64 - special.f_cdf(f, df1, df2) }
    // Roy's greatest root, the upper-bound F.
    var big = pf
    if q > big { big = q }
    df1 = big
    df2 = v - big + q
    f = eigenvalues[0usize] * df2 / df1
    result.roy = ManovaTest { statistic: eigenvalues[0usize], f: f, df1: df1, df2: df2, p_value: 1.0f64 - special.f_cdf(f, df1, df2) }
    ret ok
}
