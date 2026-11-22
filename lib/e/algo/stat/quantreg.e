// R quantreg, the point estimate: `rq` for one tau. The linear program min tau*sum(u) + (1-tau)*sum(v) subject to
// X b + u - v = y is solved through its dual by a primal-dual interior-point iteration (the idea of rq.fn,
// Frisch-Newton), and the answer is then polished to the exact vertex: the p observations with the smallest
// residuals fix b by a p by p solve. Data in general position (no ties among the fitted vertices) give the unique
// optimum that method "br" returns.
//
// Also here: summary.rq, anova.rq, rq.fit.fnb/fnc (rrq), lasso, pfn, nlrq (three built-in models), dynrq (lags and trend) and
// rqss with the total-variation penalty (one qss term).

use e.algo.linalg.decomp as decomp
use e.math
use e.math.dist as dist
use e.mem
use e.algo.stat.bayesmpkg as bz
use e.algo.rand.r as rr
use e.math.nmath_beta as nb
use e.math.nchisq as nc
use e.algo.stat.lbfgsb as lbf

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

// rq.fit.br(x, y, tau): the Barrodale-Roberts simplex, coefficients only
fn rq(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64) -> ([]f64, err) {
    let (b, e0) = mem.alloc[f64](a, p)
    let (dual, e1) = mem.alloc[f64](a, n)
    let (ci, e2) = mem.alloc[f64](a, 4usize * p)
    let (tn, e3) = mem.alloc[f64](a, 4usize * p)
    let (qn, e4) = mem.alloc[f64](a, p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (b, mem.Full) }
    let tol = math.pow[f64](2.220446049250313e-16f64, 2.0f64 / 3.0f64)
    let (ift, re) = rqbr(a, n, p, x, y, tau, tol, 1.7976931348623157e308f64, false, qn, 0.0f64, b, dual, ci, tn)
    if re != ok { ret (b, re) }
    ret (b, ok)
}

// the earlier interior-point fit with a vertex polish, kept for reference; it can pick a different vertex than br when the optimum is not unique
fn rq_ip(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64) -> ([]f64, err) {
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
    let (cov, e1) = mem.alloc[f64](a, p * p)
    let (hinv, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret mem.Full }
    ret rq_cov_nid(a, x, y, n, p, tau, se, cov, hinv)
}

// summary.rq(se = "nid", covariance = TRUE): the standard errors, the covariance matrix and Hinv (fxxinv)
fn rq_cov_nid(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, se: []f64, cov: []f64, hinv: []f64) -> err {
    var h = bandwidth_rq(tau, f64(n), true)
    while tau - h < 0.0f64 || tau + h > 1.0f64 { h = h / 2.0f64 }
    let (bhi, e1) = rq(a, x, y, n, p, tau + h)
    if e1 != ok { ret e1 }
    let (blo, e2) = rq(a, x, y, n, p, tau - h)
    if e2 != ok { ret e2 }
    let (f, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret mem.Full }
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
    ret rq_sandwich_full(a, x, f, n, p, tau, se, cov, hinv)
}

// the sandwich tau (1 - tau) D^-1 X'X D^-1 with D = X' diag(f) X: cov the matrix, hinv = D^-1, se the square roots of the diagonal
fn rq_sandwich_full(a: *mem.Arena, x: []const f64, f: []const f64, n: usize, p: usize, tau: f64, se: []f64, cov: []f64, hinv: []f64) -> err {
    let (dm, e4) = mem.alloc[f64](a, p * p)
    let (xx, e5) = mem.alloc[f64](a, p * p)
    let (u, e6) = mem.alloc[f64](a, p * p)
    let (ui, e7) = mem.alloc[f64](a, p * p)
    let (di, e8) = mem.alloc[f64](a, p * p)
    let (tmp, e9) = mem.alloc[f64](a, p * p)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    var i = 0usize
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
        var c2 = 0usize
        while c2 < p {
            var sv = 0.0f64
            var q = 0usize
            while q < p {
                sv += di[q * p + c] * tmp[c2 * p + q]
                q += 1usize
            }
            cov[c2 * p + c] = tau * (1.0f64 - tau) * sv
            hinv[c2 * p + c] = di[c2 * p + c]
            c2 += 1usize
        }
        se[c] = math.sqrt[f64](cov[c * p + c])
        c += 1usize
    }
    ret ok
}

fn rq_sandwich(a: *mem.Arena, x: []const f64, f: []const f64, n: usize, p: usize, tau: f64, se: []f64) -> err {
    let (cov, e1) = mem.alloc[f64](a, p * p)
    let (hinv, e2) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok { ret mem.Full }
    ret rq_sandwich_full(a, x, f, n, p, tau, se, cov, hinv)
}

