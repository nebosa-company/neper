// R fdrtool::fdrtool for p values (statistic = "pvalue", cutoff.method = "fndr"): the cutoff by the false
// non-discovery rate, the null proportion eta0 from the censored sample, the Grenander estimator of the p-value
// density (the least concave majorant of the eta0-corrected empirical distribution, by isotonic regression of the
// slopes), and from it the local false discovery rate and the tail-area q values.
//
// Not here: the normal, correlation and Student t statistics (their scale fit uses optimize), the other cutoff
// methods, the plots, monoreg.

use e.algo.sort
use e.algo.stat.mass as ms
use e.math
use e.mem

type Fdr = struct { eta0: f64, cutoff: f64, ncens: usize }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn sorted_copy(a: *mem.Arena, v: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, v.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < v.len {
        s[i] = v[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    ret (s, ok)
}

// pval.estimate.eta0(p, method = "quantile", q = 0.1, lambda = seq(0, 0.9, 0.05))
fn estimate_eta0(a: *mem.Arena, p: []const f64) -> (f64, err) {
    let (e0, e) = mem.alloc[f64](a, 19usize)
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i < 19usize {
        let lam = f64(i) * 0.05f64
        var c = 0.0f64
        var k = 0usize
        while k < p.len {
            if p[k] >= lam { c += 1.0f64 }
            k += 1usize
        }
        var v = c / f64(p.len) / (1.0f64 - lam)
        if v > 1.0f64 { v = 1.0f64 }
        if v < 0.0f64 { v = 0.0f64 }
        e0[i] = v
        i += 1usize
    }
    let (s, se) = sorted_copy(a, e0)
    if se != ok { ret (0.0f64, se) }
    ret (ms.quant7(s, 0.1f64), ok)
}

// the fndr cutoff on the p-value scale
fn fndr_cutoff(a: *mem.Arena, p: []const f64) -> (f64, err) {
    let n = p.len
    let (e0, ee) = estimate_eta0(a, p)
    if ee != ok { ret (0.0f64, ee) }
    let (ax, ae) = mem.alloc[f64](a, n)
    if ae != ok { ret (0.0f64, ae) }
    var i = 0usize
    while i < n {
        ax[i] = 1.0f64 - p[i]
        i += 1usize
    }
    let (sx, se) = sorted_copy(a, ax)
    if se != ok { ret (0.0f64, se) }
    var pr = 0.99f64
    if e0 < pr { pr = e0 }
    var zeta0 = ms.quant7(sx, pr)
    var f2 = fndr_at(ax, e0, zeta0)
    var f1 = fndr_at(ax, e0, 0.9f64 * zeta0)
    while f1 < f2 {
        zeta0 = zeta0 * 0.9f64
        f2 = f1
        f1 = fndr_at(ax, e0, 0.9f64 * zeta0)
    }
    ret (1.0f64 - zeta0, ok)
}

fn fndr_at(ax: []const f64, e0: f64, x: f64) -> f64 {
    var c = 0.0f64
    var i = 0usize
    while i < ax.len {
        if ax[i] < x { c += 1.0f64 }
        i += 1usize
    }
    let fx = c / f64(ax.len)
    if fx == 0.0f64 { ret 0.0f64 }
    let v = (fx - e0 * x) / fx
    if v < 0.0f64 { ret 0.0f64 }
    ret v
}

// weighted pool-adjacent-violators (C_isomean): ghat receives the isotonic fit of y with weights w
fn isomean(y: []const f64, w: []const f64, ghat: []f64, gew: []f64, k: []usize) {
    var nn = y.len
    if nn == 1usize {
        ghat[0usize] = y[0usize]
        ret
    }
    var c = 0usize
    k[0usize] = 0usize
    gew[0usize] = w[0usize]
    ghat[0usize] = y[0usize]
    var j = 1usize
    while j < nn {
        c += 1usize
        k[c] = j
        gew[c] = w[j]
        ghat[c] = y[j]
        while ghat[c - 1usize] >= ghat[c] {
            let neu = gew[c] + gew[c - 1usize]
            ghat[c - 1usize] = ghat[c - 1usize] + (gew[c] / neu) * (ghat[c] - ghat[c - 1usize])
            gew[c - 1usize] = neu
            c -= 1usize
            if c == 0usize { break }
        }
        j += 1usize
    }
    while nn >= 1usize {
        var i = k[c]
        while i < nn {
            ghat[i] = ghat[c]
            i += 1usize
        }
        nn = k[c]
        if c == 0usize { break }
        c -= 1usize
    }
}

// fdrtool(p, statistic = "pvalue", plot = FALSE): fills qval and lfdr (both p.len) and answers eta0, the cutoff
// and the number of censored p values
fn fdrtool_pvalue(a: *mem.Arena, p: []const f64, qval: []f64, lfdr: []f64) -> (Fdr, err) {
    var res: Fdr = zero
    let n = p.len
    let nf = f64(n)
    let (x0, ce) = fndr_cutoff(a, p)
    if ce != ok { ret (res, ce) }
    var ncens = 0usize
    var i = 0usize
    while i < n {
        if p[i] >= x0 { ncens += 1usize }
        i += 1usize
    }
    let m = 1.0f64 - x0
    let th = f64(ncens) / nf
    var eta0 = th / m
    if eta0 > 1.0f64 { eta0 = 1.0f64 }
    res.eta0 = eta0
    res.cutoff = x0
    res.ncens = ncens
    // ecdf.pval(p, eta0): the step values at the unique sorted p, then 0 and 1 added when missing
    let (sp, se) = sorted_copy(a, p)
    if se != ok { ret (res, se) }
    let (vals, e1) = mem.alloc[f64](a, n + 2usize)
    let (fr, e2) = mem.alloc[f64](a, n + 2usize)
    if e1 != ok || e2 != ok { ret (res, e1) }
    var nv = 0usize
    var cum = 0.0f64
    i = 0usize
    while i < n {
        cum += 1.0f64
        if i + 1usize == n || sp[i + 1usize] != sp[i] {
            var f = cum / nf
            let hi = 1.0f64 - eta0 * (1.0f64 - sp[i])
            if f > hi { f = hi }
            let lo = eta0 * sp[i]
            if f < lo { f = lo }
            vals[nv] = sp[i]
            fr[nv] = f
            nv += 1usize
        }
        i += 1usize
    }
    if vals[nv - 1usize] != 1.0f64 {
        vals[nv] = 1.0f64
        fr[nv] = 1.0f64
        nv += 1usize
    }
    if vals[0usize] != 0.0f64 {
        var j = nv
        while j > 0usize {
            vals[j] = vals[j - 1usize]
            fr[j] = fr[j - 1usize]
            j -= 1usize
        }
        vals[0usize] = 0.0f64
        fr[0usize] = 0.0f64
        nv += 1usize
    }
    let ii = nv - 2usize
    fr[ii] = 1.0f64 - eta0 * (1.0f64 - vals[ii])
    // gcmlcm(vals, fr, "lcm"): slopes by isotonic regression of -rawslope
    let nd = nv - 1usize
    let (dx, e3) = mem.alloc[f64](a, nd)
    let (rs, e4) = mem.alloc[f64](a, nd)
    let (gh, e5) = mem.alloc[f64](a, nd)
    let (gw, e6) = mem.alloc[f64](a, nd)
    let (kk, e7) = mem.alloc[usize](a, nd)
    if e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (res, e3) }
    i = 0usize
    while i < nd {
        dx[i] = vals[i + 1usize] - vals[i]
        var r = (fr[i + 1usize] - fr[i]) / dx[i]
        if r > 1.7976931348623157e308f64 { r = 1.7976931348623157e308f64 }
        if r < 0.0f64 - 1.7976931348623157e308f64 { r = 0.0f64 - 1.7976931348623157e308f64 }
        rs[i] = 0.0f64 - r
        i += 1usize
    }
    isomean(rs, dx, gh, gw, kk)
    // slope = -gh; knots where the slope changes
    let (xk, e8) = mem.alloc[f64](a, nd + 1usize)
    let (yk, e9) = mem.alloc[f64](a, nd + 1usize)
    let (sk, e10) = mem.alloc[f64](a, nd + 1usize)
    if e8 != ok || e9 != ok || e10 != ok { ret (res, e8) }
    var nk = 0usize
    i = 0usize
    while i < nd {
        let sl = 0.0f64 - gh[i]
        var dup = false
        var j = 0usize
        while j < nk {
            if sk[j] == sl { dup = true }
            j += 1usize
        }
        if !dup {
            xk[nk] = vals[i]
            sk[nk] = sl
            nk += 1usize
        }
        i += 1usize
    }
    xk[nk] = vals[nv - 1usize]
    yk[0usize] = fr[0usize]
    i = 0usize
    while i < nk {
        yk[i + 1usize] = yk[i] + (xk[i + 1usize] - xk[i]) * sk[i]
        i += 1usize
    }
    // evaluate: F (linear interpolation, 0 left, last right) and f (step, rule 2)
    i = 0usize
    while i < n {
        var pv = p[i]
        var fF = 0.0f64
        var ff = sk[nk - 1usize]
        if pv <= xk[0usize] {
            fF = 0.0f64
            if pv == xk[0usize] { fF = yk[0usize] }
            ff = sk[0usize]
        } else if pv >= xk[nk] {
            fF = yk[nk]
            ff = sk[nk - 1usize]
        } else {
            var lo = 0usize
            var hi = nk
            while lo + 1usize < hi {
                let mid = (lo + hi) / 2usize
                if pv < xk[mid] { hi = mid } else { lo = mid }
            }
            fF = yk[lo] + (yk[hi] - yk[lo]) * ((pv - xk[lo]) / (xk[hi] - xk[lo]))
            ff = sk[lo]
            if pv == xk[hi] { ff = sk[hi] }
        }
        var qv = eta0 * p[i] / fF
        if qv > 1.0f64 { qv = 1.0f64 }
        qval[i] = qv
        if pv == 2.220446049250313e-16f64 { pv = 0.0f64 }
        var lv = eta0 / ff
        if lv > 1.0f64 { lv = 1.0f64 }
        lfdr[i] = lv
        i += 1usize
    }
    ret (res, ok)
}
