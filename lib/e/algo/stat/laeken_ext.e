// R laeken beyond the weighted statistics of e.algo.stat.laeken: the gender pay gap, weightedRate, eqSS and eqInc, calibWeights (linear, raking
// and logit), the bootstrap variance and percentile / normal / basic intervals of bootVar (boot::boot with strata and clusters, replicates drawn
// from the seeded generator exactly as boot's index.array does), the Pareto tail estimators (thetaHill, thetaISE, thetaLS, thetaMoment, thetaPDC,
// thetaQQ, thetaTM, thetaWML), paretoScale, paretoTail with its replacement and shrinking helpers, fitPareto, minAMSE, and the numbers of
// meanExcessPlot and paretoQPlot.
//
// Not here: breakdown by years, the groups argument of the Pareto functions, several values of p at once, NA handling (na.rm), and the plots.
// laeken has no linearisation variance in this version (only the bootstrap).

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.sort
use e.algo.stat.fdrtool as fd
use e.algo.stat.laeken as lk
use e.algo.stat.pwr as pw
use e.math
use e.math.dist as dist
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// long double stand-in for sum()
fn rsum(v: []const f64) -> f64 {
    var total = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < v.len {
        let x = v[i]
        let t = total + x
        if math.abs[f64](total) >= math.abs[f64](x) { comp += (total - t) + x } else { comp += (x - t) + total }
        total = t
        i += 1usize
    }
    ret total + comp
}

// R's mean(): the sum over n, then the mean of the residuals added back; tmp holds v.len values
fn rmean(v: []const f64, tmp: []f64) -> f64 {
    let n = f64(v.len)
    let s = rsum(v) / n
    var i = 0usize
    while i < v.len {
        tmp[i] = v[i] - s
        i += 1usize
    }
    ret s + rsum(tmp[0usize..v.len]) / n
}

// var(): two-pass with the corrected mean
fn rvar(v: []const f64, tmp: []f64) -> f64 {
    let n = v.len
    if n < 2usize { ret nan() }
    let m = rmean(v, tmp)
    var i = 0usize
    while i < n {
        tmp[i] = (v[i] - m) * (v[i] - m)
        i += 1usize
    }
    ret rsum(tmp[0usize..n]) / f64(n - 1usize)
}

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// weighted.mean(x, w): sum(x w) / sum(w)
fn wmean(a: *mem.Arena, x: []const f64, w: []const f64) -> f64 {
    let (t, e) = mem.alloc[f64](a, x.len)
    let (t2, e2) = mem.alloc[f64](a, w.len)
    if e != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < x.len {
        t[i] = x[i] * w[i]
        i += 1usize
    }
    ret rsum(t) / rsum(w)
}

// weightedRate(x, w, threshold): the percentage of weight strictly below the threshold
fn weighted_rate(x: []const f64, w: []const f64, threshold: f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        if x[i] < threshold { s += w[i] }
        i += 1usize
    }
    ret s * 100.0f64 / rsum(w)
}

// genderGap(x, gender, method, weights): (male - female) / male of the weighted means (method 0) or medians (1); male[i] is 1 for a man
fn gender_gap(a: *mem.Arena, x: []const f64, male: []const f64, w: []const f64, method: usize) -> f64 {
    var nm = 0usize
    var nf = 0usize
    var i = 0usize
    while i < x.len {
        if male[i] == 1.0f64 { nm += 1usize } else { nf += 1usize }
        i += 1usize
    }
    let (xm, e1) = mem.alloc[f64](a, nm)
    let (wm, e2) = mem.alloc[f64](a, nm)
    let (xf, e3) = mem.alloc[f64](a, nf)
    let (wf, e4) = mem.alloc[f64](a, nf)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan() }
    var km = 0usize
    var kf = 0usize
    i = 0usize
    while i < x.len {
        if male[i] == 1.0f64 {
            xm[km] = x[i]
            wm[km] = w[i]
            km += 1usize
        } else {
            xf[kf] = x[i]
            wf[kf] = w[i]
            kf += 1usize
        }
        i += 1usize
    }
    var vm = 0.0f64
    var vf = 0.0f64
    if method == 0usize {
        vm = wmean(a, xm, wm)
        vf = wmean(a, xf, wf)
    } else {
        vm = lk.weighted_median(a, xm, wm)
        vf = lk.weighted_median(a, xf, wf)
    }
    ret (vm - vf) / vm
}

// eqSS: the equivalised household size of each person, 1 + 0.5 (members aged 14 or more - 1) + 0.3 (members under 14), hid holding the household ids
fn eq_ss(hid: []const f64, age: []const f64, out: []f64) {
    var i = 0usize
    while i < hid.len {
        var n14 = 0.0f64
        var n13 = 0.0f64
        var j = 0usize
        while j < hid.len {
            if hid[j] == hid[i] {
                if age[j] >= 14.0f64 { n14 += 1.0f64 } else { n13 += 1.0f64 }
            }
            j += 1usize
        }
        out[i] = 1.0f64 + 0.5f64 * (n14 - 1.0f64) + 0.3f64 * n13
        i += 1usize
    }
}

// eqInc: (household income + the household's summed personal income) / eqSS. hplus and hminus are nh columns each (column-major, n rows), pplus and pminus
// np columns; missing values count as zero, as rowSums(na.rm = TRUE) and aggregate(na.rm = TRUE) do
fn eq_inc(a: *mem.Arena, hid: []const f64, hplus: []const f64, nhp: usize, hminus: []const f64, nhm: usize, pplus: []const f64, npp: usize, pminus: []const f64, npm: usize, eqss: []const f64, out: []f64) -> err {
    let n = hid.len
    let (hp, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < n {
        var s = 0.0f64
        var j = 0usize
        while j < nhp {
            let v = hplus[j * n + i]
            if v == v { s += v }
            j += 1usize
        }
        j = 0usize
        while j < nhm {
            let v = hminus[j * n + i]
            if v == v { s -= v }
            j += 1usize
        }
        hp[i] = s
        i += 1usize
    }
    i = 0usize
    while i < n {
        var sp = 0.0f64
        var sm = 0.0f64
        var k = 0usize
        while k < n {
            if hid[k] == hid[i] {
                var j = 0usize
                while j < npp {
                    let v = pplus[j * n + k]
                    if v == v { sp += v }
                    j += 1usize
                }
                j = 0usize
                while j < npm {
                    let v = pminus[j * n + k]
                    if v == v { sm += v }
                    j += 1usize
                }
            }
            k += 1usize
        }
        out[i] = (hp[i] + (sp - sm)) / eqss[i]
        i += 1usize
    }
    ret ok
}

// the Moore-Penrose inverse of the m by n column-major x with singular values at or below tol * max dropped (MASS::ginv(x, tol))
fn ginv_tol(a: *mem.Arena, x: []const f64, m: usize, n: usize, rel: f64) -> ([]f64, err) {
    let (s, e) = decomp.svd(a, x, m, n)
    let (out, oe) = mem.alloc[f64](a, n * m)
    if e != ok || oe != ok { ret (out, e) }
    var i = 0usize
    while i < n * m {
        out[i] = 0.0f64
        i += 1usize
    }
    var mx = 0.0f64
    var j = 0usize
    while j < s.k {
        if s.d[j] > mx { mx = s.d[j] }
        j += 1usize
    }
    let tol = rel * mx
    j = 0usize
    while j < s.k {
        if s.d[j] > tol {
            var r = 0usize
            while r < n {
                var c = 0usize
                while c < m {
                    out[c * n + r] += s.v[j * n + r] * s.u[j * m + c] / s.d[j]
                    c += 1usize
                }
                r += 1usize
            }
        }
        j += 1usize
    }
    ret (out, ok)
}

// t(X) %*% w - totals (p values); x is n by p column-major
fn xtw(x: []const f64, n: usize, p: usize, w: []const f64, out: []f64) {
    var j = 0usize
    while j < p {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += x[j * n + i] * w[i]
            i += 1usize
        }
        out[j] = s
        j += 1usize
    }
}

