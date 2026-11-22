// R ks, one dimension: the plug-in (hpi), smoothed cross-validation (hscv) and least-squares cross-validation (hlscv) bandwidths
// with the binned functional estimates they use (massdist1d linear binning, kdde.binned.1d, symconv.1d as a direct sum, kfe.1d).
//
// Not here: hscv and hlscv with deriv.order above 0, and the unbinned bw.ucv = FALSE form of hlscv.

use e.algo.stat.bwgen as bg
use e.algo.stat.classint as ci
use e.algo.stat.fdrtool as fd
use e.math
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// a + b exactly as hi + lo
fn two_sum(a: f64, b: f64) -> (f64, f64) {
    let s = a + b
    let bb = s - a
    ret (s, (a - (s - bb)) + (b - bb))
}

// a * b exactly as hi + lo (Dekker)
fn two_prod(a: f64, b: f64) -> (f64, f64) {
    let p = a * b
    let ca = 134217729.0f64 * a
    let ah = ca - (ca - a)
    let al = a - ah
    let cb = 134217729.0f64 * b
    let bh = cb - (cb - b)
    let bl = b - bh
    ret (p, ((ah * bh - p) + ah * bl + al * bh) + al * bl)
}

// mean(x) as R's long double sum, rounded once from double-double
fn mean_of(x: []const f64) -> f64 {
    var sh = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < x.len {
        let (t, e) = two_sum(sh, x[i])
        sh = t
        sl += e
        i += 1usize
    }
    let n = f64(x.len)
    let mh = sh / n
    let (ph, pl) = two_prod(mh, n)
    let ml = ((sh - ph) - pl + sl) / n
    ret mh + ml
}

// var(x) as R's long double two-pass sum: carried in double-double, rounded once
fn var_of(x: []const f64) -> f64 {
    let mu = mean_of(x)
    var qh = 0.0f64
    var ql = 0.0f64
    var i = 0usize
    while i < x.len {
        let d = x[i] - mu
        let (t, e) = two_sum(qh, d * d)
        qh = t
        ql += e
        i += 1usize
    }
    let n1 = f64(x.len) - 1.0f64
    let q1 = qh / n1
    let (ph, pl) = two_prod(q1, n1)
    ret q1 + ((qh - ph) - pl + ql) / n1
}

// dnorm.deriv(x, 0, sigma, r)
fn dnorm_deriv(x: f64, sigma: f64, r: usize) -> f64 {
    let arg = x / sigma
    let phi = math.exp[f64](0.0f64 - 0.5f64 * arg * arg) / (2.5066282746310002f64 * sigma)
    var hm0 = 1.0f64
    var hm1 = arg
    var hmn = 1.0f64
    if r == 1usize { hmn = hm1 }
    var i = 2usize
    while i <= r {
        hmn = arg * hm1 - f64(i - 1usize) * hm0
        hm0 = hm1
        hm1 = hmn
        i += 1usize
    }
    var sg = 1.0f64
    if r % 2usize == 1usize { sg = 0.0f64 - 1.0f64 }
    ret sg * phi * hmn / math.pow[f64](sigma, f64(r))
}

// psins.1d(r, sigma)
fn psins_1d(r: usize, sigma: f64) -> f64 {
    if r % 2usize == 1usize { ret 0.0f64 }
    var f = 1.0f64
    var i = 2usize
    while i <= r {
        f *= f64(i)
        i += 1usize
    }
    var fh = 1.0f64
    i = 2usize
    while i <= r / 2usize {
        fh *= f64(i)
        i += 1usize
    }
    var sg = 1.0f64
    if (r / 2usize) % 2usize == 1usize { sg = 0.0f64 - 1.0f64 }
    ret sg * f / (math.pow[f64](2.0f64 * sigma, f64(r + 1usize)) * fh * 1.7724538509055159f64)
}

