// R drc: drm() for the continuous and Poisson dose-response models, a port of the drc algorithm (drmEMls, drmEMPoisson, drmOpt):
// drc's own start values (ssfct), its dose and response scaling for the log-logistic family, optim's BFGS with the finite-difference
// gradient (step 1e-3 in parscale units) and optimHess for the curvature. kind: 0 LL.x, 1 W1.x, 2 W2.x, 3 G.x (Gompertz),
// 4 BC.x (Brain-Cousens), 5 CRS.x (Cedergreen-Ritz-Streibig, alpha given), 6 UCRS.5a (its U-shaped twin). A model is a kind plus its fixed values: fixedv holds the
// five values (b, c, d, e, f) with NaN for a free one, so LL.2 is (NaN, 0, 1, NaN, 1) and BC.4 is (NaN, 0, NaN, NaN, NaN).
// W1, W2 and G have four parameters and ignore the fifth. Several curves (grp) have their own parameters, laid out parameter by parameter.
//
// mode: 0 least squares, 1 robust "median" (sum of absolute residuals), 2 Poisson (negative log-likelihood), 3 robust "trimmed",
// 4 "tukey", 5 "winsor" (all three divide the residuals by scale, which drc takes from a least-trimmed-squares fit and the caller
// supplies), 6 "lms", 7 "lts". A non-empty fixpar skips the optimiser and evaluates the fit at those coefficients: kinked criteria
// have no reproducible BFGS path across math libraries, so they are compared at R's own optimum (crit is the criterion there).
//
// Not here: absolute-response ED, shared parameters across curves (pmodels), negative
// binomial, binomial and event data, plots.

use e.algo.stat.rbfgs as bf
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Fit = struct {
    np: usize, nfree: usize, ncurve: usize, n: usize,
    free: []usize, par: []f64, value: f64, dfres: f64, rv: f64,
    hess: []f64, vcov: []f64, loglik: f64, fitted: []f64, resid: []f64, mode: i64, crit: f64
}

type Ctx = struct {
    kind: i64, alpha: f64, fixedv: []const f64, free: []const usize, nfree: usize, ncurve: usize,
    dose: []const f64, resp: []const f64, grp: []const usize, mode: i64, ps: []const f64, scale: f64, nres: usize,
    p5: []f64, xs: []f64, tmp: []f64, rbuf: []f64, arena: *mem.Arena
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }
fn isnan(x: f64) -> bool { ret x != x }

fn nominal(kind: i64) -> usize {
    if kind == 0 || kind == 4 || kind == 5 || kind == 6 { ret 5usize }
    ret 4usize
}

// the model function at dose x for the full parameter vector p = (b, c, d, e, f)
fn model_mean(kind: i64, alpha: f64, x: f64, p: []const f64) -> f64 {
    let b = p[0usize]
    let c = p[1usize]
    let d = p[2usize]
    let e = p[3usize]
    let f = p[4usize]
    if kind == 0 { ret c + (d - c) / math.pow[f64](1.0f64 + math.exp[f64](b * math.log[f64](x / e)), f) }
    let lr = b * (math.log[f64](x) - math.log[f64](e))
    if kind == 1 { ret c + (d - c) * math.exp[f64](0.0f64 - math.exp[f64](lr)) }
    if kind == 2 { ret c + (d - c) * (1.0f64 - math.exp[f64](0.0f64 - math.exp[f64](lr))) }
    if kind == 3 { ret c + (d - c) * math.exp[f64](0.0f64 - math.exp[f64](b * (x - e))) }
    if kind == 4 { ret c + (d + f * x - c) / (1.0f64 + math.exp[f64](lr)) }
    if kind == 6 { ret d - (d - c + f * math.exp[f64](0.0f64 - 1.0f64 / math.pow[f64](x, alpha))) / (1.0f64 + math.exp[f64](lr)) }
    ret c + (d - c + f * math.exp[f64](0.0f64 - 1.0f64 / math.pow[f64](x, alpha))) / (1.0f64 + math.exp[f64](lr))
}

fn sort_copy(a: *mem.Arena, v: []const f64) -> []f64 {
    let (s, e1) = mem.alloc[f64](a, v.len + 1usize)
    if e1 != ok { ret s }
    var i = 0usize
    while i < v.len {
        var j = i
        while j > 0usize && s[j - 1usize] > v[i] {
            s[j] = s[j - 1usize]
            j -= 1usize
        }
        s[j] = v[i]
        i += 1usize
    }
    ret s[0usize..v.len]
}

fn median(a: *mem.Arena, v: []const f64) -> f64 {
    let n = v.len
    let s = sort_copy(a, v)
    if n % 2usize == 1usize { ret s[n / 2usize] }
    ret 0.5f64 * (s[n / 2usize - 1usize] + s[n / 2usize])
}

