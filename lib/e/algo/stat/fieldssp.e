// R fields: spatialProcess (Matern or exponential covariance, polynomial drift of degree 1) as mKrig profiles it. The parameters not given are estimated the way spatialProcess does:
// a grid search (lambda 10^seq(-4, 0.5, 5), aRange seq(0.1, 0.7, length 5) times the diagonal of the bounding box, lambda varying fastest) that keeps the row with the largest
// lnProfileREML.FULL (fields picks that column even when REML is FALSE), then optim BFGS on the log parameters of lnProfileLike.FULL (numerical gradient with steps log(1.1), reltol 1e-4,
// at most 20 iterations), then mKrig at the estimate. Prediction is predict.mKrig and predictSE.mKrig; the convex hull test is predictSurface's extrap = FALSE mask.
// answer: args = [op, idx, ctype, nu, flags, lambda0, aRange0, n, d, nq, x (n*d row major), y (n), xq (nq*d row major)]; ctype 1 Matern(nu), 2 exponential; flags bit 0: estimate lambda, bit 1: estimate aRange
// (otherwise lambda0 / aRange0 are used). op 0 lambda  1 aRange  2 lnProfileLike.FULL  3 lnProfileREML.FULL  4 sigma2 (rho.MLE.FULL)  5 tau  6 d[idx]  7 c[idx]  8 fitted[idx]
// 9 predict(xq[idx])  10 predictSE(xq[idx])  11 xq[idx] inside the convex hull.
//
// Not here: eff.df and GCV (Monte Carlo trace), the optim hessian and confidence intervals, profile likelihood tables, covariates (XMat), replicated fields, weights, other covariances.

use e.algo.stat.fieldskrig as fk
use e.algo.stat.fieldspkg as fp
use e.algo.stat.rbfgs as bf
use e.math
use e.mem

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

type Prob = struct {
    ctype: usize, nu: f64, n: usize, d: usize, nt: usize,
    x: []const f64, y: []const f64, tab: []const usize,
    est_l: bool, est_a: bool, lam0: f64, a0: f64,
    lo: []f64, ts: []f64, ys: []f64, gm: []f64, gl: []f64, beta: []f64, zres: []f64, rhs: []f64, w: []f64, out: []f64
}

// L, the lower Cholesky factor of the covariance plus lambda I; false when it is not positive definite
fn chol_cov(c: *Prob, lam: f64, ar: f64) -> bool {
    let n = c.n
    var j = 0usize
    while j < n {
        var i = j
        while i < n {
            var v = fk.cov_value(c.ctype, 0.0f64, ar, c.nu, 1.0f64, c.x, i, c.x, j, c.d)
            if i == j { v = v + lam }
            var k = 0usize
            while k < j {
                v = v - c.lo[i * n + k] * c.lo[j * n + k]
                k += 1usize
            }
            if i == j {
                if v <= 0.0f64 { ret false }
                c.lo[j * n + j] = math.sqrt[f64](v)
            } else {
                c.lo[i * n + j] = v / c.lo[j * n + j]
            }
            i += 1usize
        }
        j += 1usize
    }
    ret true
}

// solve L z = b in place (forward substitution)
fn fwd(lo: []const f64, n: usize, b: []f64) {
    var i = 0usize
    while i < n {
        var v = b[i]
        var k = 0usize
        while k < i {
            v = v - lo[i * n + k] * b[k]
            k += 1usize
        }
        b[i] = v / lo[i * n + i]
        i += 1usize
    }
}

// solve L' x = b in place (back substitution)
fn bwd(lo: []const f64, n: usize, b: []f64) {
    var i = n
    while i > 0usize {
        i -= 1usize
        var v = b[i]
        var k = i + 1usize
        while k < n {
            v = v - lo[k * n + i] * b[k]
            k += 1usize
        }
        b[i] = v / lo[i * n + i]
    }
}

