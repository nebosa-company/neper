// Longitudinal models over `f64` responses in caller storage: Gaussian GEE
// with working correlations, MMRM with an unstructured covariance by REML,
// and random-intercept LMMs by REML, all with model-based or robust
// covariances for Wald inference (`wald_p`, `mixed_contrast`).
//
// Rows are observed cases grouped by subject: `counts`/`sizes` give the rows
// of each group consecutively, so a missed visit is an absent row and no
// missing-value code exists. Designs are caller-built (`x` is `n × d`
// row-major); MMRM subjects hold at most one row per visit. Pearson scales
// are maximum-likelihood (`Σe² / n`, matching statsmodels), which the
// sandwich and the Fisher steps cancel out of, leaving only the working
// correlations to matter.

use e.math
use e.math.opt
use e.math.special

error TooSmall
error Singular
error Invalid

type Corr = enum u8 { Independence, Exchangeable, Ar1 }
type MmrmCtx = struct { y: []const f64, x: []const f64, n: usize, p: usize, counts: []const usize, groups: usize, visit: []const usize, visits: usize, lbuf: []f64, vbuf: []f64, xvx: []f64, xvy: []f64, ybuf: []f64, xcol: []f64 }
type RiCtx = struct { y: []const f64, x: []const f64, n: usize, d: usize, counts: []const usize, groups: usize, xvx: []f64, xvy: []f64 }

// Solve the dense `n × n` system in place by Gaussian elimination with
// partial pivoting; the answer replaces `rhs`. `Singular` below 1e-12 pivots.
fn mixed_solve(matrix: []f64, rhs: []f64, n: usize) -> err {
    var column = 0usize
    while column < n {
        var pivot = column
        var row = column + 1usize
        while row < n {
            if math.abs[f64](matrix[row * n + column]) > math.abs[f64](matrix[pivot * n + column]) { pivot = row }
            row += 1usize
        }
        if math.abs[f64](matrix[pivot * n + column]) < 1.0e-12f64 { ret Singular }
        if pivot != column {
            var c = 0usize
            while c < n {
                let t = matrix[column * n + c]
                matrix[column * n + c] = matrix[pivot * n + c]
                matrix[pivot * n + c] = t
                c += 1usize
            }
            let t = rhs[column]
            rhs[column] = rhs[pivot]
            rhs[pivot] = t
        }
        row = column + 1usize
        while row < n {
            let factor = matrix[row * n + column] / matrix[column * n + column]
            if factor != 0.0f64 {
                var c = column
                while c < n {
                    matrix[row * n + c] -= factor * matrix[column * n + c]
                    c += 1usize
                }
                rhs[row] -= factor * rhs[column]
            }
            row += 1usize
        }
        column += 1usize
    }
    var i = n
    while i > 0usize {
        i -= 1usize
        var s = rhs[i]
        var c = i + 1usize
        while c < n {
            s -= matrix[i * n + c] * rhs[c]
            c += 1usize
        }
        rhs[i] = s / matrix[i * n + i]
    }
    ret ok
}

