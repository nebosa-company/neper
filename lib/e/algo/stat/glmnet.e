// R glmnet, the gaussian family: the elastic-net objective
// `(1 / 2n) sum (y - b0 - x b)^2 + lambda sum vf_j ((1 - alpha) / 2 b_j^2 + alpha |b_j|)` by cyclic coordinate
// descent run to a tight tolerance, with glmnet's conventions (y is scaled to unit variance inside, which makes the
// ridge part of the penalty `lambda (1 - alpha) / sd(y)`): columns standardised to unit variance (divisor n)
// inside when `standardize`, the penalty factors rescaled to sum to p, coefficients answered on the original scale
// and the intercept from the means. Answers the exact minimiser, which glmnet reaches to its `thresh` of 1e-7.
//
// Box constraints lower.limits / upper.limits (original-scale coefficients, empty for none) clamp each coordinate update, which is exact for a one-variable convex problem. Observation weights (normalised to sum 1, as glmnet does) enter the means, the standardisation and the loss; an empty slice means equal weights.
//
// Not here: other families, offsets, bounds, cv.glmnet, relax, predict.

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
                    let nb = soft(zj, lam * alpha * pf[j]) / (cj + lam * (1.0f64 - alpha) * pf[j])
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

// cv.glmnet for the gaussian family with user fold ids (0 .. nfolds - 1) over the given lambda sequence: each fold is refitted on the other observations, cvm[k] is the mean squared prediction error over all observations
// and cvsd[k] = sqrt(sum_f n_f (cv_f - cvm)^2 / n / (nfolds - 1)) with cv_f the fold's mean squared error
fn cv_gaussian(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, cvm: []f64, cvsd: []f64) -> err {
    let nl = lambdas.len
    let (xt, e1) = mem.alloc[f64](a, n * p)
    let (yt, e2) = mem.alloc[f64](a, n)
    let (coef, e3) = mem.alloc[f64](a, nl * (p + 1usize))
    let (cvf, e4) = mem.alloc[f64](a, nl * nfolds)
    let (nfv, e5) = mem.alloc[f64](a, nfolds)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e1 }
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
                yt[m] = y[i]
                m += 1usize
            }
            i += 1usize
        }
        // column-major with leading dimension m: repack
        var j = 0usize
        while j < p {
            var q = 0usize
            while q < m {
                xt[j * m + q] = xt[j * n + q]
                q += 1usize
            }
            j += 1usize
        }
        let none: []const f64 = zero
        let mark = mem.mark(a)
        let ge = gaussian(a, xt[0usize..m * p], yt[0usize..m], none, none, none, m, p, alpha, standardize, vf, lambdas, coef)
        if ge != ok { ret ge }
        var cnt = 0.0f64
        var k = 0usize
        while k < nl {
            cvf[k * nfolds + f] = 0.0f64
            k += 1usize
        }
        i = 0usize
        while i < n {
            if foldid[i] == f {
                cnt += 1.0f64
                k = 0usize
                while k < nl {
                    var pr = coef[k * (p + 1usize)]
                    j = 0usize
                    while j < p {
                        pr += x[j * n + i] * coef[k * (p + 1usize) + 1usize + j]
                        j += 1usize
                    }
                    cvf[k * nfolds + f] += (y[i] - pr) * (y[i] - pr)
                    k += 1usize
                }
            }
            i += 1usize
        }
        nfv[f] = cnt
        k = 0usize
        while k < nl {
            cvf[k * nfolds + f] = cvf[k * nfolds + f] / cnt
            k += 1usize
        }
        mem.reset(a, mark)
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
        mn = mn / f64(n)
        var vr = 0.0f64
        f = 0usize
        while f < nfolds {
            vr += nfv[f] * (cvf[k * nfolds + f] - mn) * (cvf[k * nfolds + f] - mn)
            f += 1usize
        }
        cvm[k] = mn
        cvsd[k] = math.sqrt[f64](vr / f64(n) / f64(nfolds - 1usize))
        k += 1usize
    }
    ret ok
}