// G = TStar' TStar, its Cholesky factor in gl; the determinant's log is returned
fn factor_g(c: *Prob) -> f64 {
    let n = c.n
    let nt = c.nt
    var i = 0usize
    while i < nt {
        var j = 0usize
        while j < nt {
            var s = 0.0f64
            var k = 0usize
            while k < n {
                s += c.ts[k * nt + i] * c.ts[k * nt + j]
                k += 1usize
            }
            c.gm[i * nt + j] = s
            j += 1usize
        }
        i += 1usize
    }
    var lnd = 0.0f64
    var j = 0usize
    while j < nt {
        var i2 = j
        while i2 < nt {
            var v = c.gm[i2 * nt + j]
            var k = 0usize
            while k < j {
                v = v - c.gl[i2 * nt + k] * c.gl[j * nt + k]
                k += 1usize
            }
            if i2 == j {
                c.gl[j * nt + j] = math.sqrt[f64](v)
                lnd += 2.0f64 * math.log[f64](c.gl[j * nt + j])
            } else {
                c.gl[i2 * nt + j] = v / c.gl[j * nt + j]
            }
            i2 += 1usize
        }
        j += 1usize
    }
    ret lnd
}

// solve G x = b in place with the factor from factor_g
fn solve_g(c: *Prob, b: []f64) {
    fwd(c.gl, c.nt, b)
    bwd(c.gl, c.nt, b)
}

// mKrig's profile at (lambda, aRange): out = [lnProfileLike.FULL, lnProfileREML.FULL, sigma2, lnDetCov, lnDetOmega]; beta and zres (= L^-1 resid) are left in c
fn profile(c: *Prob, lam: f64, ar: f64, out: []f64) -> bool {
    if !chol_cov(c, lam, ar) { ret false }
    let n = c.n
    let nt = c.nt
    var lndet = 0.0f64
    var i = 0usize
    while i < n {
        lndet += 2.0f64 * math.log[f64](c.lo[i * n + i])
        c.ys[i] = c.y[i]
        i += 1usize
    }
    fwd(c.lo, n, c.ys)
    var k = 0usize
    while k < nt {
        i = 0usize
        while i < n {
            c.zres[i] = fk.poly_value(c.tab, k, c.x, i, c.d)
            i += 1usize
        }
        fwd(c.lo, n, c.zres)
        i = 0usize
        while i < n {
            c.ts[i * nt + k] = c.zres[i]
            i += 1usize
        }
        k += 1usize
    }
    let lng = factor_g(c)
    k = 0usize
    while k < nt {
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += c.ts[i * nt + k] * c.ys[i]
            i += 1usize
        }
        c.beta[k] = s
        k += 1usize
    }
    solve_g(c, c.beta)
    var quad = 0.0f64
    i = 0usize
    while i < n {
        var s = c.ys[i]
        k = 0usize
        while k < nt {
            s = s - c.ts[i * nt + k] * c.beta[k]
            k += 1usize
        }
        c.zres[i] = s
        quad += s * s
        i += 1usize
    }
    let nf = f64(n)
    let s2 = quad / nf
    let like = 0.0f64 - nf / 2.0f64 - math.log[f64](2.0f64 * 3.14159265358979323846264338327950288f64) * (nf / 2.0f64) - (nf / 2.0f64) * math.log[f64](s2) - lndet / 2.0f64
    out[0usize] = like
    out[1usize] = like + 0.5f64 * (0.0f64 - lng)
    out[2usize] = s2
    out[3usize] = lndet
    out[4usize] = 0.0f64 - lng
    ret true
}

fn params_of(c: *Prob, p: []const f64, pair: []f64) {
    var at = 0usize
    pair[0usize] = c.lam0
    pair[1usize] = c.a0
    if c.est_l {
        pair[0usize] = math.exp[f64](p[at])
        at += 1usize
    }
    if c.est_a { pair[1usize] = math.exp[f64](p[at]) }
}

// optim's objective: minus lnProfileLike.FULL (fnscale = -1)
fn obj(c: *Prob, p: []const f64) -> f64 {
    var pair: [2]f64 = zero
    params_of(c, p, pair[0usize..2usize])
    if !profile(c, pair[0usize], pair[1usize], c.out) { ret 0.0f64 / 0.0f64 }
    ret 0.0f64 - c.out[0usize]
}

