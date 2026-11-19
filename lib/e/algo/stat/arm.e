// R arm: logit and invlogit, se.coef of a linear model, and binned.resids (the binned-residual table behind binnedplot).
//
// rescale (the numeric core of standardize) is here. Not here: sim, discrete, corrplot data and the model refit of standardize.

use e.algo.stat.carlmtest as ols
use e.algo.stat.desctools as dt
use e.algo.stat.gparot as gp
use e.math
use e.math.dist as dist
use e.mem

fn logit(p: f64) -> f64 { ret math.log[f64](p / (1.0f64 - p)) }

fn invlogit(x: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x)) }

// se.coef(lm): sqrt(diag(sigma^2 (X'X)^-1)) with sigma^2 = RSS / (n - p), into out (p values); x is n by p row-major
fn se_coef(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, out: []f64) -> err {
    let (f, e) = ols.ols(a, x, y, n, p)
    if e != ok { ret e }
    var rss = 0.0f64
    var i = 0usize
    while i < n {
        rss += f.resid[i] * f.resid[i]
        i += 1usize
    }
    let s2 = rss / f64(n - p)
    i = 0usize
    while i < p {
        out[i] = math.sqrt[f64](s2 * f.xtx_inv[i * p + i])
        i += 1usize
    }
    ret ok
}

// binned.resids(x, y, nclass)$binned: rows of (xbar, ybar, n, x.lo, x.hi, 2se) into out (at most nclass rows of 6); returns the number of bins
fn binned_resids(a: *mem.Arena, x: []const f64, y: []const f64, nclass0: usize, out: []f64) -> usize {
    let n = x.len
    let (s, e) = dt.sorted_copy(a, x)
    if e != ok { ret 0usize }
    var nclass = nclass0
    var i = 1usize
    while i < nclass {
        if n * i / nclass == 0usize { nclass = 1usize }
        i += 1usize
    }
    let inf = 1.0f64 / 0.0f64
    let (br, e2) = mem.alloc[f64](a, nclass + 1usize)
    if e2 != ok { ret 0usize }
    var nb = 0usize
    br[0usize] = 0.0f64 - inf
    nb = 1usize
    if nclass > 1usize {
        var q = 1usize
        while q < nclass {
            let bi = n * q / nclass
            var lo = s[bi - 1usize]
            let hi = s[bi]
            if lo == hi {
                if lo == s[0usize] {
                    lo = 0.0f64 - inf
                } else {
                    var m = 0.0f64 - inf
                    var t = 0usize
                    while t < n {
                        if x[t] < lo && x[t] > m { m = x[t] }
                        t += 1usize
                    }
                    lo = m
                }
            }
            let b = (lo + hi) / 2.0f64
            if b != br[nb - 1usize] {
                br[nb] = b
                nb += 1usize
            }
            q += 1usize
        }
    } else {
        let b = (s[0usize] + s[n - 1usize]) / 2.0f64
        br[nb] = b
        nb += 1usize
    }
    // the last break is +Inf; bins are (br[b], br[b + 1]]
    let bins = nb
    var b = 0usize
    while b < bins {
        var cnt = 0.0f64
        var sx = 0.0f64
        var sy = 0.0f64
        var xlo = inf
        var xhi = 0.0f64 - inf
        var t = 0usize
        while t < n {
            let above = x[t] > br[b]
            var inside = above
            if b + 1usize < bins && x[t] > br[b + 1usize] { inside = false }
            if inside {
                cnt += 1.0f64
                sx += x[t]
                sy += y[t]
                if x[t] < xlo { xlo = x[t] }
                if x[t] > xhi { xhi = x[t] }
            }
            t += 1usize
        }
        let ybar = sy / cnt
        var sd = 0.0f64
        if cnt > 1.0f64 {
            var ss = 0.0f64
            t = 0usize
            while t < n {
                let above = x[t] > br[b]
                var inside = above
                if b + 1usize < bins && x[t] > br[b + 1usize] { inside = false }
                if inside { ss += (y[t] - ybar) * (y[t] - ybar) }
                t += 1usize
            }
            sd = math.sqrt[f64](ss / (cnt - 1.0f64))
        }
        out[b * 6usize] = sx / cnt
        out[b * 6usize + 1usize] = ybar
        out[b * 6usize + 2usize] = cnt
        out[b * 6usize + 3usize] = xlo
        out[b * 6usize + 4usize] = xhi
        out[b * 6usize + 5usize] = 2.0f64 * sd / math.sqrt[f64](cnt)
        b += 1usize
    }
    ret bins
}

