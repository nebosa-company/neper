// R glmnet, the gaussian family: the elastic-net objective
// `(1 / 2n) sum (y - b0 - x b)^2 + lambda sum vf_j ((1 - alpha) / 2 b_j^2 + alpha |b_j|)` by cyclic coordinate
// descent run to a tight tolerance, with glmnet's conventions (y is scaled to unit variance inside, which makes the
// ridge part of the penalty `lambda (1 - alpha) / sd(y)`): columns standardised to unit variance (divisor n)
// inside when `standardize`, the penalty factors rescaled to sum to p, coefficients answered on the original scale
// and the intercept from the means. Answers the exact minimiser, which glmnet reaches to its `thresh` of 1e-7.
//
// Box constraints lower.limits / upper.limits (original-scale coefficients, empty for none) clamp each coordinate update, which is exact for a one-variable convex problem. Observation weights (normalised to sum 1, as glmnet does) enter the means, the standardisation and the loss; an empty slice means equal weights.
//
// Also here, each as the minimiser run to a tight tolerance (glmnet stops at its thresh of 1e-7, so its own coefficients sit a few 1e-5 to 3e-4 from these): the binomial and poisson families (weights, offsets, bounds), the multinomial family (ungrouped and grouped; weights, offsets, bounds),
// the Cox family (Breslow ties; weights, offsets, bounds), mgaussian, the automatic lambda sequence and its length for every family, `exclude`, cv.glmnet for every family (with the lambda sequence given, or with the default one where each fold finds its own and is read at the full fit's lambdas by
// interpolation), relax = TRUE, and the predict types.
//
// Not here: Efron ties and strata or start-stop responses for Cox, relax for the multinomial and mgaussian families, cv.glmnet with relax = TRUE, observation weights and offsets inside cv.glmnet, bounds for mgaussian.

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

// the coefficients of one cv.glmnet fold fit at the lambdas given (fam 2 gaussian, 0 binomial, 1 poisson; coef as `gaussian` fills it). With auto false the fold is fitted at those lambdas, as cv.glmnet does when the caller supplies a sequence. With auto true, as cv.glmnet does by default, each fold finds its own automatic
// sequence from its own training rows and the coefficients at the shared lambdas are read off by glmnet's linear interpolation (predict with s = lambda)
fn fold_coefs(a: *mem.Arena, fam: usize, xt: []const f64, yt: []const f64, m: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, auto: bool, coef: []f64) -> err {
    let none: []const f64 = zero
    if !auto {
        if fam == 2usize { ret gaussian(a, xt, yt, none, none, none, m, p, alpha, standardize, vf, lambdas, coef) }
        ret glm_path(a, fam, xt, yt, none, none, m, p, alpha, standardize, vf, lambdas, coef)
    }
    let (lam, e1) = mem.alloc[f64](a, 100usize)
    let (cf, e2) = mem.alloc[f64](a, 100usize * (p + 1usize))
    let (ico, e3) = mem.alloc[f64](a, p + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret e1 }
    var len = 0usize
    if fam == 2usize {
        let le = lambda_path(a, xt, yt, m, p, alpha, standardize, vf, 100usize, lam)
        if le != ok { ret le }
        let ge = gaussian(a, xt, yt, none, none, none, m, p, alpha, standardize, vf, lam, cf)
        if ge != ok { ret ge }
        len = path_len(a, xt, yt, m, p, alpha, standardize, vf, 100usize)
    } else {
        let le = glm_lambda_path(a, fam, xt, yt, none, none, m, p, alpha, standardize, vf, 100usize, lam)
        if le != ok { ret le }
        let ge = glm_path(a, fam, xt, yt, none, none, m, p, alpha, standardize, vf, lam, cf)
        if ge != ok { ret ge }
        len = glm_path_len(a, fam, xt, yt, none, none, m, p, alpha, standardize, vf, 100usize)
    }
    var k = 0usize
    while k < lambdas.len {
        coef_interp(lam[0usize..len], cf[0usize..len * (p + 1usize)], p, lambdas[k], ico)
        var j = 0usize
        while j <= p {
            coef[k * (p + 1usize) + j] = ico[j]
            j += 1usize
        }
        k += 1usize
    }
    ret ok
}

