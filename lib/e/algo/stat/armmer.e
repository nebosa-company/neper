// R arm for a linear mixed model with one random intercept (lme4's lmer fitted by e.algo.stat.lmerpkg): sim() of a merMod, se.fixef, se.ranef and extractDIC.
// x is n by p column-major, g the group codes 0 .. ng - 1. The fit is lmerpkg's (a Brent search on theta), which agrees with lme4's bobyqa to the 1e-3 or so lmer's own oracle uses, so
// these agree with arm to about that.

use e.algo.stat.lmerpkg as lm
use e.algo.rand.r as rng
use e.math
use e.mem

error NotPositive

type Mer = struct { n: usize, p: usize, ng: usize, theta: f64, sigma: f64, beta: []f64, b: []f64, rinv: []f64, rzxinv: []f64, cnt: []f64, lj: []f64, pwrss: f64 }

// the REML fit and what lme4's L, RZX and RX are for it: L is diagonal sqrt(1 + n_j theta^2), RZX row j = theta * (sum of the group's x) / L_j, RX the upper Cholesky factor of X'X - RZX'RZX;
// rinv is RX^-1 (p by p row-major, upper), rzxinv = -L^-1 RZX RX^-1 (ng by p row-major)
fn mer_fit(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, m: *Mer) -> err {
    let (beta, e1) = mem.alloc[f64](a, p)
    let (b, e2) = mem.alloc[f64](a, ng)
    let (out, e3) = mem.alloc[f64](a, 4usize)
    let (w, e4) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let e = lm.lmer_ri(a, x, y, g, n, p, ng, reml, beta, b, out)
    if e != ok { ret e }
    var df = f64(n)
    if reml { df = f64(n - p) }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    let ef = mer_factor(a, x, w, g, n, p, ng, out[1usize], m)
    if ef != ok { ret ef }
    m.sigma = out[2usize]
    m.beta = beta
    m.b = b
    m.pwrss = out[2usize] * out[2usize] * df
    ret ok
}

// the factors of lme4's L, RZX and RX at a given theta and per-observation weights w (1 for a linear model, the working weights of a glmer's last PIRLS step)
fn mer_factor(a: *mem.Arena, x: []const f64, w: []const f64, g: []const usize, n: usize, p: usize, ng: usize, theta: f64, m: *Mer) -> err {
    let (cnt, e4) = mem.alloc[f64](a, ng)
    let (lj, e5) = mem.alloc[f64](a, ng)
    let (sj, e6) = mem.alloc[f64](a, ng * p)
    let (mm, e7) = mem.alloc[f64](a, p * p)
    let (rx, e8) = mem.alloc[f64](a, p * p)
    let (rinv, e9) = mem.alloc[f64](a, p * p)
    let (rzxinv, e10) = mem.alloc[f64](a, ng * p)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret mem.Full }
    var i = 0usize
    while i < ng * p {
        sj[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ng {
        cnt[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        cnt[g[i]] += w[i]
        var c = 0usize
        while c < p {
            sj[g[i] * p + c] += w[i] * x[c * n + i]
            c += 1usize
        }
        i += 1usize
    }
    var j = 0usize
    while j < ng {
        lj[j] = math.sqrt[f64](1.0f64 + cnt[j] * theta * theta)
        j += 1usize
    }
    // M = X'X - sum_j RZX_j RZX_j'
    var c1 = 0usize
    while c1 < p {
        var c2 = 0usize
        while c2 < p {
            var s = 0.0f64
            i = 0usize
            while i < n {
                s += w[i] * x[c1 * n + i] * x[c2 * n + i]
                i += 1usize
            }
            j = 0usize
            while j < ng {
                s -= (theta * sj[j * p + c1] / lj[j]) * (theta * sj[j * p + c2] / lj[j])
                j += 1usize
            }
            mm[c1 * p + c2] = s
            c2 += 1usize
        }
        c1 += 1usize
    }
    // upper Cholesky: rx' rx = mm
    i = 0usize
    while i < p * p {
        rx[i] = 0.0f64
        i += 1usize
    }
    c1 = 0usize
    while c1 < p {
        var s = mm[c1 * p + c1]
        var k = 0usize
        while k < c1 {
            s -= rx[k * p + c1] * rx[k * p + c1]
            k += 1usize
        }
        if !(s > 0.0f64) { ret NotPositive }
        rx[c1 * p + c1] = math.sqrt[f64](s)
        var c2 = c1 + 1usize
        while c2 < p {
            var t = mm[c1 * p + c2]
            k = 0usize
            while k < c1 {
                t -= rx[k * p + c1] * rx[k * p + c2]
                k += 1usize
            }
            rx[c1 * p + c2] = t / rx[c1 * p + c1]
            c2 += 1usize
        }
        c1 += 1usize
    }
    // rinv = rx^-1 by back substitution on the columns of the identity
    c2_loop(rx, rinv, p)
    // rzxinv[j][c] = -(1 / L_j) * sum_k RZX[j][k] rinv[k][c]
    j = 0usize
    while j < ng {
        c1 = 0usize
        while c1 < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += (theta * sj[j * p + k] / lj[j]) * rinv[k * p + c1]
                k += 1usize
            }
            rzxinv[j * p + c1] = 0.0f64 - s / lj[j]
            c1 += 1usize
        }
        j += 1usize
    }
    m.n = n
    m.p = p
    m.ng = ng
    m.theta = theta
    m.rinv = rinv
    m.rzxinv = rzxinv
    m.cnt = cnt
    m.lj = lj
    ret ok
}

