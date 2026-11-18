// The EM fit of the R package flexmix for a mixture of Gaussian linear regressions (FLXMRglm with the gaussian family, the default multinomial prior and the
// "auto" classification, which is the weighted EM). The start is a given cluster vector (flexmix's cluster argument, codes 1..k): the initial posteriors are 0.9
// for the given component and 0.1 for the others, as flexmix's initPosteriors. Components whose prior falls below minprior are removed.

use e.algo.rand.r as rg
use e.algo.stat.olsfit as ols
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

error Malformed

// coef is k by p (component-major), sigma has k entries, post is n by k row-major (the scaled posteriors), cluster the 1-based max.col of post
type Fm = struct { k: usize, iter: usize, converged: bool, llh: f64, prior: []f64, coef: []f64, sigma: []f64, post: []f64, cluster: []usize, clog: f64, df: f64 }

// log(sum(exp(v))) of the k values at v[off..off + k], stable
fn lse(v: []const f64, off: usize, k: usize) -> f64 {
    var m = v[off]
    var j = 1usize
    while j < k {
        if v[off + j] > m { m = v[off + j] }
        j += 1usize
    }
    var s = 0.0f64
    j = 0usize
    while j < k {
        s += math.exp[f64](v[off + j] - m)
        j += 1usize
    }
    ret m + math.log[f64](s)
}

