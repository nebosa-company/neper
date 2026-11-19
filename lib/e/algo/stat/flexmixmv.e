// The EM fit of the R package flexmix for the multivariate clustering drivers FLXMCmvnorm (full or diagonal covariance, M step cov.wt) and FLXMCmvbinary
// (weighted column means) with the default multinomial prior, from a given start clustering (flexmix's cluster argument) or R's random start. Same loop as
// flexmixpkg: initial posteriors 0.9 / 0.1, prior = column means of the posteriors, components below minprior dropped, tolerance on the relative change of
// the log-likelihood.

use e.algo.rand.r as rg
use e.algo.rand.rdist as rd
use e.algo.stat.flexmixpkg as fx
use e.math.nmath as nm
use e.math
use e.mem

error Malformed

// center is k by d, cov is k by d by d (mvnorm), cluster is 0-based, post is n by k row-major
type Mv = struct { k: usize, iter: usize, llh: f64, prior: []f64, center: []f64, cov: []f64, post: []f64, cluster: []usize, clog: f64, df: f64, k0: usize }

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

// lower Cholesky factor of the d by d matrix s in l, returns false when not positive definite
fn chol(s: []const f64, l: []f64, d: usize) -> bool {
    var i = 0usize
    while i < d {
        var j = 0usize
        while j <= i {
            var t = s[i * d + j]
            var q = 0usize
            while q < j {
                t -= l[i * d + q] * l[j * d + q]
                q += 1usize
            }
            if i == j {
                if !(t > 0.0f64) { ret false }
                l[i * d + i] = math.sqrt[f64](t)
            } else {
                l[i * d + j] = t / l[j * d + j]
            }
            j += 1usize
        }
        i += 1usize
    }
    ret true
}

// log density of the row r (length d) under N(mu, cov) with the Cholesky factor l: the Mahalanobis term by forward substitution
fn mvn_ld(r: []const f64, mu: []const f64, l: []const f64, d: usize, z: []f64) -> f64 {
    var maha = 0.0f64
    var ld = 0.0f64
    var i = 0usize
    while i < d {
        var t = r[i] - mu[i]
        var q = 0usize
        while q < i {
            t -= l[i * d + q] * z[q]
            q += 1usize
        }
        z[i] = t / l[i * d + i]
        maha += z[i] * z[i]
        ld += math.log[f64](l[i * d + i])
        i += 1usize
    }
    ret 0.0f64 - 0.5f64 * (f64(d) * math.log[f64](2.0f64 * 3.14159265358979323846f64) + maha) - ld
}

// model 0 full mvnorm, 1 diagonal mvnorm, 2 mvbinary; y is n by d row-major; init is the 1-based start clustering
fn em(a: *mem.Arena, y: []const f64, n: usize, d: usize, init: []const f64, model: usize, minprior: f64, tol: f64, iter_max: usize) -> (Mv, err) {
    var r0: rg.Rng = zero
    rg.seed(&r0, 1i64)
    let (f, fe) = em_cls(a, &r0, y, n, d, init, model, 0usize, minprior, tol, iter_max)
    ret (f, fe)
}

