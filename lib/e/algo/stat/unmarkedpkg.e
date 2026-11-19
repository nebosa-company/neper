// unmarked::occu: single-season site occupancy with imperfect detection (MacKenzie et al.). Site i is occupied with probability psi_i = logistic(x_i' b) and an occupied site is detected on each of its J visits with probability
// p_i = logistic(z_i' a) (covariates constant over the visits of a site, no missing visits); the likelihood of the detection history y_i is psi_i prod p_i^y (1 - p_i)^(1 - y) + (1 - psi_i) [all y_i = 0], maximised by BFGS from zero.
//
// Not here: visit-level detection covariates and missing visits, other links, standard errors, the other unmarked models (colext, pcount, distsamp, occuRN), prediction, goodness of fit.

use e.math
use e.math.opt as opt
use e.math.nmath as nm
use e.mem
use e.algo.stat.numhess as nh

type OccCtx = struct { x: []const f64, z: []const f64, y: []const f64, m: usize, j: usize, p1: usize, p2: usize, q: []f64 }

fn lg(t: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t)) }

fn occ_f(c: *OccCtx, par: []const f64) -> f64 {
    var ll = 0.0f64
    // z holds either one row of detection covariates per site or one per visit (m j rows); a response below zero is a missing visit
    let visit = c.z.len == c.m * c.j * c.p2 && c.j > 1usize
    var i = 0usize
    while i < c.m {
        var e1 = 0.0f64
        var t = 0usize
        while t < c.p1 {
            e1 += c.x[i * c.p1 + t] * par[t]
            t += 1usize
        }
        let psi = lg(e1)
        var lk = psi
        var any = false
        var v = 0usize
        while v < c.j {
            let yv = c.y[i * c.j + v]
            if yv >= 0.0f64 {
                var row = i
                if visit { row = i * c.j + v }
                var e2 = 0.0f64
                t = 0usize
                while t < c.p2 {
                    e2 += c.z[row * c.p2 + t] * par[c.p1 + t]
                    t += 1usize
                }
                let p = lg(e2)
                if yv > 0.5f64 {
                    lk = lk * p
                    any = true
                } else {
                    lk = lk * (1.0f64 - p)
                }
            }
            v += 1usize
        }
        if !any { lk += 1.0f64 - psi }
        ll += math.log[f64](lk)
        i += 1usize
    }
    ret 0.0f64 - ll
}

