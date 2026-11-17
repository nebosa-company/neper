// R glmnet, the gaussian family: the elastic-net objective
// `(1 / 2n) sum (y - b0 - x b)^2 + lambda sum vf_j ((1 - alpha) / 2 b_j^2 + alpha |b_j|)` by cyclic coordinate
// descent run to a tight tolerance, with glmnet's conventions (y is scaled to unit variance inside, which makes the
// ridge part of the penalty `lambda (1 - alpha) / sd(y)`): columns standardised to unit variance (divisor n)
// inside when `standardize`, the penalty factors rescaled to sum to p, coefficients answered on the original scale
// and the intercept from the means. Answers the exact minimiser, which glmnet reaches to its `thresh` of 1e-7.
//
// Box constraints lower.limits / upper.limits (original-scale coefficients, empty for none) clamp each coordinate update, which is exact for a one-variable convex problem. Observation weights (normalised to sum 1, as glmnet does) enter the means, the standardisation and the loss; an empty slice means equal weights.
//
// Also here, each as the minimiser run to a tight tolerance (glmnet stops at its thresh of 1e-7, so its own coefficients sit a few 1e-4 from these): the binomial and poisson families (weights, offsets, bounds), the multinomial family (ungrouped and grouped; weights, offsets, bounds),
// the Cox family (Breslow and Efron ties, strata, start-stop responses, weights, offsets, bounds), mgaussian (weights, bounds), the automatic lambda sequence and its length for every family, `exclude`, relax = TRUE for every family, cv.glmnet for every family (weights, offsets, relax,
// the lambda sequence given or the default one where each fold finds its own and is read at the full fit's lambdas by interpolation), and the predict types.
//
// Not reproduced: the relaxed multinomial fit on data where glmnet's own unpenalised answer has not settled on the lasso limit (it is flat along one added vector per variable), the length of glmnet's grouped multinomial path with weights (its own algorithm stalls at the smallest lambdas),
// the paths' length to better than one lambda at glmnet's default thresh, and the C-index and misclassification measures at the near-null first lambdas of a default-lambda cross-validation.

use e.algo.rand.r as rng
use e.math
use e.mem

fn soft(z: f64, g: f64) -> f64 {
    if z > g { ret z - g }
    if z < 0.0f64 - g { ret z + g }
    ret 0.0f64
}

// x is n by p column-major; lambdas are visited in order with warm starts; coef receives, for lambda k, the
// intercept at k * (p + 1) and the p slopes after it
fn gaussian(a: *mem.Arena, x: []const f64, y: []const f64, wt: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (sc, e2) = mem.alloc[f64](a, p)
    let (mx, e3) = mem.alloc[f64](a, p)
    let (pf, e4) = mem.alloc[f64](a, p)
    let (b, e5) = mem.alloc[f64](a, p)
    let (r, e6) = mem.alloc[f64](a, n)
    let (wn, e7) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e1 }
    var wsum = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { wn[i] = wt[i] } else { wn[i] = 1.0f64 }
        wsum += wn[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        wn[i] = wn[i] / wsum
        i += 1usize
    }
    var ybar = 0.0f64
    i = 0usize
    while i < n {
        ybar += wn[i] * y[i]
        i += 1usize
    }
    var yv = 0.0f64
    i = 0usize
    while i < n {
        yv += wn[i] * (y[i] - ybar) * (y[i] - ybar)
        i += 1usize
    }
    let ys = math.sqrt[f64](yv)
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += wn[i] * x[j * n + i]
            i += 1usize
        }
        var v = 0.0f64
        i = 0usize
        while i < n {
            v += wn[i] * (x[j * n + i] - m) * (x[j * n + i] - m)
            i += 1usize
        }
        var s = 1.0f64
        if standardize { s = math.sqrt[f64](v) }
        sc[j] = s
        mx[j] = m
        i = 0usize
        while i < n {
            xs[j * n + i] = (x[j * n + i] - m) / s
            i += 1usize
        }
        pf[j] = vf[j] * f64(p) / vs
        b[j] = 0.0f64
        j += 1usize
    }
    var k = 0usize
    while k < lambdas.len {
        let lam = lambdas[k]
        i = 0usize
        while i < n {
            var f = 0.0f64
            j = 0usize
            while j < p {
                f += xs[j * n + i] * b[j]
                j += 1usize
            }
            r[i] = y[i] - ybar - f
            i += 1usize
        }
        var sweep = 0usize
        while sweep < 100000usize {
            var dmax = 0.0f64
            j = 0usize
            while j < p {
                var cj = 0.0f64
                var xr = 0.0f64
                i = 0usize
                while i < n {
                    cj += wn[i] * xs[j * n + i] * xs[j * n + i]
                    xr += wn[i] * xs[j * n + i] * r[i]
                    i += 1usize
                }
                let z = xr + cj * b[j]
                let nb = soft(z, lam * alpha * pf[j]) / (cj + lam * (1.0f64 - alpha) * pf[j] / ys)
                var nb2 = nb
                if lo.len == p && nb2 < lo[j] * sc[j] { nb2 = lo[j] * sc[j] }
                if up.len == p && nb2 > up[j] * sc[j] { nb2 = up[j] * sc[j] }
                let d = nb2 - b[j]
                if d != 0.0f64 {
                    i = 0usize
                    while i < n {
                        r[i] -= d * xs[j * n + i]
                        i += 1usize
                    }
                    b[j] = nb2
                    if math.abs[f64](d) * math.sqrt[f64](cj) > dmax { dmax = math.abs[f64](d) * math.sqrt[f64](cj) }
                }
                j += 1usize
            }
            if dmax < 1.0e-14f64 { break }
            sweep += 1usize
        }
        var b0 = ybar
        j = 0usize
        while j < p {
            coef[k * (p + 1usize) + 1usize + j] = b[j] / sc[j]
            b0 -= b[j] / sc[j] * mx[j]
            j += 1usize
        }
        coef[k * (p + 1usize)] = b0
        k += 1usize
    }
    ret ok
}

// glmnet's automatic lambda sequence (gaussian): lambda_max = max over j of |x_j' (y - ybar)| / (n max(alpha, 0.001) vf_j) with the columns centred and (when standardize) scaled to unit variance (divisor n)
// and the penalty factors rescaled to sum to p, then nlambda values equally spaced on the log scale down to lambda_max times 1e-4 (1e-2 when n < p); returns the sequence in out
fn lambda_path(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize, out: []f64) -> err {
    let nf = f64(n)
    var ybar = 0.0f64
    var i = 0usize
    while i < n {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / nf
    var vsum = 0.0f64
    var j = 0usize
    while j < p {
        vsum += vf[j]
        j += 1usize
    }
    var lmax = 0.0f64
    j = 0usize
    while j < p {
        var mj = 0.0f64
        i = 0usize
        while i < n {
            mj += x[j * n + i]
            i += 1usize
        }
        mj = mj / nf
        var ss = 0.0f64
        var sxy = 0.0f64
        i = 0usize
        while i < n {
            ss += (x[j * n + i] - mj) * (x[j * n + i] - mj)
            sxy += (x[j * n + i] - mj) * (y[i] - ybar)
            i += 1usize
        }
        var g = sxy / nf
        if standardize { g = g / math.sqrt[f64](ss / nf) }
        let vj = vf[j] * f64(p) / vsum
        if vj > 0.0f64 {
            var al = alpha
            if al < 0.001f64 { al = 0.001f64 }
            let v = math.abs[f64](g) / (al * vj)
            if v > lmax { lmax = v }
        }
        j += 1usize
    }
    var ratio = 1.0e-4f64
    if n < p { ratio = 1.0e-2f64 }
    var k = 0usize
    while k < nlambda {
        out[k] = lmax * math.pow[f64](ratio, f64(k) / f64(nlambda - 1usize))
        k += 1usize
    }
    ret ok
}

// wt (observation weights, normalised to sum 1) and off (offset added to the linear predictor) may be empty; the binomial (fam 0, y in {0, 1}) and poisson (fam 1) families: the elastic-net penalised negative log-likelihood divided by n, minimised by proximal Newton (an outer reweighted least-squares step, an inner cyclic coordinate descent on the working
// response, the intercept unpenalised), to a tight tolerance; columns standardised with divisor n, penalty factors rescaled to sum to p, coefficients answered on the original scale; layout as in `gaussian`
fn glm_path(a: *mem.Arena, fam: usize, x: []const f64, y: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64) -> err {
    let nodev: []f64 = zero
    ret glm_path_dev(a, fam, x, y, wt, off, nodev, nodev, n, p, alpha, standardize, vf, lambdas, coef, nodev)
}

// as `glm_path`, with box constraints lo and up on the original-scale coefficients (empty for none), and dev (when long enough) receives the fitted deviance at each lambda (weights normalised to sum 1)
fn glm_path_dev(a: *mem.Arena, fam: usize, x: []const f64, y: []const f64, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64, dev: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (sc, e2) = mem.alloc[f64](a, p)
    let (mx, e3) = mem.alloc[f64](a, p)
    let (pf, e4) = mem.alloc[f64](a, p)
    let (b, e5) = mem.alloc[f64](a, p)
    let (r, e6) = mem.alloc[f64](a, n)
    let (w, e7) = mem.alloc[f64](a, n)
    let (z, e8) = mem.alloc[f64](a, n)
    let (wn, e9) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret e1 }
    var wsum0 = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { wn[i] = wt[i] } else { wn[i] = 1.0f64 }
        wsum0 += wn[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        wn[i] = wn[i] / wsum0
        i += 1usize
    }
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    i = 0usize
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += wn[i] * x[j * n + i]
            i += 1usize
        }
        var v = 0.0f64
        i = 0usize
        while i < n {
            v += wn[i] * (x[j * n + i] - m) * (x[j * n + i] - m)
            i += 1usize
        }
        var s = 1.0f64
        if standardize { s = math.sqrt[f64](v) }
        sc[j] = s
        mx[j] = m
        i = 0usize
        while i < n {
            xs[j * n + i] = (x[j * n + i] - m) / s
            i += 1usize
        }
        pf[j] = vf[j] * f64(p) / vs
        b[j] = 0.0f64
        j += 1usize
    }
    var ybar = 0.0f64
    i = 0usize
    while i < n {
        ybar += wn[i] * y[i]
        i += 1usize
    }
    var b0 = math.log[f64](ybar / (1.0f64 - ybar))
    if fam == 1usize { b0 = math.log[f64](ybar) }
    var k = 0usize
    while k < lambdas.len {
        let lam = lambdas[k]
        var outer = 0usize
        while outer < 200usize {
            var wsum = 0.0f64
            i = 0usize
            while i < n {
                var eta = b0
                if off.len == n { eta += off[i] }
                j = 0usize
                while j < p {
                    eta += xs[j * n + i] * b[j]
                    j += 1usize
                }
                if fam == 1usize {
                    let mu = math.exp[f64](eta)
                    w[i] = wn[i] * mu
                    z[i] = eta + (y[i] - mu) / mu
                } else {
                    var pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
                    if pr < 1.0e-9f64 { pr = 1.0e-9f64 }
                    if pr > 1.0f64 - 1.0e-9f64 { pr = 1.0f64 - 1.0e-9f64 }
                    w[i] = wn[i] * pr * (1.0f64 - pr)
                    z[i] = eta + (y[i] - pr) / (pr * (1.0f64 - pr))
                }
                r[i] = z[i] - eta
                wsum += w[i]
                i += 1usize
            }
            var change = 0.0f64
            var sweep = 0usize
            while sweep < 100000usize {
                var dmax = 0.0f64
                var sr = 0.0f64
                i = 0usize
                while i < n {
                    sr += w[i] * r[i]
                    i += 1usize
                }
                let d0 = sr / wsum
                i = 0usize
                while i < n {
                    r[i] -= d0
                    i += 1usize
                }
                b0 += d0
                if math.abs[f64](d0) > dmax { dmax = math.abs[f64](d0) }
                j = 0usize
                while j < p {
                    var cj = 0.0f64
                    var xr = 0.0f64
                    i = 0usize
                    while i < n {
                        cj += w[i] * xs[j * n + i] * xs[j * n + i]
                        xr += w[i] * xs[j * n + i] * r[i]
                        i += 1usize
                    }
                    let zj = xr + cj * b[j]
                    var nb = soft(zj, lam * alpha * pf[j]) / (cj + lam * (1.0f64 - alpha) * pf[j])
                    if lo.len == p && nb < lo[j] * sc[j] { nb = lo[j] * sc[j] }
                    if up.len == p && nb > up[j] * sc[j] { nb = up[j] * sc[j] }
                    let d = nb - b[j]
                    if d != 0.0f64 {
                        i = 0usize
                        while i < n {
                            r[i] -= d * xs[j * n + i]
                            i += 1usize
                        }
                        b[j] = nb
                        if math.abs[f64](d) > dmax { dmax = math.abs[f64](d) }
                        if math.abs[f64](d) > change { change = math.abs[f64](d) }
                    }
                    j += 1usize
                }
                if dmax < 1.0e-15f64 { break }
                sweep += 1usize
            }
            if change < 1.0e-13f64 { break }
            outer += 1usize
        }
        var c0 = b0
        j = 0usize
        while j < p {
            coef[k * (p + 1usize) + 1usize + j] = b[j] / sc[j]
            c0 -= b[j] / sc[j] * mx[j]
            j += 1usize
        }
        coef[k * (p + 1usize)] = c0
        if dev.len > k {
            var dv = 0.0f64
            i = 0usize
            while i < n {
                var eta = b0
                if off.len == n { eta += off[i] }
                j = 0usize
                while j < p {
                    eta += xs[j * n + i] * b[j]
                    j += 1usize
                }
                if fam == 1usize {
                    var ly = 0.0f64
                    if y[i] > 0.0f64 { ly = y[i] * math.log[f64](y[i]) - y[i] }
                    dv += 2.0f64 * wn[i] * (ly - (y[i] * eta - math.exp[f64](eta)))
                } else {
                    let lp = 0.0f64 - math.log[f64](1.0f64 + math.exp[f64](0.0f64 - eta))
                    let lq = 0.0f64 - math.log[f64](1.0f64 + math.exp[f64](eta))
                    dv -= 2.0f64 * wn[i] * (y[i] * lp + (1.0f64 - y[i]) * lq)
                }
                i += 1usize
            }
            dev[k] = dv
        }
        k += 1usize
    }
    ret ok
}

fn binomial(a: *mem.Arena, x: []const f64, y: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64) -> err {
    ret glm_path(a, 0usize, x, y, wt, off, n, p, alpha, standardize, vf, lambdas, coef)
}

// the poisson family (log link, y a count): the same proximal Newton with weights mu / n and working response eta + (y - mu) / mu
fn poisson(a: *mem.Arena, x: []const f64, y: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64) -> err {
    ret glm_path(a, 1usize, x, y, wt, off, n, p, alpha, standardize, vf, lambdas, coef)
}





