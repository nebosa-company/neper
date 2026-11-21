// R MCMCpack::MCMCirt1d default start values: theta from the eigen start of the agreement matrix (MCMCpack's factor.score.start.check) and alpha, beta
// from one probit glm per item on that theta, the values irt1d takes when the caller gives none.
//
// Not here: step halving inside glm.fit after an invalid eta or mu, and the other samplers' defaults.

use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.armglm as ag
use e.algo.stat.armld as ld
use e.algo.stat.mcmcpacksamp as ms
use e.math
use e.mem

// R's dev.resids of the binomial family for one observation
fn bin_dev(y: f64, mu: f64) -> f64 {
    var d = 0.0f64
    if y != 0.0f64 { d += y * math.log[f64](y / mu) }
    if y != 1.0f64 { d += (1.0f64 - y) * math.log[f64]((1.0f64 - y) / (1.0f64 - mu)) }
    ret 2.0f64 * d
}

fn probit_linkinv(eta_in: f64) -> f64 {
    let thresh = 8.125890664701906f64
    var eta = eta_in
    if eta > thresh { eta = thresh }
    if eta < 0.0f64 - thresh { eta = 0.0f64 - thresh }
    ret ag.pnorm_cr(eta)
}

// coef(glm(y ~ t, binomial(probit), control = glm.control(maxit, epsilon))): R's IRLS from mustart = (y + 0.5) / 2, the weighted least squares by Householder QR
fn glm_probit1(a: *mem.Arena, y: []const f64, t: []const f64, maxit: usize, eps: f64, coef: []f64) -> err {
    let m = y.len
    let (eta, e1) = mem.alloc[f64](a, m)
    let (mu, e2) = mem.alloc[f64](a, m)
    let (c0, e3) = mem.alloc[f64](a, m)
    let (c1, e4) = mem.alloc[f64](a, m)
    let (rr, e5) = mem.alloc[f64](a, m)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    let deps = 2.220446049250313e-16f64
    var devold = 0.0f64
    var i = 0usize
    while i < m {
        eta[i] = ag.qnorm_r((y[i] + 0.5f64) / 2.0f64)
        mu[i] = probit_linkinv(eta[i])
        devold += bin_dev(y[i], mu[i])
        i += 1usize
    }
    var iter = 0usize
    var conv = false
    while iter < maxit && !conv {
        i = 0usize
        while i < m {
            var me = ag.dnorm_cr(eta[i])
            if me < deps { me = deps }
            let w = math.sqrt[f64](me * me / (mu[i] * (1.0f64 - mu[i])))
            rr[i] = w * (eta[i] + (y[i] - mu[i]) / me)
            c0[i] = w
            c1[i] = w * t[i]
            i += 1usize
        }
        // LINPACK dqrdc2 then dqrsl, as R's Cdqrls runs them on the two columns (c0, c1)
        var nrmxl = dnrm(c0, 0usize, m)
        if c0[0usize] != 0.0f64 && c0[0usize] < 0.0f64 { nrmxl = 0.0f64 - nrmxl }
        var sc = 1.0f64 / nrmxl
        i = 0usize
        while i < m {
            c0[i] = c0[i] * sc
            i += 1usize
        }
        c0[0usize] = 1.0f64 + c0[0usize]
        let t1 = (0.0f64 - ddot(c0, 0usize, c1, 0usize, m)) / c0[0usize]
        i = 0usize
        while i < m {
            c1[i] = c1[i] + t1 * c0[i]
            i += 1usize
        }
        let qa0 = c0[0usize]
        let r00 = 0.0f64 - nrmxl
        var nrmx2 = dnrm(c1, 1usize, m - 1usize)
        if c1[1usize] < 0.0f64 { nrmx2 = 0.0f64 - nrmx2 }
        sc = 1.0f64 / nrmx2
        i = 1usize
        while i < m {
            c1[i] = c1[i] * sc
            i += 1usize
        }
        c1[1usize] = 1.0f64 + c1[1usize]
        let qa1 = c1[1usize]
        let r11 = 0.0f64 - nrmx2
        let r01 = c1[0usize]
        // qty
        c0[0usize] = qa0
        let tq0 = (0.0f64 - ddot(c0, 0usize, rr, 0usize, m)) / c0[0usize]
        i = 0usize
        while i < m {
            rr[i] = rr[i] + tq0 * c0[i]
            i += 1usize
        }
        let tq1 = (0.0f64 - ddot(c1, 1usize, rr, 1usize, m - 1usize)) / qa1
        i = 1usize
        while i < m {
            rr[i] = rr[i] + tq1 * c1[i]
            i += 1usize
        }
        var b1 = rr[1usize]
        b1 = b1 / r11
        let b0 = (rr[0usize] + (0.0f64 - b1) * r01) / r00
        coef[0usize] = b0
        coef[1usize] = b1
        var dev = 0.0f64
        i = 0usize
        while i < m {
            eta[i] = b0 + b1 * t[i]
            mu[i] = probit_linkinv(eta[i])
            dev += bin_dev(y[i], mu[i])
            i += 1usize
        }
        iter += 1usize
        if math.abs[f64](dev - devold) / (math.abs[f64](dev) + 0.1f64) < eps { conv = true }
        devold = dev
    }
    ret ok
}

