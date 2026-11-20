// R MCMCpack::MCMCordfactanal and MCMCirtKd (which is MCMCordfactanal on a differently signed prior): the ordinal data factor model by Gibbs
// sampling with the Cowles Metropolis step for the cut points, on the Scythe Mersenne-Twister stream. The default start values (the
// intercept-only probit or polr fit per manifest variable) are in ord_start.

use e.algo.stat.masspolr as mp
use e.algo.stat.mcmcpackdraw as md
use e.algo.stat.mcmcpackfa as mf
use e.algo.stat.mcmcpackord as mo
use e.algo.stat.mcmcpacksamp as ms
use e.math
use e.math.dist as dist
use e.mem

// R's start values for lam (kn by d, d = factors + 1) and gm (the cut points, (maxc + 1) by kn row-major), from the constraints and the intercept-only fits.
// x is n by kn with 1-based categories and -999 for missing; ncat[j] is the number of categories of column j.
fn ord_start(a: *mem.Arena, x: []const f64, n: usize, kn: usize, d: usize, ncat: []const f64, maxc: usize, lam_eq: []const f64, lam_ineq: []const f64, lam: []f64, gm: []f64) -> err {
    var i = 0usize
    while i < kn {
        let mark = mem.mark(a)
        let nc = usize(ncat[i])
        var np = 0usize
        var n2 = 0usize
        var t = 0usize
        while t < n {
            if x[t * kn + i] != -999.0f64 {
                np += 1usize
                if x[t * kn + i] == 2.0f64 { n2 += 1usize }
            }
            t += 1usize
        }
        var zeta0 = 0.0f64
        var probit0 = 0.0f64
        let (y, e1) = mem.alloc[f64](a, np + 1usize)
        let (wt, e2) = mem.alloc[f64](a, np + 1usize)
        let (off, e3) = mem.alloc[f64](a, np + 1usize)
        if e1 != ok { ret e1 }
        if e2 != ok { ret e2 }
        if e3 != ok { ret e3 }
        if nc > 2usize {
            var q = 0usize
            t = 0usize
            while t < n {
                if x[t * kn + i] != -999.0f64 {
                    y[q] = x[t * kn + i]
                    wt[q] = 1.0f64
                    off[q] = 0.0f64
                    q += 1usize
                }
                t += 1usize
            }
            let (fit, ep) = mp.polr(a, y[0usize..0usize], np, 0usize, y[0usize..np], nc, wt[0usize..np], off[0usize..np], 0usize, false, y[0usize..0usize], false)
            if ep != ok { ret ep }
            zeta0 = fit.zeta[0usize]
            gm[0usize * kn + i] = -300.0f64
            gm[1usize * kn + i] = 0.0f64
            var r = 2usize
            while r < nc {
                gm[r * kn + i] = (fit.zeta[r - 1usize] - fit.zeta[0usize]) * 0.588f64
                r += 1usize
            }
            gm[nc * kn + i] = 300.0f64
        } else {
            gm[0usize * kn + i] = -300.0f64
            gm[1usize * kn + i] = 0.0f64
            gm[2usize * kn + i] = 300.0f64
            probit0 = dist.qnorm(f64(n2) / f64(np), 0.0f64, 1.0f64, true, false)
        }
        var j = 0usize
        while j < d {
            var v = 0.0f64
            if lam_eq[i * d + j] == -999.0f64 {
                if lam_ineq[i * d + j] == 0.0f64 {
                    if j == 0usize {
                        if nc == 2usize { v = probit0 }
                        if nc > 2usize { v = -1.0f64 * zeta0 * 0.588f64 }
                    }
                }
                if lam_ineq[i * d + j] > 0.0f64 { v = 1.0f64 }
                if lam_ineq[i * d + j] < 0.0f64 { v = -1.0f64 }
            } else { v = lam_eq[i * d + j] }
            lam[i * d + j] = v
            j += 1usize
        }
        mem.reset(a, mark)
        i += 1usize
    }
    ret ok
}