// lambda.min (the largest lambda whose cvm equals the smallest) and lambda.1se (the largest lambda whose cvm is within one cvsd of that smallest) of cv.glmnet; out = (lambda.min, lambda.1se)
fn cv_select(lambdas: []const f64, cvm: []const f64, cvsd: []const f64, out: []f64) {
    var best = cvm[0usize]
    var at = 0usize
    var k = 1usize
    while k < lambdas.len {
        if cvm[k] < best { best = cvm[k] }
        k += 1usize
    }
    var lmin = 0.0f64 - 1.0e300f64
    k = 0usize
    while k < lambdas.len {
        if cvm[k] <= best && lambdas[k] > lmin {
            lmin = lambdas[k]
            at = k
        }
        k += 1usize
    }
    let lim = best + cvsd[at]
    var l1 = 0.0f64 - 1.0e300f64
    k = 0usize
    while k < lambdas.len {
        if cvm[k] <= lim && lambdas[k] > l1 { l1 = lambdas[k] }
        k += 1usize
    }
    out[0usize] = lmin
    out[1usize] = l1
}

// how many of the nlambda automatic lambdas glmnet (gaussian) reports: after the fifth, the path stops once the fraction of variance explained gains less than 1e-5 of itself, or passes 0.999 (the default dfmax of p + 1 never binds)
fn path_len(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize) -> usize {
    let (lam, e1) = mem.alloc[f64](a, nlambda)
    let (coef, e2) = mem.alloc[f64](a, nlambda * (p + 1usize))
    if e1 != ok || e2 != ok { ret 0usize }
    if lambda_path(a, x, y, n, p, alpha, standardize, vf, nlambda, lam) != ok { ret 0usize }
    let none: []const f64 = zero
    if gaussian(a, x, y, none, none, none, n, p, alpha, standardize, vf, lam, coef) != ok { ret 0usize }
    var ybar = 0.0f64
    var i = 0usize
    while i < n {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / f64(n)
    var sst = 0.0f64
    i = 0usize
    while i < n {
        sst += (y[i] - ybar) * (y[i] - ybar)
        i += 1usize
    }
    var prev = 0.0f64
    var k = 0usize
    while k < nlambda {
        var sse = 0.0f64
        i = 0usize
        while i < n {
            var f = coef[k * (p + 1usize)]
            var j = 0usize
            while j < p {
                f += x[j * n + i] * coef[k * (p + 1usize) + 1usize + j]
                j += 1usize
            }
            sse += (y[i] - f) * (y[i] - f)
            i += 1usize
        }
        let rsq = 1.0f64 - sse / sst
        if k + 1usize >= 5usize {
            if rsq - prev < 1.0e-5f64 * rsq { ret k + 1usize }
            if rsq > 0.999f64 { ret k + 1usize }
        }
        prev = rsq
        k += 1usize
    }
    ret nlambda
}

// the mgaussian family: m responses (y is n by m column-major) sharing one penalty, the group penalty lambda vf_j ((1 - alpha) / 2 ||b_j||^2 + alpha ||b_j||) over each variable's row of coefficients; the responses are not rescaled,
// so the ridge part is lambda (1 - alpha) unscaled. coef receives, for lambda k and response r, the intercept at (k * m + r) * (p + 1) and the p slopes after it, on the original scale
fn mgaussian(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, m: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64) -> err {
    let none: []const f64 = zero
    ret mgaussian_b(a, x, y, none, none, none, n, p, m, alpha, standardize, vf, lambdas, coef)
}

// the mgaussian family with observation weights wt (normalised to sum 1) and box constraints lo / up on every coefficient (original scale, empty for none), as glmnet's lower.limits and upper.limits: for each variable the group problem is solved with the coordinates that hit a bound held there and the
// norm of the others found by bisection (the free part is z / (c + lambda_2 + lambda_1 / norm))
fn mgaussian_b(a: *mem.Arena, x: []const f64, y: []const f64, wt: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, m: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (sc, e2) = mem.alloc[f64](a, p)
    let (mx, e3) = mem.alloc[f64](a, p)
    let (pf, e4) = mem.alloc[f64](a, p)
    let (b, e5) = mem.alloc[f64](a, p * m)
    let (r, e6) = mem.alloc[f64](a, n * m)
    let (ybar, e7) = mem.alloc[f64](a, m)
    let (z, e8) = mem.alloc[f64](a, m)
    let (q, e9) = mem.alloc[f64](a, n)
    let (nb, e10) = mem.alloc[f64](a, m)
    let (fixed, e11) = mem.alloc[usize](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret e1 }
    var qs = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { q[i] = wt[i] } else { q[i] = 1.0f64 }
        qs += q[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        q[i] = q[i] / qs
        i += 1usize
    }
    var c = 0usize
    while c < m {
        var sm = 0.0f64
        i = 0usize
        while i < n {
            sm += q[i] * y[c * n + i]
            i += 1usize
        }
        ybar[c] = sm
        c += 1usize
    }
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    j = 0usize
    while j < p {
        var mm = 0.0f64
        i = 0usize
        while i < n {
            mm += q[i] * x[j * n + i]
            i += 1usize
        }
        var s = 1.0f64
        if standardize {
            var v = 0.0f64
            i = 0usize
            while i < n {
                v += q[i] * (x[j * n + i] - mm) * (x[j * n + i] - mm)
                i += 1usize
            }
            s = math.sqrt[f64](v)
        }
        sc[j] = s
        mx[j] = mm
        i = 0usize
        while i < n {
            xs[j * n + i] = (x[j * n + i] - mm) / s
            i += 1usize
        }
        pf[j] = vf[j] * f64(p) / vs
        c = 0usize
        while c < m {
            b[c * p + j] = 0.0f64
            c += 1usize
        }
        j += 1usize
    }
    var k = 0usize
    while k < lambdas.len {
        let lam = lambdas[k]
        c = 0usize
        while c < m {
            i = 0usize
            while i < n {
                var f = 0.0f64
                j = 0usize
                while j < p {
                    f += xs[j * n + i] * b[c * p + j]
                    j += 1usize
                }
                r[c * n + i] = y[c * n + i] - ybar[c] - f
                i += 1usize
            }
            c += 1usize
        }
        var sweep = 0usize
        while sweep < 100000usize {
            var dmax = 0.0f64
            j = 0usize
            while j < p {
                var cj = 0.0f64
                i = 0usize
                while i < n {
                    cj += q[i] * xs[j * n + i] * xs[j * n + i]
                    i += 1usize
                }
                c = 0usize
                while c < m {
                    var xr = 0.0f64
                    i = 0usize
                    while i < n {
                        xr += q[i] * xs[j * n + i] * r[c * n + i]
                        i += 1usize
                    }
                    z[c] = xr + cj * b[c * p + j]
                    c += 1usize
                }
                let l1 = lam * alpha * pf[j]
                let l2 = lam * (1.0f64 - alpha) * pf[j]
                // the unconstrained group update, then the bounds
                var zn = 0.0f64
                c = 0usize
                while c < m {
                    zn += z[c] * z[c]
                    fixed[c] = 0usize
                    c += 1usize
                }
                zn = math.sqrt[f64](zn)
                var shrink = 0.0f64
                if zn > l1 { shrink = 1.0f64 - l1 / zn }
                c = 0usize
                while c < m {
                    nb[c] = shrink * z[c] / (cj + l2)
                    c += 1usize
                }
                if lo.len == p {
                    var again = true
                    while again {
                        again = false
                        var any = false
                        c = 0usize
                        while c < m {
                            if fixed[c] == 0usize {
                                if nb[c] < lo[j] * sc[j] {
                                    nb[c] = lo[j] * sc[j]
                                    fixed[c] = 1usize
                                    any = true
                                } else if nb[c] > up[j] * sc[j] {
                                    nb[c] = up[j] * sc[j]
                                    fixed[c] = 1usize
                                    any = true
                                }
                            }
                            c += 1usize
                        }
                        if any {
                            // the free coordinates against the norm of the whole vector
                            var cn = 0.0f64
                            var zf = 0.0f64
                            c = 0usize
                            while c < m {
                                if fixed[c] == 1usize { cn += nb[c] * nb[c] } else { zf += z[c] * z[c] }
                                c += 1usize
                            }
                            var lw = 0.0f64
                            var hg = math.sqrt[f64](cn + zf) / (cj + l2) + 1.0f64
                            var it = 0usize
                            while it < 200usize {
                                let u = 0.5f64 * (lw + hg)
                                var den = cj + l2
                                if u > 0.0f64 { den += l1 / u }
                                let gv = u * u - cn - zf / (den * den)
                                if gv > 0.0f64 { hg = u } else { lw = u }
                                it += 1usize
                            }
                            let un = 0.5f64 * (lw + hg)
                            var dn = cj + l2
                            if un > 0.0f64 { dn += l1 / un }
                            c = 0usize
                            while c < m {
                                if fixed[c] == 0usize { nb[c] = z[c] / dn }
                                c += 1usize
                            }
                            again = true
                        }
                    }
                }
                c = 0usize
                while c < m {
                    let d = nb[c] - b[c * p + j]
                    if d != 0.0f64 {
                        i = 0usize
                        while i < n {
                            r[c * n + i] -= d * xs[j * n + i]
                            i += 1usize
                        }
                        b[c * p + j] = nb[c]
                        if math.abs[f64](d) * math.sqrt[f64](cj) > dmax { dmax = math.abs[f64](d) * math.sqrt[f64](cj) }
                    }
                    c += 1usize
                }
                j += 1usize
            }
            if dmax < 1.0e-14f64 { break }
            sweep += 1usize
        }
        c = 0usize
        while c < m {
            var b0 = ybar[c]
            j = 0usize
            while j < p {
                coef[(k * m + c) * (p + 1usize) + 1usize + j] = b[c * p + j] / sc[j]
                b0 -= b[c * p + j] / sc[j] * mx[j]
                j += 1usize
            }
            coef[(k * m + c) * (p + 1usize)] = b0
            c += 1usize
        }
        k += 1usize
    }
    ret ok
}

// coef(fit, s) for an s that need not be on the path, glmnet's linear interpolation: with the lambdas rescaled to (lambda_1 - lambda) / (lambda_1 - lambda_nl), s lands between two neighbours (approx on the index) and the coefficients are mixed with the fraction
// (s_frac - rescaled_right) / (rescaled_left - rescaled_right); coef holds nl rows of the intercept and p slopes (as `gaussian` fills it); out receives the p + 1 interpolated values
fn coef_interp(lambdas: []const f64, coef: []const f64, p: usize, s: f64, out: []f64) {
    let nl = lambdas.len
    let l1 = lambdas[0usize]
    let ln = lambdas[nl - 1usize]
    var sf = (l1 - s) / (l1 - ln)
    if sf < 0.0f64 { sf = 0.0f64 }
    if sf > 1.0f64 { sf = 1.0f64 }
    // the rescaled lambdas increase from 0 to 1; find the interval holding sf
    var r = 1usize
    while r < nl - 1usize && (l1 - lambdas[r]) / (l1 - ln) < sf { r += 1usize }
    let lo = (l1 - lambdas[r - 1usize]) / (l1 - ln)
    let hi = (l1 - lambdas[r]) / (l1 - ln)
    let frac = (sf - hi) / (lo - hi)
    var j = 0usize
    while j <= p {
        out[j] = frac * coef[(r - 1usize) * (p + 1usize) + j] + (1.0f64 - frac) * coef[r * (p + 1usize) + j]
        j += 1usize
    }
}

// the fold assignment cv.glmnet makes when none is given: sample(rep(seq(nfolds), length = n)), folds numbered from 0 here; out receives n values
fn random_foldid(a: *mem.Arena, r: *rng.Rng, n: usize, nfolds: usize, out: []usize) -> err {
    let (s, e) = rng.sample_int(a, r, i64(n), i64(n), false)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        out[i] = (usize(s[i]) - 1usize) % nfolds
        i += 1usize
    }
    ret ok
}

// The Cox family (coxnet, ties by Breslow): indices of the observations in ascending time order (insertion sort, stable)
fn cox_ord(time: []const f64, ord: []usize) {
    let n = time.len
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = ord[i]
        var k = i
        while k > 0usize && time[ord[k - 1usize]] > time[v] {
            ord[k] = ord[k - 1usize]
            k -= 1usize
        }
        ord[k] = v
        i += 1usize
    }
}

// sum over the event times of d_k log d_k, with d_k the weighted number of events tied at the time
fn cox_dklog(time: []const f64, dq: []const f64, ord: []const usize) -> f64 {
    let n = time.len
    var tot = 0.0f64
    var st = 0usize
    while st < n {
        var en = st
        var dk = 0.0f64
        while en < n && time[ord[en]] == time[ord[st]] {
            dk += dq[ord[en]]
            en += 1usize
        }
        if dk > 0.0f64 { tot += dk * math.log[f64](dk) }
        st = en
    }
    ret tot
}

// e = q exp(f); fills the working weights w (the diagonal of the Hessian) and the working residual wr (the gradient of the partial log-likelihood in f) and returns sum_k d_k log(risk-set sum of e at the k-th event time); s is scratch of n
fn cox_quant(time: []const f64, dq: []const f64, ord: []const usize, e: []const f64, s: []f64, w: []f64, wr: []f64) -> f64 {
    let n = time.len
    var h = 0.0f64
    var m = n
    while m > 0usize {
        m -= 1usize
        h += e[ord[m]]
        s[m] = h
    }
    var bb = 0.0f64
    var cc = 0.0f64
    var lg = 0.0f64
    var st = 0usize
    while st < n {
        var en = st
        var dk = 0.0f64
        while en < n && time[ord[en]] == time[ord[st]] {
            dk += dq[ord[en]]
            en += 1usize
        }
        if dk > 0.0f64 {
            bb += dk / s[st]
            cc += dk / (s[st] * s[st])
            lg += dk * math.log[f64](s[st])
        }
        var pos = st
        while pos < en {
            let oi = ord[pos]
            w[oi] = e[oi] * (bb - e[oi] * cc)
            wr[oi] = dq[oi] - e[oi] * bb
            pos += 1usize
        }
        st = en
    }
    ret lg
}

// The Cox elastic-net path at the lambdas given: the objective is minus the weighted partial log-likelihood (weights normalised to sum 1) plus lambda sum vf_j ((1 - alpha) / 2 b_j^2 + alpha |b_j|) on columns centred and (when standardize) scaled to unit weighted variance, the penalty factors rescaled to sum to p; coef receives p slopes (original scale) per lambda
// and dev the fraction of the null partial-likelihood deviance explained (glmnet's dev.ratio). status is 1 for an event; wt and off may be empty; lo and up (bounds on the original-scale coefficients) may be empty. Each lambda is solved by outer reweighting (gradient and diagonal Hessian of the partial likelihood) and inner coordinate descent, run until nothing moves
fn cox(a: *mem.Arena, x: []const f64, time: []const f64, status: []const f64, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64, dev: []f64) -> err {
    let none: []const f64 = zero
    ret cox_ext(a, x, time, none, none, false, status, wt, off, lo, up, n, p, alpha, standardize, vf, lambdas, coef, dev)
}