// rescale(x, binary.inputs): a two-valued x by mode (0 "center", 1 "0/1", 2 "-0.5,0.5", 3 "full"), anything else (x - mean) / (2 sd); n values in, n out
fn rescale(x: []const f64, n: usize, mode: usize, out: []f64) {
    var lo = x[0usize]
    var hi = x[0usize]
    var sum = 0.0f64
    var i = 0usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        sum += x[i]
        i += 1usize
    }
    let mean = sum / f64(n)
    var ss = 0.0f64
    var two = true
    i = 0usize
    while i < n {
        ss += (x[i] - mean) * (x[i] - mean)
        if x[i] != lo && x[i] != hi { two = false }
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / f64(n - 1usize))
    i = 0usize
    while i < n {
        var v = (x[i] - mean) / (2.0f64 * sd)
        if two && hi != lo {
            if mode == 0usize { v = x[i] - mean }
            if mode == 1usize { v = (x[i] - lo) / (hi - lo) }
            if mode == 2usize { v = x[i] - 0.5f64 }
        }
        out[i] = v
        i += 1usize
    }
}

// standardize(lm(y ~ x)): the model refitted on the rescaled predictors (x is n by q row-major without the intercept; each column by `rescale` with the "center" rule for two-valued inputs);
// out receives the q + 1 coefficients, the intercept first
fn standardize_lm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, q: usize, out: []f64) -> err {
    let (d, e1) = mem.alloc[f64](a, n * (q + 1usize))
    let (col, e2) = mem.alloc[f64](a, n)
    let (sc, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        d[i * (q + 1usize)] = 1.0f64
        i += 1usize
    }
    var c = 0usize
    while c < q {
        i = 0usize
        while i < n {
            col[i] = x[i * q + c]
            i += 1usize
        }
        rescale(col, n, 0usize, sc)
        i = 0usize
        while i < n {
            d[i * (q + 1usize) + 1usize + c] = sc[i]
            i += 1usize
        }
        c += 1usize
    }
    let (f, e) = ols.ols(a, d, y, n, q + 1usize)
    if e != ok { ret e }
    var k = 0usize
    while k <= q {
        out[k] = f.beta[k]
        k += 1usize
    }
    ret ok
}