// the C routine massdist1d: linear binning onto m grid points from lo to hi (points just outside keep their inside half)
fn massdist_1d(a: *mem.Arena, x: []const f64, lo: f64, hi: f64, m: usize) -> ([]f64, err) {
    let (g, e) = mem.alloc[f64](a, m)
    if e != ok { ret (g, e) }
    var i = 0usize
    while i < m {
        g[i] = 0.0f64
        i += 1usize
    }
    let delta = (hi - lo) / f64(m - 1usize)
    i = 0usize
    while i < x.len {
        let pos = (x[i] - lo) / delta
        let ix = i64(math.floor[f64](pos))
        let fx = pos - f64(ix)
        if ix >= 0i64 && ix <= i64(m) - 2i64 {
            g[usize(ix)] += 1.0f64 - fx
            g[usize(ix) + 1usize] += fx
        } else if ix == 0i64 - 1i64 {
            g[0usize] += fx
        } else if ix == i64(m) - 1i64 {
            g[usize(ix)] += 1.0f64 - fx
        }
        i += 1usize
    }
    ret (g, ok)
}

// kfe.1d on a binned grid (counts on lo..hi): dnorm.deriv.sum(binned) through kdde.binned.1d and symconv.1d
fn kfe_1d_binned(a: *mem.Arena, counts: []const f64, lo: f64, hi: f64, g: f64, r: usize, inc: bool, nobs: usize) -> f64 {
    let m = counts.len
    var n = 0.0f64
    var i = 0usize
    while i < m {
        n += counts[i]
        i += 1usize
    }
    let delta = (hi - lo) / f64(m - 1usize)
    var l = usize(math.ceil[f64](f64(4usize + r) * g / delta))
    if l > m - 1usize { l = m - 1usize }
    let nn = 2usize * l - 1usize
    // symconv.1d places the counts at round(N / 2) + 1 and R rounds half to even; N / 2 = l - 0.5
    var rd = l
    if (l - 1usize) % 2usize == 0usize { rd = l - 1usize }
    let lp = rd + 1usize
    let start = mem.mark(a)
    let (ke, e) = mem.alloc[f64](a, nn)
    if e != ok { ret nan() }
    var k = 0usize
    while k < nn {
        ke[k] = dnorm_deriv(delta * (f64(k) - f64(l - 1usize)), g, r) / n
        k += 1usize
    }
    var sumval = 0.0f64
    var t = 1usize
    while t <= m {
        var est = 0.0f64
        var j = 1usize
        while j <= nn {
            let c = i64(nn + t + 1usize) - i64(j) - i64(lp)
            if c >= 1i64 && c <= i64(m) { est += ke[j - 1usize] * counts[usize(c) - 1usize] }
            j += 1usize
        }
        sumval += counts[t - 1usize] * est * f64(nobs)
        t += 1usize
    }
    mem.reset(a, start)
    let nf = f64(nobs)
    var psi = sumval / (nf * nf)
    if !inc { psi = (nf * nf * psi - nf * dnorm_deriv(0.0f64, g, r)) / (nf * (nf - 1.0f64)) }
    ret psi
}

fn kfe_1d_direct(x: []const f64, g: f64, r: usize, inc: bool) -> f64 {
    let n = f64(x.len)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        var j = 0usize
        while j < x.len {
            s += dnorm_deriv(x[i] - x[j], g, r)
            j += 1usize
        }
        i += 1usize
    }
    var psi = s / (n * n)
    if !inc { psi = (n * n * psi - n * dnorm_deriv(0.0f64, g, r)) / (n * (n - 1.0f64)) }
    ret psi
}

fn min_of(x: []const f64) -> f64 {
    var m = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] < m { m = x[i] }
        i += 1usize
    }
    ret m
}

fn max_of(x: []const f64) -> f64 {
    var m = x[0usize]
    var i = 1usize
    while i < x.len {
        if x[i] > m { m = x[i] }
        i += 1usize
    }
    ret m
}

// kfe.1d(x, g, r, inc, binned) with no bin.par: binning(x, h = g, supp = 4 + r) on the default 401 grid
fn kfe_1d(a: *mem.Arena, x: []const f64, g: f64, r: usize, inc: bool, binned: bool) -> f64 {
    if !binned { ret kfe_1d_direct(x, g, r, inc) }
    let lo = min_of(x) - f64(4usize + r) * g
    let hi = max_of(x) + f64(4usize + r) * g
    let start = mem.mark(a)
    let (c, e) = massdist_1d(a, x, lo, hi, 401usize)
    if e != ok { ret nan() }
    let v = kfe_1d_binned(a, c, lo, hi, g, r, inc, x.len)
    mem.reset(a, start)
    ret v
}