// cv.glmnet for the gaussian family with user fold ids (0 .. nfolds - 1) over the given lambda sequence: each fold is refitted on the other observations, cvm[k] is the mean squared prediction error over all observations
// and cvsd[k] = sqrt(sum_f n_f (cv_f - cvm)^2 / n / (nfolds - 1)) with cv_f the fold's mean squared error
fn cv_gaussian(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
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
        let mark = mem.mark(a)
        let ge = fold_coefs(a, 2usize, xt[0usize..m * p], yt[0usize..m], m, p, alpha, standardize, vf, lambdas, auto, coef)
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
fn cv_binomial(a: *mem.Arena, measure: usize, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
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
        let mark = mem.mark(a)
        let ge = fold_coefs(a, 0usize, xt[0usize..m * p], yt[0usize..m], m, p, alpha, standardize, vf, lambdas, auto, coef)
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
fn cv_poisson(a: *mem.Arena, measure: usize, x: []const f64, y: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
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
        let mark = mem.mark(a)
        let ge = fold_coefs(a, 1usize, xt[0usize..m * p], yt[0usize..m], m, p, alpha, standardize, vf, lambdas, auto, coef)
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
    let r0 = 0.0f64 - cox_quant(time, dq, ord, ee, ss, w, wr)
    var d0 = 0.0f64
    i = 0usize
    while i < n {
        d0 += dq[i] * ff[i]
        i += 1usize
    }
    let risk0 = d0 + r0
    let rr = 0.0f64 - (cox_dklog(time, dq, ord) + risk0)
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
            let lg = cox_quant(time, dq, ord, ee, ss, w, wr)
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
        let lgk = cox_quant(time, dq, ord, ee, ss, w, wr)
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
    let lg0 = cox_quant(time, dq, ord, ee, ss, w, wr)
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
    let (lam, e1) = mem.alloc[f64](a, nlambda)
    let (coef, e2) = mem.alloc[f64](a, nlambda * p)
    let (dev, e3) = mem.alloc[f64](a, nlambda)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    if cox_lambda_path(a, x, time, status, wt, off, n, p, alpha, standardize, vf, nlambda, lam) != ok { ret 0usize }
    if cox(a, x, time, status, wt, off, lo, up, n, p, alpha, standardize, vf, lam, coef, dev) != ok { ret 0usize }
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
    ret multinomial_tol(a, x, lab, wt, off, lo, up, n, p, nc, alpha, standardize, grouped, vf, lambdas, 1.0e-13f64, coef, dev)
}

// as `multinomial`, run until no coefficient moves by more than tol in a pass (glmnet's own thresh leaves errors near 1e-7, so a cross-validation that is compared with it needs no more than 1e-9)
fn multinomial_tol(a: *mem.Arena, x: []const f64, lab: []const usize, wt: []const f64, off: []const f64, lo: []const f64, up: []const f64, n: usize, p: usize, nc: usize, alpha: f64, standardize: bool, grouped: bool, vf: []const f64, lambdas: []const f64, tol: f64, coef: []f64, dev: []f64) -> err {
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
    if e14 != ok { ret e14 }
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
                if lo.len != p {
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
                // grouped: one pass over the intercepts and the variables, each against the bound 1/2 of the Hessian; the probabilities of every class are formed once per update
                var cq = 0.0f64
                i = 0usize
                while i < n {
                    cq += q[i]
                    i += 1usize
                }
                mn_probs(eta, n, nc, pm)
                c = 0usize
                while c < nc {
                    var g0 = 0.0f64
                    i = 0usize
                    while i < n {
                        var yy = 0.0f64
                        if lab[i] == c { yy = 1.0f64 }
                        g0 += q[i] * (yy - pm[c * n + i])
                        i += 1usize
                    }
                    bo[c] = g0 / (0.5f64 * cq)
                    c += 1usize
                }
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
                    var hj = 0.0f64
                    i = 0usize
                    while i < n {
                        hj += 0.5f64 * q[i] * xs[j * n + i] * xs[j * n + i]
                        i += 1usize
                    }
                    mn_probs(eta, n, nc, pm)
                    var zn = 0.0f64
                    c = 0usize
                    while c < nc {
                        var gj = 0.0f64
                        i = 0usize
                        while i < n {
                            var yy = 0.0f64
                            if lab[i] == c { yy = 1.0f64 }
                            gj += q[i] * xs[j * n + i] * (yy - pm[c * n + i])
                            i += 1usize
                        }
                        z[c] = hj * b[c * p + j] + gj
                        zn += z[c] * z[c]
                        c += 1usize
                    }
                    zn = math.sqrt[f64](zn)
                    var shrink = 0.0f64
                    if zn > pf[j] * lam * alpha { shrink = 1.0f64 - pf[j] * lam * alpha / zn }
                    c = 0usize
                    while c < nc {
                        bo[c] = shrink * z[c] / (hj + pf[j] * lam * (1.0f64 - alpha)) - b[c * p + j]
                        c += 1usize
                    }
                    c = 0usize
                    while c < nc {
                        if bo[c] != 0.0f64 {
                            b[c * p + j] += bo[c]
                            if math.abs[f64](bo[c]) > change { change = math.abs[f64](bo[c]) }
                            i = 0usize
                            while i < n {
                                eta[c * n + i] += bo[c] * xs[j * n + i]
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
                    coef[((k - 1usize) * nc + c) * (p + 1usize) + 1usize + j] = b[c * p + j] / sc[j]
                    a0 -= b[c * p + j] / sc[j] * mx[j]
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
    if multinomial_tol(a, x, lab, wt, off, lo, up, n, p, nc, alpha, standardize, grouped, vf, lam, 1.0e-9f64, coef, dev) != ok { ret 0usize }
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

// cv.glmnet for the multinomial family (classes lab 0 .. nc - 1) with user fold ids; measure 0 deviance (probabilities clipped to [1e-5, 1 - 1e-5]), 1 misclassification, 2 mse (summed over the classes), 3 mae (summed over the classes). auto as in `fold_coefs`
fn cv_multinomial(a: *mem.Arena, measure: usize, x: []const f64, lab: []const usize, n: usize, p: usize, nc: usize, alpha: f64, standardize: bool, grouped: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
    let nl = lambdas.len
    let row = nc * (p + 1usize)
    let (xt, e1) = mem.alloc[f64](a, n * p)
    let (lt, e2) = mem.alloc[usize](a, n)
    let (coef, e3) = mem.alloc[f64](a, nl * row)
    let (cvf, e4) = mem.alloc[f64](a, nl * nfolds)
    let (nfv, e5) = mem.alloc[f64](a, nfolds)
    let (pe, e6) = mem.alloc[f64](a, nc)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
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
        if !auto {
            let ge = multinomial(a, xt[0usize..m * p], lt[0usize..m], none, none, none, none, m, p, nc, alpha, standardize, grouped, vf, lambdas, coef, none_dev(a))
            if ge != ok { ret ge }
        } else {
            let (lam, e7) = mem.alloc[f64](a, 100usize)
            let (cf, e8) = mem.alloc[f64](a, 100usize * row)
            let (dv, e9) = mem.alloc[f64](a, 100usize)
            let (ico, e10) = mem.alloc[f64](a, row)
            if e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret e7 }
            let le = multinomial_lambda_path(a, xt[0usize..m * p], lt[0usize..m], none, none, m, p, nc, alpha, standardize, grouped, vf, 100usize, lam)
            if le != ok { ret le }
            let ge = multinomial_tol(a, xt[0usize..m * p], lt[0usize..m], none, none, none, none, m, p, nc, alpha, standardize, grouped, vf, lam, 1.0e-9f64, cf, dv)
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
            kk = 0usize
            while kk < nl {
                coef_interp(lam[0usize..len], cf[0usize..len * row], row - 1usize, lambdas[kk], ico)
                var q = 0usize
                while q < row {
                    coef[kk * row + q] = ico[q]
                    q += 1usize
                }
                kk += 1usize
            }
        }
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
                    var mxe = 0.0f64 - 1.0e300f64
                    var c = 0usize
                    while c < nc {
                        var eta = coef[k * row + c * (p + 1usize)]
                        j = 0usize
                        while j < p {
                            eta += x[j * n + i] * coef[k * row + c * (p + 1usize) + 1usize + j]
                            j += 1usize
                        }
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
                    c = 0usize
                    while c < nc {
                        var yy = 0.0f64
                        if lab[i] == c { yy = 1.0f64 }
                        if measure == 0usize && yy > 0.0f64 {
                            var pc = pe[c]
                            if pc < 1.0e-5f64 { pc = 1.0e-5f64 }
                            if pc > 1.0f64 - 1.0e-5f64 { pc = 1.0f64 - 1.0e-5f64 }
                            cvf[k * nfolds + f] += 0.0f64 - 2.0f64 * math.log[f64](pc)
                        }
                        if measure == 2usize { cvf[k * nfolds + f] += (yy - pe[c]) * (yy - pe[c]) }
                        if measure == 3usize { cvf[k * nfolds + f] += math.abs[f64](yy - pe[c]) }
                        c += 1usize
                    }
                    if measure == 1usize && best != lab[i] { cvf[k * nfolds + f] += 1.0f64 }
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
    cv_finish(cvf, nfv, nl, nfolds, cvm, cvsd)
    ret ok
}

fn none_dev(a: *mem.Arena) -> []f64 {
    let nd: []f64 = zero
    ret nd
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

// cv.glmnet for the Cox family with user fold ids; measure 0 the partial-likelihood deviance (each fold: the deviance of the full data minus that of the other folds, at the fold's coefficients, divided by the fold's weight, which is cv.glmnet's grouped form), 1 the C-index. wt may be empty (the C-index ignores it). auto as in `fold_coefs`
fn cv_cox(a: *mem.Arena, measure: usize, x: []const f64, time: []const f64, status: []const f64, wt: []const f64, n: usize, p: usize, alpha: f64, standardize: bool, vf: []const f64, lambdas: []const f64, foldid: []const usize, nfolds: usize, auto: bool, cvm: []f64, cvsd: []f64) -> err {
    let nl = lambdas.len
    let (xt, e1) = mem.alloc[f64](a, n * p)
    let (tt, e2) = mem.alloc[f64](a, n)
    let (st, e3) = mem.alloc[f64](a, n)
    let (wtt, e4) = mem.alloc[f64](a, n)
    let (coef, e5) = mem.alloc[f64](a, nl * (p + 1usize))
    let (cvf, e6) = mem.alloc[f64](a, nl * nfolds)
    let (nfv, e7) = mem.alloc[f64](a, nfolds)
    let (eta, e8) = mem.alloc[f64](a, n)
    let (wall, e9) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret e1 }
    var i = 0usize
    while i < n {
        if wt.len == n { wall[i] = wt[i] } else { wall[i] = 1.0f64 }
        i += 1usize
    }
    let none: []const f64 = zero
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
                tt[m] = time[i]
                st[m] = status[i]
                wtt[m] = wall[i]
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
        let dvn: []f64 = zero
        if !auto {
            let (cf0, e10) = mem.alloc[f64](a, nl * p)
            if e10 != ok { ret e10 }
            let ge = cox(a, xt[0usize..m * p], tt[0usize..m], st[0usize..m], wtt[0usize..m], none, none, none, m, p, alpha, standardize, vf, lambdas, cf0, dvn)
            if ge != ok { ret ge }
            var k0 = 0usize
            while k0 < nl {
                coef[k0 * (p + 1usize)] = 0.0f64
                j = 0usize
                while j < p {
                    coef[k0 * (p + 1usize) + 1usize + j] = cf0[k0 * p + j]
                    j += 1usize
                }
                k0 += 1usize
            }
        } else {
            let (lam, e10) = mem.alloc[f64](a, 100usize)
            let (cf1, e11) = mem.alloc[f64](a, 100usize * p)
            let (cf, e12) = mem.alloc[f64](a, 100usize * (p + 1usize))
            let (ico, e13) = mem.alloc[f64](a, p + 1usize)
            if e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret e10 }
            let le = cox_lambda_path(a, xt[0usize..m * p], tt[0usize..m], st[0usize..m], wtt[0usize..m], none, m, p, alpha, standardize, vf, 100usize, lam)
            if le != ok { ret le }
            let ge = cox(a, xt[0usize..m * p], tt[0usize..m], st[0usize..m], wtt[0usize..m], none, none, none, m, p, alpha, standardize, vf, lam, cf1, dvn)
            if ge != ok { ret ge }
            let len = cox_path_len(a, xt[0usize..m * p], tt[0usize..m], st[0usize..m], wtt[0usize..m], none, none, none, m, p, alpha, standardize, vf, 100usize)
            var k1 = 0usize
            while k1 < len {
                cf[k1 * (p + 1usize)] = 0.0f64
                j = 0usize
                while j < p {
                    cf[k1 * (p + 1usize) + 1usize + j] = cf1[k1 * p + j]
                    j += 1usize
                }
                k1 += 1usize
            }
            k1 = 0usize
            while k1 < nl {
                coef_interp(lam[0usize..len], cf[0usize..len * (p + 1usize)], p, lambdas[k1], ico)
                j = 0usize
                while j <= p {
                    coef[k1 * (p + 1usize) + j] = ico[j]
                    j += 1usize
                }
                k1 += 1usize
            }
        }
        var wf = 0.0f64
        var cnt = 0usize
        i = 0usize
        while i < n {
            if foldid[i] == f {
                wf += wall[i]
                cnt += 1usize
            }
            i += 1usize
        }
        nfv[f] = wf
        let (ft, e14) = mem.alloc[f64](a, cnt)
        let (fs, e15) = mem.alloc[f64](a, cnt)
        let (fw, e16) = mem.alloc[f64](a, cnt)
        let (fe, e17) = mem.alloc[f64](a, cnt)
        if e14 != ok || e15 != ok || e16 != ok || e17 != ok { ret e14 }
        var q2 = 0usize
        i = 0usize
        while i < n {
            if foldid[i] == f {
                ft[q2] = time[i]
                fs[q2] = status[i]
                fw[q2] = wall[i]
                q2 += 1usize
            }
            i += 1usize
        }
        var k = 0usize
        while k < nl {
            i = 0usize
            while i < n {
                var lp = 0.0f64
                j = 0usize
                while j < p {
                    lp += x[j * n + i] * coef[k * (p + 1usize) + 1usize + j]
                    j += 1usize
                }
                eta[i] = lp
                i += 1usize
            }
            if measure == 0usize {
                let dfull = cox_deviance(a, time, status, wall, eta)
                var q3 = 0usize
                i = 0usize
                while i < n {
                    if foldid[i] != f {
                        tt[q3] = time[i]
                        st[q3] = status[i]
                        wtt[q3] = wall[i]
                        xt[q3] = eta[i]
                        q3 += 1usize
                    }
                    i += 1usize
                }
                let dtrain = cox_deviance(a, tt[0usize..q3], st[0usize..q3], wtt[0usize..q3], xt[0usize..q3])
                cvf[k * nfolds + f] = (dfull - dtrain) / wf
            } else {
                q2 = 0usize
                i = 0usize
                while i < n {
                    if foldid[i] == f {
                        fe[q2] = eta[i]
                        q2 += 1usize
                    }
                    i += 1usize
                }
                cvf[k * nfolds + f] = cox_cindex(ft, fs, fe)
            }
            k += 1usize
        }
        mem.reset(a, mark)
        f += 1usize
    }
    cv_finish(cvf, nfv, nl, nfolds, cvm, cvsd)
    ret ok
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
                if fam == 2usize { fe = gaussian(a, xk[0usize..n * ex], y, wt, none, none, n, ex, 1.0f64, false, vk[0usize..ex], zl, sm) }
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
