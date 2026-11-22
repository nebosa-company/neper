// R fields: thin plate spline (Tps) and Krig with a stationary covariance (Matern or exponential) at a fixed lambda or the lambda of KrigFindLambda's GCV or REML row (200 point df grid, golden section refinement), in the generalised-ridge form
//     [K + lambda I  T] [c]   [y]
//     [T'            0] [d] = [0]
// with K the covariance (for Tps, Rad.cov with fields' radbas.constant on range-scaled x) and T the polynomial null space of degree m-1 in dmaket order.
// answer() decodes one oracle case: args = [op, idx, ctype, m, lambda, theta, nu, n, d, nq, method, x (n*d, row major), y (n), xq (nq*d)] and returns one number:
//   op 0 d[idx]   1 c[idx]   2 effective df (trace of the hat matrix)   3 GCV at lambda   4 tauHat (GCV)   5 sigma (MLE, rhohat)   6 tauHat (MLE)
//   7 fitted[idx]   8 predict(xq[idx])   9 predictSE(xq[idx])   10 lambda
// method 0 uses lambda as given, 1 the GCV minimum, 2 the REML minimum. ctype 3 is fastTps/mKrig with wendland.cov (k = 2, d = 2, aRange = theta, no scaling): op 12 lnProfileLike, op 14 predictSE.mKrig.
// ctype 0 Tps (x scaled by its range, m given), 1 Krig Matern (theta, smoothness nu), 2 Krig exponential (theta); K is the covariance of the scaled x.
//
// Not here: df= and sigma/tau2= as inputs, replicate rows, knots, weights, lon.lat distances and non-diagonal W.

use e.algo.linalg.decomp as dc
use e.algo.linalg.lapack_syevr as sy
use e.algo.stat.fieldspkg as fp
use e.math
use e.mem

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

fn pi_value() -> f64 { ret 3.14159265358979323846264338327950288f64 }

// gamma at a positive integer or half integer, by recurrence from 1 and sqrt(pi)
fn gamma_half(x: f64) -> f64 {
    var v = x
    var acc = 1.0f64
    while v > 1.25f64 {
        v = v - 1.0f64
        acc = acc * v
    }
    if v < 0.75f64 { ret acc * math.sqrt[f64](pi_value()) }
    ret acc
}

fn gamma_local(x0: f64) -> f64 {
    var x = x0
    if x < 0.0f64 {
        var temp = 1.0f64
        while x < 0.0f64 {
            temp = temp * x
            x = x + 1.0f64
        }
        ret gamma_half(x) / temp
    }
    ret gamma_half(x)
}

fn radbas_constant(m: f64, d: f64) -> f64 {
    let half = d / 2.0f64
    let dd = i64(d)
    if dd % 2i64 == 0i64 {
        var sgn = 1.0f64
        if i64(1.0f64 + m + half) % 2i64 != 0i64 { sgn = -1.0f64 }
        ret sgn * math.pow[f64](2.0f64, 1.0f64 - 2.0f64 * m) * math.pow[f64](pi_value(), 0.0f64 - half) / (gamma_half(m) * gamma_local(m - half + 1.0f64))
    }
    ret gamma_local(half - m) * math.pow[f64](2.0f64, 0.0f64 - 2.0f64 * m) * math.pow[f64](pi_value(), 0.0f64 - half) / gamma_half(m)
}

// the covariance of two scaled points
fn cov_value(ctype: usize, m: f64, theta: f64, nu: f64, rbc: f64, x: []const f64, i: usize, y: []const f64, j: usize, d: usize) -> f64 {
    var r2 = 0.0f64
    var k = 0usize
    while k < d {
        let t = x[i * d + k] - y[j * d + k]
        r2 += t * t
        k += 1usize
    }
    if ctype == 0usize {
        let p = 2.0f64 * m - f64(d)
        if d % 2usize == 0usize {
            if r2 < 1.0e-20f64 { r2 = 1.0e-20f64 }
            ret rbc * 0.5f64 * math.log[f64](r2) * math.pow[f64](r2, p / 2.0f64)
        }
        ret rbc * math.pow[f64](r2, p / 2.0f64)
    }
    let dist = math.sqrt[f64](r2) / theta
    if ctype == 1usize { ret fp.matern(dist, 1.0f64, nu, 1.0f64) }
    if ctype == 3usize {
        // wendland.cov at k = 2 in two dimensions: (1 - r)^6 (35 r^2 + 18 r + 3) / 3 inside the support
        if dist >= 1.0f64 { ret 0.0f64 }
        let om = 1.0f64 - dist
        ret math.pow[f64](om, 6.0f64) * (35.0f64 * dist * dist + 18.0f64 * dist + 3.0f64) / 3.0f64
    }
    ret math.exp[f64](0.0f64 - dist)
}