fn dist_qn(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

// summary.rq(se = "ker"): the Gaussian kernel density of the residuals with the bandwidth (qnorm(tau + h) - qnorm(tau - h)) min(sd, IQR / 1.34), then the same sandwich
fn rq_se_ker(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, coef: []const f64, se: []f64) -> err {
    var h = bandwidth_rq(tau, f64(n), true)
    while tau - h < 0.0f64 || tau + h > 1.0f64 { h = h / 2.0f64 }
    let (u, e1) = mem.alloc[f64](a, n)
    let (srt, e2) = mem.alloc[f64](a, n)
    let (f, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    var m = 0.0f64
    while i < n {
        var fit = 0.0f64
        var j = 0usize
        while j < p {
            fit += x[j * n + i] * coef[j]
            j += 1usize
        }
        u[i] = y[i] - fit
        srt[i] = u[i]
        m += u[i]
        i += 1usize
    }
    m = m / f64(n)
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (u[i] - m) * (u[i] - m)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / f64(n - 1usize))
    i = 1usize
    while i < n {
        let key = srt[i]
        var j = i
        while j > 0usize && srt[j - 1usize] > key {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = key
        i += 1usize
    }
    let q1 = quant7(srt, 0.25f64)
    let q3 = quant7(srt, 0.75f64)
    var sc = sd
    if (q3 - q1) / 1.34f64 < sc { sc = (q3 - q1) / 1.34f64 }
    let hh = (dist_qn(tau + h) - dist_qn(tau - h)) * sc
    i = 0usize
    while i < n {
        let z = u[i] / hh
        f[i] = 0.3989422804014327f64 * math.exp[f64](0.0f64 - 0.5f64 * z * z) / hh
        i += 1usize
    }
    ret rq_sandwich(a, x, f, n, p, tau, se)
}

// quantile type 7 of a sorted sample
fn quant7(s: []const f64, p: f64) -> f64 {
    let n = s.len
    let idx = 1.0f64 + f64(n - 1usize) * p
    let lof = math.floor[f64](idx)
    let lo = usize(lof) - 1usize
    let fr = idx - lof
    if lo + 1usize >= n { ret s[n - 1usize] }
    if !(fr > 0.0f64) || s[lo + 1usize] == s[lo] { ret s[lo] }
    ret (1.0f64 - fr) * s[lo] + fr * s[lo + 1usize]
}

// rq with several taus in one call: out holds the p coefficients of each tau in turn
fn rq_taus(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, taus: []const f64, out: []f64) -> err {
    var k = 0usize
    while k < taus.len {
        let (b, be) = rq(a, x, y, n, p, taus[k])
        if be != ok { ret be }
        var j = 0usize
        while j < p {
            out[k * p + j] = b[j]
            j += 1usize
        }
        k += 1usize
    }
    ret ok
}

// summary.rq(se = "iid"): the Koenker-Bassett sparsity estimate. The residuals nearest zero (past the exact zeros) are sorted, regressed on their rank fraction by rq at tau 0.5, and the slope is the sparsity s; cov = tau (1 - tau) s^2 (X'X)^-1
fn rq_se_iid(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, coef: []const f64, se: []f64) -> err {
    let (res, e1) = mem.alloc[f64](a, n)
    let (ord, e2) = mem.alloc[usize](a, n)
    let (xx, e3) = mem.alloc[f64](a, p * p)
    let (u, e4) = mem.alloc[f64](a, p * p)
    let (ui, e5) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var i = 0usize
    var pz = 0usize
    while i < n {
        var fit = 0.0f64
        var j = 0usize
        while j < p {
            fit += x[j * n + i] * coef[j]
            j += 1usize
        }
        res[i] = y[i] - fit
        if math.abs[f64](res[i]) < 1.4901161193847656e-8f64 { pz += 1usize }
        ord[i] = i
        i += 1usize
    }
    // stable order by |residual|
    i = 1usize
    while i < n {
        let key = ord[i]
        var j = i
        while j > 0usize && math.abs[f64](res[ord[j - 1usize]]) > math.abs[f64](res[key]) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    var h = usize(math.ceil[f64](f64(n) * bandwidth_rq(tau, f64(n), true)))
    if h < p + 1usize { h = p + 1usize }
    let m = h + 1usize
    if pz + m > n { ret mem.Full }
    let (sr, e6) = mem.alloc[f64](a, m)
    let (d2, e7) = mem.alloc[f64](a, 2usize * m)
    if e6 != ok || e7 != ok { ret mem.Full }
    i = 0usize
    while i < m {
        sr[i] = res[ord[pz + i]]
        i += 1usize
    }
    i = 1usize
    while i < m {
        let key = sr[i]
        var j = i
        while j > 0usize && sr[j - 1usize] > key {
            sr[j] = sr[j - 1usize]
            j -= 1usize
        }
        sr[j] = key
        i += 1usize
    }
    i = 0usize
    while i < m {
        d2[i] = 1.0f64
        d2[m + i] = f64(pz + 1usize + i) / f64(n - p)
        i += 1usize
    }
    let (sb, se2) = rq(a, d2, sr, m, 2usize, 0.5f64)
    if se2 != ok { ret se2 }
    let sp = sb[1usize]
    var c = 0usize
    while c < p {
        var c2 = 0usize
        while c2 < p {
            var sx = 0.0f64
            i = 0usize
            while i < n {
                sx += x[c * n + i] * x[c2 * n + i]
                i += 1usize
            }
            xx[c2 * p + c] = sx
            c2 += 1usize
        }
        c += 1usize
    }
    if !bz.chol_upper(xx, p, u) { ret mem.Full }
    bz.inv_upper(u, p, ui)
    c = 0usize
    while c < p {
        var sv = 0.0f64
        var q = 0usize
        while q < p {
            sv += ui[q * p + c] * ui[q * p + c]
            q += 1usize
        }
        se[c] = math.sqrt[f64](tau * (1.0f64 - tau) * sp * sp * sv)
        c += 1usize
    }
    ret ok
}

// summary.rq(se = "boot") with the default xy-pair bootstrap: set.seed(seed), U = sample(n, n R, replace = TRUE) as an n by R matrix, one rq per column, the standard errors the square roots of the diagonal of cov(B)
fn rq_se_boot(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, reps: usize, seed: i64, se: []f64) -> err {
    var rng: rr.Rng = zero
    rr.seed(&rng, seed)
    let (u, ue) = rr.sample_int(a, &rng, i64(n), i64(n * reps), true)
    if ue != ok { ret ue }
    let (bs, e1) = mem.alloc[f64](a, reps * p)
    let (xs, e2) = mem.alloc[f64](a, n * p)
    let (ys, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var r = 0usize
    let mark = a.off
    while r < reps {
        var i = 0usize
        while i < n {
            let k = usize(u[r * n + i] - 1i64)
            ys[i] = y[k]
            var j = 0usize
            while j < p {
                xs[j * n + i] = x[j * n + k]
                j += 1usize
            }
            i += 1usize
        }
        let (b, be) = rq(a, xs, ys, n, p, tau)
        if be != ok { ret be }
        var j = 0usize
        while j < p {
            bs[r * p + j] = b[j]
            j += 1usize
        }
        a.off = mark
        r += 1usize
    }
    var j = 0usize
    while j < p {
        var m = 0.0f64
        r = 0usize
        while r < reps {
            m += bs[r * p + j]
            r += 1usize
        }
        m = m / f64(reps)
        var ss = 0.0f64
        r = 0usize
        while r < reps {
            ss += (bs[r * p + j] - m) * (bs[r * p + j] - m)
            r += 1usize
        }
        se[j] = math.sqrt[f64](ss / f64(reps - 1usize))
        j += 1usize
    }
    ret ok
}

// ---- rqbr: Barrodale-Roberts simplex with the Koenker-D'Orey rank-test confidence intervals, a transcription of
// quantreg's rqbr.f (Ratfor) for tau in (0, 1). The Fortran gotos become a state machine over the labels S_*; wa is the
// (m + 5) by (n + 4) tableau, addressed 1-based through wix.

const S_OUTER: usize = 0usize
const S_ITER: usize = 1usize
const S_STAGE2: usize = 2usize
const S_LOOP2: usize = 3usize
const S_SEL: usize = 4usize
const S_PIV: usize = 5usize
const S_SWAP: usize = 6usize
const S_PIVOT: usize = 7usize
const S_L20: usize = 8usize
const S_L30: usize = 9usize
const S_AFTER: usize = 10usize
const S_NOTEST: usize = 11usize
const S_L40: usize = 12usize
const S_L50: usize = 13usize
const S_L60: usize = 14usize
const S_L70: usize = 15usize
const S_EXIT: usize = 16usize

fn wix(i: usize, j: usize, m5: usize) -> usize { ret (j - 1usize) * m5 + (i - 1usize) }

fn sgn1(v: f64) -> f64 {
    if v >= 0.0f64 { ret 1.0f64 }
    ret 0.0f64 - 1.0f64
}

fn neg_col(wa: []f64, c: usize, rows: usize, m5: usize) {
    var i = 1usize
    while i <= rows {
        wa[wix(i, c, m5)] = 0.0f64 - wa[wix(i, c, m5)]
        i += 1usize
    }
}

// ax is m by nn column-major, b the response, t = tau, lci1 asks for the rank-inversion intervals (qn, cutoff as in rq.fit.br).
// x gets the coefficients, dual the dual solution (m), ci and tnmat (4 by nn column-major) the intervals and their test statistics. Returns ift (0 ok, 1 maybe non-unique, 2 premature end).
fn rqbr(a: *mem.Arena, m: usize, nn: usize, ax: []const f64, b: []const f64, t: f64, toler: f64, big: f64, lci1: bool, qn: []const f64, cutoff: f64, x: []f64, dual: []f64, ci: []f64, tnmat: []f64) -> (i64, err) {
    let m5 = m + 5usize
    let n3e = nn + 3usize
    let (wa, e1) = mem.alloc[f64](a, m5 * (nn + 4usize))
    let (wb, e2) = mem.alloc[f64](a, m + 1usize)
    let (s, e3) = mem.alloc[usize](a, m + 1usize)
    let (sol, e4) = mem.alloc[f64](a, n3e * 2usize)
    let (dsol, e5) = mem.alloc[f64](a, m * 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (2i64, mem.Full) }
    var z = 0usize
    while z < m5 * (nn + 4usize) {
        wa[z] = 0.0f64
        z += 1usize
    }
    z = 0usize
    while z < n3e * 2usize {
        sol[z] = 0.0f64
        z += 1usize
    }
    z = 0usize
    while z < m * 2usize {
        dsol[z] = 0.0f64
        z += 1usize
    }
    z = 0usize
    while z < nn {
        x[z] = 0.0f64
        ci[4usize * z] = 0.0f64
        ci[4usize * z + 1usize] = 0.0f64
        ci[4usize * z + 2usize] = 0.0f64
        ci[4usize * z + 3usize] = 0.0f64
        tnmat[4usize * z] = 0.0f64
        tnmat[4usize * z + 1usize] = 0.0f64
        tnmat[4usize * z + 2usize] = 0.0f64
        tnmat[4usize * z + 3usize] = 0.0f64
        z += 1usize
    }
    var ift = 0i64
    var n = nn
    let m1 = m + 1usize
    let m2 = m + 2usize
    let m3 = m + 3usize
    let m4 = m + 4usize
    var n1 = n + 1usize
    var n2 = n + 2usize
    var n3 = n + 3usize
    var n4 = n + 4usize
    var iend = true
    var lci2 = false
    var lup = true
    var idxcf = 0usize
    var tnew = 0.0f64
    var told = 0.0f64
    var tn = 0.0f64
    var smax = 0.0f64
    var kr = 1usize
    var kl = 1usize
    var kount = 0usize
    var k = 0usize
    var init = false
    var stage = false
    var test = false
    var inn = 1usize
    var outr = 1usize
    var jj = 1usize
    var pivot = 0.0f64
    var d = 0.0f64
    var sum = 0.0f64
    var mx = 0.0f64
    var mn = 0.0f64
    let tt = t
    wa[wix(m2, nn + 1usize, m5)] = 1.0f64
    var pc = S_OUTER
    var i = 1usize
    var j = 1usize
    while pc != S_EXIT {
        if pc == S_OUTER {
            i = 1usize
            while i <= m {
                var kc = 1usize
                j = 1usize
                while j <= nn {
                    if kc <= nn && j != idxcf {
                        wa[wix(i, kc, m5)] = ax[(j - 1usize) * m + i - 1usize]
                        kc += 1usize
                    }
                    j += 1usize
                }
                wa[wix(i, n4, m5)] = f64(n + i)
                wa[wix(i, n2, m5)] = b[i - 1usize]
                if idxcf != 0usize {
                    wa[wix(i, n3, m5)] = tnew * ax[(idxcf - 1usize) * m + i - 1usize]
                } else {
                    wa[wix(i, n3, m5)] = 0.0f64
                }
                wa[wix(i, n1, m5)] = wa[wix(i, n2, m5)] - wa[wix(i, n3, m5)]
                if wa[wix(i, n1, m5)] < 0.0f64 {
                    j = 1usize
                    while j <= n4 {
                        wa[wix(i, j, m5)] = 0.0f64 - wa[wix(i, j, m5)]
                        j += 1usize
                    }
                }
                i += 1usize
            }
            j = 1usize
            while j <= n {
                wa[wix(m4, j, m5)] = f64(j)
                wa[wix(m2, j, m5)] = 0.0f64
                wa[wix(m3, j, m5)] = 0.0f64
                i = 1usize
                while i <= m {
                    let aux = sgn1(wa[wix(m4, j, m5)]) * wa[wix(i, j, m5)]
                    wa[wix(m2, j, m5)] = wa[wix(m2, j, m5)] + aux * (1.0f64 - sgn1(wa[wix(i, n4, m5)]))
                    wa[wix(m3, j, m5)] = wa[wix(m3, j, m5)] + aux * sgn1(wa[wix(i, n4, m5)])
                    i += 1usize
                }
                wa[wix(m3, j, m5)] = 2.0f64 * wa[wix(m3, j, m5)]
                j += 1usize
            }
            init = false
            if !lci2 {
                var kk = 1usize
                while kk <= n {
                    wa[wix(m5, kk, m5)] = 0.0f64
                    i = 1usize
                    while i <= m {
                        wa[wix(m5, kk, m5)] = wa[wix(m5, kk, m5)] + ax[(kk - 1usize) * m + i - 1usize]
                        i += 1usize
                    }
                    wa[wix(m5, kk, m5)] = wa[wix(m5, kk, m5)] / f64(m)
                    kk += 1usize
                }
            }
            kount = 0usize
            pc = S_ITER
        } else if pc == S_ITER {
            j = 1usize
            while j <= n {
                wa[wix(m1, j, m5)] = wa[wix(m2, j, m5)] + wa[wix(m3, j, m5)] * tt
                j += 1usize
            }
            if !init {
                stage = true
                kr = 1usize
                kl = 1usize
                pc = S_L30
            } else {
                pc = S_STAGE2
            }
        } else if pc == S_STAGE2 {
            stage = false
            pc = S_LOOP2
        } else if pc == S_LOOP2 {
            mx = 0.0f64 - big
            j = kr
            while j <= n {
                d = wa[wix(m1, j, m5)]
                var skipj = false
                if d < 0.0f64 {
                    if d > 0.0f64 - 2.0f64 {
                        skipj = true
                    } else {
                        d = 0.0f64 - d - 2.0f64
                    }
                }
                if !skipj && d > mx {
                    mx = d
                    inn = j
                }
                j += 1usize
            }
            if mx <= toler {
                pc = S_AFTER
            } else {
                if wa[wix(m1, inn, m5)] <= 0.0f64 {
                    neg_col(wa, inn, m4, m5)
                    wa[wix(m1, inn, m5)] = wa[wix(m1, inn, m5)] - 2.0f64
                    wa[wix(m2, inn, m5)] = wa[wix(m2, inn, m5)] - 2.0f64
                }
                pc = S_SEL
            }
        } else if pc == S_SEL {
            k = 0usize
            i = kl
            while i <= m {
                d = wa[wix(i, inn, m5)]
                if d > toler {
                    k += 1usize
                    wb[k] = wa[wix(i, n1, m5)] / d
                    s[k] = i
                    test = true
                }
                i += 1usize
            }
            pc = S_PIV
        } else if pc == S_PIV {
            if k <= 0usize {
                test = false
            } else {
                mn = big
                i = 1usize
                while i <= k {
                    if wb[i] < mn {
                        jj = i
                        mn = wb[i]
                        outr = s[i]
                    }
                    i += 1usize
                }
                wb[jj] = wb[k]
                s[jj] = s[k]
                k -= 1usize
            }
            if !test && stage {
                pc = S_SWAP
            } else if !test {
                pc = S_NOTEST
            } else {
                pivot = wa[wix(outr, inn, m5)]
                if wa[wix(m1, inn, m5)] - pivot - pivot <= toler {
                    pc = S_PIVOT
                } else {
                    j = kr
                    while j <= n3 {
                        d = wa[wix(outr, j, m5)]
                        wa[wix(m1, j, m5)] = wa[wix(m1, j, m5)] - d - d
                        wa[wix(m2, j, m5)] = wa[wix(m2, j, m5)] - d - d
                        wa[wix(outr, j, m5)] = 0.0f64 - d
                        j += 1usize
                    }
                    wa[wix(outr, n4, m5)] = 0.0f64 - wa[wix(outr, n4, m5)]
                }
            }
        } else if pc == S_SWAP {
            i = 1usize
            while i <= m4 {
                d = wa[wix(i, kr, m5)]
                wa[wix(i, kr, m5)] = wa[wix(i, inn, m5)]
                wa[wix(i, inn, m5)] = d
                i += 1usize
            }
            kr += 1usize
            pc = S_L20
        } else if pc == S_PIVOT {
            j = kr
            while j <= n3 {
                if j != inn { wa[wix(outr, j, m5)] = wa[wix(outr, j, m5)] / pivot }
                j += 1usize
            }
            i = 1usize
            while i <= m3 {
                if i != outr {
                    d = wa[wix(i, inn, m5)]
                    j = kr
                    while j <= n3 {
                        if j != inn { wa[wix(i, j, m5)] = wa[wix(i, j, m5)] - d * wa[wix(outr, j, m5)] }
                        j += 1usize
                    }
                }
                i += 1usize
            }
            i = 1usize
            while i <= m3 {
                if i != outr { wa[wix(i, inn, m5)] = 0.0f64 - wa[wix(i, inn, m5)] / pivot }
                i += 1usize
            }
            wa[wix(outr, inn, m5)] = 1.0f64 / pivot
            d = wa[wix(outr, n4, m5)]
            wa[wix(outr, n4, m5)] = wa[wix(m4, inn, m5)]
            wa[wix(m4, inn, m5)] = d
            kount += 1usize
            if !stage {
                pc = S_LOOP2
            } else {
                kl += 1usize
                j = kr
                while j <= n4 {
                    d = wa[wix(outr, j, m5)]
                    wa[wix(outr, j, m5)] = wa[wix(kount, j, m5)]
                    wa[wix(kount, j, m5)] = d
                    j += 1usize
                }
                pc = S_L20
            }
        } else if pc == S_L20 {
            if kount + kr == n1 { pc = S_STAGE2 } else { pc = S_L30 }
        } else if pc == S_L30 {
            mx = 0.0f64 - 1.0f64
            j = kr
            while j <= n {
                if math.abs[f64](wa[wix(m4, j, m5)]) <= f64(n) {
                    d = math.abs[f64](wa[wix(m1, j, m5)])
                    if d > mx {
                        mx = d
                        inn = j
                    }
                }
                j += 1usize
            }
            if wa[wix(m1, inn, m5)] < 0.0f64 { neg_col(wa, inn, m4, m5) }
            pc = S_SEL
        } else if pc == S_AFTER {
            if kr == 1usize {
                j = 1usize
                while j <= n {
                    d = math.abs[f64](wa[wix(m1, j, m5)])
                    if (d <= toler || 2.0f64 - d <= toler) && ift != 1i64 {
                        ift = 1i64
                        wa[wix(m2, nn + 1usize, m5)] = 0.0f64
                    }
                    j += 1usize
                }
            }
            kount = 0usize
            if !lci2 {
                i = 1usize
                while i < kl {
                    let kx = usize(math.abs[f64](wa[wix(i, n4, m5)]))
                    x[kx - 1usize] = wa[wix(i, n1, m5)] * sgn1(wa[wix(i, n4, m5)])
                    i += 1usize
                }
            }
            sum = 0.0f64
            i = 1usize
            while i <= n {
                let kd = usize(math.abs[f64](wa[wix(m4, i, m5)])) - n
                dsol[kd - 1usize] = 1.0f64 + wa[wix(m1, i, m5)] / 2.0f64
                if wa[wix(m4, i, m5)] < 0.0f64 { dsol[kd - 1usize] = 1.0f64 - dsol[kd - 1usize] }
                if !lci2 {
                    sum = sum + x[i - 1usize] * wa[wix(m5, i, m5)]
                    sol[(i + 3usize) - 1usize] = x[i - 1usize]
                }
                i += 1usize
            }
            i = kl
            while i <= m {
                let kd = usize(math.abs[f64](wa[wix(i, n4, m5)])) - n
                if wa[wix(i, n4, m5)] < 0.0f64 { dsol[kd - 1usize] = 0.0f64 }
                if wa[wix(i, n4, m5)] > 0.0f64 { dsol[kd - 1usize] = 1.0f64 }
                i += 1usize
            }
            var jumped = false
            if !lci2 {
                i = 1usize
                while i <= m {
                    dsol[m + i - 1usize] = dsol[i - 1usize]
                    i += 1usize
                }
            } else {
                var a1 = 0.0f64
                i = 1usize
                while i <= m {
                    a1 = a1 + ax[(idxcf - 1usize) * m + i - 1usize] * (dsol[i - 1usize] + tt - 1.0f64)
                    i += 1usize
                }
                tn = a1 / math.sqrt[f64](qn[idxcf - 1usize] * tt * (1.0f64 - tt))
                if math.abs[f64](tn) < cutoff {
                    if lup { smax = big } else { smax = 0.0f64 - big }
                    i = 1usize
                    while i < kl {
                        let kx = usize(math.abs[f64](wa[wix(i, n4, m5)]))
                        sol[kx - 1usize] = wa[wix(i, n2, m5)] * sgn1(wa[wix(i, n4, m5)])
                        sol[n3e + kx - 1usize] = wa[wix(i, n3, m5)] * sgn1(wa[wix(i, n4, m5)]) / tnew
                        i += 1usize
                    }
                    i = kl
                    while i <= m {
                        var a2 = 0.0f64
                        var b2 = 0.0f64
                        let kx = usize(math.abs[f64](wa[wix(i, n4, m5)])) - n
                        var l = 1usize
                        j = 1usize
                        while j <= n {
                            if j == idxcf { l += 1usize }
                            a2 = a2 + ax[(l - 1usize) * m + kx - 1usize] * sol[j - 1usize]
                            b2 = b2 + ax[(l - 1usize) * m + kx - 1usize] * sol[n3e + j - 1usize]
                            l += 1usize
                            j += 1usize
                        }
                        let tnt = (b[kx - 1usize] - a2) / (ax[(idxcf - 1usize) * m + kx - 1usize] - b2)
                        if lup {
                            if tnt > tnew && tnt < smax {
                                smax = tnt
                                outr = i
                            }
                        } else {
                            if tnt < tnew && tnt > smax {
                                smax = tnt
                                outr = i
                            }
                        }
                        i += 1usize
                    }
                    if lup {
                        told = tnew
                        tnew = smax + toler
                        ci[(idxcf - 1usize) * 4usize + 2usize] = told - toler
                        tnmat[(idxcf - 1usize) * 4usize + 2usize] = tn
                        if !(tnew < big - toler) {
                            ci[(idxcf - 1usize) * 4usize + 2usize] = big
                            ci[(idxcf - 1usize) * 4usize + 3usize] = big
                            tnmat[(idxcf - 1usize) * 4usize + 2usize] = tn
                            tnmat[(idxcf - 1usize) * 4usize + 3usize] = tn
                            lup = false
                            jumped = true
                            pc = S_L70
                        }
                    } else {
                        told = tnew
                        tnew = smax - toler
                        ci[(idxcf - 1usize) * 4usize + 1usize] = told + toler
                        tnmat[(idxcf - 1usize) * 4usize + 1usize] = tn
                        if !(tnew > 0.0f64 - big + toler) {
                            ci[(idxcf - 1usize) * 4usize + 1usize] = 0.0f64 - big
                            ci[(idxcf - 1usize) * 4usize] = 0.0f64 - big
                            tnmat[(idxcf - 1usize) * 4usize + 1usize] = tn
                            tnmat[(idxcf - 1usize) * 4usize] = tn
                            lup = true
                            jumped = true
                            pc = S_L60
                        }
                    }
                    if !jumped {
                        i = 1usize
                        while i <= m {
                            wa[wix(i, n3, m5)] = wa[wix(i, n3, m5)] / told * tnew
                            wa[wix(i, n1, m5)] = wa[wix(i, n2, m5)] - wa[wix(i, n3, m5)]
                            i += 1usize
                        }
                        j = kr
                        while j <= n3 {
                            d = wa[wix(outr, j, m5)]
                            wa[wix(m1, j, m5)] = wa[wix(m1, j, m5)] - d - d
                            wa[wix(m2, j, m5)] = wa[wix(m2, j, m5)] - d - d
                            wa[wix(outr, j, m5)] = 0.0f64 - d
                            j += 1usize
                        }
                        wa[wix(outr, n4, m5)] = 0.0f64 - wa[wix(outr, n4, m5)]
                        init = true
                    }
                } else {
                    jumped = true
                    if lup {
                        ci[(idxcf - 1usize) * 4usize + 3usize] = tnew - toler
                        tnmat[(idxcf - 1usize) * 4usize + 3usize] = tn
                        lup = false
                        pc = S_L70
                    } else {
                        ci[(idxcf - 1usize) * 4usize] = tnew + toler
                        tnmat[(idxcf - 1usize) * 4usize] = tn
                        lup = true
                        pc = S_L60
                    }
                }
            }
            if !jumped {
                if iend && !lci2 { pc = S_L40 } else { pc = S_ITER }
            }
        } else if pc == S_NOTEST {
            wa[wix(m2, nn + 1usize, m5)] = 2.0f64
            ift = 2i64
            pc = S_L50
        } else if pc == S_L40 {
            i = 1usize
            while i < kl {
                if wa[wix(i, n1, m5)] < 0.0f64 {
                    j = kr
                    while j <= n4 {
                        wa[wix(i, j, m5)] = 0.0f64 - wa[wix(i, j, m5)]
                        j += 1usize
                    }
                }
                i += 1usize
            }
            pc = S_L50
        } else if pc == S_L50 {
            if wa[wix(m2, nn + 1usize, m5)] == 2.0f64 || !lci1 {
                pc = S_EXIT
            } else if lci2 {
                pc = S_OUTER
            } else {
                lci2 = true
                n = nn - 1usize
                n1 = n + 1usize
                n2 = n + 2usize
                n3 = n + 3usize
                n4 = n + 4usize
                pc = S_L60
            }
        } else if pc == S_L60 {
            idxcf += 1usize
            if idxcf > nn { pc = S_EXIT } else { pc = S_L70 }
        } else if pc == S_L70 {
            if lup {
                tnew = x[idxcf - 1usize] + toler
                told = tnew
                ci[(idxcf - 1usize) * 4usize + 2usize] = x[idxcf - 1usize]
                tnmat[(idxcf - 1usize) * 4usize + 2usize] = 0.0f64
            } else {
                tnew = x[idxcf - 1usize] - toler
                told = tnew
                ci[(idxcf - 1usize) * 4usize + 1usize] = x[idxcf - 1usize]
                tnmat[(idxcf - 1usize) * 4usize + 1usize] = 0.0f64
            }
            pc = S_OUTER
        }
    }
    i = 1usize
    while i <= m {
        dual[i - 1usize] = dsol[m + i - 1usize]
        i += 1usize
    }
    ret (ift, ok)
}

// rq.fit.br(x, y, tau, ci = TRUE, alpha, iid, interp, tcrit): the rank-inversion confidence intervals. out holds per coefficient (coef, lower, upper) as 3 p values; raw (8 p) the four-row ci and tnmat of rqbr. With interp false out is the raw bounds (rows 1..4 as lower bound, Lower Bound, upper bd, Upper Bound would be raw[2], raw[1], raw[3], raw[0])
fn rq_rank(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, alpha: f64, iid: bool, tcrit: bool, interp: bool, out: []f64, raw: []f64) -> err {
    let tol = math.pow[f64](2.220446049250313e-16f64, 2.0f64 / 3.0f64)
    let big = 1.7976931348623157e308f64
    let (b, e0) = mem.alloc[f64](a, p)
    let (dual, e1) = mem.alloc[f64](a, n)
    let (qn, e2) = mem.alloc[f64](a, p)
    let (xx, e3) = mem.alloc[f64](a, p * p)
    let (u, e4) = mem.alloc[f64](a, p * p)
    let (ui, e5) = mem.alloc[f64](a, p * p)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
    var cutoff = 0.0f64
    if tcrit { cutoff = nb.qt(1.0f64 - alpha / 2.0f64, f64(n - p), true, false) } else { cutoff = dist_qn(1.0f64 - alpha / 2.0f64) }
    var c = 0usize
    var i = 0usize
    if iid {
        c = 0usize
        while c < p {
            var c2 = 0usize
            while c2 < p {
                var sx = 0.0f64
                i = 0usize
                while i < n {
                    sx += x[c * n + i] * x[c2 * n + i]
                    i += 1usize
                }
                xx[c2 * p + c] = sx
                c2 += 1usize
            }
            c += 1usize
        }
        if !bz.chol_upper(xx, p, u) { ret mem.Full }
        bz.inv_upper(u, p, ui)
        c = 0usize
        while c < p {
            var sv = 0.0f64
            var q = 0usize
            while q < p {
                sv += ui[q * p + c] * ui[q * p + c]
                q += 1usize
            }
            qn[c] = 1.0f64 / sv
            c += 1usize
        }
    } else {
        let h = bandwidth_rq(tau, f64(n), true)
        let (bhi, e6) = rq(a, x, y, n, p, tau + h)
        if e6 != ok { ret e6 }
        let (blo, e7) = rq(a, x, y, n, p, tau - h)
        if e7 != ok { ret e7 }
        let (f, e8) = mem.alloc[f64](a, n)
        if e8 != ok { ret mem.Full }
        i = 0usize
        while i < n {
            var dy = 0.0f64
            var j = 0usize
            while j < p {
                dy += x[j * n + i] * (bhi[j] - blo[j])
                j += 1usize
            }
            var fv = 2.0f64 * h / (dy - tol)
            if !(fv > tol) { fv = tol }
            f[i] = fv
            i += 1usize
        }
        // qn[j] = sum of squared residuals of x_j on the other columns (no intercept) weighted by f
        let q1 = p - 1usize
        let (zz, e9) = mem.alloc[f64](a, q1 * q1)
        let (zr, e10) = mem.alloc[f64](a, q1)
        if e9 != ok || e10 != ok { ret mem.Full }
        var jc = 0usize
        while jc < p {
            var r1 = 0usize
            var ca = 0usize
            while ca < p {
                if ca != jc {
                    var r2 = 0usize
                    var cb = 0usize
                    while cb < p {
                        if cb != jc {
                            var sv = 0.0f64
                            i = 0usize
                            while i < n {
                                sv += x[ca * n + i] * f[i] * x[cb * n + i]
                                i += 1usize
                            }
                            zz[r1 * q1 + r2] = sv
                            r2 += 1usize
                        }
                        cb += 1usize
                    }
                    var sr = 0.0f64
                    i = 0usize
                    while i < n {
                        sr += x[ca * n + i] * f[i] * x[jc * n + i]
                        i += 1usize
                    }
                    zr[r1] = sr
                    r1 += 1usize
                }
                ca += 1usize
            }
            if !solve_dense(zz, zr, q1) { ret mem.Full }
            var ssq = 0.0f64
            i = 0usize
            while i < n {
                var fit = 0.0f64
                var rr2 = 0usize
                var cc = 0usize
                while cc < p {
                    if cc != jc {
                        fit += x[cc * n + i] * zr[rr2]
                        rr2 += 1usize
                    }
                    cc += 1usize
                }
                let rs = x[jc * n + i] - fit
                ssq += rs * rs
                i += 1usize
            }
            qn[jc] = ssq
            jc += 1usize
        }
    }
    let (ci, e11) = mem.alloc[f64](a, 4usize * p)
    let (tnm, e12) = mem.alloc[f64](a, 4usize * p)
    if e11 != ok || e12 != ok { ret mem.Full }
    let (ift, re) = rqbr(a, n, p, x, y, tau, tol, big, true, qn, cutoff, b, dual, ci, tnm)
    if re != ok { ret re }
    c = 0usize
    while c < p {
        var r = 0usize
        while r < 4usize {
            raw[c * 4usize + r] = ci[c * 4usize + r]
            raw[4usize * p + c * 4usize + r] = tnm[c * 4usize + r]
            r += 1usize
        }
        var lo = ci[c * 4usize + 1usize]
        var hi = ci[c * 4usize + 2usize]
        if interp {
            hi = hi + (math.abs[f64](ci[c * 4usize + 3usize] - hi) * (cutoff - math.abs[f64](tnm[c * 4usize + 2usize]))) / math.abs[f64](tnm[c * 4usize + 3usize] - tnm[c * 4usize + 2usize])
            lo = lo - (math.abs[f64](ci[c * 4usize] - lo) * (cutoff - math.abs[f64](tnm[c * 4usize + 1usize]))) / math.abs[f64](tnm[c * 4usize] - tnm[c * 4usize + 1usize])
            if hi != hi { hi = big }
            if lo != lo { lo = 0.0f64 - big }
        }
        out[c * 3usize] = b[c]
        out[c * 3usize + 1usize] = lo
        out[c * 3usize + 2usize] = hi
        c += 1usize
    }
    ret ok
}

// the summary.rq coefficient table columns from coefficients and standard errors: t = coef / se, p = 2 (1 - pt(|t|, n - p))
fn rq_tvalues(coef: []const f64, se: []const f64, rdf: f64, tv: []f64, pv: []f64) {
    var j = 0usize
    while j < coef.len {
        tv[j] = coef[j] / se[j]
        pv[j] = 2.0f64 * nb.pt(math.abs[f64](tv[j]), rdf, false, false)
        j += 1usize
    }
}

// ---- rq.fit.fnb: the Frisch-Newton primal-dual interior point of quantreg's rqfnb.f (Mehrotra predictor-corrector, beta = 0.99995, gap eps), with the BLAS calls done in the reference order. a is p by n column-major (the transposed design).

// Cholesky factor of the upper triangle of the column-major p by p matrix m, in place; false when not positive definite (LAPACK dpotf2 form)
fn dpotrf_u(m: []f64, p: usize) -> bool {
    var j = 0usize
    while j < p {
        var sj = m[j + p * j]
        var i = 0usize
        while i < j {
            sj -= m[i + p * j] * m[i + p * j]
            i += 1usize
        }
        if !(sj > 0.0f64) { ret false }
        let ajj = math.sqrt[f64](sj)
        m[j + p * j] = ajj
        var k = j + 1usize
        while k < p {
            var dt = 0.0f64
            i = 0usize
            while i < j {
                dt += m[i + p * j] * m[i + p * k]
                i += 1usize
            }
            m[j + p * k] = (m[j + p * k] - dt) / ajj
            k += 1usize
        }
        j += 1usize
    }
    ret true
}

// solves U'U x = b in place with U the factor from dpotrf_u
fn dpotrs_u(m: []const f64, b: []f64, p: usize) {
    var k = 0usize
    while k < p {
        var tmp = b[k]
        var i = 0usize
        while i < k {
            tmp -= m[i + p * k] * b[i]
            i += 1usize
        }
        b[k] = tmp / m[k + p * k]
        k += 1usize
    }
    k = p
    while k > 0usize {
        k -= 1usize
        if b[k] != 0.0f64 {
            b[k] = b[k] / m[k + p * k]
            var i = 0usize
            while i < k {
                b[i] -= b[k] * m[i + p * k]
                i += 1usize
            }
        }
    }
}

// stepy: ada = A diag(d) A' (upper triangle), then b := ada^-1 b; false when ada is singular
fn fnb_stepy(am: []const f64, d: []const f64, n: usize, p: usize, b: []f64, ada: []f64) -> bool {
    var z = 0usize
    while z < p * p {
        ada[z] = 0.0f64
        z += 1usize
    }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            if am[j + p * i] != 0.0f64 {
                let tmp = d[i] * am[j + p * i]
                var r = 0usize
                while r <= j {
                    ada[r + p * j] += am[r + p * i] * tmp
                    r += 1usize
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    if !dpotrf_u(ada, p) { ret false }
    dpotrs_u(ada, b, p)
    ret true
}

fn dotv(x: []const f64, y: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += x[i] * y[i]
        i += 1usize
    }
    ret s
}

// dgemv('T'): out_j = beta out_j + alpha (a_j . v); beta 1 leaves out, any other beta scales first (0 clears)
fn gemv_t(am: []const f64, n: usize, p: usize, alpha: f64, v: []const f64, beta: f64, out: []f64) {
    var j = 0usize
    while j < n {
        var tmp = 0.0f64
        var i = 0usize
        while i < p {
            tmp += am[i + p * j] * v[i]
            i += 1usize
        }
        if beta == 0.0f64 {
            out[j] = alpha * tmp
        } else if beta == 1.0f64 {
            out[j] = out[j] + alpha * tmp
        } else {
            out[j] = beta * out[j] + alpha * tmp
        }
        j += 1usize
    }
}

// dgemv('N') with beta 1: out += alpha A v
fn gemv_n(am: []const f64, n: usize, p: usize, alpha: f64, v: []const f64, out: []f64) {
    var j = 0usize
    while j < n {
        let tmp = alpha * v[j]
        var i = 0usize
        while i < p {
            out[i] += tmp * am[i + p * j]
            i += 1usize
        }
        j += 1usize
    }
}

// lpfnb: min c'x s.t. A x = b, 0 <= x <= u (u = 1 here), returning the dual y (coefficients are -y); xin the starting x. Returns false when stepy meets a singular matrix.
fn lpfnb(a: *mem.Arena, am: []const f64, n: usize, p: usize, c: []const f64, b: []const f64, xin: f64, beta: f64, eps: f64, yo: []f64) -> bool {
    let (x, e1) = mem.alloc[f64](a, n)
    let (s, e2) = mem.alloc[f64](a, n)
    let (z, e3) = mem.alloc[f64](a, n)
    let (w, e4) = mem.alloc[f64](a, n)
    let (dx, e5) = mem.alloc[f64](a, n)
    let (ds, e6) = mem.alloc[f64](a, n)
    let (dz, e7) = mem.alloc[f64](a, n)
    let (dw, e8) = mem.alloc[f64](a, n)
    let (dr, e9) = mem.alloc[f64](a, n)
    let (d, e10) = mem.alloc[f64](a, n)
    let (u, e11) = mem.alloc[f64](a, n)
    let (dy, e12) = mem.alloc[f64](a, p)
    let (rhs, e13) = mem.alloc[f64](a, p)
    let (ada, e14) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok { ret false }
    let big = 1.0e20f64
    var i = 0usize
    while i < n {
        x[i] = xin
        u[i] = 1.0f64
        d[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < p {
        yo[i] = 0.0f64
        i += 1usize
    }
    gemv_n(am, n, p, 1.0f64, c, yo)
    if !fnb_stepy(am, d, n, p, yo, ada) { ret false }
    i = 0usize
    while i < n {
        s[i] = c[i]
        i += 1usize
    }
    gemv_t(am, n, p, 0.0f64 - 1.0f64, yo, 1.0f64, s)
    i = 0usize
    while i < n {
        if math.abs[f64](s[i]) < eps {
            z[i] = math.max[f64](s[i], 0.0f64) + eps
            w[i] = math.max[f64](0.0f64 - s[i], 0.0f64) + eps
        } else {
            z[i] = math.max[f64](s[i], 0.0f64)
            w[i] = math.max[f64](0.0f64 - s[i], 0.0f64)
        }
        s[i] = u[i] - x[i]
        i += 1usize
    }
    var gap = dotv(z, x, n) + dotv(w, s, n)
    var nit = 0usize
    while gap > eps && nit < 500usize {
        nit += 1usize
        i = 0usize
        while i < n {
            d[i] = 1.0f64 / (z[i] / x[i] + w[i] / s[i])
            ds[i] = z[i] - w[i]
            dz[i] = d[i] * ds[i]
            i += 1usize
        }
        i = 0usize
        while i < p {
            dy[i] = b[i]
            i += 1usize
        }
        gemv_n(am, n, p, 0.0f64 - 1.0f64, x, dy)
        gemv_n(am, n, p, 1.0f64, dz, dy)
        i = 0usize
        while i < p {
            rhs[i] = dy[i]
            i += 1usize
        }
        if !fnb_stepy(am, d, n, p, dy, ada) { ret false }
        gemv_t(am, n, p, 1.0f64, dy, 0.0f64 - 1.0f64, ds)
        var deltap = big
        var deltad = big
        i = 0usize
        while i < n {
            dx[i] = d[i] * ds[i]
            ds[i] = 0.0f64 - dx[i]
            dz[i] = 0.0f64 - z[i] * (dx[i] / x[i] + 1.0f64)
            dw[i] = 0.0f64 - w[i] * (ds[i] / s[i] + 1.0f64)
            if dx[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - x[i] / dx[i]) }
            if ds[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - s[i] / ds[i]) }
            if dz[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - z[i] / dz[i]) }
            if dw[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - w[i] / dw[i]) }
            i += 1usize
        }
        deltap = math.min[f64](beta * deltap, 1.0f64)
        deltad = math.min[f64](beta * deltad, 1.0f64)
        if math.min[f64](deltap, deltad) < 1.0f64 {
            var mu = dotv(x, z, n) + dotv(s, w, n)
            let g = mu + deltap * dotv(dx, z, n) + deltad * dotv(dz, x, n) + deltap * deltad * dotv(dz, dx, n) + deltap * dotv(ds, w, n) + deltad * dotv(dw, s, n) + deltap * deltad * dotv(ds, dw, n)
            let q = g / mu
            mu = mu * (q * q * q) / f64(2usize * n)
            i = 0usize
            while i < n {
                dr[i] = d[i] * (mu * (1.0f64 / s[i] - 1.0f64 / x[i]) + dx[i] * dz[i] / x[i] - ds[i] * dw[i] / s[i])
                i += 1usize
            }
            i = 0usize
            while i < p {
                let tm = rhs[i]
                rhs[i] = dy[i]
                dy[i] = tm
                i += 1usize
            }
            gemv_n(am, n, p, 1.0f64, dr, dy)
            dpotrs_u(ada, dy, p)
            gemv_t(am, n, p, 1.0f64, dy, 0.0f64, u)
            deltap = big
            deltad = big
            i = 0usize
            while i < n {
                let dxdz = dx[i] * dz[i]
                let dsdw = ds[i] * dw[i]
                dx[i] = d[i] * (u[i] - z[i] + w[i]) - dr[i]
                ds[i] = 0.0f64 - dx[i]
                dz[i] = 0.0f64 - z[i] + (mu - z[i] * dx[i] - dxdz) / x[i]
                dw[i] = 0.0f64 - w[i] + (mu - w[i] * ds[i] - dsdw) / s[i]
                if dx[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - x[i] / dx[i]) }
                if ds[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - s[i] / ds[i]) }
                if dz[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - z[i] / dz[i]) }
                if dw[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - w[i] / dw[i]) }
                i += 1usize
            }
            deltap = math.min[f64](beta * deltap, 1.0f64)
            deltad = math.min[f64](beta * deltad, 1.0f64)
        }
        i = 0usize
        while i < n {
            x[i] += deltap * dx[i]
            s[i] += deltap * ds[i]
            z[i] += deltad * dz[i]
            w[i] += deltad * dw[i]
            i += 1usize
        }
        i = 0usize
        while i < p {
            yo[i] += deltad * dy[i]
            i += 1usize
        }
        gap = dotv(z, x, n) + dotv(w, s, n)
    }
    ret true
}

