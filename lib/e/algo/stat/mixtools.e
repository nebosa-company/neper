// R mixtools: the EM fits of the package, value for value from its sources (mixtools 2.0.0.1):
//   normalmixEM    univariate normal mixture: random starting values as normalmix.init draws them, the EM or ECM loop,
//                  the C routine normpost for the posteriors, restarts when a variance collapses, arbmean/arbvar
//   mvnormalmixEM  multivariate normal mixture (arbmean/arbvar), random starts as mvnormalmix.init
//   regmixEM       mixture of linear regressions through lm (weighted least squares by dqrls), random starts as regmix.init
//   multmixEM      mixture of multinomials, C routine multinompost
//   npEM, spEMsymloc  in e.algo.stat.mixtools_np; boot.se in e.algo.stat.mixtools_boot
// Draws come from e.algo.rand.r in the order the package makes them. Matrices are row-major here (R's are column-major).
//
// Not here: the constraint strings of mean.constr/sd.constr (arbmean and arbvar select the constraint sets), fast = TRUE,
// the printing, and the other mixtools families (gamma, Weibull, Poisson and logistic regression, mixed effects, repeated measures).

use e.algo.rand.r as rg
use e.math
use e.math.special as special
use e.mem
use e.os

error NotConverged
error TooManyTries

fn buf(a: *mem.Arena, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n + 1usize {
        s[i] = 0.0f64
        i += 1usize
    }
    ret s[0usize..n]
}

