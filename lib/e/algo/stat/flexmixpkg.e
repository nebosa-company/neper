// The EM fit of the R package flexmix for a mixture of Gaussian linear regressions (FLXMRglm with the gaussian family, the default multinomial prior and the
// "auto" classification, which is the weighted EM). The start is a given cluster vector (flexmix's cluster argument, codes 1..k): the initial posteriors are 0.9
// for the given component and 0.1 for the others, as flexmix's initPosteriors. Components whose prior falls below minprior are removed.

use e.algo.rand.r as rg
use e.algo.stat.olsfit as ols
use e.math
use e.math.dist as dist
use e.mem

error Malformed

// coef is k by p (component-major), sigma has k entries, post is n by k row-major (the scaled posteriors), cluster the 1-based max.col of post
type Fm = struct { k: usize, iter: usize, converged: bool, llh: f64, prior: []f64, coef: []f64, sigma: []f64, post: []f64, cluster: []usize }

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
fn gauss_em(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, cluster: []const f64, minprior: f64, tol: f64, iter_max: usize) -> (Fm, err) {
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
            let (f, fe) = ols.fit_tol(a, xw, n, p, yw, 0.0000001f64)
            if fe != ok { ret (out, fe) }
            var c = 0usize
            while c < p {
                coef[j * p + c] = f.coef[c]
                c += 1usize
            }
            sigma[j] = math.sqrt[f64](f.rss / (sw / f64(n)) / f64(n - f.rank))
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
                lp[i * k0 + j] = dist.dnorm(y[i], mu, sigma[j], true) + math.log[f64](prior[j])
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
    let (f, fe) = gauss_em(a, xc, n, p, y, cl, minprior, tol, iter_max)
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
