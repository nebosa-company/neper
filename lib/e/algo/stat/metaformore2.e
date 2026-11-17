// R metafor: permutest (the exact and the random permutation test, with R's set.seed and sample draws), regtest (the regression test of funnel plot asymmetry on any rma.uni model, with
// the sei, vi, ni, ninv, sqrtni and sqrtninv predictors, as an rma or an lm), trimfill (the L0, R0 and Q0 estimators with the final refit), fsn (the Rosenthal, Orwin, Rosenberg and
// binomial fail-safe numbers) and profile (the likelihood at given values of tau2).
//
// Not here: fsn General and Fisher (they draw from rnorm and search with extendInt), permutest's permutation confidence intervals.

use e.math
use e.mem
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.special as sp
use e.algo.rand.r as rr
use e.algo.stat.metaforrma as mr
use e.algo.stat.metaformore as mm
use e.algo.stat.metaforfit as mf

const X0: usize = 136usize
const STRIDE: usize = 16usize

fn qsort_idx(key: []const f64, n: usize, idx: []usize) {
    var i = 0usize
    while i < n {
        var j = i
        while j > 0usize && key[idx[j - 1usize]] > key[i] {
            idx[j] = idx[j - 1usize]
            j -= 1usize
        }
        idx[j] = i
        i += 1usize
    }
}

// the number of distinct row permutations of the design: multinomial coefficient over the groups of identical rows, as a double
fn exact_iter(x: []const f64, k: usize, p: usize, cls: []usize) -> f64 {
    var ncls = 0usize
    var i = 0usize
    while i < k {
        var found = false
        var j = 0usize
        while j < i && !found {
            var same = true
            var a = 0usize
            while a < p {
                if x[i * p + a] != x[j * p + a] { same = false }
                a += 1usize
            }
            if same {
                found = true
                cls[i] = cls[j]
            }
            j += 1usize
        }
        if !found {
            cls[i] = ncls
            ncls += 1usize
        }
        i += 1usize
    }
    // k! / prod(n_c!) with the largest group's factorial cancelled as R does it
    var best = 0usize
    var bestn = 0usize
    var c = 0usize
    while c < ncls {
        var n = 0usize
        i = 0usize
        while i < k {
            if cls[i] == c { n += 1usize }
            i += 1usize
        }
        if n > bestn {
            bestn = n
            best = c
        }
        c += 1usize
    }
    var num = 1.0f64
    var t = bestn + 1usize
    while t <= k {
        num = num * f64(t)
        t += 1usize
    }
    var den = 1.0f64
    c = 0usize
    while c < ncls {
        if c != best {
            var n = 0usize
            i = 0usize
            while i < k {
                if cls[i] == c { n += 1usize }
                i += 1usize
            }
            var f = 2usize
            while f <= n {
                den = den * f64(f)
                f += 1usize
            }
        }
        c += 1usize
    }
    ret math.round[f64](num / den)
}

// the next lexicographic permutation of v (length n) with repeats; false at the last one
fn next_perm(v: []usize, n: usize) -> bool {
    if n < 2usize { ret false }
    var i = n - 1usize
    while i > 0usize && v[i - 1usize] >= v[i] { i -= 1usize }
    if i == 0usize { ret false }
    var j = n - 1usize
    while v[j] <= v[i - 1usize] { j -= 1usize }
    let t = v[i - 1usize]
    v[i - 1usize] = v[j]
    v[j] = t
    var lo = i
    var hi = n - 1usize
    while lo < hi {
        let u = v[lo]
        v[lo] = v[hi]
        v[hi] = u
        lo += 1usize
        hi -= 1usize
    }
    ret true
}