// out is nsamp rows of (Lambda[kn*d] when store_lambda, gamma[(maxc+1)*kn] row-major, phi[n*d] when scores)
fn ordfactanal(a: *mem.Arena, g: *ms.Sc, x: []const f64, n: usize, kn: usize, d: usize, ncat: []const f64, maxc: usize, tune: []const f64, lam0: []const f64, gm0: []const f64, lam_eq: []const f64, lam_ineq: []const f64, l0: []const f64, big_l0: []const f64, burnin: usize, mcmc: usize, thin: usize, store_lambda: bool, scores: bool, out: []f64) -> err {
    let nstore = mcmc / thin
    let (lam, e1) = mem.alloc[f64](a, kn * d)
    let (gm, e2) = mem.alloc[f64](a, (maxc + 1usize) * kn)
    let (gp, e3) = mem.alloc[f64](a, maxc + 1usize)
    let (phi, e4) = mem.alloc[f64](a, n * d)
    let (xs, e5) = mem.alloc[f64](a, n * kn)
    let (xm, e6) = mem.alloc[f64](a, kn)
    let (m1, e7) = mem.alloc[f64](a, d * d)
    let (pv, e8) = mem.alloc[f64](a, d * d)
    let (pc, e9) = mem.alloc[f64](a, d * d)
    let (zz, e10) = mem.alloc[f64](a, d)
    let (mu, e11) = mem.alloc[f64](a, d)
    let (rest, e12) = mem.alloc[f64](a, kn * d)
    let (pinv, e13) = mem.alloc[f64](a, kn)
    let (xi, e14) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    var i = 0usize
    var j = 0usize
    var t = 0usize
    while i < kn * d {
        lam[i] = lam0[i]
        i += 1usize
    }
    i = 0usize
    while i < (maxc + 1usize) * kn {
        gm[i] = gm0[i]
        i += 1usize
    }
    i = 0usize
    while i < kn {
        pinv[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        phi[i * d] = 1.0f64
        j = 1usize
        while j < d {
            phi[i * d + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    var ld = 0.0f64
    var width = (maxc + 1usize) * kn
    if store_lambda { width += kn * d }
    if scores { width += n * d }
    var count = 0usize
    var iter = 0usize
    while iter < burnin + mcmc {
        // latent data
        t = 0usize
        while t < n {
            j = 0usize
            while j < kn {
                var s = 0.0f64
                var q = 0usize
                while q < d {
                    s += lam[j * d + q] * phi[t * d + q]
                    q += 1usize
                }
                xm[j] = s
                j += 1usize
            }
            j = 0usize
            while j < kn {
                let xv = x[t * kn + j]
                if xv == -999.0f64 { xs[t * kn + j] = ms.sc_rnorm(g, xm[j], 1.0f64) } else {
                    let c = usize(xv)
                    xs[t * kn + j] = mo.rtnorm_combo(g, xm[j], 1.0f64, gm[(c - 1usize) * kn + j], gm[c * kn + j])
                }
                j += 1usize
            }
            t += 1usize
        }
        // scores (the first column of phi stays 1)
        let dr = d - 1usize
        if dr > 0usize {
            var p = 0usize
            while p < dr {
                var q = 0usize
                while q < dr {
                    var s = 0.0f64
                    if p == q { s = 1.0f64 }
                    var k = 0usize
                    while k < kn {
                        s += lam[k * d + 1usize + p] * lam[k * d + 1usize + q]
                        k += 1usize
                    }
                    m1[p * dr + q] = s
                    q += 1usize
                }
                p += 1usize
            }
            if ms.inv_pd(a, m1[0usize..dr * dr], dr, pv, &ld) != ok { ret ms.NotPd }
            if !ms.chol(pv, dr, pc) { ret ms.NotPd }
            t = 0usize
            while t < n {
                p = 0usize
                while p < dr {
                    var s = 0.0f64
                    var k = 0usize
                    while k < kn {
                        s += lam[k * d + 1usize + p] * (xs[t * kn + k] - lam[k * d])
                        k += 1usize
                    }
                    rest[p] = s
                    zz[p] = ms.sc_rnorm(g, 0.0f64, 1.0f64)
                    p += 1usize
                }
                p = 0usize
                while p < dr {
                    var s = 0.0f64
                    var q = 0usize
                    while q < dr {
                        s += pv[p * dr + q] * rest[q]
                        q += 1usize
                    }
                    mu[p] = s
                    p += 1usize
                }
                p = 0usize
                while p < dr {
                    var s = mu[p]
                    var q = 0usize
                    while q <= p {
                        s += pc[p * dr + q] * zz[q]
                        q += 1usize
                    }
                    phi[t * d + 1usize + p] = s
                    p += 1usize
                }
                t += 1usize
            }
        }
        let el = mf.lambda_draw(a, g, lam, phi, xs, pinv, n, kn, d, lam_eq, lam_ineq, l0, big_l0)
        if el != ok { ret el }
        // cut points, one Cowles step per manifest variable
        j = 0usize
        while j < kn {
            let nc = usize(ncat[j])
            let tv = tune[j] * tune[j]
            var r = 0usize
            while r <= maxc {
                gp[r] = gm[r * kn + j]
                r += 1usize
            }
            t = 0usize
            while t < n {
                var s = 0.0f64
                var q = 0usize
                while q < d {
                    s += phi[t * d + q] * lam[j * d + q]
                    q += 1usize
                }
                xi[t] = s
                t += 1usize
            }
            r = 2usize
            while r < nc {
                if r == nc - 1usize { gp[r] = md.rtbnorm_combo(g, gm[r * kn + j], tv, gp[r - 1usize]) } else { gp[r] = mo.rtnorm_combo(g, gm[r * kn + j], tv, gp[r - 1usize], gm[(r + 1usize) * kn + j]) }
                r += 1usize
            }
            var llr = 0.0f64
            t = 0usize
            while t < n {
                let xv = x[t * kn + j]
                if xv != -999.0f64 {
                    let c = usize(xv)
                    if c == nc {
                        llr = llr + math.log[f64](1.0f64 - mo.pn(gp[c - 1usize] - xi[t], 0.0f64, 1.0f64)) - math.log[f64](1.0f64 - mo.pn(gm[(c - 1usize) * kn + j] - xi[t], 0.0f64, 1.0f64))
                    } else {
                        if c == 1usize {
                            llr = llr + math.log[f64](mo.pn(gp[c] - xi[t], 0.0f64, 1.0f64)) - math.log[f64](mo.pn(gm[c * kn + j] - xi[t], 0.0f64, 1.0f64))
                        } else {
                            llr = llr + math.log[f64](mo.pn(gp[c] - xi[t], 0.0f64, 1.0f64) - mo.pn(gp[c - 1usize] - xi[t], 0.0f64, 1.0f64)) - math.log[f64](mo.pn(gm[c * kn + j] - xi[t], 0.0f64, 1.0f64) - mo.pn(gm[(c - 1usize) * kn + j] - xi[t], 0.0f64, 1.0f64))
                        }
                    }
                }
                t += 1usize
            }
            var lgr = 0.0f64
            r = 2usize
            while r < nc {
                lgr = lgr + math.log[f64](mo.pn(gm[(r + 1usize) * kn + j], gm[r * kn + j], tune[j]) - mo.pn(gp[r - 1usize], gm[r * kn + j], tune[j])) - math.log[f64](mo.pn(gp[r + 1usize], gp[r], tune[j]) - mo.pn(gm[(r - 1usize) * kn + j], gp[r], tune[j]))
                r += 1usize
            }
            if ms.sc_unif(g) <= math.exp[f64](llr + lgr) {
                r = 0usize
                var go = true
                while r <= maxc && go {
                    if gm[r * kn + j] == 300.0f64 { go = false } else {
                        gm[r * kn + j] = gp[r]
                        r += 1usize
                    }
                }
            }
            j += 1usize
        }
        if iter >= burnin && iter % thin == 0usize {
            var o = count * width
            if store_lambda {
                i = 0usize
                while i < kn * d {
                    out[o + i] = lam[i]
                    i += 1usize
                }
                o += kn * d
            }
            i = 0usize
            while i < (maxc + 1usize) * kn {
                out[o + i] = gm[i]
                i += 1usize
            }
            o += (maxc + 1usize) * kn
            if scores {
                i = 0usize
                while i < n * d {
                    out[o + i] = phi[i]
                    i += 1usize
                }
            }
            count += 1usize
        }
        iter += 1usize
    }
    ret ok
}