fn dpik_level(a: *mem.Arena, x: []const f64, level: usize) -> f64 {
    let n = f64(x.len)
    let (s, se) = ci.sorted_copy(a, x)
    if se != ok { ret nan() }
    let mu = mean_of(x)
    let iqr = (ci.quantile7(s, 0.75f64) - ci.quantile7(s, 0.25f64)) / 1.349f64
    var sc = math.sqrt[f64](var_of(x))
    if iqr < sc { sc = iqr }
    let sa = (s[0usize] - mu) / sc
    let sb = (s[s.len - 1usize] - mu) / sc
    let (sx, xe) = mem.alloc[f64](a, x.len)
    if xe != ok { ret nan() }
    var i = 0usize
    while i < x.len {
        sx[i] = (x[i] - mu) / sc
        i += 1usize
    }
    let (g, ge) = ci.linbin(a, sx, sa, sb, 401usize)
    if ge != ok { ret nan() }
    let sqrt2 = math.sqrt[f64](2.0f64)
    var psi4 = 3.0f64 / (8.0f64 * 1.7724538509055159f64)
    if level == 1usize {
        let alpha = math.pow[f64](2.0f64 * math.pow[f64](sqrt2, 7.0f64) / (5.0f64 * n), 1.0f64 / 7.0f64)
        psi4 = ci.bkfe(g, 4usize, alpha, sa, sb)
    } else if level == 2usize {
        var alpha = math.pow[f64](2.0f64 * math.pow[f64](sqrt2, 9.0f64) / (7.0f64 * n), 1.0f64 / 9.0f64)
        let psi6 = ci.bkfe(g, 6usize, alpha, sa, sb)
        alpha = math.pow[f64](0.0f64 - 3.0f64 * math.sqrt[f64](2.0f64 / 3.141592653589793f64) / (psi6 * n), 1.0f64 / 7.0f64)
        psi4 = ci.bkfe(g, 4usize, alpha, sa, sb)
    }
    let del0 = 1.0f64 / math.pow[f64](4.0f64 * 3.141592653589793f64, 0.1f64)
    ret sc * del0 * math.pow[f64](1.0f64 / (psi4 * n), 0.2f64)
}

// hpi(x, nstage, binned, deriv.order = r)
fn hpi(a: *mem.Arena, x: []const f64, nstage: usize, binned: bool, r: usize) -> f64 {
    if r == 0usize { ret dpik_level(a, x, nstage) }
    let n = f64(x.len)
    let sg = math.sqrt[f64](var_of(x))
    let k4 = dnorm_deriv(0.0f64, 1.0f64, 2usize * r + 4usize)
    let k6 = dnorm_deriv(0.0f64, 1.0f64, 2usize * r + 6usize)
    let mr = psins_1d(2usize * r, 1.0f64)
    var psi4 = 0.0f64
    if nstage == 2usize {
        let psi8 = psins_1d(2usize * r + 8usize, sg)
        let g6 = math.pow[f64](2.0f64 * k6 / (0.0f64 - psi8 * n), 1.0f64 / f64(2usize * r + 9usize))
        let psi6 = kfe_1d(a, x, g6, 2usize * r + 6usize, true, binned)
        let g4 = math.pow[f64](2.0f64 * k4 / (0.0f64 - psi6 * n), 1.0f64 / f64(2usize * r + 7usize))
        psi4 = kfe_1d(a, x, g4, 2usize * r + 4usize, true, binned)
    } else {
        let psi6 = psins_1d(2usize * r + 6usize, sg)
        let g4 = math.pow[f64](2.0f64 * k4 / (0.0f64 - psi6 * n), 1.0f64 / f64(2usize * r + 7usize))
        psi4 = kfe_1d(a, x, g4, 2usize * r + 4usize, true, binned)
    }
    ret math.pow[f64](f64(2usize * r + 1usize) * mr / (psi4 * n), 1.0f64 / f64(2usize * r + 5usize))
}

type ScvCtx = struct { a: *mem.Arena, x: []const f64, counts: []const f64, lo: f64, hi: f64, binned: bool, c: f64 }

