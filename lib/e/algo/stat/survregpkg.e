// R survival::survreg for right-censored data: accelerated failure time models by maximum likelihood on the (log) time scale, the distributions weibull (code 0), exponential (1, scale fixed at 1),
// lognormal (2), loglogistic (3), gaussian (4, identity link), logistic (5, identity) and extreme (6, identity). Newton's method from a Nelder-Mead start on numerical derivatives of the
// log-likelihood; the standard errors come from the inverse observed information.
//
// Not here: interval and left censoring, strata(), weights, offsets, frailty, the other survreg distributions and user-defined ones.

use e.algo.stat.rnm as rn
use e.algo.stat.quantreg as qr
use e.math
use e.math.dist as dist
use e.mem

error Singular

// log density and log survival of the standardised error for the distribution family (0 extreme-value shape: weibull, exponential, extreme; 1 gaussian: lognormal, gaussian; 2 logistic: loglogistic, logistic)
fn lf(z: f64, fam: usize) -> f64 {
    if fam == 0usize { ret z - math.exp[f64](z) }
    if fam == 1usize { ret dist.dnorm(z, 0.0f64, 1.0f64, true) }
    ret z - 2.0f64 * math.log[f64](1.0f64 + math.exp[f64](z))
}

fn ls(z: f64, fam: usize) -> f64 {
    if fam == 0usize { ret 0.0f64 - math.exp[f64](z) }
    if fam == 1usize { ret dist.pnorm(z, 0.0f64, 1.0f64, false, true) }
    ret 0.0f64 - math.log[f64](1.0f64 + math.exp[f64](z))
}

type SrCtx = struct { time: []const f64, status: []const f64, x: []const f64, n: usize, p: usize, fam: usize, logt: bool, fixscale: bool }

// -log likelihood at par = (beta, log sigma) (the last entry is ignored when the scale is fixed)
fn sr_nll(c: *SrCtx, par: []const f64) -> f64 {
    var sg = 1.0f64
    if !c.fixscale { sg = math.exp[f64](par[c.p]) }
    var tot = 0.0f64
    var i = 0usize
    while i < c.n {
        var eta = 0.0f64
        var k = 0usize
        while k < c.p {
            eta += c.x[k * c.n + i] * par[k]
            k += 1usize
        }
        var y = c.time[i]
        if c.logt { y = math.log[f64](c.time[i]) }
        let z = (y - eta) / sg
        if c.status[i] != 0.0f64 {
            var jac = 0.0f64
            if c.logt { jac = math.log[f64](c.time[i]) }
            tot += lf(z, c.fam) - math.log[f64](sg) - jac
        } else {
            tot += ls(z, c.fam)
        }
        i += 1usize
    }
    ret 0.0f64 - tot
}

