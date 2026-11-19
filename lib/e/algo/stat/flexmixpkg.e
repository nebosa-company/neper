// The EM fit of the R package flexmix for a mixture of Gaussian linear regressions (FLXMRglm with the gaussian family, the default multinomial prior and the
// "auto" classification, which is the weighted EM). The start is a given cluster vector (flexmix's cluster argument, codes 1..k): the initial posteriors are 0.9
// for the given component and 0.1 for the others, as flexmix's initPosteriors. Components whose prior falls below minprior are removed.

use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.algo.stat.nnetpkg as nn
use e.algo.stat.rbfgs as bf
use e.algo.stat.olsfit as ols
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

error Malformed

// coef is k by p (component-major), sigma has k entries, post is n by k row-major (the scaled posteriors), cluster the 1-based max.col of post
type Fm = struct { k: usize, iter: usize, converged: bool, llh: f64, prior: []f64, coef: []f64, sigma: []f64, post: []f64, cluster: []usize, clog: f64, df: f64, k0: usize, pm: []f64, conc: []f64, pc: usize, des: []f64, xs: []f64 }

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

// the concomitant multinomial prior (FLXPmultinom): nnet's softmax regression (size 0, skip layer) with the first component's weights and every bias fixed at
// zero, from a zero start, BFGS with maxit 100, reltol 1e-8 and abstol 1e-4. pm is n by k0 row-major (the first k columns are written), coef is k by q.
type ConcCtx = struct { nc: nn.NetCtx, full: []f64, gfull: []f64, q: usize, k: usize }

fn conc_expand(c: *ConcCtx, v: []const f64) {
    var i = 0usize
    while i < c.full.len {
        c.full[i] = 0.0f64
        i += 1usize
    }
    var u = 1usize
    while u < c.k {
        var j = 0usize
        while j < c.q {
            c.full[u * (c.q + 1usize) + 1usize + j] = v[(u - 1usize) * c.q + j]
            j += 1usize
        }
        u += 1usize
    }
}

fn conc_f(c: *ConcCtx, v: []const f64) -> f64 {
    conc_expand(c, v)
    ret nn.net_f(&c.nc, c.full)
}

fn conc_g(c: *ConcCtx, v: []const f64, g: []f64) {
    conc_expand(c, v)
    nn.net_g(&c.nc, c.full, c.gfull)
    var u = 1usize
    while u < c.k {
        var j = 0usize
        while j < c.q {
            g[(u - 1usize) * c.q + j] = c.gfull[u * (c.q + 1usize) + 1usize + j]
            j += 1usize
        }
        u += 1usize
    }
}

fn conc_fit(a: *mem.Arena, cx: []const f64, n: usize, q: usize, post: []const f64, k0: usize, k: usize, pm: []f64, coef: []f64) -> err {
    if k < 2usize || k > 16usize { ret Malformed }
    let (yb, e1) = mem.alloc[f64](a, n * k)
    let (wb, e2) = mem.alloc[f64](a, n)
    let (full, e3) = mem.alloc[f64](a, k * (q + 1usize))
    let (gfull, e4) = mem.alloc[f64](a, k * (q + 1usize))
    let (v, e5) = mem.alloc[f64](a, (k - 1usize) * q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret Malformed }
    var t = 0usize
    while t < n {
        wb[t] = 1.0f64
        var o = 0usize
        while o < k {
            yb[t * k + o] = post[t * k0 + o]
            o += 1usize
        }
        t += 1usize
    }
    var i = 0usize
    while i < v.len {
        v[i] = 0.0f64
        i += 1usize
    }
    var c = ConcCtx { nc: nn.NetCtx { x: cx, y: yb, w: wb, n: n, p: q, h: 0usize, k: k, mode: 3usize, decay: 0.0f64, skip: true }, full: full, gfull: gfull, q: q, k: k }
    let fv = bf.vmmin_abs[ConcCtx](a, &c, conc_f, conc_g, v, 0.00000001f64, 100usize, 0.0001f64)
    if fv != fv { ret Malformed }
    conc_expand(&c, v)
    var hid: [64]f64 = zero
    var out: [16]f64 = zero
    t = 0usize
    while t < n {
        nn.net_forward(&c.nc, c.full, t, hid[0usize..64usize], out[0usize..16usize])
        var o = 0usize
        while o < k {
            pm[t * k0 + o] = out[o]
            o += 1usize
        }
        t += 1usize
    }
    var o = 0usize
    while o < k {
        var j = 0usize
        while j < q {
            coef[o * q + j] = c.full[o * (q + 1usize) + 1usize + j]
            j += 1usize
        }
        o += 1usize
    }
    ret ok
}

// R's max.col(m) with ties.method "random" for row i of the n by k0 matrix: entries within 1e-5 of the row's largest magnitude count as tied, and each tie
// costs one unif_rand
fn row_argmax(post: []const f64, i: usize, k0: usize, k: usize, r: *rg.Rng) -> usize {
    var large = 0.0f64
    var j = 0usize
    while j < k {
        let v = post[i * k0 + j]
        if v - v == 0.0f64 {
            if math.abs[f64](v) > large { large = math.abs[f64](v) }
        }
        j += 1usize
    }
    var m = 0usize
    var av = post[i * k0]
    let tol = 0.00001f64 * large
    var ntie = 1.0f64
    j = 1usize
    while j < k {
        let b = post[i * k0 + j]
        if b > av + tol {
            av = b
            m = j
            ntie = 1.0f64
        } else if b >= av - tol {
            ntie += 1.0f64
            if ntie * rg.unif(r) < 1.0f64 { m = j }
        }
        j += 1usize
    }
    ret m
}