fn kfe_ctx(s: *ScvCtx, g: f64, r: usize) -> f64 {
    if s.binned { ret kfe_1d_binned(s.a, s.counts, s.lo, s.hi, g, r, true, s.x.len) }
    ret kfe_1d_direct(s.x, g, r, true)
}

// scv.1d with deriv.order 0 and g = C n^(-23/45) h^-2
fn scv_obj(s: *ScvCtx, h: f64) -> f64 {
    let n = f64(s.x.len)
    let g = s.c * math.pow[f64](n, 0.0f64 - 23.0f64 / 45.0f64) / (h * h)
    let s1 = kfe_ctx(s, math.sqrt[f64](2.0f64 * h * h + 2.0f64 * g * g), 0usize)
    let s2 = kfe_ctx(s, math.sqrt[f64](h * h + 2.0f64 * g * g), 0usize)
    let s3 = kfe_ctx(s, math.sqrt[f64](2.0f64 * g * g), 0usize)
    var bias2 = s1 - 2.0f64 * s2 + s3
    if bias2 < 0.0f64 { bias2 = 0.0f64 }
    ret 1.0f64 / (n * h) / math.sqrt[f64](4.0f64 * 3.141592653589793f64) + bias2
}

// hscv(x, nstage, binned)
fn hscv(a: *mem.Arena, x: []const f64, nstage: usize, binned: bool) -> f64 {
    let n = f64(x.len)
    let sg = math.sqrt[f64](var_of(x))
    let hnorm = math.sqrt[f64](math.pow[f64](4.0f64 / (n * 3.0f64), 2.0f64 / 5.0f64) * var_of(x))
    let lo = min_of(x) - 3.7f64 * hnorm
    let hi = max_of(x) + 3.7f64 * hnorm
    let (c0, e) = massdist_1d(a, x, lo, hi, 401usize)
    if e != ok { ret nan() }
    var s = ScvCtx{ a: a, x: x, counts: c0, lo: lo, hi: hi, binned: binned, c: 0.0f64 }
    var psi6 = psins_1d(6usize, sg)
    var psi10 = psins_1d(10usize, sg)
    if nstage == 2usize {
        let g1 = math.pow[f64](2.0f64 / (7.0f64 * n), 1.0f64 / 9.0f64) * math.sqrt[f64](2.0f64) * sg
        let g2 = math.pow[f64](2.0f64 / (11.0f64 * n), 1.0f64 / 13.0f64) * math.sqrt[f64](2.0f64) * sg
        psi6 = kfe_ctx(&s, g1, 6usize)
        psi10 = kfe_ctx(&s, g2, 10usize)
    }
    let sq2pi = math.sqrt[f64](2.0f64 * 3.141592653589793f64)
    let g3 = math.pow[f64](0.0f64 - 6.0f64 / (sq2pi * psi6 * n), 1.0f64 / 7.0f64)
    let g4 = math.pow[f64](0.0f64 - 210.0f64 / (sq2pi * psi10 * n), 1.0f64 / 11.0f64)
    let psi4 = kfe_ctx(&s, g3, 4usize)
    let psi8 = kfe_ctx(&s, g4, 8usize)
    let pi = 3.141592653589793f64
    s.c = math.pow[f64](441.0f64 / (64.0f64 * pi), 1.0f64 / 18.0f64) * math.pow[f64](4.0f64 * pi, 0.0f64 - 0.2f64) * math.pow[f64](psi4, 0.0f64 - 0.4f64) * math.pow[f64](psi8, 0.0f64 - 1.0f64 / 9.0f64)
    ret fd.brent_min[ScvCtx](&s, scv_obj, 0.1f64 * hnorm, 2.0f64 * hnorm)
}

// hlscv(x) with its default bw.ucv = TRUE: stats::bw.ucv(x, nb = 10000, lower = the smallest positive gap)
fn hlscv(a: *mem.Arena, x: []const f64) -> f64 {
    var lower = 1.0e300f64
    var i = 0usize
    while i < x.len {
        var j = i + 1usize
        while j < x.len {
            var d = x[i] - x[j]
            if d < 0.0f64 { d = 0.0f64 - d }
            if d > 0.0f64 && d < lower { lower = d }
            j += 1usize
        }
        i += 1usize
    }
    ret bg.bw_cv_gen(a, x, 0u8, 10000usize, lower, nan(), nan())
}