// the same quantities as `cox_quant` when ties are broken by Efron's rule (efron), the responses are counting-process intervals (start empty or the entry times: a row is at risk at an event time T when start < T <= time), or the risk sets are per stratum (strata empty or one label per row);
// O(n times the number of event times). Every group of events tied in (stratum, time) adds, for Breslow, d_k / S to the gradient scale of every row at risk (S the weighted risk-set sum of e), and for Efron the d_k terms 1 / (S - (l / d) E), with E the sum of e over the tied events
fn cox_quant_g(time: []const f64, start: []const f64, strata: []const f64, dq: []const f64, e: []const f64, efron: bool, w: []f64, wr: []f64) -> f64 {
    let n = time.len
    var i = 0usize
    while i < n {
        w[i] = 0.0f64
        wr[i] = dq[i]
        i += 1usize
    }
    var lg = 0.0f64
    var g = 0usize
    while g < n {
        var first = dq[g] > 0.0f64
        var j = 0usize
        while j < g && first {
            if dq[j] > 0.0f64 && time[j] == time[g] && (strata.len == 0usize || strata[j] == strata[g]) { first = false }
            j += 1usize
        }
        if first {
            let tt = time[g]
            var d = 0.0f64
            var dw = 0.0f64
            var et = 0.0f64
            var sr = 0.0f64
            j = 0usize
            while j < n {
                let sameS = strata.len == 0usize || strata[j] == strata[g]
                if sameS && dq[j] > 0.0f64 && time[j] == tt {
                    d += 1.0f64
                    dw += dq[j]
                    et += e[j]
                }
                if sameS && time[j] >= tt && (start.len == 0usize || start[j] < tt) { sr += e[j] }
                j += 1usize
            }
            var l = 0usize
            var nl = 1usize
            if efron { nl = usize(d) }
            while l < nl {
                var dl = sr
                var c = dw
                var fr = 0.0f64
                if efron {
                    fr = f64(l) / d
                    dl = sr - fr * et
                    c = dw / d
                }
                lg += c * math.log[f64](dl)
                j = 0usize
                while j < n {
                    let sameS = strata.len == 0usize || strata[j] == strata[g]
                    if sameS && time[j] >= tt && (start.len == 0usize || start[j] < tt) {
                        var av = 1.0f64
                        if efron && dq[j] > 0.0f64 && time[j] == tt { av = 1.0f64 - fr }
                        let ea = e[j] * av
                        wr[j] -= c * ea / dl
                        w[j] += c * (ea / dl - ea * ea / (dl * dl))
                    }
                    j += 1usize
                }
                l += 1usize
            }
        }
        g += 1usize
    }
    ret lg
}

// the sum over (stratum, time) groups of events of d_k log d_k (Efron: the mean weight times log(d!)), the saturated term of the Cox deviance
fn cox_dklog_g(time: []const f64, strata: []const f64, dq: []const f64, efron: bool) -> f64 {
    let n = time.len
    var tot = 0.0f64
    var g = 0usize
    while g < n {
        var first = dq[g] > 0.0f64
        var j = 0usize
        while j < g && first {
            if dq[j] > 0.0f64 && time[j] == time[g] && (strata.len == 0usize || strata[j] == strata[g]) { first = false }
            j += 1usize
        }
        if first {
            var dw = 0.0f64
            var dc = 0.0f64
            j = 0usize
            while j < n {
                if dq[j] > 0.0f64 && time[j] == time[g] && (strata.len == 0usize || strata[j] == strata[g]) {
                    dw += dq[j]
                    dc += 1.0f64
                }
                j += 1usize
            }
            if efron {
                // Efron's saturated term: the average weight times log(d!)
                var lf = 0.0f64
                var l = 2usize
                while l <= usize(dc) {
                    lf += math.log[f64](f64(l))
                    l += 1usize
                }
                tot += dw / dc * lf
            } else {
                tot += dw * math.log[f64](dw)
            }
        }
        g += 1usize
    }
    ret tot
}

fn cox_qa(time: []const f64, start: []const f64, strata: []const f64, dq: []const f64, ord: []const usize, e: []const f64, s: []f64, efron: bool, w: []f64, wr: []f64) -> f64 {
    if start.len == 0usize && strata.len == 0usize && !efron { ret cox_quant(time, dq, ord, e, s, w, wr) }
    ret cox_quant_g(time, start, strata, dq, e, efron, w, wr)
}

fn cox_dk_a(time: []const f64, strata: []const f64, dq: []const f64, ord: []const usize, efron: bool) -> f64 {
    if strata.len == 0usize && !efron { ret cox_dklog(time, dq, ord) }
    ret cox_dklog_g(time, strata, dq, efron)
}

fn cox_ext(a: *mem.Arena, x: []const f64, time: []const f64, start: []const f64, strata: []const f64, efron: bool, status: []const f64, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, coef: []f64, dev: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (sc, e2) = mem.alloc[f64](a, p)
    let (pf, e3) = mem.alloc[f64](a, p)
    let (b, e4) = mem.alloc[f64](a, p)
    let (q, e5) = mem.alloc[f64](a, n)
    let (dq, e6) = mem.alloc[f64](a, n)
    let (ee, e7) = mem.alloc[f64](a, n)
    let (ff, e8) = mem.alloc[f64](a, n)
    let (w, e9) = mem.alloc[f64](a, n)
    let (wr, e10) = mem.alloc[f64](a, n)
    let (ss, e11) = mem.alloc[f64](a, n)
    let (ord, e12) = mem.alloc[usize](a, n)
    let (v, e13) = mem.alloc[f64](a, p)
    let (bs, e14) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret e1 }
    var qs = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { q[i] = wt[i] } else { q[i] = 1.0f64 }
        qs += q[i]
        i += 1usize
    }
    var og = 0.0f64
    i = 0usize
    while i < n {
        q[i] = q[i] / qs
        dq[i] = q[i] * status[i]
        if off.len == n { og += q[i] * off[i] }
        i += 1usize
    }
    cox_ord(time, ord)
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += q[i] * x[j * n + i]
            i += 1usize
        }
        var s = 1.0f64
        if standardize {
            var vv = 0.0f64
            i = 0usize
            while i < n {
                vv += q[i] * (x[j * n + i] - m) * (x[j * n + i] - m)
                i += 1usize
            }
            s = math.sqrt[f64](vv)
        }
        sc[j] = s
        i = 0usize
        while i < n {
            xs[j * n + i] = (x[j * n + i] - m) / s
            i += 1usize
        }
        pf[j] = vf[j] * f64(p) / vs
        b[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        ff[i] = 0.0f64
        if off.len == n { ff[i] = off[i] - og }
        ee[i] = q[i] * math.exp[f64](ff[i])
        i += 1usize
    }
    let r0 = 0.0f64 - cox_qa(time, start, strata, dq, ord, ee, ss, efron, w, wr)
    var d0 = 0.0f64
    i = 0usize
    while i < n {
        d0 += dq[i] * ff[i]
        i += 1usize
    }
    let risk0 = d0 + r0
    let rr = 0.0f64 - (cox_dk_a(time, strata, dq, ord, efron) + risk0)
    var k = 0usize
    while k < lambdas.len {
        let lam = lambdas[k]
        var outer = 0usize
        while outer < 500usize {
            i = 0usize
            while i < n {
                ee[i] = q[i] * math.exp[f64](ff[i])
                i += 1usize
            }
            let lg = cox_qa(time, start, strata, dq, ord, ee, ss, efron, w, wr)
            j = 0usize
            while j < p {
                var vj = 0.0f64
                i = 0usize
                while i < n {
                    vj += w[i] * xs[j * n + i] * xs[j * n + i]
                    i += 1usize
                }
                v[j] = vj
                bs[j] = b[j]
                j += 1usize
            }
            var sweep = 0usize
            while sweep < 100000usize {
                var dli = 0.0f64
                j = 0usize
                while j < p {
                    var g = 0.0f64
                    i = 0usize
                    while i < n {
                        g += wr[i] * xs[j * n + i]
                        i += 1usize
                    }
                    let u = b[j] * v[j] + g
                    var at = 0.0f64
                    if math.abs[f64](u) > pf[j] * lam * alpha { at = soft(u, pf[j] * lam * alpha) / (v[j] + pf[j] * lam * (1.0f64 - alpha)) }
                    if lo.len == p && at < lo[j] * sc[j] { at = lo[j] * sc[j] }
                    if up.len == p && at > up[j] * sc[j] { at = up[j] * sc[j] }
                    let del = at - b[j]
                    if del != 0.0f64 {
                        b[j] = at
                        if v[j] * del * del > dli { dli = v[j] * del * del }
                        i = 0usize
                        while i < n {
                            wr[i] -= del * w[i] * xs[j * n + i]
                            ff[i] += del * xs[j * n + i]
                            i += 1usize
                        }
                    }
                    j += 1usize
                }
                if dli < 1.0e-30f64 { break }
                sweep += 1usize
            }
            var change = 0.0f64
            j = 0usize
            while j < p {
                if math.abs[f64](b[j] - bs[j]) > change { change = math.abs[f64](b[j] - bs[j]) }
                j += 1usize
            }
            if lg != lg { break }
            if change < 1.0e-13f64 { break }
            outer += 1usize
        }
        i = 0usize
        while i < n {
            ee[i] = q[i] * math.exp[f64](ff[i])
            i += 1usize
        }
        let lgk = cox_qa(time, start, strata, dq, ord, ee, ss, efron, w, wr)
        var dk2 = 0.0f64
        i = 0usize
        while i < n {
            dk2 += dq[i] * ff[i]
            i += 1usize
        }
        if dev.len > k { dev[k] = (dk2 - lgk - risk0) / rr }
        j = 0usize
        while j < p {
            coef[k * p + j] = b[j] / sc[j]
            j += 1usize
        }
        k += 1usize
    }
    ret ok
}

// glmnet's automatic lambda sequence for the Cox family (nlambda values from lambda_max down by the ratio 1e-4, or 1e-2 when n < p): lambda_max = max_j |gradient_j| / (vf_j max(alpha, 0.001)) at the null model on the standardised columns (penalty factors rescaled to sum to p; a zero factor is skipped)
fn cox_lambda_path(a: *mem.Arena, x: []const f64, time: []const f64, status: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize, out: []f64) -> err {
    let none: []const f64 = zero
    ret cox_lambda_path_ext(a, x, time, none, none, false, status, wt, off, n, p, alpha, standardize, vf, nlambda, out)
}

fn cox_lambda_path_ext(a: *mem.Arena, x: []const f64, time: []const f64, start: []const f64, strata: []const f64, efron: bool, status: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize, out: []f64) -> err {
    let (q, e1) = mem.alloc[f64](a, n)
    let (dq, e2) = mem.alloc[f64](a, n)
    let (ee, e3) = mem.alloc[f64](a, n)
    let (w, e4) = mem.alloc[f64](a, n)
    let (wr, e5) = mem.alloc[f64](a, n)
    let (ss, e6) = mem.alloc[f64](a, n)
    let (ord, e7) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret e1 }
    var qs = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { q[i] = wt[i] } else { q[i] = 1.0f64 }
        qs += q[i]
        i += 1usize
    }
    var og = 0.0f64
    i = 0usize
    while i < n {
        q[i] = q[i] / qs
        dq[i] = q[i] * status[i]
        if off.len == n { og += q[i] * off[i] }
        i += 1usize
    }
    cox_ord(time, ord)
    i = 0usize
    while i < n {
        var fi = 0.0f64
        if off.len == n { fi = off[i] - og }
        ee[i] = q[i] * math.exp[f64](fi)
        i += 1usize
    }
    let lg0 = cox_qa(time, start, strata, dq, ord, ee, ss, efron, w, wr)
    if lg0 != lg0 { ret e1 }
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    var lmax = 0.0f64
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += q[i] * x[j * n + i]
            i += 1usize
        }
        var vv = 0.0f64
        var gj = 0.0f64
        i = 0usize
        while i < n {
            vv += q[i] * (x[j * n + i] - m) * (x[j * n + i] - m)
            gj += wr[i] * (x[j * n + i] - m)
            i += 1usize
        }
        if standardize { gj = gj / math.sqrt[f64](vv) }
        let vj = vf[j] * f64(p) / vs
        if vj > 0.0f64 {
            var al = alpha
            if al < 0.001f64 { al = 0.001f64 }
            let c = math.abs[f64](gj) / (al * vj)
            if c > lmax { lmax = c }
        }
        j += 1usize
    }
    var ratio = 1.0e-4f64
    if n < p { ratio = 1.0e-2f64 }
    var k = 0usize
    while k < nlambda {
        out[k] = lmax * math.pow[f64](ratio, f64(k) / f64(nlambda - 1usize))
        k += 1usize
    }
    ret ok
}

// how many of the nlambda automatic lambdas glmnet reports for the Cox family: from the fifth on, the path stops once the deviance ratio gains less than a thousandth of itself over the last five lambdas, or passes 0.99
fn cox_path_len(a: *mem.Arena, x: []const f64, time: []const f64, status: []const f64, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize) -> usize {
    let none: []const f64 = zero
    ret cox_path_len_ext(a, x, time, none, none, false, status, wt, off, lo, up, n, p, alpha, standardize, vf, nlambda)
}

fn cox_path_len_ext(a: *mem.Arena, x: []const f64, time: []const f64, start: []const f64, strata: []const f64, efron: bool, status: []const f64, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize) -> usize {
    let (lam, e1) = mem.alloc[f64](a, nlambda)
    let (coef, e2) = mem.alloc[f64](a, nlambda * p)
    let (dev, e3) = mem.alloc[f64](a, nlambda)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    if cox_lambda_path_ext(a, x, time, start, strata, efron, status, wt, off, n, p, alpha, standardize, vf, nlambda, lam) != ok { ret 0usize }
    if cox_ext(a, x, time, start, strata, efron, status, wt, off, lo, up, n, p, alpha, standardize, vf, lam, coef, dev) != ok { ret 0usize }
    var k = 4usize
    while k < nlambda {
        if (dev[k] - dev[k - 4usize]) / dev[k] < 1.0e-3f64 { ret k + 1usize }
        if dev[k] > 0.99f64 { ret k + 1usize }
        k += 1usize
    }
    ret nlambda
}

// softmax probability of class k for every observation (eta is n by nc column-major), written to out
fn mn_prob(eta: []const f64, n: usize, nc: usize, k: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var mx = eta[i]
        var c = 1usize
        while c < nc {
            if eta[c * n + i] > mx { mx = eta[c * n + i] }
            c += 1usize
        }
        var s = 0.0f64
        c = 0usize
        while c < nc {
            s += math.exp[f64](eta[c * n + i] - mx)
            c += 1usize
        }
        out[i] = math.exp[f64](eta[k * n + i] - mx) / s
        i += 1usize
    }
}

// solves the small dense system a x = b (a is n by n row-major, overwritten; the answer replaces b) by Gaussian elimination with partial pivoting
fn solve_small(a: []f64, b: []f64, n: usize) {
    var col = 0usize
    while col < n {
        var piv = col
        var r = col + 1usize
        while r < n {
            if math.abs[f64](a[r * n + col]) > math.abs[f64](a[piv * n + col]) { piv = r }
            r += 1usize
        }
        if piv != col {
            var c = 0usize
            while c < n {
                let t = a[col * n + c]
                a[col * n + c] = a[piv * n + c]
                a[piv * n + c] = t
                c += 1usize
            }
            let tb = b[col]
            b[col] = b[piv]
            b[piv] = tb
        }
        r = col + 1usize
        while r < n {
            let fct = a[r * n + col] / a[col * n + col]
            var c = col
            while c < n {
                a[r * n + c] -= fct * a[col * n + c]
                c += 1usize
            }
            b[r] -= fct * b[col]
            r += 1usize
        }
        col += 1usize
    }
    var rr = n
    while rr > 0usize {
        rr -= 1usize
        var t = b[rr]
        var c = rr + 1usize
        while c < n {
            t -= a[rr * n + c] * b[c]
            c += 1usize
        }
        b[rr] = t / a[rr * n + rr]
    }
}