fn ibuf(a: *mem.Arena, n: usize) -> []usize {
    let (s, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { os.exit(9) }
    var i = 0usize
    while i < n + 1usize {
        s[i] = 0usize
        i += 1usize
    }
    ret s[0usize..n]
}

// R's mean(): a long-double sum then a second pass; here a double sum and the same second pass
fn rmean(v: []const f64, from: usize, count: usize, stride: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < count {
        s += v[from + i * stride]
        i += 1usize
    }
    s = s / f64(count)
    var t = 0.0f64
    i = 0usize
    while i < count {
        t += v[from + i * stride] - s
        i += 1usize
    }
    ret s + t / f64(count)
}

// var(): the squared deviations from the mean over count - 1
fn rvar(v: []const f64, from: usize, count: usize, stride: usize) -> f64 {
    let m = rmean(v, from, count, stride)
    var s = 0.0f64
    var i = 0usize
    while i < count {
        let d = v[from + i * stride] - m
        s += d * d
        i += 1usize
    }
    ret s / f64(count - 1usize)
}

// stable ascending order of key (0-based indices)
fn order_of(a: *mem.Arena, key: []const f64) -> []usize {
    let n = key.len
    let idx = ibuf(a, n)
    var i = 0usize
    while i < n {
        var j = i
        while j > 0usize && key[idx[j - 1usize]] > key[i] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = i
        i += 1usize
    }
    ret idx
}

fn sorted_of(a: *mem.Arena, x: []const f64) -> []f64 {
    let o = order_of(a, x)
    let s = buf(a, x.len)
    var i = 0usize
    while i < x.len {
        s[i] = x[o[i]]
        i += 1usize
    }
    ret s
}

// the 1-based inclusive bin x[max(1, floor((j - 1) n / k)) : ceiling(j n / k)] as 0-based (from, count)
fn bin_of(n: usize, k: usize, j: usize) -> (usize, usize) {
    var lo = ((j - 1usize) * n) / k
    if lo < 1usize { lo = 1usize }
    var hi = (j * n + k - 1usize) / k
    ret (lo - 1usize, hi - lo + 1usize)
}

// --- normalmixEM

type Norm = struct { lambda: []f64, mu: []f64, sigma: []f64, scale: []f64, post: []f64, ll: []f64, loglik: f64, iter: usize, restarts: usize, k: usize, arbmean: bool, arbvar: bool }

type NormInit = struct { lambda: []f64, mu: []f64, s: []f64, k: usize, arbmean: bool, arbvar: bool }

// normalmix.init: an empty slice is NULL
fn normalmix_init(a: *mem.Arena, g: *rg.Rng, x: []const f64, lambda0: []const f64, mu0: []const f64, s0: []const f64, k0: usize, arbmean0: bool, arbvar0: bool) -> NormInit {
    var k = k0
    var arbmean = arbmean0
    var arbvar = arbvar0
    if s0.len > 0usize {
        arbvar = s0.len > 1usize
        if arbvar { k = s0.len }
    }
    if mu0.len > 0usize {
        arbmean = mu0.len > 1usize
        if arbmean { k = mu0.len }
    }
    let n = x.len
    let xs = sorted_of(a, x)
    var s = buf(a, k)
    var sl = s0.len
    var j = 0usize
    if s0.len == 0usize {
        let shyp = buf(a, k)
        j = 0usize
        while j < k {
            let (f, c) = bin_of(n, k, j + 1usize)
            shyp[j] = math.sqrt[f64](rvar(xs, f, c, 1usize))
            j += 1usize
        }
        j = 0usize
        while j < k {
            if shyp[j] == 0.0f64 { shyp[j] = rg.runif(g, 0.0f64, math.sqrt[f64](rvar(xs, 0usize, n, 1usize))) }
            j += 1usize
        }
        if arbvar {
            j = 0usize
            while j < k {
                s[j] = 1.0f64 / rg.rexp(g, 1.0f64 / shyp[j])
                j += 1usize
            }
            sl = k
        } else {
            s[0usize] = 1.0f64 / rg.rexp(g, 1.0f64 / rmean(shyp, 0usize, k, 1usize))
            sl = 1usize
        }
    } else {
        j = 0usize
        while j < s0.len {
            s[j] = s0[j]
            j += 1usize
        }
    }
    let mu = buf(a, k)
    var ml = mu0.len
    if mu0.len == 0usize {
        let muhyp = buf(a, k)
        j = 0usize
        while j < k {
            let (f, c) = bin_of(n, k, j + 1usize)
            muhyp[j] = rmean(xs, f, c, 1usize)
            j += 1usize
        }
        if arbmean {
            j = 0usize
            while j < k {
                var sj = s[0usize]
                if sl > 1usize { sj = s[j] }
                mu[j] = rg.rnorm(g, muhyp[j], sj)
                j += 1usize
            }
            ml = k
        } else {
            mu[0usize] = rg.rnorm(g, rmean(muhyp, 0usize, k, 1usize), rmean(s, 0usize, sl, 1usize))
            ml = 1usize
        }
    } else {
        j = 0usize
        while j < mu0.len {
            mu[j] = mu0[j]
            j += 1usize
        }
    }
    let lambda = buf(a, k)
    if lambda0.len == 0usize {
        var cond = true
        while cond {
            var tot = 0.0f64
            j = 0usize
            while j < k {
                lambda[j] = rg.runif(g, 0.0f64, 1.0f64)
                tot += lambda[j]
                j += 1usize
            }
            var mn = 2.0f64
            j = 0usize
            while j < k {
                lambda[j] = lambda[j] / tot
                if lambda[j] < mn { mn = lambda[j] }
                j += 1usize
            }
            cond = mn < 0.05f64
        }
    } else {
        var tot = 0.0f64
        j = 0usize
        while j < k {
            lambda[j] = lambda0[j % lambda0.len]
            tot += lambda[j]
            j += 1usize
        }
        j = 0usize
        while j < k {
            lambda[j] = lambda[j] / tot
            j += 1usize
        }
    }
    ret NormInit { lambda: lambda, mu: mu[0usize..ml], s: s[0usize..sl], k: k, arbmean: arbmean, arbvar: arbvar }
}

// C normpost: post and res2 (n by k, row-major), the log-likelihood
fn normpost(x: []const f64, mu: []const f64, sigma: []const f64, lambda: []const f64, n: usize, m: usize, res2: []f64, post: []f64, work: []f64) -> f64 {
    var loglik = 0.0f64 - f64(n) * 0.91893853320467274178f64
    let lsr = work[m..2usize * m]
    let llsr = work[2usize * m..3usize * m]
    var j = 0usize
    while j < m {
        lsr[j] = lambda[j] / sigma[j]
        llsr[j] = math.log[f64](lsr[j])
        j += 1usize
    }
    var i = 0usize
    while i < n {
        let xv = x[i]
        var minj = 0usize
        var mn = 0.0f64
        j = 0usize
        while j < m {
            var r = xv - mu[j]
            r = r * r
            res2[i * m + j] = r
            r = r / (2.0f64 * sigma[j] * sigma[j])
            work[j] = r
            if j == 0usize || r < mn {
                minj = j
                mn = r
            }
            j += 1usize
        }
        var rowsum = 1.0f64
        j = 0usize
        while j < m {
            if j == minj {
                work[j] = 1.0f64
            } else {
                work[j] = (lsr[j] / lsr[minj]) * math.exp[f64](mn - work[j])
                rowsum += work[j]
            }
            j += 1usize
        }
        j = 0usize
        while j < m {
            post[i * m + j] = work[j] / rowsum
            j += 1usize
        }
        loglik += math.log[f64](rowsum) - mn + llsr[minj]
        i += 1usize
    }
    ret loglik
}

// R sums in long double; a double-double accumulator stands in for it
type Acc = struct { hi: f64, lo: f64 }

fn acc_add(s: *Acc, v: f64) {
    let t = s.hi + v
    let bb = t - s.hi
    s.lo += (s.hi - (t - bb)) + (v - bb)
    s.hi = t
}

fn acc_val(s: Acc) -> f64 { ret s.hi + s.lo }

fn col_means(post: []const f64, n: usize, k: usize, out: []f64) {
    var j = 0usize
    while j < k {
        var s = Acc { hi: 0.0f64, lo: 0.0f64 }
        var i = 0usize
        while i < n {
            acc_add(&s, post[i * k + j])
            i += 1usize
        }
        out[j] = acc_val(s) / f64(n)
        j += 1usize
    }
}

fn order_vals(a: *mem.Arena, v: []const f64) -> []usize { ret order_of(a, v) }

// normalmixEM(x, lambda, mu, sigma, k, arbmean, arbvar, epsilon, maxit, maxrestarts) with the default (NULL) constraints:
// arbmean = FALSE gives every mean the same category and alpha 1, arbvar = FALSE the same for the deviations.
// An empty lambda0, mu0 or sigma0 is NULL (drawn at random).
fn normal_mix_em(a: *mem.Arena, g: *rg.Rng, x: []const f64, lambda0: []const f64, mu0: []const f64, sigma0: []const f64, k0: usize, arbmean0: bool, arbvar0: bool, epsilon: f64, maxit: usize, maxrestarts: usize) -> (Norm, err) {
    var empty: Norm = zero
    let n = x.len
    let t0 = normalmix_init(a, g, x, lambda0, mu0, sigma0, k0, arbmean0, arbvar0)
    let k = t0.k
    let arbmean = t0.arbmean
    let arbvar = t0.arbvar
    var lam = t0.lambda
    var mu = t0.mu
    var sg = t0.s
    // meancat is 1..k or all 1; sdcat likewise (category 0 never arises here)
    var ecm = false
    if !arbmean && k > 1usize { ecm = true }
    if arbvar && k > 1usize { ecm = true }
    var restarts = 0usize
    var notdone = true
    let post = buf(a, n * k)
    let res = buf(a, n * k)
    let work = buf(a, 3usize * k)
    let ll = buf(a, maxit + 2usize)
    var nll = 0usize
    let mur = buf(a, k)
    let sgr = buf(a, k)
    let lamk = buf(a, k)
    var obs = 0.0f64
    var iter = 0usize
    var first = true
    while notdone {
        notdone = false
        if !first {
            let ti = normalmix_init(a, g, x, lambda0[0usize..0usize], mu0[0usize..0usize], sigma0[0usize..0usize], k, arbmean, arbvar)
            lam = ti.lambda
            mu = ti.mu
            sg = ti.s
        }
        first = false
        var j = 0usize
        while j < k {
            mur[j] = mu[j % mu.len]
            sgr[j] = sg[j % sg.len]
            lamk[j] = lam[j]
            j += 1usize
        }
        var diff = epsilon + 1.0f64
        iter = 0usize
        obs = normpost(x, mur, sgr, lamk, n, k, res, post, work)
        nll = 0usize
        ll[nll] = obs
        nll += 1usize
        while diff > epsilon && iter < maxit {
            col_means(post, n, k, lamk)
            if arbmean {
                j = 0usize
                while j < k {
                    var sp = 0.0f64
                    var sx = 0.0f64
                    var i = 0usize
                    while i < n {
                        sp += post[i * k + j] * x[i]
                        i += 1usize
                    }
                    sx = sp
                    mur[j] = sx / (f64(n) * lamk[j])
                    j += 1usize
                }
            } else {
                // one category, alpha 1: tmp = post / sigma^2
                var num = 0.0f64
                var den = 0.0f64
                j = 0usize
                while j < k {
                    var i = 0usize
                    while i < n {
                        let t = post[i * k + j] / (sgr[j] * sgr[j])
                        num += t * x[i]
                        den += t
                        i += 1usize
                    }
                    j += 1usize
                }
                let m1 = num / den
                j = 0usize
                while j < k {
                    mur[j] = m1
                    j += 1usize
                }
            }
            if ecm {
                let _ = normpost(x, mur, sgr, lamk, n, k, res, post, work)
                col_means(post, n, k, lamk)
            }
            if arbvar {
                j = 0usize
                while j < k {
                    var sr = 0.0f64
                    var i = 0usize
                    while i < n {
                        sr += post[i * k + j] * res[i * k + j]
                        i += 1usize
                    }
                    sgr[j] = math.sqrt[f64](sr / (f64(n) * lamk[j]))
                    j += 1usize
                }
            } else {
                var sr = 0.0f64
                var sl = 0.0f64
                j = 0usize
                while j < k {
                    var i = 0usize
                    while i < n {
                        sr += post[i * k + j] * res[i * k + j]
                        i += 1usize
                    }
                    sl += lamk[j]
                    j += 1usize
                }
                let s1 = math.sqrt[f64](sr / (f64(n) * sl))
                j = 0usize
                while j < k {
                    sgr[j] = s1
                    j += 1usize
                }
            }
            var small = false
            j = 0usize
            while j < k {
                if sgr[j] < 0.00000001f64 { small = true }
                j += 1usize
            }
            if small {
                notdone = true
                restarts += 1usize
                if restarts > maxrestarts { ret (empty, TooManyTries) }
                break
            }
            let nobs = normpost(x, mur, sgr, lamk, n, k, res, post, work)
            diff = nobs - obs
            obs = nobs
            ll[nll] = obs
            nll += 1usize
            iter += 1usize
        }
    }
    var out = Norm { lambda: lamk, mu: mur, sigma: sgr, scale: sgr, post: post, ll: ll[0usize..nll], loglik: obs, iter: iter, restarts: restarts, k: k, arbmean: arbmean, arbvar: arbvar }
    if !arbmean {
        let ord = order_vals(a, sgr)
        let lam2 = buf(a, k)
        let sc = buf(a, k)
        let post2 = buf(a, n * k)
        let smin = sgr[ord[0usize]]
        var jj = 0usize
        while jj < k {
            lam2[jj] = lamk[ord[jj]]
            sc[jj] = sgr[ord[jj]] / smin
            var i = 0usize
            while i < n {
                post2[i * k + jj] = post[i * k + ord[jj]]
                i += 1usize
            }
            jj += 1usize
        }
        let mu1 = buf(a, 1usize)
        mu1[0usize] = mur[0usize]
        let sg1 = buf(a, 1usize)
        sg1[0usize] = smin
        out.lambda = lam2
        out.scale = sc
        out.post = post2
        out.mu = mur
        out.sigma = sg1
    }
    ret (out, ok)
}
