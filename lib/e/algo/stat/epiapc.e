// R Epi: apc.fit for the models "factor", "ns", "bs" and "ls" with the Poisson distribution, in all eight parametrizations ("ACP", "APC", "AdCP", "AdPC", "Ad-P-C",
// "Ad-C-P", "AC-P", "AP-C"): the age, period and cohort effects with their intervals, the drift, the reference period or cohort and the model comparison table.
// The cells are given as vectors A, P, D (cases) and Y (person-years); the effects are the glm fits of R step for step: the detrended period and cohort bases of
// Epi::detrend (the weighted projection on a constant and the standardised time, thinCol at 1e-6), a glm on the columns dqrdc2 keeps (a column it moves to the end is
// an NA coefficient, read as 0 by ci.lin), and ci.lin's Wald intervals.
//
// Not here: a knot list for npar, the binomial distribution, and a vector dr.extr; dr.extr is "1", "D", "R" (Y^2/D), "Y" or a number k (D + k Y).
//
// Layout of the answer (apc_fit): [p0, c0, nA, nP, nC, ndrift, Age (nA rows of age, rate, lower, upper), Per (nP rows of period, RR, lower, upper), Coh (nC rows of
// cohort, RR, lower, upper), drift (ndrift rows of estimate, lower, upper), model table (6 rows of residual df, residual deviance, AIC, test df, test deviance)].

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem
use e.algo.stat.armglm as ag
use e.algo.stat.robustbase as rb
use e.algo.stat.splines as sp
use e.algo.linalg.decomp as dc

type Mat = struct { r: usize, c: usize, v: []f64 }

fn mat_new(a: *mem.Arena, r: usize, c: usize) -> (Mat, err) {
    let (v, e) = mem.alloc[f64](a, r * c + 1usize)
    var i = 0usize
    if e == ok {
        while i < r * c + 1usize {
            v[i] = 0.0f64
            i += 1usize
        }
    }
    ret (Mat { r: r, c: c, v: v }, e)
}