// In-place Cholesky: the lower triangle becomes `L` with `A = L L'`.
// `Singular` on a non-positive pivot.
fn mixed_chol(matrix: []f64, n: usize) -> err {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            var s = matrix[i * n + j]
            var k = 0usize
            while k < j {
                s -= matrix[i * n + k] * matrix[j * n + k]
                k += 1usize
            }
            if i == j {
                if s <= 0.0f64 { ret Singular }
                matrix[i * n + i] = math.sqrt[f64](s)
            } else {
                matrix[i * n + j] = s / matrix[j * n + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// Solve with a Cholesky factor from `mixed_chol` (lower triangle read
// only); the answer replaces `rhs`.
fn mixed_chol_solve(l: []const f64, rhs: []f64, n: usize) -> err {
    if l.len < n * n || rhs.len < n { ret TooSmall }
    var i = 0usize
    while i < n {
        var s = rhs[i]
        var j = 0usize
        while j < i {
            s -= l[i * n + j] * rhs[j]
            j += 1usize
        }
        if l[i * n + i] == 0.0f64 { ret Singular }
        rhs[i] = s / l[i * n + i]
        i += 1usize
    }
    var r = n
    while r > 0usize {
        r -= 1usize
        var s = rhs[r]
        var j = r + 1usize
        while j < n {
            s -= l[j * n + r] * rhs[j]
            j += 1usize
        }
        rhs[r] = s / l[r * n + r]
    }
    ret ok
}

// Twice the log of the diagonal product of a Cholesky factor: `log |A|`.
fn mixed_chol_logdet(l: []const f64, n: usize) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < n {
        total += math.log[f64](l[i * n + i])
        i += 1usize
    }
    ret 2.0f64 * total
}

// The two-sided normal p-value of `estimate` with standard error `se`.
fn wald_p(estimate: f64, se: f64) -> (f64, err) {
    if !(se > 0.0f64) { ret (0.0f64, Invalid) }
    let z = math.abs[f64](estimate) / se
    ret (2.0f64 * (1.0f64 - special.normal_cdf(z)), ok)
}

// A linear contrast `weights' beta` with standard error and Wald p-value
// under `covariance` (`p × p`); `Invalid` for a non-positive variance.
fn mixed_contrast(beta: []const f64, covariance: []const f64, p: usize, weights: []const f64) -> (f64, f64, f64, err) {
    if beta.len < p || covariance.len < p * p || weights.len < p { ret (0.0f64, 0.0f64, 0.0f64, TooSmall) }
    var est = 0.0f64
    var i = 0usize
    while i < p {
        est += weights[i] * beta[i]
        i += 1usize
    }
    var v = 0.0f64
    i = 0usize
    while i < p {
        var j = 0usize
        while j < p {
            v += weights[i] * covariance[i * p + j] * weights[j]
            j += 1usize
        }
        i += 1usize
    }
    if v < 0.0f64 { ret (0.0f64, 0.0f64, 0.0f64, Invalid) }
    let se = math.sqrt[f64](v)
    let (p_value, p_error) = wald_p(est, se)
    if p_error != ok { ret (0.0f64, 0.0f64, 0.0f64, p_error) }
    ret (est, se, p_value, ok)
}

// `w = V^-1 v` for one cluster of `m` rows under working correlation
// `corr` with parameter `alpha` and scale `phi`, in closed form (identity,
// exchangeable, tridiagonal AR(1)), so no factorization is needed.
fn gee_solve_block(corr: Corr, alpha: f64, phi: f64, v: []const f64, m: usize, w: []f64) -> err {
    if v.len < m || w.len < m { ret TooSmall }
    if m == 0usize || phi <= 0.0f64 { ret Invalid }
    if corr == .Independence {
        var t = 0usize
        while t < m {
            w[t] = v[t] / phi
            t += 1usize
        }
        ret ok
    }
    if corr == .Exchangeable {
        var total = 0.0f64
        var t = 0usize
        while t < m {
            total += v[t]
            t += 1usize
        }
        let shrink = alpha / (1.0f64 + f64(m - 1usize) * alpha)
        let scale = 1.0f64 / (phi * (1.0f64 - alpha))
        t = 0usize
        while t < m {
            w[t] = (v[t] - shrink * total) * scale
            t += 1usize
        }
        ret ok
    }
    let denom = phi * (1.0f64 - alpha * alpha)
    if m == 1usize {
        w[0usize] = v[0usize] / denom
        ret ok
    }
    w[0usize] = (v[0usize] - alpha * v[1usize]) / denom
    var t = 1usize
    while t + 1usize < m {
        w[t] = ((1.0f64 + alpha * alpha) * v[t] - alpha * (v[t - 1usize] + v[t + 1usize])) / denom
        t += 1usize
    }
    w[m - 1usize] = (v[m - 1usize] - alpha * v[m - 2usize]) / denom
    ret ok
}

// Gaussian GEE over `groups` row blocks of `sizes` rows: Fisher scoring to
// 1e-10 in the largest coefficient step (at most 100 rounds) with the
// working correlation re-estimated by moments every round (Pearson scale,
// exchangeable clamped inside its feasible range, AR(1) inside (-1, 1),
// rows ordered by time within a cluster). Answers the rounds taken, the
// coefficients in `beta`, and the robust sandwich covariance in
// `covariance` (`d × d`). `scratch.len >= 4 * d * d + d + n + 2 * mmax`
// holds the bread, meat, inverse and copy, one step, the residuals, and
// two cluster work vectors (`mmax` the largest `sizes` entry).
// `Invalid` for empty input, a zero-length group, a row-count mismatch, or
// a fit with no residual variation.
fn gee(y: []const f64, x: []const f64, n: usize, d: usize, sizes: []const usize, groups: usize, corr: Corr, beta: []f64, covariance: []f64, scratch: []f64) -> (u32, err) {
    if y.len < n || x.len < n * d || sizes.len < groups || beta.len < d || covariance.len < d * d { ret (0u32, TooSmall) }
    if n == 0usize || d == 0usize || groups == 0usize { ret (0u32, Invalid) }
    var mmax = 0usize
    var total = 0usize
    var g = 0usize
    while g < groups {
        if sizes[g] == 0usize { ret (0u32, Invalid) }
        if sizes[g] > mmax { mmax = sizes[g] }
        total += sizes[g]
        g += 1usize
    }
    if total != n { ret (0u32, Invalid) }
    if scratch.len < 4usize * d * d + d + n + 2usize * mmax { ret (0u32, TooSmall) }
    var bread = scratch[..d * d]
    var meat = scratch[d * d..2usize * d * d]
    var inverse = scratch[2usize * d * d..3usize * d * d]
    var tmp = scratch[3usize * d * d..4usize * d * d]
    var at = 4usize * d * d
    var delta = scratch[at..at + d]
    at += d
    var resid = scratch[at..at + n]
    at += n
    var colbuf = scratch[at..at + mmax]
    at += mmax
    var wvec = scratch[at..at + mmax]
    var b = 0usize
    while b < d {
        beta[b] = 0.0f64
        b += 1usize
    }
    var iteration = 0u32
    var done = false
    while iteration < 100u32 && !done {
        var i = 0usize
        while i < n {
            var s = y[i]
            var j = 0usize
            while j < d {
                s -= x[i * d + j] * beta[j]
                j += 1usize
            }
            resid[i] = s
            i += 1usize
        }
        var phi = 0.0f64
        i = 0usize
        while i < n {
            phi += resid[i] * resid[i]
            i += 1usize
        }
        phi = phi / f64(n)
        if phi <= 0.0f64 { ret (iteration, Invalid) }
        let sd = math.sqrt[f64](phi)
        var alpha = 0.0f64
        if corr == .Exchangeable {
            var num = 0.0f64
            var pairs = 0usize
            var off = 0usize
            g = 0usize
            while g < groups {
                let m = sizes[g]
                var a = 0usize
                while a < m {
                    var h = a + 1usize
                    while h < m {
                        num += resid[off + a] / sd * (resid[off + h] / sd)
                        pairs += 1usize
                        h += 1usize
                    }
                    a += 1usize
                }
                off += m
                g += 1usize
            }
            if pairs > 0usize {
                alpha = num / f64(pairs)
                var lo = 0.0f64
                if mmax > 1usize { lo = 0.0f64 - 1.0f64 / f64(mmax - 1usize) + 0.000001f64 }
                if alpha < lo { alpha = lo }
                if alpha > 0.999999f64 { alpha = 0.999999f64 }
            }
        }
        if corr == .Ar1 {
            var num = 0.0f64
            var pairs = 0usize
            var off = 0usize
            g = 0usize
            while g < groups {
                let m = sizes[g]
                var a = 0usize
                while a + 1usize < m {
                    num += resid[off + a] / sd * (resid[off + a + 1usize] / sd)
                    pairs += 1usize
                    a += 1usize
                }
                off += m
                g += 1usize
            }
            if pairs > 0usize {
                alpha = num / f64(pairs)
                if alpha < 0.0f64 - 0.999999f64 { alpha = 0.0f64 - 0.999999f64 }
                if alpha > 0.999999f64 { alpha = 0.999999f64 }
            }
        }
        var e = 0usize
        while e < d * d {
            bread[e] = 0.0f64
            e += 1usize
        }
        e = 0usize
        while e < d {
            delta[e] = 0.0f64
            e += 1usize
        }
        var off = 0usize
        g = 0usize
        while g < groups {
            let m = sizes[g]
            var col = 0usize
            while col < d {
                var t = 0usize
                while t < m {
                    colbuf[t] = x[(off + t) * d + col]
                    t += 1usize
                }
                let block_error = gee_solve_block(corr, alpha, phi, colbuf[..m], m, wvec[..m])
                if block_error != ok { ret (iteration, block_error) }
                var row = 0usize
                while row < d {
                    var s = 0.0f64
                    t = 0usize
                    while t < m {
                        s += x[(off + t) * d + row] * wvec[t]
                        t += 1usize
                    }
                    bread[row * d + col] += s
                    row += 1usize
                }
                col += 1usize
            }
            let resid_error = gee_solve_block(corr, alpha, phi, resid[off..off + m], m, wvec[..m])
            if resid_error != ok { ret (iteration, resid_error) }
            var row = 0usize
            while row < d {
                var s = 0.0f64
                var t = 0usize
                while t < m {
                    s += x[(off + t) * d + row] * wvec[t]
                    t += 1usize
                }
                delta[row] += s
                row += 1usize
            }
            off += m
            g += 1usize
        }
        let step_error = mixed_solve(bread, delta, d)
        if step_error != ok { ret (iteration, step_error) }
        var largest = 0.0f64
        b = 0usize
        while b < d {
            beta[b] += delta[b]
            largest = math.max[f64](largest, math.abs[f64](delta[b]))
            b += 1usize
        }
        iteration += 1u32
        if largest < 0.0000000001f64 { done = true }
    }
    // The sandwich at the final working correlation.
    var i = 0usize
    while i < n {
        var s = y[i]
        var j = 0usize
        while j < d {
            s -= x[i * d + j] * beta[j]
            j += 1usize
        }
        resid[i] = s
        i += 1usize
    }
    var phi = 0.0f64
    i = 0usize
    while i < n {
        phi += resid[i] * resid[i]
        i += 1usize
    }
    phi = phi / f64(n)
    let sd = math.sqrt[f64](phi)
    var alpha = 0.0f64
    if corr == .Exchangeable {
        var num = 0.0f64
        var pairs = 0usize
        var off = 0usize
        g = 0usize
        while g < groups {
            let m = sizes[g]
            var a = 0usize
            while a < m {
                var h = a + 1usize
                while h < m {
                    num += resid[off + a] / sd * (resid[off + h] / sd)
                    pairs += 1usize
                    h += 1usize
                }
                a += 1usize
            }
            off += m
            g += 1usize
        }
        if pairs > 0usize {
            alpha = num / f64(pairs)
            var lo = 0.0f64
            if mmax > 1usize { lo = 0.0f64 - 1.0f64 / f64(mmax - 1usize) + 0.000001f64 }
            if alpha < lo { alpha = lo }
            if alpha > 0.999999f64 { alpha = 0.999999f64 }
        }
    }
    if corr == .Ar1 {
        var num = 0.0f64
        var pairs = 0usize
        var off = 0usize
        g = 0usize
        while g < groups {
            let m = sizes[g]
            var a = 0usize
            while a + 1usize < m {
                num += resid[off + a] / sd * (resid[off + a + 1usize] / sd)
                pairs += 1usize
                a += 1usize
            }
            off += m
            g += 1usize
        }
        if pairs > 0usize {
            alpha = num / f64(pairs)
            if alpha < 0.0f64 - 0.999999f64 { alpha = 0.0f64 - 0.999999f64 }
            if alpha > 0.999999f64 { alpha = 0.999999f64 }
        }
    }
    var e = 0usize
    while e < d * d {
        bread[e] = 0.0f64
        meat[e] = 0.0f64
        e += 1usize
    }
    var off = 0usize
    g = 0usize
    while g < groups {
        let m = sizes[g]
        var col = 0usize
        while col < d {
            var t = 0usize
            while t < m {
                colbuf[t] = x[(off + t) * d + col]
                t += 1usize
            }
            let block_error = gee_solve_block(corr, alpha, phi, colbuf[..m], m, wvec[..m])
            if block_error != ok { ret (iteration, block_error) }
            var row = 0usize
            while row < d {
                var s = 0.0f64
                var u = 0usize
                while u < m {
                    s += x[(off + u) * d + row] * wvec[u]
                    u += 1usize
                }
                bread[row * d + col] += s
                row += 1usize
            }
            col += 1usize
        }
        let resid_error = gee_solve_block(corr, alpha, phi, resid[off..off + m], m, wvec[..m])
        if resid_error != ok { ret (iteration, resid_error) }
        var row = 0usize
        while row < d {
            var s = 0.0f64
            var t = 0usize
            while t < m {
                s += x[(off + t) * d + row] * wvec[t]
                t += 1usize
            }
            delta[row] = s
            row += 1usize
        }
        row = 0usize
        while row < d {
            var c = 0usize
            while c < d {
                meat[row * d + c] += delta[row] * delta[c]
                c += 1usize
            }
            row += 1usize
        }
        off += m
        g += 1usize
    }
    // The inverse column by column, then the triple product.
    var c = 0usize
    while c < d {
        e = 0usize
        while e < d * d {
            tmp[e] = bread[e]
            e += 1usize
        }
        var r = 0usize
        while r < d {
            if r == c {
                delta[r] = 1.0f64
            } else {
                delta[r] = 0.0f64
            }
            r += 1usize
        }
        let inverse_error = mixed_solve(tmp, delta, d)
        if inverse_error != ok { ret (iteration, inverse_error) }
        r = 0usize
        while r < d {
            inverse[r * d + c] = delta[r]
            r += 1usize
        }
        c += 1usize
    }
    var a = 0usize
    while a < d {
        var h = 0usize
        while h < d {
            var s = 0.0f64
            var j = 0usize
            while j < d {
                var t = 0.0f64
                var k = 0usize
                while k < d {
                    t += inverse[a * d + k] * meat[k * d + j]
                    k += 1usize
                }
                s += t * inverse[h * d + j]
                j += 1usize
            }
            covariance[a * d + h] = s
            h += 1usize
        }
        a += 1usize
    }
    ret (iteration, ok)
}

// Unpack log-Cholesky parameters into `L` (lower, positive diagonal), row by
// row: diagonal entries exponentiated, subdiagonal entries as they are.
fn mmrm_unpack(theta: []const f64, v: usize, l: []f64) {
    var k = 0usize
    var i = 0usize
    while i < v {
        var j = 0usize
        while j < v {
            if j > i {
                l[i * v + j] = 0.0f64
            } else if i == j {
                l[i * v + j] = math.exp[f64](theta[k])
                k += 1usize
            } else {
                l[i * v + j] = theta[k]
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
}

// The GLS accumulation under `covariance` (`visits × visits`) over the
// observed rows: `xvx` receives `X'V^-1 X`, `xvy` receives `X'V^-1 y` and
// then the coefficients, solved in place. Answers the REML kernel
// `log |V| + log |X'V^-1 X| + r'V^-1 r`. Rank failure surfaces as `Singular`.
fn mmrm_fit_given(ctx: *MmrmCtx, l: []const f64) -> (f64, err) {
    let p = ctx.p
    let v = ctx.visits
    var e = 0usize
    while e < p * p {
        ctx.xvx[e] = 0.0f64
        e += 1usize
    }
    e = 0usize
    while e < p {
        ctx.xvy[e] = 0.0f64
        e += 1usize
    }
    var logdet = 0.0f64
    var off = 0usize
    var g = 0usize
    while g < ctx.groups {
        let m = ctx.counts[g]
        var a = 0usize
        while a < m {
            var h = 0usize
            while h < m {
                var s = 0.0f64
                var t = 0usize
                while t < v {
                    s += l[ctx.visit[off + a] * v + t] * l[ctx.visit[off + h] * v + t]
                    t += 1usize
                }
                ctx.vbuf[a * m + h] = s
                h += 1usize
            }
            a += 1usize
        }
        let chol_error = mixed_chol(ctx.vbuf, m)
        if chol_error != ok { ret (0.0f64, chol_error) }
        logdet += mixed_chol_logdet(ctx.vbuf, m)
        var t = 0usize
        while t < m {
            ctx.ybuf[t] = ctx.y[off + t]
            t += 1usize
        }
        let y_error = mixed_chol_solve(ctx.vbuf, ctx.ybuf, m)
        if y_error != ok { ret (0.0f64, y_error) }
        var j = 0usize
        while j < p {
            t = 0usize
            while t < m {
                ctx.xcol[t] = ctx.x[(off + t) * p + j]
                t += 1usize
            }
            let col_error = mixed_chol_solve(ctx.vbuf, ctx.xcol, m)
            if col_error != ok { ret (0.0f64, col_error) }
            var r = 0usize
            while r < p {
                var s = 0.0f64
                t = 0usize
                while t < m {
                    s += ctx.x[(off + t) * p + r] * ctx.xcol[t]
                    t += 1usize
                }
                ctx.xvx[r * p + j] += s
                r += 1usize
            }
            var s = 0.0f64
            t = 0usize
            while t < m {
                s += ctx.x[(off + t) * p + j] * ctx.ybuf[t]
                t += 1usize
            }
            ctx.xvy[j] += s
            j += 1usize
        }
        off += m
        g += 1usize
    }
    let solve_error = mixed_chol(ctx.xvx, p)
    if solve_error != ok { ret (0.0f64, solve_error) }
    let beta_error = mixed_chol_solve(ctx.xvx, ctx.xvy, p)
    if beta_error != ok { ret (0.0f64, beta_error) }
    let logdet_a = mixed_chol_logdet(ctx.xvx, p)
    // The residual quadratic form under the fitted coefficients.
    var rwr = 0.0f64
    off = 0usize
    g = 0usize
    while g < ctx.groups {
        let m = ctx.counts[g]
        var a = 0usize
        while a < m {
            var h = 0usize
            while h < m {
                var s = 0.0f64
                var t = 0usize
                while t < v {
                    s += l[ctx.visit[off + a] * v + t] * l[ctx.visit[off + h] * v + t]
                    t += 1usize
                }
                ctx.vbuf[a * m + h] = s
                h += 1usize
            }
            a += 1usize
        }
        let rchol_error = mixed_chol(ctx.vbuf, m)
        if rchol_error != ok { ret (0.0f64, rchol_error) }
        var t = 0usize
        while t < m {
            var s = ctx.y[off + t]
            var j = 0usize
            while j < p {
                s -= ctx.x[(off + t) * p + j] * ctx.xvy[j]
                j += 1usize
            }
            ctx.ybuf[t] = s
            t += 1usize
        }
        let r_error = mixed_chol_solve(ctx.vbuf, ctx.ybuf, m)
        if r_error != ok { ret (0.0f64, r_error) }
        t = 0usize
        while t < m {
            var s = ctx.y[off + t]
            var j = 0usize
            while j < p {
                s -= ctx.x[(off + t) * p + j] * ctx.xvy[j]
                j += 1usize
            }
            rwr += s * ctx.ybuf[t]
            t += 1usize
        }
        off += m
        g += 1usize
    }
    ret (logdet + logdet_a + rwr, ok)
}

// The negative REML log-likelihood at log-Cholesky `theta`: unpack, GLS,
// and the residual form, `1e300` where the design is rank-deficient.
fn mmrm_objective(ctx: *MmrmCtx, theta: []const f64) -> f64 {
    let v = ctx.visits
    mmrm_unpack(theta, v, ctx.lbuf)
    let (kernel, fit_error) = mmrm_fit_given(ctx, ctx.lbuf)
    if fit_error != ok { ret 1.0e300f64 }
    ret 0.5f64 * (f64(ctx.n - ctx.p) * 1.8378770654093453f64 + kernel)
}

// MMRM with an unstructured `visits × visits` covariance by REML: the
// covariance in log-Cholesky parameters from zero (identity) by Nelder-Mead
// (simplex 0.5, value spread 1e-10, at most 5000 rounds), the coefficients
// by GLS at the optimum. Rows are observed cases grouped by subject
// (`counts`), each with its `visit` id; a missed visit is an absent row,
// and at most one row per visit per subject holds. Answers the Nelder-Mead
// rounds taken, `beta`, its model-based covariance `beta_cov`, and the
// covariance. `scratch.len >= (m + 1) * (m + 1) + 5 * m + 2 * v * v + p *
// p + p + 2 * v` with `m = v * (v + 1) / 2` holds the simplex, the
// parameters, the factor, the working blocks, the GLS system, and one
// subject of temporaries.
fn mmrm_un(y: []const f64, x: []const f64, n: usize, p: usize, counts: []const usize, groups: usize, visit: []const usize, visits: usize, beta: []f64, beta_cov: []f64, covariance: []f64, scratch: []f64) -> (u32, err) {
    if y.len < n || x.len < n * p || counts.len < groups || visit.len < n || beta.len < p || beta_cov.len < p * p || covariance.len < visits * visits { ret (0u32, TooSmall) }
    if n == 0usize || p == 0usize || groups == 0usize || visits == 0usize { ret (0u32, Invalid) }
    let m = visits * (visits + 1usize) / 2usize
    let v = visits
    if scratch.len < (m + 1usize) * (m + 1usize) + 5usize * m + 2usize * v * v + p * p + p + 2usize * v { ret (0u32, TooSmall) }
    var total = 0usize
    var g = 0usize
    while g < groups {
        if counts[g] == 0usize { ret (0u32, Invalid) }
        total += counts[g]
        g += 1usize
    }
    if total != n { ret (0u32, Invalid) }
    if n < p { ret (0u32, Invalid) }
    var off = 0usize
    g = 0usize
    while g < groups {
        let rows = counts[g]
        var a = 0usize
        while a < rows {
            if visit[off + a] >= visits { ret (0u32, Invalid) }
            var h = a + 1usize
            while h < rows {
                if visit[off + a] == visit[off + h] { ret (0u32, Invalid) }
                h += 1usize
            }
            a += 1usize
        }
        off += rows
        g += 1usize
    }
    var at = (m + 1usize) * (m + 1usize) + 4usize * m
    var theta = scratch[at..at + m]
    at += m
    var lbuf = scratch[at..at + v * v]
    at += v * v
    var vbuf = scratch[at..at + v * v]
    at += v * v
    var xvx = scratch[at..at + p * p]
    at += p * p
    var xvy = scratch[at..at + p]
    at += p
    var ybuf = scratch[at..at + v]
    at += v
    var xcol = scratch[at..at + v]
    var ctx = MmrmCtx { y: y, x: x, n: n, p: p, counts: counts, groups: groups, visit: visit, visits: visits, lbuf: lbuf, vbuf: vbuf, xvx: xvx, xvy: xvy, ybuf: ybuf, xcol: xcol }
    var t = 0usize
    while t < m {
        theta[t] = 0.0f64
        t += 1usize
    }
    let (result, nm_error) = opt.nelder_mead[MmrmCtx](&ctx, mmrm_objective, theta, 0.5f64, 0.0000000001f64, 5000u32, scratch[..(m + 1usize) * (m + 1usize) + 4usize * m])
    if nm_error != ok { ret (0u32, nm_error) }
    mmrm_unpack(theta, v, lbuf)
    var i = 0usize
    while i < v {
        var j = 0usize
        while j < v {
            var s = 0.0f64
            var k = 0usize
            while k < v {
                s += lbuf[i * v + k] * lbuf[j * v + k]
                k += 1usize
            }
            covariance[i * v + j] = s
            j += 1usize
        }
        i += 1usize
    }
    let (_, fit_error) = mmrm_fit_given(&ctx, lbuf)
    if fit_error != ok { ret (0u32, fit_error) }
    i = 0usize
    while i < p {
        beta[i] = xvy[i]
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var r = 0usize
        while r < p {
            if r == j {
                xvy[r] = 1.0f64
            } else {
                xvy[r] = 0.0f64
            }
            r += 1usize
        }
        let inverse_error = mixed_chol_solve(xvx, xvy, p)
        if inverse_error != ok { ret (0u32, inverse_error) }
        r = 0usize
        while r < p {
            beta_cov[r * p + j] = xvy[r]
            r += 1usize
        }
        j += 1usize
    }
    ret (result.iterations, ok)
}

// The GLS accumulation for a random intercept with variances `tau2`
// (between) and `sig2` (within) in closed form: `xvx` receives `X'V^-1 X`,
// `xvy` the coefficients solved in place. Answers `log |V|`. Rank failure
// surfaces as `Singular`.
fn ri_fit_given(ctx: *RiCtx, tau2: f64, sig2: f64) -> (f64, err) {
    let d = ctx.d
    var e = 0usize
    while e < d * d {
        ctx.xvx[e] = 0.0f64
        e += 1usize
    }
    e = 0usize
    while e < d {
        ctx.xvy[e] = 0.0f64
        e += 1usize
    }
    var logdet = 0.0f64
    var off = 0usize
    var g = 0usize
    while g < ctx.groups {
        let m = ctx.counts[g]
        let shrink = tau2 / (sig2 + f64(m) * tau2)
        let scale = 1.0f64 / sig2
        logdet += f64(m - 1usize) * math.log[f64](sig2) + math.log[f64](sig2 + f64(m) * tau2)
        var a = 0usize
        while a < d {
            var h = 0usize
            while h < d {
                var one = 0.0f64
                var sa = 0.0f64
                var sb = 0.0f64
                var t = 0usize
                while t < m {
                    let xa = ctx.x[(off + t) * d + a]
                    let xb = ctx.x[(off + t) * d + h]
                    one += xa * xb
                    sa += xa
                    sb += xb
                    t += 1usize
                }
                ctx.xvx[a * d + h] += (one - shrink * sa * sb) * scale
                h += 1usize
            }
            a += 1usize
        }
        var sy = 0.0f64
        var t = 0usize
        while t < m {
            sy += ctx.y[off + t]
            t += 1usize
        }
        a = 0usize
        while a < d {
            var s1 = 0.0f64
            var sa = 0.0f64
            t = 0usize
            while t < m {
                let xa = ctx.x[(off + t) * d + a]
                s1 += xa * ctx.y[off + t]
                sa += xa
                t += 1usize
            }
            ctx.xvy[a] += (s1 - shrink * sa * sy) * scale
            a += 1usize
        }
        off += m
        g += 1usize
    }
    let chol_error = mixed_chol(ctx.xvx, d)
    if chol_error != ok { ret (0.0f64, chol_error) }
    let beta_error = mixed_chol_solve(ctx.xvx, ctx.xvy, d)
    if beta_error != ok { ret (0.0f64, beta_error) }
    ret (logdet + mixed_chol_logdet(ctx.xvx, d), ok)
}

// The negative REML log-likelihood at log variances `theta` (between,
// within): GLS and the residual form, `1e300` where the design is
// rank-deficient.
fn ri_objective(ctx: *RiCtx, theta: []const f64) -> f64 {
    let tau2 = math.exp[f64](theta[0usize])
    let sig2 = math.exp[f64](theta[1usize])
    let (kernel, fit_error) = ri_fit_given(ctx, tau2, sig2)
    if fit_error != ok { ret 1.0e300f64 }
    var rwr = 0.0f64
    var off = 0usize
    var g = 0usize
    while g < ctx.groups {
        let m = ctx.counts[g]
        let shrink = tau2 / (sig2 + f64(m) * tau2)
        let scale = 1.0f64 / sig2
        var one = 0.0f64
        var s = 0.0f64
        var t = 0usize
        while t < m {
            var r = ctx.y[off + t]
            var j = 0usize
            while j < ctx.d {
                r -= ctx.x[(off + t) * ctx.d + j] * ctx.xvy[j]
                j += 1usize
            }
            one += r * r
            s += r
            t += 1usize
        }
        rwr += (one - shrink * s * s) * scale
        off += m
        g += 1usize
    }
    ret 0.5f64 * (f64(ctx.n - ctx.d) * 1.8378770654093453f64 + kernel + rwr)
}

// A random-intercept LMM by REML: the log variances from half the sample
// variance by Nelder-Mead (simplex 0.5, value spread 1e-12, at most 500
// rounds), the coefficients by GLS at the optimum. Rows are observed cases
// grouped by subject (`counts`); a missed visit is an absent row. Answers
// the Nelder-Mead rounds taken, `beta`, its model-based covariance
// `beta_cov`, the variances (`tau2` between, `sig2` within), and the BLUPs.
// `scratch.len >= 19 + 2 * d * d + d` holds the simplex, the parameters,
// the GLS system, its inverse, and one right-hand side.
fn lmm_intercept(y: []const f64, x: []const f64, n: usize, d: usize, counts: []const usize, groups: usize, beta: []f64, beta_cov: []f64, variances: []f64, blups: []f64, scratch: []f64) -> (u32, err) {
    if y.len < n || x.len < n * d || counts.len < groups || beta.len < d || beta_cov.len < d * d || variances.len < 2usize || blups.len < groups || scratch.len < 19usize + 2usize * d * d + d { ret (0u32, TooSmall) }
    if n == 0usize || d == 0usize || groups == 0usize { ret (0u32, Invalid) }
    var total = 0usize
    var g = 0usize
    while g < groups {
        if counts[g] == 0usize { ret (0u32, Invalid) }
        total += counts[g]
        g += 1usize
    }
    if total != n { ret (0u32, Invalid) }
    if n < 2usize || n < d { ret (0u32, Invalid) }
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += y[i] / f64(n)
        i += 1usize
    }
    var spread = 0.0f64
    i = 0usize
    while i < n {
        let t = y[i] - mean
        spread += t * t
        i += 1usize
    }
    let variance = spread / f64(n - 1usize)
    if variance <= 0.0f64 { ret (0u32, Invalid) }
    var nm = scratch[..17usize]
    var at = 17usize
    var theta = scratch[at..at + 2usize]
    at += 2usize
    var xvx = scratch[at..at + d * d]
    at += d * d
    var xvy = scratch[at..at + d]
    at += d
    var inverse = scratch[at..at + d * d]
    var ctx = RiCtx { y: y, x: x, n: n, d: d, counts: counts, groups: groups, xvx: xvx, xvy: xvy }
    let start = math.log[f64](variance / 2.0f64)
    theta[0usize] = start
    theta[1usize] = start
    let (result, nm_error) = opt.nelder_mead[RiCtx](&ctx, ri_objective, theta, 0.5f64, 0.000000000001f64, 500u32, nm)
    if nm_error != ok { ret (0u32, nm_error) }
    let tau2 = math.exp[f64](theta[0usize])
    let sig2 = math.exp[f64](theta[1usize])
    variances[0usize] = tau2
    variances[1usize] = sig2
    let (_, fit_error) = ri_fit_given(&ctx, tau2, sig2)
    if fit_error != ok { ret (0u32, fit_error) }
    i = 0usize
    while i < d {
        beta[i] = xvy[i]
        i += 1usize
    }
    var j = 0usize
    while j < d {
        var r = 0usize
        while r < d {
            if r == j {
                xvy[r] = 1.0f64
            } else {
                xvy[r] = 0.0f64
            }
            r += 1usize
        }
        let inverse_error = mixed_chol_solve(xvx, xvy, d)
        if inverse_error != ok { ret (0u32, inverse_error) }
        r = 0usize
        while r < d {
            inverse[r * d + j] = xvy[r]
            r += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < d * d {
        beta_cov[i] = inverse[i]
        i += 1usize
    }
    var off = 0usize
    g = 0usize
    while g < groups {
        let m = counts[g]
        let weight = tau2 / (sig2 + f64(m) * tau2)
        var s = 0.0f64
        var t = 0usize
        while t < m {
            var r = y[off + t]
            var c = 0usize
            while c < d {
                r -= x[(off + t) * d + c] * beta[c]
                c += 1usize
            }
            s += r
            t += 1usize
        }
        blups[g] = weight * s
        off += m
        g += 1usize
    }
    ret (result.iterations, ok)
}
