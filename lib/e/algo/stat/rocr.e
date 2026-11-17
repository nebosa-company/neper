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