// t(X * w) %*% X, p by p column-major
fn xwx(x: []const f64, n: usize, p: usize, w: []const f64, out: []f64) {
    var j = 0usize
    while j < p {
        var k = 0usize
        while k < p {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += x[j * n + i] * w[i] * x[k * n + i]
                i += 1usize
            }
            out[k * p + j] = s
            k += 1usize
        }
        j += 1usize
    }
}

fn tol_not_reached(a: *mem.Arena, x: []const f64, n: usize, p: usize, w: []const f64, totals: []const f64, tol: f64) -> bool {
    let (cp, e) = mem.alloc[f64](a, p)
    if e != ok { ret false }
    xtw(x, n, p, w, cp)
    var mx = 0.0f64
    var j = 0usize
    while j < p {
        let v = math.abs[f64](cp[j] - totals[j]) / totals[j]
        if v > mx { mx = v }
        j += 1usize
    }
    ret mx >= tol
}

fn get_g(u: f64, b0: f64, b1: f64) -> f64 { ret (b0 * (b1 - 1.0f64) + b1 * (1.0f64 - b0) * u) / (b1 - 1.0f64 + (1.0f64 - b0) * u) }

// calibWeights(X, d, totals, q, method, bounds, maxit, tol): method 0 raking, 1 linear, 2 logit; g receives the n g-weights; answers false when it does not converge
fn calib_weights(a: *mem.Arena, x: []const f64, n: usize, p: usize, d: []const f64, totals: []const f64, q: []const f64, method: usize, b0: f64, b1: f64, maxit: usize, tol: f64, g: []f64) -> bool {
    let eps = 2.220446049250313e-16f64
    let (lam, e1) = mem.alloc[f64](a, p)
    let (phi, e2) = mem.alloc[f64](a, p)
    let (dphi, e3) = mem.alloc[f64](a, p * p)
    let (w, e4) = mem.alloc[f64](a, n)
    let (xl, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret false }
    var j = 0usize
    while j < p {
        lam[j] = 0.0f64
        j += 1usize
    }
    var i = 0usize
    if method == 1usize {
        let (dq, e6) = mem.alloc[f64](a, n)
        if e6 != ok { ret false }
        i = 0usize
        while i < n {
            dq[i] = d[i] * q[i]
            i += 1usize
        }
        xwx(x, n, p, dq, dphi)
        let (gi, eg) = ginv_tol(a, dphi, p, p, eps)
        if eg != ok { ret false }
        xtw(x, n, p, d, phi)
        j = 0usize
        while j < p {
            phi[j] = totals[j] - phi[j]
            j += 1usize
        }
        j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += gi[k * p + j] * phi[k]
                k += 1usize
            }
            lam[j] = s
            j += 1usize
        }
        i = 0usize
        while i < n {
            var s = 0.0f64
            j = 0usize
            while j < p {
                s += x[j * n + i] * lam[j]
                j += 1usize
            }
            g[i] = 1.0f64 + q[i] * s
            i += 1usize
        }
        ret true
    }
    var it = 1usize
    if method == 0usize {
        i = 0usize
        while i < n {
            g[i] = 1.0f64
            w[i] = d[i]
            i += 1usize
        }
        var anyna = false
        while !anyna && tol_not_reached(a, x, n, p, w, totals, tol) && it <= maxit {
            let start = mem.mark(a)
            xtw(x, n, p, w, phi)
            j = 0usize
            while j < p {
                phi[j] = phi[j] - totals[j]
                j += 1usize
            }
            xwx(x, n, p, w, dphi)
            let (gi, eg) = ginv_tol(a, dphi, p, p, eps)
            if eg != ok { ret false }
            j = 0usize
            while j < p {
                var s = 0.0f64
                var k = 0usize
                while k < p {
                    s += gi[k * p + j] * phi[k]
                    k += 1usize
                }
                lam[j] = lam[j] - s
                j += 1usize
            }
            i = 0usize
            while i < n {
                var s = 0.0f64
                j = 0usize
                while j < p {
                    s += x[j * n + i] * lam[j]
                    j += 1usize
                }
                g[i] = math.exp[f64](s * q[i])
                w[i] = g[i] * d[i]
                if g[i] != g[i] { anyna = true }
                i += 1usize
            }
            // lam and g survive the reset; only the temporaries go
            mem.reset(a, start)
            it += 1usize
        }
        if anyna || it > maxit { ret false }
        ret true
    }
    // logit: the bounded raking
    let aa = (b1 - b0) / ((1.0f64 - b0) * (b1 - 1.0f64))
    i = 0usize
    while i < n {
        g[i] = get_g(1.0f64, b0, b1)
        i += 1usize
    }
    let (idx, e7) = mem.alloc[usize](a, n)
    let (x1, e8) = mem.alloc[f64](a, n * p)
    let (d1, e9) = mem.alloc[f64](a, n)
    let (q1, e10) = mem.alloc[f64](a, n)
    let (g1, e11) = mem.alloc[f64](a, n)
    let (tot1, e12) = mem.alloc[f64](a, p)
    let (w1, e13) = mem.alloc[f64](a, n)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok { ret false }
    var m1 = n
    i = 0usize
    while i < n {
        idx[i] = i
        d1[i] = d[i]
        q1[i] = q[i]
        g1[i] = g[i]
        j = 0usize
        while j < p {
            x1[j * n + i] = x[j * n + i]
            j += 1usize
        }
        i += 1usize
    }
    j = 0usize
    while j < p {
        tot1[j] = totals[j]
        j += 1usize
    }
    var anyna = false
    while !anyna {
        i = 0usize
        var oob = false
        while i < n {
            w[i] = g[i] * d[i]
            if g[i] < b0 || g[i] > b1 { oob = true }
            i += 1usize
        }
        if !(tol_not_reached(a, x, n, p, w, totals, tol) || oob) { break }
        if it > maxit { break }
        if oob {
            i = 0usize
            var cnt = 0usize
            while i < n {
                if g[i] < b0 { g[i] = b0 }
                if g[i] > b1 { g[i] = b1 }
                if g[i] > b0 && g[i] < b1 {
                    idx[cnt] = i
                    cnt += 1usize
                }
                i += 1usize
            }
            if cnt > 0usize {
                m1 = cnt
                var r = 0usize
                while r < cnt {
                    let row = idx[r]
                    d1[r] = d[row]
                    q1[r] = q[row]
                    g1[r] = g[row]
                    j = 0usize
                    while j < p {
                        x1[j * cnt + r] = x[j * n + row]
                        j += 1usize
                    }
                    r += 1usize
                }
                if cnt < n {
                    j = 0usize
                    while j < p {
                        var s = 0.0f64
                        i = 0usize
                        while i < n {
                            var inside = false
                            if g[i] > b0 && g[i] < b1 { inside = true }
                            if !inside { s += g[i] * d[i] * x[j * n + i] }
                            i += 1usize
                        }
                        tot1[j] = totals[j] - s
                        j += 1usize
                    }
                }
            }
        }
        var r2 = 0usize
        while r2 < m1 {
            w1[r2] = g1[r2] * d1[r2]
            r2 += 1usize
        }
        xtw(x1[0usize..m1 * p], m1, p, w1[0usize..m1], phi)
        j = 0usize
        while j < p {
            phi[j] = phi[j] - tot1[j]
            j += 1usize
        }
        xwx(x1[0usize..m1 * p], m1, p, w1[0usize..m1], dphi)
        let (gi, eg) = ginv_tol(a, dphi, p, p, eps)
        if eg != ok { ret false }
        j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += gi[k * p + j] * phi[k]
                k += 1usize
            }
            lam[j] = lam[j] - s
            j += 1usize
        }
        r2 = 0usize
        while r2 < m1 {
            var s = 0.0f64
            j = 0usize
            while j < p {
                s += x1[j * m1 + r2] * lam[j]
                j += 1usize
            }
            let u = math.exp[f64](aa * s * q1[r2])
            g1[r2] = get_g(u, b0, b1)
            g[idx[r2]] = g1[r2]
            if g1[r2] != g1[r2] { anyna = true }
            r2 += 1usize
        }
        it += 1usize
    }
    if anyna || it > maxit { ret false }
    ret true
}

