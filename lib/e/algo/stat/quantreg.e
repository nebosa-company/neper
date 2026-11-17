// R quantreg, the point estimate: `rq` for one tau. The linear program min tau*sum(u) + (1-tau)*sum(v) subject to
// X b + u - v = y is solved through its dual by a primal-dual interior-point iteration (the idea of rq.fn,
// Frisch-Newton), and the answer is then polished to the exact vertex: the p observations with the smallest
// residuals fix b by a p by p solve. Data in general position (no ties among the fitted vertices) give the unique
// optimum that method "br" returns.
//
// Not here: summary.rq (rank, iid, nid, ker, boot), anova.rq, nlrq, rrq, rqss, dynrq, lasso, pfn and several taus
// in one call.

use e.algo.linalg.decomp as decomp
use e.math
use e.math.dist as dist
use e.mem
use e.algo.stat.bayesmpkg as bz

// x is n by p column-major
fn loss(x: []const f64, y: []const f64, n: usize, p: usize, b: []const f64, tau: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var r = y[i]
        var j = 0usize
        while j < p {
            r -= x[j * n + i] * b[j]
            j += 1usize
        }
        if r >= 0.0f64 { s += tau * r } else { s += (tau - 1.0f64) * r }
        i += 1usize
    }
    ret s
}

// solve the p by p system m z = r (row-major m) in place by Gaussian elimination with partial pivoting; false if singular
fn solve_dense(m: []f64, r: []f64, p: usize) -> bool {
    var c = 0usize
    while c < p {
        var piv = c
        var best = math.abs[f64](m[c * p + c])
        var i = c + 1usize
        while i < p {
            let v = math.abs[f64](m[i * p + c])
            if v > best {
                best = v
                piv = i
            }
            i += 1usize
        }
        if best < 1.0e-300f64 { ret false }
        if piv != c {
            var k = 0usize
            while k < p {
                let t = m[c * p + k]
                m[c * p + k] = m[piv * p + k]
                m[piv * p + k] = t
                k += 1usize
            }
            let t = r[c]
            r[c] = r[piv]
            r[piv] = t
        }
        i = c + 1usize
        while i < p {
            let f = m[i * p + c] / m[c * p + c]
            var k = c
            while k < p {
                m[i * p + k] -= f * m[c * p + k]
                k += 1usize
            }
            r[i] -= f * r[c]
            i += 1usize
        }
        c += 1usize
    }
    var ii = p
    while ii > 0usize {
        ii -= 1usize
        var s = r[ii]
        var k = ii + 1usize
        while k < p {
            s -= m[ii * p + k] * r[k]
            k += 1usize
        }
        r[ii] = s / m[ii * p + ii]
    }
    ret true
}

fn max_step(v: []const f64, dv: []const f64, n: usize) -> f64 {
    var t = 1.0f64
    var i = 0usize
    while i < n {
        if dv[i] < 0.0f64 {
            let c = 0.0f64 - v[i] / dv[i]
            if c < t { t = c }
        }
        i += 1usize
    }
    ret t
}