// drc's start values for one curve, the five-slot vector before the fixed ones are dropped
fn start5(a: *mem.Arena, kind: i64, alpha: f64, x: []const f64, y: []const f64, out: []f64) {
    var lo = y[0usize]
    var hi = y[0usize]
    var i = 0usize
    while i < y.len {
        if y[i] < lo { lo = y[i] }
        if y[i] > hi { hi = y[i] }
        i += 1usize
    }
    let c0 = lo - 0.001f64 * (hi - lo)
    let d0 = hi + 0.001f64 * (hi - lo)
    var sx = 0.0f64
    var sy = 0.0f64
    var m = 0.0f64
    var tx = alloc_tmp(a, x.len)
    var ty = alloc_tmp(a, x.len)
    i = 0usize
    while i < x.len {
        var ok1 = true
        if kind != 3 && !(x[i] > 0.0f64) { ok1 = false }
        if ok1 {
            var t = x[i]
            if kind != 3 { t = math.log[f64](x[i]) }
            var u = 0.0f64
            if kind == 0 || kind == 4 || kind == 5 || kind == 6 { u = math.log[f64]((d0 - y[i]) / (y[i] - c0)) }
            if kind == 1 { u = math.log[f64](0.0f64 - math.log[f64]((y[i] - c0) / (d0 - c0))) }
            if kind == 2 || kind == 3 { u = math.log[f64](0.0f64 - math.log[f64]((d0 - y[i]) / (d0 - c0))) }
            tx[i] = t
            ty[i] = u
            sx += t
            sy += u
            m += 1.0f64
        }
        i += 1usize
    }
    let mx = sx / m
    let my = sy / m
    var sxx = 0.0f64
    var sxy = 0.0f64
    i = 0usize
    while i < x.len {
        var ok2 = true
        if kind != 3 && !(x[i] > 0.0f64) { ok2 = false }
        if ok2 {
            sxx += (tx[i] - mx) * (tx[i] - mx)
            sxy += (tx[i] - mx) * (ty[i] - my)
        }
        i += 1usize
    }
    let slope = sxy / sxx
    let icpt = my - slope * mx
    var ev = math.exp[f64](0.0f64 - icpt / slope)
    if kind == 3 { ev = 0.0f64 - icpt / slope }
    out[0usize] = slope
    out[1usize] = c0
    out[2usize] = d0
    out[3usize] = ev
    out[4usize] = 1.0f64
    if kind == 1 || kind == 2 { out[4usize] = 0.0f64 }
    if kind == 3 {
        out[0usize] = 0.0f64 - slope
        out[1usize] = 0.8f64 * c0
        out[2usize] = 1.2f64 * d0
        out[4usize] = 0.0f64
    }
    if kind == 4 || kind == 6 { out[4usize] = 0.0f64 }
    if kind == 6 { out[0usize] = 0.0f64 - slope }
    if kind == 5 {
        out[4usize] = (2.0f64 * (median(a, y) - c0) - (d0 - c0)) * math.exp[f64](1.0f64 / math.pow[f64](ev, alpha))
    }
}

fn alloc_tmp(a: *mem.Arena, n: usize) -> []f64 {
    let (s, e1) = mem.alloc[f64](a, n + 1usize)
    if e1 == ok {
        var i = 0usize
        while i < s.len {
            s[i] = 0.0f64
            i += 1usize
        }
    }
    ret s[0usize..n]
}

fn fill_p5(c: *Ctx, u: []const f64) {
    let kk = c.ncurve
    var k = 0usize
    while k < kk {
        var i = 0usize
        while i < 5usize {
            c.p5[k * 5usize + i] = c.fixedv[i]
            i += 1usize
        }
        var j = 0usize
        while j < c.nfree {
            c.p5[k * 5usize + c.free[j]] = u[j * kk + k] * c.ps[j * kk + k]
            j += 1usize
        }
        k += 1usize
    }
}

fn two_sum(a: f64, b: f64) -> (f64, f64) {
    let s = a + b
    let bb = s - a
    ret (s, (a - (s - bb)) + (b - bb))
}

fn pow2(e: i64) -> f64 { ret mem.bitcast[f64](u64(e + 1023i64) << 52u64) }

// one step of a 64-bit-significand (x87 extended) running sum: the accumulator is h + l exactly, v is added and the result rounded
// to 64 significant bits, ties to even
fn ld_add(h: f64, l: f64, v: f64) -> (f64, f64) {
    if h == 0.0f64 && l == 0.0f64 { ret (v, 0.0f64) }
    let (s1, e1) = two_sum(h, v)
    let (s2, e2) = two_sum(e1, l)
    let (hh, r) = two_sum(s1, s2)
    if r == 0.0f64 && e2 == 0.0f64 { ret (hh, 0.0f64) }
    if hh == 0.0f64 { ret (r + e2, 0.0f64) }
    let bits = mem.bitcast[u64](hh)
    var e = i64((bits >> 52u64) & 2047u64) - 1023i64
    if (bits & 4503599627370495u64) == 0u64 && (r + e2) * hh < 0.0f64 { e -= 1i64 }
    let u = pow2(e - 63i64)
    let inv = pow2(63i64 - e)
    let a = r * inv
    let b = e2 * inv
    var k = math.floor[f64](a + 0.5f64)
    if a + 0.5f64 == k {
        if b > 0.0f64 { k = k } else {
            if b < 0.0f64 { k = k - 1.0f64 } else {
                if k - 2.0f64 * math.floor[f64](k / 2.0f64) == 1.0f64 { k = k - 1.0f64 }
            }
        }
    }
    let (hn, ln) = two_sum(hh, k * u)
    ret (hn, ln)
}