// ---- the indicators and their bootstrap ----

fn count_below(x: []const f64, t: f64) -> usize {
    var k = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] < t { k += 1usize }
        i += 1usize
    }
    ret k
}

// indicator kinds: 0 gini, 1 qsr, 2 rmpg, 3 arpr (p), 4 gpg with the mean, 5 gpg with the median
type Spec = struct { kind: usize, p: f64, nlev: usize }

// the statistic and, for each of nlev strata levels (sorted distinct values of stratum), the statistic within the stratum; out has 1 + nlev values.
// arpr and rmpg use the overall threshold within a stratum
fn stat_vec(a: *mem.Arena, sp: Spec, inc: []const f64, w: []const f64, male: []const f64, stratum: []const f64, levels: []const f64, out: []f64) {
    let n = inc.len
    var thr = 0.0f64
    if sp.kind == 3usize { thr = sp.p * lk.weighted_median(a, inc, w) }
    if sp.kind == 2usize { thr = 0.6f64 * lk.weighted_median(a, inc, w) }
    var lv = 0usize
    while lv <= sp.nlev {
        let start = mem.mark(a)
        var cnt = n
        if lv > 0usize {
            cnt = 0usize
            var i = 0usize
            while i < n {
                if stratum[i] == levels[lv - 1usize] { cnt += 1usize }
                i += 1usize
            }
        }
        let (xi, e1) = mem.alloc[f64](a, cnt)
        let (wi, e2) = mem.alloc[f64](a, cnt)
        let (mi, e3) = mem.alloc[f64](a, cnt)
        if e1 != ok || e2 != ok || e3 != ok { ret }
        var k = 0usize
        var i2 = 0usize
        while i2 < n {
            if lv == 0usize || stratum[i2] == levels[lv - 1usize] {
                xi[k] = inc[i2]
                wi[k] = w[i2]
                if male.len > 0usize { mi[k] = male[i2] }
                k += 1usize
            }
            i2 += 1usize
        }
        var v = 0.0f64
        if sp.kind == 0usize { v = lk.gini(a, xi, wi, xi, false) }
        if sp.kind == 1usize { v = lk.qsr(a, xi, wi, xi, false) }
        if sp.kind == 2usize {
            v = nan()
            if count_below(xi, thr) > 0usize { v = lk.rmpg(a, xi, wi, thr) }
        }
        if sp.kind == 3usize { v = lk.arpr(xi, wi, thr) }
        if sp.kind == 4usize { v = gender_gap(a, xi, mi, wi, 0usize) }
        if sp.kind == 5usize { v = gender_gap(a, xi, mi, wi, 1usize) }
        mem.reset(a, start)
        out[lv] = v
        lv += 1usize
    }
}

fn norm_inter_one(ts: []const f64, alpha: f64) -> f64 {
    let rr = ts.len
    let rk = f64(rr + 1usize) * alpha
    let k = usize(math.trunc[f64](rk))
    if k == 0usize { ret ts[0usize] }
    if k >= rr { ret ts[rr - 1usize] }
    if f64(k) == rk { ret ts[k - 1usize] }
    let t1 = dist.qnorm(alpha, 0.0f64, 1.0f64, true, false)
    let t2 = dist.qnorm(f64(k) / f64(rr + 1usize), 0.0f64, 1.0f64, true, false)
    let t3 = dist.qnorm(f64(k + 1usize) / f64(rr + 1usize), 0.0f64, 1.0f64, true, false)
    let tk = ts[k - 1usize]
    let tk1 = ts[k]
    ret tk + (t1 - t2) / (t3 - t2) * (tk1 - tk)
}

// boot.ci of one statistic's replicates t (non-finite ones dropped): type 0 perc, 1 norm, 2 basic; lo and hi are written to out[0], out[1]
fn boot_ci(a: *mem.Arena, t: []const f64, t0: f64, conf: f64, kind: usize, out: []f64) {
    var nf = 0usize
    var i = 0usize
    while i < t.len {
        if t[i] - t[i] == 0.0f64 { nf += 1usize }
        i += 1usize
    }
    let (ts, e1) = mem.alloc[f64](a, nf)
    let (tmp, e2) = mem.alloc[f64](a, nf)
    if e1 != ok || e2 != ok {
        out[0usize] = nan()
        out[1usize] = nan()
        ret
    }
    var k = 0usize
    i = 0usize
    while i < t.len {
        if t[i] - t[i] == 0.0f64 {
            ts[k] = t[i]
            k += 1usize
        }
        i += 1usize
    }
    if kind == 1usize {
        let vt = rvar(ts, tmp)
        let bias = rmean(ts, tmp) - t0
        let merr = math.sqrt[f64](vt) * dist.qnorm((1.0f64 + conf) / 2.0f64, 0.0f64, 1.0f64, true, false)
        out[0usize] = t0 - bias - merr
        out[1usize] = t0 - bias + merr
        ret
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](ts, &ctx, cmp_up)
    if kind == 0usize {
        out[0usize] = norm_inter_one(ts, (1.0f64 - conf) / 2.0f64)
        out[1usize] = norm_inter_one(ts, (1.0f64 + conf) / 2.0f64)
        ret
    }
    out[0usize] = 2.0f64 * t0 - norm_inter_one(ts, (1.0f64 + conf) / 2.0f64)
    out[1usize] = 2.0f64 * t0 - norm_inter_one(ts, (1.0f64 - conf) / 2.0f64)
}