// permutest on the model: out[X0 + a] the p-value of coefficient a (two-sided, on the test statistic), out[X0 + 8] the p-value of the omnibus test, out[X0 + 9] the number of iterations;
// exact is 0 or 1, iter the number of random permutations, seed R's set.seed value
fn permutest(m: *mm.Mod, exact: bool, iter: f64, seed: i64) {
    let k = m.k
    let p = m.p
    let o = m.out
    let a = m.a
    let comptol = math.sqrt[f64](2.220446049250313e-16f64)
    let (cls, ce) = mem.alloc[usize](a, k)
    if ce != ok { ret }
    var iters = 0.0f64
    let intonly = p == 1usize && m.c.intercept
    var sorted_x: []f64 = zero
    var order: []usize = zero
    if intonly {
        iters = math.pow[f64](2.0f64, f64(k))
    } else {
        // the rows of X sorted by all columns, as order() on the data frame does
        let (ord, oe) = mem.alloc[usize](a, k)
        if oe != ok { ret }
        let (sx, se) = mem.alloc[f64](a, k * p)
        if se != ok { ret }
        var i = 0usize
        while i < k {
            var j = i
            while j > 0usize && row_less(m.x, i, ord[j - 1usize], p) {
                ord[j] = ord[j - 1usize]
                j -= 1usize
            }
            ord[j] = i
            i += 1usize
        }
        i = 0usize
        while i < k {
            var c = 0usize
            while c < p {
                sx[i * p + c] = m.x[ord[i] * p + c]
                c += 1usize
            }
            i += 1usize
        }
        sorted_x = sx
        order = ord
        iters = exact_iter(sx, k, p, cls)
    }
    var is_exact = exact
    var niter = iter
    if exact || iters <= iter {
        is_exact = true
        niter = iters
    }
    let n = usize(niter)
    let (zp, e1) = mem.alloc[f64](a, n * p)
    let (qp, e2) = mem.alloc[f64](a, n)
    let (ys, e3) = mem.alloc[f64](a, k)
    let (xs, e4) = mem.alloc[f64](a, k * p)
    let (perm, e5) = mem.alloc[usize](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret }
    var rng: rr.Rng = zero
    if !is_exact { rr.seed(&rng, seed) }
    var c = m.c
    c.skipr2 = true
    var btt0 = 0usize
    if m.c.intercept && p > 1usize { btt0 = 1usize }
    // the class vector of the sorted rows, the first lexicographic permutation of it
    var i = 0usize
    if is_exact && !intonly {
        // classes in order of first appearance among the sorted rows
        let (cls2, c2e) = mem.alloc[usize](a, k)
        if c2e != ok { ret }
        let _ = exact_iter(sorted_x, k, p, cls2)
        i = 0usize
        while i < k {
            perm[i] = cls2[i]
            i += 1usize
        }
        // the representative row of each class
        i = 0usize
        // sort perm ascending so next_perm visits every arrangement
        var s1 = 1usize
        while s1 < k {
            let t = perm[s1]
            var s2 = s1
            while s2 > 0usize && perm[s2 - 1usize] > t {
                perm[s2] = perm[s2 - 1usize]
                s2 -= 1usize
            }
            perm[s2] = t
            s1 += 1usize
        }
        let (cls3, c3e) = mem.alloc[usize](a, k)
        if c3e != ok { ret }
        let _ = exact_iter(sorted_x, k, p, cls3)
        // rep[class] = first sorted row of that class
        let (rep, re) = mem.alloc[usize](a, k)
        if re != ok { ret }
        i = k
        while i > 0usize {
            i -= 1usize
            rep[cls3[i]] = i
        }
        var it = 0usize
        var more = true
        while more && it < n {
            var r = 0usize
            while r < k {
                var cc = 0usize
                while cc < p {
                    xs[r * p + cc] = sorted_x[rep[perm[r]] * p + cc]
                    cc += 1usize
                }
                r += 1usize
            }
            mf.fit(m.ws, m.y, m.v, xs, k, p, &c, m.tmp)
            record(m, zp, qp, it)
            it += 1usize
            more = next_perm(perm, k)
        }
    } else {
        var it = 0usize
        while it < n {
            if intonly {
                if is_exact {
                    var r = 0usize
                    while r < k {
                        // expand.grid(c(1, -1), ...): the first factor varies fastest
                        var sg = 1.0f64
                        var dv = it
                        var q = 0usize
                        while q < r {
                            dv = dv / 2usize
                            q += 1usize
                        }
                        if dv % 2usize == 1usize { sg = 0.0f64 - 1.0f64 }
                        ys[r] = sg * m.y[r]
                        r += 1usize
                    }
                } else {
                    var r = 0usize
                    while r < k {
                        let u = rr.unif_index(&rng, 2.0f64)
                        var sg = 0.0f64 - 1.0f64
                        if u >= 1.0f64 { sg = 1.0f64 }
                        ys[r] = sg * m.y[r]
                        r += 1usize
                    }
                }
                mf.fit(m.ws, ys, m.v, m.x, k, p, &c, m.tmp)
            } else {
                let (sm, se) = rr.sample_int(a, &rng, i64(k), i64(k), false)
                if se != ok { ret }
                var r = 0usize
                while r < k {
                    var cc = 0usize
                    while cc < p {
                        xs[r * p + cc] = sorted_x[usize(sm[r] - 1i64) * p + cc]
                        cc += 1usize
                    }
                    r += 1usize
                }
                mf.fit(m.ws, m.y, m.v, xs, k, p, &c, m.tmp)
            }
            record(m, zp, qp, it)
            it += 1usize
        }
    }
    if !is_exact {
        var cc = 0usize
        while cc < p {
            zp[cc] = o[mr.O_Z + cc]
            cc += 1usize
        }
        qp[0usize] = o[mr.O_QM]
    }
    var cc = 0usize
    while cc < p {
        var cnt = 0.0f64
        var tot = 0.0f64
        var r = 0usize
        while r < n {
            let z = zp[r * p + cc]
            if z == z {
                tot += 1.0f64
                if math.abs[f64](z) >= math.abs[f64](o[mr.O_Z + cc]) - comptol { cnt += 1.0f64 }
            }
            r += 1usize
        }
        var pv = cnt / tot
        if pv > 1.0f64 { pv = 1.0f64 }
        o[X0 + cc] = pv
        cc += 1usize
    }
    var cnt = 0.0f64
    var tot = 0.0f64
    var r = 0usize
    while r < n {
        let q = qp[r]
        if q == q {
            tot += 1.0f64
            if q >= o[mr.O_QM] - comptol { cnt += 1.0f64 }
        }
        r += 1usize
    }
    o[X0 + 8usize] = cnt / tot
    o[X0 + 9usize] = niter
}