// one robust criterion term for the scaled residual r (lts keeps the signed residual: drc sorts the signed values, then squares the lowest ones)
fn robust_term(mode: i64, r: f64, scale: f64) -> f64 {
    if mode == 1 { ret math.abs[f64](r) }
    if mode == 7 { ret r }
    if mode == 0 || mode == 6 { ret r * r }
    let x = r / scale
    if mode == 3 {
        if math.abs[f64](x) > 1.345f64 { ret 1.345f64 * 1.345f64 }
        ret x * x
    }
    if mode == 4 {
        if math.abs[f64](x) > 4.685f64 { ret 4.685f64 * 4.685f64 }
        ret math.pow[f64](x, 6.0f64) / math.pow[f64](4.685f64, 4.0f64) - 3.0f64 * math.pow[f64](x, 4.0f64) / (4.685f64 * 4.685f64) + 3.0f64 * x * x
    }
    if math.abs[f64](x) > 1.345f64 { ret 1.345f64 * (2.0f64 * math.abs[f64](x) - 1.345f64) }
    ret x * x
}

// the quantity optim minimises, at the parscale-divided parameters u
fn objective(c: *Ctx, u: []const f64) -> f64 {
    fill_p5(c, u)
    let n = c.dose.len
    // R sums in x87 long double; ld_add reproduces that accumulator, which a flat or non-smooth optimum is sensitive to
    var s = 0.0f64
    var comp = 0.0f64
    var i = 0usize
    let tmp = c.rbuf
    while i < n {
        let k = c.grp[i]
        let f = model_mean(c.kind, c.alpha, c.dose[i], c.p5[k * 5usize..k * 5usize + 5usize])
        var v = 0.0f64
        if c.mode == 2 { v = 0.0f64 - f + c.resp[i] * math.log[f64](f) } else { v = robust_term(c.mode, c.resp[i] - f, c.scale) }
        tmp[i] = v
        if c.mode != 6 && c.mode != 7 {
            let (s2, c2) = ld_add(s, comp, v)
            s = s2
            comp = c2
        }
        i += 1usize
    }
    if c.mode == 6 || c.mode == 7 {
        let st = mem.mark(c.arena)
        var res = 0.0f64
        if c.mode == 6 { res = median(c.arena, tmp[0usize..n]) } else {
            let srt = sort_copy(c.arena, tmp[0usize..n])
            i = 0usize
            while i < c.nres {
                let (s2, c2) = ld_add(s, comp, srt[i] * srt[i])
                s = s2
                comp = c2
                i += 1usize
            }
            res = s
        }
        mem.reset(c.arena, st)
        ret res
    }
    if c.mode == 2 { ret 0.0f64 - s }
    ret s
}

fn gradient(c: *Ctx, u: []const f64, g: []f64) {
    var j = 0usize
    while j < u.len {
        var k = 0usize
        while k < u.len {
            c.xs[k] = u[k]
            k += 1usize
        }
        c.xs[j] = u[j] + 0.001f64
        let v1 = objective(c, c.xs)
        c.xs[j] = u[j] - 0.001f64
        let v2 = objective(c, c.xs)
        g[j] = (v1 - v2) / 0.002f64
        j += 1usize
    }
}