// the bootstrap of bootVar (no breakdown by years): R replicates of the statistic from `boot::boot` over rows (cluster empty) or clusters, resampled
// within the levels of design (all one level when design is empty). bootType calibrate (calib true) re-calibrates the weights on each replicate with
// calibWeights(aux, weight, totals, method, bounds). out_var has 1 + nlev values, out_ci two per value (lower, upper) for the ciType 0 perc / 1 norm / 2 basic.
fn boot_var(a: *mem.Arena, r: *rng.Rng, sp: Spec, inc: []const f64, w: []const f64, male: []const f64, stratum: []const f64, levels: []const f64, design: []const f64, cluster: []const f64, aux: []const f64, naux: usize, totals: []const f64, calib: bool, cmethod: usize, b0: f64, b1: f64, nrep: usize, ci_type: usize, alpha: f64, out_var: []f64, out_ci: []f64) -> err {
    let n = inc.len
    let ns = 1usize + sp.nlev
    // units: rows, or the clusters in order of first appearance
    var nu = n
    let (first, ef) = mem.alloc[usize](a, n)
    if ef != ok { ret ef }
    if cluster.len == 0usize {
        var i = 0usize
        while i < n {
            first[i] = i
            i += 1usize
        }
    } else {
        nu = 0usize
        var i = 0usize
        while i < n {
            var seen = false
            var j = 0usize
            while j < i {
                if cluster[j] == cluster[i] { seen = true }
                j += 1usize
            }
            if !seen {
                first[nu] = i
                nu += 1usize
            }
            i += 1usize
        }
    }
    // strata of the units, their sorted distinct values
    let (ustr, e1) = mem.alloc[f64](a, nu)
    let (sv, e2) = mem.alloc[f64](a, nu)
    if e1 != ok || e2 != ok { ret e1 }
    var i = 0usize
    while i < nu {
        if design.len == 0usize { ustr[i] = 1.0f64 } else { ustr[i] = design[first[i]] }
        i += 1usize
    }
    var nsv = 0usize
    i = 0usize
    while i < nu {
        var seen = false
        var j = 0usize
        while j < nsv {
            if sv[j] == ustr[i] { seen = true }
            j += 1usize
        }
        if !seen {
            sv[nsv] = ustr[i]
            nsv += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < nsv {
        let v = sv[i]
        var j = i
        while j > 0usize && sv[j - 1usize] > v {
            sv[j] = sv[j - 1usize]
            j -= 1usize
        }
        sv[j] = v
        i += 1usize
    }
    // index matrix R by nu, column-major (idx[c * R + r])
    let (idx, e3) = mem.alloc[usize](a, nrep * nu)
    if e3 != ok { ret e3 }
    if nsv == 1usize {
        let (s, es) = rng.sample_int(a, r, i64(nu), i64(nu * nrep), true)
        if es != ok { ret es }
        i = 0usize
        while i < nu * nrep {
            idx[i] = usize(s[i] - 1i64)
            i += 1usize
        }
    } else {
        var g = 0usize
        while g < nsv {
            var len = 0usize
            i = 0usize
            while i < nu {
                if ustr[i] == sv[g] { len += 1usize }
                i += 1usize
            }
            let (gp, e4) = mem.alloc[usize](a, len)
            if e4 != ok { ret e4 }
            var k = 0usize
            i = 0usize
            while i < nu {
                if ustr[i] == sv[g] {
                    gp[k] = i
                    k += 1usize
                }
                i += 1usize
            }
            if len == 1usize {
                var rr = 0usize
                while rr < nrep {
                    idx[gp[0usize] * nrep + rr] = gp[0usize]
                    rr += 1usize
                }
            } else {
                let (s, es) = rng.sample_int(a, r, i64(len), i64(nrep * len), true)
                if es != ok { ret es }
                var pos = 0usize
                while pos < nrep * len {
                    let col = gp[pos / nrep]
                    idx[col * nrep + pos % nrep] = gp[usize(s[pos] - 1i64)]
                    pos += 1usize
                }
            }
            g += 1usize
        }
    }
    // cluster members in the order of split(1:n, cluster): sorted distinct cluster values
    let (cv, e5) = mem.alloc[f64](a, nu)
    if e5 != ok { ret e5 }
    i = 0usize
    while i < nu {
        if cluster.len > 0usize { cv[i] = cluster[first[i]] } else { cv[i] = f64(i) }
        i += 1usize
    }
    i = 1usize
    while i < nu {
        let v = cv[i]
        var j = i
        while j > 0usize && cv[j - 1usize] > v {
            cv[j] = cv[j - 1usize]
            j -= 1usize
        }
        cv[j] = v
        i += 1usize
    }
    var maxc = 1usize
    if cluster.len > 0usize {
        i = 0usize
        while i < nu {
            var cnt = 0usize
            var j = 0usize
            while j < n {
                if cluster[j] == cv[i] { cnt += 1usize }
                j += 1usize
            }
            if cnt > maxc { maxc = cnt }
            i += 1usize
        }
    }
    let cap = n * maxc
    let (t0, e6) = mem.alloc[f64](a, ns)
    let (tt, e7) = mem.alloc[f64](a, nrep * ns)
    let (rows, e8) = mem.alloc[usize](a, cap)
    let (bi, e9) = mem.alloc[f64](a, cap)
    let (bw, e10) = mem.alloc[f64](a, cap)
    let (bm, e11) = mem.alloc[f64](a, cap)
    let (bs, e12) = mem.alloc[f64](a, cap)
    let (bx, e13) = mem.alloc[f64](a, cap * naux + 1usize)
    let (gg, e14) = mem.alloc[f64](a, cap)
    let (qq, e15) = mem.alloc[f64](a, cap)
    let (sres, e16) = mem.alloc[f64](a, ns)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok || e16 != ok { ret e6 }
    i = 0usize
    while i < cap {
        qq[i] = 1.0f64
        i += 1usize
    }
    // replicate rr = nrep is the original sample (boot's t0); the others are the resamples
    var rr = 0usize
    while rr <= nrep {
        var m = 0usize
        if rr == nrep {
            i = 0usize
            while i < n {
                rows[i] = i
                i += 1usize
            }
            m = n
        } else if cluster.len == 0usize {
            i = 0usize
            while i < n {
                rows[i] = idx[i * nrep + rr]
                i += 1usize
            }
            m = n
        } else {
            var c = 0usize
            while c < nu {
                let cl = cv[idx[c * nrep + rr]]
                i = 0usize
                while i < n {
                    if cluster[i] == cl {
                        rows[m] = i
                        m += 1usize
                    }
                    i += 1usize
                }
                c += 1usize
            }
        }
        i = 0usize
        while i < m {
            bi[i] = inc[rows[i]]
            bw[i] = w[rows[i]]
            if male.len > 0usize { bm[i] = male[rows[i]] }
            if stratum.len > 0usize { bs[i] = stratum[rows[i]] }
            var j = 0usize
            while j < naux {
                bx[j * m + i] = aux[j * n + rows[i]]
                j += 1usize
            }
            i += 1usize
        }
        var okc = true
        if calib {
            okc = calib_weights(a, bx[0usize..m * naux], m, naux, bw[0usize..m], totals, qq[0usize..m], cmethod, b0, b1, 500usize, 1.0e-6f64, gg)
            i = 0usize
            while i < m {
                bw[i] = gg[i] * bw[i]
                i += 1usize
            }
        }
        var mm: []const f64 = zero
        if male.len > 0usize { mm = bm[0usize..m] }
        var ss: []const f64 = zero
        if stratum.len > 0usize { ss = bs[0usize..m] }
        stat_vec(a, sp, bi[0usize..m], bw[0usize..m], mm, ss, levels, sres)
        var s = 0usize
        while s < ns {
            var v = sres[s]
            if !okc { v = nan() }
            if rr == nrep { t0[s] = v } else { tt[rr * ns + s] = v }
            s += 1usize
        }
        rr += 1usize
    }
    let (col, e17) = mem.alloc[f64](a, nrep)
    let (tmp, e18) = mem.alloc[f64](a, nrep)
    if e17 != ok || e18 != ok { ret e17 }
    var s = 0usize
    while s < ns {
        rr = 0usize
        while rr < nrep {
            col[rr] = tt[rr * ns + s]
            rr += 1usize
        }
        out_var[s] = rvar(col, tmp)
        boot_ci(a, col, t0[s], 1.0f64 - alpha, ci_type, out_ci[2usize * s..2usize * s + 2usize])
        s += 1usize
    }
    ret ok
}

// ---- the Pareto tail ----

fn count_above(x: []const f64, x0: f64) -> usize {
    var k = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] > x0 { k += 1usize }
        i += 1usize
    }
    ret k
}

// sorted copy of x and, when w is not empty, w in the same order (R's order(x), ties by position)
fn sort_pair(a: *mem.Arena, x: []const f64, w: []const f64, xs: []f64, ws: []f64) -> err {
    let (ord, e) = lk.order_of(a, x, x, false)
    if e != ok { ret e }
    var i = 0usize
    while i < x.len {
        xs[i] = x[ord[i]]
        if w.len > 0usize { ws[i] = w[ord[i]] }
        i += 1usize
    }
    ret ok
}

// .thetaHill on sorted x with k tail values; w the weights in the same order or empty
fn theta_hill(x: []const f64, k: usize, x0: f64, w: []const f64) -> f64 {
    let n = x.len
    let lx0 = math.log[f64](x0)
    var s = 0.0f64
    var cmp = 0.0f64
    var sw = 0.0f64
    var cw = 0.0f64
    var i = n - k
    while i < n {
        if w.len > 0usize {
            let v = w[i] * (math.log[f64](x[i]) - lx0)
            let t = s + v
            if math.abs[f64](s) >= math.abs[f64](v) { cmp += (s - t) + v } else { cmp += (v - t) + s }
            s = t
            let t2 = sw + w[i]
            if math.abs[f64](sw) >= math.abs[f64](w[i]) { cw += (sw - t2) + w[i] } else { cw += (w[i] - t2) + sw }
            sw = t2
        } else {
            let v = math.log[f64](x[i]) - lx0
            let t = s + v
            if math.abs[f64](s) >= math.abs[f64](v) { cmp += (s - t) + v } else { cmp += (v - t) + s }
            s = t
        }
        i += 1usize
    }
    if w.len > 0usize { ret (sw + cw) / (s + cmp) }
    ret f64(k) / (s + cmp)
}

type IseCtx = struct { y: []const f64, w: []const f64, pdc: bool, tmp: []f64 }