// the transposed design (p by n, column-major) of an n by p column-major matrix
fn transpose_design(a: *mem.Arena, x: []const f64, n: usize, p: usize) -> ([]f64, err) {
    let (t, te) = mem.alloc[f64](a, n * p)
    if te != ok { ret (t, te) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < p {
            t[j + p * i] = x[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    ret (t, ok)
}

// rq.fit.fnb(x, y, tau, beta = 0.99995, eps): coefficients of the Frisch-Newton fit
fn rq_fnb(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, eps: f64) -> ([]f64, err) {
    let (b, be) = mem.alloc[f64](a, p)
    let (rhs, re) = mem.alloc[f64](a, p)
    let (c, ce) = mem.alloc[f64](a, n)
    if be != ok || re != ok || ce != ok { ret (b, mem.Full) }
    let (am, ae) = transpose_design(a, x, n, p)
    if ae != ok { ret (b, ae) }
    var j = 0usize
    while j < p {
        var sm = 0.0f64
        var i = 0usize
        while i < n {
            sm += x[j * n + i]
            i += 1usize
        }
        rhs[j] = (1.0f64 - tau) * sm
        j += 1usize
    }
    var i = 0usize
    while i < n {
        c[i] = 0.0f64 - y[i]
        i += 1usize
    }
    if !lpfnb(a, am, n, p, c, rhs, 1.0f64 - tau, 0.99995f64, eps, b) { ret (b, mem.Full) }
    j = 0usize
    while j < p {
        b[j] = 0.0f64 - b[j]
        j += 1usize
    }
    ret (b, ok)
}

// rq.fit.lasso(x, y, tau, lambda): lambda has p entries (0 leaves a coefficient unpenalised); the penalty rows are appended to the data
fn rq_lasso(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, lambda: []const f64, eps: f64) -> ([]f64, err) {
    var nr = 0usize
    var k = 0usize
    while k < p {
        if lambda[k] != 0.0f64 { nr += 1usize }
        k += 1usize
    }
    let big_n = n + nr
    let (xx, e1) = mem.alloc[f64](a, big_n * p)
    let (c, e2) = mem.alloc[f64](a, big_n)
    let (rhs, e3) = mem.alloc[f64](a, p)
    let (b, e4) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret (b, mem.Full) }
    var z = 0usize
    while z < big_n * p {
        xx[z] = 0.0f64
        z += 1usize
    }
    var j = 0usize
    while j < p {
        var i = 0usize
        var sm = 0.0f64
        while i < n {
            xx[j * big_n + i] = x[j * n + i]
            sm += x[j * n + i]
            i += 1usize
        }
        rhs[j] = (1.0f64 - tau) * sm
        j += 1usize
    }
    var r = 0usize
    j = 0usize
    while j < p {
        if lambda[j] != 0.0f64 {
            xx[j * big_n + n + r] = lambda[j]
            rhs[j] = rhs[j] + 0.5f64 * lambda[j]
            r += 1usize
        }
        j += 1usize
    }
    var i = 0usize
    while i < big_n {
        c[i] = 0.0f64
        if i < n { c[i] = 0.0f64 - y[i] }
        i += 1usize
    }
    let (am, ae) = transpose_design(a, xx, big_n, p)
    if ae != ok { ret (b, ae) }
    if !lpfnb(a, am, big_n, p, c, rhs, 0.5f64, 0.99995f64, eps, b) { ret (b, mem.Full) }
    j = 0usize
    while j < p {
        b[j] = 0.0f64 - b[j]
        j += 1usize
    }
    ret (b, ok)
}

fn sort_asc(s: []f64) {
    var i = 1usize
    while i < s.len {
        let key = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > key {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = key
        i += 1usize
    }
}

// LassoLambdaHat(X, R = 1000, tau, C = 1, alpha = 0.95): the Belloni-Chernozhukov default penalty; draws runif(n R) from rng
fn lasso_lambda_hat(a: *mem.Arena, x: []const f64, n: usize, p: usize, tau: f64, rng: *rr.Rng, out: []f64) -> err {
    let reps = 1000usize
    let (sigs, e1) = mem.alloc[f64](a, p)
    let (rmax, e2) = mem.alloc[f64](a, reps)
    if e1 != ok || e2 != ok { ret mem.Full }
    var j = 0usize
    while j < p {
        var sq = 0.0f64
        var i = 0usize
        while i < n {
            sq += x[j * n + i] * x[j * n + i]
            i += 1usize
        }
        sigs[j] = sq / f64(n)
        j += 1usize
    }
    var r = 0usize
    while r < reps {
        var mxv = 0.0f64
        var uu: []f64 = zero
        let (ud, ue) = mem.alloc[f64](a, n)
        if ue != ok { ret mem.Full }
        uu = ud
        var i = 0usize
        while i < n {
            uu[i] = rr.unif(rng)
            i += 1usize
        }
        j = 0usize
        while j < p {
            var sm = 0.0f64
            i = 0usize
            while i < n {
                var ind = 0.0f64
                if uu[i] < tau { ind = 1.0f64 }
                sm += x[j * n + i] * (tau - ind)
                i += 1usize
            }
            let v = math.abs[f64](sm / sigs[j])
            if v > mxv { mxv = v }
            j += 1usize
        }
        rmax[r] = mxv
        r += 1usize
    }
    sort_asc(rmax)
    let q = quant7(rmax, 0.05f64)
    j = 0usize
    while j < p {
        out[j] = q * sigs[j]
        j += 1usize
    }
    ret ok
}

// rq.fit.pfn(x, y, tau, Mm.factor, max.bad.fixups, eps): the Portnoy-Koenker preprocessing, a fit on a random sample of m = round(sqrt(p) n^(2/3)) rows (sample(n, m) from rng), then the fixups of the rows whose sign is settled
fn rq_pfn(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, mm_factor: f64, max_bad: usize, eps: f64, rng: *rr.Rng) -> ([]f64, err) {
    var m = usize(math.floor[f64](math.sqrt[f64](f64(p)) * math.pow[f64](f64(n), 2.0f64 / 3.0f64) + 0.5f64))
    let (r, e1) = mem.alloc[f64](a, n)
    let (band, e2) = mem.alloc[f64](a, n)
    let (sl, e3) = mem.alloc[bool](a, n)
    let (su, e4) = mem.alloc[bool](a, n)
    let (rq1, e5) = mem.alloc[f64](a, n)
    let (xtx, e6) = mem.alloc[f64](a, p * p)
    let (uu, e7) = mem.alloc[f64](a, p * p)
    let (ui, e8) = mem.alloc[f64](a, p * p)
    let (srt, e9) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (r, mem.Full) }
    var zc: []f64 = zero
    var optimal = false
    while !optimal {
        if m >= n {
            let (zf, zfe) = rq_fnb(a, x, y, n, p, tau, eps)
            ret (zf, zfe)
        }
        let (si, se1) = rr.sample_int(a, rng, i64(n), i64(m), false)
        if se1 != ok { ret (r, se1) }
        let (xx, e10) = mem.alloc[f64](a, m * p)
        let (yy, e11) = mem.alloc[f64](a, m)
        if e10 != ok || e11 != ok { ret (r, mem.Full) }
        var i = 0usize
        while i < m {
            let k = usize(si[i] - 1i64)
            yy[i] = y[k]
            var j = 0usize
            while j < p {
                xx[j * m + i] = x[j * n + k]
                j += 1usize
            }
            i += 1usize
        }
        let (z0, z0e) = rq_fnb(a, xx, yy, m, p, tau, eps)
        if z0e != ok { ret (z0, z0e) }
        var c = 0usize
        while c < p {
            var c2 = 0usize
            while c2 < p {
                var sx = 0.0f64
                i = 0usize
                while i < m {
                    sx += xx[c * m + i] * xx[c2 * m + i]
                    i += 1usize
                }
                xtx[c2 * p + c] = sx
                c2 += 1usize
            }
            c += 1usize
        }
        if !bz.chol_upper(xtx, p, uu) { ret (z0, mem.Full) }
        bz.inv_upper(uu, p, ui)
        i = 0usize
        while i < n {
            var bs = 0.0f64
            var j = 0usize
            while j < p {
                var v = 0.0f64
                var k = 0usize
                while k <= j {
                    v += x[k * n + i] * ui[j * p + k]
                    k += 1usize
                }
                bs += v * v
                j += 1usize
            }
            band[i] = math.sqrt[f64](bs)
            var fit = 0.0f64
            j = 0usize
            while j < p {
                fit += x[j * n + i] * z0[j]
                j += 1usize
            }
            r[i] = y[i] - fit
            i += 1usize
        }
        let bigm = mm_factor * f64(m)
        let loq = math.max[f64](1.0f64 / f64(n), tau - bigm / (2.0f64 * f64(n)))
        let hiq = math.min[f64](tau + bigm / (2.0f64 * f64(n)), f64(n - 1usize) / f64(n))
        i = 0usize
        while i < n {
            srt[i] = r[i] / math.max[f64](eps, band[i])
            i += 1usize
        }
        sort_asc(srt)
        let k1 = quant7(srt, loq)
        let k2 = quant7(srt, hiq)
        i = 0usize
        while i < n {
            sl[i] = r[i] < band[i] * k1
            su[i] = r[i] > band[i] * k2
            i += 1usize
        }
        var bad = 0usize
        while !optimal && bad < max_bad {
            var keep = 0usize
            var nsl = 0usize
            var nsu = 0usize
            i = 0usize
            while i < n {
                if sl[i] { nsl += 1usize }
                if su[i] { nsu += 1usize }
                if !sl[i] && !su[i] { keep += 1usize }
                i += 1usize
            }
            var rows = keep
            if nsl > 0usize { rows += 1usize }
            if nsu > 0usize { rows += 1usize }
            let (x2, e12) = mem.alloc[f64](a, rows * p)
            let (y2, e13) = mem.alloc[f64](a, rows)
            if e12 != ok || e13 != ok { ret (r, mem.Full) }
            var w = 0usize
            i = 0usize
            while i < n {
                if !sl[i] && !su[i] {
                    y2[w] = y[i]
                    var j = 0usize
                    while j < p {
                        x2[j * rows + w] = x[j * n + i]
                        j += 1usize
                    }
                    w += 1usize
                }
                i += 1usize
            }
            if nsl > 0usize {
                y2[w] = 0.0f64
                var j = 0usize
                while j < p {
                    x2[j * rows + w] = 0.0f64
                    j += 1usize
                }
                i = 0usize
                while i < n {
                    if sl[i] {
                        y2[w] += y[i]
                        j = 0usize
                        while j < p {
                            x2[j * rows + w] += x[j * n + i]
                            j += 1usize
                        }
                    }
                    i += 1usize
                }
                w += 1usize
            }
            if nsu > 0usize {
                y2[w] = 0.0f64
                var j = 0usize
                while j < p {
                    x2[j * rows + w] = 0.0f64
                    j += 1usize
                }
                i = 0usize
                while i < n {
                    if su[i] {
                        y2[w] += y[i]
                        j = 0usize
                        while j < p {
                            x2[j * rows + w] += x[j * n + i]
                            j += 1usize
                        }
                    }
                    i += 1usize
                }
                w += 1usize
            }
            let (z1, z1e) = rq_fnb(a, x2, y2, rows, p, tau, eps)
            if z1e != ok { ret (z1, z1e) }
            zc = z1
            var nbad = 0usize
            var anyb = false
            i = 0usize
            while i < n {
                var fit = 0.0f64
                var j = 0usize
                while j < p {
                    fit += x[j * n + i] * z1[j]
                    j += 1usize
                }
                let ri = y[i] - fit
                rq1[i] = 0.0f64
                if (ri < 0.0f64 && su[i]) || (ri > 0.0f64 && sl[i]) {
                    nbad += 1usize
                    anyb = true
                    rq1[i] = 1.0f64
                }
                i += 1usize
            }
            if anyb {
                if f64(nbad) > 0.1f64 * bigm {
                    bad += 1usize
                    m = 2usize * m
                    break
                }
                i = 0usize
                while i < n {
                    if rq1[i] == 1.0f64 {
                        su[i] = false
                        sl[i] = false
                    }
                    i += 1usize
                }
            } else {
                optimal = true
            }
        }
    }
    ret (zc, ok)
}

// ---- anova.rq

// the coefficients and the dual solution of rq.fit.br
fn rq_dual(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, b: []f64, dual: []f64) -> err {
    let (ci, e2) = mem.alloc[f64](a, 4usize * p)
    let (tn, e3) = mem.alloc[f64](a, 4usize * p)
    let (qn, e4) = mem.alloc[f64](a, p)
    if e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    let tol = math.pow[f64](2.220446049250313e-16f64, 2.0f64 / 3.0f64)
    let (ift, re) = rqbr(a, n, p, x, y, tau, tol, 1.7976931348623157e308f64, false, qn, 0.0f64, b, dual, ci, tn)
    ret re
}

// anova.rq(fit, reduced, test = "Wald"): the Wald F test of the coefficients dropped in the reduced model, covariance by se = "nid". out = (ndf, ddf, Tn, pvalue)
fn anova_wald(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, drop: []const usize, out: []f64) -> err {
    let (se, e1) = mem.alloc[f64](a, p)
    let (cov, e2) = mem.alloc[f64](a, p * p)
    let (hinv, e3) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    let (b, be) = rq(a, x, y, n, p, tau)
    if be != ok { ret be }
    if rq_cov_nid(a, x, y, n, p, tau, se, cov, hinv) != ok { ret mem.Full }
    let q = drop.len
    let (mm, e4) = mem.alloc[f64](a, q * q)
    let (cv, e5) = mem.alloc[f64](a, q)
    let (cs, e6) = mem.alloc[f64](a, q)
    if e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var i = 0usize
    while i < q {
        cv[i] = b[drop[i]]
        cs[i] = b[drop[i]]
        var j = 0usize
        while j < q {
            mm[i * q + j] = cov[drop[j] * p + drop[i]]
            j += 1usize
        }
        i += 1usize
    }
    if !solve_dense(mm, cs, q) { ret mem.Full }
    var tn = 0.0f64
    i = 0usize
    while i < q {
        tn += cv[i] * cs[i]
        i += 1usize
    }
    tn = tn / f64(q)
    out[0usize] = f64(q)
    out[1usize] = f64(n - p)
    out[2usize] = tn
    out[3usize] = 1.0f64 - nb.pf(tn, f64(q), f64(n - p), true, false)
    ret ok
}

// residuals of column col of x1 (n by q) on x0 (n by p0), no intercept, weights w (all ones when unweighted)
fn ls_resid(a: *mem.Arena, x0: []const f64, p0: usize, x1: []const f64, col: usize, w: []const f64, n: usize, out: []f64) -> err {
    let (mm, e1) = mem.alloc[f64](a, p0 * p0)
    let (rh, e2) = mem.alloc[f64](a, p0)
    if e1 != ok || e2 != ok { ret mem.Full }
    var r1 = 0usize
    while r1 < p0 {
        var r2 = 0usize
        while r2 < p0 {
            var sv = 0.0f64
            var i = 0usize
            while i < n {
                sv += x0[r1 * n + i] * w[i] * x0[r2 * n + i]
                i += 1usize
            }
            mm[r1 * p0 + r2] = sv
            r2 += 1usize
        }
        var sr = 0.0f64
        var i = 0usize
        while i < n {
            sr += x0[r1 * n + i] * w[i] * x1[col * n + i]
            i += 1usize
        }
        rh[r1] = sr
        r1 += 1usize
    }
    if !solve_dense(mm, rh, p0) { ret mem.Full }
    var i = 0usize
    while i < n {
        var fit = 0.0f64
        var k = 0usize
        while k < p0 {
            fit += x0[k * n + i] * rh[k]
            k += 1usize
        }
        out[i] = x1[col * n + i] - fit
        i += 1usize
    }
    ret ok
}

// anova.rq(fit, reduced, test = "rank", score = "tau"): the rank-score test of the dropped coefficients. out = (ndf, ddf, Tn, pvalue)
fn anova_rank(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, tau: f64, drop: []const usize, iid: bool, out: []f64) -> err {
    let q = drop.len
    let p0 = p - q
    let (x0, e1) = mem.alloc[f64](a, n * p0)
    let (x1, e2) = mem.alloc[f64](a, n * q)
    let (w, e3) = mem.alloc[f64](a, n)
    let (b0, e4) = mem.alloc[f64](a, p0)
    let (dual, e5) = mem.alloc[f64](a, n)
    let (x1h, e6) = mem.alloc[f64](a, n * q)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var c0 = 0usize
    var c1 = 0usize
    var c = 0usize
    while c < p {
        var isdrop = false
        var k = 0usize
        while k < q {
            if drop[k] == c { isdrop = true }
            k += 1usize
        }
        var i = 0usize
        while i < n {
            if isdrop { x1[c1 * n + i] = x[c * n + i] } else { x0[c0 * n + i] = x[c * n + i] }
            i += 1usize
        }
        if isdrop { c1 += 1usize } else { c0 += 1usize }
        c += 1usize
    }
    if rq_dual(a, x0, y, n, p0, tau, b0, dual) != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        w[i] = 1.0f64
        i += 1usize
    }
    if !iid {
        let tol = math.pow[f64](2.220446049250313e-16f64, 2.0f64 / 3.0f64)
        let h = bandwidth_rq(tau, f64(n), true)
        let (bhi, e7) = rq(a, x0, y, n, p0, tau + h)
        if e7 != ok { ret e7 }
        let (blo, e8) = rq(a, x0, y, n, p0, tau - h)
        if e8 != ok { ret e8 }
        i = 0usize
        while i < n {
            var dy = 0.0f64
            var j = 0usize
            while j < p0 {
                dy += x0[j * n + i] * (bhi[j] - blo[j])
                j += 1usize
            }
            var fv = 2.0f64 * h / (dy - tol)
            if !(fv > tol) { fv = tol }
            w[i] = fv
            i += 1usize
        }
    }
    let (col, e9) = mem.alloc[f64](a, n)
    if e9 != ok { ret mem.Full }
    var k = 0usize
    while k < q {
        if ls_resid(a, x0, p0, x1, k, w, n, col) != ok { ret mem.Full }
        i = 0usize
        while i < n {
            x1h[k * n + i] = col[i]
            i += 1usize
        }
        k += 1usize
    }
    let (tv, e10) = mem.alloc[f64](a, q)
    let (gm, e11) = mem.alloc[f64](a, q * q)
    let (ts, e12) = mem.alloc[f64](a, q)
    if e10 != ok || e11 != ok || e12 != ok { ret mem.Full }
    k = 0usize
    while k < q {
        var sv = 0.0f64
        i = 0usize
        while i < n {
            sv += x1h[k * n + i] * (dual[i] - (1.0f64 - tau))
            i += 1usize
        }
        tv[k] = sv
        ts[k] = sv
        var k2 = 0usize
        while k2 < q {
            var sg = 0.0f64
            i = 0usize
            while i < n {
                sg += x1h[k * n + i] * x1h[k2 * n + i]
                i += 1usize
            }
            gm[k * q + k2] = sg
            k2 += 1usize
        }
        k += 1usize
    }
    if !solve_dense(gm, ts, q) { ret mem.Full }
    var tn = 0.0f64
    k = 0usize
    while k < q {
        tn += tv[k] * ts[k]
        k += 1usize
    }
    tn = tn / (tau * (1.0f64 - tau))
    tn = tn / f64(q)
    out[0usize] = f64(q)
    out[1usize] = f64(n - p0 - q)
    out[2usize] = tn
    out[3usize] = 1.0f64 - nc.pnf(tn, f64(q), f64(n - p0 - q), 0.0f64, true, false)
    ret ok
}

// anova.rq(fit_1, ..., fit_m) with distinct taus, se = "nid": the equality-of-slopes Wald test. joint tests all slopes together, out = (ndf, ddf, Tn, pvalue); otherwise out holds one such row per slope
fn anova_taus(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, taus: []const f64, joint: bool, out: []f64) -> err {
    let m = taus.len
    let pm = p * m
    let (coef, e1) = mem.alloc[f64](a, pm)
    let (hs, e2) = mem.alloc[f64](a, m * p * p)
    let (jm, e3) = mem.alloc[f64](a, p * p)
    let (w, e4) = mem.alloc[f64](a, pm * pm)
    let (tmp, e5) = mem.alloc[f64](a, p * p)
    let (se, e6) = mem.alloc[f64](a, p)
    let (cov, e7) = mem.alloc[f64](a, p * p)
    let (hv, e8) = mem.alloc[f64](a, p * p)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var k = 0usize
    while k < m {
        let (b, be) = rq(a, x, y, n, p, taus[k])
        if be != ok { ret be }
        if rq_cov_nid(a, x, y, n, p, taus[k], se, cov, hv) != ok { ret mem.Full }
        var j = 0usize
        while j < p {
            coef[k * p + j] = b[j]
            j += 1usize
        }
        j = 0usize
        while j < p * p {
            hs[k * p * p + j] = hv[j]
            j += 1usize
        }
        k += 1usize
    }
    var c = 0usize
    while c < p {
        var c2 = 0usize
        while c2 < p {
            var sv = 0.0f64
            var i = 0usize
            while i < n {
                sv += x[c * n + i] * x[c2 * n + i]
                i += 1usize
            }
            jm[c2 * p + c] = sv
            c2 += 1usize
        }
        c += 1usize
    }
    // W block (k, l) = Hinv_k J Hinv_l * Omega_kl, entry [(k, i), (l, j)] at w[((l * p + j) * pm) + k * p + i]
    k = 0usize
    while k < m {
        var l = 0usize
        while l < m {
            var i = 0usize
            while i < p {
                var j = 0usize
                while j < p {
                    var sv = 0.0f64
                    var u = 0usize
                    while u < p {
                        var tm = 0.0f64
                        var v = 0usize
                        while v < p {
                            tm += jm[v * p + u] * hs[l * p * p + j * p + v]
                            v += 1usize
                        }
                        sv += hs[k * p * p + u * p + i] * tm
                        u += 1usize
                    }
                    var mn = taus[k]
                    if taus[l] < mn { mn = taus[l] }
                    w[(l * p + j) * pm + k * p + i] = sv * (mn - taus[k] * taus[l])
                    j += 1usize
                }
                i += 1usize
            }
            l += 1usize
        }
        k += 1usize
    }
    var ns = p - 1usize
    var rows = 1usize
    if !joint { rows = p - 1usize }
    var row = 0usize
    while row < rows {
        var first = 1usize
        if !joint {
            first = row + 1usize
            ns = 1usize
        }
        let dim = (m - 1usize) * ns
        let (dm, e9) = mem.alloc[f64](a, dim * dim)
        let (dv, e10) = mem.alloc[f64](a, dim)
        let (ds, e11) = mem.alloc[f64](a, dim)
        if e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
        // D row (k, s): coefficient s of fit k + 1 minus that of fit k
        var r1 = 0usize
        while r1 < dim {
            let k1 = r1 / ns
            let s1 = first + r1 % ns
            dv[r1] = coef[(k1 + 1usize) * p + s1] - coef[k1 * p + s1]
            ds[r1] = dv[r1]
            var r2 = 0usize
            while r2 < dim {
                let k2 = r2 / ns
                let s2 = first + r2 % ns
                dm[r1 * dim + r2] = w[((k2 + 1usize) * p + s2) * pm + (k1 + 1usize) * p + s1] - w[(k2 * p + s2) * pm + (k1 + 1usize) * p + s1] - w[((k2 + 1usize) * p + s2) * pm + k1 * p + s1] + w[(k2 * p + s2) * pm + k1 * p + s1]
                r2 += 1usize
            }
            r1 += 1usize
        }
        if !solve_dense(dm, ds, dim) { ret mem.Full }
        var qf = 0.0f64
        r1 = 0usize
        while r1 < dim {
            qf += dv[r1] * ds[r1]
            r1 += 1usize
        }
        let ndf = f64(dim)
        let ddf = f64(n * m) - f64(ns * (m - 1usize))
        var ddf2 = ddf
        if !joint { ddf2 = f64(n * m - (m - 1usize)) }
        let tn = qf / ndf
        out[row * 4usize] = ndf
        out[row * 4usize + 1usize] = ddf2
        out[row * 4usize + 2usize] = tn
        out[row * 4usize + 3usize] = 1.0f64 - nb.pf(tn, ndf, ddf2, true, false)
        row += 1usize
    }
    ret ok
}

// ---- nlrq: nonlinear quantile regression by the Koenker-Park interior point (Meketon steps), the step length by optim's L-BFGS-B on [0, 1]
// Models (kind): 0 a exp(b x), 1 a + b exp(c x), 2 a x / (b + x); the gradient is analytic, as deriv() gives it in R.

type NlCtx = struct { kind: i64, np: usize, n: usize, tau: f64, xs: []const f64, ys: []const f64, p0: []f64, st: []f64, tmp: []f64 }

fn nl_value(kind: i64, xv: f64, p: []const f64) -> f64 {
    if kind == 0i64 { ret p[0usize] * math.exp[f64](p[1usize] * xv) }
    if kind == 1i64 { ret p[0usize] + p[1usize] * math.exp[f64](p[2usize] * xv) }
    ret p[0usize] * xv / (p[1usize] + xv)
}

fn nl_grad(kind: i64, xv: f64, p: []const f64, g: []f64) {
    if kind == 0i64 {
        let e = math.exp[f64](p[1usize] * xv)
        g[0usize] = e
        g[1usize] = p[0usize] * (e * xv)
    } else if kind == 1i64 {
        let e = math.exp[f64](p[2usize] * xv)
        g[0usize] = 1.0f64
        g[1usize] = e
        g[2usize] = p[1usize] * (e * xv)
    } else {
        let d = p[1usize] + xv
        g[0usize] = xv / d
        g[1usize] = 0.0f64 - p[0usize] * xv / (d * d)
    }
}

fn nl_dev(c: *NlCtx, p: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < c.n {
        let r = c.ys[i] - nl_value(c.kind, c.xs[i], p)
        s += c.tau * math.max[f64](r, 0.0f64) + (c.tau - 1.0f64) * math.min[f64](r, 0.0f64)
        i += 1usize
    }
    ret s
}

fn nl_step_f(c: *NlCtx, lam: []const f64) -> f64 {
    var j = 0usize
    while j < c.np {
        c.tmp[j] = c.p0[j] + lam[0usize] * c.st[j]
        j += 1usize
    }
    ret nl_dev(c, c.tmp)
}

fn nl_step_g(c: *NlCtx, lam: []const f64, out: []f64) {
    var w: [1]f64 = zero
    w[0usize] = lam[0usize]
    var lo: [1]f64 = zero
    var up: [1]f64 = zero
    up[0usize] = 1.0f64
    let _ = lbf.lbfgsb_fd_gradient[NlCtx](c, nl_step_f, w[0usize..1usize], lo[0usize..1usize], up[0usize..1usize], 0.001f64, out)
}

// nlrq(y ~ model, start, tau) with the default control (maxiter 100, k 2, InitialStepSize 1, big 1e20, eps 1e-7, beta 0.97); pars holds start on entry and the estimate on exit
fn nlrq(a: *mem.Arena, kind: i64, xs: []const f64, ys: []const f64, tau: f64, pars: []f64, maxiter: usize) -> err {
    let n = xs.len
    let np = pars.len
    let big = 1.0e20f64
    let eps = 1.0e-7f64
    let beta = 0.97f64
    let (g, e1) = mem.alloc[f64](a, n * np)
    let (res, e2) = mem.alloc[f64](a, n)
    let (w, e3) = mem.alloc[f64](a, n)
    let (d, e4) = mem.alloc[f64](a, n)
    let (xw, e5) = mem.alloc[f64](a, n * np)
    let (yw, e6) = mem.alloc[f64](a, n)
    let (ww, e7) = mem.alloc[f64](a, n)
    let (gr, e8) = mem.alloc[f64](a, np)
    let (p0, e9) = mem.alloc[f64](a, np)
    let (st, e10) = mem.alloc[f64](a, np)
    let (tmp, e11) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    var c: NlCtx = zero
    c.kind = kind
    c.np = np
    c.n = n
    c.tau = tau
    c.xs = xs
    c.ys = ys
    c.p0 = p0
    c.st = st
    c.tmp = tmp
    var i = 0usize
    while i < n {
        w[i] = 0.0f64
        i += 1usize
    }
    var snew = nl_dev(&c, pars)
    var sold = big
    var nit = 0usize
    while sold - snew > eps && nit < maxiter {
        // gradient and residual at the current parameters
        i = 0usize
        while i < n {
            nl_grad(kind, xs[i], pars, gr)
            var j = 0usize
            while j < np {
                g[j * n + i] = gr[j]
                j += 1usize
            }
            res[i] = ys[i] - nl_value(kind, xs[i], pars)
            i += 1usize
        }
        // Meketon
        var yv = big
        var k = 1usize
        var zcoef: []f64 = zero
        while k <= 2usize {
            var cp = 0.0f64
            i = 0usize
            while i < n {
                cp += res[i] * w[i]
                i += 1usize
            }
            if !(yv - cp > eps) { break }
            i = 0usize
            while i < n {
                d[i] = math.min[f64](tau - w[i], 1.0f64 - tau + w[i])
                ww[i] = d[i] * d[i]
                yw[i] = math.sqrt[f64](ww[i]) * res[i]
                var j = 0usize
                while j < np {
                    xw[j * n + i] = math.sqrt[f64](ww[i]) * g[j * n + i]
                    j += 1usize
                }
                i += 1usize
            }
            let (ols, oe) = decomp.lm_fit(a, xw, n, np, yw, 1.0e-7f64)
            if oe != ok { ret oe }
            zcoef = ols.coef
            var dv = 0.0f64
            var mxa = eps
            var sv: []f64 = zero
            let (svd, se1) = mem.alloc[f64](a, n)
            if se1 != ok { ret mem.Full }
            sv = svd
            i = 0usize
            while i < n {
                var fit = 0.0f64
                var j = 0usize
                while j < np {
                    fit += g[j * n + i] * zcoef[j]
                    j += 1usize
                }
                let rz = res[i] - fit
                dv += tau * math.max[f64](rz, 0.0f64) + (tau - 1.0f64) * math.min[f64](rz, 0.0f64)
                sv[i] = rz * ww[i]
                let t1 = sv[i] / (tau - w[i])
                let t2 = 0.0f64 - sv[i] / (1.0f64 - tau + w[i])
                if t1 > mxa { mxa = t1 }
                if t2 > mxa { mxa = t2 }
                i += 1usize
            }
            yv = dv
            k += 1usize
            i = 0usize
            while i < n {
                w[i] = w[i] + (beta / mxa) * sv[i]
                i += 1usize
            }
        }
        var j = 0usize
        while j < np {
            st[j] = zcoef[j]
            p0[j] = pars[j]
            j += 1usize
        }
        var lam: [1]f64 = zero
        lam[0usize] = 1.0f64
        var lo: [1]f64 = zero
        var up: [1]f64 = zero
        up[0usize] = 1.0f64
        let (fv, fl) = lbf.lbfgsb[NlCtx](a, &c, nl_step_f, nl_step_g, lam[0usize..1usize], lo[0usize..1usize], up[0usize..1usize], 1.0e7f64, 0.0f64, 5usize, 100usize)
        if !(lam[0usize] == lam[0usize]) { ret mem.Full }
        j = 0usize
        while j < np {
            pars[j] = p0[j] + lam[0usize] * st[j]
            j += 1usize
        }
        sold = snew
        snew = nl_dev(&c, pars)
        // w <- qr.resid(qr(gradient at the new parameters), w)
        i = 0usize
        while i < n {
            nl_grad(kind, xs[i], pars, gr)
            j = 0usize
            while j < np {
                g[j * n + i] = gr[j]
                j += 1usize
            }
            i += 1usize
        }
        let (rw, rwe) = decomp.lm_fit(a, g, n, np, w, 1.0e-7f64)
        if rwe != ok { ret rwe }
        i = 0usize
        while i < n {
            w[i] = rw.residuals[i]
            i += 1usize
        }
        var w1 = 0.0f64
        i = 0usize
        while i < n {
            if w[i] > w1 { w1 = w[i] }
            i += 1usize
        }
        if w1 > tau {
            i = 0usize
            while i < n {
                w[i] = (w[i] * tau) / (w1 + eps)
                i += 1usize
            }
        }
        var w0 = 0.0f64
        i = 0usize
        while i < n {
            if 0.0f64 - w[i] > w0 { w0 = 0.0f64 - w[i] }
            i += 1usize
        }
        if w0 > 1.0f64 - tau {
            i = 0usize
            while i < n {
                w[i] = (w[i] * (1.0f64 - tau)) / (w0 + eps)
                i += 1usize
            }
        }
        nit += 1usize
    }
    ret ok
}

// ---- dynrq: rq on the lagged design of dynlm: y ~ L(y, ylags) + L(x, xlags) + trend(y), the rows where every lag exists
// ylags and xlags hold the lag orders (0 allowed for x); trend adds t / freq with t the position in the whole series. Returns the coefficients (intercept first).
fn dynrq(a: *mem.Arena, ys: []const f64, xs: []const f64, ylags: []const usize, xlags: []const usize, trend: bool, freq: f64, tau: f64) -> ([]f64, err) {
    let n = ys.len
    var maxlag = 0usize
    var k = 0usize
    while k < ylags.len {
        if ylags[k] > maxlag { maxlag = ylags[k] }
        k += 1usize
    }
    k = 0usize
    while k < xlags.len {
        if xlags[k] > maxlag { maxlag = xlags[k] }
        k += 1usize
    }
    var p = 1usize + ylags.len + xlags.len
    if trend { p += 1usize }
    let rows = n - maxlag
    let (d, de) = mem.alloc[f64](a, rows * p)
    let (yy, ye) = mem.alloc[f64](a, rows)
    if de != ok || ye != ok {
        var none: []f64 = zero
        ret (none, mem.Full)
    }
    var i = 0usize
    while i < rows {
        let t = i + maxlag
        yy[i] = ys[t]
        var col = 0usize
        d[col * rows + i] = 1.0f64
        col += 1usize
        k = 0usize
        while k < ylags.len {
            d[col * rows + i] = ys[t - ylags[k]]
            col += 1usize
            k += 1usize
        }
        k = 0usize
        while k < xlags.len {
            d[col * rows + i] = xs[t - xlags[k]]
            col += 1usize
            k += 1usize
        }
        if trend { d[col * rows + i] = f64(t + 1usize) / freq }
        i += 1usize
    }
    let (bq, bqe) = rq(a, d, yy, rows, p, tau)
    ret (bq, bqe)
}

// stepy2: ada = A1 diag(d1) A1' + A2 diag(d2) A2' (upper triangle), then b := ada^-1 b
fn fnc_stepy(a1: []const f64, d1: []const f64, n1: usize, a2: []const f64, d2: []const f64, n2: usize, p: usize, b: []f64, ada: []f64) -> bool {
    var z = 0usize
    while z < p * p {
        ada[z] = 0.0f64
        z += 1usize
    }
    var i = 0usize
    while i < n1 {
        var j = 0usize
        while j < p {
            if a1[j + p * i] != 0.0f64 {
                let tmp = d1[i] * a1[j + p * i]
                var r = 0usize
                while r <= j {
                    ada[r + p * j] += a1[r + p * i] * tmp
                    r += 1usize
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < n2 {
        var j = 0usize
        while j < p {
            if a2[j + p * i] != 0.0f64 {
                let tmp = d2[i] * a2[j + p * i]
                var r = 0usize
                while r <= j {
                    ada[r + p * j] += a2[r + p * i] * tmp
                    r += 1usize
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    if !dpotrf_u(ada, p) { ret false }
    dpotrs_u(ada, b, p)
    ret true
}

// rq.fit.fnc(x, y, R, r, tau, beta, eps): regression quantiles restricted by R b >= r (rqfnc.f / lpfnc). x is n by p and
// rm is n2 by p, both column-major. This is the function the plan calls rrq.
fn rq_fnc(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, p: usize, rm: []const f64, rr2: []const f64, n2: usize, tau: f64, beta: f64, eps: f64) -> ([]f64, err) {
    let (yo, e0) = mem.alloc[f64](a, p)
    if e0 != ok { ret (yo, e0) }
    let (a1, ea1) = transpose_design(a, x, n, p)
    let (a2, ea2) = transpose_design(a, rm, n2, p)
    if ea1 != ok || ea2 != ok { ret (yo, mem.Full) }
    let nm = math.max[usize](n, n2)
    let (x1, e1) = mem.alloc[f64](a, n)
    let (x2, e2) = mem.alloc[f64](a, n2)
    let (s, e3) = mem.alloc[f64](a, n)
    let (z1, e4) = mem.alloc[f64](a, n)
    let (z2, e5) = mem.alloc[f64](a, n2)
    let (w, e6) = mem.alloc[f64](a, n)
    let (dx1, e7) = mem.alloc[f64](a, n)
    let (dx2, e8) = mem.alloc[f64](a, n2)
    let (ds, e9) = mem.alloc[f64](a, n)
    let (dz1, e10) = mem.alloc[f64](a, n)
    let (dz2, e11) = mem.alloc[f64](a, n2)
    let (dw, e12) = mem.alloc[f64](a, n)
    let (dr1, e13) = mem.alloc[f64](a, n)
    let (dr2, e14) = mem.alloc[f64](a, n2)
    let (r2, e15) = mem.alloc[f64](a, n2)
    let (d1, e16) = mem.alloc[f64](a, n)
    let (d2, e17) = mem.alloc[f64](a, n2)
    let (u, e18) = mem.alloc[f64](a, nm)
    let (dy, e19) = mem.alloc[f64](a, p)
    let (rhs, e20) = mem.alloc[f64](a, p)
    let (ada, e21) = mem.alloc[f64](a, p * p)
    let (rh0, e22) = mem.alloc[f64](a, p)
    let (c1, e23) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok || e23 != ok { ret (yo, mem.Full) }
    let big = 1.0e20f64
    var i = 0usize
    while i < n {
        x1[i] = 1.0f64 - tau
        c1[i] = 0.0f64 - y[i]
        u[i] = 1.0f64
        d1[i] = 1.0f64
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var sm = 0.0f64
        i = 0usize
        while i < n {
            sm += x[j * n + i]
            i += 1usize
        }
        rh0[j] = (1.0f64 - tau) * sm
        yo[j] = 0.0f64
        j += 1usize
    }
    i = 0usize
    while i < n2 {
        x2[i] = 1.0f64
        d2[i] = 0.0f64
        z2[i] = 1.0f64
        i += 1usize
    }
    gemv_n(a1, n, p, 1.0f64, c1, yo)
    if !fnc_stepy(a1, d1, n, a2, d2, n2, p, yo, ada) { ret (yo, mem.Full) }
    i = 0usize
    while i < n {
        s[i] = c1[i]
        i += 1usize
    }
    gemv_t(a1, n, p, 0.0f64 - 1.0f64, yo, 1.0f64, s)
    i = 0usize
    while i < n {
        if math.abs[f64](s[i]) < eps {
            z1[i] = math.max[f64](s[i], 0.0f64) + eps
            w[i] = math.max[f64](0.0f64 - s[i], 0.0f64) + eps
        } else {
            z1[i] = math.max[f64](s[i], 0.0f64)
            w[i] = math.max[f64](0.0f64 - s[i], 0.0f64)
        }
        s[i] = u[i] - x1[i]
        i += 1usize
    }
    var gap = dotv(z1, x1, n) + dotv(z2, x2, n2) + dotv(w, s, n)
    var nit = 0usize
    while gap > eps && nit < 500usize {
        nit += 1usize
        i = 0usize
        while i < n2 {
            r2[i] = 0.0f64 - rr2[i]
            i += 1usize
        }
        gemv_t(a2, n2, p, 0.0f64 - 1.0f64, yo, 1.0f64, r2)
        j = 0usize
        while j < p {
            dy[j] = rh0[j]
            j += 1usize
        }
        gemv_n(a1, n, p, 0.0f64 - 1.0f64, x1, dy)
        gemv_n(a2, n2, p, 0.0f64 - 1.0f64, x2, dy)
        i = 0usize
        while i < n {
            d1[i] = 1.0f64 / (z1[i] / x1[i] + w[i] / s[i])
            ds[i] = z1[i] - w[i]
            dz1[i] = d1[i] * ds[i]
            i += 1usize
        }
        i = 0usize
        while i < n2 {
            d2[i] = x2[i] / z2[i]
            dz2[i] = d2[i] * r2[i]
            i += 1usize
        }
        gemv_n(a1, n, p, 1.0f64, dz1, dy)
        gemv_n(a2, n2, p, 1.0f64, dz2, dy)
        j = 0usize
        while j < p {
            rhs[j] = dy[j]
            j += 1usize
        }
        if !fnc_stepy(a1, d1, n, a2, d2, n2, p, dy, ada) { ret (yo, mem.Full) }
        gemv_t(a1, n, p, 1.0f64, dy, 0.0f64 - 1.0f64, ds)
        var deltap = big
        var deltad = big
        i = 0usize
        while i < n {
            dx1[i] = d1[i] * ds[i]
            ds[i] = 0.0f64 - dx1[i]
            dz1[i] = 0.0f64 - z1[i] * (dx1[i] / x1[i] + 1.0f64)
            dw[i] = 0.0f64 - w[i] * (ds[i] / s[i] + 1.0f64)
            if dx1[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - x1[i] / dx1[i]) }
            if ds[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - s[i] / ds[i]) }
            if dz1[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - z1[i] / dz1[i]) }
            if dw[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - w[i] / dw[i]) }
            i += 1usize
        }
        i = 0usize
        while i < n2 {
            dx2[i] = r2[i]
            i += 1usize
        }
        gemv_t(a2, n2, p, 1.0f64, dy, 0.0f64 - 1.0f64, dx2)
        i = 0usize
        while i < n2 {
            dx2[i] = d2[i] * dx2[i]
            dz2[i] = 0.0f64 - z2[i] * (dx2[i] / x2[i] + 1.0f64)
            if dx2[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - x2[i] / dx2[i]) }
            if dz2[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - z2[i] / dz2[i]) }
            i += 1usize
        }
        deltap = math.min[f64](beta * deltap, 1.0f64)
        deltad = math.min[f64](beta * deltad, 1.0f64)
        if math.min[f64](deltap, deltad) < 1.0f64 {
            var mu = dotv(x1, z1, n) + dotv(x2, z2, n2) + dotv(s, w, n)
            let g = mu + deltap * dotv(dx1, z1, n) + deltad * dotv(dz1, x1, n) + deltap * deltad * dotv(dz1, dx1, n) + deltap * dotv(dx2, z2, n2) + deltad * dotv(dz2, x2, n2) + deltap * deltad * dotv(dz2, dx2, n2) + deltap * dotv(ds, w, n) + deltad * dotv(dw, s, n) + deltap * deltad * dotv(ds, dw, n)
            let q = g / mu
            mu = mu * (q * q * q) / (f64(2usize * n) + f64(n2))
            i = 0usize
            while i < n {
                let dsdw = ds[i] * dw[i]
                dr1[i] = d1[i] * (mu * (1.0f64 / s[i] - 1.0f64 / x1[i]) + dx1[i] * dz1[i] / x1[i] - dsdw / s[i])
                i += 1usize
            }
            i = 0usize
            while i < n2 {
                dr2[i] = d2[i] * (dx2[i] * dz2[i] / x2[i] - mu / x2[i])
                i += 1usize
            }
            j = 0usize
            while j < p {
                let tm = rhs[j]
                rhs[j] = dy[j]
                dy[j] = tm
                j += 1usize
            }
            gemv_n(a1, n, p, 1.0f64, dr1, dy)
            gemv_n(a2, n2, p, 1.0f64, dr2, dy)
            dpotrs_u(ada, dy, p)
            gemv_t(a1, n, p, 1.0f64, dy, 0.0f64, u)
            deltap = big
            deltad = big
            i = 0usize
            while i < n {
                let dsdw = ds[i] * dw[i]
                let dxdz1 = dx1[i] * dz1[i]
                dx1[i] = d1[i] * (u[i] - z1[i] + w[i]) - dr1[i]
                ds[i] = 0.0f64 - dx1[i]
                dz1[i] = 0.0f64 - z1[i] + (mu - z1[i] * dx1[i] - dxdz1) / x1[i]
                dw[i] = 0.0f64 - w[i] + (mu - w[i] * ds[i] - dsdw) / s[i]
                if dx1[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - x1[i] / dx1[i]) }
                if ds[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - s[i] / ds[i]) }
                if dz1[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - z1[i] / dz1[i]) }
                if dw[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - w[i] / dw[i]) }
                i += 1usize
            }
            gemv_t(a2, n2, p, 1.0f64, dy, 0.0f64, u)
            i = 0usize
            while i < n2 {
                let dxdz2 = dx2[i] * dz2[i]
                dx2[i] = d2[i] * (u[i] - r2[i]) - dr2[i]
                dz2[i] = 0.0f64 - z2[i] + (mu - z2[i] * dx2[i] - dxdz2) / x2[i]
                if dx2[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - x2[i] / dx2[i]) }
                if dz2[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - z2[i] / dz2[i]) }
                i += 1usize
            }
            deltap = math.min[f64](beta * deltap, 1.0f64)
            deltad = math.min[f64](beta * deltad, 1.0f64)
        }
        i = 0usize
        while i < n {
            x1[i] += deltap * dx1[i]
            s[i] += deltap * ds[i]
            z1[i] += deltad * dz1[i]
            w[i] += deltad * dw[i]
            i += 1usize
        }
        i = 0usize
        while i < n2 {
            x2[i] += deltap * dx2[i]
            z2[i] += deltad * dz2[i]
            i += 1usize
        }
        j = 0usize
        while j < p {
            yo[j] += deltad * dy[j]
            j += 1usize
        }
        gap = dotv(z1, x1, n) + dotv(z2, x2, n2) + dotv(w, s, n)
    }
    j = 0usize
    while j < p {
        yo[j] = 0.0f64 - yo[j]
        j += 1usize
    }
    ret (yo, ok)
}