// x is n by p column-major (the intercept a column of ones), y the response, cluster the start (1-based codes with k = the largest)
fn gauss_em(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, cluster: []const f64, minprior: f64, tol: f64, iter_max: usize, famcode: usize, sz: []const f64) -> (Fm, err) {
    // famcode 0 Gaussian, 1 Poisson, 2 binomial, 3 Gamma; plus 10 for the classification EM (CEM: each observation goes wholly to its most probable component)
    var cem = false
    var fam = famcode
    if famcode >= 10usize {
        cem = true
        fam = famcode - 10usize
    }
    var out: Fm = zero
    var k = 0usize
    var i = 0usize
    while i < n {
        if usize(cluster[i]) > k { k = usize(cluster[i]) }
        i += 1usize
    }
    let k0 = k
    let (post, e1) = mem.alloc[f64](a, n * k0)
    let (lp, e2) = mem.alloc[f64](a, n * k0)
    let (prior, e3) = mem.alloc[f64](a, k0)
    let (coef, e4) = mem.alloc[f64](a, k0 * p)
    let (sigma, e5) = mem.alloc[f64](a, k0)
    let (xw, e6) = mem.alloc[f64](a, n * p)
    let (yw, e7) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (out, Malformed) }
    // initial scaled posteriors
    i = 0usize
    while i < n {
        var tot = 0.0f64
        var j = 0usize
        while j < k {
            var v = 0.1f64
            if usize(cluster[i]) == j + 1usize { v = 0.9f64 }
            post[i * k0 + j] = v
            tot += v
            j += 1usize
        }
        j = 0usize
        while j < k {
            post[i * k0 + j] = post[i * k0 + j] / tot
            j += 1usize
        }
        i += 1usize
    }
    var llh = 0.0f64 - 1.0f64 / 0.0f64
    var converged = false
    var iter = 1usize
    while iter <= iter_max {
        if cem {
            // .FLXgetOK for classify = "CEM": the posterior becomes the indicator of its first maximum
            var ci = 0usize
            while ci < n {
                var bj = 0usize
                var cj = 1usize
                while cj < k {
                    if post[ci * k0 + cj] > post[ci * k0 + bj] { bj = cj }
                    cj += 1usize
                }
                cj = 0usize
                while cj < k {
                    if cj == bj { post[ci * k0 + cj] = 1.0f64 } else { post[ci * k0 + cj] = 0.0f64 }
                    cj += 1usize
                }
                ci += 1usize
            }
        }
        // prior = column means; drop the components below minprior
        var keep = 0usize
        var j = 0usize
        while j < k {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += post[i * k0 + j]
                i += 1usize
            }
            prior[j] = s / f64(n)
            if prior[j] >= minprior { keep += 1usize }
            j += 1usize
        }
        if keep < k {
            if keep == 0usize { ret (out, Malformed) }
            // compact the kept columns to the front
            var w = 0usize
            var tp = 0.0f64
            j = 0usize
            while j < k {
                if prior[j] >= minprior {
                    prior[w] = prior[j]
                    var cc2 = 0usize
                    while cc2 < p {
                        coef[w * p + cc2] = coef[j * p + cc2]
                        cc2 += 1usize
                    }
                    i = 0usize
                    while i < n {
                        post[i * k0 + w] = post[i * k0 + j]
                        i += 1usize
                    }
                    tp += prior[w]
                    w += 1usize
                }
                j += 1usize
            }
            j = 0usize
            while j < keep {
                prior[j] = prior[j] / tp
                j += 1usize
            }
            i = 0usize
            while i < n {
                var rs = 0.0f64
                j = 0usize
                while j < keep {
                    rs += post[i * k0 + j]
                    j += 1usize
                }
                j = 0usize
                while j < keep {
                    if rs == 0.0f64 { post[i * k0 + j] = prior[j] } else { post[i * k0 + j] = post[i * k0 + j] }
                    j += 1usize
                }
                var rs2 = 0.0f64
                j = 0usize
                while j < keep {
                    rs2 += post[i * k0 + j]
                    j += 1usize
                }
                j = 0usize
                while j < keep {
                    post[i * k0 + j] = post[i * k0 + j] / rs2
                    j += 1usize
                }
                i += 1usize
            }
            k = keep
        }
        // M step: weighted least squares for each component
        j = 0usize
        while j < k {
            var sw = 0.0f64
            i = 0usize
            while i < n {
                let w = post[i * k0 + j]
                sw += w
                let sq = math.sqrt[f64](w)
                yw[i] = sq * y[i]
                var c = 0usize
                while c < p {
                    xw[c * n + i] = sq * x[c * n + i]
                    c += 1usize
                }
                i += 1usize
            }
            if fam >= 1usize {
                let (wj, e9) = mem.alloc[f64](a, n)
                let (bj, e10) = mem.alloc[f64](a, p)
                if e9 != ok || e10 != ok { ret (out, Malformed) }
                i = 0usize
                while i < n {
                    wj[i] = post[i * k0 + j]
                    i += 1usize
                }
                var c0 = 0usize
                while c0 < p {
                    bj[c0] = coef[j * p + c0]
                    c0 += 1usize
                }
                var ge = ok
                let (dv, e11) = mem.alloc[f64](a, 1usize)
                if e11 != ok { ret (out, Malformed) }
                if fam == 1usize {
                    ge = pois_glm(a, x, n, p, y, wj, bj, iter > 1usize)
                } else if fam == 2usize {
                    ge = binom_glm(a, x, n, p, y, sz, wj, bj, iter > 1usize)
                } else {
                    ge = gamma_glm(a, x, n, p, y, wj, bj, iter > 1usize, dv)
                }
                if ge != ok { ret (out, ge) }
                c0 = 0usize
                while c0 < p {
                    coef[j * p + c0] = bj[c0]
                    c0 += 1usize
                }
                sigma[j] = 1.0f64
                if fam == 3usize { sigma[j] = sw / dv[0usize] }
            } else {
                let (f, fe) = ols.fit_tol(a, xw, n, p, yw, 0.0000001f64)
                if fe != ok { ret (out, fe) }
                var c = 0usize
                while c < p {
                    coef[j * p + c] = f.coef[c]
                    c += 1usize
                }
                sigma[j] = math.sqrt[f64](f.rss / (sw / f64(n)) / f64(n - f.rank))
            }
            j += 1usize
        }
        // E step
        i = 0usize
        while i < n {
            j = 0usize
            while j < k {
                var mu = 0.0f64
                var c = 0usize
                while c < p {
                    mu += x[c * n + i] * coef[j * p + c]
                    c += 1usize
                }
                var ld = 0.0f64
                if fam == 1usize {
                    ld = nm.dpois(y[i], math.exp[f64](mu), true)
                } else if fam == 3usize {
                    ld = nm.dgamma(y[i], sigma[j], (1.0f64 / mu) / sigma[j], true)
                } else if fam == 2usize {
                    ld = nb.dbinom(y[i], sz[i], 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - mu)), true)
                } else {
                    ld = dist.dnorm(y[i], mu, sigma[j], true)
                }
                lp[i * k0 + j] = ld + math.log[f64](prior[j])
                j += 1usize
            }
            i += 1usize
        }
        let old = llh
        llh = 0.0f64
        i = 0usize
        while i < n {
            let ls = lse(lp, i * k0, k)
            llh += ls
            j = 0usize
            while j < k {
                post[i * k0 + j] = math.exp[f64](lp[i * k0 + j] - ls)
                j += 1usize
            }
            i += 1usize
        }
        if math.abs[f64](llh - old) / (math.abs[f64](llh) + 0.1f64) < tol {
            converged = true
            break
        }
        iter += 1usize
    }
    if iter > iter_max { iter = iter_max }
    // the prior is the column means of the final posteriors
    var j = 0usize
    while j < k {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += post[i * k0 + j]
            i += 1usize
        }
        prior[j] = s / f64(n)
        j += 1usize
    }
    let (cl, e8) = mem.alloc[usize](a, n)
    if e8 != ok { ret (out, Malformed) }
    i = 0usize
    while i < n {
        var best = 0usize
        j = 1usize
        while j < k {
            if post[i * k0 + j] > post[i * k0 + best] { best = j }
            j += 1usize
        }
        cl[i] = best + 1usize
        i += 1usize
    }
    out.k = k
    out.iter = iter
    out.converged = converged
    out.llh = llh
    out.prior = prior[0usize..k]
    out.coef = coef
    out.sigma = sigma
    out.post = post
    // the classification log-likelihood (the log unscaled posteriors of the assigned components) and the parameter count, for BIC and ICL
    var clg = 0.0f64
    i = 0usize
    while i < n {
        clg += lp[i * k0 + (cl[i] - 1usize)]
        i += 1usize
    }
    out.clog = clg
    var dfc = f64(p)
    if fam == 0usize || fam == 3usize { dfc = f64(p + 1usize) }
    out.df = f64(k - 1usize) + f64(k) * dfc
    out.cluster = cl
    ret (out, ok)
}