// the integrated squared error criterion of .thetaISE (pdc false) and .thetaPDC (pdc true) at theta; the tail values are y = x / x0
fn ise_at(c: *IseCtx, theta: f64) -> f64 {
    let k = c.y.len
    var i = 0usize
    while i < k {
        let f = theta * math.pow[f64](c.y[i], 0.0f64 - 1.0f64 - theta)
        if c.pdc { c.tmp[i] = f } else { c.tmp[i] = theta * theta / (2.0f64 * theta + 1.0f64) - 2.0f64 * f }
        i += 1usize
    }
    var mean = 0.0f64
    if c.w.len > 0usize {
        var j = 0usize
        while j < k {
            c.tmp[k + j] = c.tmp[j] * c.w[j]
            j += 1usize
        }
        mean = rsum(c.tmp[k..2usize * k]) / rsum(c.w)
    } else {
        mean = rsum(c.tmp[0usize..k]) / f64(k)
    }
    if !c.pdc { ret mean }
    let pf2 = theta * theta / (2.0f64 * theta + 1.0f64)
    let u = mean / pf2
    ret u * u * pf2 - 2.0f64 * u * mean
}

fn eps4() -> f64 { ret math.sqrt[f64](math.sqrt[f64](2.220446049250313e-16f64)) }

// thetaISE (pdc false) or thetaPDC (pdc true) by optimize over (tol, 3 Hill)
fn theta_ise(a: *mem.Arena, x: []const f64, k: usize, x0: f64, w: []const f64, pdc: bool) -> f64 {
    let n = x.len
    let (y, e1) = mem.alloc[f64](a, k)
    let (tmp, e2) = mem.alloc[f64](a, 2usize * k)
    if e1 != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < k {
        y[i] = x[n - k + i] / x0
        i += 1usize
    }
    var wt: []const f64 = zero
    if w.len > 0usize { wt = w[n - k..n] }
    var c = IseCtx { y: y, w: wt, pdc: pdc, tmp: tmp }
    let p = theta_hill(x, k, x0, w)
    ret fd.brent_min[IseCtx](&c, ise_at, eps4(), 3.0f64 * p)
}

fn theta_ls(x: []const f64, k: usize, tmp: []f64) -> f64 {
    let n = x.len
    let kk = f64(k)
    let z = tmp[0usize..k]
    let ck = tmp[k..2usize * k]
    let t3 = tmp[2usize * k..3usize * k]
    var i = 0usize
    while i < k {
        z[i] = math.log[f64](x[n - k + i])
        var pk = f64(i + 1usize) / kk
        if i + 1usize == k { pk = kk / (kk + 1.0f64) }
        ck[i] = 0.0f64 - math.log[f64](1.0f64 - pk)
        i += 1usize
    }
    let zm = rmean(z, t3)
    let ckm = rmean(ck, t3)
    i = 0usize
    while i < k {
        t3[i] = (ck[i] - ckm) * (ck[i] - ckm)
        i += 1usize
    }
    let num = rsum(t3) / kk
    i = 0usize
    while i < k {
        t3[i] = ck[i] * z[i]
        i += 1usize
    }
    ret num / (rsum(t3) / kk - ckm * zm)
}

fn theta_moment(x: []const f64, k: usize, x0: f64, tmp: []f64) -> f64 {
    let n = x.len
    let y = tmp[0usize..k]
    let t2 = tmp[k..2usize * k]
    var i = 0usize
    while i < k {
        y[i] = math.log[f64](x[n - k + i] / x0)
        i += 1usize
    }
    let m1 = rmean(y, t2)
    i = 0usize
    while i < k {
        t2[i] = y[i] * y[i]
        i += 1usize
    }
    let m2 = rmean(t2, tmp[2usize * k..3usize * k])
    ret 1.0f64 / (m1 + 1.0f64 - 1.0f64 / (2.0f64 * (1.0f64 - m1 * m1 / m2)))
}

fn theta_qq(x: []const f64, k: usize, tmp: []f64) -> f64 {
    let n = x.len
    let kk = f64(k)
    let lx = tmp[0usize..k]
    let h = tmp[k..2usize * k]
    let t3 = tmp[2usize * k..3usize * k]
    var i = 0usize
    while i < k {
        lx[i] = math.log[f64](x[n - 1usize - i])
        h[i] = 0.0f64 - math.log[f64](f64(i + 1usize) / (kk + 1.0f64))
        i += 1usize
    }
    let slx = rsum(lx)
    let sh = rsum(h)
    i = 0usize
    while i < k {
        t3[i] = h[i] * h[i]
        i += 1usize
    }
    let sh2 = rsum(t3)
    i = 0usize
    while i < k {
        t3[i] = h[i] * (kk * lx[i] - slx)
        i += 1usize
    }
    ret (kk * sh2 - sh * sh) / rsum(t3)
}

fn theta_tm(x: []const f64, k: usize, x0: f64, beta1: f64, beta2: f64, tmp: []f64) -> f64 {
    let n = x.len
    let kl = usize(math.trunc[f64](f64(k) * beta1)) + 1usize
    let kh = k - usize(math.trunc[f64](f64(k) * beta2))
    let cs = tmp[0usize..k]
    var run = 0.0f64
    var i = 1usize
    var denom = 0.0f64
    while i <= kh {
        run += 1.0f64 / f64(k - i + 1usize)
        if i >= kl { denom += run }
        cs[i - 1usize] = run
        i += 1usize
    }
    let cc = 1.0f64 / denom
    var s = 0.0f64
    i = kl
    while i <= kh {
        s += cc * math.log[f64](x[n - k + i - 1usize] / x0)
        i += 1usize
    }
    ret 1.0f64 / s
}

type WmlCtx = struct { y: []const f64, hy: []const f64, hsig: []const f64, xt: []const f64, x0: f64, cst: f64, p1: f64, p2: f64, resid: bool }

fn wml_zero(c: *WmlCtx, theta: f64) -> f64 {
    let k = c.y.len
    var s = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    while i < k {
        var u = 1.0f64
        if c.resid {
            let r = (theta * c.y[i] + c.hy[i]) / c.hsig[i]
            u = c.cst / math.abs[f64](r)
            if u > 1.0f64 { u = 1.0f64 }
        } else {
            let f = 1.0f64 - math.pow[f64](c.xt[i] / c.x0, 0.0f64 - theta)
            if f < c.p1 {
                u = f / c.p1
            } else if f <= 1.0f64 - c.p2 {
                u = 1.0f64
            } else {
                u = (1.0f64 - f) / c.p2
            }
        }
        let v = u * (1.0f64 / theta - c.y[i])
        let t = s + v
        if math.abs[f64](s) >= math.abs[f64](v) { comp += (s - t) + v } else { comp += (v - t) + s }
        s = t
        i += 1usize
    }
    ret s + comp
}