fn c2_loop(rx: []const f64, rinv: []f64, p: usize) {
    var col = 0usize
    while col < p {
        var r = p
        while r > 0usize {
            r -= 1usize
            var s = 0.0f64
            if r == col { s = 1.0f64 }
            var k = r + 1usize
            while k < p {
                s -= rx[r * p + k] * rinv[k * p + col]
                k += 1usize
            }
            rinv[r * p + col] = s / rx[r * p + r]
        }
        col += 1usize
    }
}

// sim(lmer fit, n.sims): fixef (nsims by p row-major), ranef (nsims by ng) and sigma (nsims), drawn in arm's order: per simulation sigma = sqrt(1 / rgamma(1, (n - p) / 2, rate = pwrss / 2)),
// then n.ranef + n.fixef normals of sd sigma through the left factor of the inverse information
fn sim_mer(a: *mem.Arena, r: *rng.Rng, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, nsims: usize, fixef: []f64, ranef: []f64, sigma: []f64) -> err {
    var m: Mer = zero
    let e = mer_fit(a, x, y, g, n, p, ng, true, &m)
    if e != ok { ret e }
    ret sim_draw(a, r, &m, true, nsims, fixef, ranef, sigma)
}

// sim of the REML fit at a given theta (lmer's own optimiser stops short of the optimum, so the oracle hands R's theta over): beta, u and pwrss follow from theta in closed form
fn sim_mer_theta(a: *mem.Arena, r: *rng.Rng, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, theta: f64, nsims: usize, fixef: []f64, ranef: []f64, sigma: []f64) -> err {
    var m: Mer = zero
    let e = mer_at_theta(a, x, y, g, n, p, ng, theta, &m)
    if e != ok { ret e }
    ret sim_draw(a, r, &m, true, nsims, fixef, ranef, sigma)
}

// se.fixef and se.ranef of the REML fit at a given theta
fn se_mer_theta(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, theta: f64, sefix: []f64, seran: []f64) -> err {
    var m: Mer = zero
    let e = mer_at_theta(a, x, y, g, n, p, ng, theta, &m)
    if e != ok { ret e }
    m.sigma = math.sqrt[f64](m.pwrss / f64(n - p))
    ret se_from(&m, p, ng, sefix, seran)
}