fn row_less(x: []const f64, i: usize, j: usize, p: usize) -> bool {
    var c = 0usize
    while c < p {
        if x[i * p + c] < x[j * p + c] { ret true }
        if x[i * p + c] > x[j * p + c] { ret false }
        c += 1usize
    }
    ret false
}

fn record(m: *mm.Mod, zp: []f64, qp: []f64, it: usize) {
    let p = m.p
    var cc = 0usize
    while cc < p {
        zp[it * p + cc] = m.tmp[mr.O_Z + cc]
        cc += 1usize
    }
    qp[it] = m.tmp[mr.O_QM]
}

// -------------------------------------------------------------------------------------------------------------------------------
// regtest

// predictor 0 sei, 1 vi, 2 ni, 3 ninv, 4 sqrtni, 5 sqrtninv; model 0 rma, 1 lm; out[X0 .. X0 + 5] = zval, pval, ddf, est, ci.lb, ci.ub of the added coefficient and the intercept
fn regtest(m: *mm.Mod, predictor: usize, model: usize, ni: []const f64) {
    let k = m.k
    let p = m.p
    let a = m.a
    let o = m.out
    let (xn, e1) = mem.alloc[f64](a, k * (p + 1usize))
    if e1 != ok { ret }
    var i = 0usize
    while i < k {
        var c = 0usize
        while c < p {
            xn[i * (p + 1usize) + c] = m.x[i * p + c]
            c += 1usize
        }
        var pr = 0.0f64
        if predictor == 0usize { pr = math.sqrt[f64](m.v[i]) }
        if predictor == 1usize { pr = m.v[i] }
        if predictor == 2usize { pr = ni[i] }
        if predictor == 3usize { pr = 1.0f64 / ni[i] }
        if predictor == 4usize { pr = math.sqrt[f64](ni[i]) }
        if predictor == 5usize { pr = 1.0f64 / math.sqrt[f64](ni[i]) }
        xn[i * (p + 1usize) + p] = pr
        i += 1usize
    }
    let alpha = 1.0f64 - m.c.level
    var zval = mr.nan()
    var pval = mr.nan()
    var ddf = mr.nan()
    var est = mr.nan()
    var lb = mr.nan()
    var ub = mr.nan()
    let showest = predictor != 2usize && predictor != 4usize && p == 1usize && m.c.intercept
    if model == 0usize {
        var c = m.c
        c.skipr2 = true
        c.intercept = false
        mf.fit(m.ws, m.y, m.v, xn, k, p + 1usize, &c, m.tmp)
        zval = m.tmp[mr.O_Z + p]
        pval = m.tmp[mr.O_P + p]
        ddf = m.tmp[mr.O_DDF]
        if showest {
            est = m.tmp[mr.O_BETA]
            lb = m.tmp[mr.O_CILB]
            ub = m.tmp[mr.O_CIUB]
        }
    } else {
        // the weighted lm with weights 1 / vi: t tests on k - p - 1 degrees of freedom
        let q = p + 1usize
        let (w, e2) = mem.alloc[f64](a, k)
        if e2 != ok { ret }
        i = 0usize
        while i < k {
            w[i] = 1.0f64 / m.v[i]
            i += 1usize
        }
        if !mr.xwx_inv(m.ws, xn, w, k, q) { ret }
        mr.beta_of(m.ws, xn, w, m.y, k, q)
        let rss = mr.rss_of(m.ws, m.y, xn, w, m.ws.b, k, q)
        ddf = f64(k - q)
        let s2 = rss / ddf
        let se = math.sqrt[f64](s2 * m.ws.s[p * q + p])
        zval = m.ws.b[p] / se
        pval = 2.0f64 * nb.pt(math.abs[f64](zval), ddf, false, false)
        if showest {
            let se0 = math.sqrt[f64](s2 * m.ws.s[0usize])
            est = m.ws.b[0usize]
            let tc = nb.qt(alpha / 2.0f64, ddf, false, false)
            lb = est - tc * se0
            ub = est + tc * se0
        }
    }
    o[X0] = zval
    o[X0 + 1usize] = pval
    o[X0 + 2usize] = ddf
    o[X0 + 3usize] = est
    o[X0 + 4usize] = lb
    o[X0 + 5usize] = ub
}