// thetaWML: weight 0 residuals (const defaults to 2.5), 1 probability (const = (p1, p2) defaults to 0.005); bias applies the bias correction
fn theta_wml(a: *mem.Arena, x: []const f64, k: usize, x0: f64, resid: bool, c1: f64, c2: f64, bias: bool) -> f64 {
    let n = x.len
    let (y, e1) = mem.alloc[f64](a, k)
    let (hy, e2) = mem.alloc[f64](a, k)
    let (hsig, e3) = mem.alloc[f64](a, k)
    let (xt, e4) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan() }
    var cum = 0.0f64
    var i = 0usize
    while i < k {
        xt[i] = x[n - k + i]
        y[i] = math.log[f64](xt[i] / x0)
        let h = f64(k - i)
        hy[i] = math.log[f64](h / (f64(k) + 1.0f64))
        cum += 1.0f64 / (h * h)
        hsig[i] = math.sqrt[f64](cum)
        i += 1usize
    }
    var c = WmlCtx { y: y, hy: hy, hsig: hsig, xt: xt, x0: x0, cst: c1, p1: c1, p2: c2, resid: resid }
    let tol = eps4()
    let hill = theta_hill(x, k, x0, x[0usize..0usize])
    var theta = pw.zeroin[WmlCtx](&c, wml_zero, tol, 5.0f64 * hill, tol, 1000i64)
    if bias {
        var bcorr = 0.0f64
        if resid {
            var num = 0.0f64
            var den = 0.0f64
            var prev = 0.0f64
            i = 0usize
            while i < k {
                let r = (theta * y[i] + hy[i]) / hsig[i]
                var u = c1 / math.abs[f64](r)
                if u > 1.0f64 { u = 1.0f64 }
                let f = 1.0f64 - math.pow[f64](xt[i] / x0, 0.0f64 - theta)
                let df = f - prev
                prev = f
                let dlogf = 1.0f64 / theta - y[i]
                let d2logf = 0.0f64 - 1.0f64 / (theta * theta)
                var du = 0.0f64
                if u != 1.0f64 {
                    let tyh = theta * y[i] + hy[i]
                    du = (0.0f64 - c1) * y[i] * hsig[i] / (tyh * tyh)
                }
                num += u * dlogf * df
                den += (du * dlogf + u * d2logf) * df
                i += 1usize
            }
            bcorr = (0.0f64 - num) / den
        } else {
            let cp1 = 1.0f64 - c1
            let cp2 = 1.0f64 - c2
            let lcp1 = math.log[f64](cp1)
            let lp2 = math.log[f64](c2)
            bcorr = (theta / 2.0f64) * (2.0f64 * cp1 * cp1 * lcp1 + c1 * cp1 + c1 * cp2 + 2.0f64 * c1 * c2 * lp2) / ((cp1 * lcp1) * (cp1 * lcp1) - c1 * cp1 - c1 * cp2 + c1 * c2 * (lp2 * lp2))
        }
        theta = theta - bcorr
    }
    ret theta
}

// the Pareto index of the k largest of the sorted x by the method: 0 Hill, 1 ISE, 2 PDC, 3 LS, 4 moment, 5 QQ, 6 TM (beta = (c1, c2)), 7 WML residuals
// (const c1), 8 WML probability (const c1, c2); bias applies to WML; w are the weights in the sorted order for Hill, ISE and PDC (else empty)
fn theta_of(a: *mem.Arena, x: []const f64, k: usize, x0: f64, method: usize, w: []const f64, c1: f64, c2: f64, bias: bool) -> f64 {
    let (tmp, e) = mem.alloc[f64](a, 3usize * k + 3usize)
    if e != ok { ret nan() }
    if method == 0usize { ret theta_hill(x, k, x0, w) }
    if method == 1usize { ret theta_ise(a, x, k, x0, w, false) }
    if method == 2usize { ret theta_ise(a, x, k, x0, w, true) }
    if method == 3usize { ret theta_ls(x, k, tmp) }
    if method == 4usize { ret theta_moment(x, k, x0, tmp) }
    if method == 5usize { ret theta_qq(x, k, tmp) }
    if method == 6usize { ret theta_tm(x, k, x0, c1, c2, tmp) }
    if method == 7usize { ret theta_wml(a, x, k, x0, true, c1, c2, bias) }
    ret theta_wml(a, x, k, x0, false, c1, c2, bias)
}

// qpareto(p, x0, theta) = x0 exp(qexp(p) / theta)
fn qpareto(p: f64, x0: f64, theta: f64) -> f64 { ret x0 * math.exp[f64]((0.0f64 - dist.log1p(0.0f64 - p)) / theta) }

// paretoScale(x, w, method VanKerm, center, probs): x0 and the number of values above it; center 0 mean, 1 median; w empty for none
fn pareto_scale(a: *mem.Arena, x: []const f64, w: []const f64, center: usize, p1: f64, p2: f64) -> (f64, usize) {
    let (ones, e) = mem.alloc[f64](a, x.len)
    let (tmp, e2) = mem.alloc[f64](a, x.len)
    if e != ok || e2 != ok { ret (nan(), 0usize) }
    var i = 0usize
    while i < x.len {
        ones[i] = 1.0f64
        i += 1usize
    }
    var ww = w
    if w.len == 0usize { ww = ones }
    var mu = 0.0f64
    var q1 = 0.0f64
    var q2 = 0.0f64
    if center == 0usize {
        if w.len == 0usize { mu = rmean(x, tmp) } else { mu = wmean(a, x, w) }
        q1 = lk.weighted_quantile(a, x, ww, p1)
        q2 = lk.weighted_quantile(a, x, ww, p2)
    } else {
        mu = lk.weighted_quantile(a, x, ww, 0.5f64)
        q1 = lk.weighted_quantile(a, x, ww, p1)
        q2 = lk.weighted_quantile(a, x, ww, p2)
    }
    var x0 = 2.5f64 * mu
    if q2 < x0 { x0 = q2 }
    if q1 > x0 { x0 = q1 }
    ret (x0, count_above(x, x0))
}

type Tail = struct { theta: f64, x0: f64, k: usize, q: f64, nout: usize }

// paretoTail(x, k or x0, method, w, alpha): usek true takes k, else x0 sets k; tail receives the (1-based) indices of the tail values in increasing order of x
// and out those above the 1 - alpha Pareto quantile, in increasing order of x
fn pareto_tail(a: *mem.Arena, x: []const f64, usek: bool, kin: usize, x0in: f64, method: usize, w: []const f64, alpha: f64, c1: f64, c2: f64, bias: bool, tail: []usize, out: []usize) -> (Tail, err) {
    var res: Tail = zero
    let n = x.len
    let (ord, e) = lk.order_of(a, x, x, false)
    let (xs, e1) = mem.alloc[f64](a, n)
    let (ws, e2) = mem.alloc[f64](a, n)
    if e != ok || e1 != ok || e2 != ok { ret (res, mem.Full) }
    var i = 0usize
    while i < n {
        xs[i] = x[ord[i]]
        if w.len > 0usize { ws[i] = w[ord[i]] }
        i += 1usize
    }
    var k = kin
    var x0 = x0in
    if usek { x0 = xs[n - k - 1usize] } else { k = count_above(xs, x0) }
    var wv: []const f64 = zero
    if w.len > 0usize && (method <= 2usize) { wv = ws }
    let theta = theta_of(a, xs, k, x0, method, wv, c1, c2, bias)
    i = 0usize
    while i < k {
        tail[i] = ord[n - k + i] + 1usize
        i += 1usize
    }
    let q = qpareto(1.0f64 - alpha, x0, theta)
    var no = 0usize
    // which(x > q) ordered by x
    i = 0usize
    while i < n {
        let id = ord[i]
        if x[id] > q {
            out[no] = id + 1usize
            no += 1usize
        }
        i += 1usize
    }
    res.theta = theta
    res.x0 = x0
    res.k = k
    res.q = q
    res.nout = no
    ret (res, ok)
}

// replaceTail: the tail (all) or only the outliers get a sorted rpareto(k, x0, theta) sample, assigned in increasing order of x; the draws come from r
fn replace_tail(a: *mem.Arena, r: *rng.Rng, x: []const f64, which: []const usize, x0: f64, theta: f64, res: []f64) -> err {
    var i = 0usize
    while i < x.len {
        res[i] = x[i]
        i += 1usize
    }
    let k = which.len
    if k == 0usize { ret ok }
    let (nw, e) = mem.alloc[f64](a, k)
    if e != ok { ret e }
    i = 0usize
    while i < k {
        nw[i] = x0 / math.pow[f64](rng.unif(r), 1.0f64 / theta)
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](nw, &ctx, cmp_up)
    i = 0usize
    while i < k {
        res[which[i] - 1usize] = nw[i]
        i += 1usize
    }
    ret ok
}