fn rq(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64) -> ([]f64, err) {
    let (b, e0) = mem.alloc[f64](a, p)
    let (u, e1) = mem.alloc[f64](a, n)
    let (v, e2) = mem.alloc[f64](a, n)
    let (al, e3) = mem.alloc[f64](a, n)
    let (s, e4) = mem.alloc[f64](a, n)
    let (du, e5) = mem.alloc[f64](a, n)
    let (dv, e6) = mem.alloc[f64](a, n)
    let (dal, e7) = mem.alloc[f64](a, n)
    let (ds, e8) = mem.alloc[f64](a, n)
    let (w, e9) = mem.alloc[f64](a, n)
    let (q, e10) = mem.alloc[f64](a, n)
    let (mat, e11) = mem.alloc[f64](a, p * p)
    let (rhs, e12) = mem.alloc[f64](a, p)
    let (rh2, e13) = mem.alloc[f64](a, p)
    if e0 != ok { ret (b, e0) }
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret (b, e1) }
    let (ols, le) = decomp.lm_fit(a, x, n, p, y, 1.0e-9f64)
    if le != ok { ret (b, le) }
    var j = 0usize
    while j < p {
        b[j] = ols.coef[j]
        j += 1usize
    }
    var scale = 0.0f64
    var i = 0usize
    while i < n {
        scale += math.abs[f64](ols.residuals[i])
        i += 1usize
    }
    let delta = 0.01f64 * scale / f64(n) + 1.0e-8f64
    i = 0usize
    while i < n {
        let r = ols.residuals[i]
        if r > 0.0f64 {
            u[i] = r + delta
            v[i] = delta
        } else {
            u[i] = delta
            v[i] = delta - r
        }
        al[i] = 1.0f64 - tau
        s[i] = tau
        i += 1usize
    }
    var it = 0usize
    while it < 200usize {
        var gap = 0.0f64
        i = 0usize
        while i < n {
            gap += u[i] * s[i] + v[i] * al[i]
            i += 1usize
        }
        if gap < 1.0e-13f64 * (scale + 1.0f64) { break }
        let mu = 0.1f64 * gap / (2.0f64 * f64(n))
        // residuals of the three feasibility systems
        i = 0usize
        while i < n {
            var xb = 0.0f64
            j = 0usize
            while j < p {
                xb += x[j * n + i] * b[j]
                j += 1usize
            }
            let r1 = y[i] - xb - u[i] + v[i]
            let r3 = 1.0f64 - al[i] - s[i]
            let c1 = mu - u[i] * s[i]
            let c2 = mu - v[i] * al[i]
            w[i] = 1.0f64 / (u[i] / s[i] + v[i] / al[i])
            q[i] = r1 - (c1 - u[i] * r3) / s[i] + c2 / al[i]
            i += 1usize
        }
        j = 0usize
        while j < p {
            var xa = 0.0f64
            i = 0usize
            while i < n {
                xa += x[j * n + i] * al[i]
                i += 1usize
            }
            var tot = 0.0f64
            i = 0usize
            while i < n {
                tot += x[j * n + i]
                i += 1usize
            }
            let r2 = (1.0f64 - tau) * tot - xa
            var xwq = 0.0f64
            i = 0usize
            while i < n {
                xwq += x[j * n + i] * w[i] * q[i]
                i += 1usize
            }
            rhs[j] = xwq - r2
            var k = 0usize
            while k < p {
                var m = 0.0f64
                i = 0usize
                while i < n {
                    m += x[j * n + i] * w[i] * x[k * n + i]
                    i += 1usize
                }
                mat[j * p + k] = m
                k += 1usize
            }
            j += 1usize
        }
        if !solve_dense(mat, rhs, p) { break }
        i = 0usize
        while i < n {
            var xd = 0.0f64
            j = 0usize
            while j < p {
                xd += x[j * n + i] * rhs[j]
                j += 1usize
            }
            dal[i] = w[i] * (q[i] - xd)
            let r3 = 1.0f64 - al[i] - s[i]
            ds[i] = r3 - dal[i]
            du[i] = ((mu - u[i] * s[i]) - u[i] * ds[i]) / s[i]
            dv[i] = ((mu - v[i] * al[i]) - v[i] * dal[i]) / al[i]
            i += 1usize
        }
        var tp = max_step(u, du, n)
        let t2 = max_step(v, dv, n)
        if t2 < tp { tp = t2 }
        var td = max_step(al, dal, n)
        let t3 = max_step(s, ds, n)
        if t3 < td { td = t3 }
        tp = 0.9995f64 * tp
        td = 0.9995f64 * td
        if tp > 1.0f64 { tp = 1.0f64 }
        if td > 1.0f64 { td = 1.0f64 }
        j = 0usize
        while j < p {
            b[j] += tp * rhs[j]
            j += 1usize
        }
        i = 0usize
        while i < n {
            u[i] += tp * du[i]
            v[i] += tp * dv[i]
            al[i] += td * dal[i]
            s[i] += td * ds[i]
            i += 1usize
        }
        it += 1usize
    }
    // polish: the p smallest |residuals| define the vertex
    let (res, re) = mem.alloc[f64](a, n)
    let (used, ue) = mem.alloc[bool](a, n)
    if re != ok || ue != ok { ret (b, re) }
    i = 0usize
    while i < n {
        var r = y[i]
        j = 0usize
        while j < p {
            r -= x[j * n + i] * b[j]
            j += 1usize
        }
        res[i] = math.abs[f64](r)
        used[i] = false
        i += 1usize
    }
    let (rows, rwe) = mem.alloc[usize](a, p)
    if rwe != ok { ret (b, rwe) }
    var pick = 0usize
    while pick < p {
        var bi = n
        i = 0usize
        while i < n {
            if !used[i] && (bi == n || res[i] < res[bi]) { bi = i }
            i += 1usize
        }
        used[bi] = true
        rows[pick] = bi
        pick += 1usize
    }
    pick = 0usize
    while pick < p {
        j = 0usize
        while j < p {
            mat[pick * p + j] = x[j * n + rows[pick]]
            j += 1usize
        }
        rh2[pick] = y[rows[pick]]
        pick += 1usize
    }
    if solve_dense(mat, rh2, p) && loss(x, y, n, p, rh2, tau) <= loss(x, y, n, p, b, tau) + 1.0e-12f64 {
        j = 0usize
        while j < p {
            b[j] = rh2[j]
            j += 1usize
        }
    }
    ret (b, ok)
}