// the call the oracle fixture makes: x is n by p row-major (the intercept first), init the 0-based start clustering, k the number of components;
// cluster in the result is 0-based
fn gaussian(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, k: usize, init: []const f64, iter_max: usize, minprior: f64, tol: f64) -> (Fm, err) {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (cl, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = x[i * p + c]
            c += 1usize
        }
        cl[i] = init[i] + 1.0f64
        i += 1usize
    }
    let (f, fe) = gauss_em(a, xc, n, p, y, cl, minprior, tol, iter_max, 0usize, y)
    if fe != ok { ret (f, fe) }
    var g = f
    i = 0usize
    while i < n {
        g.cluster[i] = f.cluster[i] - 1usize
        i += 1usize
    }
    if k != 0usize && k < f.k { ret (g, Malformed) }
    ret (g, ok)
}

// flexmix(y ~ x, k = k) without a cluster argument: the start is sample(seq_len(k), n, replace = TRUE) on R's stream, then the same EM; x is n by p row-major
fn gaussian_random(a: *mem.Arena, r: *rg.Rng, x: []const f64, y: []const f64, n: usize, p: usize, k: usize, iter_max: usize, minprior: f64, tol: f64) -> (Fm, err) {
    let (cl, ce) = rg.sample_int(a, r, i64(k), i64(n), true)
    if ce != ok { ret (zero, ce) }
    let (init, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        init[i] = f64(cl[i] - 1i64)
        i += 1usize
    }
    let (f, fe) = gaussian(a, x, y, n, p, k, init, iter_max, minprior, tol)
    ret (f, fe)
}


// R glm.fit for the Poisson family with the log link (IRLS from the mean y + 0.1, or from a start vector as flexmix passes the previous coefficients),
// weights w, deviance convergence |dev - devold| / (|dev| + 0.1) < 1e-8, at most 25 iterations; x is n by p column-major; beta is the start on entry (when
// has_start) and the estimate on exit
fn pois_dev(y: []const f64, mu: []const f64, w: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var r = mu[i] * w[i]
        if y[i] > 0.0f64 { r = w[i] * (y[i] * math.log[f64](y[i] / mu[i]) - (y[i] - mu[i])) }
        s += 2.0f64 * r
        i += 1usize
    }
    ret s
}

fn pois_glm(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, beta: []f64, has_start: bool) -> err {
    let (eta, e1) = mem.alloc[f64](a, n)
    let (mu, e2) = mem.alloc[f64](a, n)
    let (z, e3) = mem.alloc[f64](a, n)
    let (xw, e4) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret Malformed }
    var i = 0usize
    while i < n {
        if has_start {
            var t = 0.0f64
            var c = 0usize
            while c < p {
                t += x[c * n + i] * beta[c]
                c += 1usize
            }
            eta[i] = t
            mu[i] = math.exp[f64](t)
        } else {
            mu[i] = y[i] + 0.1f64
            eta[i] = math.log[f64](mu[i])
        }
        i += 1usize
    }
    var devold = pois_dev(y, mu, w, n)
    var iter = 0usize
    while iter < 25usize {
        iter += 1usize
        i = 0usize
        while i < n {
            let sq = math.sqrt[f64](w[i] * mu[i])
            z[i] = (eta[i] + (y[i] - mu[i]) / mu[i]) * sq
            var c = 0usize
            while c < p {
                xw[c * n + i] = x[c * n + i] * sq
                c += 1usize
            }
            i += 1usize
        }
        let (f, fe) = ols.fit_tol(a, xw, n, p, z, 0.00000000001f64)
        if fe != ok { ret fe }
        var c = 0usize
        while c < p {
            beta[c] = f.coef[c]
            c += 1usize
        }
        i = 0usize
        while i < n {
            var t = 0.0f64
            c = 0usize
            while c < p {
                t += x[c * n + i] * beta[c]
                c += 1usize
            }
            eta[i] = t
            mu[i] = math.exp[f64](t)
            i += 1usize
        }
        let dev = pois_dev(y, mu, w, n)
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 0.00000001f64 { break }
        devold = dev
    }
    ret ok
}

// flexmix(y ~ x, k, model = FLXMRglm(family = "poisson"), cluster = init): x n by p row-major, counts y, init 0-based
fn poisson(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, k: usize, init: []const f64, iter_max: usize, minprior: f64, tol: f64) -> (Fm, err) {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (cl, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = x[i * p + c]
            c += 1usize
        }
        cl[i] = init[i] + 1.0f64
        i += 1usize
    }
    let (f, fe) = gauss_em(a, xc, n, p, y, cl, minprior, tol, iter_max, 1usize, y)
    if fe != ok { ret (f, fe) }
    var g = f
    i = 0usize
    while i < n {
        g.cluster[i] = f.cluster[i] - 1usize
        i += 1usize
    }
    ret (g, ok)
}

// stepFlexmix(y ~ x, k = k, nrep = nrep) for one k: nrep random-start fits from the same stream, the best by log-likelihood (the first of equals, as a strict > keeps it)
// with the nrep log-likelihoods (NaN where a fit failed); x is n by p row-major
fn step_gaussian(a: *mem.Arena, r: *rg.Rng, x: []const f64, y: []const f64, n: usize, p: usize, k: usize, nrep: usize, iter_max: usize, minprior: f64, tol: f64, logliks: []f64) -> (Fm, err) {
    var best: Fm = zero
    var best_ll = 0.0f64 - 1.0f64 / 0.0f64
    var got = false
    var m = 0usize
    while m < nrep {
        let (f, fe) = gaussian_random(a, r, x, y, n, p, k, iter_max, minprior, tol)
        if fe != ok {
            logliks[m] = 0.0f64 / 0.0f64
        } else {
            logliks[m] = f.llh
            if f.llh > best_ll {
                best_ll = f.llh
                best = f
                got = true
            }
        }
        m += 1usize
    }
    if !got { ret (best, Malformed) }
    ret (best, ok)
}


// BIC, AIC and ICL as flexmix defines them: -2 logLik + df log n, -2 logLik + 2 df, and -2 clogLik + df log n
fn bic(f: *const Fm, n: usize) -> f64 { ret 0.0f64 - 2.0f64 * f.llh + f.df * math.log[f64](f64(n)) }

fn aic(f: *const Fm) -> f64 { ret 0.0f64 - 2.0f64 * f.llh + 2.0f64 * f.df }

fn icl(f: *const Fm, n: usize) -> f64 { ret 0.0f64 - 2.0f64 * f.clog + f.df * math.log[f64](f64(n)) }


// R glm.fit for the binomial family with the logit link and a (successes, size) response: the proportion y / size with prior weights w * size, started from
// mustart = (weights y + 0.5) / (weights + 1) or from the previous coefficients, the same deviance convergence as the Poisson fit
fn binom_dev(yp: []const f64, mu: []const f64, wt: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var t1 = 0.0f64
        if yp[i] > 0.0f64 { t1 = yp[i] * math.log[f64](yp[i] / mu[i]) }
        var t2 = 0.0f64
        if yp[i] < 1.0f64 { t2 = (1.0f64 - yp[i]) * math.log[f64]((1.0f64 - yp[i]) / (1.0f64 - mu[i])) }
        s += 2.0f64 * wt[i] * (t1 + t2)
        i += 1usize
    }
    ret s
}

fn binom_glm(a: *mem.Arena, x: []const f64, n: usize, p: usize, succ: []const f64, size: []const f64, w: []const f64, beta: []f64, has_start: bool) -> err {
    let (eta, e1) = mem.alloc[f64](a, n)
    let (mu, e2) = mem.alloc[f64](a, n)
    let (z, e3) = mem.alloc[f64](a, n)
    let (xw, e4) = mem.alloc[f64](a, n * p)
    let (yp, e5) = mem.alloc[f64](a, n)
    let (wt, e6) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret Malformed }
    var i = 0usize
    while i < n {
        yp[i] = succ[i] / size[i]
        wt[i] = w[i] * size[i]
        if has_start {
            var t = 0.0f64
            var c = 0usize
            while c < p {
                t += x[c * n + i] * beta[c]
                c += 1usize
            }
            eta[i] = t
            mu[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t))
        } else {
            mu[i] = (wt[i] * yp[i] + 0.5f64) / (wt[i] + 1.0f64)
            eta[i] = math.log[f64](mu[i] / (1.0f64 - mu[i]))
        }
        i += 1usize
    }
    var devold = binom_dev(yp, mu, wt, n)
    var iter = 0usize
    while iter < 25usize {
        iter += 1usize
        i = 0usize
        while i < n {
            let me = mu[i] * (1.0f64 - mu[i])
            let sq = math.sqrt[f64](wt[i] * me)
            z[i] = (eta[i] + (yp[i] - mu[i]) / me) * sq
            var c = 0usize
            while c < p {
                xw[c * n + i] = x[c * n + i] * sq
                c += 1usize
            }
            i += 1usize
        }
        let (f, fe) = ols.fit_tol(a, xw, n, p, z, 0.00000000001f64)
        if fe != ok { ret fe }
        var c = 0usize
        while c < p {
            beta[c] = f.coef[c]
            c += 1usize
        }
        i = 0usize
        while i < n {
            var t = 0.0f64
            c = 0usize
            while c < p {
                t += x[c * n + i] * beta[c]
                c += 1usize
            }
            eta[i] = t
            mu[i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t))
            i += 1usize
        }
        let dev = binom_dev(yp, mu, wt, n)
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 0.00000001f64 { break }
        devold = dev
    }
    ret ok
}

// flexmix(cbind(succ, fail) ~ x, k, model = FLXMRglm(family = "binomial"), cluster = init): x n by p row-major, init 0-based
fn binomial(a: *mem.Arena, x: []const f64, succ: []const f64, size: []const f64, n: usize, p: usize, k: usize, init: []const f64, iter_max: usize, minprior: f64, tol: f64) -> (Fm, err) {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (cl, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = x[i * p + c]
            c += 1usize
        }
        cl[i] = init[i] + 1.0f64
        i += 1usize
    }
    let (f, fe) = gauss_em(a, xc, n, p, succ, cl, minprior, tol, iter_max, 2usize, size)
    if fe != ok { ret (f, fe) }
    var g = f
    i = 0usize
    while i < n {
        g.cluster[i] = f.cluster[i] - 1usize
        i += 1usize
    }
    ret (g, ok)
}