// the softmax probabilities of every class (n by nc column-major), from eta of the same shape
fn mn_probs(eta: []const f64, n: usize, nc: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var mx = eta[i]
        var c = 1usize
        while c < nc {
            if eta[c * n + i] > mx { mx = eta[c * n + i] }
            c += 1usize
        }
        var sm = 0.0f64
        c = 0usize
        while c < nc {
            out[c * n + i] = math.exp[f64](eta[c * n + i] - mx)
            sm += out[c * n + i]
            c += 1usize
        }
        c = 0usize
        while c < nc {
            out[c * n + i] = out[c * n + i] / sm
            c += 1usize
        }
        i += 1usize
    }
}

// the weighted multinomial deviance -2 sum_i q_i log p_i,lab(i)
fn mn_dev(eta: []const f64, lab: []const usize, q: []const f64, n: usize, nc: usize, pr: []f64) -> f64 {
    var d = 0.0f64
    var k = 0usize
    while k < nc {
        mn_prob(eta, n, nc, k, pr)
        var i = 0usize
        while i < n {
            if lab[i] == k { d -= 2.0f64 * q[i] * math.log[f64](pr[i]) }
            i += 1usize
        }
        k += 1usize
    }
    ret d
}

// The multinomial family (symmetric, one coefficient vector per class, intercepts centred over the classes as glmnet reports them): the elastic-net penalised negative log-likelihood (weights normalised to sum 1, offsets an n by nc matrix or empty)
// with lambda sum_j vf_j sum_k ((1 - alpha) / 2 b_jk^2 + alpha |b_jk|) when `grouped` is false, and lambda sum_j vf_j ((1 - alpha) / 2 ||b_j||^2 + alpha ||b_j||) over each variable's vector of class coefficients when it is true (type.multinomial = "grouped"). lab holds the class of
// each observation (0 .. nc - 1). Ungrouped: class by class, a reweighted least-squares quadratic (weights p (1 - p)) solved by coordinate descent, repeated until nothing moves; grouped: coordinate descent over the variables on the bound 1/2 of the Hessian, which cannot overshoot. coef receives, for lambda k and class c, the intercept at (k nc + c) (p + 1) and the p slopes after it, on the original
// scale; dev receives glmnet's dev.ratio per lambda
fn multinomial(a: *mem.Arena, x: []const f64, lab: []const usize, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, nc: usize, alpha: f64, standardize: bool, grouped: bool, vf: []const f64, lambdas: []const f64, coef: []f64, dev: []f64) -> err {
    ret multinomial_tol(a, x, lab, wt, off, lo, up, n, p, nc, alpha, standardize, grouped, vf, lambdas, 1.0e-13f64, true, coef, dev)
}

// as `multinomial` (centre false leaves out the re-centring of each variable's coefficients over the classes), run until no coefficient moves by more than tol in a pass (glmnet's own thresh leaves errors near 1e-7, so a cross-validation that is compared with it needs no more than 1e-9)
fn multinomial_tol(a: *mem.Arena, x: []const f64, lab: []const usize, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, nc: usize, alpha: f64, standardize: bool, grouped: bool, vf: []const f64, lambdas: []const f64, tol: f64, centre: bool, coef: []f64, dev: []f64) -> err {
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (sc, e2) = mem.alloc[f64](a, p)
    let (mx, e3) = mem.alloc[f64](a, p)
    let (pf, e4) = mem.alloc[f64](a, p)
    let (b, e5) = mem.alloc[f64](a, p * nc)
    let (b0, e6) = mem.alloc[f64](a, nc)
    let (eta, e7) = mem.alloc[f64](a, n * nc)
    let (q, e8) = mem.alloc[f64](a, n)
    let (w, e9) = mem.alloc[f64](a, n)
    let (r, e10) = mem.alloc[f64](a, n)
    let (pr, e11) = mem.alloc[f64](a, n)
    let (z, e12) = mem.alloc[f64](a, nc)
    let (bo, e13) = mem.alloc[f64](a, nc)
    let (pm, e14) = mem.alloc[f64](a, n * nc)
    let (hm, e15) = mem.alloc[f64](a, nc * nc)
    let (sa, e16) = mem.alloc[f64](a, nc * nc)
    let (gv, e17) = mem.alloc[f64](a, nc)
    let (bn, e18) = mem.alloc[f64](a, nc)
    if e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok { ret e14 }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret e1 }
    var qs = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { q[i] = wt[i] } else { q[i] = 1.0f64 }
        qs += q[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        q[i] = q[i] / qs
        i += 1usize
    }
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += q[i] * x[j * n + i]
            i += 1usize
        }
        var s = 1.0f64
        if standardize {
            var vv = 0.0f64
            i = 0usize
            while i < n {
                vv += q[i] * (x[j * n + i] - m) * (x[j * n + i] - m)
                i += 1usize
            }
            s = math.sqrt[f64](vv)
        }
        sc[j] = s
        mx[j] = m
        i = 0usize
        while i < n {
            xs[j * n + i] = (x[j * n + i] - m) / s
            i += 1usize
        }
        pf[j] = vf[j] * f64(p) / vs
        var c2 = 0usize
        while c2 < nc {
            b[c2 * p + j] = 0.0f64
            c2 += 1usize
        }
        j += 1usize
    }
    var c = 0usize
    while c < nc {
        var fr = 0.0f64
        i = 0usize
        while i < n {
            if lab[i] == c { fr += q[i] }
            i += 1usize
        }
        b0[c] = math.log[f64](fr)
        i = 0usize
        while i < n {
            eta[c * n + i] = b0[c]
            if off.len == n * nc { eta[c * n + i] += off[c * n + i] }
            i += 1usize
        }
        c += 1usize
    }
    var nulldev = 0.0f64
    var k = 0usize
    while k <= lambdas.len {
        var lam = 1.0e300f64
        if k > 0usize { lam = lambdas[k - 1usize] }
        var outer = 0usize
        while outer < 20000usize {
            var change = 0.0f64
            if !grouped {
                c = 0usize
                while c < nc {
                    mn_prob(eta, n, nc, c, pr)
                    var v0 = 0.0f64
                    var u0 = 0.0f64
                    i = 0usize
                    while i < n {
                        var vv = pr[i] * (1.0f64 - pr[i])
                        if vv < 1.0e-12f64 { vv = 1.0e-12f64 }
                        w[i] = q[i] * vv
                        var yy = 0.0f64
                        if lab[i] == c { yy = 1.0f64 }
                        r[i] = q[i] * (yy - pr[i])
                        v0 += w[i]
                        u0 += r[i]
                        i += 1usize
                    }
                    var sweep = 0usize
                    while sweep < 100000usize {
                        var dli = 0.0f64
                        var d0 = 0.0f64
                        u0 = 0.0f64
                        i = 0usize
                        while i < n {
                            u0 += r[i]
                            i += 1usize
                        }
                        d0 = u0 / v0
                        if d0 != 0.0f64 {
                            b0[c] += d0
                            i = 0usize
                            while i < n {
                                r[i] -= d0 * w[i]
                                eta[c * n + i] += d0
                                i += 1usize
                            }
                            if v0 * d0 * d0 > dli { dli = v0 * d0 * d0 }
                            if math.abs[f64](d0) > change { change = math.abs[f64](d0) }
                        }
                        j = 0usize
                        while j < p {
                            var vj = 0.0f64
                            var gj = 0.0f64
                            i = 0usize
                            while i < n {
                                vj += w[i] * xs[j * n + i] * xs[j * n + i]
                                gj += r[i] * xs[j * n + i]
                                i += 1usize
                            }
                            let u = b[c * p + j] * vj + gj
                            var at = 0.0f64
                            if math.abs[f64](u) > pf[j] * lam * alpha { at = soft(u, pf[j] * lam * alpha) / (vj + pf[j] * lam * (1.0f64 - alpha)) }
                            if lo.len == p && at < lo[j] * sc[j] { at = lo[j] * sc[j] }
                            if up.len == p && at > up[j] * sc[j] { at = up[j] * sc[j] }
                            let del = at - b[c * p + j]
                            if del != 0.0f64 {
                                b[c * p + j] = at
                                if vj * del * del > dli { dli = vj * del * del }
                                if math.abs[f64](del) > change { change = math.abs[f64](del) }
                                i = 0usize
                                while i < n {
                                    r[i] -= del * w[i] * xs[j * n + i]
                                    eta[c * n + i] += del * xs[j * n + i]
                                    i += 1usize
                                }
                            }
                            j += 1usize
                        }
                        if dli < 1.0e-30f64 { break }
                        sweep += 1usize
                    }
                    c += 1usize
                }
                // the loss does not change when one variable's coefficient moves by the same amount in every class, so re-centre each variable on the shift that minimises its penalty (a bisection on the monotone derivative); this removes the slow flat direction
                if lo.len != p && centre {
                    j = 0usize
                    while j < p {
                        if pf[j] > 0.0f64 {
                            var lb = 0.0f64
                            c = 0usize
                            while c < nc {
                                if math.abs[f64](b[c * p + j]) > lb { lb = math.abs[f64](b[c * p + j]) }
                                c += 1usize
                            }
                            var lw = 0.0f64 - lb - 1.0f64
                            var hg = lb + 1.0f64
                            var it = 0usize
                            while it < 200usize {
                                let mid = 0.5f64 * (lw + hg)
                                var gd = 0.0f64
                                c = 0usize
                                while c < nc {
                                    let t = b[c * p + j] + mid
                                    if t > 0.0f64 { gd += alpha }
                                    if t < 0.0f64 { gd -= alpha }
                                    gd += (1.0f64 - alpha) * t
                                    c += 1usize
                                }
                                if gd > 0.0f64 { hg = mid } else { lw = mid }
                                it += 1usize
                            }
                            let sh = 0.5f64 * (lw + hg)
                            c = 0usize
                            while c < nc {
                                b[c * p + j] += sh
                                c += 1usize
                            }
                            c = 0usize
                            while c < nc {
                                i = 0usize
                                while i < n {
                                    eta[c * n + i] += sh * xs[j * n + i]
                                    i += 1usize
                                }
                                c += 1usize
                            }
                        }
                        j += 1usize
                    }
                }
            } else {
                // grouped: one pass over the intercepts (a Newton step on the centred intercepts) and the variables; for each variable the group's coefficients move by a proximal Newton step on the exact K by K block of the Hessian, solved by inner proximal-gradient iterations
                mn_probs(eta, n, nc, pm)
                c = 0usize
                while c < nc * nc {
                    hm[c] = 0.0f64
                    c += 1usize
                }
                c = 0usize
                while c < nc {
                    gv[c] = 0.0f64
                    c += 1usize
                }
                i = 0usize
                while i < n {
                    c = 0usize
                    while c < nc {
                        var yy = 0.0f64
                        if lab[i] == c { yy = 1.0f64 }
                        gv[c] += q[i] * (yy - pm[c * n + i])
                        var c2 = 0usize
                        while c2 < nc {
                            var dg = 0.0f64
                            if c == c2 { dg = pm[c * n + i] }
                            hm[c * nc + c2] += q[i] * (dg - pm[c * n + i] * pm[c2 * n + i]) + 1.0f64 / f64(n) / f64(nc) * 0.0f64
                            c2 += 1usize
                        }
                        c += 1usize
                    }
                    i += 1usize
                }
                // (H + 11') d = g gives the step with sum d = 0, because H 1 = 0 and g sums to zero
                c = 0usize
                while c < nc {
                    var c2 = 0usize
                    while c2 < nc {
                        sa[c * nc + c2] = hm[c * nc + c2] + 1.0f64
                        c2 += 1usize
                    }
                    bo[c] = gv[c]
                    c += 1usize
                }
                solve_small(sa, bo, nc)
                c = 0usize
                while c < nc {
                    b0[c] += bo[c]
                    if math.abs[f64](bo[c]) > change { change = math.abs[f64](bo[c]) }
                    i = 0usize
                    while i < n {
                        eta[c * n + i] += bo[c]
                        i += 1usize
                    }
                    c += 1usize
                }
                j = 0usize
                while j < p {
                    mn_probs(eta, n, nc, pm)
                    c = 0usize
                    while c < nc * nc {
                        hm[c] = 0.0f64
                        c += 1usize
                    }
                    c = 0usize
                    while c < nc {
                        gv[c] = 0.0f64
                        c += 1usize
                    }
                    i = 0usize
                    while i < n {
                        let xi = xs[j * n + i]
                        c = 0usize
                        while c < nc {
                            var yy = 0.0f64
                            if lab[i] == c { yy = 1.0f64 }
                            gv[c] += q[i] * xi * (yy - pm[c * n + i])
                            var c2 = 0usize
                            while c2 < nc {
                                var dg = 0.0f64
                                if c == c2 { dg = pm[c * n + i] }
                                hm[c * nc + c2] += q[i] * xi * xi * (dg - pm[c * n + i] * pm[c2 * n + i])
                                c2 += 1usize
                            }
                            c += 1usize
                        }
                        i += 1usize
                    }
                    // the largest eigenvalue of the block by power iteration
                    c = 0usize
                    while c < nc {
                        z[c] = f64(c) - 0.5f64 * f64(nc - 1usize) + 0.1f64 * f64((c * 3usize) % 2usize)
                        c += 1usize
                    }
                    var lh = 1.0e-12f64
                    var it = 0usize
                    while it < 40usize {
                        var nrm = 0.0f64
                        c = 0usize
                        while c < nc {
                            var t = 0.0f64
                            var c2 = 0usize
                            while c2 < nc {
                                t += hm[c * nc + c2] * z[c2]
                                c2 += 1usize
                            }
                            bo[c] = t
                            nrm += t * t
                            c += 1usize
                        }
                        nrm = math.sqrt[f64](nrm)
                        if nrm < 1.0e-300f64 { break }
                        c = 0usize
                        while c < nc {
                            z[c] = bo[c] / nrm
                            c += 1usize
                        }
                        lh = nrm
                        it += 1usize
                    }
                    lh = lh * 1.05f64 + 1.0e-12f64
                    let l1 = lam * alpha * pf[j]
                    let l2 = lam * (1.0f64 - alpha) * pf[j]
                    c = 0usize
                    while c < nc {
                        bn[c] = b[c * p + j]
                        c += 1usize
                    }
                    var inner = 0usize
                    while inner < 500usize {
                        var vn = 0.0f64
                        c = 0usize
                        while c < nc {
                            var t = 0.0f64 - gv[c]
                            var c2 = 0usize
                            while c2 < nc {
                                t += hm[c * nc + c2] * (bn[c2] - b[c2 * p + j])
                                c2 += 1usize
                            }
                            bo[c] = (lh * bn[c] - t) / (lh + l2)
                            vn += bo[c] * bo[c]
                            c += 1usize
                        }
                        vn = math.sqrt[f64](vn)
                        var sh = 0.0f64
                        if vn > l1 / (lh + l2) { sh = 1.0f64 - l1 / (lh + l2) / vn }
                        var dmv = 0.0f64
                        c = 0usize
                        while c < nc {
                            let nv = sh * bo[c]
                            if math.abs[f64](nv - bn[c]) > dmv { dmv = math.abs[f64](nv - bn[c]) }
                            bn[c] = nv
                            c += 1usize
                        }
                        if dmv < 1.0e-15f64 { break }
                        inner += 1usize
                    }
                    c = 0usize
                    while c < nc {
                        let d = bn[c] - b[c * p + j]
                        if d != 0.0f64 {
                            b[c * p + j] = bn[c]
                            if math.abs[f64](d) > change { change = math.abs[f64](d) }
                            i = 0usize
                            while i < n {
                                eta[c * n + i] += d * xs[j * n + i]
                                i += 1usize
                            }
                        }
                        c += 1usize
                    }
                    j += 1usize
                }
            }
            if change < tol { break }
            outer += 1usize
        }
        let dv = mn_dev(eta, lab, q, n, nc, pr)
        if k == 0usize {
            nulldev = dv
        } else {
            if dev.len >= k { dev[k - 1usize] = 1.0f64 - dv / nulldev }
            var mean0 = 0.0f64
            c = 0usize
            while c < nc {
                var a0 = b0[c]
                j = 0usize
                while j < p {
                    var bv = b[c * p + j]
                    if math.abs[f64](bv) < 1.0e-12f64 { bv = 0.0f64 }
                    coef[((k - 1usize) * nc + c) * (p + 1usize) + 1usize + j] = bv / sc[j]
                    a0 -= bv / sc[j] * mx[j]
                    j += 1usize
                }
                bo[c] = a0
                mean0 += a0
                c += 1usize
            }
            mean0 = mean0 / f64(nc)
            c = 0usize
            while c < nc {
                coef[((k - 1usize) * nc + c) * (p + 1usize)] = bo[c] - mean0
                c += 1usize
            }
        }
        k += 1usize
    }
    ret ok
}