// cv.glmnet for the binomial family (y in {0, 1}) with user fold ids; measure 0 deviance, 1 misclassification, 2 mse, 3 mae (the last two counted over both outcomes, so twice the plain error as cv.glmnet reports them). The deviance loss: the fitted probabilities clipped to [1e-5, 1 - 1e-5], the per-observation deviance 2 (-y log p - (1 - y) log(1 - p)),
// averaged within each fold and then over folds by size, cvsd as in `cv_gaussian`
fn cv_binomial(a: *mem.Arena, measure: usize, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, cvm: []f64, cvsd: []f64) -> err {
    let nl = lambdas.len
    let (xt, e1) = mem.alloc[f64](a, n * p)
    let (yt, e2) = mem.alloc[f64](a, n)
    let (coef, e3) = mem.alloc[f64](a, nl * (p + 1usize))
    let (cvf, e4) = mem.alloc[f64](a, nl * nfolds)
    let (nfv, e5) = mem.alloc[f64](a, nfolds)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e1 }
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
                yt[m] = y[i]
                m += 1usize
            }
            i += 1usize
        }
        // column-major with leading dimension m: repack
        var j = 0usize
        while j < p {
            var q = 0usize
            while q < m {
                xt[j * m + q] = xt[j * n + q]
                q += 1usize
            }
            j += 1usize
        }
        let none: []const f64 = zero
        let mark = mem.mark(a)
        let ge = glm_path(a, 0usize, xt[0usize..m * p], yt[0usize..m], none, none, m, p, alpha, standardize, vf, lambdas, coef)
        if ge != ok { ret ge }
        var cnt = 0.0f64
        var k = 0usize
        while k < nl {
            cvf[k * nfolds + f] = 0.0f64
            k += 1usize
        }
        i = 0usize
        while i < n {
            if foldid[i] == f {
                cnt += 1.0f64
                k = 0usize
                while k < nl {
                    var pr = coef[k * (p + 1usize)]
                    j = 0usize
                    while j < p {
                        pr += x[j * n + i] * coef[k * (p + 1usize) + 1usize + j]
                        j += 1usize
                    }
                    var pp = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - pr))
                    if pp < 1.0e-5f64 { pp = 1.0e-5f64 }
                    if pp > 1.0f64 - 1.0e-5f64 { pp = 1.0f64 - 1.0e-5f64 }
                    if measure == 0usize { cvf[k * nfolds + f] += 2.0f64 * (0.0f64 - y[i] * math.log[f64](pp) - (1.0f64 - y[i]) * math.log[f64](1.0f64 - pp)) }
                    if measure == 1usize {
                        if y[i] == 0.0f64 && pp > 0.5f64 { cvf[k * nfolds + f] += 1.0f64 }
                        if y[i] == 1.0f64 && pp <= 0.5f64 { cvf[k * nfolds + f] += 1.0f64 }
                    }
                    if measure == 2usize { cvf[k * nfolds + f] += 2.0f64 * (y[i] - pp) * (y[i] - pp) }
                    if measure == 3usize { cvf[k * nfolds + f] += 2.0f64 * math.abs[f64](y[i] - pp) }
                    k += 1usize
                }
            }
            i += 1usize
        }
        if measure == 4usize {
            // the area under the ROC curve of the fold's fitted probabilities (ties counting half), stored times the fold size so the division below returns it
            k = 0usize
            while k < nl {
                var wins = 0.0f64
                var n1 = 0.0f64
                var n0 = 0.0f64
                var i1 = 0usize
                while i1 < n {
                    if foldid[i1] == f && y[i1] == 1.0f64 {
                        n1 += 1.0f64
                        var p1 = coef[k * (p + 1usize)]
                        j = 0usize
                        while j < p {
                            p1 += x[j * n + i1] * coef[k * (p + 1usize) + 1usize + j]
                            j += 1usize
                        }
                        var i0 = 0usize
                        while i0 < n {
                            if foldid[i0] == f && y[i0] == 0.0f64 {
                                var p0 = coef[k * (p + 1usize)]
                                j = 0usize
                                while j < p {
                                    p0 += x[j * n + i0] * coef[k * (p + 1usize) + 1usize + j]
                                    j += 1usize
                                }
                                var q1 = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - p1))
                                var q0 = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - p0))
                                if q1 < 1.0e-5f64 { q1 = 1.0e-5f64 }
                                if q1 > 1.0f64 - 1.0e-5f64 { q1 = 1.0f64 - 1.0e-5f64 }
                                if q0 < 1.0e-5f64 { q0 = 1.0e-5f64 }
                                if q0 > 1.0f64 - 1.0e-5f64 { q0 = 1.0f64 - 1.0e-5f64 }
                                if q1 > q0 { wins += 1.0f64 }
                                if q1 == q0 { wins += 0.5f64 }
                            }
                            i0 += 1usize
                        }
                    } else if foldid[i1] == f {
                        n0 += 1.0f64
                    }
                    i1 += 1usize
                }
                cvf[k * nfolds + f] = wins / (n1 * n0) * cnt
                k += 1usize
            }
        }
        nfv[f] = cnt
        k = 0usize
        while k < nl {
            cvf[k * nfolds + f] = cvf[k * nfolds + f] / cnt
            k += 1usize
        }
        mem.reset(a, mark)
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
        mn = mn / f64(n)
        var vr = 0.0f64
        f = 0usize
        while f < nfolds {
            vr += nfv[f] * (cvf[k * nfolds + f] - mn) * (cvf[k * nfolds + f] - mn)
            f += 1usize
        }
        cvm[k] = mn
        cvsd[k] = math.sqrt[f64](vr / f64(n) / f64(nfolds - 1usize))
        k += 1usize
    }
    ret ok
}

