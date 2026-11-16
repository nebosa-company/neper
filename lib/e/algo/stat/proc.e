// R pROC: the area under the ROC curve of a binary response and a predictor (direction chosen by the group medians, as direction = "auto"),
// its DeLong variance and confidence interval, and the paired DeLong test of two predictors on the same cases.
//
// Not here: smoothing, partial AUC, bootstrap methods, coords, the other roc.test methods and the multi-class AUC.

use e.math
use e.math.dist as dist
use e.mem

fn median_of(a: *mem.Arena, v: []const f64) -> f64 {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    i = 1usize
    while i < s.len {
        let t = s[i]
        var j = i
        while j > 0usize && s[j - 1usize] > t {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = t
        i += 1usize
    }
    if s.len % 2usize == 1usize { ret s[s.len / 2usize] }
    ret (s[s.len / 2usize - 1usize] + s[s.len / 2usize]) / 2.0f64
}

fn counts(y: []const f64) -> (usize, usize) {
    var nc = 0usize
    var nn = 0usize
    var i = 0usize
    while i < y.len {
        if y[i] > 0.5f64 { nc += 1usize } else { nn += 1usize }
        i += 1usize
    }
    ret (nc, nn)
}

// the placement values of a predictor: v10[i] over the cases, v01[j] over the controls; the area under the curve is returned
fn placements(a: *mem.Arena, y: []const f64, x: []const f64, v10: []f64, v01: []f64) -> f64 {
    let n = y.len
    let (nc, nn) = counts(y)
    let (cs, e1) = mem.alloc[f64](a, nc)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    let (ct, e2) = mem.alloc[f64](a, nn)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    var p = 0usize
    var q = 0usize
    var i = 0usize
    while i < n {
        if y[i] > 0.5f64 {
            cs[p] = x[i]
            p += 1usize
        } else {
            ct[q] = x[i]
            q += 1usize
        }
        i += 1usize
    }
    var sign = 1.0f64
    if median_of(a, ct) > median_of(a, cs) { sign = 0.0f64 - 1.0f64 }
    var total = 0.0f64
    i = 0usize
    while i < nc {
        v10[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nn {
        v01[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nc {
        var j = 0usize
        while j < nn {
            let d = sign * (cs[i] - ct[j])
            var psi = 0.0f64
            if d > 0.0f64 { psi = 1.0f64 }
            if d == 0.0f64 { psi = 0.5f64 }
            v10[i] += psi / f64(nn)
            v01[j] += psi / f64(nc)
            total += psi
            j += 1usize
        }
        i += 1usize
    }
    ret total / (f64(nc) * f64(nn))
}

fn cov_of(x: []const f64, y: []const f64) -> f64 {
    var mx = 0.0f64
    var my = 0.0f64
    var i = 0usize
    while i < x.len {
        mx += x[i]
        my += y[i]
        i += 1usize
    }
    mx = mx / f64(x.len)
    my = my / f64(x.len)
    var s = 0.0f64
    i = 0usize
    while i < x.len {
        s += (x[i] - mx) * (y[i] - my)
        i += 1usize
    }
    ret s / (f64(x.len) - 1.0f64)
}

// the area under the curve and its DeLong variance
fn auc_var(a: *mem.Arena, y: []const f64, x: []const f64) -> (f64, f64) {
    let (nc, nn) = counts(y)
    let (v10, e1) = mem.alloc[f64](a, nc)
    if e1 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let (v01, e2) = mem.alloc[f64](a, nn)
    if e2 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let auc = placements(a, y, x, v10, v01)
    ret (auc, cov_of(v10, v10) / f64(nc) + cov_of(v01, v01) / f64(nn))
}

// the paired DeLong statistic Z of two predictors, and the two-sided p value
fn delong_paired(a: *mem.Arena, y: []const f64, x1: []const f64, x2: []const f64) -> (f64, f64) {
    let (nc, nn) = counts(y)
    let (a10, e1) = mem.alloc[f64](a, nc)
    if e1 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let (a01, e2) = mem.alloc[f64](a, nn)
    if e2 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let (b10, e3) = mem.alloc[f64](a, nc)
    if e3 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let (b01, e4) = mem.alloc[f64](a, nn)
    if e4 != ok { ret (0.0f64 / 0.0f64, 0.0f64) }
    let auc1 = placements(a, y, x1, a10, a01)
    let auc2 = placements(a, y, x2, b10, b01)
    let m = f64(nc)
    let n = f64(nn)
    let v1 = cov_of(a10, a10) / m + cov_of(a01, a01) / n
    let v2 = cov_of(b10, b10) / m + cov_of(b01, b01) / n
    let c12 = cov_of(a10, b10) / m + cov_of(a01, b01) / n
    let z = (auc1 - auc2) / math.sqrt[f64](v1 + v2 - 2.0f64 * c12)
    ret (z, 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false))
}

// the DeLong confidence interval of the area under the curve, capped at 1
fn ci_delong(auc: f64, v: f64, level: f64) -> (f64, f64) {
    let z = dist.qnorm(1.0f64 - (1.0f64 - level) / 2.0f64, 0.0f64, 1.0f64, true, false)
    var hi = auc + z * math.sqrt[f64](v)
    if hi > 1.0f64 { hi = 1.0f64 }
    var lo = auc - z * math.sqrt[f64](v)
    if lo < 0.0f64 { lo = 0.0f64 }
    ret (lo, hi)
}
