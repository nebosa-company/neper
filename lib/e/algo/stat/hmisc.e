// R Hmisc, the closed-form part: `binconf` (exact, Wilson and asymptotic binomial confidence limits),
// `wtd_mean`, `wtd_var` (unbiased), `somers2` (the concordance index C and Somers' Dxy of a 0/1 response,
// unweighted, ties by mid-ranks) and `rank_avg`.
//
// Also here: wtd.table, wtd.quantile, wtd.rank and the rcspline.eval basis.
//
// Not here: rcorr, hdquantile, cut2, rcspline.restate, describe, varclus,
// redun and the bootstrap summaries.

use e.algo.rand.r as rng
use e.math
use e.algo.linalg.decomp as dc
use e.algo.stat.hclust as hc
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem

fn qn(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

// binconf(x, n, alpha): which 0 exact, 1 wilson, 2 asymptotic; answers (lower, upper)
fn binconf(x: f64, n: f64, alpha: f64, which: u8) -> (f64, f64) {
    let nu1 = 2.0f64 * (n - x + 1.0f64)
    let nu2 = 2.0f64 * x
    var ll = 0.0f64
    if x > 0.0f64 { ll = x / (x + nb.qf(1.0f64 - alpha / 2.0f64, nu1, nu2, true, false) * (n - x + 1.0f64)) }
    let nu1p = nu2 + 2.0f64
    let nu2p = nu1 - 2.0f64
    var pp = 1.0f64
    if x < n { pp = nb.qf(1.0f64 - alpha / 2.0f64, nu1p, nu2p, true, false) }
    let ul = ((x + 1.0f64) * pp) / (n - x + (x + 1.0f64) * pp)
    let zcrit = 0.0f64 - qn(alpha / 2.0f64)
    let z2 = zcrit * zcrit
    let p = x / n
    var cl0 = (p + z2 / 2.0f64 / n - zcrit * math.sqrt[f64]((p * (1.0f64 - p) + z2 / 4.0f64 / n) / n)) / (1.0f64 + z2 / n)
    var cl1 = (p + z2 / 2.0f64 / n + zcrit * math.sqrt[f64]((p * (1.0f64 - p) + z2 / 4.0f64 / n) / n)) / (1.0f64 + z2 / n)
    if x == 1.0f64 { cl0 = 0.0f64 - math.log[f64](1.0f64 - alpha) / n }
    if x == n - 1.0f64 { cl1 = 1.0f64 + math.log[f64](1.0f64 - alpha) / n }
    let za = qn(1.0f64 - alpha / 2.0f64)
    let al = x / n - za * math.sqrt[f64](((x / n) * (1.0f64 - x / n)) / n)
    let au = x / n + za * math.sqrt[f64](((x / n) * (1.0f64 - x / n)) / n)
    if which == 0u8 { ret (ll, ul) }
    if which == 1u8 { ret (cl0, cl1) }
    ret (al, au)
}

fn wtd_mean(x: []const f64, w: []const f64) -> f64 {
    var s = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < x.len {
        s += w[i] * x[i]
        sw += w[i]
        i += 1usize
    }
    ret s / sw
}

fn wtd_var(x: []const f64, w: []const f64) -> f64 {
    var sw = 0.0f64
    var i = 0usize
    while i < x.len {
        sw += w[i]
        i += 1usize
    }
    let xbar = wtd_mean(x, w)
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += w[i] * (x[i] - xbar) * (x[i] - xbar)
        i += 1usize
    }
    ret s / (sw - 1.0f64)
}

// the average rank of x[i] (ties share the mean of their ranks), 1-based
fn rank_avg(x: []const f64, i: usize) -> f64 {
    var less = 0.0f64
    var eq = 0.0f64
    var j = 0usize
    while j < x.len {
        if x[j] < x[i] { less += 1.0f64 } else if x[j] == x[i] { eq += 1.0f64 }
        j += 1usize
    }
    ret less + (eq + 1.0f64) / 2.0f64
}

// somers2(x, y) for a 0/1 y: (C, Dxy)
fn somers2(x: []const f64, y: []const f64) -> (f64, f64) {
    let n = f64(x.len)
    var n1 = 0.0f64
    var sr = 0.0f64
    var i = 0usize
    while i < x.len {
        if y[i] == 1.0f64 {
            n1 += 1.0f64
            sr += rank_avg(x, i)
        }
        i += 1usize
    }
    let c = (sr / n1 - (n1 + 1.0f64) / 2.0f64) / (n - n1)
    ret (c, 2.0f64 * (c - 0.5f64))
}

// ---- weighted tables, quantiles and ranks, and the restricted cubic spline basis ----

// wtd.table(x, weights): the distinct values ascending (ux) and the summed weights (sw); returns the count; zero-weight observations are dropped by the callers
fn wtd_table(a: *mem.Arena, x: []const f64, w: []const f64, ux: []f64, sw: []f64) -> usize {
    let n = x.len
    let (ord, e) = mem.alloc[usize](a, n)
    if e != ok { ret 0usize }
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = ord[i]
        var j = i
        while j > 0usize && x[ord[j - 1usize]] > x[key] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    var m = 0usize
    i = 0usize
    while i < n {
        if m > 0usize && ux[m - 1usize] == x[ord[i]] {
            sw[m - 1usize] += w[ord[i]]
        } else {
            ux[m] = x[ord[i]]
            sw[m] = w[ord[i]]
            m += 1usize
        }
        i += 1usize
    }
    ret m
}

// wtd.quantile(x, weights, probs, type = "quantile"): out[k] for each probability
fn wtd_quantile(a: *mem.Arena, x: []const f64, w: []const f64, probs: []const f64, out: []f64) -> err {
    let n0 = x.len
    let (xs, e1) = mem.alloc[f64](a, n0)
    let (ws, e2) = mem.alloc[f64](a, n0)
    let (ux, e3) = mem.alloc[f64](a, n0)
    let (sw, e4) = mem.alloc[f64](a, n0)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret mem.Full }
    var cnt = 0usize
    var i = 0usize
    while i < n0 {
        if w[i] != 0.0f64 {
            xs[cnt] = x[i]
            ws[cnt] = w[i]
            cnt += 1usize
        }
        i += 1usize
    }
    let m = wtd_table(a, xs[0usize..cnt], ws[0usize..cnt], ux, sw)
    var n = 0.0f64
    i = 0usize
    while i < m {
        n += sw[i]
        i += 1usize
    }
    var k = 0usize
    while k < probs.len {
        let order = 1.0f64 + (n - 1.0f64) * probs[k]
        var low = math.floor[f64](order)
        if low < 1.0f64 { low = 1.0f64 }
        var high = low + 1.0f64
        if high > n { high = n }
        let fr = order - math.floor[f64](order)
        let ql = step_at(ux, sw, m, low)
        let qh = step_at(ux, sw, m, high)
        out[k] = (1.0f64 - fr) * ql + fr * qh
        k += 1usize
    }
    ret ok
}

// approx(cumsum(w), x, xout = t, method = "constant", f = 1, rule = 2): the value at the first cumulative weight that reaches t
fn step_at(ux: []const f64, sw: []const f64, m: usize, t: f64) -> f64 {
    var cum = 0.0f64
    var i = 0usize
    while i < m {
        cum += sw[i]
        if cum >= t { ret ux[i] }
        i += 1usize
    }
    ret ux[m - 1usize]
}