// the next exponent vector of the same total degree in descending lexicographic order; false at the end
fn next_exponents(e: []usize, d: usize) -> bool {
    if d < 2usize { ret false }
    var j = d - 1usize
    var found = false
    while j > 0usize && !found {
        j -= 1usize
        if e[j] > 0usize { found = true }
    }
    if !found { ret false }
    var after = 0usize
    var q = j + 1usize
    while q < d {
        after += e[q]
        e[q] = 0usize
        q += 1usize
    }
    e[j] -= 1usize
    e[j + 1usize] = after + 1usize
    ret true
}

// the monomial table: nt rows of d exponents, degrees 0..m-1
fn poly_table(a: *mem.Arena, d: usize, m: usize) -> ([]usize, usize, err) {
    var cap = 1usize
    var deg = 0usize
    while deg < m {
        cap = cap + 64usize * (deg + 1usize) * (deg + 1usize)
        deg += 1usize
    }
    let (tab, e1) = mem.alloc[usize](a, cap * d)
    if e1 != ok { ret (tab, 0usize, e1) }
    let (cur, e2) = mem.alloc[usize](a, d)
    if e2 != ok { ret (tab, 0usize, e2) }
    var nt = 0usize
    deg = 0usize
    while deg < m {
        var q = 0usize
        while q < d {
            cur[q] = 0usize
            q += 1usize
        }
        cur[0usize] = deg
        var more = true
        while more {
            q = 0usize
            while q < d {
                tab[nt * d + q] = cur[q]
                q += 1usize
            }
            nt += 1usize
            more = next_exponents(cur, d)
        }
        deg += 1usize
    }
    ret (tab, nt, ok)
}

fn poly_value(tab: []const usize, row: usize, x: []const f64, i: usize, d: usize) -> f64 {
    var v = 1.0f64
    var q = 0usize
    while q < d {
        var k = 0usize
        while k < tab[row * d + q] {
            v = v * x[i * d + q]
            k += 1usize
        }
        q += 1usize
    }
    ret v
}