fn grad(c: *Prob, p: []const f64, g: []f64) {
    let eps = math.log[f64](1.1f64)
    var k = 0usize
    while k < p.len {
        var j = 0usize
        while j < p.len {
            c.w[j] = p[j]
            j += 1usize
        }
        c.w[k] = p[k] + eps
        let v1 = obj(c, c.w[0usize..p.len])
        c.w[k] = p[k] - eps
        let v2 = obj(c, c.w[0usize..p.len])
        g[k] = (v1 - v2) / (2.0f64 * eps)
        k += 1usize
    }
}

fn answer(a: *mem.Arena, g: []const f64) -> f64 {
    let op = usize(g[0usize])
    let idx = usize(g[1usize])
    let n = usize(g[7usize])
    let d = usize(g[8usize])
    let nq = usize(g[9usize])
    let flags = usize(g[4usize])
    var c: Prob = zero
    c.ctype = usize(g[2usize])
    c.nu = g[3usize]
    c.n = n
    c.d = d
    c.est_l = flags % 2usize == 1usize
    c.est_a = flags / 2usize == 1usize
    c.lam0 = g[5usize]
    c.a0 = g[6usize]
    let (x, e1) = mem.alloc[f64](a, n * d)
    let (y, e2) = mem.alloc[f64](a, n)
    let (xq, e3) = mem.alloc[f64](a, nq * d + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret nan_value() }
    var k = 0usize
    while k < n * d {
        x[k] = g[10usize + k]
        k += 1usize
    }
    k = 0usize
    while k < n {
        y[k] = g[10usize + n * d + k]
        k += 1usize
    }
    k = 0usize
    while k < nq * d {
        xq[k] = g[10usize + n * d + n + k]
        k += 1usize
    }
    if op == 11usize {
        if fp.in_hull(x, n, d, xq[idx * d], xq[idx * d + 1usize]) { ret 1.0f64 }
        ret 0.0f64
    }
    c.x = x
    c.y = y
    let (tab, nt, e4) = fk.poly_table(a, d, 2usize)
    if e4 != ok { ret nan_value() }
    c.tab = tab
    c.nt = nt
    let (lo, f1) = mem.alloc[f64](a, n * n)
    let (ts, f2) = mem.alloc[f64](a, n * nt)
    let (ys, f3) = mem.alloc[f64](a, n)
    let (gm, f4) = mem.alloc[f64](a, nt * nt)
    let (gl, f5) = mem.alloc[f64](a, nt * nt)
    let (beta, f6) = mem.alloc[f64](a, nt)
    let (zres, f7) = mem.alloc[f64](a, n)
    let (rhs, f8) = mem.alloc[f64](a, n + nt)
    let (w, f9) = mem.alloc[f64](a, 4usize)
    let (out, f10) = mem.alloc[f64](a, 8usize)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok || f7 != ok || f8 != ok || f9 != ok || f10 != ok { ret nan_value() }
    c.lo = lo
    c.ts = ts
    c.ys = ys
    c.gm = gm
    c.gl = gl
    c.beta = beta
    c.zres = zres
    c.rhs = rhs
    c.w = w
    c.out = out
    var lam = c.lam0
    var ar = c.a0
    if c.est_l || c.est_a {
        // the grid search
        var dmax = 0.0f64
        k = 0usize
        while k < d {
            var lo_k = x[k]
            var hi_k = x[k]
            var i = 1usize
            while i < n {
                if x[i * d + k] < lo_k { lo_k = x[i * d + k] }
                if x[i * d + k] > hi_k { hi_k = x[i * d + k] }
                i += 1usize
            }
            dmax += (hi_k - lo_k) * (hi_k - lo_k)
            k += 1usize
        }
        dmax = math.sqrt[f64](dmax)
        var nl = 1usize
        var na = 1usize
        if c.est_l { nl = 5usize }
        if c.est_a { na = 5usize }
        var best = 0.0f64
        var have = false
        var ia = 0usize
        while ia < na {
            var il = 0usize
            while il < nl {
                var gl_v = c.lam0
                var ga_v = c.a0
                if c.est_l { gl_v = math.pow[f64](10.0f64, -4.0f64 + f64(il) * 1.125f64) }
                if c.est_a { ga_v = 0.1f64 * dmax + f64(ia) * (0.7f64 * dmax - 0.1f64 * dmax) / 4.0f64 }
                if profile(&c, gl_v, ga_v, out) {
                    if !have || out[1usize] > best {
                        have = true
                        best = out[1usize]
                        lam = gl_v
                        ar = ga_v
                    }
                }
                il += 1usize
            }
            ia += 1usize
        }
        var np = 0usize
        if c.est_l { np += 1usize }
        if c.est_a { np += 1usize }
        let (b, g1) = mem.alloc[f64](a, np)
        if g1 != ok { ret nan_value() }
        var at = 0usize
        if c.est_l {
            b[at] = math.log[f64](lam)
            at += 1usize
        }
        if c.est_a { b[at] = math.log[f64](ar) }
        let fmin = bf.vmmin[Prob](a, &c, obj, grad, b, 1.0e-4f64, 20usize)
        var pair: [2]f64 = zero
        params_of(&c, b, pair[0usize..2usize])
        lam = pair[0usize]
        ar = pair[1usize]
    }
    if !profile(&c, lam, ar, out) { ret nan_value() }
    if op == 0usize { ret lam }
    if op == 1usize { ret ar }
    if op == 2usize { ret out[0usize] }
    if op == 3usize { ret out[1usize] }
    let sigma2 = out[2usize]
    if op == 4usize { ret sigma2 }
    if op == 5usize { ret math.sqrt[f64](lam * sigma2) }
    if op == 6usize { ret beta[idx] }
    // c = L^-T (L^-1 resid)
    let (coef, g2) = mem.alloc[f64](a, n)
    if g2 != ok { ret nan_value() }
    k = 0usize
    while k < n {
        coef[k] = zres[k]
        k += 1usize
    }
    bwd(lo, n, coef)
    if op == 7usize { ret coef[idx] }
    if op == 8usize {
        var f = y[idx]
        f = f - lam * coef[idx]
        ret f
    }
    // the covariance and drift at the query point
    let (kv, g3) = mem.alloc[f64](a, n)
    let (t0, g4) = mem.alloc[f64](a, nt)
    if g3 != ok || g4 != ok { ret nan_value() }
    k = 0usize
    while k < n {
        kv[k] = fk.cov_value(c.ctype, 0.0f64, ar, c.nu, 1.0f64, x, k, xq, idx, d)
        k += 1usize
    }
    k = 0usize
    while k < nt {
        t0[k] = fk.poly_value(tab, k, xq, idx, d)
        k += 1usize
    }
    if op == 9usize {
        var s = 0.0f64
        k = 0usize
        while k < n {
            s += kv[k] * coef[k]
            k += 1usize
        }
        k = 0usize
        while k < nt {
            s += t0[k] * beta[k]
            k += 1usize
        }
        ret s
    }
    // predictSE.mKrig
    let (zk, g5) = mem.alloc[f64](a, n)
    let (bk, g6) = mem.alloc[f64](a, nt)
    let (ot, g7) = mem.alloc[f64](a, nt)
    if g5 != ok || g6 != ok || g7 != ok { ret nan_value() }
    k = 0usize
    while k < n {
        zk[k] = kv[k]
        k += 1usize
    }
    fwd(lo, n, zk)
    var zz = 0.0f64
    k = 0usize
    while k < n {
        zz += zk[k] * zk[k]
        k += 1usize
    }
    k = 0usize
    while k < nt {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += ts[i * nt + k] * zk[i]
            i += 1usize
        }
        bk[k] = s
        ot[k] = t0[k]
        k += 1usize
    }
    solve_g(&c, bk)
    solve_g(&c, ot)
    var q1 = zz
    var q2 = 0.0f64
    var q3 = 0.0f64
    k = 0usize
    while k < nt {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += ts[i * nt + k] * zk[i]
            i += 1usize
        }
        q1 = q1 - s * bk[k]
        q2 += t0[k] * ot[k]
        q3 += t0[k] * bk[k]
        k += 1usize
    }
    ret math.sqrt[f64](sigma2 * (1.0f64 - q1) + sigma2 * (q2 - 2.0f64 * q3))
}