// the inverse of the n by n row-major h by Gauss-Jordan; false when singular
fn invert(a: *mem.Arena, h: []const f64, n: usize, out: []f64) -> bool {
    let w = 2usize * n
    let m = alloc_tmp(a, n * w)
    var i = 0usize
    while i < n {
        var k = 0usize
        while k < n {
            m[i * w + k] = h[i * n + k]
            k += 1usize
        }
        m[i * w + n + i] = 1.0f64
        i += 1usize
    }
    var col = 0usize
    while col < n {
        var piv = col
        var r = col + 1usize
        while r < n {
            if math.abs[f64](m[r * w + col]) > math.abs[f64](m[piv * w + col]) { piv = r }
            r += 1usize
        }
        if m[piv * w + col] == 0.0f64 { ret false }
        if piv != col {
            var k = 0usize
            while k < w {
                let t = m[col * w + k]
                m[col * w + k] = m[piv * w + k]
                m[piv * w + k] = t
                k += 1usize
            }
        }
        let d = m[col * w + col]
        var k = 0usize
        while k < w {
            m[col * w + k] = m[col * w + k] / d
            k += 1usize
        }
        r = 0usize
        while r < n {
            if r != col {
                let f = m[r * w + col]
                k = 0usize
                while k < w {
                    m[r * w + k] = m[r * w + k] - f * m[col * w + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    i = 0usize
    while i < n {
        var k = 0usize
        while k < n {
            out[i * n + k] = m[i * w + n + k]
            k += 1usize
        }
        i += 1usize
    }
    ret true
}

fn log10_floor_pow(v: f64) -> f64 {
    if !(v > 0.0f64) { ret 0.0f64 }
    ret math.pow[f64](10.0f64, math.floor[f64](math.log10[f64](v)))
}

// drm(resp ~ dose, curveid = grp, fct = <kind, fixedv>, type = continuous|Poisson, robust = mean|median)
fn fit(a: *mem.Arena, kind: i64, alpha: f64, fixedv: []const f64, dose: []const f64, resp: []const f64, grp: []const usize, ncurve: usize, mode: i64, scale: f64, fixpar: []const f64) -> (Fit, err) {
    let n = dose.len
    let kk = ncurve
    var nf = 0usize
    var i = 0usize
    while i < nominal(kind) {
        if isnan(fixedv[i]) { nf += 1usize }
        i += 1usize
    }
    let free = alloc_tmp_usize(a, nf)
    var jj = 0usize
    i = 0usize
    while i < nominal(kind) {
        if isnan(fixedv[i]) {
            free[jj] = i
            jj += 1usize
        }
        i += 1usize
    }
    let np = nf * kk
    // scaling: the log-logistic family only
    var dsc = 1.0f64
    var rsc = 1.0f64
    if kind == 0 {
        dsc = log10_floor_pow(median(a, dose))
        if !(dsc >= 1.0e-15f64) { dsc = 1.0f64 }
        rsc = log10_floor_pow(median(a, resp))
        if !(rsc >= 1.0e-15f64) || mode == 2 { rsc = 1.0f64 }
    }
    // drc's retFct divides the fixed values by the scales as well
    let fxs = alloc_tmp(a, 5usize)
    i = 0usize
    while i < 5usize {
        fxs[i] = fixedv[i]
        if kind == 0 && i == 1usize || kind == 0 && i == 2usize { fxs[i] = fixedv[i] / rsc }
        if kind == 0 && i == 3usize { fxs[i] = fixedv[i] / dsc }
        i += 1usize
    }
    let xs = alloc_tmp(a, n)
    let ys = alloc_tmp(a, n)
    i = 0usize
    while i < n {
        xs[i] = dose[i] / dsc
        ys[i] = resp[i] / rsc
        i += 1usize
    }
    // start values, curve by curve, then parameter by parameter with zeros replaced by the mean
    let sm = alloc_tmp(a, kk * 5usize)
    var k = 0usize
    while k < kk {
        var cnt = 0usize
        i = 0usize
        while i < n {
            if grp[i] == k { cnt += 1usize }
            i += 1usize
        }
        let cx = alloc_tmp(a, cnt)
        let cy = alloc_tmp(a, cnt)
        var q = 0usize
        i = 0usize
        while i < n {
            if grp[i] == k {
                cx[q] = xs[i]
                cy[q] = ys[i]
                q += 1usize
            }
            i += 1usize
        }
        start5(a, kind, alpha, cx[0usize..cnt], cy[0usize..cnt], sm[k * 5usize..k * 5usize + 5usize])
        k += 1usize
    }
    let u0 = alloc_tmp(a, np)
    var j = 0usize
    while j < nf {
        var tot = 0.0f64
        k = 0usize
        while k < kk {
            u0[j * kk + k] = sm[k * 5usize + free[j]]
            tot += u0[j * kk + k]
            k += 1usize
        }
        k = 0usize
        while k < kk {
            if u0[j * kk + k] == 0.0f64 { u0[j * kk + k] = tot / f64(kk) }
            k += 1usize
        }
        j += 1usize
    }
    let ps = alloc_tmp(a, np)
    i = 0usize
    while i < np {
        var v = math.abs[f64](u0[i])
        if v < 1.0e-4f64 { v = 1.0f64 }
        ps[i] = v
        i += 1usize
    }
    var cx = Ctx {
        kind: kind, alpha: alpha, fixedv: fxs, free: free, nfree: nf, ncurve: kk,
        dose: xs, resp: ys, grp: grp, mode: mode, ps: ps, scale: scale, nres: (n + np + 1usize) / 2usize,
        p5: alloc_tmp(a, kk * 5usize), xs: alloc_tmp(a, np), tmp: alloc_tmp(a, np), rbuf: alloc_tmp(a, n), arena: a
    }
    let u = alloc_tmp(a, np)
    i = 0usize
    while i < np {
        u[i] = u0[i] / ps[i]
        i += 1usize
    }
    var mn = 0.0f64
    if fixpar.len == np && np > 0usize {
        j = 0usize
        while j < nf {
            k = 0usize
            while k < kk {
                var sc0 = 1.0f64
                if kind == 0 {
                    if free[j] == 1usize || free[j] == 2usize { sc0 = rsc }
                    if free[j] == 3usize { sc0 = dsc }
                }
                u[j * kk + k] = fixpar[j * kk + k] / (ps[j * kk + k] * sc0)
                k += 1usize
            }
            j += 1usize
        }
        mn = objective(&cx, u[0usize..np])
    } else {
        mn = bf.vmmin[Ctx](a, &cx, objective, gradient, u[0usize..np], 1.0e-7f64, 500usize)
    }
    if !(mn == mn) { ret (Fit { np: 0usize, nfree: 0usize, ncurve: 0usize, n: 0usize, free: free, par: u, value: 0.0f64, dfres: 0.0f64, rv: 0.0f64, hess: u, vcov: u, loglik: 0.0f64, fitted: u, resid: u, mode: mode, crit: 0.0f64 }, fx_malformed()) }
    // optimHess at the optimum
    let hs = alloc_tmp(a, np * np)
    let g1 = alloc_tmp(a, np)
    let g2 = alloc_tmp(a, np)
    let dp = alloc_tmp(a, np)
    i = 0usize
    while i < np {
        let eps = 0.001f64 / ps[i]
        k = 0usize
        while k < np {
            dp[k] = u[k]
            k += 1usize
        }
        dp[i] = u[i] + eps
        gradient(&cx, dp[0usize..np], g1)
        dp[i] = u[i] - eps
        gradient(&cx, dp[0usize..np], g2)
        k = 0usize
        while k < np {
            hs[i * np + k] = (g1[k] - g2[k]) / (2.0f64 * eps * ps[i] * ps[k])
            k += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < np {
        k = 0usize
        while k < i {
            let m = 0.5f64 * (hs[i * np + k] + hs[k * np + i])
            hs[i * np + k] = m
            hs[k * np + i] = m
            k += 1usize
        }
        i += 1usize
    }
    // back to the data scale
    let par = alloc_tmp(a, np)
    let lsv = alloc_tmp(a, np)
    j = 0usize
    while j < nf {
        k = 0usize
        while k < kk {
            var sc = 1.0f64
            if kind == 0 {
                let fi = free[j]
                if fi == 1usize || fi == 2usize { sc = rsc }
                if fi == 3usize { sc = dsc }
            }
            lsv[j * kk + k] = sc
            par[j * kk + k] = u[j * kk + k] * ps[j * kk + k] * sc
            k += 1usize
        }
        j += 1usize
    }
    var value = mn * rsc * rsc
    i = 0usize
    while i < np {
        k = 0usize
        while k < np {
            hs[i * np + k] = hs[i * np + k] / ((lsv[i] / rsc) * (lsv[k] / rsc))
            k += 1usize
        }
        i += 1usize
    }
    // fitted values and residuals on the data scale
    let fitted = alloc_tmp(a, n)
    let resid = alloc_tmp(a, n)
    let p5 = alloc_tmp(a, kk * 5usize)
    k = 0usize
    while k < kk {
        i = 0usize
        while i < 5usize {
            p5[k * 5usize + i] = fixedv[i]
            i += 1usize
        }
        j = 0usize
        while j < nf {
            p5[k * 5usize + free[j]] = par[j * kk + k]
            j += 1usize
        }
        k += 1usize
    }
    var ss = 0.0f64
    var sa = 0.0f64
    i = 0usize
    while i < n {
        k = grp[i]
        fitted[i] = model_mean(kind, alpha, dose[i], p5[k * 5usize..k * 5usize + 5usize])
        resid[i] = resp[i] - fitted[i]
        ss += resid[i] * resid[i]
        i += 1usize
    }
    let dfres = f64(n) - f64(np)
    if mode == 0 { value = ss }
    if mode == 1 || mode == 3 || mode == 4 || mode == 5 {
        let ar = alloc_tmp(a, n)
        i = 0usize
        while i < n {
            ar[i] = math.abs[f64](resid[i])
            i += 1usize
        }
        let mad = 1.4826f64 * median(a, ar[0usize..n])
        value = mad * mad * dfres
    }
    if mode == 6 || mode == 7 {
        let sq = alloc_tmp(a, n)
        i = 0usize
        while i < n {
            sq[i] = resid[i] * resid[i]
            i += 1usize
        }
        let se = 1.4826f64 * (1.0f64 + 5.0f64 / dfres) * math.sqrt[f64](median(a, sq[0usize..n]))
        var sw = 0.0f64
        var sr = 0.0f64
        i = 0usize
        while i < n {
            if resid[i] / se < 2.5f64 {
                sw += 1.0f64
                sr += sq[i]
            }
            i += 1usize
        }
        value = sr / (sw - f64(np))
    }
    var rv = value / dfres
    let vc = alloc_tmp(a, np * np)
    let sh = alloc_tmp(a, np * np)
    i = 0usize
    while i < np * np {
        sh[i] = hs[i]
        if mode != 2 { sh[i] = hs[i] / (2.0f64 * rv) }
        i += 1usize
    }
    if !invert(a, sh[0usize..np * np], np, vc) && fixpar.len == np {
        i = 0usize
        while i < np * np {
            vc[i] = nan()
            i += 1usize
        }
    } else if !invert(a, sh[0usize..np * np], np, vc) { ret (Fit { np: 0usize, nfree: 0usize, ncurve: 0usize, n: 0usize, free: free, par: u, value: 0.0f64, dfres: 0.0f64, rv: 0.0f64, hess: u, vcov: u, loglik: 0.0f64, fitted: u, resid: u, mode: mode, crit: 0.0f64 }, fx_malformed()) }
    var ll = 0.0f64 - (f64(n) / 2.0f64) * (math.log[f64](2.0f64 * 3.141592653589793f64) + math.log[f64](value) - math.log[f64](f64(n)) + 1.0f64)
    if mode == 2 {
        var lg = 0.0f64
        i = 0usize
        while i < n {
            lg += nm.lgammafn(resp[i] + 1.0f64)
            i += 1usize
        }
        ll = 0.0f64 - value + lg
        rv = nan()
    }
    ret (Fit { np: np, nfree: nf, ncurve: kk, n: n, free: free, par: par, value: value, dfres: dfres, rv: rv, hess: hs, vcov: vc, loglik: ll, fitted: fitted, resid: resid, mode: mode, crit: mn }, ok)
}

fn alloc_tmp_usize(a: *mem.Arena, n: usize) -> []usize {
    let (s, e1) = mem.alloc[usize](a, n + 1usize)
    if e1 == ok {
        var i = 0usize
        while i < s.len {
            s[i] = 0usize
            i += 1usize
        }
    }
    ret s[0usize..n]
}

error Malformed
fn fx_malformed() -> err { ret Malformed }

// the five parameters of curve k, fixed values filled in
fn curve_par(f: *const Fit, fixedv: []const f64, k: usize, out: []f64) {
    var i = 0usize
    while i < 5usize {
        out[i] = fixedv[i]
        i += 1usize
    }
    var j = 0usize
    while j < f.nfree {
        out[f.free[j]] = f.par[j * f.ncurve + k]
        j += 1usize
    }
}

// Akaike's criterion as drc's logLik/AIC: continuous fits count the variance as a parameter
fn aic(f: *const Fit) -> f64 {
    ret 0.0f64 - 2.0f64 * f.loglik + 2.0f64 * (f64(f.np) + 1.0f64)
}

// the equations drc's BC and CRS edfct hand to uniroot: mode 0 BC helpEqn, 1 BC eqn, 2 CRS eqn
type Zq = struct { mode: i64, alpha: f64, tv: f64, b: f64, c: f64, d: f64, e: f64, f: f64 }

fn zf_eval(z: *const Zq, x: f64) -> f64 {
    let ev = math.exp[f64](z.b * (math.log[f64](x) - math.log[f64](z.e)))
    if z.mode == 0 { ret z.f * (1.0f64 + ev * (1.0f64 - z.b)) - (z.d - z.c) * ev * z.b / x }
    if z.mode == 1 { ret z.tv * (1.0f64 + ev) - (1.0f64 + z.f * x / (z.d - z.c)) }
    ret z.tv * (1.0f64 + ev) - (1.0f64 + z.f * math.exp[f64](0.0f64 - 1.0f64 / math.pow[f64](x, z.alpha)) / (z.d - z.c))
}

// stats::uniroot(f, c(lower, upper))$root with its default tolerance and R_zeroin2's iteration; NaN when the end points do not bracket
fn zf_root(z: *const Zq, lower: f64, upper: f64) -> f64 {
    let eps = 2.220446049250313e-16f64
    let tol = math.pow[f64](eps, 0.25f64)
    var a = lower
    var b = upper
    var c = a
    var fa = zf_eval(z, a)
    var fb = zf_eval(z, b)
    var fc = fa
    if fa * fb > 0.0f64 || fa != fa || fb != fb { ret nan() }
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    var left = 1001i64
    while left > 0i64 {
        left -= 1i64
        let prev = b - a
        if math.abs[f64](fc) < math.abs[f64](fb) {
            a = b
            b = c
            c = a
            fa = fb
            fb = fc
            fc = fa
        }
        let tol_act = 2.0f64 * eps * math.abs[f64](b) + tol / 2.0f64
        var step = (c - b) / 2.0f64
        if math.abs[f64](step) <= tol_act || fb == 0.0f64 { ret b }
        if math.abs[f64](prev) >= tol_act && math.abs[f64](fa) > math.abs[f64](fb) {
            let cb = c - b
            var pp = 0.0f64
            var qq = 0.0f64
            if a == c {
                let t1 = fb / fa
                pp = cb * t1
                qq = 1.0f64 - t1
            } else {
                qq = fa / fc
                let t1 = fb / fc
                let t2 = fb / fa
                pp = t2 * (cb * qq * (qq - t1) - (b - a) * (t1 - 1.0f64))
                qq = (qq - 1.0f64) * (t1 - 1.0f64) * (t2 - 1.0f64)
            }
            if pp > 0.0f64 { qq = 0.0f64 - qq } else { pp = 0.0f64 - pp }
            if pp < (0.75f64 * cb * qq - math.abs[f64](tol_act * qq) / 2.0f64) && pp < math.abs[f64](prev * qq / 2.0f64) { step = pp / qq }
        }
        if math.abs[f64](step) < tol_act {
            if step > 0.0f64 { step = tol_act } else { step = 0.0f64 - tol_act }
        }
        a = b
        fa = fb
        b += step
        fb = zf_eval(z, b)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret b
}

// drc's ED for BC.x (kind 4) and CRS.x (kind 5): the root and the gradient der (b, c, d, e, f) of the ED formula
fn ed_root(kind: i64, alpha: f64, pv: []const f64, p0: f64, der: []f64) -> f64 {
    var z = Zq { mode: 0i64, alpha: alpha, tv: 0.0f64, b: pv[0usize], c: pv[1usize], d: pv[2usize], e: pv[3usize], f: pv[4usize] }
    var p = p0
    if z.b < 0.0f64 { p = 100.0f64 - p }
    z.tv = (100.0f64 - p) / 100.0f64
    var lo = 0.001f64
    var hi = 1000.0f64
    var maxat = 0.0f64
    if kind == 4 {
        maxat = zf_root(&z, lo, hi)
        z.mode = 1i64
    } else {
        lo = 1.0e-4f64
        hi = 10000.0f64
        z.mode = 2i64
        let l0 = math.log[f64](lo)
        let by = (math.log[f64](hi) - l0) / 999.0f64
        var best = 0.0f64 - 1.0e308f64
        var i = 0usize
        while i < 1000usize {
            var x = math.exp[f64](l0 + f64(i) * by)
            if i == 999usize { x = math.exp[f64](math.log[f64](hi)) }
            let ev = math.exp[f64](z.b * (math.log[f64](x) - math.log[f64](z.e)))
            let v = z.c + (z.d - z.c + z.f * math.exp[f64](0.0f64 - 1.0f64 / math.pow[f64](x, alpha))) / (1.0f64 + ev)
            if v > best {
                best = v
                maxat = x
            }
            i += 1usize
        }
    }
    let est = zf_root(&z, maxat, hi)
    let t1 = math.exp[f64](z.b * (math.log[f64](est) - math.log[f64](z.e)))
    let t2 = z.d - z.c
    var g = est
    var dd = z.tv * t1 * z.b / est - z.f / t2
    der[0usize] = z.tv * t1 * (math.log[f64](est) - math.log[f64](z.e))
    der[3usize] = 0.0f64 - z.tv * t1 * z.b / z.e
    if kind == 5 {
        g = math.exp[f64](0.0f64 - 1.0f64 / math.pow[f64](est, alpha))
        dd = z.tv * t1 * z.b / est - z.f / t2 * g / math.pow[f64](est, 1.0f64 + alpha) * alpha
    }
    der[1usize] = 0.0f64 - z.f * g / (t2 * t2)
    der[2usize] = z.f * g / (t2 * t2)
    der[4usize] = 0.0f64 - g / t2
    var j = 0usize
    while j < 5usize {
        der[j] = der[j] / dd
        j += 1usize
    }
    ret est
}

// ED at response percentage p of curve k (drc, relative type, reference "control"); dn (length np) receives the
// gradient with respect to the coefficients, zero outside the curve's own
fn ed_der(f: *const Fit, kind: i64, alpha: f64, fixedv: []const f64, k: usize, p0: f64, a: *mem.Arena, dn: []f64) -> f64 {
    let pv = alloc_tmp(a, 5usize)
    curve_par(f, fixedv, k, pv)
    let b = pv[0usize]
    let e = pv[3usize]
    let ff = pv[4usize]
    var p = p0
    var est = 0.0f64
    let der = alloc_tmp(a, 5usize)
    if kind == 0 {
        if b < 0.0f64 { p = 100.0f64 - p }
        let tv = math.log[f64](1.0f64 - p / 100.0f64)
        let w = math.exp[f64](0.0f64 - tv / ff)
        est = e * math.pow[f64](w - 1.0f64, 1.0f64 / b)
        der[0usize] = est * (0.0f64 - math.log[f64](w - 1.0f64) / (b * b))
        der[3usize] = est * (1.0f64 / e)
        der[4usize] = est * (w * tv / (ff * ff) * (1.0f64 / b) * (1.0f64 / (w - 1.0f64)))
    }
    if kind == 1 || kind == 2 {
        if kind == 2 && b > 0.0f64 { p = 100.0f64 - p }
        var tv = math.log[f64](0.0f64 - math.log[f64](1.0f64 - p / 100.0f64))
        if kind == 2 { tv = math.log[f64](0.0f64 - math.log[f64](p / 100.0f64)) }
        est = math.exp[f64](tv / b + math.log[f64](e))
        der[0usize] = est * (0.0f64 - tv / (b * b))
        der[3usize] = est * (1.0f64 / e)
    }
    if kind == 3 {
        if b < 0.0f64 { p = 100.0f64 - p }
        let tv = math.log[f64](0.0f64 - math.log[f64]((100.0f64 - p) / 100.0f64))
        est = tv / b + e
        der[0usize] = est * (0.0f64 - tv / (b * b))
        der[3usize] = est
    }
    if kind == 4 || kind == 5 { est = ed_root(kind, alpha, pv, p0, der) }
    if kind == 6 { est = ed_root(5i64, alpha, pv, 100.0f64 - p0, der) }
    var i = 0usize
    while i < f.nfree {
        dn[i * f.ncurve + k] = der[f.free[i]]
        i += 1usize
    }
    ret est
}

fn quad(v: []const f64, vc: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            s += v[i] * vc[i * n + j] * v[j]
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn ed(f: *const Fit, kind: i64, alpha: f64, fixedv: []const f64, k: usize, p0: f64, a: *mem.Arena) -> (f64, f64) {
    let dn = alloc_tmp(a, f.np)
    let est = ed_der(f, kind, alpha, fixedv, k, p0, a, dn)
    ret (est, math.sqrt[f64](quad(dn, f.vcov, f.np)))
}

// drc's EDcomp (selectivity index): the ratio ED(p1) of curve c1 over ED(p2) of curve c2 with its delta-method standard
// error; returns (ratio, standard error, t against 1, two-sided p value)
fn ed_comp(f: *const Fit, kind: i64, alpha: f64, fixedv: []const f64, c1: usize, c2: usize, p1: f64, p2: f64, a: *mem.Arena) -> (f64, f64, f64, f64) {
    let d1 = alloc_tmp(a, f.np)
    let d2 = alloc_tmp(a, f.np)
    let v1 = ed_der(f, kind, alpha, fixedv, c1, p1, a, d1)
    let v2 = ed_der(f, kind, alpha, fixedv, c2, p2, a, d2)
    let r = v1 / v2
    let dr = alloc_tmp(a, f.np)
    var i = 0usize
    while i < f.np {
        dr[i] = (d1[i] - r * d2[i]) / v2
        i += 1usize
    }
    let se = math.sqrt[f64](quad(dr, f.vcov, f.np))
    let t = (r - 1.0f64) / se
    ret (r, se, t, tail2(f, t))
}

fn tail2(f: *const Fit, t: f64) -> f64 {
    let at = math.abs[f64](t)
    if f.mode == 2 { ret 2.0f64 * dist.pnorm(0.0f64 - at, 0.0f64, 1.0f64, true, false) }
    ret 2.0f64 * nb.pt(0.0f64 - at, f.dfres, true, false)
}

// drc's compParm: curve c1 against curve c2 for the free parameter at position j (in the order of the free parameters), as a
// ratio (test against 1) or a difference (test against 0); returns (estimate, standard error, t, p value)
fn comp_parm(f: *const Fit, j: usize, c1: usize, c2: usize, ratio: bool) -> (f64, f64, f64, f64) {
    let i1 = j * f.ncurve + c1
    let i2 = j * f.ncurve + c2
    let p1 = f.par[i1]
    let p2 = f.par[i2]
    let v11 = f.vcov[i1 * f.np + i1]
    let v12 = f.vcov[i1 * f.np + i2]
    let v22 = f.vcov[i2 * f.np + i2]
    var est = p1 - p2
    var hyp = 0.0f64
    var t1 = 1.0f64
    var t2 = 0.0f64 - 1.0f64
    if ratio {
        est = p1 / p2
        hyp = 1.0f64
        t1 = 1.0f64 / p2
        t2 = 0.0f64 - p1 / (p2 * p2)
    }
    let se = math.sqrt[f64](t1 * t1 * v11 + 2.0f64 * t1 * t2 * v12 + t2 * t2 * v22)
    let t = (est - hyp) / se
    ret (est, se, t, tail2(f, t))
}

// 1-based positions in ascending order of v, ties in the order given (R's order); out[i] is the position of v[i]
fn rank_order(v: []const f64, out: []f64) {
    var i = 0usize
    while i < v.len {
        var r = 1.0f64
        var j = 0usize
        while j < v.len {
            if v[j] < v[i] || v[j] == v[i] && j < i { r += 1.0f64 }
            j += 1usize
        }
        out[i] = r
        i += 1usize
    }
}

// drc's modelFit lack-of-fit F test against the one-way ANOVA with a mean per (curve, dose): returns (F, p value, df of the
// test, df of pure error); needs replicates
fn lack_of_fit(f: *const Fit, dose: []const f64, resp: []const f64, grp: []const usize, a: *mem.Arena) -> (f64, f64, f64, f64) {
    let n = dose.len
    var pure = 0.0f64
    var groups = 0usize
    var i = 0usize
    let seen = alloc_tmp_usize(a, n)
    while i < n {
        if seen[i] == 0usize {
            var cnt = 0.0f64
            var sm = 0.0f64
            var j = i
            while j < n {
                if seen[j] == 0usize && dose[j] == dose[i] && grp[j] == grp[i] {
                    cnt += 1.0f64
                    sm += resp[j]
                }
                j += 1usize
            }
            let mu = sm / cnt
            j = i
            while j < n {
                if seen[j] == 0usize && dose[j] == dose[i] && grp[j] == grp[i] {
                    pure += (resp[j] - mu) * (resp[j] - mu)
                    seen[j] = 1usize
                }
                j += 1usize
            }
            groups += 1usize
        }
        i += 1usize
    }
    let dfp = f64(n) - f64(groups)
    let dft = f.dfres - dfp
    let fv = ((f.value - pure) / dft) / (pure / dfp)
    ret (fv, nb.pf(fv, dft, dfp, false, false), dft, dfp)
}