// in-place Gauss-Jordan inverse with partial pivoting of a size x size matrix; false when singular
fn invert(s: []f64, size: usize, inv: []f64) -> bool {
    var i = 0usize
    while i < size {
        var j = 0usize
        while j < size {
            inv[i * size + j] = 0.0f64
            if i == j { inv[i * size + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    var col = 0usize
    while col < size {
        var piv = col
        var best = math.abs[f64](s[col * size + col])
        var r = col + 1usize
        while r < size {
            let v = math.abs[f64](s[r * size + col])
            if v > best {
                best = v
                piv = r
            }
            r += 1usize
        }
        if best == 0.0f64 { ret false }
        if piv != col {
            var q = 0usize
            while q < size {
                let t1 = s[col * size + q]
                s[col * size + q] = s[piv * size + q]
                s[piv * size + q] = t1
                let t2 = inv[col * size + q]
                inv[col * size + q] = inv[piv * size + q]
                inv[piv * size + q] = t2
                q += 1usize
            }
        }
        let p = 1.0f64 / s[col * size + col]
        var q = 0usize
        while q < size {
            s[col * size + q] = s[col * size + q] * p
            inv[col * size + q] = inv[col * size + q] * p
            q += 1usize
        }
        r = 0usize
        while r < size {
            if r != col {
                let f = s[r * size + col]
                if f != 0.0f64 {
                    q = 0usize
                    while q < size {
                        s[r * size + q] = s[r * size + q] - f * s[col * size + q]
                        inv[r * size + q] = inv[r * size + q] - f * inv[col * size + q]
                        q += 1usize
                    }
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    ret true
}

// GCV score at lambda from the eigenvalues D (nt zeros first) and the rotated data u: Krig.fgcv with cost 1 and offset 0
fn fgcv(dd: []const f64, u: []const f64, n: usize, nt: usize, lam: f64) -> f64 {
    var rss = 0.0f64
    var tra = 0.0f64
    var i = 0usize
    while i < n {
        let ld = dd[i] * lam
        let t = u[i] * ld / (1.0f64 + ld)
        rss += t * t
        tra += 1.0f64 / (1.0f64 + ld)
        i += 1usize
    }
    let nf = f64(n)
    let den = 1.0f64 - (tra - f64(nt) + f64(nt)) / nf
    if den > 0.0f64 { ret rss / nf / (den * den) }
    ret 1.0e20f64
}

// Krig.flplike: minus the restricted log likelihood profiled over sigma
fn flplike(dd: []const f64, u: []const f64, n: usize, nt: usize, lam: f64) -> f64 {
    let n2 = f64(n - nt)
    var s = 0.0f64
    var lnd = 0.0f64
    var i = nt
    while i < n {
        let ld = dd[i] * lam
        s += dd[i] * u[i] * u[i] / (1.0f64 + ld)
        lnd += math.log[f64](dd[i] / (1.0f64 + ld))
        i += 1usize
    }
    let sigma2 = s / n2
    let lndet = 0.0f64 - lnd
    ret 0.0f64 - (0.0f64 - n2 / 2.0f64 - math.log[f64](2.0f64 * pi_value()) * (n2 / 2.0f64) - (n2 / 2.0f64) * math.log[f64](sigma2) - lndet / 2.0f64)
}

fn objective(method: usize, dd: []const f64, u: []const f64, n: usize, nt: usize, lam: f64) -> f64 {
    if method == 1usize { ret fgcv(dd, u, n, nt, lam) }
    ret flplike(dd, u, n, nt, lam)
}

fn trace_of(dd: []const f64, n: usize, lam: f64) -> f64 {
    var tra = 0.0f64
    var i = 0usize
    while i < n {
        tra += 1.0f64 / (1.0f64 + lam * dd[i])
        i += 1usize
    }
    ret tra
}

// Krig.df.to.lambda: bracket by factors of 4 from 1, then bisection on log lambda (tol 1e-5, at most 25 steps)
fn df_to_lambda(dd: []const f64, n: usize, df: f64) -> f64 {
    var l1 = 1.0f64
    var k = 0usize
    var going = true
    while k < 25usize && going {
        if trace_of(dd, n, l1) <= df { going = false }
        if going { l1 = l1 * 4.0f64 }
        k += 1usize
    }
    var l2 = 1.0f64
    k = 0usize
    going = true
    while k < 25usize && going {
        if trace_of(dd, n, l2) >= df { going = false }
        if going { l2 = l2 / 4.0f64 }
        k += 1usize
    }
    var x1 = math.log[f64](l1)
    var x2 = math.log[f64](l2)
    k = 0usize
    going = true
    while k < 25usize && going {
        let xm = (x1 + x2) / 2.0f64
        let fm = trace_of(dd, n, math.exp[f64](xm)) - df
        if fm < 0.0f64 { x1 = xm }
        if fm >= 0.0f64 { x2 = xm }
        if math.abs[f64](fm) < 1.0e-5f64 { going = false }
        k += 1usize
    }
    ret math.exp[f64]((x1 + x2) / 2.0f64)
}

// KrigFindLambda for the GCV (method 1) or REML (method 2) row: a 200 point grid in effective df, the best point refined by golden section search
fn find_lambda(a: *mem.Arena, dd: []const f64, u: []const f64, n: usize, nt: usize, method: usize) -> f64 {
    let ng = 200usize
    let (grid, e1) = mem.alloc[f64](a, ng)
    if e1 != ok { ret nan_value() }
    let from = f64(nt)
    let to = f64(n) * 0.95f64
    let by = (to - from) / f64(ng - 1usize)
    var k = 0usize
    while k < ng {
        var df = from + f64(k) * by
        if k == 0usize { df = from + 0.001f64 }
        if k == ng - 1usize { df = to }
        grid[k] = df_to_lambda(dd, n, df)
        k += 1usize
    }
    // sort ascending (insertion)
    k = 1usize
    while k < ng {
        let v = grid[k]
        var j = k
        while j > 0usize && grid[j - 1usize] > v {
            grid[j] = grid[j - 1usize]
            j -= 1usize
        }
        grid[j] = v
        k += 1usize
    }
    var imin = 0usize
    var best = objective(method, dd, u, n, nt, grid[0usize])
    k = 1usize
    while k < ng {
        let v = objective(method, dd, u, n, nt, grid[k])
        if v < best {
            best = v
            imin = k
        }
        k += 1usize
    }
    if imin == 0usize || imin == ng - 1usize { ret grid[imin] }
    let ax = grid[imin - 1usize]
    let bx = grid[imin]
    let cx = grid[imin + 1usize]
    let r = 0.61803399f64
    let con = 1.0f64 - r
    var x0 = ax
    var x3 = cx
    var x1 = 0.0f64
    var x2 = 0.0f64
    if math.abs[f64](cx - bx) > math.abs[f64](bx - ax) {
        x1 = bx
        x2 = bx + con * (bx - ax)
    } else {
        x2 = bx
        x1 = bx - con * (bx - ax)
    }
    var f1 = objective(method, dd, u, n, nt, x1)
    var f2 = objective(method, dd, u, n, nt, x2)
    k = 0usize
    var going = true
    while k < 25usize && going {
        if f2 < f1 {
            x0 = x1
            x1 = x2
            x2 = r * x1 + con * x3
            f1 = f2
            f2 = objective(method, dd, u, n, nt, x2)
        } else {
            x3 = x2
            x2 = x1
            x1 = r * x2 + con * x0
            f2 = f1
            f1 = objective(method, dd, u, n, nt, x1)
        }
        k += 1usize
        if math.abs[f64](f2 - f1) < 1.0e-5f64 { going = false }
    }
    if f1 < f2 { ret x1 }
    ret x2
}

// D (nt zeros, then the inverse eigenvalues of Q2' K Q2 ascending) and u (the data rotated onto those eigenvectors) of Krig.engine.default
fn eigen_du(a: *mem.Arena, qf: *const dc.Qr, z: []f64, kmat: []const f64, y: []const f64, n: usize, nt: usize, dd: []f64, u: []f64) -> err {
    let m = n - nt
    let (c1, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret e1 }
    let (c2, e2) = mem.alloc[f64](a, n * n)
    if e2 != ok { ret e2 }
    let (col, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret e3 }
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            col[i] = kmat[i * n + j]
            i += 1usize
        }
        dc.qr_qty(qf, col)
        i = 0usize
        while i < n {
            c1[j * n + i] = col[i]
            i += 1usize
        }
        j += 1usize
    }
    // c1[., j] = Q' K[., j]; row r of c1 transformed gives (Q' K Q)[r, .]
    var r = 0usize
    while r < n {
        var i = 0usize
        while i < n {
            col[i] = c1[i * n + r]
            i += 1usize
        }
        dc.qr_qty(qf, col)
        i = 0usize
        while i < n {
            c2[r * n + i] = col[i]
            i += 1usize
        }
        r += 1usize
    }
    let (sub, e4) = mem.alloc[f64](a, m * m)
    if e4 != ok { ret e4 }
    var ci = 0usize
    while ci < m {
        var ri = 0usize
        while ri < m {
            sub[ci * m + ri] = c2[(nt + ri) * n + (nt + ci)]
            ri += 1usize
        }
        ci += 1usize
    }
    let (w, e5) = mem.alloc[f64](a, m)
    if e5 != ok { ret e5 }
    let ee = sy.dsyevr_all(a, sub, m, w, z)
    if ee != ok { ret ee }
    var i = 0usize
    while i < n {
        col[i] = y[i]
        i += 1usize
    }
    dc.qr_qty(qf, col)
    i = 0usize
    while i < nt {
        dd[i] = 0.0f64
        u[i] = 0.0f64
        i += 1usize
    }
    var q = 0usize
    while q < m {
        let src = m - 1usize - q
        dd[nt + q] = 1.0f64 / w[src]
        var acc = 0.0f64
        var t = 0usize
        while t < m {
            acc += z[src * m + t] * col[nt + t]
            t += 1usize
        }
        u[nt + q] = acc
        q += 1usize
    }
    ret ok
}

// Krig.coef for the WBW decomposition: c = Q2 V (D / (1 + lambda D)) u, then d from the least squares fit of y - K c on the null space; cd = [c; d]
fn coefs(a: *mem.Arena, qf: *const dc.Qr, z: []const f64, dd: []const f64, u: []const f64, kmat: []const f64, y: []const f64, n: usize, nt: usize, lambda: f64, cd: []f64) -> err {
    let m = n - nt
    let (col, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < nt {
        col[i] = 0.0f64
        i += 1usize
    }
    var r = 0usize
    while r < m {
        var acc = 0.0f64
        var q = 0usize
        while q < m {
            let src = m - 1usize - q
            let ld = dd[nt + q] * lambda
            acc += z[src * m + r] * (dd[nt + q] / (1.0f64 + ld)) * u[nt + q]
            q += 1usize
        }
        col[nt + r] = acc
        r += 1usize
    }
    dc.qr_qy(qf, col)
    i = 0usize
    while i < n {
        cd[i] = col[i]
        i += 1usize
    }
    // y - K c, rotated: R d = (Q' (y - K c))[0:nt]
    i = 0usize
    while i < n {
        var acc = y[i]
        var j = 0usize
        while j < n {
            acc -= kmat[i * n + j] * cd[j]
            j += 1usize
        }
        col[i] = acc
        i += 1usize
    }
    dc.qr_qty(qf, col)
    var jj = nt
    while jj > 0usize {
        jj -= 1usize
        var acc = col[jj]
        var q = jj + 1usize
        while q < nt {
            acc -= qf.qr[q * n + jj] * cd[n + q]
            q += 1usize
        }
        cd[n + jj] = acc / qf.qr[jj * n + jj]
    }
    ret ok
}

fn answer(a: *mem.Arena, g: []const f64) -> f64 {
    let op = usize(g[0usize])
    let idx = usize(g[1usize])
    let ctype = usize(g[2usize])
    let m = usize(g[3usize])
    var lambda = g[4usize]
    let theta = g[5usize]
    let nu = g[6usize]
    let n = usize(g[7usize])
    let d = usize(g[8usize])
    let nq = usize(g[9usize])
    let method = usize(g[10usize])
    let (x, e1) = mem.alloc[f64](a, n * d)
    if e1 != ok { ret nan_value() }
    let (xq, e2) = mem.alloc[f64](a, nq * d + 1usize)
    if e2 != ok { ret nan_value() }
    var k = 0usize
    while k < n * d {
        x[k] = g[11usize + k]
        k += 1usize
    }
    let ybase = 11usize + n * d
    let qbase = ybase + n
    k = 0usize
    while k < nq * d {
        xq[k] = g[qbase + k]
        k += 1usize
    }
    // op 15: query idx inside the convex hull of x (predictSurface with extrap = FALSE leaves the other grid nodes NA)
    if op == 15usize {
        if fp.in_hull(x, n, d, xq[idx * d], xq[idx * d + 1usize]) { ret 1.0f64 }
        ret 0.0f64
    }
    if ctype == 0usize {
        var q = 0usize
        while q < d {
            var lo = x[q]
            var hi = x[q]
            var i = 1usize
            while i < n {
                if x[i * d + q] < lo { lo = x[i * d + q] }
                if x[i * d + q] > hi { hi = x[i * d + q] }
                i += 1usize
            }
            i = 0usize
            while i < n {
                x[i * d + q] = (x[i * d + q] - lo) / (hi - lo)
                i += 1usize
            }
            i = 0usize
            while i < nq {
                xq[i * d + q] = (xq[i * d + q] - lo) / (hi - lo)
                i += 1usize
            }
            q += 1usize
        }
    }
    let (tab, nt, e3) = poly_table(a, d, m)
    if e3 != ok { ret nan_value() }
    let size = n + nt
    let mf = f64(m)
    var rbc = 1.0f64
    if ctype == 0usize { rbc = radbas_constant(mf, f64(d)) }
    let (kmat, e4) = mem.alloc[f64](a, n * n)
    if e4 != ok { ret nan_value() }
    let (tcol, e5) = mem.alloc[f64](a, n * nt)
    if e5 != ok { ret nan_value() }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            kmat[i * n + j] = cov_value(ctype, mf, theta, nu, rbc, x, i, x, j, d)
            j += 1usize
        }
        j = 0usize
        while j < nt {
            tcol[j * n + i] = poly_value(tab, j, x, i, d)
            j += 1usize
        }
        i += 1usize
    }
    let (dd, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret nan_value() }
    let (uu, e7) = mem.alloc[f64](a, n)
    if e7 != ok { ret nan_value() }
    let (yv, e8) = mem.alloc[f64](a, n)
    if e8 != ok { ret nan_value() }
    i = 0usize
    while i < n {
        yv[i] = g[ybase + i]
        i += 1usize
    }
    let (qf, e0) = dc.qr(a, tcol, n, nt, 1.0e-7f64)
    if e0 != ok { ret nan_value() }
    let (zm, e0b) = mem.alloc[f64](a, (n - nt) * (n - nt))
    if e0b != ok { ret nan_value() }
    let ed = eigen_du(a, &qf, zm, kmat, yv, n, nt, dd, uu)
    if ed != ok { ret nan_value() }
    if method > 0usize { lambda = find_lambda(a, dd, uu, n, nt, method) }
    if op == 10usize { ret lambda }
    let nf = f64(n)
    let tra = trace_of(dd, n, lambda)
    var rss = 0.0f64
    i = 0usize
    while i < n {
        let ld = dd[i] * lambda
        let t = uu[i] * ld / (1.0f64 + ld)
        rss += t * t
        i += 1usize
    }
    if op == 2usize { ret tra }
    if op == 3usize { ret fgcv(dd, uu, n, nt, lambda) }
    if op == 4usize { ret math.sqrt[f64](rss / (nf - tra)) }
    let (s, e9) = mem.alloc[f64](a, size * size)
    if e9 != ok { ret nan_value() }
    let (inv, e10) = mem.alloc[f64](a, size * size)
    if e10 != ok { ret nan_value() }
    i = 0usize
    while i < size * size {
        s[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            s[i * size + j] = kmat[i * n + j]
            j += 1usize
        }
        s[i * size + i] = s[i * size + i] + lambda
        j = 0usize
        while j < nt {
            let t = tcol[j * n + i]
            s[i * size + n + j] = t
            s[(n + j) * size + i] = t
            j += 1usize
        }
        i += 1usize
    }
    if !invert(s, size, inv) { ret nan_value() }
    // [c; d] = inv * [y; 0]
    let (cd, e11) = mem.alloc[f64](a, size)
    if e11 != ok { ret nan_value() }
    i = 0usize
    while i < size {
        var acc = 0.0f64
        var j = 0usize
        while j < n {
            acc += inv[i * size + j] * yv[j]
            j += 1usize
        }
        cd[i] = acc
        i += 1usize
    }
    if coefs(a, &qf, zm, dd, uu, kmat, yv, n, nt, lambda, cd) != ok { ret nan_value() }
    if op == 0usize { ret cd[n + idx] }
    if op == 1usize { ret cd[idx] }
    var cy = 0.0f64
    i = 0usize
    while i < n {
        cy += cd[i] * yv[i]
        i += 1usize
    }
    let sigma = cy / nf
    if op == 5usize { ret sigma }
    if op == 6usize { ret math.sqrt[f64](lambda * sigma) }
    if op == 7usize { ret yv[idx] - lambda * cd[idx] }
    if op == 12usize {
        // lnProfileLike of mKrig: -n/2 - n/2 log(2 pi) - n/2 log(sigma2.MLE) - log det(K + lambda I) / 2
        let (ch, e15) = mem.alloc[f64](a, n * n)
        if e15 != ok { ret nan_value() }
        var lnd = 0.0f64
        var cj = 0usize
        while cj < n {
            var dsum = kmat[cj * n + cj] + lambda
            var kk = 0usize
            while kk < cj {
                dsum -= ch[cj * n + kk] * ch[cj * n + kk]
                kk += 1usize
            }
            let lj = math.sqrt[f64](dsum)
            ch[cj * n + cj] = lj
            lnd += 2.0f64 * math.log[f64](lj)
            var ri = cj + 1usize
            while ri < n {
                var v = kmat[ri * n + cj]
                kk = 0usize
                while kk < cj {
                    v -= ch[ri * n + kk] * ch[cj * n + kk]
                    kk += 1usize
                }
                ch[ri * n + cj] = v / lj
                ri += 1usize
            }
            cj += 1usize
        }
        ret 0.0f64 - nf / 2.0f64 - math.log[f64](2.0f64 * pi_value()) * (nf / 2.0f64) - (nf / 2.0f64) * math.log[f64](sigma) - lnd / 2.0f64
    }
    // the covariance and null-space columns at the query point
    let (kv, e12) = mem.alloc[f64](a, size)
    if e12 != ok { ret nan_value() }
    i = 0usize
    while i < n {
        kv[i] = cov_value(ctype, mf, theta, nu, rbc, x, i, xq, idx, d)
        i += 1usize
    }
    var j = 0usize
    while j < nt {
        kv[n + j] = poly_value(tab, j, xq, idx, d)
        j += 1usize
    }
    if op == 8usize {
        var acc = 0.0f64
        i = 0usize
        while i < size {
            acc += kv[i] * cd[i]
            i += 1usize
        }
        ret acc
    }
    if op == 14usize {
        // predictSE.mKrig: sigma2 (1 - k'c_k + t' Omega t - 2 t' d_k) with [c_k; d_k] = inv [k; 0] and Omega = (T' M^-1 T)^-1 = -inv[dd]
        let (sol, e14) = mem.alloc[f64](a, size)
        if e14 != ok { ret nan_value() }
        i = 0usize
        while i < size {
            var acc = 0.0f64
            j = 0usize
            while j < n {
                acc += inv[i * size + j] * kv[j]
                j += 1usize
            }
            sol[i] = acc
            i += 1usize
        }
        var q1 = 0.0f64
        i = 0usize
        while i < n {
            q1 += kv[i] * sol[i]
            i += 1usize
        }
        var q2 = 0.0f64
        var q3 = 0.0f64
        i = 0usize
        while i < nt {
            q3 += kv[n + i] * sol[n + i]
            j = 0usize
            while j < nt {
                q2 -= kv[n + i] * inv[(n + i) * size + n + j] * kv[n + j]
                j += 1usize
            }
            i += 1usize
        }
        ret math.sqrt[f64](sigma * (1.0f64 - q1 + q2 - 2.0f64 * q3))
    }
    // predictSE: weights w (first n entries of inv * [k; t]); sigma2 K and tau2 I as the data covariance
    let (w, e13) = mem.alloc[f64](a, n)
    if e13 != ok { ret nan_value() }
    i = 0usize
    while i < n {
        var acc = 0.0f64
        j = 0usize
        while j < size {
            acc += inv[i * size + j] * kv[j]
            j += 1usize
        }
        w[i] = acc
        i += 1usize
    }
    var marg = 0.0f64
    if ctype != 0usize { marg = 1.0f64 }
    var t1 = 0.0f64
    i = 0usize
    while i < n {
        t1 += w[i] * kv[i]
        i += 1usize
    }
    var t2 = 0.0f64
    i = 0usize
    while i < n {
        j = 0usize
        while j < n {
            var cy2 = sigma * kmat[i * n + j]
            if i == j { cy2 = cy2 + lambda * sigma }
            t2 += w[i] * cy2 * w[j]
            j += 1usize
        }
        i += 1usize
    }
    ret math.sqrt[f64](sigma * marg - 2.0f64 * sigma * t1 + t2)
}