// -------------------------------------------------------------------------------------------------------------------------------
// trimfill

// rank(x, ties.method = "first") of the first n values into r (1-based as doubles)
fn rank_first(x: []const f64, n: usize, r: []f64) {
    var i = 0usize
    while i < n {
        var c = 1.0f64
        var j = 0usize
        while j < n {
            if x[j] < x[i] || (x[j] == x[i] && j < i) { c += 1.0f64 }
            j += 1usize
        }
        r[i] = c
        i += 1usize
    }
}

fn sgn(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

// the intercept of an rma.uni fit of (y, v) with the model's method and weighting (the test z, tau2 free): the pooled estimate
fn pooled(m: *mm.Mod, y: []const f64, v: []const f64, n: usize, tmp: []f64) -> f64 {
    var c = mf.default_ctl()
    c.method = m.c.method
    c.weighted = m.c.weighted
    c.skipr2 = true
    let (ones, e) = mem.alloc[f64](m.a, n)
    if e != ok { ret mr.nan() }
    var i = 0usize
    while i < n {
        ones[i] = 1.0f64
        i += 1usize
    }
    mf.fit(m.ws, y, v, ones, n, 1usize, &c, tmp)
    ret tmp[mr.O_BETA]
}

// trimfill(x, side, estimator) on an intercept-only model: estimator 0 L0, 1 R0, 2 Q0; side -1 automatic, 0 left, 1 right
// out holds the fit of the final model (the filled data when k0 > 0, else the original); out[X0 .. X0 + 3] = k0, se.k0, p.k0, side (0 left, 1 right)
fn trimfill(m: *mm.Mod, estimator: usize, side0: i64) {
    let k = m.k
    let a = m.a
    let o = m.out
    let kf = f64(k)
    var side = side0
    if side0 < 0i64 {
        let (xs, e) = mem.alloc[f64](a, k * 2usize)
        if e != ok { ret }
        var i = 0usize
        while i < k {
            xs[i * 2usize] = 1.0f64
            xs[i * 2usize + 1usize] = math.sqrt[f64](m.v[i])
            i += 1usize
        }
        var c = mf.default_ctl()
        c.method = m.c.method
        c.weighted = m.c.weighted
        c.skipr2 = true
        c.intercept = false
        mf.fit(m.ws, m.y, m.v, xs, k, 2usize, &c, m.tmp)
        if m.tmp[mr.O_BETA + 1usize] < 0.0f64 { side = 1i64 } else { side = 0i64 }
    }
    let (ys0, e1) = mem.alloc[f64](a, k)
    let (vs0, e2) = mem.alloc[f64](a, k)
    let (idx, e3) = mem.alloc[usize](a, k)
    let (ysrt, e4) = mem.alloc[f64](a, k)
    let (vsrt, e5) = mem.alloc[f64](a, k)
    let (yc, e6) = mem.alloc[f64](a, k)
    let (rk, e7) = mem.alloc[f64](a, k)
    let (absy, e8) = mem.alloc[f64](a, k)
    let (yrs, e9) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret }
    var i = 0usize
    while i < k {
        ys0[i] = m.y[i]
        if side == 1i64 { ys0[i] = 0.0f64 - m.y[i] }
        vs0[i] = m.v[i]
        i += 1usize
    }
    qsort_idx(ys0, k, idx)
    i = 0usize
    while i < k {
        ysrt[i] = ys0[idx[i]]
        vsrt[i] = vs0[idx[i]]
        i += 1usize
    }
    var k0 = 0.0f64
    var k0sav = 0.0f64 - 1.0f64
    var sek0 = 0.0f64
    var beta = 0.0f64
    var iter = 0usize
    while math.abs[f64](k0 - k0sav) > 0.0f64 {
        k0sav = k0
        iter += 1usize
        if iter > 100usize { ret }
        let nt = k - usize(k0)
        beta = pooled(m, ysrt[0usize..nt], vsrt[0usize..nt], nt, m.tmp)
        i = 0usize
        while i < k {
            yc[i] = ysrt[i] - beta
            absy[i] = math.abs[f64](yc[i])
            i += 1usize
        }
        rank_first(absy, k, rk)
        i = 0usize
        while i < k {
            yrs[i] = sgn(yc[i]) * rk[i]
            i += 1usize
        }
        var sr = 0.0f64
        i = 0usize
        while i < k {
            if yrs[i] > 0.0f64 { sr += yrs[i] }
            i += 1usize
        }
        var k0n = 0.0f64
        if estimator == 1usize {
            var mx = 0.0f64 - 1.0f64 / 0.0f64
            i = 0usize
            while i < k {
                if yrs[i] < 0.0f64 && 0.0f64 - yrs[i] > mx { mx = 0.0f64 - yrs[i] }
                i += 1usize
            }
            k0n = (kf - mx) - 1.0f64
            sek0 = math.sqrt[f64](2.0f64 * mr.max0(k0n) + 2.0f64)
        }
        if estimator == 0usize {
            k0n = (4.0f64 * sr - kf * (kf + 1.0f64)) / (2.0f64 * kf - 1.0f64)
            let vs = 1.0f64 / 24.0f64 * (kf * (kf + 1.0f64) * (2.0f64 * kf + 1.0f64) + 10.0f64 * k0n * k0n * k0n + 27.0f64 * k0n * k0n + 17.0f64 * k0n - 18.0f64 * kf * k0n * k0n - 18.0f64 * kf * k0n + 6.0f64 * kf * kf * k0n)
            sek0 = 4.0f64 * math.sqrt[f64](vs) / (2.0f64 * kf - 1.0f64)
        }
        if estimator == 2usize {
            k0n = kf - 0.5f64 - math.sqrt[f64](2.0f64 * kf * kf - 4.0f64 * sr + 0.25f64)
            let vs = 1.0f64 / 24.0f64 * (kf * (kf + 1.0f64) * (2.0f64 * kf + 1.0f64) + 10.0f64 * k0n * k0n * k0n + 27.0f64 * k0n * k0n + 17.0f64 * k0n - 18.0f64 * kf * k0n * k0n - 18.0f64 * kf * k0n + 6.0f64 * kf * kf * k0n)
            sek0 = 2.0f64 * math.sqrt[f64](vs) / math.sqrt[f64]((kf - 0.5f64) * (kf - 0.5f64) - k0n * (2.0f64 * kf - k0n - 1.0f64))
        }
        k0 = mr.max0(math.round[f64](k0n))
        sek0 = mr.max0(sek0)
        if k0 - k0 != 0.0f64 { ret }
    }
    let k0u = usize(k0)
    if k0u > 0usize {
        let (yf, ef) = mem.alloc[f64](a, k + k0u)
        let (vf, ef2) = mem.alloc[f64](a, k + k0u)
        if ef != ok || ef2 != ok { ret }
        i = 0usize
        while i < k {
            yf[i] = m.y[i]
            vf[i] = m.v[i]
            i += 1usize
        }
        var j = 0usize
        while j < k0u {
            var yc2 = yc[k - k0u + j] - beta
            if side == 1i64 { yc2 = 0.0f64 - (yc[k - k0u + j] - beta) }
            yf[k + j] = 0.0f64 - 1.0f64 * yc2
            vf[k + j] = vsrt[k - k0u + j]
            j += 1usize
        }
        var c = mf.default_ctl()
        c.method = m.c.method
        c.weighted = m.c.weighted
        let (ones, oe) = mem.alloc[f64](a, k + k0u)
        if oe != ok { ret }
        i = 0usize
        while i < k + k0u {
            ones[i] = 1.0f64
            i += 1usize
        }
        mf.fit(m.ws, yf, vf, ones, k + k0u, 1usize, &c, o)
    }
    o[X0] = k0
    o[X0 + 1usize] = sek0
    var pk0 = mr.nan()
    if estimator == 1usize { pk0 = math.pow[f64](0.5f64, k0 + 1.0f64) }
    o[X0 + 2usize] = pk0
    o[X0 + 3usize] = f64(side)
}

