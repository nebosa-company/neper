// R pROC: the area under the ROC curve of a binary response and a predictor (direction chosen by the group medians, as direction = "auto"),
// its DeLong variance and confidence interval, and the paired DeLong test of two predictors on the same cases.
//
// Not here: smoothing, partial AUC, bootstrap methods, coords, the other roc.test methods and the multi-class AUC.

use e.algo.rand.r as rng
use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
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

// the direction of roc(direction = "auto"): true when the cases are expected higher ("<"), i.e. median(controls) <= median(cases)
fn cases_higher(a: *mem.Arena, y: []const f64, x: []const f64) -> bool {
    let (nc, nn) = counts(y)
    let (cs, e1) = mem.alloc[f64](a, nc)
    if e1 != ok { ret true }
    let (ct, e2) = mem.alloc[f64](a, nn)
    if e2 != ok { ret true }
    var p = 0usize
    var q = 0usize
    var i = 0usize
    while i < y.len {
        if y[i] > 0.5f64 {
            cs[p] = x[i]
            p += 1usize
        } else {
            ct[q] = x[i]
            q += 1usize
        }
        i += 1usize
    }
    ret median_of(a, ct) <= median_of(a, cs)
}

// sensitivity and specificity of the rule at threshold t (the direction from cases_higher)
fn coords_at(y: []const f64, x: []const f64, higher: bool, t: f64) -> (f64, f64) {
    var hit = 0.0f64
    var ok_n = 0.0f64
    var nc = 0.0f64
    var nn = 0.0f64
    var i = 0usize
    while i < y.len {
        if y[i] > 0.5f64 {
            nc += 1.0f64
            if higher && x[i] > t { hit += 1.0f64 }
            if !higher && x[i] < t { hit += 1.0f64 }
        } else {
            nn += 1.0f64
            if higher && x[i] <= t { ok_n += 1.0f64 }
            if !higher && x[i] >= t { ok_n += 1.0f64 }
        }
        i += 1usize
    }
    ret (hit / nc, ok_n / nn)
}

