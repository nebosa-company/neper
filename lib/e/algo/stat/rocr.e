// R ROCR: the performance measures of a binary classifier at every cutoff: the cutoffs are Inf and the distinct predictions in decreasing
// order, a cutoff predicts positive for scores >= it, and the measures follow ROCR's definitions.
//
// Not here: the other measures (rch, phi, cal, prbe, mxe, rmse, ecost), the cross-validation and averaging of several runs, and plots.

use e.algo.stat.pwr as pwr
use e.math
use e.mem

// the number of cutoffs for the predictions (distinct values plus the leading Inf)
fn cutoff_count(a: *mem.Arena, pred: []const f64) -> usize {
    let (s, e) = mem.alloc[f64](a, pred.len)
    if e != ok { ret 0usize }
    sorted_desc(pred, s)
    var c = 1usize
    var i = 1usize
    while i < s.len {
        if s[i] != s[i - 1usize] { c += 1usize }
        i += 1usize
    }
    ret c + 1usize
}

fn sorted_desc(pred: []const f64, s: []f64) {
    var i = 0usize
    while i < pred.len {
        s[i] = pred[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] < t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
}

// measure: 0 acc 1 err 2 fpr 3 tpr 4 fnr 5 tnr 6 prec 7 f (alpha 0.5) 8 lift 9 mat 10 sens 11 spec 12 npv 13 ppv
// writes the measure at every cutoff (NaN where undefined) into out, which needs cutoff_count entries; returns the count
fn measure(a: *mem.Arena, pred: []const f64, lab: []const f64, kind: usize, out: []f64) -> usize {
    let n = pred.len
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0usize }
    sorted_desc(pred, s)
    var npos = 0.0f64
    var nneg = 0.0f64
    var i = 0usize
    while i < n {
        if lab[i] > 0.5f64 { npos += 1.0f64 } else { nneg += 1.0f64 }
        i += 1usize
    }
    var count = 0usize
    var idx = 0usize
    var cut = 1.0e308f64 * 10.0f64
    var first = true
    while first || idx < n {
        if !first {
            cut = s[idx]
            while idx < n && s[idx] == cut { idx += 1usize }
        }
        first = false
        var tp = 0.0f64
        var fp = 0.0f64
        var k = 0usize
        while k < n {
            if pred[k] >= cut {
                if lab[k] > 0.5f64 { tp += 1.0f64 } else { fp += 1.0f64 }
            }
            k += 1usize
        }
        let fneg = npos - tp
        let tn = nneg - fp
        var v = 0.0f64 / 0.0f64
        if kind == 0usize { v = (tp + tn) / f64(n) }
        if kind == 1usize { v = (fp + fneg) / f64(n) }
        if kind == 2usize { v = fp / nneg }
        if kind == 3usize || kind == 10usize { v = tp / npos }
        if kind == 4usize { v = fneg / npos }
        if kind == 5usize || kind == 11usize { v = tn / nneg }
        if kind == 6usize || kind == 13usize { v = tp / (tp + fp) }
        if kind == 7usize {
            let pr = tp / (tp + fp)
            let rc = tp / npos
            v = 1.0f64 / (0.5f64 * (1.0f64 / pr) + 0.5f64 * (1.0f64 / rc))
        }
        if kind == 8usize { v = (tp / npos) / ((tp + fp) / f64(n)) }
        if kind == 9usize { v = (tp * tn - fp * fneg) / math.sqrt[f64]((tp + fneg) * (tn + fp) * (tp + fp) * (tn + fneg)) }
        if kind == 12usize { v = tn / (tn + fneg) }
        if kind == 14usize { v = (tp + fp) / f64(n) }
        if kind == 15usize { v = (tp * tn - fp * fneg) / math.sqrt[f64]((tp + fneg) * (tn + fp) * (tp + fp) * (tn + fneg)) }
        if kind == 16usize { v = (npos / f64(n)) * (fneg / npos) + (nneg / f64(n)) * (fp / nneg) }
        out[count] = v
        count += 1usize
    }
    ret count
}