// glmnet's automatic lambda sequence for the binomial (fam 0) and poisson (fam 1) families: at the intercept-only model (an offset is allowed), lambda_max = max_j |sum_i q_i xs_ij (y_i - mu_i)| / (vf_j max(alpha, 0.001)) on the standardised columns with the penalty factors rescaled to sum to p,
// then nlambda values equally spaced on the log scale down to the ratio 1e-4 (1e-2 when n < p)
fn glm_lambda_path(a: *mem.Arena, fam: usize, x: []const f64, y: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize, out: []f64) -> err {
    let (q, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var qs = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { q[i] = wt[i] } else { q[i] = 1.0f64 }
        qs += q[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        q[i] = q[i] / qs
        i += 1usize
    }
    var yb = 0.0f64
    i = 0usize
    while i < n {
        yb += q[i] * y[i]
        i += 1usize
    }
    var b0 = math.log[f64](yb / (1.0f64 - yb))
    if fam == 1usize { b0 = math.log[f64](yb) }
    var it = 0usize
    while it < 100usize {
        var g = 0.0f64
        var h = 0.0f64
        i = 0usize
        while i < n {
            var eta = b0
            if off.len == n { eta += off[i] }
            if fam == 1usize {
                let mu = math.exp[f64](eta)
                g += q[i] * (y[i] - mu)
                h += q[i] * mu
            } else {
                let pr = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta))
                g += q[i] * (y[i] - pr)
                h += q[i] * pr * (1.0f64 - pr)
            }
            i += 1usize
        }
        b0 += g / h
        it += 1usize
    }
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    var lmax = 0.0f64
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += q[i] * x[j * n + i]
            i += 1usize
        }
        var vv = 0.0f64
        var gj = 0.0f64
        i = 0usize
        while i < n {
            var eta = b0
            if off.len == n { eta += off[i] }
            var mu = 0.0f64
            if fam == 1usize { mu = math.exp[f64](eta) } else { mu = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta)) }
            vv += q[i] * (x[j * n + i] - m) * (x[j * n + i] - m)
            gj += q[i] * (x[j * n + i] - m) * (y[i] - mu)
            i += 1usize
        }
        if standardize { gj = gj / math.sqrt[f64](vv) }
        let vj = vf[j] * f64(p) / vs
        if vj > 0.0f64 {
            var al = alpha
            if al < 0.001f64 { al = 0.001f64 }
            let c = math.abs[f64](gj) / (al * vj)
            if c > lmax { lmax = c }
        }
        j += 1usize
    }
    var ratio = 1.0e-4f64
    if n < p { ratio = 1.0e-2f64 }
    var k = 0usize
    while k < nlambda {
        out[k] = lmax * math.pow[f64](ratio, f64(k) / f64(nlambda - 1usize))
        k += 1usize
    }
    ret ok
}

// the number of automatic lambdas glmnet reports for the binomial or poisson family: from the fifth on, the path stops once the deviance ratio gains less than 1e-5 over the last lambda (binomial) or less than 1e-4 of itself over the last four steps (poisson), or passes 0.999
fn glm_path_len(a: *mem.Arena, fam: usize, x: []const f64, y: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize) -> usize {
    let (lam, e1) = mem.alloc[f64](a, nlambda)
    let (coef, e2) = mem.alloc[f64](a, nlambda * (p + 1usize))
    let (dev, e3) = mem.alloc[f64](a, nlambda)
    let (cf0, e4) = mem.alloc[f64](a, p + 1usize)
    let (dv0, e5) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0usize }
    if glm_lambda_path(a, fam, x, y, wt, off, n, p, alpha, standardize, vf, nlambda, lam) != ok { ret 0usize }
    let none: []const f64 = zero
    let (big, e6) = mem.alloc[f64](a, 1usize)
    if e6 != ok { ret 0usize }
    big[0usize] = 1.0e300f64
    if glm_path_dev(a, fam, x, y, wt, off, none, none, n, p, alpha, standardize, vf, big, cf0, dv0) != ok { ret 0usize }
    if glm_path_dev(a, fam, x, y, wt, off, none, none, n, p, alpha, standardize, vf, lam, coef, dev) != ok { ret 0usize }
    var k = 4usize
    while k < nlambda {
        let r1 = 1.0f64 - dev[k] / dv0[0usize]
        let r0 = 1.0f64 - dev[k - 1usize] / dv0[0usize]
        let r4 = 1.0f64 - dev[k - 4usize] / dv0[0usize]
        if fam == 0usize && r1 - r0 < 1.0e-5f64 { ret k + 1usize }
        if fam == 1usize && r1 - r4 < 1.0e-4f64 * r1 { ret k + 1usize }
        if r1 > 0.999f64 { ret k + 1usize }
        k += 1usize
    }
    ret nlambda
}

// glmnet's automatic lambda sequence for the multinomial family (ungrouped: the largest |gradient| over variable and class; grouped: the largest norm over the classes), at the intercept-only fit; lab holds the classes 0 .. nc - 1
fn multinomial_lambda_path(a: *mem.Arena, x: []const f64, lab: []const usize, wt: []const f64, off: []const f64, n: usize, p: usize, nc: usize, alpha: f64, standardize: bool, grouped: bool, vf: []const f64, nlambda: usize, out: []f64) -> err {
    let (q, e1) = mem.alloc[f64](a, n)
    let (eta, e2) = mem.alloc[f64](a, n * nc)
    let (pr, e3) = mem.alloc[f64](a, n)
    let (b0, e4) = mem.alloc[f64](a, nc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret e1 }
    var qs = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { q[i] = wt[i] } else { q[i] = 1.0f64 }
        qs += q[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        q[i] = q[i] / qs
        i += 1usize
    }
    var c = 0usize
    while c < nc {
        var fr = 0.0f64
        i = 0usize
        while i < n {
            if lab[i] == c { fr += q[i] }
            i += 1usize
        }
        b0[c] = math.log[f64](fr)
        c += 1usize
    }
    var it = 0usize
    while it < 200usize {
        c = 0usize
        while c < nc {
            i = 0usize
            while i < n {
                eta[c * n + i] = b0[c]
                if off.len == n * nc { eta[c * n + i] += off[c * n + i] }
                i += 1usize
            }
            c += 1usize
        }
        c = 0usize
        while c < nc {
            mn_prob(eta, n, nc, c, pr)
            var g = 0.0f64
            var h = 0.0f64
            i = 0usize
            while i < n {
                var yy = 0.0f64
                if lab[i] == c { yy = 1.0f64 }
                g += q[i] * (yy - pr[i])
                h += q[i] * pr[i] * (1.0f64 - pr[i])
                i += 1usize
            }
            b0[c] += g / h
            i = 0usize
            while i < n {
                eta[c * n + i] += g / h
                i += 1usize
            }
            c += 1usize
        }
        it += 1usize
    }
    c = 0usize
    while c < nc {
        i = 0usize
        while i < n {
            eta[c * n + i] = b0[c]
            if off.len == n * nc { eta[c * n + i] += off[c * n + i] }
            i += 1usize
        }
        c += 1usize
    }
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    var lmax = 0.0f64
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += q[i] * x[j * n + i]
            i += 1usize
        }
        var vv = 0.0f64
        i = 0usize
        while i < n {
            vv += q[i] * (x[j * n + i] - m) * (x[j * n + i] - m)
            i += 1usize
        }
        var sj = 1.0f64
        if standardize { sj = math.sqrt[f64](vv) }
        var gn = 0.0f64
        var gm = 0.0f64
        c = 0usize
        while c < nc {
            mn_prob(eta, n, nc, c, pr)
            var gj = 0.0f64
            i = 0usize
            while i < n {
                var yy = 0.0f64
                if lab[i] == c { yy = 1.0f64 }
                gj += q[i] * (x[j * n + i] - m) * (yy - pr[i])
                i += 1usize
            }
            gj = gj / sj
            gn += gj * gj
            if math.abs[f64](gj) > gm { gm = math.abs[f64](gj) }
            c += 1usize
        }
        var gs = gm
        if grouped { gs = math.sqrt[f64](gn) }
        let vj = vf[j] * f64(p) / vs
        if vj > 0.0f64 {
            var al = alpha
            if al < 0.001f64 { al = 0.001f64 }
            let cv = gs / (al * vj)
            if cv > lmax { lmax = cv }
        }
        j += 1usize
    }
    var ratio = 1.0e-4f64
    if n < p { ratio = 1.0e-2f64 }
    var k = 0usize
    while k < nlambda {
        out[k] = lmax * math.pow[f64](ratio, f64(k) / f64(nlambda - 1usize))
        k += 1usize
    }
    ret ok
}

// the number of automatic lambdas glmnet reports for the multinomial family: the binomial stopping rule (from the fifth lambda, a gain of less than 1e-5 in the deviance ratio, or a ratio above 0.999)
fn multinomial_path_len(a: *mem.Arena, x: []const f64, lab: []const usize, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, nc: usize, alpha: f64, standardize: bool, grouped: bool, vf: []const f64, nlambda: usize) -> usize {
    let (lam, e1) = mem.alloc[f64](a, nlambda)
    let (coef, e2) = mem.alloc[f64](a, nlambda * nc * (p + 1usize))
    let (dev, e3) = mem.alloc[f64](a, nlambda)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    if multinomial_lambda_path(a, x, lab, wt, off, n, p, nc, alpha, standardize, grouped, vf, nlambda, lam) != ok { ret 0usize }
    var tl = 1.0e-9f64
    if grouped { tl = 1.0e-12f64 }
    if multinomial_tol(a, x, lab, wt, off, lo, up, n, p, nc, alpha, standardize, grouped, vf, lam, tl, true, coef, dev) != ok { ret 0usize }
    var k = 4usize
    while k < nlambda {
        if dev[k] - dev[k - 1usize] < 1.0e-5f64 { ret k + 1usize }
        if dev[k] > 0.999f64 { ret k + 1usize }
        k += 1usize
    }
    ret nlambda
}

// glmnet's `exclude`: the listed variables (excl[j] != 0, or none when excl is empty) are dropped before anything is computed, so the penalty factors are rescaled over the kept variables only and the automatic lambda sequence ignores them; xo and vo receive the kept columns and factors and kept their indices; returns how many were kept
fn keep_columns(x: []const f64, vf: []const f64, n: usize, p: usize, excl: []const f64, xo: []f64, vo: []f64, kept: []usize) -> usize {
    var q = 0usize
    var j = 0usize
    while j < p {
        if excl.len != p || excl[j] == 0.0f64 {
            var i = 0usize
            while i < n {
                xo[q * n + i] = x[j * n + i]
                i += 1usize
            }
            vo[q] = vf[j]
            kept[q] = j
            q += 1usize
        }
        j += 1usize
    }
    ret q
}

// the coefficient rows (intercept, then the nk kept slopes) of a fit on the kept variables, spread back over all p variables with zeros for the excluded ones; nl rows
fn scatter_coef(small: []const f64, kept: []const usize, nk: usize, p: usize, nl: usize, out: []f64) {
    var k = 0usize
    while k < nl {
        out[k * (p + 1usize)] = small[k * (nk + 1usize)]
        var j = 0usize
        while j < p {
            out[k * (p + 1usize) + 1usize + j] = 0.0f64
            j += 1usize
        }
        var q = 0usize
        while q < nk {
            out[k * (p + 1usize) + 1usize + kept[q]] = small[k * (nk + 1usize) + 1usize + q]
            q += 1usize
        }
        k += 1usize
    }
}

// cv.glmnet's last step from the per-fold raw measures: cvf[k * nfolds + f] is fold f's measure at lambda k, nfv[f] the fold's weight; cvm is the weighted mean over the folds and cvsd = sqrt(weighted variance / (nfolds - 1))
fn cv_finish(cvf: []const f64, nfv: []const f64, nl: usize, nfolds: usize, cvm: []f64, cvsd: []f64) {
    var tot = 0.0f64
    var f = 0usize
    while f < nfolds {
        tot += nfv[f]
        f += 1usize
    }
    var k = 0usize
    while k < nl {
        var mn = 0.0f64
        f = 0usize
        while f < nfolds {
            mn += nfv[f] * cvf[k * nfolds + f]
            f += 1usize
        }
        mn = mn / tot
        var vr = 0.0f64
        f = 0usize
        while f < nfolds {
            vr += nfv[f] * (cvf[k * nfolds + f] - mn) * (cvf[k * nfolds + f] - mn)
            f += 1usize
        }
        cvm[k] = mn
        cvsd[k] = math.sqrt[f64](vr / tot / f64(nfolds - 1usize))
        k += 1usize
    }
}

// lambda.min and lambda.1se for a measure that is to be maximised (the C-index, the AUC): the largest lambda whose cvm is the largest, and the largest lambda whose cvm is within one cvsd below it
fn cv_select_max(lambdas: []const f64, cvm: []const f64, cvsd: []const f64, out: []f64) {
    var best = cvm[0usize]
    var k = 1usize
    while k < lambdas.len {
        if cvm[k] > best { best = cvm[k] }
        k += 1usize
    }
    var lmin = 0.0f64 - 1.0e300f64
    var at = 0usize
    k = 0usize
    while k < lambdas.len {
        if cvm[k] >= best && lambdas[k] > lmin {
            lmin = lambdas[k]
            at = k
        }
        k += 1usize
    }
    let lim = best - cvsd[at]
    var l1 = 0.0f64 - 1.0e300f64
    k = 0usize
    while k < lambdas.len {
        if cvm[k] >= lim && lambdas[k] > l1 { l1 = lambdas[k] }
        k += 1usize
    }
    out[0usize] = lmin
    out[1usize] = l1
}