// out receives the p coefficients, the scale and the log-likelihood; se the p + 1 standard errors of (beta, log sigma) (the scale entry is the delta-method se of log sigma, as survreg's table gives)
fn survreg(a: *mem.Arena, time: []const f64, status: []const f64, x: []const f64, n: usize, p: usize, dcode: usize, out: []f64, se: []f64) -> err {
    var fam = 0usize
    if dcode == 2usize || dcode == 4usize { fam = 1usize }
    if dcode == 3usize || dcode == 5usize { fam = 2usize }
    let logt = dcode <= 3usize
    let fix = dcode == 1usize
    let np = p + 1usize
    var c = SrCtx{ time: time, status: status, x: x, n: n, p: p, fam: fam, logt: logt, fixscale: fix }
    let (start, e1) = mem.alloc[f64](a, np)
    let (best, e2) = mem.alloc[f64](a, np)
    let (g, e3) = mem.alloc[f64](a, np)
    let (h, e4) = mem.alloc[f64](a, np * np)
    let (step, e5) = mem.alloc[f64](a, np)
    let (pt, e6) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret e1 }
    // start: the intercept at the mean of y when the first column is 1, the others 0, scale 1
    var k = 0usize
    while k < np {
        start[k] = 0.0f64
        k += 1usize
    }
    var my = 0.0f64
    var i = 0usize
    while i < n {
        if logt { my += math.log[f64](time[i]) } else { my += time[i] }
        i += 1usize
    }
    start[0usize] = my / f64(n)
    var round = 0usize
    while round < 3usize {
        let (fmin, cnt, fail) = rn.nmmin[SrCtx](a, &c, sr_nll, start, 0.0f64 - 1.0f64 / 0.0f64, 1.0e-14f64, 1.0f64, 0.5f64, 2.0f64, 4000usize, 1.0f64, best)
        k = 0usize
        while k < np {
            start[k] = best[k]
            k += 1usize
        }
        round += 1usize
    }
    // Newton on central differences
    let nfree = np
    var it = 0usize
    while it < 20usize {
        let hh = 0.00001f64
        let f0 = sr_nll(&c, start)
        var a1 = 0usize
        while a1 < nfree {
            k = 0usize
            while k < np {
                pt[k] = start[k]
                k += 1usize
            }
            pt[a1] = start[a1] + hh
            let fp = sr_nll(&c, pt)
            pt[a1] = start[a1] - hh
            let fm = sr_nll(&c, pt)
            g[a1] = (fp - fm) / (2.0f64 * hh)
            h[a1 * np + a1] = (fp - 2.0f64 * f0 + fm) / (hh * hh)
            var b1 = a1 + 1usize
            while b1 < nfree {
                k = 0usize
                while k < np {
                    pt[k] = start[k]
                    k += 1usize
                }
                pt[a1] = start[a1] + hh
                pt[b1] = start[b1] + hh
                let fpp = sr_nll(&c, pt)
                pt[b1] = start[b1] - hh
                let fpm = sr_nll(&c, pt)
                pt[a1] = start[a1] - hh
                let fmm = sr_nll(&c, pt)
                pt[b1] = start[b1] + hh
                let fmp = sr_nll(&c, pt)
                let v = (fpp - fpm - fmp + fmm) / (4.0f64 * hh * hh)
                h[a1 * np + b1] = v
                h[b1 * np + a1] = v
                b1 += 1usize
            }
            a1 += 1usize
        }
        if fix {
            // the scale is not a parameter: pin its row and column
            g[p] = 0.0f64
            k = 0usize
            while k < np {
                h[p * np + k] = 0.0f64
                h[k * np + p] = 0.0f64
                k += 1usize
            }
            h[p * np + p] = 1.0f64
        }
        k = 0usize
        while k < np {
            step[k] = g[k]
            k += 1usize
        }
        if !qr.solve_dense(h, step, np) { ret Singular }
        var mx = 0.0f64
        k = 0usize
        while k < np {
            start[k] = start[k] - step[k]
            if math.abs[f64](step[k]) > mx { mx = math.abs[f64](step[k]) }
            k += 1usize
        }
        if mx < 1.0e-10f64 { break }
        it += 1usize
    }
    // the information at the optimum for the standard errors
    let hh2 = 0.00002f64
    let f0 = sr_nll(&c, start)
    var a2 = 0usize
    while a2 < np {
        var b2 = a2
        while b2 < np {
            if a2 == b2 {
                k = 0usize
                while k < np {
                    pt[k] = start[k]
                    k += 1usize
                }
                pt[a2] = start[a2] + hh2
                let fp = sr_nll(&c, pt)
                pt[a2] = start[a2] - hh2
                let fm = sr_nll(&c, pt)
                h[a2 * np + a2] = (fp - 2.0f64 * f0 + fm) / (hh2 * hh2)
            } else {
                k = 0usize
                while k < np {
                    pt[k] = start[k]
                    k += 1usize
                }
                pt[a2] = start[a2] + hh2
                pt[b2] = start[b2] + hh2
                let fpp = sr_nll(&c, pt)
                pt[b2] = start[b2] - hh2
                let fpm = sr_nll(&c, pt)
                pt[a2] = start[a2] - hh2
                let fmm = sr_nll(&c, pt)
                pt[b2] = start[b2] + hh2
                let fmp = sr_nll(&c, pt)
                let v = (fpp - fpm - fmp + fmm) / (4.0f64 * hh2 * hh2)
                h[a2 * np + b2] = v
                h[b2 * np + a2] = v
            }
            b2 += 1usize
        }
        a2 += 1usize
    }
    if fix {
        k = 0usize
        while k < np {
            h[p * np + k] = 0.0f64
            h[k * np + p] = 0.0f64
            k += 1usize
        }
        h[p * np + p] = 1.0f64
    }
    let (mat, e7) = mem.alloc[f64](a, np * np)
    if e7 != ok { ret e7 }
    var col = 0usize
    while col < np {
        k = 0usize
        while k < np * np {
            mat[k] = h[k]
            k += 1usize
        }
        k = 0usize
        while k < np {
            step[k] = 0.0f64
            k += 1usize
        }
        step[col] = 1.0f64
        if !qr.solve_dense(mat, step, np) { ret Singular }
        se[col] = math.sqrt[f64](step[col])
        col += 1usize
    }
    k = 0usize
    while k < p {
        out[k] = start[k]
        k += 1usize
    }
    if fix { out[p] = 1.0f64 } else { out[p] = math.exp[f64](start[p]) }
    out[p + 1usize] = 0.0f64 - sr_nll(&c, start)
    ret ok
}