// wtd.rank(x, weights): the weighted mid-rank of every observation
fn wtd_rank(a: *mem.Arena, x: []const f64, w: []const f64, out: []f64) -> err {
    let n = x.len
    let (ux, e1) = mem.alloc[f64](a, n)
    let (sw, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    let m = wtd_table(a, x, w, ux, sw)
    var i = 0usize
    while i < n {
        var cum = 0.0f64
        var k = 0usize
        var hit = false
        while k < m && !hit {
            cum += sw[k]
            if ux[k] == x[i] {
                out[i] = cum - 0.5f64 * (sw[k] - 1.0f64)
                hit = true
            }
            k += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn pos_part(v: f64) -> f64 {
    if v > 0.0f64 { ret v }
    ret 0.0f64
}

// rcspline.eval(x, knots, inclx = FALSE, norm): the nk - 2 restricted cubic spline basis columns (n by nk - 2, column-major); norm 0 no scaling, 1 the last knot gap, 2 (the default) (last - first knot)^(2/3)
fn rcspline_eval(x: []const f64, knots: []const f64, norm: usize, out: []f64) {
    let n = x.len
    let nk = knots.len
    let k1 = knots[0usize]
    let kn = knots[nk - 1usize]
    let kn1 = knots[nk - 2usize]
    var kd = 1.0f64
    if norm == 1usize { kd = kn - kn1 }
    if norm == 2usize { kd = math.pow[f64](kn - k1, 2.0f64 / 3.0f64) }
    var j = 0usize
    while j + 2usize < nk {
        var i = 0usize
        while i < n {
            let t1 = pos_part((x[i] - knots[j]) / kd)
            let t2 = pos_part((x[i] - kn) / kd)
            let t3 = pos_part((x[i] - kn1) / kd)
            out[j * n + i] = t1 * t1 * t1 + ((kn1 - knots[j]) * (t2 * t2 * t2) - (kn - knots[j]) * (t3 * t3 * t3)) / (kn - kn1)
            i += 1usize
        }
        j += 1usize
    }
}

// hdquantile(x, probs): the Harrell-Davis estimator, the order statistics weighted by the beta(p (n + 1), (1 - p) (n + 1)) probability of each rank interval
fn hd_quantile(a: *mem.Arena, x: []const f64, p: f64) -> f64 {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > key {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = key
        i += 1usize
    }
    let m = f64(n) + 1.0f64
    var total = 0.0f64
    var prev = 0.0f64
    i = 1usize
    while i <= n {
        let cur = nb.pbeta(f64(i) / f64(n), p * m, (1.0f64 - p) * m, true, false)
        total += (cur - prev) * s[i - 1usize]
        prev = cur
        i += 1usize
    }
    ret total
}

// rcorr(x, y): the correlation (Pearson, or Spearman on mid-ranks when spearman) of two complete samples and its two-sided P value from the t distribution on n - 2 degrees of freedom; out = (r, P)
fn rcorr_pair(a: *mem.Arena, x: []const f64, y: []const f64, spearman: bool, out: []f64) -> err {
    let n = x.len
    let (rx, e1) = mem.alloc[f64](a, n)
    let (ry, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        if spearman {
            rx[i] = rank_avg(x, i)
            ry[i] = rank_avg(y, i)
        } else {
            rx[i] = x[i]
            ry[i] = y[i]
        }
        i += 1usize
    }
    var mx = 0.0f64
    var my = 0.0f64
    i = 0usize
    while i < n {
        mx += rx[i]
        my += ry[i]
        i += 1usize
    }
    mx = mx / f64(n)
    my = my / f64(n)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < n {
        sxy += (rx[i] - mx) * (ry[i] - my)
        sxx += (rx[i] - mx) * (rx[i] - mx)
        syy += (ry[i] - my) * (ry[i] - my)
        i += 1usize
    }
    let r = sxy / math.sqrt[f64](sxx * syy)
    out[0usize] = r
    let t = math.abs[f64](r) * math.sqrt[f64](f64(n - 2usize) / (1.0f64 - r * r))
    out[1usize] = 2.0f64 * (1.0f64 - nb.pt(t, f64(n - 2usize), true, false))
    ret ok
}

// cut2(x, g = g, onlycuts = TRUE): the lower limits of the groups and the maximum; x has no missing values; returns the count written to out
fn cut2_cuts_n(a: *mem.Arena, x: []const f64, g: usize, out: []f64) -> (usize, usize) {
    let n = x.len
    let (ones, e1) = mem.alloc[f64](a, n)
    let (xx, e2) = mem.alloc[f64](a, n)
    let (cn, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret (0usize, 0usize) }
    var i = 0usize
    while i < n {
        ones[i] = 1.0f64
        i += 1usize
    }
    let m = wtd_table(a, x, ones, xx, cn)
    // cumulative counts
    var cum = 0.0f64
    i = 0usize
    while i < m {
        cum += cn[i]
        cn[i] = cum
        i += 1usize
    }
    let nnm = f64(n)
    let (cuts, e4) = mem.alloc[f64](a, g)
    if e4 != ok { ret (0usize, 0usize) }
    var j = 0usize
    while j < g {
        let t = f64(j + 1usize) * (nnm / f64(g))
        var v = xx[m - 1usize]
        var k = 0usize
        var hit = false
        while k < m && !hit {
            if cn[k] >= t {
                v = xx[k]
                hit = true
            }
            k += 1usize
        }
        cuts[j] = v
        j += 1usize
    }
    cuts[g - 1usize] = xx[m - 1usize]
    var lower = xx[0usize]
    var upper = 1.0e45f64
    var cnt = 0usize
    j = 0usize
    while j < g {
        let cj = cuts[j]
        if cj != upper {
            upper = cj
            out[cnt] = lower
            cnt += 1usize
            if j + 1usize == g {
                lower = upper
            } else {
                var nx = upper
                var found = false
                var q = 0usize
                while q < m {
                    if xx[q] > upper && (!found || xx[q] < nx) {
                        nx = xx[q]
                        found = true
                    }
                    q += 1usize
                }
                lower = nx
            }
        }
        j += 1usize
    }
    let nlow = cnt
    // unique(c(low, max(xx)))
    var last = xx[m - 1usize]
    var dup = false
    i = 0usize
    while i < cnt {
        if out[i] == last { dup = true }
        i += 1usize
    }
    if !dup {
        out[cnt] = last
        cnt += 1usize
    }
    ret (cnt, nlow)
}

fn cut2_cuts(a: *mem.Arena, x: []const f64, g: usize, out: []f64) -> usize {
    let (cnt, nlow) = cut2_cuts_n(a, x, g, out)
    ret cnt
}

// approxExtrap(x, y, xout): linear interpolation of the sorted distinct x, extended beyond the range by the line through the two end points; x is ascending and distinct
fn approx_extrap(x: []const f64, y: []const f64, xo: f64) -> f64 {
    let n = x.len
    if xo < x[0usize] { ret (y[1usize] - y[0usize]) / (x[1usize] - x[0usize]) * (xo - x[0usize]) + y[0usize] }
    if xo > x[n - 1usize] { ret (y[n - 1usize] - y[n - 2usize]) / (x[n - 1usize] - x[n - 2usize]) * (xo - x[n - 2usize]) + y[n - 2usize] }
    var i = 0usize
    while i + 1usize < n && x[i + 1usize] < xo { i += 1usize }
    if xo == x[i] { ret y[i] }
    if i + 1usize < n && xo == x[i + 1usize] { ret y[i + 1usize] }
    ret y[i] + (y[i + 1usize] - y[i]) * (xo - x[i]) / (x[i + 1usize] - x[i])
}

// rcorr.cens(x, Surv(time, event)): out = (C index, Dxy, n, uncensored, relevant pairs, concordant, uncertain), the pair counts as the package reports them (each pair counted twice, a tie in x as half)
fn rcorr_cens(x: []const f64, time: []const f64, event: []const f64, out: []f64) {
    let n = x.len
    var rel = 0.0f64
    var conc = 0.0f64
    var tied = 0.0f64
    var unc = 0.0f64
    var tiec = 0.0f64
    var nu = 0.0f64
    var i = 0usize
    while i < n {
        if event[i] == 1.0f64 { nu += 1.0f64 }
        var j = 0usize
        while j < n {
            if j != i && (time[i] < time[j] || (time[i] == time[j] && event[i] == 1.0f64 && event[j] == 0.0f64)) {
                if event[i] == 1.0f64 {
                    rel += 1.0f64
                    if x[i] < x[j] { conc += 1.0f64 } else if x[i] == x[j] { tied += 1.0f64 }
                } else if time[i] < time[j] {
                    unc += 1.0f64
                }
            }
            if j != i && time[i] == time[j] && event[i] == 0.0f64 && event[j] == 0.0f64 { tiec += 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    let c = (conc + 0.5f64 * tied) / rel
    out[0usize] = c
    out[1usize] = 2.0f64 * (c - 0.5f64)
    out[2usize] = f64(n)
    out[3usize] = nu
    out[4usize] = 2.0f64 * rel
    out[5usize] = 2.0f64 * conc + tied
    out[6usize] = 2.0f64 * unc + tiec
}

fn mean_sd(x: []const f64) -> (f64, f64) {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / n
    var v = 0.0f64
    i = 0usize
    while i < x.len {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret (m, math.sqrt[f64](v / (n - 1.0f64)))
}

// smean.cl.normal(x, conf.int): out = (mean, lower, upper) with the t quantile on n - 1 degrees of freedom
fn smean_cl_normal(x: []const f64, conf: f64, out: []f64) {
    let (m, s) = mean_sd(x)
    let n = f64(x.len)
    let t = nb.qt((1.0f64 + conf) / 2.0f64, n - 1.0f64, true, false)
    out[0usize] = m
    out[1usize] = m - t * s / math.sqrt[f64](n)
    out[2usize] = m + t * s / math.sqrt[f64](n)
}

// smean.sdl(x, mult): out = (mean, mean - mult sd, mean + mult sd)
fn smean_sdl(x: []const f64, mult: f64, out: []f64) {
    let (m, s) = mean_sd(x)
    out[0usize] = m
    out[1usize] = m - mult * s
    out[2usize] = m + mult * s
}

// smedian.hilow(x, conf.int): out = (median, the (1 - conf) / 2 quantile, the (1 + conf) / 2 quantile), type 7
fn smedian_hilow(a: *mem.Arena, x: []const f64, conf: f64, out: []f64) -> err {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > key {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = key
        i += 1usize
    }
    out[0usize] = q7(s, 0.5f64)
    out[1usize] = q7(s, (1.0f64 - conf) / 2.0f64)
    out[2usize] = q7(s, (1.0f64 + conf) / 2.0f64)
    ret ok
}

fn q7(s: []const f64, p: f64) -> f64 {
    let h = (f64(s.len) - 1.0f64) * p
    let lo = math.floor[f64](h)
    let hi = math.ceil[f64](h)
    let q = s[usize(lo)]
    if hi > lo { ret q + (h - lo) * (s[usize(hi)] - q) }
    ret q
}

// varclus(x, similarity = "spearman" or "pearson", trans, method): the variables of the n by k column-major x clustered by hclust on 1 - similarity, the similarity the squared (trans 0), absolute (1) or raw (2) correlation; tree receives R's merge, heights and order
fn varclus(a: *mem.Arena, x: []const f64, n: usize, k: usize, spearman: bool, trans: usize, method: usize) -> (hc.Tree, err) {
    let (d, e1) = mem.alloc[f64](a, k * k)
    let (o2, e2) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok { ret (zero, e1) }
    var i = 0usize
    while i < k {
        d[i * k + i] = 0.0f64
        var j = i + 1usize
        while j < k {
            let e = rcorr_pair(a, x[i * n..i * n + n], x[j * n..j * n + n], spearman, o2)
            if e != ok { ret (zero, e) }
            var s = o2[0usize]
            if trans == 0usize { s = s * s }
            if trans == 1usize { s = math.abs[f64](s) }
            d[i * k + j] = 1.0f64 - s
            d[j * k + i] = 1.0f64 - s
            j += 1usize
        }
        i += 1usize
    }
    let (t, e3) = hc.hclust(a, d, k, method)
    ret (t, e3)
}

// GiniMd(x): Gini's mean difference, the mean absolute difference of two distinct observations, 2 / (n (n - 1)) sum (2 i - n - 1) x_(i) over the sorted values
fn gini_md(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > key {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = key
        i += 1usize
    }
    var t = 0.0f64
    i = 0usize
    while i < n {
        t += s[i] * (2.0f64 * f64(i + 1usize) - f64(n) - 1.0f64)
        i += 1usize
    }
    ret t * 2.0f64 / (f64(n) * (f64(n) - 1.0f64))
}

// the Info of describe(): 1 - sum(f^3 - f) / (n^3 - n) over the frequencies f of the distinct values, the share of the information a continuous variable would carry
fn describe_info(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > key {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = key
        i += 1usize
    }
    var tot = 0.0f64
    i = 0usize
    while i < n {
        var j = i
        while j + 1usize < n && s[j + 1usize] == s[i] { j += 1usize }
        let f = f64(j - i + 1usize)
        tot += f * f * f - f
        i = j + 1usize
    }
    let nf = f64(n)
    ret 1.0f64 - tot / (nf * nf * nf - nf)
}

// the S.D. of rcorr.cens: 2 sqrt(sum_i (r_i - D m_i)^2) / M, where for every relevant pair (an event i with a later time, or an event tied with a censored one) both members get the sign of x_j - x_i added to r and one added to m, D = sum r / sum m is Dxy and M = sum m the "Relevant Pairs"
// (the form was found against the package: sd^2 M^2 / sum (r - D m)^2 is exactly 4)
fn rcorr_cens_sd(a: *mem.Arena, x: []const f64, time: []const f64, event: []const f64) -> f64 {
    let n = x.len
    let (r, e1) = mem.alloc[f64](a, n)
    let (m, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        r[i] = 0.0f64
        m[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        if event[i] == 1.0f64 {
            var j = 0usize
            while j < n {
                if j != i && (time[i] < time[j] || (time[i] == time[j] && event[j] == 0.0f64)) {
                    var s = 0.0f64
                    if x[i] < x[j] { s = 1.0f64 } else if x[i] > x[j] { s = 0.0f64 - 1.0f64 }
                    r[i] += s
                    r[j] += s
                    m[i] += 1.0f64
                    m[j] += 1.0f64
                }
                j += 1usize
            }
        }
        i += 1usize
    }
    var sr = 0.0f64
    var sm = 0.0f64
    i = 0usize
    while i < n {
        sr += r[i]
        sm += m[i]
        i += 1usize
    }
    let d = sr / sm
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (r[i] - d * m[i]) * (r[i] - d * m[i])
        i += 1usize
    }
    ret 2.0f64 * math.sqrt[f64](ss) / sm
}

// smean.cl.boot(x, conf.int, B): the bootstrap mean interval, B resamples each drawn with sample.int(n, n, TRUE) (R's rejection-sampled indices), the mean of each, and the type-7 quantiles of those means at (1 -/+ conf) / 2; out = (mean, lower, upper)
fn smean_cl_boot(a: *mem.Arena, r: *rng.Rng, x: []const f64, conf: f64, nboot: usize, out: []f64) -> err {
    let n = x.len
    let (z, e1) = mem.alloc[f64](a, nboot)
    if e1 != ok { ret e1 }
    var xbar = 0.0f64
    var i = 0usize
    while i < n {
        xbar += x[i]
        i += 1usize
    }
    xbar = xbar / f64(n)
    var b = 0usize
    while b < nboot {
        let mark = mem.mark(a)
        let (s, e2) = rng.sample_int(a, r, i64(n), i64(n), true)
        if e2 != ok { ret e2 }
        var sum = 0.0f64
        i = 0usize
        while i < n {
            sum += x[usize(s[i]) - 1usize]
            i += 1usize
        }
        z[b] = sum / f64(n)
        mem.reset(a, mark)
        b += 1usize
    }
    i = 1usize
    while i < nboot {
        let key = z[i]
        var j = i
        while j > 0usize && z[j - 1usize] > key {
            z[j] = z[j - 1usize]
            j -= 1usize
        }
        z[j] = key
        i += 1usize
    }
    out[0usize] = xbar
    out[1usize] = q7(z, (1.0f64 - conf) / 2.0f64)
    out[2usize] = q7(z, (1.0f64 + conf) / 2.0f64)
    ret ok
}

// redun(~ ., data, r2, nk = 0): the redundancy analysis with linear terms. Each pass regresses every remaining variable on all the other remaining ones (lm with an intercept), removes the variable with the largest R^2 when it reaches r2, and repeats on the rest;
// order receives the removed columns (0-based) and rsq their R^2 at removal; x is n by p column-major; answers the number removed
fn redun_linear(a: *mem.Arena, x: []const f64, n: usize, p: usize, r2: f64, order: []usize, rsq: []f64) -> usize {
    let (alive, e1) = mem.alloc[bool](a, p)
    let (dm, e2) = mem.alloc[f64](a, n * p)
    if e1 != ok || e2 != ok { ret 0usize }
    var j = 0usize
    while j < p {
        alive[j] = true
        j += 1usize
    }
    var removed = 0usize
    var go = true
    while go {
        var best = p
        var bestr = 0.0f64
        var left = 0usize
        j = 0usize
        while j < p {
            if alive[j] { left += 1usize }
            j += 1usize
        }
        if left < 2usize { break }
        j = 0usize
        while j < p {
            if alive[j] {
                let mark = mem.mark(a)
                var cols = 1usize
                var i = 0usize
                while i < n {
                    dm[i] = 1.0f64
                    i += 1usize
                }
                var k = 0usize
                while k < p {
                    if alive[k] && k != j {
                        i = 0usize
                        while i < n {
                            dm[cols * n + i] = x[k * n + i]
                            i += 1usize
                        }
                        cols += 1usize
                    }
                    k += 1usize
                }
                let (f, fe) = dc.lm_fit(a, dm[0usize..cols * n], n, cols, x[j * n..j * n + n], 1.0e-7f64)
                if fe == ok {
                    var ym = 0.0f64
                    i = 0usize
                    while i < n {
                        ym += x[j * n + i]
                        i += 1usize
                    }
                    ym = ym / f64(n)
                    var tss = 0.0f64
                    var rss = 0.0f64
                    i = 0usize
                    while i < n {
                        tss += (x[j * n + i] - ym) * (x[j * n + i] - ym)
                        rss += f.residuals[i] * f.residuals[i]
                        i += 1usize
                    }
                    let rr = 1.0f64 - rss / tss
                    if best == p || rr > bestr {
                        best = j
                        bestr = rr
                    }
                }
                mem.reset(a, mark)
            }
            j += 1usize
        }
        if best == p || bestr < r2 { break }
        alive[best] = false
        order[removed] = best
        rsq[removed] = bestr
        removed += 1usize
    }
    ret removed
}

// spearman2(x, y, p) for a numeric x and p of 1 or 2: out = (rho2, F, adjusted rho2); the squared rank correlation, or the R^2 of the y ranks on the x ranks and their squares
fn spearman2(a: *mem.Arena, x: []const f64, y: []const f64, p: usize, out: []f64) -> err {
    let n = x.len
    let (rx, e1) = mem.alloc[f64](a, n * 2usize)
    let (ry, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        rx[i] = rank_avg(x, i)
        rx[n + i] = rx[i] * rx[i]
        ry[i] = rank_avg(y, i)
        i += 1usize
    }
    var ym = 0.0f64
    i = 0usize
    while i < n {
        ym += ry[i]
        i += 1usize
    }
    ym = ym / f64(n)
    var tss = 0.0f64
    i = 0usize
    while i < n {
        tss += (ry[i] - ym) * (ry[i] - ym)
        i += 1usize
    }
    var r2 = 0.0f64
    if p == 1usize {
        var xm = 0.0f64
        i = 0usize
        while i < n {
            xm += rx[i]
            i += 1usize
        }
        xm = xm / f64(n)
        var sxy = 0.0f64
        var sxx = 0.0f64
        i = 0usize
        while i < n {
            sxy += (rx[i] - xm) * (ry[i] - ym)
            sxx += (rx[i] - xm) * (rx[i] - xm)
            i += 1usize
        }
        r2 = sxy * sxy / (sxx * tss)
    } else {
        let (dm, e3) = mem.alloc[f64](a, n * 3usize)
        if e3 != ok { ret e3 }
        i = 0usize
        while i < n {
            dm[i] = 1.0f64
            dm[n + i] = rx[i]
            dm[2usize * n + i] = rx[n + i]
            i += 1usize
        }
        let (f, fe) = dc.lm_fit(a, dm, n, 3usize, ry, 1.0e-7f64)
        if fe != ok { ret fe }
        var rss = 0.0f64
        i = 0usize
        while i < n {
            rss += f.residuals[i] * f.residuals[i]
            i += 1usize
        }
        r2 = 1.0f64 - rss / tss
    }
    let df2 = f64(n) - f64(p) - 1.0f64
    out[0usize] = r2
    out[1usize] = r2 / f64(p) / ((1.0f64 - r2) / df2)
    out[2usize] = 1.0f64 - (1.0f64 - r2) * (f64(n) - 1.0f64) / df2
    ret ok
}

// spearman2 for a factor x with ng > 2 levels (g holds the 0-based level of each row, every level used): p = ng - 1 and rho2 the between-group share of the y rank variance; out = (rho2, F, adjusted rho2)
fn spearman2_factor(a: *mem.Arena, g: []const usize, ng: usize, y: []const f64, out: []f64) -> err {
    let n = y.len
    let (ry, e1) = mem.alloc[f64](a, n)
    let (sm, e2) = mem.alloc[f64](a, ng)
    let (ct, e3) = mem.alloc[f64](a, ng)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var i = 0usize
    var ym = 0.0f64
    while i < n {
        ry[i] = rank_avg(y, i)
        ym += ry[i]
        sm[g[i]] = 0.0f64
        ct[g[i]] = 0.0f64
        i += 1usize
    }
    ym = ym / f64(n)
    i = 0usize
    var tss = 0.0f64
    while i < n {
        sm[g[i]] += ry[i]
        ct[g[i]] += 1.0f64
        tss += (ry[i] - ym) * (ry[i] - ym)
        i += 1usize
    }
    var ssb = 0.0f64
    var k = 0usize
    while k < ng {
        if ct[k] > 0.0f64 {
            let m = sm[k] / ct[k]
            ssb += ct[k] * (m - ym) * (m - ym)
        }
        k += 1usize
    }
    let p = f64(ng) - 1.0f64
    let df2 = f64(n) - p - 1.0f64
    let r2 = ssb / tss
    out[0usize] = r2
    out[1usize] = r2 / p / ((1.0f64 - r2) / df2)
    out[2usize] = 1.0f64 - (1.0f64 - r2) * (f64(n) - 1.0f64) / df2
    ret ok
}

// bpower(p1, p2, n1 =, n2 =, alpha): the power of the two-sided comparison of two proportions
fn bpower(p1: f64, p2: f64, n1: f64, n2: f64, alpha: f64) -> f64 {
    let z = qn(1.0f64 - alpha / 2.0f64)
    let pm = (n1 * p1 + n2 * p2) / (n1 + n2)
    let ds = z * math.sqrt[f64]((1.0f64 / n1 + 1.0f64 / n2) * pm * (1.0f64 - pm))
    let ex = math.abs[f64](p1 - p2)
    let sd = math.sqrt[f64](p1 * (1.0f64 - p1) / n1 + p2 * (1.0f64 - p2) / n2)
    ret 1.0f64 - dist.pnorm((ds - ex) / sd, 0.0f64, 1.0f64, true, false) + dist.pnorm((0.0f64 - ds - ex) / sd, 0.0f64, 1.0f64, true, false)
}

// bsamsize(p1, p2, fraction, alpha, power): (n1, n2)
fn bsamsize(p1: f64, p2: f64, fraction: f64, alpha: f64, power: f64) -> (f64, f64) {
    let za = qn(1.0f64 - alpha / 2.0f64)
    let zb = qn(power)
    let ratio = (1.0f64 - fraction) / fraction
    let p = fraction * p1 + (1.0f64 - fraction) * p2
    let t = za * math.sqrt[f64]((ratio + 1.0f64) * p * (1.0f64 - p)) + zb * math.sqrt[f64](ratio * p1 * (1.0f64 - p1) + p2 * (1.0f64 - p2))
    let n1 = t * t / ratio / ((p1 - p2) * (p1 - p2))
    ret (n1, ratio * n1)
}

// samplesize.bin(alpha, beta, pit, pic, rho): the arcsine-transformed sample size of Fleiss, rounded up the way Hmisc does (round(n + 0.5))
fn samplesize_bin(alpha: f64, beta: f64, pit: f64, pic: f64, rho: f64) -> f64 {
    let n0 = (qn(1.0f64 - alpha) + qn(beta)) / (math.asin[f64](math.sqrt[f64](pit)) - math.asin[f64](math.sqrt[f64](pic)))
    let n = n0 * n0 / (4.0f64 * rho * (1.0f64 - rho))
    ret math.round[f64](n + 0.5f64)
}

// ballocation(p1, p2, n, alpha): out = (min variance of the difference, of the ratio, of the log odds, the grid fraction of maximum power over 1000 points from 0.001 to 0.999 nearest one half)
fn ballocation(p1: f64, p2: f64, n: f64, alpha: f64, out: []f64) {
    let q1 = 1.0f64 - p1
    let q2 = 1.0f64 - p2
    let fd = 1.0f64 / (1.0f64 + math.sqrt[f64](p2 * q2 / (p1 * q1)))
    out[0usize] = fd
    out[1usize] = 1.0f64 / (1.0f64 + math.sqrt[f64](p1 * q2 / p2 / q1))
    out[2usize] = 1.0f64 - fd
    var best = -1.0f64
    var bf = 0.0f64
    var i = 0usize
    while i < 1000usize {
        let f = 0.001f64 + f64(i) * (0.999f64 - 0.001f64) / 999.0f64
        let pw = bpower(p1, p2, n * f, n * (1.0f64 - f), alpha)
        if pw > best || (pw == best && math.abs[f64](f - 0.5f64) < math.abs[f64](bf - 0.5f64)) {
            best = pw
            bf = f
        }
        i += 1usize
    }
    out[3usize] = bf
}

// cpower(tref, n, mc, r, accrual, tmin, noncomp.c, noncomp.i, alpha): the Cox/logrank power of Lachin and Foulkes as Hmisc computes it, equal group sizes n / 2; mc is the control mortality at tref and r the percent reduction
fn cpower(tref: f64, n: f64, mc: f64, r: f64, accrual: f64, tmin: f64, ncc: f64, nci: f64, alpha: f64) -> f64 {
    let mi = (1.0f64 - r / 100.0f64) * mc
    let lamc = 0.0f64 - math.log[f64](1.0f64 - mc) / tref
    let lami = 0.0f64 - math.log[f64](1.0f64 - mi) / tref
    let tmax = tmin + accrual
    var pc = 1.0f64 - math.exp[f64](0.0f64 - lamc * tmin)
    var pi = 1.0f64 - math.exp[f64](0.0f64 - lami * tmin)
    if accrual != 0.0f64 {
        pc = 1.0f64 - 1.0f64 / accrual / lamc * (math.exp[f64](0.0f64 - tmin * lamc) - math.exp[f64](0.0f64 - tmax * lamc))
        pi = 1.0f64 - 1.0f64 / accrual / lami * (math.exp[f64](0.0f64 - tmin * lami) - math.exp[f64](0.0f64 - tmax * lami))
    }
    let ec = pc * n / 2.0f64
    let ei = pi * n / 2.0f64
    var delta = math.log[f64](lami / lamc)
    if ncc + nci > 0.0f64 { delta = delta * (1.0f64 - (ncc + nci) / 100.0f64) }
    let sd = math.sqrt[f64](1.0f64 / ec + 1.0f64 / ei)
    let z = 0.0f64 - qn(alpha / 2.0f64)
    ret 1.0f64 - (dist.pnorm(z - math.abs[f64](delta) / sd, 0.0f64, 1.0f64, true, false) - dist.pnorm(0.0f64 - z - math.abs[f64](delta) / sd, 0.0f64, 1.0f64, true, false))
}

fn ev_prob(lam: f64, tmin: f64, tmax: f64, accrual: f64) -> f64 {
    ret 1.0f64 - 1.0f64 / accrual / lam * (math.exp[f64](0.0f64 - tmin * lam) - math.exp[f64](0.0f64 - tmax * lam))
}

// ciapower(tref, n1, n2, m1c, m2c, r1, r2, accrual, tmin, alpha): the power to detect a difference in the intervention hazard ratios of two strata
fn ciapower(tref: f64, n1: f64, n2: f64, m1c: f64, m2c: f64, r1: f64, r2: f64, accrual: f64, tmin: f64, alpha: f64) -> f64 {
    let m1i = (1.0f64 - r1 / 100.0f64) * m1c
    let m2i = (1.0f64 - r2 / 100.0f64) * m2c
    let l1c = 0.0f64 - math.log[f64](1.0f64 - m1c) / tref
    let l2c = 0.0f64 - math.log[f64](1.0f64 - m2c) / tref
    let l1i = 0.0f64 - math.log[f64](1.0f64 - m1i) / tref
    let l2i = 0.0f64 - math.log[f64](1.0f64 - m2i) / tref
    let tmax = tmin + accrual
    let e1c = ev_prob(l1c, tmin, tmax, accrual) * n1 / 2.0f64
    let e2c = ev_prob(l2c, tmin, tmax, accrual) * n2 / 2.0f64
    let e1i = ev_prob(l1i, tmin, tmax, accrual) * n1 / 2.0f64
    let e2i = ev_prob(l2i, tmin, tmax, accrual) * n2 / 2.0f64
    let delta = math.log[f64]((l1i / l1c) / (l2i / l2c))
    let sd = math.sqrt[f64](1.0f64 / e1c + 1.0f64 / e2c + 1.0f64 / e1i + 1.0f64 / e2i)
    let z = 0.0f64 - qn(alpha / 2.0f64)
    ret 1.0f64 - (dist.pnorm(z - math.abs[f64](delta) / sd, 0.0f64, 1.0f64, true, false) - dist.pnorm(0.0f64 - z - math.abs[f64](delta) / sd, 0.0f64, 1.0f64, true, false))
}

// popower(p, odds.ratio, n1, n2, alpha): out = (power, eff, approx.se) of the proportional-odds (Whitehead) comparison, p the marginal cell probabilities summing to one
fn popower(p: []const f64, oratio: f64, n1: f64, n2: f64, alpha: f64, out: []f64) {
    let n = n1 + n2
    var s3 = 0.0f64
    var i = 0usize
    while i < p.len {
        s3 += p[i] * p[i] * p[i]
        i += 1usize
    }
    let ps = 1.0f64 - s3
    let v = n1 * n2 * n / 3.0f64 / ((n + 1.0f64) * (n + 1.0f64)) * ps
    out[0usize] = dist.pnorm(math.abs[f64](math.log[f64](oratio)) * math.sqrt[f64](v) - qn(1.0f64 - alpha / 2.0f64), 0.0f64, 1.0f64, true, false)
    out[1usize] = ps / (1.0f64 - 1.0f64 / n / n)
    out[2usize] = 1.0f64 / math.sqrt[f64](v)
}

// posamsize(p, odds.ratio, fraction, alpha, power): (n, eff)
fn posamsize(p: []const f64, oratio: f64, fraction: f64, alpha: f64, power: f64) -> (f64, f64) {
    var s3 = 0.0f64
    var i = 0usize
    while i < p.len {
        s3 += p[i] * p[i] * p[i]
        i += 1usize
    }
    let ps = 1.0f64 - s3
    let aa = (1.0f64 - fraction) / fraction
    let lo = math.log[f64](oratio)
    let zz = qn(1.0f64 - alpha / 2.0f64) + qn(power)
    let n = 3.0f64 * (aa + 1.0f64) * (aa + 1.0f64) * zz * zz / aa / (lo * lo) / ps
    ret (n, ps / (1.0f64 - 1.0f64 / n / n))
}

// hoeffd(x, y): Hoeffding D (Hmisc, D[1, 2]) with mid-ranks and the Hollander-Wolfe bivariate rank Q with its tie weights
fn hoeffd(x: []const f64, y: []const f64) -> f64 {
    let n = x.len
    let nf = f64(n)
    var d1 = 0.0f64
    var d2 = 0.0f64
    var d3 = 0.0f64
    var i = 0usize
    while i < n {
        var q = 1.0f64
        var j = 0usize
        while j < n {
            if j != i {
                let lx = x[j] < x[i]
                let ey = y[j] == y[i]
                let ly = y[j] < y[i]
                let ex = x[j] == x[i]
                if lx && ly { q += 1.0f64 } else if ex && ey { q += 0.25f64 } else if ex && ly { q += 0.5f64 } else if lx && ey { q += 0.5f64 }
            }
            j += 1usize
        }
        let r = rank_avg(x, i)
        let s = rank_avg(y, i)
        d1 += (q - 1.0f64) * (q - 2.0f64)
        d2 += (r - 1.0f64) * (r - 2.0f64) * (s - 1.0f64) * (s - 2.0f64)
        d3 += (r - 2.0f64) * (s - 2.0f64) * (q - 1.0f64)
        i += 1usize
    }
    ret 30.0f64 * ((nf - 2.0f64) * (nf - 3.0f64) * d1 + d2 - 2.0f64 * (nf - 2.0f64) * d3) / (nf * (nf - 1.0f64) * (nf - 2.0f64) * (nf - 3.0f64) * (nf - 4.0f64))
}

// rcspline.restate(knots, coef, type, norm): the k + 1 coefficients of x and of the truncated powers (x - t_i)+^3 (or ^4 and x^2 for the integral) a restricted cubic spline fit expands to; coef holds the k - 1 slopes without the intercept; integral selects the integral type
fn rcspline_restate(knots: []const f64, coef: []const f64, norm: usize, integral: bool, out: []f64) {
    let k = knots.len
    let p = k - 1usize
    var kd = (knots[k - 1usize] - knots[0usize]) * (knots[k - 1usize] - knots[0usize])
    let dk = knots[k - 1usize] - knots[k - 2usize]
    if norm == 0usize { kd = 1.0f64 }
    if norm == 1usize { kd = dk * dk * dk }
    var i = 0usize
    while i < p {
        out[i] = coef[i]
        if i > 0usize { out[i] = coef[i] / kd }
        i += 1usize
    }
    var ck = 0.0f64
    var ck1 = 0.0f64
    i = 1usize
    while i < p {
        ck += out[i] * (knots[i - 1usize] - knots[k - 1usize])
        ck1 += out[i] * (knots[i - 1usize] - knots[k - 2usize])
        i += 1usize
    }
    out[p] = ck / (knots[k - 1usize] - knots[k - 2usize])
    out[p + 1usize] = ck1 / (knots[k - 2usize] - knots[k - 1usize])
    if integral {
        out[0usize] = 0.5f64 * out[0usize]
        i = 1usize
        while i < p + 2usize {
            out[i] = 0.25f64 * out[i]
            i += 1usize
        }
    }
}

// a sorted copy by insertion (ascending)
fn sorted_of(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let n = x.len
    let (s, e) = mem.alloc[f64](a, n + 1usize)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < n {
        s[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > key {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = key
        i += 1usize
    }
    ret (s[0usize..n], ok)
}

// the quantiles of a sorted sample at p = from + k (to - from) / (len - 1), k = 0 .. len - 1, into out
fn seq_quantiles(s: []const f64, from: f64, to: f64, len: usize, out: []f64) {
    var k = 0usize
    while k < len {
        var p = from
        if len > 1usize { p = from + f64(k) * (to - from) / f64(len - 1usize) }
        out[k] = q7(s, p)
        k += 1usize
    }
}

// the number of distinct values among the first n of v
fn count_unique(v: []const f64, n: usize) -> usize {
    var c = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < i {
            if v[j] == v[i] { seen = true }
            j += 1usize
        }
        if !seen { c += 1usize }
        i += 1usize
    }
    ret c
}

// rcspline.eval(x, nk = nk, knots.only = TRUE, fractied = fractied): the default knots of Hmisc (the tail quantiles with the first and fifth smallest and largest values, ties at the ends and the alternate algorithm
// for a sample with few distinct values) into out; returns the number of knots, or 0 when R stops
fn rcspline_knots(a: *mem.Arena, x: []const f64, nk: usize, fractied: f64, out: []f64) -> usize {
    let n0 = x.len
    if n0 < 6usize || nk < 3usize { ret 0usize }
    let (xs, e1) = sorted_of(a, x)
    if e1 != ok { ret 0usize }
    // the distinct values and their counts
    let (xu, e2) = mem.alloc[f64](a, n0)
    let (cn, e3) = mem.alloc[f64](a, n0)
    if e2 != ok || e3 != ok { ret 0usize }
    var nxu = 0usize
    var i = 0usize
    while i < n0 {
        if nxu > 0usize && xu[nxu - 1usize] == xs[i] {
            cn[nxu - 1usize] += 1.0f64
        } else {
            xu[nxu] = xs[i]
            cn[nxu] = 1.0f64
            nxu += 1usize
        }
        i += 1usize
    }
    if nxu < nk + 3usize {
        // (nxu - 2) <= nk: the interior distinct values
        var c = 0usize
        i = 1usize
        while i + 1usize < nxu {
            out[c] = xu[i]
            c += 1usize
            i += 1usize
        }
        if c < 3usize { ret 0usize }
        ret c
    }
    var outer = 0.05f64
    if nk <= 3usize { outer = 0.1f64 }
    if nk > 6usize { outer = 0.025f64 }
    var lo = 0usize
    var hi = n0
    var nke = nk
    var have_first = false
    var have_last = false
    var firstknot = 0.0f64
    var lastknot = 0.0f64
    let nn = f64(n0)
    if fractied > 0.0f64 && fractied < 1.0f64 {
        var mx = 0.0f64
        i = 1usize
        while i + 1usize < nxu {
            if cn[i] / nn > mx { mx = cn[i] / nn }
            i += 1usize
        }
        if mx < fractied {
            if cn[0usize] / nn >= fractied {
                firstknot = xu[1usize]
                have_first = true
                while lo < hi && xs[lo] <= firstknot { lo += 1usize }
                nke -= 1usize
            }
            if cn[nxu - 1usize] / nn >= fractied {
                lastknot = xu[nxu - 2usize]
                have_last = true
                while hi > lo && xs[hi - 1usize] >= lastknot { hi -= 1usize }
                nke -= 1usize
            }
        }
    }
    let xr = xs[lo..hi]
    let (knots, e4) = mem.alloc[f64](a, 2usize * nk + 4usize)
    if e4 != ok { ret 0usize }
    var nkn = 0usize
    if nke == 1usize {
        knots[0usize] = q7(xr, 0.5f64)
        nkn = 1usize
    } else {
        if nxu <= nke {
            i = 0usize
            while i < nxu {
                knots[i] = xu[i]
                i += 1usize
            }
            nkn = nxu
        } else {
            if nke == 2usize { seq_quantiles(xr, 0.5f64, 1.0f64 - outer, nke, knots) } else { seq_quantiles(xr, outer, 1.0f64 - outer, nke, knots) }
            nkn = nke
            var need = nke
            if need > 3usize { need = 3usize }
            if count_unique(knots, nkn) < need {
                seq_quantiles(xr, outer, 1.0f64 - outer, 2usize * nke, knots)
                nkn = 2usize * nke
                if have_first && count_unique(knots, nkn) < 3usize {
                    var midval = q7(xr, 0.5f64)
                    if have_first && have_last { midval = (firstknot + lastknot) / 2.0f64 }
                    knots[0usize] = firstknot
                    knots[1usize] = midval
                    if have_last { knots[2usize] = lastknot } else { knots[2usize] = q7(xr, 1.0f64 - outer) }
                    nkn = 3usize
                    // sort the three
                    var s1 = 0usize
                    while s1 < 3usize {
                        var s2 = s1 + 1usize
                        while s2 < 3usize {
                            if knots[s2] < knots[s1] {
                                let tt = knots[s1]
                                knots[s1] = knots[s2]
                                knots[s2] = tt
                            }
                            s2 += 1usize
                        }
                        s1 += 1usize
                    }
                }
                if count_unique(knots, nkn) < 3usize { ret 0usize }
            }
        }
        if xr.len < 100usize {
            if !have_first { knots[0usize] = xr[4usize] }
            if !have_last { knots[nke - 1usize] = xr[xr.len - 5usize] }
        }
    }
    // c(firstknot, knots, lastknot), sorted and unique
    var all_n = 0usize
    let (all, e5) = mem.alloc[f64](a, nkn + 2usize)
    if e5 != ok { ret 0usize }
    if have_first {
        all[all_n] = firstknot
        all_n += 1usize
    }
    i = 0usize
    while i < nkn {
        all[all_n] = knots[i]
        all_n += 1usize
        i += 1usize
    }
    if have_last {
        all[all_n] = lastknot
        all_n += 1usize
    }
    let (sa, e6) = sorted_of(a, all[0usize..all_n])
    if e6 != ok { ret 0usize }
    var c = 0usize
    i = 0usize
    while i < all_n {
        if c == 0usize || out[c - 1usize] != sa[i] {
            out[c] = sa[i]
            c += 1usize
        }
        i += 1usize
    }
    if c < 3usize { ret 0usize }
    ret c
}

// the pseudo-median (Hodges-Lehmann estimate) of x: the median of the Walsh averages (x_i + x_j) / 2, i <= j
fn pmedian(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    if n == 0usize { ret 0.0f64 / 0.0f64 }
    if n == 1usize { ret x[0usize] }
    let cnt = n * (n + 1usize) / 2usize
    let (w, e1) = mem.alloc[f64](a, cnt)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var c = 0usize
    var i = 0usize
    while i < n {
        var j = i
        while j < n {
            w[c] = (x[i] + x[j]) / 2.0f64
            c += 1usize
            j += 1usize
        }
        i += 1usize
    }
    let (s, e2) = sorted_of(a, w[0usize..cnt])
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    ret q7(s, 0.5f64)
}

// describe(x) of a numeric vector: out = (n, missing, distinct, Info, Mean, pMedian, Gmd, then the .05 .10 .25 .50 .75 .90 .95 quantiles, the five lowest and the five highest distinct values (L1 .. L5, H5 .. H1)); missing values are NaN
fn describe_numeric(a: *mem.Arena, x: []const f64, out: []f64) -> err {
    let (v, e1) = mem.alloc[f64](a, x.len + 1usize)
    if e1 != ok { ret e1 }
    var n = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] == x[i] {
            v[n] = x[i]
            n += 1usize
        }
        i += 1usize
    }
    let (s, e2) = sorted_of(a, v[0usize..n])
    if e2 != ok { ret e2 }
    var distinct = 0usize
    let (u, e3) = mem.alloc[f64](a, n + 1usize)
    if e3 != ok { ret e3 }
    i = 0usize
    while i < n {
        if distinct == 0usize || u[distinct - 1usize] != s[i] {
            u[distinct] = s[i]
            distinct += 1usize
        }
        i += 1usize
    }
    var sum = 0.0f64
    i = 0usize
    while i < n {
        sum += s[i]
        i += 1usize
    }
    out[0usize] = f64(n)
    out[1usize] = f64(x.len - n)
    out[2usize] = f64(distinct)
    out[3usize] = describe_info(a, v[0usize..n])
    out[4usize] = sum / f64(n)
    out[5usize] = pmedian(a, s)
    out[6usize] = gini_md(a, s)
    out[7usize] = q7(s, 0.05f64)
    out[8usize] = q7(s, 0.1f64)
    out[9usize] = q7(s, 0.25f64)
    out[10usize] = q7(s, 0.5f64)
    out[11usize] = q7(s, 0.75f64)
    out[12usize] = q7(s, 0.9f64)
    out[13usize] = q7(s, 0.95f64)
    i = 0usize
    while i < 10usize {
        out[14usize + i] = 0.0f64 / 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < 5usize && i < distinct {
        out[14usize + i] = u[i]
        out[23usize - i] = u[distinct - 1usize - i]
        i += 1usize
    }
    ret ok
}

// the smallest gap between the sorted distinct values of x and the extra values, over two
fn min_dif_half(a: *mem.Arena, x: []const f64, extra: []const f64) -> f64 {
    let (v, e1) = mem.alloc[f64](a, x.len + extra.len + 1usize)
    if e1 != ok { ret 0.0f64 }
    var n = 0usize
    var i = 0usize
    while i < x.len {
        if x[i] == x[i] {
            v[n] = x[i]
            n += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < extra.len {
        v[n] = extra[i]
        n += 1usize
        i += 1usize
    }
    let (sv, e2) = sorted_of(a, v[0usize..n])
    if e2 != ok { ret 0.0f64 }
    var md = 1.0e300f64
    i = 1usize
    while i < n {
        let d = sv[i] - sv[i - 1usize]
        if d > 0.0f64 && d < md { md = d }
        i += 1usize
    }
    ret md / 2.0f64
}

// cut2(x, g = g) codes (1-based interval of every x; the same as m = floor(n / g)): the largest i whose lower end low_i satisfies x >= low_i - min.dif
fn cut2_codes(a: *mem.Arena, x: []const f64, g: usize, out: []f64) -> err {
    let (lows, e1) = mem.alloc[f64](a, g + 2usize)
    if e1 != ok { ret e1 }
    let (cnt, nlow) = cut2_cuts_n(a, x, g, lows)
    let md = min_dif_half(a, x, lows[0usize..0usize])
    var k = 0usize
    while k < x.len {
        var code = 0.0f64
        var i = 0usize
        while i < nlow {
            if x[k] >= lows[i] - md { code = f64(i + 1usize) }
            i += 1usize
        }
        out[k] = code
        k += 1usize
    }
    ret ok
}

// cut2(x, cuts = cuts) codes with minmax = TRUE: cut(x, c(cuts - min.dif, last cut)) so the interval i holds k2_i < x <= k2_(i+1)
fn cut2_codes_cuts(a: *mem.Arena, x: []const f64, cuts: []const f64, out: []f64) -> err {
    var mn = 1.0e300f64
    var mx = 0.0f64 - 1.0e300f64
    var i = 0usize
    while i < x.len {
        if x[i] == x[i] {
            if x[i] < mn { mn = x[i] }
            if x[i] > mx { mx = x[i] }
        }
        i += 1usize
    }
    let (k, e1) = mem.alloc[f64](a, cuts.len + 3usize)
    if e1 != ok { ret e1 }
    var l = 0usize
    if mn < cuts[0usize] {
        k[l] = mn
        l += 1usize
    }
    i = 0usize
    while i < cuts.len {
        k[l] = cuts[i]
        l += 1usize
        i += 1usize
    }
    if mx > cuts[cuts.len - 1usize] {
        k[l] = mx
        l += 1usize
    }
    let md = min_dif_half(a, x, cuts)
    i = 0usize
    while i + 1usize < l {
        k[i] = k[i] - md
        i += 1usize
    }
    var q = 0usize
    while q < x.len {
        var code = 0.0f64
        i = 0usize
        while i + 1usize < l {
            if k[i] < x[q] { code = f64(i + 1usize) }
            i += 1usize
        }
        out[q] = code
        q += 1usize
    }
    ret ok
}

// the first canonical correlation of the column-major blocks x (n by kx) and y (n by ky), as stats::cancor computes it: the columns centred, an R qr of each with tolerance 1e-7, and the largest singular
// value of Qx' Qy over the ranks of the two blocks
fn cancor_first(a: *mem.Arena, xs: []const f64, kx: usize, ys: []const f64, ky: usize, n: usize) -> f64 {
    let (xc, e1) = mem.alloc[f64](a, n * kx + 1usize)
    let (yc, e2) = mem.alloc[f64](a, n * ky + 1usize)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < kx {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += xs[j * n + i]
            i += 1usize
        }
        m = m / f64(n)
        i = 0usize
        while i < n {
            xc[j * n + i] = xs[j * n + i] - m
            i += 1usize
        }
        j += 1usize
    }
    j = 0usize
    while j < ky {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += ys[j * n + i]
            i += 1usize
        }
        m = m / f64(n)
        i = 0usize
        while i < n {
            yc[j * n + i] = ys[j * n + i] - m
            i += 1usize
        }
        j += 1usize
    }
    let (fx, ex) = dc.qr(a, xc[0usize..n * kx], n, kx, 1.0e-7f64)
    let (fy, ey) = dc.qr(a, yc[0usize..n * ky], n, ky, 1.0e-7f64)
    if ex != ok || ey != ok { ret 0.0f64 / 0.0f64 }
    let dx = fx.rank
    let dy = fy.rank
    if dx == 0usize || dy == 0usize { ret 0.0f64 }
    let (qx, e3) = mem.alloc[f64](a, n * dx)
    let (qy, e4) = mem.alloc[f64](a, n * dy)
    let (mm, e5) = mem.alloc[f64](a, dx * dy)
    if e3 != ok || e4 != ok || e5 != ok { ret 0.0f64 / 0.0f64 }
    j = 0usize
    while j < dx {
        let col = qx[j * n..(j + 1usize) * n]
        var i = 0usize
        while i < n {
            col[i] = 0.0f64
            i += 1usize
        }
        col[j] = 1.0f64
        dc.qr_qy(&fx, col)
        j += 1usize
    }
    j = 0usize
    while j < dy {
        let col = qy[j * n..(j + 1usize) * n]
        var i = 0usize
        while i < n {
            col[i] = 0.0f64
            i += 1usize
        }
        col[j] = 1.0f64
        dc.qr_qy(&fy, col)
        j += 1usize
    }
    var p = 0usize
    while p < dx {
        var q = 0usize
        while q < dy {
            var s = 0.0f64
            var i = 0usize
            while i < n {
                s += qx[p * n + i] * qy[q * n + i]
                i += 1usize
            }
            mm[q * dx + p] = s
            q += 1usize
        }
        p += 1usize
    }
    let (sv, es) = dc.svd(a, mm, dx, dy)
    if es != ok { ret 0.0f64 / 0.0f64 }
    var best = 0.0f64
    var t = 0usize
    while t < sv.d.len {
        if sv.d[t] > best { best = sv.d[t] }
        t += 1usize
    }
    ret best
}

// redun(~ x1 + ... + xp, nk, tlinear, r2, type) for numeric and categorical variables: data is column-major n by p, kind 0 numeric and 1 categorical (integer codes); a numeric variable with at least three distinct values and nk > 0
// is expanded to the restricted cubic spline basis with the default knots (inclx), a categorical one to its level indicators (all but the first); the loop is the package one including the r2later check;
// order receives the removed variables (0-based) and rsq their R^2; returns the number removed, or -1 when a spline expansion cannot be made
fn redun_general(a: *mem.Arena, data: []const f64, kind: []const usize, n: usize, p: usize, nk: usize, tlinear: bool, r2: f64, adjusted: bool, order: []usize, rsq: []f64) -> i64 {
    let (st, e1) = mem.alloc[usize](a, p)
    let (en, e2) = mem.alloc[usize](a, p)
    let (vt, e3) = mem.alloc[usize](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret 0i64 - 1i64 }
    // widths: 1 for linear, the basis size for a spline, levels - 1 for a categorical variable
    var total = 0usize
    var v = 0usize
    let (kn, e4) = mem.alloc[f64](a, 2usize * nk + 12usize)
    if e4 != ok { ret 0i64 - 1i64 }
    let (wd, e5) = mem.alloc[usize](a, p)
    if e5 != ok { ret 0i64 - 1i64 }
    while v < p {
        let col = data[v * n..(v + 1usize) * n]
        if kind[v] == 1usize {
            var mx = 0usize
            var i = 0usize
            while i < n {
                if usize(col[i]) > mx { mx = usize(col[i]) }
                i += 1usize
            }
            vt[v] = 2usize
            wd[v] = mx - 1usize
        } else {
            let nu = count_unique(col, n)
            if nk == 0usize || nu < 3usize {
                vt[v] = 0usize
                wd[v] = 1usize
            } else {
                let c = rcspline_knots(a, col, nk, 0.05f64, kn)
                if c == 0usize { ret 0i64 - 1i64 }
                vt[v] = 1usize
                wd[v] = c - 1usize
            }
        }
        st[v] = total
        total += wd[v]
        en[v] = total
        v += 1usize
    }
    let (xm, e6) = mem.alloc[f64](a, n * total + 1usize)
    if e6 != ok { ret 0i64 - 1i64 }
    v = 0usize
    while v < p {
        let col = data[v * n..(v + 1usize) * n]
        let base = st[v]
        if vt[v] == 0usize {
            var i = 0usize
            while i < n {
                xm[base * n + i] = col[i]
                i += 1usize
            }
        } else if vt[v] == 2usize {
            var j = 0usize
            while j < wd[v] {
                var i = 0usize
                while i < n {
                    xm[(base + j) * n + i] = 0.0f64
                    if usize(col[i]) == j + 2usize { xm[(base + j) * n + i] = 1.0f64 }
                    i += 1usize
                }
                j += 1usize
            }
        } else {
            let c = rcspline_knots(a, col, nk, 0.05f64, kn)
            var i = 0usize
            while i < n {
                xm[base * n + i] = col[i]
                i += 1usize
            }
            let (bs, eb) = mem.alloc[f64](a, n * (c - 2usize) + 1usize)
            if eb != ok { ret 0i64 - 1i64 }
            rcspline_eval(col, kn[0usize..c], 2usize, bs)
            var j = 0usize
            while j + 2usize < c {
                i = 0usize
                while i < n {
                    xm[(base + 1usize + j) * n + i] = bs[j * n + i]
                    i += 1usize
                }
                j += 1usize
            }
        }
        v += 1usize
    }
    let (inn, e7) = mem.alloc[bool](a, p)
    let (outv, e8) = mem.alloc[bool](a, p)
    let (rs, e9) = mem.alloc[f64](a, p)
    let (lat, e10) = mem.alloc[f64](a, p)
    if e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret 0i64 - 1i64 }
    v = 0usize
    while v < p {
        inn[v] = true
        outv[v] = false
        v += 1usize
    }
    var removed = 0usize
    var step = 0usize
    while step < p {
        var left = 0usize
        v = 0usize
        while v < p {
            if inn[v] { left += 1usize }
            v += 1usize
        }
        if left < 2usize { break }
        var best = p
        var bestr = 0.0f64
        v = 0usize
        while v < p {
            if inn[v] {
                let mark = mem.mark(a)
                let rr = redun_fcan(a, xm, n, st, en, vt, inn, v, v, tlinear, adjusted, p)
                mem.reset(a, mark)
                rs[v] = rr
                if best == p || rr > bestr {
                    best = v
                    bestr = rr
                }
            }
            v += 1usize
        }
        if bestr < r2 { break }
        // the variables already removed must stay predictable once this one goes too
        var stop = false
        v = 0usize
        while v < p {
            if outv[v] {
                inn[best] = false
                let mark = mem.mark(a)
                let rr = redun_fcan(a, xm, n, st, en, vt, inn, v, v, tlinear, adjusted, p)
                mem.reset(a, mark)
                inn[best] = true
                lat[v] = rr
                if rr < r2 { stop = true }
            }
            v += 1usize
        }
        if stop { break }
        order[removed] = best
        rsq[removed] = bestr
        removed += 1usize
        inn[best] = false
        outv[best] = true
        step += 1usize
    }
    ret i64(removed)
}

// the R^2 of variable iy on the variables still in inn other than iy (the target iy itself when skip == iy is left out of the predictors)
fn redun_fcan(a: *mem.Arena, xm: []const f64, n: usize, st: []const usize, en: []const usize, vt: []const usize, inn: []const bool, iy: usize, skip: usize, tlinear: bool, adjusted: bool, p: usize) -> f64 {
    var kx = 0usize
    var v = 0usize
    while v < p {
        if inn[v] && v != skip { kx += en[v] - st[v] }
        v += 1usize
    }
    if kx == 0usize { ret 0.0f64 }
    let (xs, e1) = mem.alloc[f64](a, n * kx)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var c = 0usize
    v = 0usize
    while v < p {
        if inn[v] && v != skip {
            var j = st[v]
            while j < en[v] {
                var i = 0usize
                while i < n {
                    xs[c * n + i] = xm[j * n + i]
                    i += 1usize
                }
                c += 1usize
                j += 1usize
            }
        }
        v += 1usize
    }
    var ky = en[iy] - st[iy]
    if tlinear && vt[iy] == 1usize { ky = 1usize }
    let ys = xm[st[iy] * n..(st[iy] + ky) * n]
    let cor = cancor_first(a, xs, kx, ys, ky, n)
    var r2v = cor * cor
    if adjusted {
        let dof = f64(kx + ky) - 1.0f64
        r2v = 1.0f64 - (1.0f64 - r2v) * (f64(n) - 1.0f64) / (f64(n) - dof - 1.0f64)
        if r2v < 0.0f64 { r2v = 0.0f64 }
    }
    ret r2v
}