// glmnet's coxnet.deviance for the rows (weights w, the linear predictor eta, Breslow ties): twice the negative partial log-likelihood minus twice the sum over event times of d_k log d_k (d_k the weighted number of events tied there)
fn cox_deviance(a: *mem.Arena, time: []const f64, status: []const f64, w: []const f64, eta: []const f64) -> f64 {
    let n = time.len
    let (dq, e1) = mem.alloc[f64](a, n)
    let (ee, e2) = mem.alloc[f64](a, n)
    let (ss, e3) = mem.alloc[f64](a, n)
    let (ww, e4) = mem.alloc[f64](a, n)
    let (wr, e5) = mem.alloc[f64](a, n)
    let (ord, e6) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret 0.0f64 / 0.0f64 }
    var d0 = 0.0f64
    var i = 0usize
    while i < n {
        dq[i] = w[i] * status[i]
        ee[i] = w[i] * math.exp[f64](eta[i])
        d0 += dq[i] * eta[i]
        i += 1usize
    }
    cox_ord(time, ord)
    let lg = cox_quant(time, dq, ord, ee, ss, ww, wr)
    ret 2.0f64 * (lg - d0) - 2.0f64 * cox_dklog(time, dq, ord)
}

// Harrell's concordance as survival::concordance reports it for glmnet's C measure: over the pairs whose earlier time is an event (a tie in time counts when exactly one of the two is an event, the event being the earlier), a pair is concordant when the earlier subject has the larger predictor, tied predictors count one half
fn cox_cindex(time: []const f64, status: []const f64, pred: []const f64) -> f64 {
    let n = time.len
    var conc = 0.0f64
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if status[i] > 0.0f64 && (time[i] < time[j] || (time[i] == time[j] && status[j] == 0.0f64)) {
                tot += 1.0f64
                if pred[i] > pred[j] { conc += 1.0f64 }
                if pred[i] == pred[j] { conc += 0.5f64 }
            }
            j += 1usize
        }
        i += 1usize
    }
    ret conc / tot
}


// glmnet gives an excluded variable the penalty factor 1 and then rescales all p factors to sum to p, whereas the fit on the kept variables rescales over the kept ones only; the two agree once every lambda of the original problem is multiplied by this factor (a fit on the kept columns at lambda c is the fit glmnet reports at lambda), and the automatic sequence of the kept fit divided by it is glmnet's
fn exclude_scale(vf: []const f64, p: usize, excl: []const f64, nk: usize) -> f64 {
    var sall = 0.0f64
    var skept = 0.0f64
    var j = 0usize
    while j < p {
        if excl.len == p && excl[j] != 0.0f64 {
            sall += 1.0f64
        } else {
            sall += vf[j]
            skept += vf[j]
        }
        j += 1usize
    }
    ret (f64(p) / sall) / (f64(nk) / skept)
}

// glmnet's relax = TRUE, the relaxed fits: every distinct set of active variables along the path is refitted without a penalty (lambda 0) on those variables alone, and a lambda keeps its lasso coefficients when its set is empty or larger than n - 3.
// fam 2 gaussian, 0 binomial, 1 poisson, 3 Cox (y is then the time and st the status); coef (nl rows of the intercept and p slopes, a Cox fit with a zero intercept) is the lasso path, rcoef receives the relaxed rows
fn relax_path(a: *mem.Arena, fam: usize, x: []const f64, y: []const f64, st: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, coef: []const f64, nl: usize, rcoef: []f64) -> err {
    let (xk, e1) = mem.alloc[f64](a, n * p)
    let (vk, e2) = mem.alloc[f64](a, p)
    let (kept, e3) = mem.alloc[usize](a, p)
    let (sm, e4) = mem.alloc[f64](a, p + 1usize)
    let (zl, e5) = mem.alloc[f64](a, 1usize)
    let (first, e6) = mem.alloc[usize](a, nl)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    zl[0usize] = 0.0f64
    let none: []const f64 = zero
    let nodv: []f64 = zero
    var k = 0usize
    while k < nl {
        first[k] = k
        var q = 0usize
        while q < k {
            var same = true
            var j = 0usize
            while j < p {
                let a1 = coef[k * (p + 1usize) + 1usize + j] != 0.0f64
                let a2 = coef[q * (p + 1usize) + 1usize + j] != 0.0f64
                if a1 != a2 { same = false }
                j += 1usize
            }
            if same {
                first[k] = first[q]
                break
            }
            q += 1usize
        }
        var j = 0usize
        var nz = 0usize
        while j < p {
            if coef[k * (p + 1usize) + 1usize + j] != 0.0f64 { nz += 1usize }
            vk[j] = 1.0f64
            j += 1usize
        }
        var c = 0usize
        while c <= p {
            rcoef[k * (p + 1usize) + c] = coef[k * (p + 1usize) + c]
            c += 1usize
        }
        if nz > 0usize && nz + 3usize <= n {
            if first[k] < k {
                c = 0usize
                while c <= p {
                    rcoef[k * (p + 1usize) + c] = rcoef[first[k] * (p + 1usize) + c]
                    c += 1usize
                }
            } else {
                var ex = 0usize
                j = 0usize
                while j < p {
                    if coef[k * (p + 1usize) + 1usize + j] != 0.0f64 {
                        var i = 0usize
                        while i < n {
                            xk[ex * n + i] = x[j * n + i]
                            i += 1usize
                        }
                        kept[ex] = j
                        ex += 1usize
                    }
                    j += 1usize
                }
                var fe = ok
                if fam == 2usize {
                    let (ye, e7) = mem.alloc[f64](a, n)
                    if e7 != ok { ret e7 }
                    var ii = 0usize
                    while ii < n {
                        ye[ii] = y[ii]
                        if off.len == n { ye[ii] = y[ii] - off[ii] }
                        ii += 1usize
                    }
                    fe = gaussian(a, xk[0usize..n * ex], ye, wt, none, none, n, ex, 1.0f64, false, vk[0usize..ex], zl, sm)
                }
                if fam == 0usize || fam == 1usize { fe = glm_path_dev(a, fam, xk[0usize..n * ex], y, wt, off, none, none, n, ex, 1.0f64, false, vk[0usize..ex], zl, sm, nodv) }
                if fam == 3usize {
                    fe = cox(a, xk[0usize..n * ex], y, st, wt, off, none, none, n, ex, 1.0f64, false, vk[0usize..ex], zl, sm[1usize..ex + 1usize], nodv)
                    sm[0usize] = 0.0f64
                }
                if fe != ok { ret fe }
                rcoef[k * (p + 1usize)] = sm[0usize]
                j = 0usize
                while j < p {
                    rcoef[k * (p + 1usize) + 1usize + j] = 0.0f64
                    j += 1usize
                }
                var t = 0usize
                while t < ex {
                    rcoef[k * (p + 1usize) + 1usize + kept[t]] = sm[1usize + t]
                    t += 1usize
                }
            }
        }
        k += 1usize
    }
    ret ok
}

// predict(relaxed fit, gamma): the relaxed rows blended with the lasso rows, gamma times the lasso coefficients plus (1 - gamma) times the relaxed ones, gamma floored at 1e-5 (glmnet's epsilon)
fn relax_blend(coef: []const f64, rcoef: []const f64, gamma: f64, out: []f64) {
    var g = gamma
    if g < 1.0e-5f64 { g = 1.0e-5f64 }
    var q = 0usize
    while q < coef.len {
        if gamma >= 1.0f64 { out[q] = coef[q] } else { out[q] = g * coef[q] + (1.0f64 - g) * rcoef[q] }
        q += 1usize
    }
}

// predict(fit, newx, type = "link") for one coefficient row (the intercept, then p slopes) and an optional offset: the linear predictor of every row of the n by p column-major x
fn predict_link(x: []const f64, n: usize, p: usize, row: []const f64, off: []const f64, out: []f64) {
    var i = 0usize
    while i < n {
        var eta = row[0usize]
        if off.len == n { eta += off[i] }
        var j = 0usize
        while j < p {
            eta += x[j * n + i] * row[1usize + j]
            j += 1usize
        }
        out[i] = eta
        i += 1usize
    }
}

// predict(..., type = "response") from the link: fam 2 gaussian (the link itself), 0 binomial (the probability), 1 poisson and Cox (exp)
fn predict_response(fam: usize, link: []const f64, out: []f64) {
    var i = 0usize
    while i < link.len {
        if fam == 0usize { out[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - link[i])) }
        if fam == 1usize { out[i] = math.exp[f64](link[i]) }
        if fam == 2usize { out[i] = link[i] }
        i += 1usize
    }
}

// predict(binomial fit, type = "class"): the second level (1) when the link is positive, else the first (0)
fn predict_class(link: []const f64, out: []f64) {
    var i = 0usize
    while i < link.len {
        out[i] = 0.0f64
        if link[i] > 0.0f64 { out[i] = 1.0f64 }
        i += 1usize
    }
}

// predict for the multinomial family from nc coefficient rows (class c at c (p + 1)): kind 0 the link (n by nc, column-major), 1 the probabilities (softmax of the link), 2 the class with the largest link (0-based, ties to the first), written to out (n values)
fn predict_multinomial(x: []const f64, n: usize, p: usize, nc: usize, rows: []const f64, off: []const f64, kind: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var best = 0usize
        var mx = 0.0f64 - 1.0e300f64
        var c = 0usize
        while c < nc {
            var eta = rows[c * (p + 1usize)]
            if off.len == n * nc { eta += off[c * n + i] }
            var j = 0usize
            while j < p {
                eta += x[j * n + i] * rows[c * (p + 1usize) + 1usize + j]
                j += 1usize
            }
            if kind < 2usize { out[c * n + i] = eta }
            if eta > mx {
                mx = eta
                best = c
            }
            c += 1usize
        }
        if kind == 1usize {
            var sm = 0.0f64
            c = 0usize
            while c < nc {
                sm += math.exp[f64](out[c * n + i] - mx)
                c += 1usize
            }
            c = 0usize
            while c < nc {
                out[c * n + i] = math.exp[f64](out[c * n + i] - mx) / sm
                c += 1usize
            }
        }
        if kind == 2usize { out[i] = f64(best) }
        i += 1usize
    }
}

// predict(fit, type = "nonzero") for one coefficient row: how many of the p slopes are nonzero, and (for index >= 0) the 0-based position of the index-th one
fn nonzero_count(row: []const f64, p: usize) -> usize {
    var c = 0usize
    var j = 0usize
    while j < p {
        if row[1usize + j] != 0.0f64 { c += 1usize }
        j += 1usize
    }
    ret c
}

fn nonzero_at(row: []const f64, p: usize, which: usize) -> usize {
    var c = 0usize
    var j = 0usize
    while j < p {
        if row[1usize + j] != 0.0f64 {
            if c == which { ret j }
            c += 1usize
        }
        j += 1usize
    }
    ret p
}

// glmnet's lambda sequence for a chosen nlambda and lambda.min.ratio: lambda_max (the first value any of the *_lambda_path functions returns) times ratio^(k / (nlambda - 1)); the path may still stop early, which the *_path_len functions report for the defaults
fn lambda_seq(lmax: f64, ratio: f64, nlambda: usize, out: []f64) {
    var k = 0usize
    while k < nlambda {
        out[k] = lmax * math.pow[f64](ratio, f64(k) / f64(nlambda - 1usize))
        k += 1usize
    }
}

// glmnet's automatic lambda sequence for the gaussian family with observation weights (and, through y, an offset: pass y - offset): `lambda_path` with the weights normalised to sum 1 in the means, the standardisation and the gradient
fn lambda_path_w(a: *mem.Arena, x: []const f64, y: []const f64, wt: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize, out: []f64) -> err {
    let (q, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var qs = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { q[i] = wt[i] } else { q[i] = 1.0f64 }
        qs += q[i]
        i += 1usize
    }
    var yb = 0.0f64
    i = 0usize
    while i < n {
        q[i] = q[i] / qs
        yb += q[i] * y[i]
        i += 1usize
    }
    var vs = 0.0f64
    var j = 0usize
    while j < p {
        vs += vf[j]
        j += 1usize
    }
    var lmax = 0.0f64
    j = 0usize
    while j < p {
        var m = 0.0f64
        i = 0usize
        while i < n {
            m += q[i] * x[j * n + i]
            i += 1usize
        }
        var vv = 0.0f64
        var gj = 0.0f64
        i = 0usize
        while i < n {
            vv += q[i] * (x[j * n + i] - m) * (x[j * n + i] - m)
            gj += q[i] * (x[j * n + i] - m) * (y[i] - yb)
            i += 1usize
        }
        if standardize { gj = gj / math.sqrt[f64](vv) }
        let vj = vf[j] * f64(p) / vs
        if vj > 0.0f64 {
            var al = alpha
            if al < 0.001f64 { al = 0.001f64 }
            let c = math.abs[f64](gj) / (al * vj)
            if c > lmax { lmax = c }
        }
        j += 1usize
    }
    var ratio = 1.0e-4f64
    if n < p { ratio = 1.0e-2f64 }
    lambda_seq(lmax, ratio, nlambda, out)
    ret ok
}

// the number of automatic lambdas of the weighted gaussian family (y again already net of any offset): the stopping rule of `path_len` with weighted sums of squares
fn path_len_w(a: *mem.Arena, x: []const f64, y: []const f64, wt: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, nlambda: usize) -> usize {
    let (lam, e1) = mem.alloc[f64](a, nlambda)
    let (coef, e2) = mem.alloc[f64](a, nlambda * (p + 1usize))
    if e1 != ok || e2 != ok { ret 0usize }
    if lambda_path_w(a, x, y, wt, n, p, alpha, standardize, vf, nlambda, lam) != ok { ret 0usize }
    let none: []const f64 = zero
    if gaussian(a, x, y, wt, none, none, n, p, alpha, standardize, vf, lam, coef) != ok { ret 0usize }
    var qs = 0.0f64
    var i = 0usize
    while i < n {
        if wt.len == n { qs += wt[i] } else { qs += 1.0f64 }
        i += 1usize
    }
    var yb = 0.0f64
    i = 0usize
    while i < n {
        var qi = 1.0f64
        if wt.len == n { qi = wt[i] }
        yb += qi / qs * y[i]
        i += 1usize
    }
    var sst = 0.0f64
    i = 0usize
    while i < n {
        var qi = 1.0f64
        if wt.len == n { qi = wt[i] }
        sst += qi / qs * (y[i] - yb) * (y[i] - yb)
        i += 1usize
    }
    var prev = 0.0f64
    var k = 0usize
    while k < nlambda {
        var sse = 0.0f64
        i = 0usize
        while i < n {
            var f = coef[k * (p + 1usize)]
            var j = 0usize
            while j < p {
                f += x[j * n + i] * coef[k * (p + 1usize) + 1usize + j]
                j += 1usize
            }
            var qi = 1.0f64
            if wt.len == n { qi = wt[i] }
            sse += qi / qs * (y[i] - f) * (y[i] - f)
            i += 1usize
        }
        let rsq = 1.0f64 - sse / sst
        if k + 1usize >= 5usize {
            if rsq - prev < 1.0e-5f64 * rsq { ret k + 1usize }
            if rsq > 0.999f64 { ret k + 1usize }
        }
        prev = rsq
        k += 1usize
    }
    ret nlambda
}