// model 0 FLXMCmvnorm full, 1 diagonal (also FLXMCnorm1 for d = 1), 2 FLXMCmvbinary, 3 FLXMCmvpois; cls 0 weighted EM, 1 CEM, 2 SEM (draws from r)
fn em_cls(a: *mem.Arena, r: *rg.Rng, y: []const f64, n: usize, d: usize, init: []const f64, model: usize, cls: usize, minprior: f64, tol: f64, iter_max: usize) -> (Mv, err) {
    var out: Mv = zero
    var k = 0usize
    var i = 0usize
    while i < n {
        if usize(init[i]) > k { k = usize(init[i]) }
        i += 1usize
    }
    let k0 = k
    let (post, e1) = mem.alloc[f64](a, n * k0)
    let (lp, e2) = mem.alloc[f64](a, n * k0)
    let (prior, e3) = mem.alloc[f64](a, k0)
    let (cen, e4) = mem.alloc[f64](a, k0 * d)
    let (cv, e5) = mem.alloc[f64](a, k0 * d * d)
    let (ch, e6) = mem.alloc[f64](a, k0 * d * d)
    let (zz, e7) = mem.alloc[f64](a, d)
    let (cl, e8) = mem.alloc[usize](a, n)
    let (bad, e9) = mem.alloc[bool](a, k0)
    if e9 != ok { ret (out, Malformed) }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret (out, Malformed) }
    i = 0usize
    while i < n {
        var tot = 0.0f64
        var j = 0usize
        while j < k {
            var v = 0.1f64
            if usize(init[i]) == j + 1usize { v = 0.9f64 }
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
    var iter = 1usize
    while iter <= iter_max {
        if cls >= 1usize {
            var ci = 0usize
            while ci < n {
                var bj = 0usize
                if cls == 1usize {
                    bj = fx.row_argmax(post, ci, k0, k, r)
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
                if rs == 0.0f64 {
                    j = 0usize
                    while j < keep {
                        post[i * k0 + j] = prior[j]
                        j += 1usize
                    }
                    rs = 0.0f64
                    j = 0usize
                    while j < keep {
                        rs += post[i * k0 + j]
                        j += 1usize
                    }
                }
                j = 0usize
                while j < keep {
                    post[i * k0 + j] = post[i * k0 + j] / rs
                    j += 1usize
                }
                i += 1usize
            }
            k = keep
        }
        // M step
        j = 0usize
        while j < k {
            var sw = 0.0f64
            var sw2 = 0.0f64
            i = 0usize
            while i < n {
                sw += post[i * k0 + j]
                i += 1usize
            }
            var c = 0usize
            while c < d {
                var m = 0.0f64
                i = 0usize
                while i < n {
                    if model >= 2usize { m += post[i * k0 + j] * y[i * d + c] } else { m += post[i * k0 + j] / sw * y[i * d + c] }
                    i += 1usize
                }
                // binary and Poisson centres are colSums(w * y) / sum(w); cov.wt scales the weights first
                if model >= 2usize { m = m / sw }
                cen[j * d + c] = m
                c += 1usize
            }
            if model < 2usize {
                i = 0usize
                while i < n {
                    let wt = post[i * k0 + j] / sw
                    sw2 += wt * wt
                    i += 1usize
                }
                c = 0usize
                while c < d {
                    var c2 = 0usize
                    while c2 < d {
                        var s = 0.0f64
                        if model == 0usize || c == c2 {
                            i = 0usize
                            while i < n {
                                s += post[i * k0 + j] / sw * (y[i * d + c] - cen[j * d + c]) * (y[i * d + c2] - cen[j * d + c2])
                                i += 1usize
                            }
                            s = s / (1.0f64 - sw2)
                        }
                        cv[(j * d + c) * d + c2] = s
                        c2 += 1usize
                    }
                    c += 1usize
                }
                bad[j] = !chol(cv[j * d * d..(j + 1usize) * d * d], ch[j * d * d..(j + 1usize) * d * d], d)
            }
            j += 1usize
        }
        // E step
        i = 0usize
        while i < n {
            j = 0usize
            while j < k {
                var ld = 0.0f64
                if model < 2usize && bad[j] {
                    // mvtnorm::dmvnorm when chol(sigma) fails: -Inf everywhere except +Inf at the mean itself
                    var same = true
                    var c = 0usize
                    while c < d {
                        if y[i * d + c] != cen[j * d + c] { same = false }
                        c += 1usize
                    }
                    ld = 0.0f64 - 1.0f64 / 0.0f64
                    if same { ld = 1.0f64 / 0.0f64 }
                } else if model < 2usize {
                    ld = mvn_ld(y[i * d..(i + 1usize) * d], cen[j * d..(j + 1usize) * d], ch[j * d * d..(j + 1usize) * d * d], d, zz)
                } else if model == 3usize {
                    var c = 0usize
                    while c < d {
                        ld += nm.dpois(y[i * d + c], cen[j * d + c], true)
                        c += 1usize
                    }
                } else {
                    var c = 0usize
                    while c < d {
                        let pj = cen[j * d + c]
                        if y[i * d + c] > 0.5f64 { ld += math.log[f64](pj) } else { ld += math.log[f64](1.0f64 - pj) }
                        c += 1usize
                    }
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
        if llh != llh || llh - llh != 0.0f64 { ret (out, Malformed) }
        if math.abs[f64](llh - old) / (math.abs[f64](llh) + 0.1f64) < tol { break }
        iter += 1usize
    }
    if iter > iter_max { iter = iter_max }
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
    var clg = 0.0f64
    i = 0usize
    while i < n {
        let best = fx.row_argmax(post, i, k0, k, r)
        cl[i] = best
        clg += lp[i * k0 + best]
        i += 1usize
    }
    out.k = k
    out.iter = iter
    out.llh = llh
    out.prior = prior[0usize..k]
    out.center = cen
    out.cov = cv
    out.post = post
    out.k0 = k0
    out.cluster = cl
    out.clog = clg
    var dfc = f64(d)
    if model == 0usize { dfc = (3.0f64 * f64(d) + f64(d * d)) / 2.0f64 }
    if model == 1usize { dfc = 2.0f64 * f64(d) }
    out.df = f64(k - 1usize) + f64(k) * dfc
    ret (out, ok)
}

// the random start of flexmix(): sample(seq_len(k), n, replace = TRUE) on R's stream (1-based init codes for em_cls), classification cls
fn random_cls(a: *mem.Arena, r: *rg.Rng, y: []const f64, n: usize, d: usize, k: usize, model: usize, cls: usize, minprior: f64, tol: f64, iter_max: usize) -> (Mv, err) {
    let (cl, ce) = rg.sample_int(a, r, i64(k), i64(n), true)
    if ce != ok { ret (zero, ce) }
    let (init, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret (zero, Malformed) }
    var i = 0usize
    while i < n {
        init[i] = f64(cl[i])
        i += 1usize
    }
    let (f, fe) = em_cls(a, r, y, n, d, init, model, cls, minprior, tol, iter_max)
    ret (f, fe)
}

fn random(a: *mem.Arena, r: *rg.Rng, y: []const f64, n: usize, d: usize, k: usize, model: usize, minprior: f64, tol: f64, iter_max: usize) -> (Mv, err) {
    let (f, fe) = random_cls(a, r, y, n, d, k, model, 0usize, minprior, tol, iter_max)
    ret (f, fe)
}

// stepFlexmix(k = k1:k2, nrep) for the multivariate drivers: per k, nrep random starts from the stream and the best by log-likelihood; ll is (k2 - k1 + 1) by nrep
fn step_mv(a: *mem.Arena, r: *rg.Rng, y: []const f64, n: usize, d: usize, k1: usize, k2: usize, nrep: usize, model: usize, cls: usize, minprior: f64, tol: f64, iter_max: usize, ll: []f64, models: []Mv) -> err {
    var kk = k1
    while kk <= k2 {
        var best = 0.0f64 - 1.0f64 / 0.0f64
        var got = false
        var m = 0usize
        while m < nrep {
            let (f, fe) = random_cls(a, r, y, n, d, kk, model, cls, minprior, tol, iter_max)
            if fe != ok {
                ll[(kk - k1) * nrep + m] = 0.0f64 / 0.0f64
            } else {
                ll[(kk - k1) * nrep + m] = f.llh
                if f.llh > best {
                    best = f.llh
                    models[kk - k1] = f
                    got = true
                }
            }
            m += 1usize
        }
        if !got {
            var zm: Mv = zero
            models[kk - k1] = zm
        }
        kk += 1usize
    }
    ret ok
}

fn bic(f: *const Mv, n: usize) -> f64 { ret 0.0f64 - 2.0f64 * f.llh + f.df * math.log[f64](f64(n)) }
fn aic(f: *const Mv) -> f64 { ret 0.0f64 - 2.0f64 * f.llh + 2.0f64 * f.df }
fn icl(f: *const Mv, n: usize) -> f64 { ret 0.0f64 - 2.0f64 * f.clog + f.df * math.log[f64](f64(n)) }