// the area under the ROC curve by the trapezoid rule over the (fpr, tpr) points in cutoff order
fn auc(a: *mem.Arena, pred: []const f64, lab: []const f64) -> f64 {
    let m = cutoff_count(a, pred)
    let (fpr, e1) = mem.alloc[f64](a, m)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (tpr, e2) = mem.alloc[f64](a, m)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    let c1 = measure(a, pred, lab, 2usize, fpr)
    let c2 = measure(a, pred, lab, 3usize, tpr)
    if c1 != c2 { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    var i = 1usize
    while i < c1 {
        s += (fpr[i] - fpr[i - 1usize]) * (tpr[i] + tpr[i - 1usize]) / 2.0f64
        i += 1usize
    }
    ret s
}

// mxe: the mean cross entropy -1/n (sum of log p over the positives + sum of log (1 - p) over the negatives); predictions in [0, 1]
fn mxe(pred: []const f64, lab: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < pred.len {
        if lab[i] > 0.5f64 { s += math.log[f64](pred[i]) } else { s += math.log[f64](1.0f64 - pred[i]) }
        i += 1usize
    }
    ret 0.0f64 - s / f64(pred.len)
}

// rmse of the predictions against the 0 and 1 labels
fn rmse(pred: []const f64, lab: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < pred.len {
        var yv = 0.0f64
        if lab[i] > 0.5f64 { yv = 1.0f64 }
        s += (pred[i] - yv) * (pred[i] - yv)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(pred.len))
}

// performance(pred, "cal", window.size = w): for every window of w consecutive predictions (in decreasing order, equal predictions in reverse index order as `rev(order())` leaves them) the median
// prediction and the absolute difference between the positive fraction and the mean prediction; returns the number of windows
fn calibration(a: *mem.Arena, pred: []const f64, lab: []const f64, w: usize, med: []f64, er: []f64) -> usize {
    let n = pred.len
    let (ord, e1) = mem.alloc[usize](a, n)
    let (tmp, e2) = mem.alloc[f64](a, w)
    if e1 != ok || e2 != ok { ret 0usize }
    // order(pred) is a stable ascending sort; rev() of it is the descending order with ties reversed
    var i = 0usize
    while i < n {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < n {
        let key = ord[i]
        var j = i
        while j > 0usize && pred[ord[j - 1usize]] > pred[key] {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    var left = 0usize
    while left + w <= n {
        var pos = 0.0f64
        var sm = 0.0f64
        var k = 0usize
        while k < w {
            let idx = ord[n - 1usize - (left + k)]
            if lab[idx] > 0.5f64 { pos += 1.0f64 }
            sm += pred[idx]
            tmp[k] = pred[idx]
            k += 1usize
        }
        // the median of the window
        i = 1usize
        while i < w {
            let key = tmp[i]
            var j = i
            while j > 0usize && tmp[j - 1usize] > key {
                tmp[j] = tmp[j - 1usize]
                j -= 1usize
            }
            tmp[j] = key
            i += 1usize
        }
        var md = tmp[w / 2usize]
        if w % 2usize == 0usize { md = (tmp[w / 2usize - 1usize] + tmp[w / 2usize]) / 2.0f64 }
        er[left] = math.abs[f64](pos / f64(w) - sm / f64(w))
        med[left] = md
        left += 1usize
    }
    ret left
}

type PrbeCtx = struct { x0: f64, x1: f64, f0: f64, f1: f64 }

fn prbe_lin(c: *PrbeCtx, x: f64) -> f64 { ret c.f0 + (c.f1 - c.f0) * (x - c.x0) / (c.x1 - c.x0) }

// performance(pred, "prbe"): the cutoffs where recall and precision cross (the points where they are equal, and the roots of their linear interpolation between neighbouring cutoffs by uniroot) and the
// value R records there (the interpolant's residual, about zero); both lists in R's order (the reverse of the scan); returns the count
fn prbe(a: *mem.Arena, pred: []const f64, lab: []const f64, cut: []f64, val: []f64) -> usize {
    let m = cutoff_count(a, pred)
    let (rec, e1) = mem.alloc[f64](a, m)
    let (prc, e2) = mem.alloc[f64](a, m)
    let (cs, e3) = mem.alloc[f64](a, pred.len)
    let (al, e4) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0usize }
    let _r = measure(a, pred, lab, 3usize, rec)
    let _p = measure(a, pred, lab, 6usize, prc)
    sorted_desc(pred, cs)
    al[0usize] = 1.0e308f64 * 10.0f64
    var c = 1usize
    var i = 0usize
    while i < cs.len {
        if i == 0usize || cs[i] != cs[i - 1usize] {
            al[c] = cs[i]
            c += 1usize
        }
        i += 1usize
    }
    // reverse, keeping the finite entries
    let (x, e5) = mem.alloc[f64](a, m)
    let (y, e6) = mem.alloc[f64](a, m)
    let (aa, e7) = mem.alloc[f64](a, m)
    if e5 != ok || e6 != ok || e7 != ok { ret 0usize }
    var k = 0usize
    i = m
    while i > 0usize {
        i -= 1usize
        let xv = rec[i]
        let yv = prc[i]
        let av = al[i]
        if xv - xv == 0.0f64 && yv - yv == 0.0f64 && av - av == 0.0f64 {
            x[k] = xv
            y[k] = yv
            aa[k] = av
            k += 1usize
        }
    }
    var cnt = 0usize
    // the intersections are collected in scan order, then reversed
    let (tc, e8) = mem.alloc[f64](a, m + 1usize)
    let (tv, e9) = mem.alloc[f64](a, m + 1usize)
    if e8 != ok || e9 != ok { ret 0usize }
    if k < 2usize { ret 0usize }
    if x[0usize] - y[0usize] == 0.0f64 {
        tc[cnt] = aa[0usize]
        tv[cnt] = x[0usize]
        cnt += 1usize
    }
    i = 0usize
    while i + 1usize < k {
        let d0 = x[i] - y[i]
        let d1 = x[i + 1usize] - y[i + 1usize]
        if d1 == 0.0f64 {
            tc[cnt] = aa[i + 1usize]
            tv[cnt] = x[i + 1usize]
            cnt += 1usize
        } else if d0 * d1 < 0.0f64 {
            var cx = PrbeCtx{ x0: aa[i], x1: aa[i + 1usize], f0: d0, f1: d1 }
            let root = pwr.zeroin[PrbeCtx](&cx, prbe_lin, aa[i], aa[i + 1usize], 1.220703125e-4f64, 1000i64)
            tc[cnt] = root
            tv[cnt] = prbe_lin(&cx, root)
            cnt += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < cnt {
        cut[i] = tc[cnt - 1usize - i]
        val[i] = tv[cnt - 1usize - i]
        i += 1usize
    }
    ret cnt
}

// the (fpr, tpr) points of every cutoff
fn roc_points(a: *mem.Arena, pred: []const f64, lab: []const f64, fpr: []f64, tpr: []f64) -> usize {
    let c1 = measure(a, pred, lab, 2usize, fpr)
    let c2 = measure(a, pred, lab, 3usize, tpr)
    if c1 != c2 { ret 0usize }
    ret c1
}

fn cross3(ox: f64, oy: f64, ax: f64, ay: f64, bx: f64, by: f64) -> f64 { ret (ax - ox) * (by - oy) - (ay - oy) * (bx - ox) }

// performance(pred, "rch"): the vertices of the convex hull of the ROC points above the diagonal (x < y), with (0, 0) and (1, 1) added, in increasing x; returns the count
fn rocconvexhull(a: *mem.Arena, pred: []const f64, lab: []const f64, xo: []f64, yo: []f64) -> usize {
    let m = cutoff_count(a, pred)
    let (fx, e1) = mem.alloc[f64](a, m)
    let (fy, e2) = mem.alloc[f64](a, m)
    let (ord, e3) = mem.alloc[usize](a, m)
    let (hull, e4) = mem.alloc[usize](a, 2usize * m + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret 0usize }
    let k = roc_points(a, pred, lab, fx, fy)
    if k < 2usize { ret 0usize }
    let h = chull_set(a, fx[0usize..k], fy[0usize..k], hull)
    var i = 0usize
    var cnt = 0usize
    i = 0usize
    while i < h {
        if fx[hull[i]] < fy[hull[i]] {
            hull[cnt] = hull[i]
            cnt += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < cnt {
        let key = hull[i]
        var j = i
        while j > 0usize && fx[hull[j - 1usize]] > fx[key] {
            hull[j] = hull[j - 1usize]
            j -= 1usize
        }
        hull[j] = key
        i += 1usize
    }
    xo[0usize] = 0.0f64
    yo[0usize] = 0.0f64
    i = 0usize
    while i < cnt {
        xo[i + 1usize] = fx[hull[i]]
        yo[i + 1usize] = fy[hull[i]]
        i += 1usize
    }
    xo[cnt + 1usize] = 1.0f64
    yo[cnt + 1usize] = 1.0f64
    ret cnt + 2usize
}

// performance(pred, "ecost"): the lower envelope of the cost lines f_i(x) = fpr_i + (1 - tpr_i - fpr_i) x of the distinct ROC points, its corner points in increasing x; returns the count
fn expected_cost(a: *mem.Arena, pred: []const f64, lab: []const f64, xo: []f64, yo: []f64) -> usize {
    let m = cutoff_count(a, pred)
    let (fx, e1) = mem.alloc[f64](a, m + 2usize)
    let (fy, e2) = mem.alloc[f64](a, m + 2usize)
    let (ord, e3) = mem.alloc[usize](a, m + 2usize)
    let (gx, e4) = mem.alloc[f64](a, m + 2usize)
    let (gy, e5) = mem.alloc[f64](a, m + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret 0usize }
    let k = roc_points(a, pred, lab, fx, fy)
    if k < 2usize { ret 0usize }
    var i = 0usize
    while i < k {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < k {
        let key = ord[i]
        var j = i
        while j > 0usize && (fx[ord[j - 1usize]] > fx[key] || (fx[ord[j - 1usize]] == fx[key] && fy[ord[j - 1usize]] < fy[key])) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    var u = 0usize
    i = 0usize
    while i < k {
        if u == 0usize || fx[ord[i]] != gx[u - 1usize] {
            gx[u] = fx[ord[i]]
            gy[u] = fy[ord[i]]
            u += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < u {
        ord[i] = i
        i += 1usize
    }
    i = 1usize
    while i < u {
        let key = ord[i]
        var j = i
        while j > 0usize && (gy[ord[j - 1usize]] < gy[key] || (gy[ord[j - 1usize]] == gy[key] && gx[ord[j - 1usize]] > gx[key])) {
            ord[j] = ord[j - 1usize]
            j -= 1usize
        }
        ord[j] = key
        i += 1usize
    }
    var v = 0usize
    i = 0usize
    while i < u {
        if v == 0usize || gy[ord[i]] != fy[v - 1usize] {
            fx[v] = gx[ord[i]]
            fy[v] = gy[ord[i]]
            v += 1usize
        }
        i += 1usize
    }
    var has00 = false
    var has11 = false
    i = 0usize
    while i < v {
        if fx[i] == 0.0f64 && fy[i] == 0.0f64 { has00 = true }
        if fx[i] == 1.0f64 && fy[i] == 1.0f64 { has11 = true }
        i += 1usize
    }
    if !has00 {
        i = v
        while i > 0usize {
            fx[i] = fx[i - 1usize]
            fy[i] = fy[i - 1usize]
            i -= 1usize
        }
        fx[0usize] = 0.0f64
        fy[0usize] = 0.0f64
        v += 1usize
    }
    if !has11 {
        fx[v] = 1.0f64
        fy[v] = 1.0f64
        v += 1usize
    }
    // the cost lines as ROCR builds them: through (0, fpr) and (1, 1 - tpr) from the numbers pasted into source text, so to 15 significant digits
    var cnt = 0usize
    let (px, e6) = mem.alloc[f64](a, v * v + 2usize)
    let (py, e7) = mem.alloc[f64](a, v * v + 2usize)
    let (lm, e8) = mem.alloc[f64](a, v)
    let (lc, e9) = mem.alloc[f64](a, v)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret 0usize }
    var r0 = 0usize
    while r0 < v {
        let y1 = sig15(fx[r0])
        let y2 = sig15(1.0f64 - fy[r0])
        lm[r0] = (y2 - y1) / (1.0f64 - 0.0f64)
        lc[r0] = y1 - lm[r0] * 0.0f64
        r0 += 1usize
    }
    var s = 0usize
    while s + 1usize < v {
        var t = s + 1usize
        while t < v {
            var cx = LineCtx{ m1: lm[s], c1: lc[s], m2: lm[t], c2: lc[t] }
            let f1 = lm[s] * 1.0f64 + lc[s]
            let f0 = lc[s]
            let g1 = lm[t] * 1.0f64 + lc[t]
            let g0 = lc[t]
            if f1 - f0 != g1 - g0 {
                var imin = 0.0f64 - 1.0f64
                var imax = 1.0f64
                var guard = 0usize
                while sgn(line_h(&cx, imin)) == sgn(line_h(&cx, imax)) && guard < 2000usize {
                    imin = 2.0f64 * imin
                    imax = 2.0f64 * imax
                    guard += 1usize
                }
                let x = pwr.zeroin[LineCtx](&cx, line_h, imin - 1.0f64, imax + 1.0f64, 1.220703125e-4f64, 1000i64)
                let y = lm[s] * x + lc[s]
                if x - x == 0.0f64 && y - y == 0.0f64 {
                    var mn = 1.0e300f64
                    var r = 0usize
                    while r < v {
                        let val = lm[r] * x + lc[r]
                        if val < mn { mn = val }
                        r += 1usize
                    }
                    if math.abs[f64](y - mn) < 1.490116119384766e-8f64 {
                        px[cnt] = x
                        py[cnt] = y
                        cnt += 1usize
                    }
                }
            }
            t += 1usize
        }
        s += 1usize
    }
    var h00 = false
    var h10 = false
    i = 0usize
    while i < cnt {
        if px[i] == 0.0f64 && py[i] == 0.0f64 { h00 = true }
        if px[i] == 1.0f64 && py[i] == 0.0f64 { h10 = true }
        i += 1usize
    }
    if !h00 {
        i = cnt
        while i > 0usize {
            px[i] = px[i - 1usize]
            py[i] = py[i - 1usize]
            i -= 1usize
        }
        px[0usize] = 0.0f64
        py[0usize] = 0.0f64
        cnt += 1usize
    }
    if !h10 {
        px[cnt] = 1.0f64
        py[cnt] = 0.0f64
        cnt += 1usize
    }
    i = 1usize
    while i < cnt {
        let kx = px[i]
        let ky = py[i]
        var j = i
        while j > 0usize && px[j - 1usize] > kx {
            px[j] = px[j - 1usize]
            py[j] = py[j - 1usize]
            j -= 1usize
        }
        px[j] = kx
        py[j] = ky
        i += 1usize
    }
    i = 0usize
    while i < cnt {
        xo[i] = px[i]
        yo[i] = py[i]
        i += 1usize
    }
    ret cnt
}

// ---- R's chull (grDevices): Eddy's algorithm 523, ported with its floating-point tests, so the near-collinear points the ROC grid produces are kept or dropped as R does ----

type ChSplit = struct { na: i64, maxa: i64, nb: i64, maxb: i64 }

// split(): the m points whose 1-based subscripts are src[s0 .. s0 + m - 1] are partitioned by the line through points ii and jj (1-based) of (x, y): the ones above go to dst[a0 ..], the ones below to dst[b0 ..]
// (s = 2 drops the below set, s = -2 the above set); maxa and maxb are the 1-based positions of the farthest point of each set (the last one among equals), 0 when empty
fn ch_split(xs: []const f64, ys: []const f64, m: i64, src: []const i64, s0: i64, ii: i64, jj: i64, s: i64, dst: []i64, a0: i64, b0: i64) -> ChSplit {
    var r = ChSplit{ na: 0i64, maxa: 0i64, nb: 0i64, maxb: 0i64 }
    let xt = xs[usize(ii - 1i64)]
    let vert = xs[usize(jj - 1i64)] == xt
    let d1 = ys[usize(jj - 1i64)] - ys[usize(ii - 1i64)]
    var neg_dir = false
    var a = 0.0f64
    var b = 0.0f64
    if vert {
        neg_dir = (s > 0i64 && d1 < 0.0f64) || (s < 0i64 && d1 > 0.0f64)
    } else {
        a = d1 / (xs[usize(jj - 1i64)] - xt)
        b = ys[usize(ii - 1i64)] - a * xt
    }
    var up = 0.0f64
    var down = 0.0f64
    var i = 0i64
    while i < m {
        let is = src[usize(s0 + i - 1i64)]
        var z = 0.0f64
        if vert {
            if neg_dir { z = xt - xs[usize(is - 1i64)] } else { z = xs[usize(is - 1i64)] - xt }
        } else {
            z = ys[usize(is - 1i64)] - a * xs[usize(is - 1i64)] - b
        }
        if z > 0.0f64 {
            if s != -2i64 {
                dst[usize(a0 + r.na - 1i64)] = is
                r.na += 1i64
                if z >= up {
                    up = z
                    r.maxa = r.na
                }
            }
        } else if s != 2i64 && z < 0.0f64 {
            dst[usize(b0 + r.nb - 1i64)] = is
            r.nb += 1i64
            if z <= down {
                down = z
                r.maxb = r.nb
            }
        }
        i += 1i64
    }
    ret r
}

// the 0-based indices of the hull vertices of the n points (xs, ys), in the order the algorithm finds them (the order R then rearranges counter-clockwise); returns the count
fn chull_set(a: *mem.Arena, xs: []const f64, ys: []const f64, out: []usize) -> usize {
    let n = i64(xs.len)
    let (buf, e1) = mem.alloc[i64](a, usize(4i64 * n + 8i64))
    let (inn, e2) = mem.alloc[i64](a, usize(n + 2i64))
    if e1 != ok || e2 != ok { ret 0usize }
    var q = 0i64
    while q < n {
        inn[usize(q)] = q + 1i64
        q += 1i64
    }
    // 1-based views: ih(k) = buf[k - 1], ia(k) = buf[n + k - 1], ib(k) = buf[2 n + k - 1], il(k) = buf[3 n + k - 1]
    let m = n
    var nh = 0i64
    if m == 1i64 {
        out[0usize] = 0usize
        ret 1usize
    }
    buf[usize(3i64 * n)] = 2i64
    buf[usize(3i64 * n + 1i64)] = 1i64
    var kn = inn[0usize]
    var kx = inn[1usize]
    var min = 1i64
    var mx = 1i64
    var maxe = false
    var mine = false
    var vertical = false
    if m == 2i64 {
        out[0usize] = usize(kx - 1i64)
        out[1usize] = usize(kn - 1i64)
        if xs[usize(kn - 1i64)] == xs[usize(kx - 1i64)] && ys[usize(kn - 1i64)] == ys[usize(kx - 1i64)] { ret 1usize }
        ret 2usize
    }
    let mp1 = m + 1i64
    kx = inn[0usize]
    var i = 2i64
    while i <= m {
        let j = inn[usize(i - 1i64)]
        let d1 = xs[usize(j - 1i64)] - xs[usize(kx - 1i64)]
        if d1 < 0.0f64 {
        } else if d1 == 0.0f64 {
            maxe = true
        } else {
            maxe = false
            mx = i
            kx = j
        }
        let d2 = xs[usize(j - 1i64)] - xs[usize(kn - 1i64)]
        if d2 < 0.0f64 {
            mine = false
            min = i
            kn = j
        } else if d2 == 0.0f64 {
            mine = true
        }
        i += 1i64
    }
    if kx == kn { vertical = true }
    if vertical {
        kx = inn[0usize]
        kn = inn[0usize]
        i = 1i64
        while i <= m {
            let j = inn[usize(i - 1i64)]
            if ys[usize(j - 1i64)] > ys[usize(kx - 1i64)] {
                mx = i
                kx = j
            }
            if ys[usize(j - 1i64)] < ys[usize(kn - 1i64)] {
                min = i
                kn = j
            }
            i += 1i64
        }
        out[0usize] = usize(kx - 1i64)
        if kx == kn { ret 1usize }
        out[1usize] = usize(kn - 1i64)
        if xs[usize(kn - 1i64)] == xs[usize(kx - 1i64)] && ys[usize(kn - 1i64)] == ys[usize(kx - 1i64)] { ret 1usize }
        ret 2usize
    }
    if maxe {
        i = 1i64
        while i <= m {
            let j = inn[usize(i - 1i64)]
            if xs[usize(j - 1i64)] == xs[usize(kx - 1i64)] && ys[usize(j - 1i64)] > ys[usize(kx - 1i64)] {
                mx = i
                kx = j
            }
            i += 1i64
        }
    }
    if mine {
        i = 1i64
        while i <= m {
            let j = inn[usize(i - 1i64)]
            if xs[usize(j - 1i64)] == xs[usize(kn - 1i64)] && ys[usize(j - 1i64)] < ys[usize(kn - 1i64)] {
                min = i
                kn = j
            }
            i += 1i64
        }
    }
    buf[0usize] = kx
    buf[1usize] = kn
    nh = 3i64
    var inh = 1i64
    var nib = 1i64
    var ma = m
    inn[usize(mx - 1i64)] = inn[usize(m - 1i64)]
    inn[usize(m - 1i64)] = kx
    let mm = m - 2i64
    if min == m { min = mx }
    inn[usize(min - 1i64)] = inn[usize(m - 2i64)]
    inn[usize(m - 2i64)] = kn
    let IA = n
    let IB = 2i64 * n
    let IL = 3i64 * n
    // the first split of the root
    var sp = ch_split(xs, ys, mm, inn, 1i64, buf[0usize], buf[1usize], 0i64, buf, IA + 1i64, IB + 1i64)
    var mb = sp.na
    var mxa = sp.maxa
    buf[usize(IA + ma - 1i64)] = sp.nb
    var mxbb = sp.maxb
    var mxb = 0i64
    var mbb = 0i64
    // the left half of the tree
    var stage = 8i64
    while stage == 8i64 {
        nib += buf[usize(IA + ma - 1i64)]
        ma -= 1i64
        var again = false
        while !again && stage == 8i64 {
            if mxa != 0i64 {
                buf[usize(IL + nh - 1i64)] = buf[usize(IL + inh - 1i64)]
                buf[usize(IL + inh - 1i64)] = nh
                buf[usize(nh - 1i64)] = buf[usize(IA + mxa - 1i64)]
                buf[usize(IA + mxa - 1i64)] = buf[usize(IA + mb - 1i64)]
                mb -= 1i64
                nh += 1i64
                if mb != 0i64 {
                    let ilinh = buf[usize(IL + inh - 1i64)]
                    sp = ch_split(xs, ys, mb, buf, IA + 1i64, buf[usize(inh - 1i64)], buf[usize(ilinh - 1i64)], 1i64, buf, IA + 1i64, IB + nib)
                    mbb = sp.na
                    mxa = sp.maxa
                    buf[usize(IA + ma - 1i64)] = sp.nb
                    mxb = sp.maxb
                    mb = mbb
                    again = true
                } else {
                    inh = buf[usize(IL + inh - 1i64)]
                }
            }
            if !again {
                var more = true
                while more {
                    inh = buf[usize(IL + inh - 1i64)]
                    ma += 1i64
                    nib -= buf[usize(IA + ma - 1i64)]
                    if ma >= m {
                        stage = 12i64
                        more = false
                    } else if buf[usize(IA + ma - 1i64)] != 0i64 {
                        more = false
                    }
                }
                if stage == 8i64 {
                    let ilinh = buf[usize(IL + inh - 1i64)]
                    sp = ch_split(xs, ys, buf[usize(IA + ma - 1i64)], buf, IB + nib, buf[usize(inh - 1i64)], buf[usize(ilinh - 1i64)], 2i64, buf, IA + 1i64, IB + nib)
                    mb = sp.na
                    mxa = sp.maxa
                    mbb = sp.nb
                    mxb = sp.maxb
                    buf[usize(IA + ma - 1i64)] = mbb
                }
            }
        }
    }
    // the right half of the tree
    mxb = mxbb
    ma = m
    mb = buf[usize(IA + ma - 1i64)]
    var nia = 1i64
    buf[usize(IA + ma - 1i64)] = 0i64
    var done = false
    while !done {
        nia += buf[usize(IA + ma - 1i64)]
        ma -= 1i64
        var again2 = false
        while !again2 && !done {
            if mxb != 0i64 {
                buf[usize(IL + nh - 1i64)] = buf[usize(IL + inh - 1i64)]
                buf[usize(IL + inh - 1i64)] = nh
                buf[usize(nh - 1i64)] = buf[usize(IB + mxb - 1i64)]
                buf[usize(IB + mxb - 1i64)] = buf[usize(IB + mb - 1i64)]
                mb -= 1i64
                nh += 1i64
                if mb != 0i64 {
                    let ilinh = buf[usize(IL + inh - 1i64)]
                    sp = ch_split(xs, ys, mb, buf, IB + nib, buf[usize(inh - 1i64)], buf[usize(ilinh - 1i64)], 0i64 - 1i64, buf, IA + nia, IB + nib)
                    buf[usize(IA + ma - 1i64)] = sp.na
                    mxa = sp.maxa
                    mbb = sp.nb
                    mxb = sp.maxb
                    mb = mbb
                    again2 = true
                } else {
                    inh = buf[usize(IL + inh - 1i64)]
                }
            }
            if !again2 {
                var more2 = true
                while more2 {
                    inh = buf[usize(IL + inh - 1i64)]
                    ma += 1i64
                    if ma == mp1 {
                        done = true
                        more2 = false
                    } else {
                        nia -= buf[usize(IA + ma - 1i64)]
                        if buf[usize(IA + ma - 1i64)] != 0i64 { more2 = false }
                    }
                }
                if !done {
                    let ilinh = buf[usize(IL + inh - 1i64)]
                    sp = ch_split(xs, ys, buf[usize(IA + ma - 1i64)], buf, IA + nia, buf[usize(inh - 1i64)], buf[usize(ilinh - 1i64)], 0i64 - 2i64, buf, IA + nia, IB + nib)
                    mbb = sp.na
                    mxa = sp.maxa
                    mb = sp.nb
                    mxb = sp.maxb
                }
            }
        }
    }
    nh -= 1i64
    var k = 0i64
    while k < nh {
        out[usize(k)] = usize(buf[usize(k)] - 1i64)
        k += 1i64
    }
    ret usize(nh)
}

type LineCtx = struct { m1: f64, c1: f64, m2: f64, c2: f64 }

fn line_h(c: *LineCtx, x: f64) -> f64 { ret (c.m1 * x + c.c1) - (c.m2 * x + c.c2) }

fn sgn(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

// a number as R's paste() prints it, 15 significant digits, read back
fn sig15(v: f64) -> f64 {
    if v == 0.0f64 { ret 0.0f64 }
    let e = math.floor[f64](math.log10[f64](math.abs[f64](v)))
    let p = math.pow[f64](10.0f64, 14.0f64 - e)
    ret math.round[f64](v * p) / p
}