// the coefficient rows (intercept first; a Cox fit gets a zero intercept) of the family at the lambdas given; fam 2 gaussian (an offset is taken off y), 0 binomial, 1 poisson, 3 Cox (y the time, st the status)
fn path_rows(a: *mem.Arena, fam: usize, x: []const f64, y: []const f64, st: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lams: []const f64, rows: []f64) -> err {
    let none: []const f64 = zero
    let nodv: []f64 = zero
    if fam == 2usize {
        let (ye, e1) = mem.alloc[f64](a, n)
        if e1 != ok { ret e1 }
        var i = 0usize
        while i < n {
            ye[i] = y[i]
            if off.len == n { ye[i] = y[i] - off[i] }
            i += 1usize
        }
        ret gaussian(a, x, ye, wt, none, none, n, p, alpha, standardize, vf, lams, rows)
    }
    if fam == 3usize {
        let (cx, e1) = mem.alloc[f64](a, lams.len * p)
        if e1 != ok { ret e1 }
        let ce = cox(a, x, y, st, wt, off, none, none, n, p, alpha, standardize, vf, lams, cx, nodv)
        if ce != ok { ret ce }
        var k = 0usize
        while k < lams.len {
            rows[k * (p + 1usize)] = 0.0f64
            var j = 0usize
            while j < p {
                rows[k * (p + 1usize) + 1usize + j] = cx[k * p + j]
                j += 1usize
            }
            k += 1usize
        }
        ret ok
    }
    ret glm_path_dev(a, fam, x, y, wt, off, none, none, n, p, alpha, standardize, vf, lams, rows, nodv)
}

// the lasso rows cl (and, when relax, the relaxed rows cr) of one cross-validation fold's fit at the lambdas given. With auto false the fold is fitted at those lambdas; with auto true (cv.glmnet's default) the fold finds its own automatic sequence from its training rows
// and the rows at the shared lambdas are read off by glmnet's linear interpolation; the relaxed rows are interpolated the same way
fn fold_rows(a: *mem.Arena, fam: usize, xt: []const f64, yt: []const f64, stt: []const f64, wtt: []const f64, offt: []const f64, m: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, auto: bool, relax: bool, cl: []f64, cr: []f64) -> err {
    let nl = lambdas.len
    let row = p + 1usize
    if !auto {
        let pe = path_rows(a, fam, xt, yt, stt, wtt, offt, m, p, alpha, standardize, vf, lambdas, cl)
        if pe != ok { ret pe }
        if relax { ret relax_path(a, fam, xt, yt, stt, wtt, offt, m, p, cl, nl, cr) }
        ret ok
    }
    let (lam, e1) = mem.alloc[f64](a, 100usize)
    let (r1, e2) = mem.alloc[f64](a, 100usize * row)
    let (r2, e3) = mem.alloc[f64](a, 100usize * row)
    let (ico, e4) = mem.alloc[f64](a, row)
    let (ye, e5) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e1 }
    let none: []const f64 = zero
    var len = 100usize
    var i = 0usize
    while i < m {
        ye[i] = yt[i]
        if fam == 2usize && offt.len == m { ye[i] = yt[i] - offt[i] }
        i += 1usize
    }
    if fam == 2usize {
        let le = lambda_path_w(a, xt, ye, wtt, m, p, alpha, standardize, vf, 100usize, lam)
        if le != ok { ret le }
        len = path_len_w(a, xt, ye, wtt, m, p, alpha, standardize, vf, 100usize)
    }
    if fam == 0usize || fam == 1usize {
        let le = glm_lambda_path(a, fam, xt, yt, wtt, offt, m, p, alpha, standardize, vf, 100usize, lam)
        if le != ok { ret le }
        len = glm_path_len(a, fam, xt, yt, wtt, offt, m, p, alpha, standardize, vf, 100usize)
    }
    if fam == 3usize {
        let le = cox_lambda_path(a, xt, yt, stt, wtt, offt, m, p, alpha, standardize, vf, 100usize, lam)
        if le != ok { ret le }
        len = cox_path_len(a, xt, yt, stt, wtt, offt, none, none, m, p, alpha, standardize, vf, 100usize)
    }
    let pe = path_rows(a, fam, xt, yt, stt, wtt, offt, m, p, alpha, standardize, vf, lam, r1)
    if pe != ok { ret pe }
    if relax {
        let re = relax_path(a, fam, xt, yt, stt, wtt, offt, m, p, r1[0usize..len * row], len, r2)
        if re != ok { ret re }
    }
    var k = 0usize
    while k < nl {
        coef_interp(lam[0usize..len], r1[0usize..len * row], p, lambdas[k], ico)
        var j = 0usize
        while j <= p {
            cl[k * row + j] = ico[j]
            j += 1usize
        }
        if relax {
            coef_interp(lam[0usize..len], r2[0usize..len * row], p, lambdas[k], ico)
            j = 0usize
            while j <= p {
                cr[k * row + j] = ico[j]
                j += 1usize
            }
        }
        k += 1usize
    }
    ret ok
}

// the area under the ROC curve of the observations idx (a mask foldid == f) with weights: pairs (a positive i, a negative j) weigh w_i w_j, ties count one half, as survival::concordance with the weights glmnet gives it
fn weighted_auc(y: []const f64, pr: []const f64, w: []const f64, foldid: []const usize, f: usize) -> f64 {
    var num = 0.0f64
    var den = 0.0f64
    var i = 0usize
    while i < y.len {
        if foldid[i] == f && y[i] == 1.0f64 {
            var j = 0usize
            while j < y.len {
                if foldid[j] == f && y[j] == 0.0f64 {
                    den += w[i] * w[j]
                    if pr[i] > pr[j] { num += w[i] * w[j] }
                    if pr[i] == pr[j] { num += 0.5f64 * w[i] * w[j] }
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    ret num / den
}

// Harrell's concordance with case weights as survival::concordance takes them: pairs weigh w_i w_j
fn cox_cindex_w(time: []const f64, status: []const f64, pred: []const f64, w: []const f64) -> f64 {
    let n = time.len
    var conc = 0.0f64
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            if status[i] > 0.0f64 && (time[i] < time[j] || (time[i] == time[j] && status[j] == 0.0f64)) {
                tot += w[i] * w[j]
                if pred[i] > pred[j] { conc += w[i] * w[j] }
                if pred[i] == pred[j] { conc += 0.5f64 * w[i] * w[j] }
            }
            j += 1usize
        }
        i += 1usize
    }
    ret conc / tot
}

// cv.glmnet for the gaussian (fam 2), binomial (0), poisson (1) and Cox (3) families, with user fold ids (0 .. nfolds - 1), observation weights wt and offsets off (either may be empty), and cv.glmnet's relax = TRUE (relax true: the measures are
// computed for each of the gammas, whose relaxed rows are gamma times the lasso rows plus 1 - gamma times the relaxed rows; without relax pass the single gamma 1). Measures: 0 deviance (the mean squared error for the gaussian), 1 misclassification, 2 mse, 3 mae, 4 auc (binomial), 5 the C-index (Cox; with measure 0 the Cox deviance is the grouped
// full-minus-training form). cvm and cvsd receive gammas.len * lambdas.len values, gamma-major. auto as in `fold_rows`
fn cv_engine(a: *mem.Arena, fam: usize, measure: usize, x: []const f64, y: []const f64, st: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, relax: bool, gammas: []const f64, cvm: []f64, cvsd: []f64) -> err {
    let nl = lambdas.len
    let row = p + 1usize
    let ng = gammas.len
    let (xt, e1) = mem.alloc[f64](a, n * p)
    let (yt, e2) = mem.alloc[f64](a, n)
    let (stt, e3) = mem.alloc[f64](a, n)
    let (wtt, e4) = mem.alloc[f64](a, n)
    let (ott, e5) = mem.alloc[f64](a, n)
    let (cl, e6) = mem.alloc[f64](a, nl * row)
    let (cr, e7) = mem.alloc[f64](a, nl * row)
    let (bl, e8) = mem.alloc[f64](a, nl * row)
    let (cvf, e9) = mem.alloc[f64](a, ng * nl * nfolds)
    let (nfv, e10) = mem.alloc[f64](a, nfolds)
    let (wall, e11) = mem.alloc[f64](a, n)
    let (eta, e12) = mem.alloc[f64](a, n)
    let (tt2, e13) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret e1 }
    var i = 0usize
    while i < n {
        wall[i] = 1.0f64
        if wt.len == n { wall[i] = wt[i] }
        i += 1usize
    }
    var f = 0usize
    while f < nfolds {
        var m = 0usize
        i = 0usize
        while i < n {
            if foldid[i] != f {
                var j = 0usize
                while j < p {
                    xt[j * n + m] = x[j * n + i]
                    j += 1usize
                }
                yt[m] = y[i]
                if st.len == n { stt[m] = st[i] }
                wtt[m] = wall[i]
                if off.len == n { ott[m] = off[i] }
                m += 1usize
            }
            i += 1usize
        }
        var j = 0usize
        while j < p {
            var q = 0usize
            while q < m {
                xt[j * m + q] = xt[j * n + q]
                q += 1usize
            }
            j += 1usize
        }
        let mark = mem.mark(a)
        let none: []const f64 = zero
        var stz = none
        if st.len == n { stz = stt[0usize..m] }
        var otz = none
        if off.len == n { otz = ott[0usize..m] }
        let fe = fold_rows(a, fam, xt[0usize..m * p], yt[0usize..m], stz, wtt[0usize..m], otz, m, p, alpha, standardize, vf, lambdas, auto, relax, cl, cr)
        if fe != ok { ret fe }
        var wf = 0.0f64
        i = 0usize
        while i < n {
            if foldid[i] == f { wf += wall[i] }
            i += 1usize
        }
        nfv[f] = wf
        var g = 0usize
        while g < ng {
            var k = 0usize
            while k < nl {
                // the rows blended for gamma g
                var gm = gammas[g]
                if gm < 1.0e-5f64 { gm = 1.0e-5f64 }
                var q = 0usize
                while q < row {
                    if relax && gammas[g] < 1.0f64 { bl[q] = gm * cl[k * row + q] + (1.0f64 - gm) * cr[k * row + q] } else { bl[q] = cl[k * row + q] }
                    q += 1usize
                }
                i = 0usize
                while i < n {
                    var lp = bl[0usize]
                    j = 0usize
                    while j < p {
                        lp += x[j * n + i] * bl[1usize + j]
                        j += 1usize
                    }
                    if off.len == n { lp += off[i] }
                    eta[i] = lp
                    i += 1usize
                }
                var acc = 0.0f64
                if fam == 3usize {
                    if measure == 0usize {
                        let dfull = cox_deviance(a, y, st, wall, eta)
                        var q3 = 0usize
                        i = 0usize
                        while i < n {
                            if foldid[i] != f {
                                tt2[q3] = eta[i]
                                q3 += 1usize
                            }
                            i += 1usize
                        }
                        let dtrain = cox_deviance(a, yt[0usize..q3], stt[0usize..q3], wtt[0usize..q3], tt2[0usize..q3])
                        acc = (dfull - dtrain) / wf
                    } else {
                        var cnt = 0usize
                        i = 0usize
                        while i < n {
                            if foldid[i] == f { cnt += 1usize }
                            i += 1usize
                        }
                        let (ft, e14) = mem.alloc[f64](a, cnt)
                        let (fs, e15) = mem.alloc[f64](a, cnt)
                        let (fp, e16) = mem.alloc[f64](a, cnt)
                        let (fw, e17) = mem.alloc[f64](a, cnt)
                        if e14 != ok || e15 != ok || e16 != ok || e17 != ok { ret e14 }
                        var q2 = 0usize
                        i = 0usize
                        while i < n {
                            if foldid[i] == f {
                                ft[q2] = y[i]
                                fs[q2] = st[i]
                                fp[q2] = eta[i]
                                fw[q2] = wall[i]
                                q2 += 1usize
                            }
                            i += 1usize
                        }
                        acc = cox_cindex_w(ft, fs, fp, fw)
                    }
                } else if fam == 0usize && measure == 4usize {
                    i = 0usize
                    while i < n {
                        var pp = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta[i]))
                        if pp < 1.0e-5f64 { pp = 1.0e-5f64 }
                        if pp > 1.0f64 - 1.0e-5f64 { pp = 1.0f64 - 1.0e-5f64 }
                        tt2[i] = pp
                        i += 1usize
                    }
                    acc = weighted_auc(y, tt2, wall, foldid, f)
                } else {
                    i = 0usize
                    while i < n {
                        if foldid[i] == f {
                            var v = 0.0f64
                            if fam == 2usize {
                                let r = y[i] - eta[i]
                                if measure == 3usize { v = math.abs[f64](r) } else { v = r * r }
                            }
                            if fam == 0usize {
                                var pp = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - eta[i]))
                                if measure == 1usize {
                                    if y[i] == 0.0f64 && pp > 0.5f64 { v = 1.0f64 }
                                    if y[i] == 1.0f64 && pp <= 0.5f64 { v = 1.0f64 }
                                }
                                if measure == 2usize { v = 2.0f64 * (y[i] - pp) * (y[i] - pp) }
                                if measure == 3usize { v = 2.0f64 * math.abs[f64](y[i] - pp) }
                                if measure == 0usize {
                                    if pp < 1.0e-5f64 { pp = 1.0e-5f64 }
                                    if pp > 1.0f64 - 1.0e-5f64 { pp = 1.0f64 - 1.0e-5f64 }
                                    v = 2.0f64 * (0.0f64 - y[i] * math.log[f64](pp) - (1.0f64 - y[i]) * math.log[f64](1.0f64 - pp))
                                }
                            }
                            if fam == 1usize {
                                let mu = math.exp[f64](eta[i])
                                if measure == 0usize {
                                    var devy = 0.0f64
                                    if y[i] > 0.0f64 { devy = y[i] * math.log[f64](y[i]) - y[i] }
                                    v = 2.0f64 * (devy - (y[i] * eta[i] - mu))
                                }
                                if measure == 2usize { v = (y[i] - mu) * (y[i] - mu) }
                                if measure == 3usize { v = math.abs[f64](y[i] - mu) }
                            }
                            acc += wall[i] * v
                        }
                        i += 1usize
                    }
                    acc = acc / wf
                }
                cvf[(g * nl + k) * nfolds + f] = acc
                k += 1usize
            }
            g += 1usize
        }
        mem.reset(a, mark)
        f += 1usize
    }
    var g = 0usize
    while g < ng {
        cv_finish(cvf[g * nl * nfolds..(g + 1usize) * nl * nfolds], nfv, nl, nfolds, cvm[g * nl..(g + 1usize) * nl], cvsd[g * nl..(g + 1usize) * nl])
        g += 1usize
    }
    ret ok
}

// the old per-family entry points, now one call of `cv_engine` with no weights, offsets or relax
fn cv_gaussian(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
    let none: []const f64 = zero
    let (g1, e1) = mem.alloc[f64](a, 1usize)
    if e1 != ok { ret e1 }
    g1[0usize] = 1.0f64
    ret cv_engine(a, 2usize, 0usize, x, y, none, none, none, n, p, alpha, standardize, vf, lambdas, foldid, nfolds, auto, false, g1, cvm, cvsd)
}

fn cv_binomial(a: *mem.Arena, measure: usize, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
    let none: []const f64 = zero
    let (g1, e1) = mem.alloc[f64](a, 1usize)
    if e1 != ok { ret e1 }
    g1[0usize] = 1.0f64
    ret cv_engine(a, 0usize, measure, x, y, none, none, none, n, p, alpha, standardize, vf, lambdas, foldid, nfolds, auto, false, g1, cvm, cvsd)
}

fn cv_poisson(a: *mem.Arena, measure: usize, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
    let none: []const f64 = zero
    let (g1, e1) = mem.alloc[f64](a, 1usize)
    if e1 != ok { ret e1 }
    g1[0usize] = 1.0f64
    ret cv_engine(a, 1usize, measure, x, y, none, none, none, n, p, alpha, standardize, vf, lambdas, foldid, nfolds, auto, false, g1, cvm, cvsd)
}