// bandwidth.rq(p, n, hs = TRUE, alpha = 0.05)
fn bandwidth_rq(p: f64, n: f64, hs: bool) -> f64 {
    let x0 = dist_qn(p)
    let f0 = math.exp[f64](0.0f64 - x0 * x0 / 2.0f64) * 0.3989422804014327f64
    if hs { ret math.pow[f64](n, 0.0f64 - 1.0f64 / 3.0f64) * math.pow[f64](dist_qn(0.975f64), 2.0f64 / 3.0f64) * math.pow[f64]((1.5f64 * f0 * f0) / (2.0f64 * x0 * x0 + 1.0f64), 1.0f64 / 3.0f64) }
    ret math.pow[f64](n, 0.0f64 - 0.2f64) * math.pow[f64]((4.5f64 * f0 * f0 * f0 * f0) / ((2.0f64 * x0 * x0 + 1.0f64) * (2.0f64 * x0 * x0 + 1.0f64)), 0.2f64)
}

// summary.rq(se = "nid") standard errors: the Hall-Sheather bandwidth (halved while tau +- h leaves (0, 1)), the local density f = max(0, 2 h / (x (b(tau + h) - b(tau - h)) - eps)) and the sandwich tau (1 - tau) D^-1 X'X D^-1 with D = X' diag(f) X
fn rq_se_nid(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, se: []f64) -> err {
    var h = bandwidth_rq(tau, f64(n), true)
    while tau - h < 0.0f64 || tau + h > 1.0f64 { h = h / 2.0f64 }
    let (bhi, e1) = rq(a, x, y, n, p, tau + h)
    if e1 != ok { ret e1 }
    let (blo, e2) = rq(a, x, y, n, p, tau - h)
    if e2 != ok { ret e2 }
    let (f, e3) = mem.alloc[f64](a, n)
    let (dm, e4) = mem.alloc[f64](a, p * p)
    let (xx, e5) = mem.alloc[f64](a, p * p)
    let (u, e6) = mem.alloc[f64](a, p * p)
    let (ui, e7) = mem.alloc[f64](a, p * p)
    let (di, e8) = mem.alloc[f64](a, p * p)
    let (tmp, e9) = mem.alloc[f64](a, p * p)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    let eps = 1.4901161193847656e-8f64
    var i = 0usize
    while i < n {
        var dy = 0.0f64
        var j = 0usize
        while j < p {
            dy += x[j * n + i] * (bhi[j] - blo[j])
            j += 1usize
        }
        var fv = 2.0f64 * h / (dy - eps)
        if !(fv > 0.0f64) { fv = 0.0f64 }
        f[i] = fv
        i += 1usize
    }
    var c = 0usize
    while c < p {
        var c2 = 0usize
        while c2 < p {
            var sd = 0.0f64
            var sx = 0.0f64
            i = 0usize
            while i < n {
                sd += x[c * n + i] * f[i] * x[c2 * n + i]
                sx += x[c * n + i] * x[c2 * n + i]
                i += 1usize
            }
            dm[c2 * p + c] = sd
            xx[c2 * p + c] = sx
            c2 += 1usize
        }
        c += 1usize
    }
    if !bz.chol_upper(dm, p, u) { ret mem.Full }
    bz.inv_upper(u, p, ui)
    // D^-1 = Ui Ui'
    c = 0usize
    while c < p {
        var c2 = 0usize
        while c2 < p {
            var sv = 0.0f64
            var q = 0usize
            while q < p {
                sv += ui[q * p + c] * ui[q * p + c2]
                q += 1usize
            }
            di[c2 * p + c] = sv
            c2 += 1usize
        }
        c += 1usize
    }
    // tmp = XX D^-1
    c = 0usize
    while c < p {
        var c2 = 0usize
        while c2 < p {
            var sv = 0.0f64
            var q = 0usize
            while q < p {
                sv += xx[q * p + c] * di[c2 * p + q]
                q += 1usize
            }
            tmp[c2 * p + c] = sv
            c2 += 1usize
        }
        c += 1usize
    }
    c = 0usize
    while c < p {
        // diag of D^-1 tmp
        var sv = 0.0f64
        var q = 0usize
        while q < p {
            sv += di[q * p + c] * tmp[c * p + q]
            q += 1usize
        }
        se[c] = math.sqrt[f64](tau * (1.0f64 - tau) * sv)
        c += 1usize
    }
    ret ok
}

fn dist_qn(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }
