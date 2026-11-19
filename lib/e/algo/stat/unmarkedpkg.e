// unmarked::occu: single-season site occupancy with imperfect detection (MacKenzie et al.). Site i is occupied with probability psi_i = logistic(x_i' b) and an occupied site is detected on each of its J visits with probability
// p_i = logistic(z_i' a) (covariates constant over the visits of a site, no missing visits); the likelihood of the detection history y_i is psi_i prod p_i^y (1 - p_i)^(1 - y) + (1 - psi_i) [all y_i = 0], maximised by BFGS from zero.
//
// Not here: visit-level detection covariates and missing visits, other links, standard errors, the other unmarked models (colext, pcount, distsamp, occuRN), prediction, goodness of fit.

use e.math
use e.math.opt as opt
use e.mem

type OccCtx = struct { x: []const f64, z: []const f64, y: []const f64, m: usize, j: usize, p1: usize, p2: usize, q: []f64 }

fn lg(t: f64) -> f64 { ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - t)) }

fn occ_f(c: *OccCtx, par: []const f64) -> f64 {
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
        let psi = lg(e1)
        let p = lg(e2)
        var lk = psi
        var any = false
        var v = 0usize
        while v < c.j {
            if c.y[i * c.j + v] > 0.5f64 {
                lk = lk * p
                any = true
            } else {
                lk = lk * (1.0f64 - p)
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