// the variables with a nonzero coefficient in any class at lambda k of a multi-class path (rows of nc blocks of the intercept and p slopes); the kept indices go to kept and the count is returned
fn active_set(coef: []const f64, k: usize, p: usize, nc: usize, kept: []usize) -> usize {
    let row = nc * (p + 1usize)
    var ex = 0usize
    var j = 0usize
    while j < p {
        var any = false
        var c = 0usize
        while c < nc {
            if coef[k * row + c * (p + 1usize) + 1usize + j] != 0.0f64 { any = true }
            c += 1usize
        }
        if any {
            kept[ex] = j
            ex += 1usize
        }
        j += 1usize
    }
    ret ex
}

// relax = TRUE for the multinomial (fam 4, lab the classes) and mgaussian (fam 5, ym the n by nc responses) families: each distinct active set (a variable counts when any class has it) is refitted without a penalty on those variables; coef and rcoef hold nl rows of nc blocks (intercept, p slopes)
// as `multinomial` and `mgaussian` fill them. The unpenalised multinomial fit is flat along adding one vector to every class's coefficients of a variable; glmnet's lambda 0 answer is the limit of the lasso, which puts the median class at zero, so it is fitted at a lambda of 1e-12 (an odd number of classes makes that unique)
fn relax_multi(a: *mem.Arena, fam: usize, x: []const f64, lab: []const usize, ym: []const f64, wt: []const f64, off: []const f64, n: usize, p: usize, nc: usize, coef: []const f64, nl: usize, rcoef: []f64) -> err {
    let row = nc * (p + 1usize)
    let (xk, e1) = mem.alloc[f64](a, n * p)
    let (vk, e2) = mem.alloc[f64](a, p)
    let (kept, e3) = mem.alloc[usize](a, p)
    let (sm, e4) = mem.alloc[f64](a, row)
    let (zl, e5) = mem.alloc[f64](a, 1usize)
    let (first, e6) = mem.alloc[usize](a, nl)
    let (dv, e7) = mem.alloc[f64](a, 1usize)
    let (kp2, e8) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret e1 }
    let none: []const f64 = zero
    var k = 0usize
    while k < nl {
        first[k] = k
        let nz = active_set(coef, k, p, nc, kept)
        var q = 0usize
        while q < k {
            let nq = active_set(coef, q, p, nc, kp2)
            var same = nq == nz
            var t = 0usize
            while t < nz && same {
                if kept[t] != kp2[t] { same = false }
                t += 1usize
            }
            if same {
                first[k] = first[q]
                break
            }
            q += 1usize
        }
        var c = 0usize
        while c < row {
            rcoef[k * row + c] = coef[k * row + c]
            c += 1usize
        }
        if nz > 0usize && nz + 3usize <= n {
            if first[k] < k {
                c = 0usize
                while c < row {
                    rcoef[k * row + c] = rcoef[first[k] * row + c]
                    c += 1usize
                }
            } else {
                var t = 0usize
                while t < nz {
                    var i = 0usize
                    while i < n {
                        xk[t * n + i] = x[kept[t] * n + i]
                        i += 1usize
                    }
                    vk[t] = 1.0f64
                    t += 1usize
                }
                var fe = ok
                zl[0usize] = 0.0f64
                if fam == 5usize { fe = mgaussian(a, xk[0usize..n * nz], ym, n, nz, nc, 1.0f64, false, vk[0usize..nz], zl, sm) }
                if fam == 4usize {
                    zl[0usize] = 1.0e-12f64
                    let nodv: []f64 = zero
                    fe = multinomial_tol(a, xk[0usize..n * nz], lab, wt, off, none, none, n, nz, nc, 1.0f64, false, false, vk[0usize..nz], zl, 1.0e-13f64, true, sm, nodv)
                }
                if fe != ok { ret fe }
                c = 0usize
                while c < nc {
                    rcoef[k * row + c * (p + 1usize)] = sm[c * (nz + 1usize)]
                    var j = 0usize
                    while j < p {
                        rcoef[k * row + c * (p + 1usize) + 1usize + j] = 0.0f64
                        j += 1usize
                    }
                    t = 0usize
                    while t < nz {
                        rcoef[k * row + c * (p + 1usize) + 1usize + kept[t]] = sm[c * (nz + 1usize) + 1usize + t]
                        t += 1usize
                    }
                    c += 1usize
                }
            }
        }
        k += 1usize
    }
    ret ok
}

// the lasso rows cl (and, when relax, the relaxed rows cr) of one multinomial cross-validation fold at the lambdas given, direct or (auto) from the fold's own automatic sequence by interpolation; rows of nc blocks of the intercept and p slopes
fn mn_fold_rows(a: *mem.Arena, xt: []const f64, lt: []const usize, wtt: []const f64, offt: []const f64, m: usize, p: usize, nc: usize, alpha: f64, standardize: bool, grouped: bool, vf: []const f64, lambdas: []const f64, auto: bool, relax: bool, cl: []f64, cr: []f64) -> err {
    let nl = lambdas.len
    let row = nc * (p + 1usize)
    let none: []const f64 = zero
    let nodv: []f64 = zero
    let nonu: []const usize = zero
    if !auto {
        let ge = multinomial(a, xt, lt, wtt, offt, none, none, m, p, nc, alpha, standardize, grouped, vf, lambdas, cl, nodv)
        if ge != ok { ret ge }
        if relax { ret relax_multi(a, 4usize, xt, lt, none, wtt, offt, m, p, nc, cl, nl, cr) }
        ret ok
    }
    let (lam, e7) = mem.alloc[f64](a, 100usize)
    let (cf, e8) = mem.alloc[f64](a, 100usize * row)
    let (rc, e9) = mem.alloc[f64](a, 100usize * row)
    let (dv, e10) = mem.alloc[f64](a, 100usize)
    let (ico, e11) = mem.alloc[f64](a, row)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret e7 }
    let le = multinomial_lambda_path(a, xt, lt, wtt, offt, m, p, nc, alpha, standardize, grouped, vf, 100usize, lam)
    if le != ok { ret le }
    let ge = multinomial_tol(a, xt, lt, wtt, offt, none, none, m, p, nc, alpha, standardize, grouped, vf, lam, 1.0e-9f64, true, cf, dv)
    if ge != ok { ret ge }
    var len = 100usize
    var kk = 4usize
    while kk < 100usize {
        if dv[kk] - dv[kk - 1usize] < 1.0e-5f64 || dv[kk] > 0.999f64 {
            len = kk + 1usize
            break
        }
        kk += 1usize
    }
    if relax {
        let re = relax_multi(a, 4usize, xt, lt, none, wtt, offt, m, p, nc, cf[0usize..len * row], len, rc)
        if re != ok { ret re }
    }
    kk = 0usize
    while kk < nl {
        coef_interp(lam[0usize..len], cf[0usize..len * row], row - 1usize, lambdas[kk], ico)
        var q = 0usize
        while q < row {
            cl[kk * row + q] = ico[q]
            q += 1usize
        }
        if relax {
            coef_interp(lam[0usize..len], rc[0usize..len * row], row - 1usize, lambdas[kk], ico)
            q = 0usize
            while q < row {
                cr[kk * row + q] = ico[q]
                q += 1usize
            }
        }
        kk += 1usize
    }
    ret ok
}

// cv.glmnet for the multinomial family (classes lab 0 .. nc - 1) with user fold ids, observation weights wt and offsets off (n by nc, class-major; either may be empty) and relax: as `cv_engine`, with measure 0 deviance (probabilities clipped to [1e-5, 1 - 1e-5]), 1 misclassification, 2 mse and 3 mae (summed over the classes)
fn cv_multinomial(a: *mem.Arena, measure: usize, x: []const f64, lab: []const usize, wt: []const f64, off: []const f64, n: usize, p: usize, nc: usize, alpha: f64, standardize: bool, grouped: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, relax: bool, gammas: []const f64, cvm: []f64, cvsd: []f64) -> err {
    let nl = lambdas.len
    let row = nc * (p + 1usize)
    let ng = gammas.len
    let (xt, e1) = mem.alloc[f64](a, n * p)
    let (lt, e2) = mem.alloc[usize](a, n)
    let (wtt, e3) = mem.alloc[f64](a, n)
    let (ott, e4) = mem.alloc[f64](a, n * nc)
    let (cl, e5) = mem.alloc[f64](a, nl * row)
    let (cr, e6) = mem.alloc[f64](a, nl * row)
    let (bl, e7) = mem.alloc[f64](a, nl * row)
    let (cvf, e8) = mem.alloc[f64](a, ng * nl * nfolds)
    let (nfv, e9) = mem.alloc[f64](a, nfolds)
    let (pe, e10) = mem.alloc[f64](a, nc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret e1 }
    let none: []const f64 = zero
    var f = 0usize
    while f < nfolds {
        var m = 0usize
        var i = 0usize
        while i < n {
            if foldid[i] != f {
                var j = 0usize
                while j < p {
                    xt[j * n + m] = x[j * n + i]
                    j += 1usize
                }
                lt[m] = lab[i]
                wtt[m] = 1.0f64
                if wt.len == n { wtt[m] = wt[i] }
                m += 1usize
            }
            i += 1usize
        }
        var j = 0usize
        while j < p {
            var q = 0usize
            while q < m {
                xt[j * m + q] = xt[j * n + q]
                q += 1usize
            }
            j += 1usize
        }
        var hasoff = false
        if off.len == n * nc { hasoff = true }
        if hasoff {
            var c = 0usize
            while c < nc {
                var mq = 0usize
                i = 0usize
                while i < n {
                    if foldid[i] != f {
                        ott[c * m + mq] = off[c * n + i]
                        mq += 1usize
                    }
                    i += 1usize
                }
                c += 1usize
            }
        }
        var wz = none
        if wt.len == n { wz = wtt[0usize..m] }
        var oz = none
        if hasoff { oz = ott[0usize..m * nc] }
        let mark = mem.mark(a)
        let fe = mn_fold_rows(a, xt[0usize..m * p], lt[0usize..m], wz, oz, m, p, nc, alpha, standardize, grouped, vf, lambdas, auto, relax, cl, cr)
        if fe != ok { ret fe }
        var wf = 0.0f64
        i = 0usize
        while i < n {
            if foldid[i] == f {
                if wt.len == n { wf += wt[i] } else { wf += 1.0f64 }
            }
            i += 1usize
        }
        nfv[f] = wf
        var g = 0usize
        while g < ng {
            var gm = gammas[g]
            if gm < 1.0e-5f64 { gm = 1.0e-5f64 }
            var k = 0usize
            while k < nl {
                var q = 0usize
                while q < row {
                    if relax && gammas[g] < 1.0f64 { bl[q] = gm * cl[k * row + q] + (1.0f64 - gm) * cr[k * row + q] } else { bl[q] = cl[k * row + q] }
                    q += 1usize
                }
                var acc = 0.0f64
                i = 0usize
                while i < n {
                    if foldid[i] == f {
                        var mxe = 0.0f64 - 1.0e300f64
                        var c = 0usize
                        while c < nc {
                            var eta = bl[c * (p + 1usize)]
                            j = 0usize
                            while j < p {
                                eta += x[j * n + i] * bl[c * (p + 1usize) + 1usize + j]
                                j += 1usize
                            }
                            if hasoff { eta += off[c * n + i] }
                            pe[c] = eta
                            if eta > mxe { mxe = eta }
                            c += 1usize
                        }
                        var sm = 0.0f64
                        c = 0usize
                        while c < nc {
                            pe[c] = math.exp[f64](pe[c] - mxe)
                            sm += pe[c]
                            c += 1usize
                        }
                        var best = 0usize
                        c = 0usize
                        while c < nc {
                            pe[c] = pe[c] / sm
                            if pe[c] > pe[best] { best = c }
                            c += 1usize
                        }
                        var v = 0.0f64
                        c = 0usize
                        while c < nc {
                            var yy = 0.0f64
                            if lab[i] == c { yy = 1.0f64 }
                            if measure == 0usize && yy > 0.0f64 {
                                var pc = pe[c]
                                if pc < 1.0e-5f64 { pc = 1.0e-5f64 }
                                if pc > 1.0f64 - 1.0e-5f64 { pc = 1.0f64 - 1.0e-5f64 }
                                v += 0.0f64 - 2.0f64 * math.log[f64](pc)
                            }
                            if measure == 2usize { v += (yy - pe[c]) * (yy - pe[c]) }
                            if measure == 3usize { v += math.abs[f64](yy - pe[c]) }
                            c += 1usize
                        }
                        if measure == 1usize && best != lab[i] { v = 1.0f64 }
                        var wi = 1.0f64
                        if wt.len == n { wi = wt[i] }
                        acc += wi * v
                    }
                    i += 1usize
                }
                cvf[(g * nl + k) * nfolds + f] = acc / wf
                k += 1usize
            }
            g += 1usize
        }
        mem.reset(a, mark)
        f += 1usize
    }
    var g = 0usize
    while g < ng {
        cv_finish(cvf[g * nl * nfolds..(g + 1usize) * nl * nfolds], nfv, nl, nfolds, cvm[g * nl..(g + 1usize) * nl], cvsd[g * nl..(g + 1usize) * nl])
        g += 1usize
    }
    ret ok
}

// cv.glmnet for the Cox family: the old entry point (measure 0 deviance, 1 C-index), now a call of `cv_engine`
fn cv_cox(a: *mem.Arena, measure: usize, x: []const f64, time: []const f64, status: []const f64, wt: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
    let none: []const f64 = zero
    let (g1, e1) = mem.alloc[f64](a, 1usize)
    if e1 != ok { ret e1 }
    g1[0usize] = 1.0f64
    var ms = 0usize
    if measure == 1usize { ms = 5usize }
    ret cv_engine(a, 3usize, ms, x, time, status, wt, none, n, p, alpha, standardize, vf, lambdas, foldid, nfolds, auto, false, g1, cvm, cvsd)
}

// cv.glmnet(relax = TRUE)'s choice of lambda.min and gamma.min: over every gamma and lambda the smallest cvm (the largest for the C-index and auc: pass maximize), the largest lambda among those tied, and among gammas tied at that lambda the largest; cvm is gamma-major as `cv_engine` fills it. out = (lambda.min, gamma.min)
fn cv_select_relax(lambdas: []const f64, gammas: []const f64, cvm: []const f64, maximize: bool, out: []f64) {
    let nl = lambdas.len
    var best = cvm[0usize]
    var q = 1usize
    while q < cvm.len {
        if maximize {
            if cvm[q] > best { best = cvm[q] }
        } else {
            if cvm[q] < best { best = cvm[q] }
        }
        q += 1usize
    }
    var lmin = 0.0f64 - 1.0e300f64
    q = 0usize
    while q < cvm.len {
        var hit = cvm[q] <= best
        if maximize { hit = cvm[q] >= best }
        if hit && lambdas[q % nl] > lmin { lmin = lambdas[q % nl] }
        q += 1usize
    }
    var gmin = 0.0f64
    var found = false
    q = 0usize
    while q < cvm.len {
        var hit = cvm[q] <= best
        if maximize { hit = cvm[q] >= best }
        if hit && lambdas[q % nl] == lmin && (!found || gammas[q / nl] > gmin) {
            gmin = gammas[q / nl]
            found = true
        }
        q += 1usize
    }
    out[0usize] = lmin
    out[1usize] = gmin
}