// rq.fit.sfn(x, y, tau, rhs): the sparse Frisch-Newton of srqfn.f (slpfn) with a dense Cholesky; x is n by m column-major,
// tau is 0.5 whenever rhs is supplied. Returns the m coefficients.
fn rq_sfn(a: *mem.Arena, x: []const f64, y: []const f64, n: usize, m: usize, tau: f64, rhs: []const f64, small: f64, maxit: usize) -> ([]f64, err) {
    let (yo, e0) = mem.alloc[f64](a, m)
    if e0 != ok { ret (yo, e0) }
    let (am, ea) = transpose_design(a, x, n, m)
    if ea != ok { ret (yo, ea) }
    let (yn, e1) = mem.alloc[f64](a, n)
    let (xx, e2) = mem.alloc[f64](a, n)
    let (s, e3) = mem.alloc[f64](a, n)
    let (r, e4) = mem.alloc[f64](a, n)
    let (z, e5) = mem.alloc[f64](a, n)
    let (w, e6) = mem.alloc[f64](a, n)
    let (q, e7) = mem.alloc[f64](a, n)
    let (dx, e8) = mem.alloc[f64](a, n)
    let (ds, e9) = mem.alloc[f64](a, n)
    let (dz, e10) = mem.alloc[f64](a, n)
    let (dw, e11) = mem.alloc[f64](a, n)
    let (dxdz, e12) = mem.alloc[f64](a, n)
    let (dsdw, e13) = mem.alloc[f64](a, n)
    let (xi, e14) = mem.alloc[f64](a, n)
    let (xinv, e15) = mem.alloc[f64](a, n)
    let (sinv, e16) = mem.alloc[f64](a, n)
    let (ww1, e17) = mem.alloc[f64](a, n)
    let (dy, e18) = mem.alloc[f64](a, m)
    let (c, e19) = mem.alloc[f64](a, m)
    let (ada, e20) = mem.alloc[f64](a, m * m)
    let (one, e21) = mem.alloc[f64](a, n)
    let (ww2, e22) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok || e17 != ok || e18 != ok || e19 != ok || e20 != ok || e21 != ok || e22 != ok { ret (yo, mem.Full) }
    let beta = 0.9995f64
    var i = 0usize
    while i < n {
        yn[i] = 0.0f64 - y[i]
        xx[i] = 1.0f64 - tau
        s[i] = 1.0f64 - xx[i]
        one[i] = 1.0f64
        i += 1usize
    }
    var j = 0usize
    while j < m {
        yo[j] = 0.0f64
        j += 1usize
    }
    gemv_n(am, n, m, 1.0f64, yn, yo)
    if !fnb_stepy(am, one, n, m, yo, ada) { ret (yo, mem.Full) }
    i = 0usize
    while i < n {
        r[i] = yn[i]
        i += 1usize
    }
    gemv_t(am, n, m, 0.0f64 - 1.0f64, yo, 1.0f64, r)
    i = 0usize
    while i < n {
        var rp = 0.0f64
        if r[i] > 0.0f64 { rp = r[i] }
        z[i] = rp
        if math.abs[f64](r[i]) < small { z[i] = rp + small }
        w[i] = z[i] - r[i]
        i += 1usize
    }
    var gap = dotv(z, xx, n) + dotv(w, s, n)
    var it = 0usize
    while !(gap < small || it > maxit) {
        it += 1usize
        i = 0usize
        while i < n {
            q[i] = 1.0f64 / (z[i] / xx[i] + w[i] / s[i])
            r[i] = z[i] - w[i]
            ww1[i] = q[i] * r[i]
            i += 1usize
        }
        j = 0usize
        while j < m {
            ww2[j] = 0.0f64
            c[j] = 0.0f64
            j += 1usize
        }
        gemv_n(am, n, m, 1.0f64, xx, ww2)
        gemv_n(am, n, m, 1.0f64, ww1, c)
        j = 0usize
        while j < m {
            c[j] = rhs[j] - ww2[j] + c[j]
            dy[j] = c[j]
            j += 1usize
        }
        if !fnb_stepy(am, q, n, m, dy, ada) { ret (yo, mem.Full) }
        gemv_t(am, n, m, 1.0f64, dy, 0.0f64, dx)
        var deltap = 1.0e20f64
        var deltad = 1.0e20f64
        i = 0usize
        while i < n {
            dx[i] = q[i] * (dx[i] - r[i])
            ds[i] = 0.0f64 - dx[i]
            dz[i] = 0.0f64 - z[i] * (1.0f64 + dx[i] / xx[i])
            dw[i] = 0.0f64 - w[i] * (1.0f64 + ds[i] / s[i])
            if dx[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - xx[i] / dx[i]) }
            if ds[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - s[i] / ds[i]) }
            if dz[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - z[i] / dz[i]) }
            if dw[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - w[i] / dw[i]) }
            i += 1usize
        }
        deltap = math.min[f64](beta * deltap, 1.0f64)
        deltad = math.min[f64](beta * deltad, 1.0f64)
        if deltap * deltad < 1.0f64 {
            var mu = dotv(z, xx, n) + dotv(w, s, n)
            let g = dotv(z, xx, n) + deltap * dotv(z, dx, n) + deltad * dotv(dz, xx, n) + deltad * deltap * dotv(dz, dx, n) + dotv(w, s, n) + deltap * dotv(w, ds, n) + deltad * dotv(dw, s, n) + deltad * deltap * dotv(dw, ds, n)
            let qq = g / mu
            mu = mu * (qq * qq * qq) / (2.0f64 * f64(n))
            i = 0usize
            while i < n {
                dxdz[i] = dx[i] * dz[i]
                dsdw[i] = ds[i] * dw[i]
                xinv[i] = 1.0f64 / xx[i]
                sinv[i] = 1.0f64 / s[i]
                xi[i] = xinv[i] * dxdz[i] - sinv[i] * dsdw[i] - mu * (xinv[i] - sinv[i])
                ww1[i] = q[i] * xi[i]
                i += 1usize
            }
            j = 0usize
            while j < m {
                ww2[j] = 0.0f64
                j += 1usize
            }
            gemv_n(am, n, m, 1.0f64, ww1, ww2)
            j = 0usize
            while j < m {
                c[j] = c[j] + ww2[j]
                dy[j] = c[j]
                j += 1usize
            }
            dpotrs_u(ada, dy, m)
            gemv_t(am, n, m, 1.0f64, dy, 0.0f64, dx)
            deltap = 1.0e20f64
            deltad = 1.0e20f64
            i = 0usize
            while i < n {
                dx[i] = q[i] * (dx[i] - xi[i] - r[i])
                ds[i] = 0.0f64 - dx[i]
                dz[i] = 0.0f64 - z[i] + xinv[i] * (mu - z[i] * dx[i] - dxdz[i])
                dw[i] = 0.0f64 - w[i] + sinv[i] * (mu - w[i] * ds[i] - dsdw[i])
                if dx[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - xx[i] / dx[i]) }
                if ds[i] < 0.0f64 { deltap = math.min[f64](deltap, 0.0f64 - s[i] / ds[i]) }
                if dz[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - z[i] / dz[i]) }
                if dw[i] < 0.0f64 { deltad = math.min[f64](deltad, 0.0f64 - w[i] / dw[i]) }
                i += 1usize
            }
            deltap = math.min[f64](beta * deltap, 1.0f64)
            deltad = math.min[f64](beta * deltad, 1.0f64)
        }
        i = 0usize
        while i < n {
            xx[i] += deltap * dx[i]
            s[i] += deltap * ds[i]
            w[i] += deltad * dw[i]
            z[i] += deltad * dz[i]
            i += 1usize
        }
        j = 0usize
        while j < m {
            yo[j] += deltad * dy[j]
            j += 1usize
        }
        gap = dotv(z, xx, n) + dotv(w, s, n)
    }
    j = 0usize
    while j < m {
        yo[j] = 0.0f64 - yo[j]
        j += 1usize
    }
    ret (yo, ok)
}