// the curve of coords(r, "all"): thresholds are -Inf, the midpoints of consecutive distinct values, Inf; returns their count and the sums of sensitivity, specificity and the finite thresholds
fn roc_sums(a: *mem.Arena, y: []const f64, x: []const f64) -> (f64, f64, f64, f64) {
    let higher = cases_higher(a, y, x)
    let (u, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (0.0f64, 0.0f64, 0.0f64, 0.0f64) }
    var i = 0usize
    while i < x.len {
        u[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < u.len {
        let t = u[i]
        var j = i
        while j > 0usize && u[j - 1usize] > t {
            u[j] = u[j - 1usize]
            j -= 1usize
        }
        u[j] = t
        i += 1usize
    }
    var k = 0usize
    i = 0usize
    while i < u.len {
        if i == 0usize || u[i] != u[i - 1usize] {
            u[k] = u[i]
            k += 1usize
        }
        i += 1usize
    }
    let inf = 1.0f64 / 0.0f64
    var ss = 0.0f64
    var sp = 0.0f64
    var st = 0.0f64
    var cnt = 0.0f64
    var j = 0usize
    while j <= k {
        var t = inf
        if j == 0usize { t = 0.0f64 - inf } else if j < k { t = (u[j - 1usize] + u[j]) / 2.0f64 }
        let (se, sc) = coords_at(y, x, higher, t)
        ss += se
        sp += sc
        if j > 0usize && j < k { st += t }
        cnt += 1.0f64
        j += 1usize
    }
    ret (cnt, ss, sp, st)
}

// coords(r, "best", best.method, best.weights = c(cost, prev)): method 0 "youden" (se + r sp), 1 "closest.topleft"; returns the number of thresholds attaining the maximum, the lowest of them and the maximum criterion
fn roc_best(a: *mem.Arena, y: []const f64, x: []const f64, cost: f64, prev: f64, method: usize) -> (f64, f64, f64) {
    let nan = 0.0f64 / 0.0f64
    let higher = cases_higher(a, y, x)
    let r = (1.0f64 - prev) / (cost * prev)
    let (u, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (nan, nan, nan) }
    var i = 0usize
    while i < x.len {
        u[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < u.len {
        let t = u[i]
        var j = i
        while j > 0usize && u[j - 1usize] > t {
            u[j] = u[j - 1usize]
            j -= 1usize
        }
        u[j] = t
        i += 1usize
    }
    var k = 0usize
    i = 0usize
    while i < u.len {
        if i == 0usize || u[i] != u[i - 1usize] {
            u[k] = u[i]
            k += 1usize
        }
        i += 1usize
    }
    let inf = 1.0f64 / 0.0f64
    var best = 0.0f64 - inf
    var cnt = 0.0f64
    var first = nan
    var j = 0usize
    while j <= k {
        var t = inf
        if j == 0usize { t = 0.0f64 - inf } else if j < k { t = (u[j - 1usize] + u[j]) / 2.0f64 }
        let (se, sp) = coords_at(y, x, higher, t)
        var crit = se + r * sp
        if method == 1usize { crit = 0.0f64 - ((1.0f64 - se) * (1.0f64 - se) + r * (1.0f64 - sp) * (1.0f64 - sp)) }
        if crit > best {
            best = crit
            cnt = 1.0f64
            first = t
        } else if crit == best {
            cnt += 1.0f64
        }
        j += 1usize
    }
    ret (cnt, first, best)
}

// auc(r, partial.auc = c(hi, lo), partial.auc.focus, partial.auc.correct) on the curve of roc(): focus 0 specificity, 1 sensitivity; hi >= lo within [0, 1]; NaN where R gives NA
fn partial_auc(a: *mem.Arena, y: []const f64, x: []const f64, hi: f64, lo: f64, focus: usize, correct: bool) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let higher = cases_higher(a, y, x)
    let (u, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret nan }
    var i = 0usize
    while i < x.len {
        u[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < u.len {
        let t = u[i]
        var j = i
        while j > 0usize && u[j - 1usize] > t {
            u[j] = u[j - 1usize]
            j -= 1usize
        }
        u[j] = t
        i += 1usize
    }
    var k = 0usize
    i = 0usize
    while i < u.len {
        if i == 0usize || u[i] != u[i - 1usize] {
            u[k] = u[i]
            k += 1usize
        }
        i += 1usize
    }
    let inf = 1.0f64 / 0.0f64
    let np = k + 1usize
    let (se, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret nan }
    let (sp, e2) = mem.alloc[f64](a, np)
    if e2 != ok { ret nan }
    var j = 0usize
    while j <= k {
        var t = inf
        if j == 0usize { t = 0.0f64 - inf } else if j < k { t = (u[j - 1usize] + u[j]) / 2.0f64 }
        let (s1, s2) = coords_at(y, x, higher, t)
        // sort_roc: specificities ascending
        var at = j
        if !higher { at = k - j }
        se[at] = s1
        sp[at] = s2
        j += 1usize
    }
    let (px, e3) = mem.alloc[f64](a, np)
    if e3 != ok { ret nan }
    let (py, e4) = mem.alloc[f64](a, np)
    if e4 != ok { ret nan }
    i = 0usize
    while i < np {
        if focus == 1usize {
            px[i] = se[np - 1usize - i]
            py[i] = sp[np - 1usize - i]
        } else {
            px[i] = sp[i]
            py[i] = se[i]
        }
        i += 1usize
    }
    var auc = 0.0f64
    var first = np
    var last = 0usize
    var cnt = 0usize
    var has_hi = false
    var has_lo = false
    i = 0usize
    while i < np {
        if px[i] <= hi && px[i] >= lo {
            if cnt == 0usize { first = i }
            last = i
            cnt += 1usize
            if px[i] == hi { has_hi = true }
            if px[i] == lo { has_lo = true }
        }
        i += 1usize
    }
    if cnt > 0usize {
        i = first
        while i < last {
            auc += (py[i + 1usize] + py[i]) / 2.0f64 * (px[i + 1usize] - px[i])
            i += 1usize
        }
    }
    if cnt == 0usize {
        var ih = 0usize
        while ih < np && px[ih] < hi { ih += 1usize }
        let il = ih - 1usize
        let ph = (px[ih] - hi) / (px[ih] - px[il])
        let pl = (lo - px[il]) / (px[ih] - px[il])
        let yh = py[ih] + ph * (py[il] - py[ih])
        let yl = py[il] - pl * (py[il] - py[ih])
        auc = (yh + yl) / 2.0f64 * (hi - lo)
    } else {
        if !has_hi {
            var io = 0usize
            while io < np && px[io] < hi { io += 1usize }
            let ii = io - 1usize
            let pr = (hi - px[io]) / (px[ii] - px[io])
            let yi = py[io] + pr * (py[ii] - py[io])
            auc += (hi - px[ii]) * (py[ii] + yi) / 2.0f64
        }
        if !has_lo {
            var io = 0usize
            while io < np && !(px[io] > lo) { io += 1usize }
            io -= 1usize
            let ii = io + 1usize
            let pr = (px[ii] - lo) / (px[ii] - px[io])
            let yi = py[ii] + pr * (py[io] - py[ii])
            auc += (px[ii] - lo) * (py[ii] + yi) / 2.0f64
        }
    }
    if correct {
        let mn = ((1.0f64 - hi) + (1.0f64 - lo)) * (hi - lo) / 2.0f64
        let mx = hi - lo
        if auc < mn { ret nan }
        auc = (1.0f64 + (auc - mn) / (mx - mn)) / 2.0f64
    }
    ret auc
}

// multiclass.roc(response, predictor) on a single predictor: the mean of the pairwise AUCs (direction chosen per pair), classes coded 0 .. k - 1 in the response
fn multiclass_auc(a: *mem.Arena, cls: []const f64, x: []const f64, k: usize) -> f64 {
    let n = cls.len
    let (ys, e1) = mem.alloc[f64](a, n)
    let (xs, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var sum = 0.0f64
    var i = 0usize
    while i < k {
        var j = i + 1usize
        while j < k {
            var m = 0usize
            var q = 0usize
            while q < n {
                let c = usize(cls[q])
                if c == i || c == j {
                    xs[m] = x[q]
                    if c == j { ys[m] = 1.0f64 } else { ys[m] = 0.0f64 }
                    m += 1usize
                }
                q += 1usize
            }
            let (au, av) = auc_var(a, ys[0usize..m], xs[0usize..m])
            sum += au
            j += 1usize
        }
        i += 1usize
    }
    ret 2.0f64 * sum / (f64(k) * f64(k - 1usize))
}

// roc.test(r1, r2, method = "delong", paired = FALSE): the t statistic (auc1 - auc2) / sqrt(var1 + var2) of two curves from independent samples and its two-sided p value on the Welch degrees of freedom
fn delong_unpaired(a: *mem.Arena, y1: []const f64, x1: []const f64, y2: []const f64, x2: []const f64) -> (f64, f64) {
    let (a1, v1) = auc_var(a, y1, x1)
    let (a2, v2) = auc_var(a, y2, x2)
    let z = (a1 - a2) / math.sqrt[f64](v1 + v2)
    let df = (v1 + v2) * (v1 + v2) / (v1 * v1 / f64(y1.len - 1usize) + v2 * v2 / f64(y2.len - 1usize))
    ret (z, 2.0f64 * nb.pt(0.0f64 - math.abs[f64](z), df, true, false))
}

// ---- ci.auc by bootstrap ----

// the area under the curve of a resample (controls, cases) when cases tend to be higher (direction "<") or lower: the share of case-control pairs ordered the right way, ties half
fn auc_pairs(cs: []const f64, ct: []const f64, higher: bool) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cs.len {
        var j = 0usize
        while j < ct.len {
            var a = cs[i]
            var b = ct[j]
            if !higher {
                a = ct[j]
                b = cs[i]
            }
            if a > b { s += 1.0f64 } else if a == b { s += 0.5f64 }
            j += 1usize
        }
        i += 1usize
    }
    ret s / f64(cs.len * ct.len)
}

// R's quantile(x, p) type 7 of a sorted vector
fn quantile7(s: []const f64, p: f64) -> f64 {
    let h = f64(s.len - 1usize) * p
    let lo = math.floor[f64](h)
    let hi = math.ceil[f64](h)
    var q = s[usize(lo)]
    if h > lo { q += (h - lo) * (s[usize(hi)] - s[usize(lo)]) }
    ret q
}

// ci.auc(roc, method = "bootstrap", boot.n, boot.stratified) after set.seed(seed): per replicate (stratified) the controls then the cases are resampled with replacement (`sample(x, replace = TRUE)`), (non-stratified) the
// observations; the direction is the original's; out receives the 2.5%, 50% and 97.5% quantiles (the level's tails)
fn ci_auc_boot(a: *mem.Arena, y: []const f64, x: []const f64, boot_n: usize, seed: i64, level: f64, stratified: bool, out: []f64) -> err {
    let (nc, nn) = counts(y)
    let higher = cases_higher(a, y, x)
    let n = y.len
    let (cs, e1) = mem.alloc[f64](a, nc)
    let (ct, e2) = mem.alloc[f64](a, nn)
    let (rc, e3) = mem.alloc[f64](a, nc + nn)
    let (rt, e4) = mem.alloc[f64](a, nc + nn)
    let (aucs, e5) = mem.alloc[f64](a, boot_n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret mem.Full }
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
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    var nv = 0usize
    var b = 0usize
    while b < boot_n {
        var mc = 0usize
        var mt = 0usize
        if stratified {
            let (ic, f1) = rng.sample_int(a, &r, i64(nn), i64(nn), true)
            if f1 != ok { ret f1 }
            let (is, f2) = rng.sample_int(a, &r, i64(nc), i64(nc), true)
            if f2 != ok { ret f2 }
            i = 0usize
            while i < nn {
                rt[i] = ct[usize(ic[i]) - 1usize]
                i += 1usize
            }
            i = 0usize
            while i < nc {
                rc[i] = cs[usize(is[i]) - 1usize]
                i += 1usize
            }
            mc = nc
            mt = nn
        } else {
            let (ix, f3) = rng.sample_int(a, &r, i64(n), i64(n), true)
            if f3 != ok { ret f3 }
            i = 0usize
            while i < n {
                let k = usize(ix[i]) - 1usize
                if y[k] > 0.5f64 {
                    rc[mc] = x[k]
                    mc += 1usize
                } else {
                    rt[mt] = x[k]
                    mt += 1usize
                }
                i += 1usize
            }
        }
        if mc > 0usize && mt > 0usize {
            aucs[nv] = auc_pairs(rc[0usize..mc], rt[0usize..mt], higher)
            nv += 1usize
        }
        b += 1usize
    }
    // sort the replicates
    i = 1usize
    while i < nv {
        let key = aucs[i]
        var j = i
        while j > 0usize && aucs[j - 1usize] > key {
            aucs[j] = aucs[j - 1usize]
            j -= 1usize
        }
        aucs[j] = key
        i += 1usize
    }
    let tail = (1.0f64 - level) / 2.0f64
    out[0usize] = quantile7(aucs[0usize..nv], tail)
    out[1usize] = quantile7(aucs[0usize..nv], 0.5f64)
    out[2usize] = quantile7(aucs[0usize..nv], 1.0f64 - tail)
    ret ok
}

// ---- smooth(roc, method = "binormal") ----

// the binormal fit: sp' = a + b se' (least squares over the finite normal quantiles of the curve's points, `lm(sp ~ se)`), and the AUC of the smooth, which `auc.roc` takes from the fitted coefficients (n, the grid size, is unused);
// out receives the intercept, the slope and the AUC
fn smooth_binormal(a: *mem.Arena, y: []const f64, x: []const f64, n: usize, out: []f64) -> err {
    let higher = cases_higher(a, y, x)
    let m = x.len
    let (u, e1) = mem.alloc[f64](a, m)
    if e1 != ok { ret e1 }
    var i = 0usize
    while i < m {
        u[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < m {
        let key = u[i]
        var j = i
        while j > 0usize && u[j - 1usize] > key {
            u[j] = u[j - 1usize]
            j -= 1usize
        }
        u[j] = key
        i += 1usize
    }
    var nu = 0usize
    i = 0usize
    while i < m {
        if nu == 0usize || u[i] != u[nu - 1usize] {
            u[nu] = u[i]
            nu += 1usize
        }
        i += 1usize
    }
    // the points of the curve: thresholds -Inf, the midpoints, Inf
    var sx = 0.0f64
    var sy = 0.0f64
    var sxx = 0.0f64
    var sxy = 0.0f64
    var cnt = 0.0f64
    var t = 0usize
    while t < nu + 1usize {
        var thr = 0.0f64
        if t == 0usize { thr = 0.0f64 - 1.0e308f64 * 10.0f64 } else if t == nu { thr = 1.0e308f64 * 10.0f64 } else { thr = (u[t - 1usize] + u[t]) / 2.0f64 }
        let (se, sp) = coords_at(y, x, higher, thr)
        if se > 0.0f64 && se < 1.0f64 && sp > 0.0f64 && sp < 1.0f64 {
            let qs = dist.qnorm(se, 0.0f64, 1.0f64, true, false)
            let qp = dist.qnorm(sp, 0.0f64, 1.0f64, true, false)
            sx += qs
            sy += qp
            sxx += qs * qs
            sxy += qs * qp
            cnt += 1.0f64
        }
        t += 1usize
    }
    if cnt < 2.0f64 { ret mem.Full }
    let mx = sx / cnt
    let my = sy / cnt
    var sxx2 = 0.0f64
    var sxy2 = 0.0f64
    t = 0usize
    while t < nu + 1usize {
        var thr = 0.0f64
        if t == 0usize { thr = 0.0f64 - 1.0e308f64 * 10.0f64 } else if t == nu { thr = 1.0e308f64 * 10.0f64 } else { thr = (u[t - 1usize] + u[t]) / 2.0f64 }
        let (se, sp) = coords_at(y, x, higher, thr)
        if se > 0.0f64 && se < 1.0f64 && sp > 0.0f64 && sp < 1.0f64 {
            let qs = dist.qnorm(se, 0.0f64, 1.0f64, true, false) - mx
            let qp = dist.qnorm(sp, 0.0f64, 1.0f64, true, false) - my
            sxx2 += qs * qs
            sxy2 += qs * qp
        }
        t += 1usize
    }
    let slope = sxy2 / sxx2
    let icpt = my - slope * mx
    // auc.roc of a binormal smooth is closed form, pnorm(a / sqrt(1 + b^2)), whatever the grid
    let auc = dist.pnorm(icpt / math.sqrt[f64](1.0f64 + slope * slope), 0.0f64, 1.0f64, true, false)
    out[0usize] = icpt
    out[1usize] = slope
    out[2usize] = auc
    ret ok
}

// ---- roc.test by bootstrap (method "bootstrap", the AUC difference, paired curves) ----

// D = (auc1 - auc2) / sd(the replicates' differences) for the two predictors x1 and x2 of the same response y, after set.seed(seed); both resample with the same indices (stratified: the controls then the cases;
// otherwise the whole sample), directions are the originals', replicates missing a class are dropped; out receives D and the two-sided p value 2 pnorm(-|D|)
fn roc_test_boot(a: *mem.Arena, y: []const f64, x1: []const f64, x2: []const f64, boot_n: usize, seed: i64, stratified: bool, out: []f64) -> err {
    let n = y.len
    let (nc, nn) = counts(y)
    let h1 = cases_higher(a, y, x1)
    let h2 = cases_higher(a, y, x2)
    let (cs1, e1) = mem.alloc[f64](a, nc)
    let (ct1, e2) = mem.alloc[f64](a, nn)
    let (cs2, e3) = mem.alloc[f64](a, nc)
    let (ct2, e4) = mem.alloc[f64](a, nn)
    let (r1c, e5) = mem.alloc[f64](a, n)
    let (r1t, e6) = mem.alloc[f64](a, n)
    let (r2c, e7) = mem.alloc[f64](a, n)
    let (r2t, e8) = mem.alloc[f64](a, n)
    let (diffs, e9) = mem.alloc[f64](a, boot_n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret mem.Full }
    var p = 0usize
    var q = 0usize
    var i = 0usize
    while i < n {
        if y[i] > 0.5f64 {
            cs1[p] = x1[i]
            cs2[p] = x2[i]
            p += 1usize
        } else {
            ct1[q] = x1[i]
            ct2[q] = x2[i]
            q += 1usize
        }
        i += 1usize
    }
    var r: rng.Rng = zero
    rng.seed(&r, seed)
    var nv = 0usize
    var b = 0usize
    while b < boot_n {
        var mc = 0usize
        var mt = 0usize
        if stratified {
            let (ic, f1) = rng.sample_int(a, &r, i64(nn), i64(nn), true)
            if f1 != ok { ret f1 }
            let (is, f2) = rng.sample_int(a, &r, i64(nc), i64(nc), true)
            if f2 != ok { ret f2 }
            i = 0usize
            while i < nn {
                r1t[i] = ct1[usize(ic[i]) - 1usize]
                r2t[i] = ct2[usize(ic[i]) - 1usize]
                i += 1usize
            }
            i = 0usize
            while i < nc {
                r1c[i] = cs1[usize(is[i]) - 1usize]
                r2c[i] = cs2[usize(is[i]) - 1usize]
                i += 1usize
            }
            mc = nc
            mt = nn
        } else {
            let (ix, f3) = rng.sample_int(a, &r, i64(n), i64(n), true)
            if f3 != ok { ret f3 }
            i = 0usize
            while i < n {
                let k = usize(ix[i]) - 1usize
                if y[k] > 0.5f64 {
                    r1c[mc] = x1[k]
                    r2c[mc] = x2[k]
                    mc += 1usize
                } else {
                    r1t[mt] = x1[k]
                    r2t[mt] = x2[k]
                    mt += 1usize
                }
                i += 1usize
            }
        }
        if mc > 0usize && mt > 0usize {
            diffs[nv] = auc_pairs(r1c[0usize..mc], r1t[0usize..mt], h1) - auc_pairs(r2c[0usize..mc], r2t[0usize..mt], h2)
            nv += 1usize
        }
        b += 1usize
    }
    var mean = 0.0f64
    i = 0usize
    while i < nv {
        mean += diffs[i]
        i += 1usize
    }
    mean = mean / f64(nv)
    var ss = 0.0f64
    i = 0usize
    while i < nv {
        ss += (diffs[i] - mean) * (diffs[i] - mean)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / f64(nv - 1usize))
    let auc1 = auc_pairs(cs1, ct1, h1)
    let auc2 = auc_pairs(cs2, ct2, h2)
    var d = (auc1 - auc2) / sd
    if d != d && sd == 0.0f64 && auc1 == auc2 { d = 0.0f64 }
    out[0usize] = d
    out[1usize] = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](d), 0.0f64, 1.0f64, true, false)
    ret ok
}