// the columns of x then those of y (same rows)
fn hcat(a: *mem.Arena, x: Mat, y: Mat) -> (Mat, err) {
    let (m, e) = mat_new(a, x.r, x.c + y.c)
    if e != ok { ret (m, e) }
    var i = 0usize
    while i < x.r {
        var j = 0usize
        while j < x.c {
            m.v[i * m.c + j] = x.v[i * x.c + j]
            j += 1usize
        }
        j = 0usize
        while j < y.c {
            m.v[i * m.c + x.c + j] = y.v[i * y.c + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (m, ok)
}

fn col1(a: *mem.Arena, x: []const f64, n: usize) -> (Mat, err) {
    let (m, e) = mat_new(a, n, 1usize)
    if e != ok { ret (m, e) }
    var i = 0usize
    while i < n {
        m.v[i] = x[i]
        i += 1usize
    }
    ret (m, ok)
}

// the sorted distinct values of x
fn levels(a: *mem.Arena, x: []const f64, n: usize) -> ([]f64, usize, err) {
    let (u, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (u, 0usize, e) }
    var m = 0usize
    var i = 0usize
    while i < n {
        var j = 0usize
        var found = false
        while j < m {
            if u[j] == x[i] { found = true }
            j += 1usize
        }
        if !found {
            u[m] = x[i]
            m += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < m {
        let t = u[i]
        var j = i
        while j > 0usize && u[j - 1usize] > t {
            u[j] = u[j - 1usize]
            j -= 1usize
        }
        u[j] = t
        i += 1usize
    }
    ret (u, m, ok)
}

fn lev_index(u: []const f64, m: usize, v: f64) -> usize {
    var j = 0usize
    while j < m {
        if u[j] == v { ret j }
        j += 1usize
    }
    ret m
}

// model.matrix(~ factor(x) - 1)
fn dummies(a: *mem.Arena, x: []const f64, n: usize, u: []const f64, m: usize) -> (Mat, err) {
    let (d, e) = mat_new(a, n, m)
    if e != ok { ret (d, e) }
    var i = 0usize
    while i < n {
        d.v[i * m + lev_index(u, m, x[i])] = 1.0f64
        i += 1usize
    }
    ret (d, ok)
}

// the median of the weights y along x: the first x, in the stable order of x, where the cumulative weight exceeds half
fn med(a: *mem.Arena, x: []const f64, y: []const f64, n: usize) -> f64 {
    let (o, e) = mem.alloc[usize](a, n + 1usize)
    if e != ok { ret 0.0f64 }
    var i = 0usize
    while i < n {
        o[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let t = o[i]
        var j = i
        while j > 0usize && x[o[j - 1usize]] > x[t] {
            o[j] = o[j - 1usize]
            j -= 1usize
        }
        o[j] = t
        i += 1usize
    }
    var tot = 0.0f64
    i = 0usize
    while i < n {
        tot += y[i]
        i += 1usize
    }
    var cum = 0.0f64
    i = 0usize
    while i < n {
        cum += y[o[i]]
        if cum / tot > 0.5f64 { ret x[o[i]] }
        i += 1usize
    }
    ret x[o[n - 1usize]]
}

// the columns of the n by c matrix (column-major copy) that dqrdc2 keeps at tol, in pivot order
fn kept(a: *mem.Arena, x: Mat, tol: f64) -> ([]usize, usize, err) {
    let (cm, e) = mem.alloc[f64](a, x.r * x.c + 1usize)
    if e != ok {
        let (z, ze) = mem.alloc[usize](a, 1usize)
        ret (z, 0usize, ze)
    }
    var i = 0usize
    while i < x.r {
        var j = 0usize
        while j < x.c {
            cm[j * x.r + i] = x.v[i * x.c + j]
            j += 1usize
        }
        i += 1usize
    }
    let (q, qe) = rb.dqrdc2_blue(a, cm, x.r, x.c, tol)
    ret (q.pivot, q.rank, qe)
}

// Epi::detrend(rbind(Rp, M), c(t0, t), weight = c(0, wt)) with thinCol, the first row left out and, when sub, subtracted from the others. M has the n rows, rp the
// reference row (the index of a cell), t0 the reference time.
fn detrend(a: *mem.Arena, m: Mat, rrow: []const f64, t: []const f64, t0: f64, wt: []const f64, sub: bool) -> (Mat, err) {
    let n = m.r
    let nn = n + 1usize
    let (tt, e0) = mem.alloc[f64](a, nn)
    let (w, e1) = mem.alloc[f64](a, nn)
    if e0 != ok || e1 != ok { ret (m, mem.Exhausted) }
    tt[0usize] = t0
    w[0usize] = 0.0f64
    var i = 0usize
    while i < n {
        tt[i + 1usize] = t[i]
        w[i + 1usize] = wt[i]
        i += 1usize
    }
    var mean = 0.0f64
    i = 0usize
    while i < nn {
        mean += tt[i]
        i += 1usize
    }
    mean = mean / f64(nn)
    var ss = 0.0f64
    i = 0usize
    while i < nn {
        ss += (tt[i] - mean) * (tt[i] - mean)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / f64(nn - 1usize))
    i = 0usize
    while i < nn {
        tt[i] = (tt[i] - mean) / sd
        i += 1usize
    }
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    i = 0usize
    while i < nn {
        s0 += w[i]
        s1 += w[i] * tt[i]
        s2 += w[i] * tt[i] * tt[i]
        i += 1usize
    }
    let det = s0 * s2 - s1 * s1
    let (dd, e2) = mat_new(a, nn, m.c)
    if e2 != ok { ret (dd, e2) }
    var j = 0usize
    while j < m.c {
        var b0 = 0.0f64
        var b1 = 0.0f64
        i = 0usize
        while i < nn {
            var v = 0.0f64
            if i == 0usize { v = rrow[j] } else { v = m.v[(i - 1usize) * m.c + j] }
            b0 += w[i] * v
            b1 += w[i] * tt[i] * v
            i += 1usize
        }
        let g0 = (s2 * b0 - s1 * b1) / det
        let g1 = (s0 * b1 - s1 * b0) / det
        i = 0usize
        while i < nn {
            var v = 0.0f64
            if i == 0usize { v = rrow[j] } else { v = m.v[(i - 1usize) * m.c + j] }
            dd.v[i * m.c + j] = v - (g0 + g1 * tt[i])
            i += 1usize
        }
        j += 1usize
    }
    let (pv, rank, ke) = kept(a, dd, 1.0e-6f64)
    if ke != ok { ret (dd, ke) }
    let (out, e3) = mat_new(a, n, rank)
    if e3 != ok { ret (out, e3) }
    i = 0usize
    while i < n {
        j = 0usize
        while j < rank {
            var v = dd.v[(i + 1usize) * m.c + pv[j]]
            if sub { v = v - dd.v[pv[j]] }
            out.v[i * rank + j] = v
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

type Fit = struct { k: usize, rank: usize, coef: []const f64, cov: []const f64, eta: []const f64, dev: f64, aic: f64 }

// glm(y ~ x - 1, poisson, offset = off) over the columns of x dqrdc2 keeps; the others stay 0 in coef and cov
fn fit_model(a: *mem.Arena, x: Mat, y0: []const f64, off0: []const f64) -> (Fit, err) {
    let n = x.r
    let y = y0[0usize..n]
    let off = off0[0usize..n]
    let k = x.c
    var f = Fit { k: k, rank: 0usize, coef: y[0usize..0usize], cov: y[0usize..0usize], eta: y[0usize..0usize], dev: 0.0f64, aic: 0.0f64 }
    let (pv, rank, ke) = kept(a, x, 1.0e-11f64)
    if ke != ok { ret (f, ke) }
    let (xr, e0) = mat_new(a, n, rank)
    let (cf, e1) = mem.alloc[f64](a, rank + 1usize)
    let (cv, e2) = mem.alloc[f64](a, rank * rank + 1usize)
    let (info, e3) = mem.alloc[f64](a, 8usize)
    let (cff, e4) = mat_new(a, k, 1usize)
    let (cvf, e5) = mat_new(a, k, k)
    let (eta, e6) = mem.alloc[f64](a, n + 1usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (f, mem.Exhausted) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < rank {
            xr.v[i * rank + j] = x.v[i * k + pv[j]]
            j += 1usize
        }
        i += 1usize
    }
    let none = y[0usize..0usize]
    let it = ag.glm_fit_gen(a, xr.v, y, n, rank, 2usize, 1usize, none, off, true, cf, cv, info)
    if it == 0usize { ret (f, mem.Exhausted) }
    var j = 0usize
    while j < rank {
        cff.v[pv[j]] = cf[j]
        var l = 0usize
        while l < rank {
            cvf.v[pv[j] * k + pv[l]] = cv[j * rank + l]
            l += 1usize
        }
        j += 1usize
    }
    var ll = 0.0f64
    i = 0usize
    while i < n {
        var e = off[i]
        j = 0usize
        while j < k {
            e += x.v[i * k + j] * cff.v[j]
            j += 1usize
        }
        eta[i] = e
        ll += nm.dpois(y[i], math.exp[f64](e), true)
        i += 1usize
    }
    f.rank = rank
    f.coef = cff.v
    f.cov = cvf.v
    f.eta = eta
    f.dev = info[1usize]
    f.aic = 0.0f64 - 2.0f64 * ll + 2.0f64 * f64(rank)
    ret (f, ok)
}

// ci.exp: the rows of ctr (m by k) against the fit: exp of the estimate and of the limits, written as (est, lower, upper) at out[o + 3 i]
fn ci_exp(f: Fit, ctr: Mat, z: f64, out: []f64, o: usize, scale: f64) {
    var i = 0usize
    while i < ctr.r {
        var ct = 0.0f64
        var j = 0usize
        while j < f.k {
            ct += ctr.v[i * ctr.c + j] * f.coef[j]
            j += 1usize
        }
        var vc = 0.0f64
        j = 0usize
        while j < f.k {
            var s = 0.0f64
            var l = 0usize
            while l < f.k {
                s += f.cov[j * f.k + l] * ctr.v[i * ctr.c + l]
                l += 1usize
            }
            vc += ctr.v[i * ctr.c + j] * s
            j += 1usize
        }
        let se = math.sqrt[f64](vc)
        out[o + 3usize * i] = math.exp[f64](ct) * scale
        out[o + 3usize * i + 1usize] = math.exp[f64](ct - z * se) * scale
        out[o + 3usize * i + 2usize] = math.exp[f64](ct + z * se) * scale
        i += 1usize
    }
}

// rows idx of the block b (cells by kb) placed at columns c0.. of a matrix with k columns
fn place(a: *mem.Arena, b: Mat, rows: []const usize, nr: usize, c0: usize, k: usize) -> (Mat, err) {
    let (m, e) = mat_new(a, nr, k)
    if e != ok { ret (m, e) }
    var i = 0usize
    while i < nr {
        var j = 0usize
        while j < b.c {
            m.v[i * k + c0 + j] = b.v[rows[i] * b.c + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (m, ok)
}

// the cell of the first occurrence of each distinct value, ordered by value
fn first_cells(a: *mem.Arena, x: []const f64, n: usize, u: []const f64, m: usize) -> ([]usize, err) {
    let (r, e) = mem.alloc[usize](a, m + 1usize)
    if e != ok { ret (r, e) }
    var j = 0usize
    while j < m {
        var i = 0usize
        while i < n {
            if x[i] == u[j] {
                r[j] = i
                break
            }
            i += 1usize
        }
        j += 1usize
    }
    ret (r, ok)
}

fn ones(a: *mem.Arena, n: usize) -> (Mat, err) {
    let (m, e) = mat_new(a, n, 1usize)
    var i = 0usize
    while i < n && e == ok {
        m.v[i] = 1.0f64
        i += 1usize
    }
    ret (m, e)
}

fn closest(x: []const f64, n: usize, v: f64) -> usize {
    var best = 0usize
    var bd = 0.0f64
    var i = 0usize
    while i < n {
        var d = x[i] - v
        if d < 0.0f64 { d = 0.0f64 - d }
        if i == 0usize || d < bd {
            bd = d
            best = i
        }
        i += 1usize
    }
    ret best
}

// The natural cubic spline basis of splines::ns / Epi::Ns on the knots (the first and last are the boundary knots): the cubic B-splines of spline.des without the
// first, linear beyond the boundary, rotated by the Householder QR of the second derivatives at the boundary and the first two columns dropped.
type NsB = struct { m: usize, lo: f64, hi: f64, t: []f64, q: dc.Qr, v: []f64 }

fn ns_make(a: *mem.Arena, knots: []const f64) -> (NsB, err) {
    var b: NsB = zero
    let ni = knots.len - 2usize
    let (t, e1) = mem.alloc[f64](a, ni + 8usize)
    if e1 != ok { ret (b, e1) }
    sp.extend(t, knots[1usize..knots.len - 1usize], knots[0usize], knots[knots.len - 1usize], 4usize)
    let k = ni + 4usize
    let (cm, e2) = mem.alloc[f64](a, 2usize * (k - 1usize))
    let (v, e3) = mem.alloc[f64](a, k)
    if e2 != ok || e3 != ok { ret (b, mem.Exhausted) }
    var j = 1usize
    while j < k {
        cm[j - 1usize] = sp.bval(t, j, 4usize, knots[0usize], 2usize, knots[0usize], knots[knots.len - 1usize])
        cm[k - 1usize + j - 1usize] = sp.bval(t, j, 4usize, knots[knots.len - 1usize], 2usize, knots[0usize], knots[knots.len - 1usize])
        j += 1usize
    }
    let (q, qe) = rb.dqrdc2_blue(a, cm, k - 1usize, 2usize, 1.0e-7f64)
    if qe != ok { ret (b, qe) }
    b.m = ni
    b.lo = knots[0usize]
    b.hi = knots[knots.len - 1usize]
    b.t = t
    b.q = q
    b.v = v
    ret (b, ok)
}

// the m + 1 values of the basis at x into out
fn ns_row(b: *NsB, x: f64, out: []f64) {
    let k = b.m + 4usize
    var piv = b.lo
    var outside = false
    if x < b.lo { outside = true }
    if x > b.hi {
        outside = true
        piv = b.hi
    }
    var j = 1usize
    while j < k {
        if outside {
            b.v[j - 1usize] = sp.bval(b.t, j, 4usize, piv, 0usize, b.lo, b.hi) + (x - piv) * sp.bval(b.t, j, 4usize, piv, 1usize, b.lo, b.hi)
        } else {
            b.v[j - 1usize] = sp.bval(b.t, j, 4usize, x, 0usize, b.lo, b.hi)
        }
        j += 1usize
    }
    dc.qr_qty(&b.q, b.v[0usize..k - 1usize])
    j = 0usize
    while j <= b.m {
        out[j] = b.v[2usize + j]
        j += 1usize
    }
}

// quantile(rep(x, d), probs = (1:nk - 0.5) / nk), type 7, as the sorted distinct knots
fn quantile_knots(a: *mem.Arena, x: []const f64, d: []const f64, n: usize, nk: usize) -> ([]f64, usize, err) {
    var tot = 0usize
    var i = 0usize
    while i < n {
        tot += usize(d[i])
        i += 1usize
    }
    let (rx, e1) = mem.alloc[f64](a, tot + 1usize)
    let (kn, e2) = mem.alloc[f64](a, nk + 1usize)
    if e1 != ok || e2 != ok { ret (kn, 0usize, mem.Exhausted) }
    var at = 0usize
    i = 0usize
    while i < n {
        var r = 0usize
        while r < usize(d[i]) {
            rx[at] = x[i]
            at += 1usize
            r += 1usize
        }
        i += 1usize
    }
    let (xs, e3) = rb.sort_copy(a, rx[0usize..tot])
    if e3 != ok { ret (kn, 0usize, e3) }
    var m = 0usize
    i = 0usize
    while i < nk {
        let p = (f64(i + 1usize) - 0.5f64) / f64(nk)
        let index = 1.0f64 + f64(tot - 1usize) * p
        let lo = math.floor[f64](index)
        let hi = math.ceil[f64](index)
        var qs = xs[usize(lo) - 1usize]
        let xh = xs[usize(hi) - 1usize]
        if index > lo && xh != qs {
            let h = index - lo
            qs = (1.0f64 - h) * qs + h * xh
        }
        if m == 0usize || kn[m - 1usize] != qs {
            kn[m] = qs
            m += 1usize
        }
        i += 1usize
    }
    ret (kn, m, ok)
}

// the basis of one axis: the dummies of its levels (model 0) or the natural spline on the quantile knots (model 1), with the reference row at x0
fn axis_basis(a: *mem.Arena, model: usize, x: []const f64, d: []const f64, n: usize, u: []const f64, nl: usize, nk: usize, x0: f64) -> (Mat, []f64, err) {
    var rrow: []f64 = zero
    if model == 0usize {
        let (m, e) = dummies(a, x, n, u, nl)
        let (rr, e2) = mem.alloc[f64](a, nl + 1usize)
        if e != ok || e2 != ok { ret (m, rr, mem.Exhausted) }
        let k0 = closest(x, n, x0)
        var j = 0usize
        while j < nl {
            rr[j] = m.v[k0 * nl + j]
            j += 1usize
        }
        ret (m, rr, ok)
    }
    if model >= 2usize {
        // splines::bs(x, df = nk, degree = 3) or, for "ls", degree 1: interior knots at the quantiles of x, boundary knots at its range
        var deg = 3usize
        if model == 3usize { deg = 1usize }
        let ni = nk - deg
        let (xs, es) = rb.sort_copy(a, x[0usize..n])
        let (kn2, ek) = mem.alloc[f64](a, ni + 1usize)
        let (t, et) = mem.alloc[f64](a, ni + 2usize * (deg + 1usize))
        let w = nk
        let (m, em) = mat_new(a, n, w)
        let (rr, er) = mem.alloc[f64](a, w + 1usize)
        if es != ok || ek != ok || et != ok || em != ok || er != ok { ret (m, rr, mem.Exhausted) }
        let by = 1.0f64 / f64(ni + 1usize)
        var q = 0usize
        while q < ni {
            let p = f64(q + 1usize) * by
            let index = 1.0f64 + f64(n - 1usize) * p
            let lo2 = math.floor[f64](index)
            let hi2 = math.ceil[f64](index)
            var qs = xs[usize(lo2) - 1usize]
            let xh = xs[usize(hi2) - 1usize]
            if index > lo2 && xh != qs {
                let h = index - lo2
                qs = (1.0f64 - h) * qs + h * xh
            }
            kn2[q] = qs
            q += 1usize
        }
        let lo = xs[0usize]
        let hi = xs[n - 1usize]
        sp.extend(t, kn2[0usize..ni], lo, hi, deg + 1usize)
        var r = 0usize
        while r <= n {
            var xv = x0
            if r < n { xv = x[r] }
            var j = 1usize
            while j <= w {
                let v = sp.bval(t, j, deg + 1usize, xv, 0usize, lo, hi)
                if r < n { m.v[r * w + j - 1usize] = v } else { rr[j - 1usize] = v }
                j += 1usize
            }
            r += 1usize
        }
        ret (m, rr, ok)
    }
    let (kn, nkn, e1) = quantile_knots(a, x, d, n, nk)
    if e1 != ok || nkn < 3usize {
        let (m0, e0) = mat_new(a, 1usize, 1usize)
        ret (m0, rrow, mem.Exhausted)
    }
    let (nb, e2) = ns_make(a, kn[0usize..nkn])
    if e2 != ok {
        let (m0, e0) = mat_new(a, 1usize, 1usize)
        ret (m0, rrow, e2)
    }
    let w = nb.m + 1usize
    let (m, e3) = mat_new(a, n, w)
    let (rr, e4) = mem.alloc[f64](a, w + 1usize)
    if e3 != ok || e4 != ok { ret (m, rr, mem.Exhausted) }
    var nbv = nb
    var i = 0usize
    while i < n {
        ns_row(&nbv, x[i], m.v[i * w..i * w + w])
        i += 1usize
    }
    ns_row(&nbv, x0, rr)
    ret (m, rr, ok)
}

// out must hold 2 * n * 4 + 200 numbers. parm 0..7 in the order of apc.fit's match.arg; drmode 0 "1", 1 "D", 2 "R", 3 "Y", 4 numeric k = drk; refp, refc used when hasp, hasc;
// model 0 "factor", 1 "ns" with nka, nkp, nkc knots (npar) on the quantiles of the cases, 2 "bs" and 3 "ls" with nka, nkp, nkc degrees of freedom
fn apc_fit(a: *mem.Arena, av: []const f64, pv: []const f64, dv: []const f64, yv: []const f64, n: usize, parm: usize, drmode: usize, drk: f64, hasp: bool, refp: f64, hasc: bool, refc: f64, alpha: f64, scale: f64, model: usize, nka: usize, nkp: usize, nkc: usize, out: []f64) -> err {
    let (cv, ce) = mem.alloc[f64](a, n + 1usize)
    let (dP, de) = mem.alloc[f64](a, n + 1usize)
    let (dC, de2) = mem.alloc[f64](a, n + 1usize)
    let (wt, we) = mem.alloc[f64](a, n + 1usize)
    let (off, oe) = mem.alloc[f64](a, n + 1usize)
    if ce != ok || de != ok || de2 != ok || we != ok || oe != ok { ret mem.Exhausted }
    var i = 0usize
    while i < n {
        cv[i] = pv[i] - av[i]
        off[i] = math.log[f64](yv[i])
        wt[i] = 1.0f64
        if drmode == 1usize { wt[i] = dv[i] }
        if drmode == 2usize { wt[i] = (yv[i] * yv[i]) / dv[i] }
        if drmode == 3usize { wt[i] = yv[i] }
        if drmode == 4usize { wt[i] = dv[i] + drk * yv[i] }
        i += 1usize
    }
    var p0 = refp
    var c0 = refc
    if !hasp { p0 = med(a, pv, dv, n) }
    if !hasc { c0 = med(a, cv, dv, n) }
    i = 0usize
    while i < n {
        dP[i] = pv[i] - p0
        dC[i] = cv[i] - c0
        i += 1usize
    }
    let (ua, na, e1) = levels(a, av, n)
    let (up, np, e2) = levels(a, pv, n)
    let (uc, nc, e3) = levels(a, cv, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Exhausted }
    let (ma, rowa, e4) = axis_basis(a, model, av, dv, n, ua, na, nka, 0.0f64)
    let (mp, rowp, e5) = axis_basis(a, model, pv, dv, n, up, np, nkp, p0)
    let (mc, rowc, e6) = axis_basis(a, model, cv, dv, n, uc, nc, nkc, c0)
    let wa = ma.c
    let (one, e7) = ones(a, n)
    let (mdp, e8) = col1(a, dP, n)
    let (mdc, e9) = col1(a, dC, n)
    if e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Exhausted }
    let (ma1, e10) = hcat(a, one, ma)
    if e10 != ok { ret mem.Exhausted }
    let (mpr, e11) = detrend(a, mp, rowp, pv, p0, wt, hasp)
    let (mcr, e12) = detrend(a, mc, rowc, cv, c0, wt, hasc)
    if e11 != ok || e12 != ok { ret mem.Exhausted }
    let z = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
    let (apos, e13) = first_cells(a, av, n, ua, na)
    let (ppos, e14) = first_cells(a, pv, n, up, np)
    let (cpos, e15) = first_cells(a, cv, n, uc, nc)
    if e13 != ok || e14 != ok || e15 != ok { ret mem.Exhausted }
    // the model comparison table: A, A + drift, AC, APC, AP, A + drift (anova of the glm fits with intercept)
    let (mA, f1) = hcat(a, one, ma)
    let (mAd, f2) = hcat(a, mA, mdp)
    let (mAP0, f3) = hcat(a, mAd, mp)
    let (mAC0, f4) = hcat(a, mAd, mc)
    let (mAPC0, f5) = hcat(a, mAP0, mc)
    if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok { ret mem.Exhausted }
    let (mf0, g0) = fit_model(a, mA, dv, off)
    let (mf1, g1) = fit_model(a, mAd, dv, off)
    let (mf2, g2) = fit_model(a, mAC0, dv, off)
    let (mf3, g3) = fit_model(a, mAPC0, dv, off)
    let (mf4, g4) = fit_model(a, mAP0, dv, off)
    if g0 != ok || g1 != ok || g2 != ok || g3 != ok || g4 != ok { ret mem.Exhausted }
    let na4 = 4usize * na
    let np4 = 4usize * np
    let nc4 = 4usize * nc
    var nd = 2usize
    if parm >= 4usize { nd = 1usize }
    out[0usize] = p0
    out[1usize] = c0
    out[2usize] = f64(na)
    out[3usize] = f64(np)
    out[4usize] = f64(nc)
    out[5usize] = f64(nd)
    let oA = 6usize
    let oP = oA + na4
    let oC = oP + np4
    let oD = oC + nc4
    let oM = oD + 3usize * nd
    // effects are written (value, est, lower, upper); ci_exp writes triples, so go through a scratch
    let (tmp, te) = mem.alloc[f64](a, 3usize * (na + np + nc + 3usize))
    if te != ok { ret mem.Exhausted }
    var fa: Fit = mf0
    var fp: Fit = mf0
    var fc: Fit = mf0
    var ca: Mat = mA
    var cp: Mat = mA
    var cc: Mat = mA
    if parm < 4usize {
        let (xd0, h1) = hcat(a, ma1, mdp)
        let (xd1, h2) = hcat(a, xd0, mpr)
        let (xadpc, h3) = hcat(a, xd1, mcr)
        if h1 != ok || h2 != ok || h3 != ok { ret mem.Exhausted }
        let (fdr, h4) = fit_model(a, xadpc, dv, off)
        if h4 != ok { ret mem.Exhausted }
        // the drift rows: the coefficient of I(P - p0) in the ADPC form, then in A + drift
        let (dr1, h6) = mat_new(a, 1usize, xadpc.c)
        let (dr2, h7) = mat_new(a, 1usize, mAd.c)
        if h6 != ok || h7 != ok { ret mem.Exhausted }
        dr1.v[1usize + wa] = 1.0f64
        dr2.v[1usize + wa] = 1.0f64
        ci_exp(fdr, dr1, z, tmp, 0usize, 1.0f64)
        ci_exp(mf1, dr2, z, tmp, 3usize, 1.0f64)
        var q = 0usize
        while q < 6usize {
            out[oD + q] = tmp[q]
            q += 1usize
        }
        var xf = xadpc
        var s1 = 1usize + wa
        var s2 = 0usize
        var ctrP: Mat = mpr
        var ctrC: Mat = mcr
        if parm == 0usize {
            // ACP: [MA1 | MPr | dC MCr]
            let (b1, k1) = hcat(a, ma1, mpr)
            let (b2, k2) = hcat(a, mdc, mcr)
            let (b3, k3) = hcat(a, b1, b2)
            if k1 != ok || k2 != ok || k3 != ok { ret mem.Exhausted }
            xf = b3
            ctrP = mpr
            ctrC = b2
            s1 = 1usize + wa
            s2 = 1usize + wa + mpr.c
        }
        if parm == 1usize {
            // APC: [MA1 | dP MPr | MCr]
            let (b1, k1) = hcat(a, mdp, mpr)
            if k1 != ok { ret mem.Exhausted }
            ctrP = b1
            ctrC = mcr
            s1 = 1usize + wa
            s2 = 1usize + wa + b1.c
        }
        if parm == 2usize {
            // ADCP: [MA1 | dC | MPr | MCr]
            let (b1, k1) = hcat(a, ma1, mdc)
            let (b2, k2) = hcat(a, b1, mpr)
            let (b3, k3) = hcat(a, b2, mcr)
            if k1 != ok || k2 != ok || k3 != ok { ret mem.Exhausted }
            xf = b3
            s1 = 2usize + wa
            s2 = 2usize + wa + mpr.c
        }
        if parm == 3usize {
            s1 = 2usize + wa
            s2 = 2usize + wa + mpr.c
        }
        let (mf, k4) = fit_model(a, xf, dv, off)
        if k4 != ok { ret mem.Exhausted }
        let kk = xf.c
        let (pa, k5) = place(a, ma1, apos, na, 0usize, kk)
        let (pp, k6) = place(a, ctrP, ppos, np, s1, kk)
        let (pc, k7) = place(a, ctrC, cpos, nc, s2, kk)
        if k5 != ok || k6 != ok || k7 != ok { ret mem.Exhausted }
        fa = mf
        fp = mf
        fc = mf
        ca = pa
        cp = pp
        cc = pc
    } else {
        let (adc, h1) = hcat(a, ma1, mdc)
        let (adp, h2) = hcat(a, ma1, mdp)
        let (xP0, h3) = hcat(a, one, mdp)
        let (xP, h4) = hcat(a, xP0, mpr)
        let (xC0, h5) = hcat(a, one, mdc)
        let (xC, h6) = hcat(a, xC0, mcr)
        let (lP, h7) = hcat(a, mdp, mpr)
        let (lC, h8) = hcat(a, mdc, mcr)
        if h1 != ok || h2 != ok || h3 != ok || h4 != ok || h5 != ok || h6 != ok || h7 != ok || h8 != ok { ret mem.Exhausted }
        let (fadc, g5) = fit_model(a, adc, dv, off)
        if g5 != ok { ret mem.Exhausted }
        let (dr, h9) = mat_new(a, 1usize, adc.c)
        if h9 != ok { ret mem.Exhausted }
        dr.v[1usize + wa] = 1.0f64
        // the drift of a sequential parametrization is ci.exp's default level, whatever alpha is
        ci_exp(fadc, dr, dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false), tmp, 0usize, 1.0f64)
        out[oD] = tmp[0usize]
        out[oD + 1usize] = tmp[1usize]
        out[oD + 2usize] = tmp[2usize]
        if parm == 5usize {
            // Ad-C-P
            let (rc, k1) = fit_model(a, xC, dv, fadc.eta)
            let (rp, k2) = fit_model(a, xP, dv, fadc.eta)
            if k1 != ok || k2 != ok { ret mem.Exhausted }
            let (pa, k3) = place(a, ma1, apos, na, 0usize, adc.c)
            let (pp, k4) = place(a, xP, ppos, np, 0usize, xP.c)
            let (pc, k5) = place(a, xC, cpos, nc, 0usize, xC.c)
            if k3 != ok || k4 != ok || k5 != ok { ret mem.Exhausted }
            fa = fadc
            fp = rp
            fc = rc
            ca = pa
            cp = pp
            cc = pc
        }
        if parm == 4usize {
            // Ad-P-C
            let (fadp, k0) = fit_model(a, adp, dv, off)
            if k0 != ok { ret mem.Exhausted }
            let (rp, k1) = fit_model(a, xP, dv, fadp.eta)
            if k1 != ok { ret mem.Exhausted }
            let (rc, k2) = fit_model(a, xC, dv, rp.eta)
            if k2 != ok { ret mem.Exhausted }
            let (pa, k3) = place(a, ma1, apos, na, 0usize, adp.c)
            let (pp, k4) = place(a, xP, ppos, np, 0usize, xP.c)
            let (pc, k5) = place(a, xC, cpos, nc, 0usize, xC.c)
            if k3 != ok || k4 != ok || k5 != ok { ret mem.Exhausted }
            fa = fadp
            fp = rp
            fc = rc
            ca = pa
            cp = pp
            cc = pc
        }
        if parm == 6usize {
            // AC-P
            let (ac, k0) = hcat(a, ma1, lC)
            if k0 != ok { ret mem.Exhausted }
            let (fac, k1) = fit_model(a, ac, dv, off)
            if k1 != ok { ret mem.Exhausted }
            let (rp, k2) = fit_model(a, xP, dv, fac.eta)
            if k2 != ok { ret mem.Exhausted }
            let (pa, k3) = place(a, ma1, apos, na, 0usize, ac.c)
            let (pc, k4) = place(a, lC, cpos, nc, 1usize + wa, ac.c)
            let (pp, k5) = place(a, xP, ppos, np, 0usize, xP.c)
            if k3 != ok || k4 != ok || k5 != ok { ret mem.Exhausted }
            fa = fac
            fc = fac
            fp = rp
            ca = pa
            cc = pc
            cp = pp
        }
        if parm == 7usize {
            // AP-C
            let (ap, k0) = hcat(a, ma1, lP)
            if k0 != ok { ret mem.Exhausted }
            let (fap, k1) = fit_model(a, ap, dv, off)
            if k1 != ok { ret mem.Exhausted }
            let (rc, k2) = fit_model(a, xC, dv, fap.eta)
            if k2 != ok { ret mem.Exhausted }
            let (pa, k3) = place(a, ma1, apos, na, 0usize, ap.c)
            let (pp, k4) = place(a, lP, ppos, np, 1usize + wa, ap.c)
            let (pc, k5) = place(a, xC, cpos, nc, 0usize, xC.c)
            if k3 != ok || k4 != ok || k5 != ok { ret mem.Exhausted }
            fa = fap
            fp = fap
            fc = rc
            ca = pa
            cp = pp
            cc = pc
        }
    }
    ci_exp(fa, ca, z, tmp, 0usize, scale)
    var r = 0usize
    while r < na {
        out[oA + 4usize * r] = ua[r]
        out[oA + 4usize * r + 1usize] = tmp[3usize * r]
        out[oA + 4usize * r + 2usize] = tmp[3usize * r + 1usize]
        out[oA + 4usize * r + 3usize] = tmp[3usize * r + 2usize]
        r += 1usize
    }
    ci_exp(fp, cp, z, tmp, 0usize, 1.0f64)
    r = 0usize
    while r < np {
        out[oP + 4usize * r] = up[r]
        out[oP + 4usize * r + 1usize] = tmp[3usize * r]
        out[oP + 4usize * r + 2usize] = tmp[3usize * r + 1usize]
        out[oP + 4usize * r + 3usize] = tmp[3usize * r + 2usize]
        r += 1usize
    }
    ci_exp(fc, cc, z, tmp, 0usize, 1.0f64)
    r = 0usize
    while r < nc {
        out[oC + 4usize * r] = uc[r]
        out[oC + 4usize * r + 1usize] = tmp[3usize * r]
        out[oC + 4usize * r + 2usize] = tmp[3usize * r + 1usize]
        out[oC + 4usize * r + 3usize] = tmp[3usize * r + 2usize]
        r += 1usize
    }
    // the model table, rows A, A-drift, A-C, APC, A-P, A-drift
    table_row(out, oM, mf0, mf0, n, false)
    table_row(out, oM + 5usize, mf1, mf0, n, true)
    table_row(out, oM + 10usize, mf2, mf1, n, true)
    table_row(out, oM + 15usize, mf3, mf2, n, true)
    table_row(out, oM + 20usize, mf4, mf3, n, true)
    table_row(out, oM + 25usize, mf1, mf4, n, true)
    ret ok
}

// residual df, residual deviance, AIC and, against the model before, the absolute differences of rank and deviance
fn table_row(out: []f64, o: usize, f: Fit, prev: Fit, n: usize, test: bool) {
    out[o] = f64(n) - f64(f.rank)
    out[o + 1usize] = f.dev
    out[o + 2usize] = f.aic
    out[o + 3usize] = 0.0f64
    out[o + 4usize] = 0.0f64
    if test {
        var df = f64(f.rank) - f64(prev.rank)
        if df < 0.0f64 { df = 0.0f64 - df }
        var dd = f.dev - prev.dev
        if dd < 0.0f64 { dd = 0.0f64 - dd }
        out[o + 3usize] = df
        out[o + 4usize] = dd
    }
}