// rqss(y ~ qss(x, lambda, Dorder), tau) with an intercept: the coefficients (intercept, then the fitted values at the distinct
// sorted x beyond the first). dorder 1 penalises the change of slope (qss1), 0 the slope (qts1). rqss hands sfn its own rhs, tau 0.5.
fn rqss_tv(a: *mem.Arena, xs: []const f64, ys: []const f64, n: usize, lambda: f64, dorder: i64, tau: f64) -> ([]f64, err) {
    let (srt, se) = mem.alloc[f64](a, n)
    if se != ok { ret (srt, se) }
    var i = 0usize
    while i < n {
        srt[i] = xs[i]
        i += 1usize
    }
    sort_asc(srt)
    let (xun, xe) = mem.alloc[f64](a, n)
    if xe != ok { ret (xun, xe) }
    var nu = 0usize
    i = 0usize
    while i < n {
        if i == 0usize || srt[i] != srt[i - 1usize] {
            xun[nu] = srt[i]
            nu += 1usize
        }
        i += 1usize
    }
    let nh = nu - 1usize
    var np = nh
    if dorder == 1 { np = nh - 1usize }
    let rows = n + np
    let (xm, xme) = mem.alloc[f64](a, rows * nu)
    let (yy, ye) = mem.alloc[f64](a, rows)
    let (rhs, re) = mem.alloc[f64](a, nu)
    if xme != ok || ye != ok || re != ok { ret (rhs, mem.Full) }
    var z = 0usize
    while z < rows * nu {
        xm[z] = 0.0f64
        z += 1usize
    }
    i = 0usize
    while i < n {
        yy[i] = ys[i]
        xm[i] = 1.0f64
        var k = 0usize
        var found = false
        while k < nu && !found {
            if xun[k] == xs[i] {
                found = true
            } else {
                k += 1usize
            }
        }
        if k >= 1usize { xm[k * rows + i] = 1.0f64 }
        i += 1usize
    }
    var pr = 0usize
    while pr < np {
        yy[n + pr] = 0.0f64
        let h0 = xun[pr + 1usize] - xun[pr]
        if dorder == 1 {
            let h1 = xun[pr + 2usize] - xun[pr + 1usize]
            if pr >= 1usize { xm[pr * rows + n + pr] = lambda * (1.0f64 / h0) }
            xm[(pr + 1usize) * rows + n + pr] = lambda * (0.0f64 - 1.0f64 / h1 - 1.0f64 / h0)
            xm[(pr + 2usize) * rows + n + pr] = lambda * (1.0f64 / h1)
        } else {
            if pr >= 1usize { xm[pr * rows + n + pr] = lambda * (0.0f64 - 1.0f64 / h0) }
            xm[(pr + 1usize) * rows + n + pr] = lambda * (1.0f64 / h0)
        }
        pr += 1usize
    }
    var j = 0usize
    while j < nu {
        var sm = 0.0f64
        i = 0usize
        while i < n {
            sm += (1.0f64 - tau) * xm[j * rows + i]
            i += 1usize
        }
        var sa = 0.0f64
        i = n
        while i < rows {
            sa += 0.5f64 * xm[j * rows + i]
            i += 1usize
        }
        rhs[j] = sm + sa
        j += 1usize
    }
    let (cf, ce) = rq_sfn(a, xm, yy, rows, nu, 0.5f64, rhs, 1.0e-6f64, 100usize)
    ret (cf, ce)
}