// fitPareto(x, k or x0, method): the k largest values replaced by a sorted Pareto sample drawn from r
fn fit_pareto(a: *mem.Arena, r: *rng.Rng, x: []const f64, usek: bool, kin: usize, x0in: f64, method: usize, w: []const f64, c1: f64, c2: f64, bias: bool, res: []f64) -> err {
    let n = x.len
    let (ord, e) = lk.order_of(a, x, x, false)
    let (xs, e1) = mem.alloc[f64](a, n)
    let (ws, e2) = mem.alloc[f64](a, n)
    if e != ok || e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        xs[i] = x[ord[i]]
        if w.len > 0usize { ws[i] = w[ord[i]] }
        i += 1usize
    }
    var k = kin
    var x0 = x0in
    if usek { x0 = xs[n - k - 1usize] } else { k = count_above(xs, x0) }
    var wv: []const f64 = zero
    if w.len > 0usize && method <= 2usize { wv = ws }
    let theta = theta_of(a, xs, k, x0, method, wv, c1, c2, bias)
    i = 0usize
    while i < n {
        res[i] = x[i]
        i += 1usize
    }
    let (nw, e3) = mem.alloc[f64](a, k)
    if e3 != ok { ret e3 }
    i = 0usize
    while i < k {
        nw[i] = x0 / math.pow[f64](rng.unif(r), 1.0f64 / theta)
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](nw, &ctx, cmp_up)
    i = 0usize
    while i < k {
        res[ord[n - k + i]] = nw[i]
        i += 1usize
    }
    ret ok
}