// x is n by p column-major (the intercept a column of ones), y the response, post0 the n by k0 initial unscaled posteriors (row-major), cx the n by q concomitant
// model matrix (q = 0 for the constant prior). famcode = family + 10 * classify: family 0 Gaussian, 1 Poisson, 2 binomial, 3 Gamma; classify 0 weighted EM,
// 1 CEM (each observation goes wholly to its most probable component), 2 SEM (one multinomial draw per observation from r), 3 random (SEM that keeps the best iteration)
fn flex_em(a: *mem.Arena, r: *rg.Rng, x: []const f64, n: usize, p: usize, y: []const f64, post0: []const f64, k0: usize, minprior: f64, tol: f64, iter_max: usize, famcode: usize, sz: []const f64, cx: []const f64, q: usize, fxs: *Fix) -> (Fm, err) {
    let cls = famcode / 10usize
    let fam = famcode - cls * 10usize
    var out: Fm = zero
    var k = k0
    var i = 0usize
    let (post, e1) = mem.alloc[f64](a, n * k0)
    let (lp, e2) = mem.alloc[f64](a, n * k0)
    let (prior, e3) = mem.alloc[f64](a, k0)
    let (coef, e4) = mem.alloc[f64](a, k0 * p)
    let (sigma, e5) = mem.alloc[f64](a, k0)
    let (xw, e6) = mem.alloc[f64](a, n * p)
    let (yw, e7) = mem.alloc[f64](a, n)
    let (pm, e8) = mem.alloc[f64](a, n * k0)
    let (cc, e9) = mem.alloc[f64](a, k0 * (q + 1usize))
    let (kidx, e19) = mem.alloc[usize](a, k0)
    let (bco, e10) = mem.alloc[f64](a, k0 * p)
    let (bsg, e11) = mem.alloc[f64](a, k0)
    let (bpr, e12) = mem.alloc[f64](a, k0)
    let (bpo, e13) = mem.alloc[f64](a, n * k0)
    let (blp, e14) = mem.alloc[f64](a, n * k0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e19 != ok { ret (out, Malformed) }
    // initial scaled posteriors
    i = 0usize
    while i < n {
        var tot = 0.0f64
        var j = 0usize
        while j < k {
            tot += post0[i * k0 + j]
            j += 1usize
        }
        j = 0usize
        while j < k {
            post[i * k0 + j] = post0[i * k0 + j] / tot
            j += 1usize
        }
        i += 1usize
    }
    var llh = 0.0f64 - 1.0f64 / 0.0f64
    var llh_max = 0.0f64 - 1.0f64 / 0.0f64
    var kbest = k
    var converged = false
    var iter_rm = 0usize
    var iter = 1usize
    while iter <= iter_max {
        if cls >= 1usize {
            // .FLXgetOK: the posterior becomes an indicator, of its first maximum (CEM) or of one multinomial draw (SEM, random)
            var ci = 0usize
            while ci < n {
                var bj = 0usize
                if cls == 1usize {
                    bj = row_argmax(post, ci, k0, k, r)
                } else {
                    let mk = mem.mark(a)
                    let (dr, de) = rd.sample_prob(a, r, k, 1usize, false, post[ci * k0..ci * k0 + k])
                    if de != ok { ret (out, de) }
                    bj = usize(dr[0usize] - 1i64)
                    mem.reset(a, mk)
                }
                var cj = 0usize
                while cj < k {
                    if cj == bj { post[ci * k0 + cj] = 1.0f64 } else { post[ci * k0 + cj] = 0.0f64 }
                    cj += 1usize
                }
                ci += 1usize
            }
        }
        // prior: the column means (constant) or the multinomial regression on the concomitant variables; drop the components below minprior
        if q > 0usize {
            let ce = conc_fit(a, cx, n, q, post, k0, k, pm, cc)
            if ce != ok { ret (out, ce) }
        }
        var keep = 0usize
        var j = 0usize
        while j < k {
            var s = 0.0f64
            i = 0usize
            while i < n {
                if q > 0usize { s += pm[i * k0 + j] } else { s += post[i * k0 + j] }
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
                    kidx[w] = j
                    var cc2 = 0usize
                    while cc2 < p {
                        coef[w * p + cc2] = coef[j * p + cc2]
                        cc2 += 1usize
                    }
                    i = 0usize
                    while i < n {
                        post[i * k0 + w] = post[i * k0 + j]
                        pm[i * k0 + w] = pm[i * k0 + j]
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
                // the rows of a matrix prior are rescaled one by one
                if q > 0usize {
                    var ps = 0.0f64
                    j = 0usize
                    while j < keep {
                        ps += pm[i * k0 + j]
                        j += 1usize
                    }
                    j = 0usize
                    while j < keep {
                        pm[i * k0 + j] = pm[i * k0 + j] / ps
                        j += 1usize
                    }
                }
                var rs = 0.0f64
                j = 0usize
                while j < keep {
                    rs += post[i * k0 + j]
                    j += 1usize
                }
                if rs == 0.0f64 {
                    j = 0usize
                    while j < keep {
                        if q > 0usize { post[i * k0 + j] = pm[i * k0 + j] } else { post[i * k0 + j] = prior[j] }
                        j += 1usize
                    }
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
            if fxs.on {
                let fre = fix_remove(a, fxs, kidx, keep, k, n)
                if fre != ok { ret (out, fre) }
            }
            k = keep
            if cls == 3usize {
                llh_max = 0.0f64 - 1.0f64 / 0.0f64
                iter_rm = iter
            }
        }
        // M step: weighted least squares (Gaussian) or glm.fit for each component
        var km = k
        if fxs.on {
            km = 0usize
            let me2 = fix_mstep(a, fxs, post, k0, k, n, y, sz, fam, coef, sigma)
            if me2 != ok { ret (out, me2) }
        }
        j = 0usize
        while j < km {
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
                let (wj, e15) = mem.alloc[f64](a, n)
                let (bj, e16) = mem.alloc[f64](a, p)
                if e15 != ok || e16 != ok { ret (out, Malformed) }
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
                let (dv, e17) = mem.alloc[f64](a, 1usize)
                if e17 != ok { ret (out, Malformed) }
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
                if fxs.on {
                    while c < fxs.pc {
                        mu += fxs.xs[c * (k * n) + j * n + i] * coef[c]
                        c += 1usize
                    }
                } else {
                    while c < p {
                        mu += x[c * n + i] * coef[j * p + c]
                        c += 1usize
                    }
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
                if q > 0usize { lp[i * k0 + j] = ld + math.log[f64](pm[i * k0 + j]) } else { lp[i * k0 + j] = ld + math.log[f64](prior[j]) }
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
        if llh != llh || llh - llh != 0.0f64 { ret (out, Malformed) }
        if math.abs[f64](llh - old) / (math.abs[f64](llh) + 0.1f64) < tol {
            converged = true
            break
        }
        if cls == 3usize && llh_max < llh {
            kbest = k
            j = 0usize
            while j < k {
                bpr[j] = prior[j]
                bsg[j] = sigma[j]
                var c = 0usize
                while c < p {
                    bco[j * p + c] = coef[j * p + c]
                    c += 1usize
                }
                j += 1usize
            }
            i = 0usize
            while i < n * k0 {
                bpo[i] = post[i]
                blp[i] = lp[i]
                i += 1usize
            }
            llh_max = llh
        }
        iter += 1usize
    }
    if iter > iter_max { iter = iter_max }
    if cls == 3usize {
        if llh_max != llh_max || llh_max < 0.0f64 - 1.0e300f64 { ret (out, Malformed) }
        k = kbest
        var j2 = 0usize
        while j2 < k {
            prior[j2] = bpr[j2]
            sigma[j2] = bsg[j2]
            var c = 0usize
            while c < p {
                coef[j2 * p + c] = bco[j2 * p + c]
                c += 1usize
            }
            j2 += 1usize
        }
        i = 0usize
        while i < n * k0 {
            post[i] = bpo[i]
            lp[i] = blp[i]
            i += 1usize
        }
        llh = llh_max
        iter = iter_max - iter_rm
    }
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
    // FLXfillConcomitant: the multinomial refitted on the final posteriors
    if q > 0usize {
        let ce2 = conc_fit(a, cx, n, q, post, k0, k, pm, cc)
        if ce2 != ok { ret (out, ce2) }
    }
    let (cl, e18) = mem.alloc[usize](a, n)
    if e18 != ok { ret (out, Malformed) }
    i = 0usize
    while i < n {
        cl[i] = row_argmax(post, i, k0, k, r) + 1usize
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
    out.k0 = k0
    out.pc = p
    out.pm = pm
    out.conc = cc
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
    var dfp = f64(k - 1usize)
    if q > 0usize { dfp = f64(k - 1usize) * f64(q) }
    out.df = dfp + f64(k) * dfc
    if fxs.on {
        // per component coefficients (zero where unused); the df of every component is its share of each column it uses, plus the share of its variance group
        let (cf2, e20) = mem.alloc[f64](a, k * fxs.pc)
        if e20 != ok { ret (out, Malformed) }
        var jj = 0usize
        while jj < k {
            var cq = 0usize
            while cq < fxs.pc {
                cf2[jj * fxs.pc + cq] = coef[cq] * fxs.des[jj * fxs.pc + cq]
                cq += 1usize
            }
            jj += 1usize
        }
        out.coef = cf2
        out.pc = fxs.pc
        out.des = fxs.des
        out.xs = fxs.xs
        out.df = dfp + f64(fxs.pc)
        if fam == 0usize { out.df += f64(fxs.ng) }
    }
    out.cluster = cl
    ret (out, ok)
}

// the earlier entry: x n by p column-major, cluster the 1-based start codes
fn gauss_em(a: *mem.Arena, x: []const f64, n: usize, p: usize, y: []const f64, cluster: []const f64, minprior: f64, tol: f64, iter_max: usize, famcode: usize, sz: []const f64) -> (Fm, err) {
    var k = 0usize
    var i = 0usize
    while i < n {
        if usize(cluster[i]) > k { k = usize(cluster[i]) }
        i += 1usize
    }
    let (p0, e1) = mem.alloc[f64](a, n * k)
    if e1 != ok { ret (zero, Malformed) }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < k {
            var v = 0.1f64
            if usize(cluster[i]) == j + 1usize { v = 0.9f64 }
            p0[i * k + j] = v
            j += 1usize
        }
        i += 1usize
    }
    var r0: rg.Rng = zero
    rg.seed(&r0, 1i64)
    var nofix: Fix = zero
    let (fo, fe) = flex_em(a, &r0, x, n, p, y, p0, k, minprior, tol, iter_max, famcode, sz, y, 0usize, &nofix)
    ret (fo, fe)
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
            mu[i] = (size[i] * yp[i] + 0.5f64) / (size[i] + 1.0f64)
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

// ---- the flexmix() call with its options: family, classification, start, concomitant variables ----

// start: 0 the cluster argument as 1-based codes (n values), 1 sample(seq_len(k), n, replace = TRUE) from r, 2 an n by k matrix of initial posteriors (row-major)
type Opt = struct { fam: usize, cls: usize, start: usize, minprior: f64, tol: f64, itermax: usize }

fn to_colmajor(a: *mem.Arena, xr: []const f64, n: usize, p: usize) -> ([]f64, err) {
    let (xc, e1) = mem.alloc[f64](a, n * p)
    if e1 != ok { ret (xc, Malformed) }
    var i = 0usize
    while i < n {
        var c = 0usize
        while c < p {
            xc[c * n + i] = xr[i * p + c]
            c += 1usize
        }
        i += 1usize
    }
    ret (xc, ok)
}

// x is n by p row-major, cx n by q row-major; the cluster in the result is 1-based
fn run(a: *mem.Arena, r: *rg.Rng, o: *const Opt, xr: []const f64, n: usize, p: usize, y: []const f64, sz: []const f64, k: usize, start: []const f64, cx: []const f64, q: usize) -> (Fm, err) {
    let (xc, e1) = to_colmajor(a, xr, n, p)
    let (p0, e2) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok { ret (zero, Malformed) }
    var i = 0usize
    if o.start == 1usize {
        let (cl, ce) = rg.sample_int(a, r, i64(k), i64(n), true)
        if ce != ok { ret (zero, ce) }
        while i < n {
            var j = 0usize
            while j < k {
                var v = 0.1f64
                if usize(cl[i]) == j + 1usize { v = 0.9f64 }
                p0[i * k + j] = v
                j += 1usize
            }
            i += 1usize
        }
    } else if o.start == 0usize {
        while i < n {
            var j = 0usize
            while j < k {
                var v = 0.1f64
                if usize(start[i]) == j + 1usize { v = 0.9f64 }
                p0[i * k + j] = v
                j += 1usize
            }
            i += 1usize
        }
    } else {
        while i < n * k {
            p0[i] = start[i]
            i += 1usize
        }
    }
    var nofix: Fix = zero
    let (f, fe) = flex_em(a, r, xc, n, p, y, p0, k, o.minprior, o.tol, o.itermax, o.fam + 10usize * o.cls, sz, cx, q, &nofix)
    ret (f, fe)
}

// stepFlexmix(k = k1:k2, nrep = nrep): per k, nrep random-start fits from the stream, the best by log-likelihood (the first of equals) kept; ll receives the
// (k2 - k1 + 1) by nrep log-likelihoods (NaN where a fit failed), models the best fit per k
fn step_all(a: *mem.Arena, r: *rg.Rng, o: *const Opt, xr: []const f64, n: usize, p: usize, y: []const f64, sz: []const f64, k1: usize, k2: usize, nrep: usize, cx: []const f64, q: usize, ll: []f64, models: []Fm) -> err {
    var oo = *o
    oo.start = 1usize
    var kk = k1
    while kk <= k2 {
        var best_ll = 0.0f64 - 1.0f64 / 0.0f64
        var got = false
        var m = 0usize
        while m < nrep {
            let (f, fe) = run(a, r, &oo, xr, n, p, y, sz, kk, y, cx, q)
            if fe != ok {
                ll[(kk - k1) * nrep + m] = 0.0f64 / 0.0f64
            } else {
                ll[(kk - k1) * nrep + m] = f.llh
                if f.llh > best_ll {
                    best_ll = f.llh
                    models[kk - k1] = f
                    got = true
                }
            }
            m += 1usize
        }
        if !got {
            var zm: Fm = zero
            models[kk - k1] = zm
        }
        kk += 1usize
    }
    ret ok
}

// initFlexmix(k = k1:k2, init = tol.em (0) / cem.em (1) / sem.em (2), nrep): the step-1 stepFlexmix with tolerance 1e-2 and that classification, then the
// default fit started from the posteriors of its best model
fn init_flex(a: *mem.Arena, r: *rg.Rng, o: *const Opt, xr: []const f64, n: usize, p: usize, y: []const f64, sz: []const f64, k1: usize, k2: usize, nrep: usize, method: usize, cx: []const f64, q: usize, ll: []f64, models: []Fm) -> err {
    var o1 = *o
    o1.tol = 0.01f64
    o1.cls = method
    let (s1, e1) = mem.alloc[Fm](a, k2 - k1 + 1usize)
    if e1 != ok { ret Malformed }
    let se = step_all(a, r, &o1, xr, n, p, y, sz, k1, k2, nrep, cx, q, ll, s1)
    if se != ok { ret se }
    var o2 = *o
    o2.start = 2usize
    var kk = k1
    while kk <= k2 {
        let b = s1[kk - k1]
        let (pst, e2) = mem.alloc[f64](a, n * b.k)
        if e2 != ok { ret Malformed }
        var i = 0usize
        while i < n {
            var j = 0usize
            while j < b.k {
                pst[i * b.k + j] = b.post[i * b.k0 + j]
                j += 1usize
            }
            i += 1usize
        }
        let (f, fe) = run(a, r, &o2, xr, n, p, y, sz, b.k, pst, cx, q)
        if fe != ok { ret fe }
        models[kk - k1] = f
        kk += 1usize
    }
    ret ok
}

// the log density of observation i under component j (the family's logLik, as flexmix evaluates it); x is column-major
fn comp_ld(f: *const Fm, fam: usize, x: []const f64, n: usize, p: usize, i: usize, j: usize, yi: f64, szi: f64) -> f64 {
    var mu = 0.0f64
    var c = 0usize
    while c < p {
        mu += x[c * n + i] * f.coef[j * p + c]
        c += 1usize
    }
    if fam == 1usize { ret nm.dpois(yi, math.exp[f64](mu), true) }
    if fam == 3usize { ret nm.dgamma(yi, f.sigma[j], (1.0f64 / mu) / f.sigma[j], true) }
    if fam == 2usize { ret nb.dbinom(yi, szi, 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - mu)), true) }
    ret dist.dnorm(yi, mu, f.sigma[j], true)
}

// predict() / fitted(): the n by k component means at the (row-major) design xr, in out (stride k)
fn comp_mean(f: *const Fm, fam: usize, xr: []const f64, n: usize, p: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < f.k {
            var mu = 0.0f64
            var c = 0usize
            while c < p {
                mu += xr[i * p + c] * f.coef[j * p + c]
                c += 1usize
            }
            var v = mu
            if fam == 1usize { v = math.exp[f64](mu) }
            if fam == 2usize { v = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - mu)) }
            if fam == 3usize { v = 1.0f64 / mu }
            out[i * f.k + j] = v
            j += 1usize
        }
        i += 1usize
    }
}

// prior(object, newdata): the n by k prior, from the concomitant model (exp of the linear predictor, normalised) or the constant prior
fn prior_new(f: *const Fm, cx: []const f64, n: usize, q: usize, out: []f64) {
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < f.k {
            if q > 0usize {
                var e = 0.0f64
                var c = 0usize
                while c < q {
                    e += cx[i * q + c] * f.conc[j * q + c]
                    c += 1usize
                }
                out[i * f.k + j] = math.exp[f64](e)
            } else {
                out[i * f.k + j] = f.prior[j]
            }
            s += out[i * f.k + j]
            j += 1usize
        }
        if q > 0usize {
            j = 0usize
            while j < f.k {
                out[i * f.k + j] = out[i * f.k + j] / s
                j += 1usize
            }
        }
        i += 1usize
    }
}

// posterior(object, newdata): rows are the scaled posteriors (unscaled false) or exp(log density + log prior) (true); logLik(object, newdata) lands in ll[0]
fn post_new(a: *mem.Arena, f: *const Fm, fam: usize, xr: []const f64, n: usize, p: usize, y: []const f64, sz: []const f64, cx: []const f64, q: usize, unscaled: bool, out: []f64, ll: []f64) -> err {
    let (xc, e1) = to_colmajor(a, xr, n, p)
    let (pr, e2) = mem.alloc[f64](a, n * f.k)
    let (lv, e3) = mem.alloc[f64](a, f.k)
    if e1 != ok || e2 != ok || e3 != ok { ret Malformed }
    prior_new(f, cx, n, q, pr)
    var tot = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        var rs = 0.0f64
        while j < f.k {
            lv[j] = comp_ld(f, fam, xc, n, p, i, j, y[i], sz[i]) + math.log[f64](pr[i * f.k + j])
            rs += math.exp[f64](lv[j])
            j += 1usize
        }
        tot += math.log[f64](rs)
        let ls = lse(lv, 0usize, f.k)
        j = 0usize
        while j < f.k {
            if unscaled { out[i * f.k + j] = math.exp[f64](lv[j]) } else { out[i * f.k + j] = math.exp[f64](lv[j] - ls) }
            j += 1usize
        }
        i += 1usize
    }
    ll[0usize] = tot
    ret ok
}