// -------------------------------------------------------------------------------------------------------------------------------
// fsn

// the exact two-sided binomial test p-value with p = 0.5 (binom.test): the sum of the probabilities no larger than that of x, within a relative 1e-7
fn binom_p(x: f64, n: f64) -> f64 {
    let lc = sp.lgamma(n + 1.0f64)
    let ld = lc - sp.lgamma(x + 1.0f64) - sp.lgamma(n - x + 1.0f64) - n * math.log[f64](2.0f64)
    let dx = math.exp[f64](ld)
    let relerr = 1.0f64 + 1.0e-7f64
    var s = 0.0f64
    var i = 0.0f64
    while i <= n {
        let li = lc - sp.lgamma(i + 1.0f64) - sp.lgamma(n - i + 1.0f64) - n * math.log[f64](2.0f64)
        let di = math.exp[f64](li)
        if di <= dx * relerr { s += di }
        i += 1.0f64
    }
    if s > 1.0f64 { s = 1.0f64 }
    ret s
}

fn rnd_fsn(x: f64) -> f64 {
    if x - x == 0.0f64 && math.abs[f64](x - math.round[f64](x)) >= math.sqrt[f64](2.220446049250313e-16f64) { ret math.ceil[f64](x) }
    ret math.round[f64](x)
}

