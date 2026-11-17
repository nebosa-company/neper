// R Hmisc, the closed-form part: `binconf` (exact, Wilson and asymptotic binomial confidence limits),
// `wtd_mean`, `wtd_var` (unbiased), `somers2` (the concordance index C and Somers' Dxy of a 0/1 response,
// unweighted, ties by mid-ranks) and `rank_avg`.
//
// Also here: wtd.table, wtd.quantile, wtd.rank and the rcspline.eval basis.
//
// Not here: rcorr, hdquantile, cut2, rcspline.restate, describe, varclus,
// redun and the bootstrap summaries.

use e.math
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
fn cut2_cuts(a: *mem.Arena, x: []const f64, g: usize, out: []f64) -> usize {
    let n = x.len
    let (ones, e1) = mem.alloc[f64](a, n)
    let (xx, e2) = mem.alloc[f64](a, n)
    let (cn, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
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
    if e4 != ok { ret 0usize }
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