// R's order() on k values, ascending, ties by index
fn order_k(v: []const f64, k: usize, perm: []usize) {
    var i = 0usize
    while i < k {
        perm[i] = i
        i += 1usize
    }
    i = 1usize
    while i < k {
        let pv = perm[i]
        var j = i
        while j > 0usize && v[perm[j - 1usize]] > v[pv] {
            perm[j] = perm[j - 1usize]
            j -= 1usize
        }
        perm[j] = pv
        i += 1usize
    }
}

// relabel(object, by): by 0 = "prior", 1 = "model" ordering by parameter row idx (coef columns, then sigma), 2 = "concomitant" row idx, 3 the explicit
// permutation in key; the components are reordered by perm = order(...). Prior, coef, sigma, post columns, the cluster codes and the concomitant
// coefficients (swept so that the first column is zero) follow.
fn relabel(a: *mem.Arena, f: *const Fm, by: usize, idx: usize, key3: []const f64, p: usize, q: usize, n: usize) -> (Fm, err) {
    let k = f.k
    let (key, e1) = mem.alloc[f64](a, k)
    let (perm, e2) = mem.alloc[usize](a, k)
    let (inv, e3) = mem.alloc[usize](a, k)
    if e1 != ok || e2 != ok || e3 != ok { ret (zero, Malformed) }
    var j = 0usize
    while j < k {
        if by == 0usize { key[j] = f.prior[j] }
        if by == 1usize {
            if idx < p { key[j] = f.coef[j * p + idx] } else { key[j] = f.sigma[j] }
        }
        if by == 2usize { key[j] = f.conc[j * q + idx] }
        j += 1usize
    }
    if by == 3usize {
        j = 0usize
        while j < k {
            perm[j] = usize(key3[j]) - 1usize
            j += 1usize
        }
    } else {
        order_k(key, k, perm)
    }
    j = 0usize
    while j < k {
        inv[perm[j]] = j
        j += 1usize
    }
    var g = *f
    let (pr, e4) = mem.alloc[f64](a, k)
    let (co, e5) = mem.alloc[f64](a, f.k0 * p)
    let (sg, e6) = mem.alloc[f64](a, f.k0)
    let (po, e7) = mem.alloc[f64](a, n * f.k0)
    let (cl, e8) = mem.alloc[usize](a, n)
    let (cc, e9) = mem.alloc[f64](a, f.k0 * (q + 1usize))
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (zero, Malformed) }
    j = 0usize
    while j < k {
        pr[j] = f.prior[perm[j]]
        sg[j] = f.sigma[perm[j]]
        var c = 0usize
        while c < p {
            co[j * p + c] = f.coef[perm[j] * p + c]
            c += 1usize
        }
        c = 0usize
        while c < q {
            cc[j * q + c] = f.conc[perm[j] * q + c] - f.conc[perm[0usize] * q + c]
            c += 1usize
        }
        var i = 0usize
        while i < n {
            po[i * f.k0 + j] = f.post[i * f.k0 + perm[j]]
            i += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < n {
        cl[i] = inv[f.cluster[i] - 1usize] + 1usize
        i += 1usize
    }
    g.prior = pr
    g.coef = co
    g.sigma = sg
    g.post = po
    g.cluster = cl
    g.conc = cc
    ret (g, ok)
}

// digamma by recurrence up to 12 and the asymptotic series
fn digam(x0: f64) -> f64 {
    var x = x0
    var r = 0.0f64
    while x < 12.0f64 {
        r -= 1.0f64 / x
        x += 1.0f64
    }
    let f = 1.0f64 / (x * x)
    let t = f * (0.0f64 - 1.0f64 / 12.0f64 + f * (1.0f64 / 120.0f64 + f * (0.0f64 - 1.0f64 / 252.0f64 + f * (1.0f64 / 240.0f64 + f * (0.0f64 - 1.0f64 / 132.0f64 + f * (691.0f64 / 32760.0f64 + f * (0.0f64 - 1.0f64 / 12.0f64)))))))
    ret r + math.log[f64](x) - 0.5f64 / x + t
}

// KLdiv(object) with method "continuous" for the glm drivers: the k by k matrix (row-major) of divergences summed over the observations, from the fitted means
fn kldiv_cont(a: *mem.Arena, f: *const Fm, fam: usize, xr: []const f64, n: usize, p: usize, out: []f64) -> err {
    let k = f.k
    let (mu, e1) = mem.alloc[f64](a, n * k)
    if e1 != ok { ret Malformed }
    comp_mean(f, fam, xr, n, p, mu)
    var kk = 0usize
    while kk < k {
        var l = 0usize
        while l < k {
            var s = 0.0f64
            if kk != l {
                var i = 0usize
                while i < n {
                    let mk = mu[i * k + kk]
                    let ml = mu[i * k + l]
                    if fam == 0usize {
                        let sk = f.sigma[kk]
                        let sl = f.sigma[l]
                        s += math.log[f64](sl) - math.log[f64](sk) + 0.5f64 * (0.0f64 - 1.0f64 + (sk * sk + (mk - ml) * (mk - ml)) / (sl * sl))
                    } else if fam == 2usize {
                        s += mk * math.log[f64](mk / ml) + (1.0f64 - mk) * math.log[f64]((1.0f64 - mk) / (1.0f64 - ml))
                    } else if fam == 1usize {
                        s += mk * math.log[f64](mk / ml) + ml - mk
                    } else {
                        // R's z[k, l] for the Gamma family
                        let shk = f.sigma[kk]
                        let shl = f.sigma[l]
                        let xx = mk * shl / ml / shk
                        s += nm.lgammafn(shl) - nm.lgammafn(shk) + shl * math.log[f64](xx) - shk * (1.0f64 - 1.0f64 / xx) + (shk - shl) * digam(shk)
                    }
                    i += 1usize
                }
            }
            out[kk * k + l] = s
            l += 1usize
        }
        kk += 1usize
    }
    ret ok
}

// the matrix method of KLdiv on the posteriors: values under eps raised to eps, columns scaled to sum one, NaN for a pair without overlap
fn kldiv_disc(f: *const Fm, n: usize, out: []f64) {
    let k = f.k
    let eps = 0.0001f64
    var i = 0usize
    var cs: [16]f64 = zero
    while i < n {
        var j = 0usize
        while j < k {
            var v = f.post[i * f.k0 + j]
            if v < eps { v = eps }
            cs[j] += v
            j += 1usize
        }
        i += 1usize
    }
    var kk = 0usize
    while kk < k {
        var l = 0usize
        while l < k {
            var s = 0.0f64
            var any = false
            i = 0usize
            while i < n {
                var vk = f.post[i * f.k0 + kk]
                var vl = f.post[i * f.k0 + l]
                if vk < eps { vk = eps }
                if vl < eps { vl = eps }
                vk = vk / cs[kk]
                vl = vl / cs[l]
                if vk > eps && vl > eps { any = true }
                s += vk * (math.log[f64](vk) - math.log[f64](vl))
                i += 1usize
            }
            if kk == l { s = 0.0f64 } else if !any { s = 0.0f64 / 0.0f64 }
            out[kk * k + l] = s
            l += 1usize
        }
        kk += 1usize
    }
}

// ---- FLXMRglmfix: fixed, nested and varying coefficients, one joint weighted fit over the components stacked ----

// xs is the stacked design, column-major with nr = k * n rows (component block m holds rows m * n .. m * n + n - 1) and pc columns; des is the k by pc incidence (row-major,
// 1 where component m uses column c); vg holds the sizes of the ng variance groups (consecutive components sharing one sigma)
type Fix = struct { on: bool, pc: usize, xs: []f64, des: []f64, vg: []usize, ng: usize }

// the joint M step: glm.fit (or lm.wfit) over the stacked rows with the posteriors as weights, no start values; beta (pc values) is the coefficient vector and sigma gets
// the per component sigma (Gaussian, by variance group: weighted residual sum of squares over its rows / (rows - coefficients of the group's row of the incidence))
// or the Gamma shape
fn fix_mstep(a: *mem.Arena, fxs: *const Fix, post: []const f64, k0: usize, k: usize, n: usize, y: []const f64, sz: []const f64, fam: usize, beta: []f64, sigma: []f64) -> err {
    let nr = k * n
    let pc = fxs.pc
    let (w, e1) = mem.alloc[f64](a, nr)
    let (ys, e2) = mem.alloc[f64](a, nr)
    let (zs, e3) = mem.alloc[f64](a, nr)
    if e1 != ok || e2 != ok || e3 != ok { ret Malformed }
    var m = 0usize
    while m < k {
        var i = 0usize
        while i < n {
            w[m * n + i] = post[i * k0 + m]
            ys[m * n + i] = y[i]
            zs[m * n + i] = sz[i]
            i += 1usize
        }
        m += 1usize
    }
    if fam == 0usize {
        let (xw, e4) = mem.alloc[f64](a, nr * pc)
        let (yw, e5) = mem.alloc[f64](a, nr)
        if e4 != ok || e5 != ok { ret Malformed }
        var r = 0usize
        while r < nr {
            let sq = math.sqrt[f64](w[r])
            yw[r] = sq * ys[r]
            var c = 0usize
            while c < pc {
                xw[c * nr + r] = sq * fxs.xs[c * nr + r]
                c += 1usize
            }
            r += 1usize
        }
        let (f, fe) = ols.fit_tol(a, xw, nr, pc, yw, 0.0000001f64)
        if fe != ok { ret fe }
        var c = 0usize
        while c < pc {
            beta[c] = f.coef[c]
            c += 1usize
        }
        var cum = 0usize
        var g = 0usize
        while g < fxs.ng {
            let lo = cum * n
            let len = fxs.vg[g] * n
            var mw = 0.0f64
            r = 0usize
            while r < len {
                mw += w[lo + r]
                r += 1usize
            }
            mw = mw / f64(len)
            var s = 0.0f64
            r = 0usize
            while r < len {
                var res = ys[lo + r]
                var cc = 0usize
                while cc < pc {
                    res -= fxs.xs[cc * nr + lo + r] * beta[cc]
                    cc += 1usize
                }
                s += w[lo + r] * res * res / mw
                r += 1usize
            }
            let nc = inc_row_sum(fxs, g)
            let sg = math.sqrt[f64](s / (f64(len) - nc))
            var u = 0usize
            while u < fxs.vg[g] {
                sigma[cum + u] = sg
                u += 1usize
            }
            cum += fxs.vg[g]
            g += 1usize
        }
        ret ok
    }
    var ge = ok
    let (dv, e6) = mem.alloc[f64](a, 1usize)
    if e6 != ok { ret Malformed }
    if fam == 1usize {
        ge = pois_glm(a, fxs.xs, nr, pc, ys, w, beta, false)
    } else if fam == 2usize {
        ge = binom_glm(a, fxs.xs, nr, pc, ys, zs, w, beta, false)
    } else {
        ge = gamma_glm(a, fxs.xs, nr, pc, ys, w, beta, false, dv)
    }
    if ge != ok { ret ge }
    var sw = 0.0f64
    var r2 = 0usize
    while r2 < nr {
        sw += w[r2]
        r2 += 1usize
    }
    var u = 0usize
    while u < k {
        sigma[u] = 1.0f64
        if fam == 3usize { sigma[u] = sw / dv[0usize] }
        u += 1usize
    }
    ret ok
}

// the sum of row g of the incidence (R's incidence[i, ] with i the variance group)
fn inc_row_sum(fxs: *const Fix, g: usize) -> f64 {
    var s = 0.0f64
    var c = 0usize
    while c < fxs.pc {
        s += fxs.des[g * fxs.pc + c]
        c += 1usize
    }
    ret s
}

// FLXremoveComponent: drop the components not in kidx (the first keep entries are kept, ascending, of kold), their rows of the stacked design, the columns no kept
// component uses, and shrink the variance groups
fn fix_remove(a: *mem.Arena, fxs: *Fix, kidx: []const usize, keep: usize, kold: usize, n: usize) -> err {
    let pc = fxs.pc
    let nro = kold * n
    let nrn = keep * n
    // columns still used by a kept component
    let (cuse, e1) = mem.alloc[usize](a, pc)
    if e1 != ok { ret Malformed }
    var c = 0usize
    var pc2 = 0usize
    while c < pc {
        var s = 0.0f64
        var m = 0usize
        while m < keep {
            s += fxs.des[kidx[m] * pc + c]
            m += 1usize
        }
        if s > 0.0f64 {
            cuse[pc2] = c
            pc2 += 1usize
        }
        c += 1usize
    }
    let (nx, e2) = mem.alloc[f64](a, nrn * pc2)
    let (nd, e3) = mem.alloc[f64](a, keep * pc2)
    if e2 != ok || e3 != ok { ret Malformed }
    var m2 = 0usize
    while m2 < keep {
        var cc = 0usize
        while cc < pc2 {
            nd[m2 * pc2 + cc] = fxs.des[kidx[m2] * pc + cuse[cc]]
            var i = 0usize
            while i < n {
                nx[cc * nrn + m2 * n + i] = fxs.xs[cuse[cc] * nro + kidx[m2] * n + i]
                i += 1usize
            }
            cc += 1usize
        }
        m2 += 1usize
    }
    // variance groups: count the kept components per group, drop empty ones
    var ng2 = 0usize
    var lo = 0usize
    var g = 0usize
    while g < fxs.ng {
        let hi = lo + fxs.vg[g]
        var cnt = 0usize
        var m3 = 0usize
        while m3 < keep {
            if kidx[m3] >= lo && kidx[m3] < hi { cnt += 1usize }
            m3 += 1usize
        }
        if cnt > 0usize {
            fxs.vg[ng2] = cnt
            ng2 += 1usize
        }
        lo = hi
        g += 1usize
    }
    var i2 = 0usize
    while i2 < nrn * pc2 {
        fxs.xs[i2] = nx[i2]
        i2 += 1usize
    }
    i2 = 0usize
    while i2 < keep * pc2 {
        fxs.des[i2] = nd[i2]
        i2 += 1usize
    }
    fxs.pc = pc2
    fxs.ng = ng2
    ret ok
}

// flexmix(y ~ random, model = FLXMRglmfix(fixed = ~ fixed, nested = list(k = gsz, formula = ...), varFix = ...)): the columns of the n by p design xr that are random
// (rmask, one coefficient per component), fixed (fmask, shared) and nested (gmask[l] for the gsz[l] consecutive components of group l, ng groups); vmode 0 one sigma
// per component, 1 one common sigma, 2 the variance groups of sizes vsz. The stacked design is fixed columns, then nested columns, then the random columns of
// component 1, 2, ...; start and options as in run.
fn run_fix(a: *mem.Arena, r: *rg.Rng, o: *const Opt, xr: []const f64, n: usize, p: usize, y: []const f64, sz: []const f64, k: usize, start: []const f64, cx: []const f64, q: usize, rmask: usize, fmask: usize, ng: usize, gsz: []const f64, gmask: []const f64, vmode: usize, vsz: []const f64) -> (Fm, err) {
    var nf = 0usize
    var nr = 0usize
    var c = 0usize
    while c < p {
        if (fmask >> c) & 1usize == 1usize { nf += 1usize }
        if (rmask >> c) & 1usize == 1usize { nr += 1usize }
        c += 1usize
    }
    var nn_ = 0usize
    var l = 0usize
    while l < ng {
        c = 0usize
        while c < p {
            if (usize(gmask[l]) >> c) & 1usize == 1usize { nn_ += 1usize }
            c += 1usize
        }
        l += 1usize
    }
    let pc = nf + nn_ + k * nr
    let nrows = k * n
    let (xs, e1) = mem.alloc[f64](a, nrows * pc)
    let (des, e2) = mem.alloc[f64](a, k * pc)
    let (vg, e3) = mem.alloc[usize](a, k)
    let (src, e4) = mem.alloc[usize](a, pc)
    let (p0, e5) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (zero, Malformed) }
    var zi = 0usize
    while zi < nrows * pc {
        xs[zi] = 0.0f64
        zi += 1usize
    }
    zi = 0usize
    while zi < k * pc {
        des[zi] = 0.0f64
        zi += 1usize
    }
    var col = 0usize
    var m = 0usize
    c = 0usize
    while c < p {
        if (fmask >> c) & 1usize == 1usize {
            m = 0usize
            while m < k {
                des[m * pc + col] = 1.0f64
                m += 1usize
            }
            src[col] = c
            col += 1usize
        }
        c += 1usize
    }
    var cum = 0usize
    l = 0usize
    while l < ng {
        c = 0usize
        while c < p {
            if (usize(gmask[l]) >> c) & 1usize == 1usize {
                m = cum
                while m < cum + usize(gsz[l]) {
                    des[m * pc + col] = 1.0f64
                    m += 1usize
                }
                src[col] = c
                col += 1usize
            }
            c += 1usize
        }
        cum += usize(gsz[l])
        l += 1usize
    }
    m = 0usize
    while m < k {
        c = 0usize
        while c < p {
            if (rmask >> c) & 1usize == 1usize {
                des[m * pc + col] = 1.0f64
                src[col] = c
                col += 1usize
            }
            c += 1usize
        }
        m += 1usize
    }
    var i = 0usize
    while i < n {
        m = 0usize
        while m < k {
            c = 0usize
            while c < pc {
                xs[c * nrows + m * n + i] = des[m * pc + c] * xr[i * p + src[c]]
                c += 1usize
            }
            m += 1usize
        }
        i += 1usize
    }
    var ngv = k
    if vmode == 0usize {
        m = 0usize
        while m < k {
            vg[m] = 1usize
            m += 1usize
        }
    } else if vmode == 1usize {
        vg[0usize] = k
        ngv = 1usize
    } else {
        ngv = 0usize
        while ngv < 3usize && vsz[ngv] > 0.0f64 {
            vg[ngv] = usize(vsz[ngv])
            ngv += 1usize
        }
    }
    if o.start == 1usize {
        let (cl, ce) = rg.sample_int(a, r, i64(k), i64(n), true)
        if ce != ok { ret (zero, ce) }
        i = 0usize
        while i < n {
            m = 0usize
            while m < k {
                var v = 0.1f64
                if usize(cl[i]) == m + 1usize { v = 0.9f64 }
                p0[i * k + m] = v
                m += 1usize
            }
            i += 1usize
        }
    } else {
        i = 0usize
        while i < n {
            m = 0usize
            while m < k {
                var v = 0.1f64
                if usize(start[i]) == m + 1usize { v = 0.9f64 }
                p0[i * k + m] = v
                m += 1usize
            }
            i += 1usize
        }
    }
    var fxs = Fix { on: true, pc: pc, xs: xs, des: des, vg: vg, ng: ngv }
    let (f, fe) = flex_em(a, r, xs, n, pc, y, p0, k, o.minprior, o.tol, o.itermax, o.fam + 10usize * o.cls, sz, cx, q, &fxs)
    ret (f, fe)
}