// the deviance residual of one observation (gaussian, binomial or poisson)
fn dev_resid(family: usize, y: f64, mu: f64) -> f64 {
    if family == 0usize { ret (y - mu) * (y - mu) }
    if family == 1usize || family == 3usize || family == 4usize {
        var d = 0.0f64
        if y > 0.0f64 { d += y * math.log[f64](y / mu) }
        if y < 1.0f64 { d += (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
        ret 2.0f64 * d
    }
    var d = 0.0f64
    if y > 0.0f64 { d = y * math.log[f64](y / mu) }
    ret 2.0f64 * (d - (y - mu))
}

// bayesglm with t priors (prior_df, Inf for normal; prior_scale; 10 and df 1 for the intercept in column 0; prior mean 0; scaled = TRUE): arm's EM-style IRLS, replicated step by step
// so that the iteration at which it stops is the same. family 0 gaussian, 1 binomial (logit), 2 poisson (log); x is n by k row-major with the constant in column 0. coef receives the
// coefficients and the answer is the number of iterations (0 on failure).
fn bayesglm(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, k: usize, family: usize, prior_mean: []const f64, prior_df: []const f64, prior_scale: []const f64, coef: []f64) -> usize {
    let nf = f64(n)
    let (ps, e1) = mem.alloc[f64](a, k)
    let (ps0, e2) = mem.alloc[f64](a, k)
    let (psd, e3) = mem.alloc[f64](a, k)
    let (eta, e4) = mem.alloc[f64](a, n)
    let (mu, e5) = mem.alloc[f64](a, n)
    let (zz, e6) = mem.alloc[f64](a, n)
    let (ww, e7) = mem.alloc[f64](a, n)
    let (am, e8) = mem.alloc[f64](a, k * k)
    let (bv, e9) = mem.alloc[f64](a, k)
    let (hat, e10) = mem.alloc[f64](a, k)
    let (cm, e11) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret 0usize }
    var ybar = 0.0f64
    var i = 0usize
    while i < n {
        ybar += y[i]
        i += 1usize
    }
    ybar = ybar / nf
    var yv = 0.0f64
    i = 0usize
    while i < n {
        yv += (y[i] - ybar) * (y[i] - ybar)
        i += 1usize
    }
    yv = yv / (nf - 1.0f64)
    let ysd = math.sqrt[f64](yv)
    var j = 0usize
    while j < k {
        ps[j] = prior_scale[j]
        if family == 0usize { ps[j] = ps[j] * 2.0f64 * ysd }
        ps0[j] = ps[j]
        j += 1usize
    }
    j = 0usize
    while j < k {
        // the number of distinct values of column j decides its scale: two values the range, more than two twice the sd
        var lo = x[j]
        var hi = x[j]
        var mean = 0.0f64
        i = 0usize
        while i < n {
            let v = x[i * k + j]
            if v < lo { lo = v }
            if v > hi { hi = v }
            mean += v
            i += 1usize
        }
        mean = mean / nf
        cm[j] = mean
        var distinct = 0usize
        i = 0usize
        while i < n && distinct < 3usize {
            var seen = false
            var q = 0usize
            while q < i {
                if x[q * k + j] == x[i * k + j] { seen = true }
                q += 1usize
            }
            if !seen { distinct += 1usize }
            i += 1usize
        }
        var xs = 1.0f64
        if distinct == 2usize { xs = hi - lo }
        if distinct > 2usize {
            var vv = 0.0f64
            i = 0usize
            while i < n {
                vv += (x[i * k + j] - mean) * (x[i * k + j] - mean)
                i += 1usize
            }
            xs = 2.0f64 * math.sqrt[f64](vv / (nf - 1.0f64))
        }
        ps[j] = ps[j] / xs
        psd[j] = ps[j]
        j += 1usize
    }
    i = 0usize
    while i < n {
        var m0 = y[i]
        if family == 1usize || family == 3usize || family == 4usize { m0 = (y[i] + 0.5f64) / 2.0f64 }
        if family == 2usize { m0 = y[i] + 0.1f64 }
        mu[i] = m0
        eta[i] = m0
        if family == 1usize { eta[i] = math.log[f64](m0 / (1.0f64 - m0)) }
        if family == 3usize { eta[i] = dist.qnorm(m0, 0.0f64, 1.0f64, true, false) }
        if family == 4usize { eta[i] = math.log[f64](0.0f64 - math.log[f64](1.0f64 - m0)) }
        if family == 2usize { eta[i] = math.log[f64](m0) }
        i += 1usize
    }
    var disp = yv / 10000.0f64
    if family != 0usize { disp = 1.0f64 }
    var dispold = disp
    var devold = 0.0f64
    i = 0usize
    while i < n {
        devold += dev_resid(family, y[i], mu[i])
        i += 1usize
    }
    var iter = 1usize
    while iter <= 25usize {
        i = 0usize
        while i < n {
            var me = 1.0f64
            var vr = 1.0f64
            if family == 1usize {
                me = mu[i] * (1.0f64 - mu[i])
                vr = me
            }
            if family == 3usize {
                me = dist.dnorm(eta[i], 0.0f64, 1.0f64, false)
                if me < 2.220446049250313e-16f64 { me = 2.220446049250313e-16f64 }
                vr = mu[i] * (1.0f64 - mu[i])
            }
            if family == 4usize {
                me = math.exp[f64](eta[i]) * math.exp[f64](0.0f64 - math.exp[f64](eta[i]))
                if me < 2.220446049250313e-16f64 { me = 2.220446049250313e-16f64 }
                vr = mu[i] * (1.0f64 - mu[i])
            }
            if family == 2usize {
                me = mu[i]
                vr = mu[i]
            }
            zz[i] = eta[i] + (y[i] - mu[i]) / me
            ww[i] = math.sqrt[f64](me * me / vr)
            i += 1usize
        }
        // the normal equations of the weighted least squares augmented by the k prior rows: the identity with row 0 replaced by the column means (intercept and scaled);
        // the prior mean is 0, so the prior rows add nothing to the right-hand side
        var r = 0usize
        while r < k {
            var c = 0usize
            while c < k {
                var v = 0.0f64
                i = 0usize
                while i < n {
                    v += ww[i] * ww[i] * x[i * k + r] * x[i * k + c]
                    i += 1usize
                }
                var pr = 0.0f64
                var j2 = 0usize
                while j2 < k {
                    let wj = math.sqrt[f64](disp) / psd[j2]
                    var vr0 = 0.0f64
                    var vc0 = 0.0f64
                    if j2 == 0usize {
                        vr0 = cm[r]
                        vc0 = cm[c]
                    } else {
                        if r == j2 { vr0 = 1.0f64 }
                        if c == j2 { vc0 = 1.0f64 }
                    }
                    pr += wj * wj * vr0 * vc0
                    j2 += 1usize
                }
                am[r * k + c] = v + pr
                c += 1usize
            }
            var t = 0.0f64
            i = 0usize
            while i < n {
                t += ww[i] * ww[i] * x[i * k + r] * zz[i]
                i += 1usize
            }
            var j3 = 0usize
            while j3 < k {
                let wj3 = math.sqrt[f64](disp) / psd[j3]
                var vr3 = 0.0f64
                if j3 == 0usize { vr3 = cm[r] } else {
                    if r == j3 { vr3 = 1.0f64 }
                }
                t += wj3 * wj3 * vr3 * prior_mean[j3]
                j3 += 1usize
            }
            bv[r] = t
            r += 1usize
        }
        let (inv, ie) = gp.invert(a, am, k)
        if ie != ok { ret 0usize }
        r = 0usize
        while r < k {
            var v = 0.0f64
            var c = 0usize
            while c < k {
                v += inv[r * k + c] * bv[c]
                c += 1usize
            }
            hat[r] = v
            r += 1usize
        }
        if family == 0usize {
            j = 0usize
            while j < k {
                ps[j] = ps0[j]
                j += 1usize
            }
        }
        j = 0usize
        while j < k {
            let dfj = prior_df[j]
            if dfj == math.inf64() { psd[j] = ps[j] } else { psd[j] = math.sqrt[f64](((hat[j] - prior_mean[j]) * (hat[j] - prior_mean[j]) + inv[j * k + j] * disp + dfj * ps[j] * ps[j]) / (1.0f64 + dfj)) }
            coef[j] = hat[j]
            j += 1usize
        }
        var dev = 0.0f64
        i = 0usize
        while i < n {
            var e = 0.0f64
            j = 0usize
            while j < k {
                e += x[i * k + j] * hat[j]
                j += 1usize
            }
            eta[i] = e
            if family == 0usize { mu[i] = e }
            if family == 1usize { mu[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - e)) }
            if family == 2usize { mu[i] = math.exp[f64](e) }
            if family == 3usize {
                var ec = e
                if ec < -8.125890664701906f64 { ec = -8.125890664701906f64 }
                if ec > 8.125890664701906f64 { ec = 8.125890664701906f64 }
                mu[i] = dist.pnorm(ec, 0.0f64, 1.0f64, true, false)
            }
            if family == 4usize {
                var mc4 = 1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](e))
                if mc4 < 2.220446049250313e-16f64 { mc4 = 2.220446049250313e-16f64 }
                if mc4 > 1.0f64 - 2.220446049250313e-16f64 { mc4 = 1.0f64 - 2.220446049250313e-16f64 }
                mu[i] = mc4
            }
            dev += dev_resid(family, y[i], mu[i])
            i += 1usize
        }
        if family == 0usize {
            var mse = 0.0f64
            var unc = 0.0f64
            i = 0usize
            while i < n {
                var e = 0.0f64
                j = 0usize
                while j < k {
                    e += x[i * k + j] * hat[j]
                    j += 1usize
                }
                let rr = ww[i] * (zz[i] - e)
                mse += rr * rr
                var q = 0.0f64
                j = 0usize
                while j < k {
                    var xv = 0.0f64
                    var c = 0usize
                    while c < k {
                        xv += x[i * k + c] * inv[c * k + j]
                        c += 1usize
                    }
                    q += xv * x[i * k + j]
                    j += 1usize
                }
                unc += q
                i += 1usize
            }
            disp = mse / nf + unc / nf * disp
        }
        if iter > 1usize && math.abs[f64](dev - devold) / (0.1f64 + math.abs[f64](dev)) < 1.0e-8f64 && math.abs[f64](disp - dispold) / (0.1f64 + math.abs[f64](disp)) < 1.0e-8f64 { ret iter }
        devold = dev
        dispold = disp
        iter += 1usize
    }
    ret 25usize
}
