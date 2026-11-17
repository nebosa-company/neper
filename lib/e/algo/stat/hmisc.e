// R Hmisc, the closed-form part: `binconf` (exact, Wilson and asymptotic binomial confidence limits),
// `wtd_mean`, `wtd_var` (unbiased), `somers2` (the concordance index C and Somers' Dxy of a 0/1 response,
// unweighted, ties by mid-ranks) and `rank_avg`.
//
// Also here: wtd.table, wtd.quantile, wtd.rank and the rcspline.eval basis.
//
// Not here: rcorr, hdquantile, cut2, rcspline.restate, describe, varclus,
// redun and the bootstrap summaries.

use e.math
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