fn dnrm(v: []const f64, from: usize, n: usize) -> f64 {
    var s = 0.0f64
    var i = from
    while i < from + n {
        s += v[i] * v[i]
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

fn ddot(x: []const f64, xf: usize, y: []const f64, yf: usize, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[xf + i] * y[yf + i]
        i += 1usize
    }
    ret s
}

fn flip(v: []f64) {
    var i = 0usize
    while i < v.len {
        v[i] = 0.0f64 - v[i]
        i += 1usize
    }
}

fn mean_of(v: []const f64) -> f64 { ret ld.mean_ld(v) }

// x is the J by K row-major data (9 for missing); eq and ineq are the constraint arrays irt1d takes
fn irt1d_starts(a: *mem.Arena, x: []const f64, jn: usize, kn: usize, t0: f64, tt0: f64, eq: []const f64, ineq: []const f64, theta: []f64, alpha: []f64, beta: []f64) -> err {
    let (am, e1) = mem.alloc[f64](a, jn * jn)
    let (aa, e2) = mem.alloc[f64](a, jn * jn)
    let (rm, e3) = mem.alloc[f64](a, jn)
    let (w, e4) = mem.alloc[f64](a, jn)
    let (zv, e5) = mem.alloc[f64](a, jn * jn)
    let (yy, e6) = mem.alloc[f64](a, jn)
    let (tt, e7) = mem.alloc[f64](a, jn)
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    var i = 0usize
    var j = 0usize
    var k = 0usize
    let fk = f64(kn)
    while i < jn {
        j = 0usize
        while j < jn {
            var c = 0.0f64
            k = 0usize
            while k < kn {
                if x[i * kn + k] == x[j * kn + k] { c += 1.0f64 }
                k += 1usize
            }
            let d = 1.0f64 - c / fk
            am[i * jn + j] = d * d
            j += 1usize
        }
        i += 1usize
    }
    var gm = 0.0f64
    i = 0usize
    while i < jn {
        rm[i] = mean_of(am[i * jn..(i + 1usize) * jn])
        gm += rm[i]
        i += 1usize
    }
    gm = mean_of(rm)
    i = 0usize
    while i < jn {
        j = 0usize
        while j < jn {
            aa[j * jn + i] = (am[i * jn + j] - rm[i] - rm[j] + gm) / (0.0f64 - 2.0f64)
            j += 1usize
        }
        i += 1usize
    }
    if sy.dsyevr_all(a, aa, jn, w, zv) != ok { ret ms.NotPd }
    let top = jn - 1usize
    let sc = math.sqrt[f64](w[top])
    i = 0usize
    while i < jn {
        theta[i] = zv[top * jn + i] * sc
        i += 1usize
    }
    let mu = mean_of(theta)
    let sd = math.sqrt[f64](ld.var_ld(theta))
    let psd = math.sqrt[f64](1.0f64 / tt0)
    i = 0usize
    while i < jn {
        theta[i] = t0 + (theta[i] - mu) / sd * psd
        i += 1usize
    }
    j = 0usize
    while j < jn {
        if eq[j] != -999.0f64 && theta[j] * eq[j] < 0.0f64 { flip(theta) }
        if theta[j] * ineq[j] < 0.0f64 { flip(theta) }
        j += 1usize
    }
    j = 0usize
    while j < jn {
        if eq[j] != -999.0f64 { theta[j] = eq[j] }
        if ineq[j] != 0.0f64 { theta[j] = math.abs[f64](theta[j]) * ineq[j] }
        j += 1usize
    }
    var prev = 0usize
    j = 0usize
    while j < jn {
        if eq[j] == -999.0f64 {
            if (ineq[j] > 0.0f64 && theta[j] < 0.0f64) || (ineq[j] < 0.0f64 && theta[j] > 0.0f64) {
                if prev != 0usize { ret ms.NotPd }
                flip(theta)
                prev += 1usize
            }
        } else {
            if theta[j] * eq[j] > 0.0f64 { theta[j] = eq[j] } else {
                if prev != 0usize { ret ms.NotPd }
                flip(theta)
                theta[j] = eq[j]
                prev += 1usize
            }
        }
        j += 1usize
    }
    k = 0usize
    while k < kn {
        var m = 0usize
        var ones = 0.0f64
        j = 0usize
        while j < jn {
            let v = x[j * kn + k]
            if v == 0.0f64 || v == 1.0f64 {
                yy[m] = v
                tt[m] = theta[j]
                ones += v
                m += 1usize
            }
            j += 1usize
        }
        if ones == 0.0f64 || ones == f64(m) {
            alpha[k] = 0.0f64
            beta[k] = 10.0f64
        } else {
            var cf: [2]f64 = zero
            let eg = glm_probit1(a, yy[0usize..m], tt[0usize..m], 8usize, 0.001f64, cf[0usize..2usize])
            if eg != ok { ret eg }
            alpha[k] = 0.0f64 - cf[0usize]
            beta[k] = cf[1usize]
        }
        k += 1usize
    }
    ret ok
}