// fsn on (y, v): type 0 Rosenthal (Stouffer), 1 Orwin, 2 Rosenberg, 3 Binomial; tgt is NaN for the default; out[X0] the fail-safe number, out[X0 + 1] the p-value, out[X0 + 2] the tgt
fn fsn(y: []const f64, v: []const f64, k: usize, kind: usize, alpha: f64, tgt0: f64, o: []f64) {
    let kf = f64(k)
    var fsnum = 0.0f64
    var pval = mr.nan()
    var tgt = tgt0
    if kind == 0usize {
        var sz = 0.0f64
        var i = 0usize
        while i < k {
            sz += y[i] / math.sqrt[f64](v[i])
            i += 1usize
        }
        let zavg = math.abs[f64](sz / math.sqrt[f64](kf))
        pval = dist.pnorm(zavg, 0.0f64, 1.0f64, false, false)
        let q = dist.qnorm(alpha, 0.0f64, 1.0f64, false, false)
        fsnum = mr.max0(kf * (zavg / q) * (zavg / q) - kf)
        fsnum = rnd_fsn(fsnum)
        tgt = mr.nan()
    }
    if kind == 1usize || kind == 2usize {
        var sw = 0.0f64
        var swy = 0.0f64
        var i = 0usize
        while i < k {
            sw += 1.0f64 / v[i]
            swy += y[i] / v[i]
            i += 1usize
        }
        let est = swy / sw
        if kind == 1usize {
            if tgt != tgt { tgt = est / 2.0f64 }
            if tgt == 0.0f64 {
                fsnum = 1.0f64 / 0.0f64
            } else {
                if sgn(tgt) != sgn(est) { tgt = 0.0f64 - tgt }
                fsnum = mr.max0(kf * (est - tgt) / tgt)
            }
            fsnum = rnd_fsn(fsnum)
        } else {
            let zval = est / math.sqrt[f64](1.0f64 / sw)
            pval = 2.0f64 * dist.pnorm(math.abs[f64](zval), 0.0f64, 1.0f64, false, false)
            var mean_inv = 0.0f64
            i = 0usize
            while i < k {
                mean_inv += 1.0f64 / v[i]
                i += 1usize
            }
            let vt = 1.0f64 / (mean_inv / kf)
            let qa = dist.qnorm(alpha / 2.0f64, 0.0f64, 1.0f64, false, false)
            fsnum = mr.max0(((swy / qa) * (swy / qa) - sw) * vt)
            fsnum = rnd_fsn(fsnum)
            tgt = mr.nan()
        }
    }
    if kind == 3usize {
        var kpos = 0.0f64
        var i = 0usize
        while i < k {
            if y[i] > 0.0f64 { kpos += 1.0f64 }
            i += 1usize
        }
        pval = binom_p(kpos, kf)
        if pval >= alpha {
            fsnum = 0.0f64
        } else {
            var pnew = pval
            fsnum = 0.0f64
            while pnew < alpha {
                fsnum += 2.0f64
                pnew = binom_p(kpos + fsnum / 2.0f64, kf + fsnum)
            }
        }
        fsnum = rnd_fsn(fsnum)
        tgt = mr.nan()
    }
    o[X0] = fsnum
    o[X0 + 1usize] = pval
    o[X0 + 2usize] = tgt
}

// -------------------------------------------------------------------------------------------------------------------------------
// profile: the (restricted) log-likelihood and the coefficients at fixed values of tau2: out[X0 + i * STRIDE + 0..5] = ll, beta[0], ci.lb[0], ci.ub[0], I2, H2
fn profile(m: *mm.Mod, taus: []const f64) {
    var i = 0usize
    while i < taus.len {
        var c = m.c
        c.tau2fix = taus[i]
        c.skipr2 = true
        mf.fit(m.ws, m.y, m.v, m.x, m.k, m.p, &c, m.tmp)
        var ll = m.tmp[mr.O_LLML]
        if m.c.method == 8usize { ll = m.tmp[mr.O_LLREML] }
        let b = X0 + i * STRIDE
        m.out[b] = ll
        m.out[b + 1usize] = m.tmp[mr.O_BETA]
        m.out[b + 2usize] = m.tmp[mr.O_CILB]
        m.out[b + 3usize] = m.tmp[mr.O_CIUB]
        m.out[b + 4usize] = m.tmp[mr.O_I2]
        m.out[b + 5usize] = m.tmp[mr.O_H2]
        i += 1usize
    }
}