// shrinkOut: the outliers are set to the 1 - alpha Pareto quantile
fn shrink_out(x: []const f64, out: []const usize, q: f64, res: []f64) {
    var i = 0usize
    while i < x.len {
        res[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < out.len {
        res[out[i] - 1usize] = q
        i += 1usize
    }
}

// reweightOut(tail, X, w): without weights the outliers get weight 0 (the rest 1); with weights the others are re-calibrated so the totals of X (taken with
// the original weights) minus the sum of X over the outliers are met, and the outliers get weight 1. ok is false when calibration fails
fn reweight_out(a: *mem.Arena, out: []const usize, n: usize, xm: []const f64, p: usize, w: []const f64, method: usize, b0: f64, b1: f64, res: []f64) -> bool {
    var i = 0usize
    if w.len == 0usize {
        i = 0usize
        while i < n {
            res[i] = 1.0f64
            i += 1usize
        }
        i = 0usize
        while i < out.len {
            res[out[i] - 1usize] = 0.0f64
            i += 1usize
        }
        ret true
    }
    i = 0usize
    while i < n {
        res[i] = w[i]
        i += 1usize
    }
    if out.len == 0usize { ret true }
    let m = n - out.len
    let (isout, e0) = mem.alloc[bool](a, n)
    let (x1, e1) = mem.alloc[f64](a, m * p)
    let (d1, e2) = mem.alloc[f64](a, m)
    let (tot, e3) = mem.alloc[f64](a, p)
    let (g, e4) = mem.alloc[f64](a, m)
    let (q, e5) = mem.alloc[f64](a, m)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret false }
    i = 0usize
    while i < n {
        isout[i] = false
        i += 1usize
    }
    i = 0usize
    while i < out.len {
        isout[out[i] - 1usize] = true
        i += 1usize
    }
    var j = 0usize
    while j < p {
        var st = 0.0f64
        var so = 0.0f64
        i = 0usize
        while i < n {
            st += xm[j * n + i] * w[i]
            if isout[i] { so += xm[j * n + i] }
            i += 1usize
        }
        tot[j] = st - so
        j += 1usize
    }
    var r = 0usize
    i = 0usize
    while i < n {
        if !isout[i] {
            d1[r] = w[i]
            q[r] = 1.0f64
            j = 0usize
            while j < p {
                x1[j * m + r] = xm[j * n + i]
                j += 1usize
            }
            r += 1usize
        }
        i += 1usize
    }
    let okc = calib_weights(a, x1, m, p, d1, tot, q, method, b0, b1, 500usize, 1.0e-6f64, g)
    if !okc { ret false }
    i = 0usize
    while i < out.len {
        res[out[i] - 1usize] = 1.0f64
        i += 1usize
    }
    r = 0usize
    i = 0usize
    while i < n {
        if !isout[i] {
            res[i] = g[r] * d1[r]
            r += 1usize
        }
        i += 1usize
    }
    ret true
}

// meanExcessPlot's points: the thresholds mu (the smallest n - trunc(sqrt n)... values in increasing order when probs is empty, else the weighted quantiles
// at probs) and the mean excess above each, weighted when w is not empty; mu_out and me_out receive one value per threshold; answers how many
fn mean_excess(a: *mem.Arena, x: []const f64, w: []const f64, probs: []const f64, mu_out: []f64, me_out: []f64) -> usize {
    let n = x.len
    var cnt = 0usize
    if probs.len > 0usize {
        let (ones, e) = mem.alloc[f64](a, n)
        if e != ok { ret 0usize }
        var i = 0usize
        while i < n {
            ones[i] = 1.0f64
            i += 1usize
        }
        var ww = w
        if w.len == 0usize { ww = ones }
        i = 0usize
        while i < probs.len {
            if w.len == 0usize {
                mu_out[i] = type1_quantile(a, x, probs[i])
            } else {
                mu_out[i] = lk.weighted_quantile(a, x, ww, probs[i])
            }
            i += 1usize
        }
        cnt = probs.len
    } else {
        let (xs, e) = mem.alloc[f64](a, n)
        if e != ok { ret 0usize }
        let (ord, e1) = lk.order_of(a, x, x, false)
        if e1 != ok { ret 0usize }
        var i = 0usize
        while i < n {
            xs[i] = x[ord[i]]
            i += 1usize
        }
        cnt = usize(f64(n) - math.sqrt[f64](f64(n)))
        i = 0usize
        while i < cnt {
            mu_out[i] = xs[i]
            i += 1usize
        }
    }
    let (tmp, e2) = mem.alloc[f64](a, 2usize * n)
    if e2 != ok { ret 0usize }
    var m = 0usize
    while m < cnt {
        var c = 0usize
        var i = 0usize
        while i < n {
            if x[i] > mu_out[m] {
                tmp[c] = x[i] - mu_out[m]
                if w.len > 0usize { tmp[n + c] = tmp[c] * w[i] }
                c += 1usize
            }
            i += 1usize
        }
        if w.len == 0usize {
            me_out[m] = rmean(tmp[0usize..c], tmp[n..n + c])
        } else {
            var sw = 0.0f64
            var cw = 0.0f64
            i = 0usize
            var cc = 0usize
            while i < n {
                if x[i] > mu_out[m] {
                    sw += w[i]
                    cc += 1usize
                }
                i += 1usize
            }
            me_out[m] = rsum(tmp[n..n + c]) / sw
        }
        m += 1usize
    }
    ret cnt
}

// quantile(x, p, type = 1): the smallest order statistic whose cumulative share reaches p (with R's fuzz)
fn type1_quantile(a: *mem.Arena, x: []const f64, p: f64) -> f64 {
    let n = x.len
    let (xs, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan() }
    var i = 0usize
    while i < n {
        xs[i] = x[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](xs, &ctx, cmp_up)
    let nppm = f64(n) * p
    let j = math.floor[f64](nppm + 4.0f64 * 2.220446049250313e-16f64)
    var idx = usize(j)
    if nppm > j { idx += 1usize }
    if idx < 1usize { idx = 1usize }
    if idx > n { idx = n }
    ret xs[idx - 1usize]
}

// the y of paretoQPlot: the theoretical exponential quantiles of the sorted sample, -log(n:1 / (n + 1)) or with weights -log(1 - cumsum(w) / (cw[n] (n + 1) / n))
fn pareto_q_y(a: *mem.Arena, x: []const f64, w: []const f64, y: []f64) -> err {
    let n = x.len
    let (xs, e1) = mem.alloc[f64](a, n)
    let (ws, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    let es = sort_pair(a, x, w, xs, ws)
    if es != ok { ret es }
    if w.len == 0usize {
        var i = 0usize
        while i < n {
            y[i] = 0.0f64 - math.log[f64](f64(n - i) / f64(n + 1usize))
            i += 1usize
        }
        ret ok
    }
    var cw = 0.0f64
    let (cs, e3) = mem.alloc[f64](a, n)
    if e3 != ok { ret e3 }
    var i = 0usize
    while i < n {
        cw += ws[i]
        cs[i] = cw
        i += 1usize
    }
    i = 0usize
    while i < n {
        y[i] = 0.0f64 - math.log[f64](1.0f64 - cs[i] / (cs[n - 1usize] * f64(n + 1usize) / f64(n)))
        i += 1usize
    }
    ret ok
}

// ---- minAMSE ----

fn mse_init(x: []const f64, k: usize, theta: f64, sc: []f64) -> f64 {
    let n = x.len
    let x0 = x[n - k - 1usize]
    var i = 0usize
    while i < k {
        let y = math.log[f64](x[n - k + i] / x0)
        let nyhat = math.log[f64](f64(k - i) / f64(k + 1usize)) / theta
        sc[i] = (y + nyhat) * (y + nyhat)
        i += 1usize
    }
    ret rsum(sc[0usize..k]) / f64(k)
}

// sc needs 5 k values
fn mse_opt(x: []const f64, k: usize, theta: f64, rho: f64, bern: bool, sc: []f64) -> f64 {
    let n = x.len
    let x0 = x[n - k - 1usize]
    let kk = f64(k)
    let tmp2 = (1.0f64 - rho) * (1.0f64 - rho)
    let v = sc[0usize..k]
    let tm = sc[k..2usize * k]
    let w1 = sc[2usize * k..3usize * k]
    let w2 = sc[3usize * k..4usize * k]
    let t3 = sc[4usize * k..5usize * k]
    var i = 1usize
    while i <= k {
        let hv = f64(i) / (kk + 1.0f64)
        var wk1 = 1.0f64
        var wk2 = f64(k - i + 1usize) / (kk + 1.0f64)
        if bern {
            wk1 = hv
            wk2 = 0.0f64 - math.log[f64](f64(i) / (kk + 1.0f64))
        }
        w1[i - 1usize] = wk1
        w2[i - 1usize] = wk2
        let tmp1 = 1.0f64 / hv - 1.0f64
        let q3 = (math.pow[f64](hv, 0.0f64 - rho) - 1.0f64) / rho
        tm[i - 1usize] = tmp1
        v[i - 1usize] = q3 * q3
        i += 1usize
    }
    // mean(wk1 * tmp1), mean(wk2 * tmp1), tmp2 * mean(wk1 * tmp3), tmp2 * mean(wk2 * tmp3)
    i = 0usize
    while i < k {
        t3[i] = w1[i] * tm[i]
        i += 1usize
    }
    let ak1 = rsum(t3) / kk
    i = 0usize
    while i < k {
        t3[i] = w2[i] * tm[i]
        i += 1usize
    }
    let ak2 = rsum(t3) / kk
    i = 0usize
    while i < k {
        t3[i] = w1[i] * v[i]
        i += 1usize
    }
    let bk1 = tmp2 * (rsum(t3) / kk)
    i = 0usize
    while i < k {
        t3[i] = w2[i] * v[i]
        i += 1usize
    }
    let bk2 = tmp2 * (rsum(t3) / kk)
    let den = ak1 * bk2 - bk1 * ak2
    let d1 = (bk2 - ak2) / den
    let d2 = (ak1 - bk1) / den
    i = 1usize
    while i <= k {
        let wopt = d1 * w1[i - 1usize] + d2 * w2[i - 1usize]
        let y = math.log[f64](x[n - k + i - 1usize] / x0)
        let nyhat = math.log[f64](f64(k - i + 1usize) / (kk + 1.0f64)) / theta
        t3[i - 1usize] = wopt * ((y + nyhat) * (y + nyhat))
        i += 1usize
    }
    ret rsum(t3) / kk
}

// theta is 1-based in R: th[j - 1] is theta[j]
fn rm_of(th: []const f64, m: usize, k: usize) -> f64 {
    let mk = m + k
    let h4 = th[mk / 4usize - 1usize]
    let h2 = th[mk / 2usize - 1usize]
    let hm2 = th[m / 2usize - 1usize]
    let hm = th[m - 1usize]
    ret math.log[f64](math.abs[f64]((h4 - h2) / (hm2 - hm))) / math.log[f64](2.0f64 * f64(m) / f64(m - k))
}

fn crit_rm(th: []const f64, rho: f64, m: usize, k: usize, sc: []f64) -> f64 {
    // j <- k:(m - 1), which counts down when k exceeds m - 1
    var cnt = 0usize
    var j = k
    var up = true
    if k > m - 1usize { up = false }
    var going = true
    while going {
        let l = math.log[f64](math.abs[f64]((th[j / 2usize - 1usize] - th[j - 1usize]) / (th[m / 2usize - 1usize] - th[m - 1usize])))
        let d = l - rho * math.log[f64](f64(m) / f64(j))
        sc[cnt] = d * d
        cnt += 1usize
        if j == m - 1usize {
            going = false
        } else if up {
            j += 1usize
        } else {
            j -= 1usize
        }
    }
    ret rmean(sc[0usize..cnt], sc[cnt..2usize * cnt])
}

// minAMSE(x, weight, kmin, kmax, mmax, tol, maxit): res = (kopt, x0, theta, MSEmin, rho); the arguments are used as given (no clamping to the suggested bounds)
fn min_amse(a: *mem.Arena, x: []const f64, bern: bool, kmin: usize, kmax: usize, mmax: usize, tol: usize, maxit: usize, res: []f64) -> err {
    let n = x.len
    let (xs, e0) = mem.alloc[f64](a, n)
    let (th, e1) = mem.alloc[f64](a, mmax + 1usize)
    let (mse, e2) = mem.alloc[f64](a, 5usize * kmax + 2usize * mmax + 8usize)
    if e0 != ok || e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        xs[i] = x[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](xs, &ctx, cmp_up)
    let kl = kmin / 2usize
    var kk = kl
    while kk <= mmax {
        th[kk - 1usize] = theta_hill(xs, kk, xs[n - kk - 1usize], xs[0usize..0usize])
        kk += 1usize
    }
    // k0 = the k in kmin:kmax with the smallest MSEinit
    var k0 = kmin
    var best = mse_init(xs, kmin, th[kmin - kl], mse)
    kk = kmin + 1usize
    while kk <= kmax {
        let v = mse_init(xs, kk, th[kk - kl], mse)
        if v == v && (best != best || v < best) {
            best = v
            k0 = kk
        }
        kk += 1usize
    }
    var theta0 = th[k0 - 1usize]
    var rho0 = 0.0f64
    var bc = 0.0f64
    var m = k0 + 1usize
    var first = true
    while m <= mmax {
        let rho = rm_of(th, m, k0)
        let c = crit_rm(th, rho, m, k0, mse)
        if c == c && (first || c < bc) {
            bc = c
            rho0 = rho
            first = false
        }
        m += 1usize
    }
    var kn = k0
    var msemin = 0.0f64
    var rhon = rho0
    var it = 1usize
    while it <= maxit {
        var bm = 0.0f64
        var fnd = false
        kn = kmin
        kk = kmin
        while kk <= kmax {
            let v = mse_opt(xs, kk, theta0, rho0, bern, mse)
            if v == v && (!fnd || v < bm) {
                bm = v
                kn = kk
                fnd = true
            }
            kk += 1usize
        }
        msemin = bm
        let thetan = th[kn - 1usize]
        var rbest = 0.0f64
        var cbest = 0.0f64
        var f2 = true
        m = kn + 1usize
        while m <= mmax {
            let rho = rm_of(th, m, kn)
            let c = crit_rm(th, rho, m, k0, mse)
            if c == c && (f2 || c < cbest) {
                cbest = c
                rbest = rho
                f2 = false
            }
            m += 1usize
        }
        rhon = rbest
        var d = 0usize
        if kn > k0 { d = kn - k0 } else { d = k0 - kn }
        if d <= tol {
            res[0usize] = f64(kn)
            res[1usize] = xs[n - kn - 1usize]
            res[2usize] = thetan
            res[3usize] = msemin
            res[4usize] = rhon
            ret ok
        }
        k0 = kn
        theta0 = thetan
        rho0 = rhon
        it += 1usize
    }
    res[0usize] = f64(kn)
    res[1usize] = xs[n - kn - 1usize]
    res[2usize] = th[kn - 1usize]
    res[3usize] = msemin
    res[4usize] = rhon
    ret ok
}