// stepFlexmix over k = k1:k2 for a FLXMRglmfix model whose random / fixed columns do not depend on k (no nested groups); see step_all
fn step_fix(a: *mem.Arena, r: *rg.Rng, o: *const Opt, xr: []const f64, n: usize, p: usize, y: []const f64, sz: []const f64, k1: usize, k2: usize, nrep: usize, cx: []const f64, q: usize, rmask: usize, fmask: usize, vmode: usize, ll: []f64, models: []Fm) -> err {
    var oo = *o
    oo.start = 1usize
    var zero_sz: [3]f64 = zero
    var kk = k1
    while kk <= k2 {
        var best_ll = 0.0f64 - 1.0f64 / 0.0f64
        var got = false
        var m = 0usize
        while m < nrep {
            let (f, fe) = run_fix(a, r, &oo, xr, n, p, y, sz, kk, y, cx, q, rmask, fmask, 0usize, zero_sz[0usize..3usize], zero_sz[0usize..3usize], vmode, zero_sz[0usize..3usize])
            if fe != ok {
                ll[(kk - k1) * nrep + m] = 0.0f64 / 0.0f64
            } else {
                ll[(kk - k1) * nrep + m] = f.llh
                if f.llh > best_ll {
                    best_ll = f.llh
                    models[kk - k1] = f
                    got = true
                }
            }
            m += 1usize
        }
        if !got {
            var zm: Fm = zero
            models[kk - k1] = zm
        }
        kk += 1usize
    }
    ret ok
}