fn mer_at_theta(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, theta: f64, m: *Mer) -> err {
    let (w, e0) = mem.alloc[f64](a, n)
    let (beta, e1) = mem.alloc[f64](a, p)
    let (b, e2) = mem.alloc[f64](a, ng)
    let (cu, e3) = mem.alloc[f64](a, ng)
    let (rhs, e4) = mem.alloc[f64](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    let ef = mer_factor(a, x, w, g, n, p, ng, theta, m)
    if ef != ok { ret ef }
    var j = 0usize
    while j < ng {
        cu[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n {
        cu[g[i]] += theta * y[i] / m.lj[g[i]]
        i += 1usize
    }
    // RX'RX beta = X'y - RZX'cu, RZX_j = theta (sum of x_j) / L_j, solved through rinv
    var c = 0usize
    while c < p {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += x[c * n + i] * y[i]
            i += 1usize
        }
        j = 0usize
        while j < ng {
            var sx = 0.0f64
            i = 0usize
            while i < n {
                if g[i] == j { sx += x[c * n + i] }
                i += 1usize
            }
            s -= theta * sx / m.lj[j] * cu[j]
            j += 1usize
        }
        rhs[c] = s
        c += 1usize
    }
    c = 0usize
    while c < p {
        var s = 0.0f64
        var k = 0usize
        while k < p {
            s += m.rinv[c * p + k] * rinvt_rhs(m.rinv, rhs, p, k)
            k += 1usize
        }
        beta[c] = s
        c += 1usize
    }
    // u_j = (cu_j - RZX_j beta) / L_j, b = theta u, pwrss = |y - X beta - Z b|^2 + |u|^2
    var pw = 0.0f64
    j = 0usize
    while j < ng {
        var sx = cu[j]
        c = 0usize
        while c < p {
            var sc = 0.0f64
            i = 0usize
            while i < n {
                if g[i] == j { sc += x[c * n + i] }
                i += 1usize
            }
            sx -= theta * sc / m.lj[j] * beta[c]
            c += 1usize
        }
        let u = sx / m.lj[j]
        b[j] = theta * u
        pw += u * u
        j += 1usize
    }
    i = 0usize
    while i < n {
        var f = y[i] - b[g[i]]
        c = 0usize
        while c < p {
            f -= x[c * n + i] * beta[c]
            c += 1usize
        }
        pw += f * f
        i += 1usize
    }
    m.beta = beta
    m.b = b
    m.pwrss = pw
    ret ok
}

fn rinvt_rhs(rinv: []const f64, rhs: []const f64, p: usize, k: usize) -> f64 {
    var s = 0.0f64
    var q = 0usize
    while q < p {
        s += rinv[q * p + k] * rhs[q]
        q += 1usize
    }
    ret s
}

// sim of a glmer fit with a random intercept given R's final state: theta, beta, u and the working weights w; the draws are standard normals (no common scale)
fn sim_glmer(a: *mem.Arena, r: *rng.Rng, x: []const f64, w: []const f64, g: []const usize, n: usize, p: usize, ng: usize, theta: f64, beta: []const f64, u: []const f64, nsims: usize, fixef: []f64, ranef: []f64) -> err {
    var m: Mer = zero
    let ef = mer_factor(a, x, w, g, n, p, ng, theta, &m)
    if ef != ok { ret ef }
    let (b, e1) = mem.alloc[f64](a, ng)
    let (sg, e2) = mem.alloc[f64](a, 1usize)
    let (bt, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var c = 0usize
    while c < p {
        bt[c] = beta[c]
        c += 1usize
    }
    var j = 0usize
    while j < ng {
        b[j] = theta * u[j]
        j += 1usize
    }
    m.beta = bt
    m.b = b
    m.pwrss = 0.0f64
    ret sim_draw(a, r, &m, false, nsims, fixef, ranef, sg)
}

// the draw loop in arm's order; scaled draws a common sigma first (a linear model), else the effects are standard normals
fn sim_draw(a: *mem.Arena, r: *rng.Rng, m: *Mer, scaled: bool, nsims: usize, fixef: []f64, ranef: []f64, sigma: []f64) -> err {
    let n = m.n
    let p = m.p
    let ng = m.ng
    let (sph, e1) = mem.alloc[f64](a, ng + p)
    if e1 != ok { ret e1 }
    var s = 0usize
    while s < nsims {
        var sd = 1.0f64
        if scaled {
            let gm = rng.rgamma(r, 0.5f64 * f64(n - p), 2.0f64 / m.pwrss)
            sd = math.sqrt[f64](1.0f64 / gm)
            sigma[s] = sd
        }
        var k = 0usize
        while k < ng + p {
            sph[k] = rng.rnorm(r, 0.0f64, sd)
            k += 1usize
        }
        var j = 0usize
        while j < ng {
            var v = m.theta / m.lj[j] * sph[j]
            var c = 0usize
            while c < p {
                v += m.theta * m.rzxinv[j * p + c] * sph[ng + c]
                c += 1usize
            }
            ranef[s * ng + j] = v + m.b[j]
            j += 1usize
        }
        var c1 = 0usize
        while c1 < p {
            var v = 0.0f64
            var c2 = 0usize
            while c2 < p {
                v += m.rinv[c1 * p + c2] * sph[ng + c2]
                c2 += 1usize
            }
            fixef[s * p + c1] = v + m.beta[c1]
            c1 += 1usize
        }
        s += 1usize
    }
    ret ok
}

// se.fixef: sqrt(diag(vcov)) with vcov = sigma^2 (RX'RX)^-1 = sigma^2 RX^-1 RX^-T, and se.ranef: sqrt(sigma^2 theta^2 / (1 + n_j theta^2)), for the REML fit (reml) or the ML one
fn se_mer(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool, sefix: []f64, seran: []f64) -> err {
    var m: Mer = zero
    let e = mer_fit(a, x, y, g, n, p, ng, reml, &m)
    if e != ok { ret e }
    ret se_from(&m, p, ng, sefix, seran)
}

fn se_from(m: *Mer, p: usize, ng: usize, sefix: []f64, seran: []f64) -> err {
    var c1 = 0usize
    while c1 < p {
        var v = 0.0f64
        var c2 = 0usize
        while c2 < p {
            v += m.rinv[c1 * p + c2] * m.rinv[c1 * p + c2]
            c2 += 1usize
        }
        sefix[c1] = m.sigma * math.sqrt[f64](v)
        c1 += 1usize
    }
    var j = 0usize
    while j < ng {
        seran[j] = m.sigma * m.theta / m.lj[j]
        j += 1usize
    }
    ret ok
}

// extractDIC of a REML fit: the ML deviance (at the ML refit) plus pD = deviance - Dhat, with Dhat the REML criterion; for an ML fit it is the deviance itself
fn dic_mer(a: *mem.Arena, x: []const f64, y: []const f64, g: []const usize, n: usize, p: usize, ng: usize, reml: bool) -> (f64, err) {
    let (beta, e1) = mem.alloc[f64](a, p)
    let (b, e2) = mem.alloc[f64](a, ng)
    let (o1, e3) = mem.alloc[f64](a, 4usize)
    let (o2, e4) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (0.0f64, mem.Full) }
    let ea = lm.lmer_ri(a, x, y, g, n, p, ng, false, beta, b, o1)
    if ea != ok { ret (0.0f64, ea) }
    if !reml { ret (o1[0usize] + 0.0f64, ok) }
    let eb = lm.lmer_ri(a, x, y, g, n, p, ng, true, beta, b, o2)
    if eb != ok { ret (0.0f64, eb) }
    ret (2.0f64 * o1[0usize] - o2[0usize], ok)
}