fn occ_g(c: *OccCtx, par: []const f64, g: []f64) {
    let n = par.len
    var i = 0usize
    while i < n {
        c.q[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        let h = 1.0e-6f64
        c.q[i] = par[i] + h
        let fp = occ_f(c, c.q[0usize..n])
        c.q[i] = par[i] - h
        let fm = occ_f(c, c.q[0usize..n])
        c.q[i] = par[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// the fit to y (m sites by j visits, row-major 0/1) with occupancy design x (m by p1 with its intercept column) and detection design z (m by p2): out = the p1 occupancy coefficients, the p2 detection coefficients, the log-likelihood
fn occu(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, m: usize, j: usize, p1: usize, p2: usize, out: []f64) -> bool {
    let k = p1 + p2
    let (par, e1) = mem.alloc[f64](a, k)
    let (qq, e2) = mem.alloc[f64](a, k)
    let (scr, e3) = mem.alloc[f64](a, k * k + 6usize * k + 16usize)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var t = 0usize
    while t < k {
        par[t] = 0.0f64
        t += 1usize
    }
    var c = OccCtx { x: x, z: z, y: y, m: m, j: j, p1: p1, p2: p2, q: qq }
    var round = 0usize
    while round < 3usize {
        let (r, e4) = opt.bfgs[OccCtx](&c, occ_f, occ_g, par, 1.0e-11f64, 300u32, scr)
        if e4 != ok { ret false }
        round += 1usize
    }
    t = 0usize
    while t < k {
        out[t] = par[t]
        t += 1usize
    }
    out[k] = 0.0f64 - occ_f(&c, par)
    ret true
}

type PcCtx = struct { x: []const f64, z: []const f64, y: []const f64, m: usize, j: usize, p1: usize, p2: usize, kk: usize, lf: []const f64, q: []f64 }

// minus the N-mixture log-likelihood (Poisson abundance with log mean x' b, binomial detection logistic in z' a, latent N summed from the largest count to kk)
fn pc_f(c: *PcCtx, par: []const f64) -> f64 {
    var ll = 0.0f64
    var i = 0usize
    while i < c.m {
        var e1 = 0.0f64
        var t = 0usize
        while t < c.p1 {
            e1 += c.x[i * c.p1 + t] * par[t]
            t += 1usize
        }
        var e2 = 0.0f64
        t = 0usize
        while t < c.p2 {
            e2 += c.z[i * c.p2 + t] * par[c.p1 + t]
            t += 1usize
        }
        let lam = math.exp[f64](e1)
        let p = lg(e2)
        let lp = math.log[f64](p)
        let lq = math.log[f64](1.0f64 - p)
        var mx = 0.0f64
        var v = 0usize
        while v < c.j {
            if c.y[i * c.j + v] > mx { mx = c.y[i * c.j + v] }
            v += 1usize
        }
        var best = 0.0f64 - 1.0e300f64
        var s = 0.0f64
        var n = usize(mx)
        // log-sum-exp in two passes
        var pass = 0usize
        while pass < 2usize {
            n = usize(mx)
            while n <= c.kk {
                let nf = f64(n)
                var term = nf * e1 - lam - c.lf[n]
                v = 0usize
                while v < c.j {
                    let y = c.y[i * c.j + v]
                    term += c.lf[n] - c.lf[usize(y)] - c.lf[n - usize(y)] + y * lp + (nf - y) * lq
                    v += 1usize
                }
                if pass == 0usize {
                    if term > best { best = term }
                } else {
                    s += math.exp[f64](term - best)
                }
                n += 1usize
            }
            pass += 1usize
        }
        ll += best + math.log[f64](s)
        i += 1usize
    }
    ret 0.0f64 - ll
}

fn pc_g(c: *PcCtx, par: []const f64, g: []f64) {
    let n = par.len
    var i = 0usize
    while i < n {
        c.q[i] = par[i]
        i += 1usize
    }
    i = 0usize
    while i < n {
        let h = 1.0e-6f64
        c.q[i] = par[i] + h
        let fp = pc_f(c, c.q[0usize..n])
        c.q[i] = par[i] - h
        let fm = pc_f(c, c.q[0usize..n])
        c.q[i] = par[i]
        g[i] = (fp - fm) / (2.0f64 * h)
        i += 1usize
    }
}

// unmarked::pcount(~ z ~ x, K = kk): out = the p1 abundance coefficients (log link), the p2 detection coefficients (logit), the log-likelihood; y holds counts, m sites by j visits, row-major
fn pcount(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, m: usize, j: usize, p1: usize, p2: usize, kk: usize, out: []f64) -> bool {
    let k = p1 + p2
    let (par, e1) = mem.alloc[f64](a, k)
    let (qq, e2) = mem.alloc[f64](a, k)
    let (scr, e3) = mem.alloc[f64](a, k * k + 6usize * k + 16usize)
    if e1 != ok || e2 != ok || e3 != ok { ret false }
    var t = 0usize
    while t < k {
        par[t] = 0.0f64
        t += 1usize
    }
    var tot = 0.0f64
    var i = 0usize
    while i < m * j {
        tot += y[i]
        i += 1usize
    }
    par[0usize] = math.log[f64](tot / f64(m * j) + 0.5f64)
    let (lf, e5) = mem.alloc[f64](a, kk + 2usize)
    if e5 != ok { ret false }
    lf[0usize] = 0.0f64
    i = 1usize
    while i <= kk + 1usize {
        lf[i] = lf[i - 1usize] + math.log[f64](f64(i))
        i += 1usize
    }
    var c = PcCtx { x: x, z: z, y: y, m: m, j: j, p1: p1, p2: p2, kk: kk, lf: lf, q: qq }
    var round = 0usize
    while round < 2usize {
        let (r, e4) = opt.bfgs[PcCtx](&c, pc_f, pc_g, par, 1.0e-11f64, 300u32, scr)
        if e4 != ok { ret false }
        round += 1usize
    }
    t = 0usize
    while t < k {
        out[t] = par[t]
        t += 1usize
    }
    out[k] = 0.0f64 - pc_f(&c, par)
    ret true
}

// the standard errors of the `occu` fit at est (p1 occupancy then p2 detection coefficients)
fn occu_se(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, m: usize, j: usize, p1: usize, p2: usize, est: []const f64, out: []f64) -> bool {
    let (qq, e1) = mem.alloc[f64](a, p1 + p2)
    if e1 != ok { ret false }
    var c = OccCtx { x: x, z: z, y: y, m: m, j: j, p1: p1, p2: p2, q: qq }
    ret nh.hessian_se[OccCtx](a, &c, occ_f, est, p1 + p2, out)
}

// the standard errors of the `pcount` fit at est, for the same K
fn pcount_se(a: *mem.Arena, x: []const f64, z: []const f64, y: []const f64, m: usize, j: usize, p1: usize, p2: usize, kk: usize, est: []const f64, out: []f64) -> bool {
    let (qq, e1) = mem.alloc[f64](a, p1 + p2)
    let (lf, e5) = mem.alloc[f64](a, kk + 2usize)
    if e1 != ok || e5 != ok { ret false }
    lf[0usize] = 0.0f64
    var i = 1usize
    while i <= kk + 1usize {
        lf[i] = lf[i - 1usize] + math.log[f64](f64(i))
        i += 1usize
    }
    var c = PcCtx { x: x, z: z, y: y, m: m, j: j, p1: p1, p2: p2, kk: kk, lf: lf, q: qq }
    ret nh.hessian_se[PcCtx](a, &c, pc_f, est, p1 + p2, out)
}