// cv.glmnet for the poisson family with user fold ids; measure 0 deviance 2 (y log y - y - (y eta - exp(eta))), 2 mse and 3 mae on the response scale exp(eta)
fn cv_poisson(a: *mem.Arena, measure: usize, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, cvm: []f64, cvsd: []f64) -> err {
    let nl = lambdas.len
    let (xt, e1) = mem.alloc[f64](a, n * p)
    let (yt, e2) = mem.alloc[f64](a, n)
    let (coef, e3) = mem.alloc[f64](a, nl * (p + 1usize))
    let (cvf, e4) = mem.alloc[f64](a, nl * nfolds)
    let (nfv, e5) = mem.alloc[f64](a, nfolds)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret e1 }
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
                yt[m] = y[i]
                m += 1usize
            }
            i += 1usize
        }
        // column-major with leading dimension m: repack
        var j = 0usize
        while j < p {
            var q = 0usize
            while q < m {
                xt[j * m + q] = xt[j * n + q]
                q += 1usize
            }
            j += 1usize
        }
        let none: []const f64 = zero
        let mark = mem.mark(a)
        let ge = glm_path(a, 1usize, xt[0usize..m * p], yt[0usize..m], none, none, m, p, alpha, standardize, vf, lambdas, coef)
        if ge != ok { ret ge }
        var cnt = 0.0f64
        var k = 0usize
        while k < nl {
            cvf[k * nfolds + f] = 0.0f64
            k += 1usize
        }
        i = 0usize
        while i < n {
            if foldid[i] == f {
                cnt += 1.0f64
                k = 0usize
                while k < nl {
                    var pr = coef[k * (p + 1usize)]
                    j = 0usize
                    while j < p {
                        pr += x[j * n + i] * coef[k * (p + 1usize) + 1usize + j]
                        j += 1usize
                    }
                    let mu = math.exp[f64](pr)
                    if measure == 0usize {
                        var devy = 0.0f64
                        if y[i] > 0.0f64 { devy = y[i] * math.log[f64](y[i]) - y[i] }
                        cvf[k * nfolds + f] += 2.0f64 * (devy - (y[i] * pr - mu))
                    }
                    if measure == 2usize { cvf[k * nfolds + f] += (y[i] - mu) * (y[i] - mu) }
                    if measure == 3usize { cvf[k * nfolds + f] += math.abs[f64](y[i] - mu) }
                    k += 1usize
                }
            }
            i += 1usize
        }
        nfv[f] = cnt
        k = 0usize
        while k < nl {
            cvf[k * nfolds + f] = cvf[k * nfolds + f] / cnt
            k += 1usize
        }
        mem.reset(a, mark)
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
        mn = mn / f64(n)
        var vr = 0.0f64
        f = 0usize
        while f < nfolds {
            vr += nfv[f] * (cvf[k * nfolds + f] - mn) * (cvf[k * nfolds + f] - mn)
            f += 1usize
        }
        cvm[k] = mn
        cvsd[k] = math.sqrt[f64](vr / f64(n) / f64(nfolds - 1usize))
        k += 1usize
    }
    ret ok
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
    let nf = f64(n)
    let (xs, e1) = mem.alloc[f64](a, n * p)
    let (sc, e2) = mem.alloc[f64](a, p)
    let (mx, e3) = mem.alloc[f64](a, p)
    let (pf, e4) = mem.alloc[f64](a, p)
    let (b, e5) = mem.alloc[f64](a, p * m)
    let (r, e6) = mem.alloc[f64](a, n * m)
    let (ybar, e7) = mem.alloc[f64](a, m)
    let (z, e8) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret e1 }
    var q = 0usize
    while q < m {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += y[q * n + i]
            i += 1usize
        }
        ybar[q] = s / nf
        q += 1usize
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
        var i = 0usize
        while i < n {
            mm += x[j * n + i]
            i += 1usize
        }
        mm = mm / nf
        var v = 0.0f64
        i = 0usize
        while i < n {
            v += (x[j * n + i] - mm) * (x[j * n + i] - mm)
            i += 1usize
        }
        var s = 1.0f64
        if standardize { s = math.sqrt[f64](v / nf) }
        sc[j] = s
        mx[j] = mm
        i = 0usize
        while i < n {
            xs[j * n + i] = (x[j * n + i] - mm) / s
            i += 1usize
        }
        pf[j] = vf[j] * f64(p) / vs
        q = 0usize
        while q < m {
            b[q * p + j] = 0.0f64
            q += 1usize
        }
        j += 1usize
    }
    var k = 0usize
    while k < lambdas.len {
        let lam = lambdas[k]
        q = 0usize
        while q < m {
            var i = 0usize
            while i < n {
                var f = 0.0f64
                j = 0usize
                while j < p {
                    f += xs[j * n + i] * b[q * p + j]
                    j += 1usize
                }
                r[q * n + i] = y[q * n + i] - ybar[q] - f
                i += 1usize
            }
            q += 1usize
        }
        var sweep = 0usize
        while sweep < 100000usize {
            var dmax = 0.0f64
            j = 0usize
            while j < p {
                var cj = 0.0f64
                var i = 0usize
                while i < n {
                    cj += xs[j * n + i] * xs[j * n + i]
                    i += 1usize
                }
                cj = cj / nf
                var zn = 0.0f64
                q = 0usize
                while q < m {
                    var xr = 0.0f64
                    i = 0usize
                    while i < n {
                        xr += xs[j * n + i] * r[q * n + i]
                        i += 1usize
                    }
                    z[q] = xr / nf + cj * b[q * p + j]
                    zn += z[q] * z[q]
                    q += 1usize
                }
                zn = math.sqrt[f64](zn)
                var shrink = 0.0f64
                if zn > lam * alpha * pf[j] { shrink = 1.0f64 - lam * alpha * pf[j] / zn }
                q = 0usize
                while q < m {
                    let nb = shrink * z[q] / (cj + lam * (1.0f64 - alpha) * pf[j])
                    let d = nb - b[q * p + j]
                    if d != 0.0f64 {
                        i = 0usize
                        while i < n {
                            r[q * n + i] -= d * xs[j * n + i]
                            i += 1usize
                        }
                        b[q * p + j] = nb
                        if math.abs[f64](d) * math.sqrt[f64](cj) > dmax { dmax = math.abs[f64](d) * math.sqrt[f64](cj) }
                    }
                    q += 1usize
                }
                j += 1usize
            }
            if dmax < 1.0e-14f64 { break }
            sweep += 1usize
        }
        q = 0usize
        while q < m {
            var b0 = ybar[q]
            j = 0usize
            while j < p {
                coef[(k * m + q) * (p + 1usize) + 1usize + j] = b[q * p + j] / sc[j]
                b0 -= b[q * p + j] / sc[j] * mx[j]
                j += 1usize
            }
            coef[(k * m + q) * (p + 1usize)] = b0
            q += 1usize
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