// R glm.fit for the Gamma family with the inverse link: mustart = y (or the previous coefficients), working weights sqrt(w) mu, the Gamma deviance
// -2 w (log(y / mu) - (y - mu) / mu) and the same convergence test; dev[0] receives the final deviance, from which flexmix takes the shape sum(w) / deviance
fn gamma_dev(y: []const f64, mu: []const f64, w: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var lg = 0.0f64
        if y[i] != 0.0f64 { lg = math.log[f64](y[i] / mu[i]) }
        s += 0.0f64 - 2.0f64 * w[i] * (lg - (y[i] - mu[i]) / mu[i])
        i += 1usize
    }
    ret s
}

fn gamma_glm(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, w: []const f64, beta: []f64, has_start: bool, dev_out: []f64) -> err {
    let (eta, e1) = mem.alloc[f64](a, n)
    let (mu, e2) = mem.alloc[f64](a, n)
    let (z, e3) = mem.alloc[f64](a, n)
    let (xw, e4) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret Malformed }
    var i = 0usize
    while i < n {
        if has_start {
            var t = 0.0f64
            var c = 0usize
            while c < p {
                t += x[c * n + i] * beta[c]
                c += 1usize
            }
            eta[i] = t
            mu[i] = 1.0f64 / t
        } else {
            mu[i] = y[i]
            eta[i] = 1.0f64 / mu[i]
        }
        i += 1usize
    }
    var devold = gamma_dev(y, mu, w, n)
    var dev = devold
    var iter = 0usize
    while iter < 25usize {
        iter += 1usize
        i = 0usize
        while i < n {
            // mu.eta = -mu^2 and variance mu^2: z = eta - (y - mu) / mu^2, weight sqrt(w) mu
            let sq = math.sqrt[f64](w[i]) * mu[i]
            z[i] = (eta[i] - (y[i] - mu[i]) / (mu[i] * mu[i])) * sq
            var c = 0usize
            while c < p {
                xw[c * n + i] = x[c * n + i] * sq
                c += 1usize
            }
            i += 1usize
        }
        let (f, fe) = ols.fit_tol(a, xw, n, p, z, 0.00000000001f64)
        if fe != ok { ret fe }
        var c = 0usize
        while c < p {
            beta[c] = f.coef[c]
            c += 1usize
        }
        i = 0usize
        while i < n {
            var t = 0.0f64
            c = 0usize
            while c < p {
                t += x[c * n + i] * beta[c]
                c += 1usize
            }
            eta[i] = t
            mu[i] = 1.0f64 / t
            i += 1usize
        }
        dev = gamma_dev(y, mu, w, n)
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < 0.00000001f64 { break }
        devold = dev
    }
    dev_out[0usize] = dev
    ret ok
}

// flexmix(y ~ x, k, model = FLXMRglm(family = "Gamma"), cluster = init): x n by p row-major, positive y, init 0-based
fn gamma_mix(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, k: usize, init: []const f64, iter_max: usize, minprior: f64, tol: f64) -> (Fm, err) {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (cl, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = x[i * p + c]
            c += 1usize
        }
        cl[i] = init[i] + 1.0f64
        i += 1usize
    }
    let (f, fe) = gauss_em(a, xc, n, p, y, cl, minprior, tol, iter_max, 3usize, y)
    if fe != ok { ret (f, fe) }
    var g = f
    i = 0usize
    while i < n {
        g.cluster[i] = f.cluster[i] - 1usize
        i += 1usize
    }
    ret (g, ok)
}


// the same Gaussian fit with control(classify = "CEM")
fn gaussian_cem(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, k: usize, init: []const f64, iter_max: usize, minprior: f64, tol: f64) -> (Fm, err) {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    let (cl, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = x[i * p + c]
            c += 1usize
        }
        cl[i] = init[i] + 1.0f64
        i += 1usize
    }
    let (f, fe) = gauss_em(a, xc, n, p, y, cl, minprior, tol, iter_max, 10usize, y)
    if fe != ok { ret (f, fe) }
    var g = f
    i = 0usize
    while i < n {
        g.cluster[i] = f.cluster[i] - 1usize
        i += 1usize
    }
    ret (g, ok)
}
