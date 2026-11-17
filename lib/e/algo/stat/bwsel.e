// R stats bandwidth selectors by cross-validation: bw.ucv and bw.bcv for n <= 500 (pair-count binning, nb = 1000), each the minimiser of its criterion over [0.1 hmax, hmax] by R's optimize.
//
// And bw.SJ (method "ste"). Not here: the binned counting R uses for n > 500, and the other bw.SJ method ("dpi").

use e.algo.stat.classint as ci
use e.algo.stat.fdrtool as fd
use e.algo.stat.mass as ms
use e.algo.stat.pwr as pw
use e.math
use e.mem

type BwCtx = struct { n: usize, nb: usize, d: []f64, cnt: []f64, kind: u8 }

fn bw_obj(c: *BwCtx, h: f64) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < c.nb {
        var delta = c.d[i] / h
        delta = delta * delta
        if delta >= 1000.0f64 { break }
        if c.kind == 0u8 {
            sum += (math.exp[f64](0.0f64 - delta / 4.0f64) - math.sqrt[f64](8.0f64) * math.exp[f64](0.0f64 - delta / 2.0f64)) * c.cnt[i]
        } else {
            sum += math.exp[f64](0.0f64 - delta / 4.0f64) * (delta * delta - 12.0f64 * delta + 12.0f64) * c.cnt[i]
        }
        i += 1usize
    }
    let nf = f64(c.n)
    let sp = 1.7724538509055159f64
    if c.kind == 0u8 { ret (0.5f64 + sum / nf) / (nf * h * sp) }
    ret (1.0f64 + sum / (32.0f64 * nf)) / (2.0f64 * nf * h * sp)
}

fn bin_pairs(x: []const f64, xmin: f64, xmax: f64, d: []f64, cnt: []f64) {
    let n = x.len
    let nb = d.len
    let dd = (xmax - xmin) * 1.01f64 / f64(nb)
    var i = 0usize
    while i < nb {
        d[i] = f64(i) * dd
        cnt[i] = 0.0f64
        i += 1usize
    }
    i = 1usize
    while i < n {
        let ii = i64(x[i] / dd)
        var j = 0usize
        while j < i {
            var q = ii - i64(x[j] / dd)
            if q < 0i64 { q = 0i64 - q }
            cnt[usize(q)] += 1.0f64
            j += 1usize
        }
        i += 1usize
    }
}

// stats::bw.ucv (kind 0) and bw.bcv (kind 1) for n <= 500, the pair-count binning (nb = 1000): the minimiser of the unbiased / biased cross-validation criterion on [0.1 hmax, hmax] by R's optimize with tol 0.1 lower
fn bw_cv(a: *mem.Arena, x: []const f64, kind: u8) -> f64 {
    let n = x.len
    let nb = 1000usize
    let (d, e1) = mem.alloc[f64](a, nb)
    let (cnt, e2) = mem.alloc[f64](a, nb)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var xmin = x[0usize]
    var xmax = x[0usize]
    var i = 0usize
    var s = 0.0f64
    while i < n {
        if x[i] < xmin { xmin = x[i] }
        if x[i] > xmax { xmax = x[i] }
        s += x[i]
        i += 1usize
    }
    let mean = s / f64(n)
    var v = 0.0f64
    i = 0usize
    while i < n {
        v += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    v = v / f64(n - 1usize)
    bin_pairs(x, xmin, xmax, d, cnt)
    let hmax = 1.144f64 * math.sqrt[f64](v) * math.pow[f64](f64(n), 0.0f64 - 0.2f64)
    var c = BwCtx{ n: n, nb: nb, d: d, cnt: cnt, kind: kind }
    ret fd.brent_min_tol[BwCtx](&c, bw_obj, 0.1f64 * hmax, hmax, 0.01f64 * hmax)
}

type SjCtx = struct { n: usize, nb: usize, d: []f64, cnt: []f64, a2: f64, c1: f64 }

fn sj_phi(c: *SjCtx, h: f64, six: bool) -> f64 {
    var sum = 0.0f64
    var i = 0usize
    while i < c.nb {
        var delta = c.d[i] / h
        delta = delta * delta
        if delta >= 1000.0f64 { break }
        if six {
            sum += math.exp[f64](0.0f64 - delta / 2.0f64) * (delta * delta * delta - 15.0f64 * delta * delta + 45.0f64 * delta - 15.0f64) * c.cnt[i]
        } else {
            sum += math.exp[f64](0.0f64 - delta / 2.0f64) * (delta * delta - 6.0f64 * delta + 3.0f64) * c.cnt[i]
        }
        i += 1usize
    }
    let nf = f64(c.n)
    let sq = 2.5066282746310002f64
    if six {
        sum = 2.0f64 * sum - 15.0f64 * nf
        ret sum / (nf * (nf - 1.0f64) * math.pow[f64](h, 7.0f64) * sq)
    }
    sum = 2.0f64 * sum + nf * 3.0f64
    ret sum / (nf * (nf - 1.0f64) * math.pow[f64](h, 5.0f64) * sq)
}

fn sj_f(c: *SjCtx, h: f64) -> f64 {
    ret math.pow[f64](c.c1 / sj_phi(c, c.a2 * math.pow[f64](h, 5.0f64 / 7.0f64), false), 0.2f64) - h
}

// stats::bw.SJ (method "ste") for n <= 500: the Sheather-Jones solve-the-equation bandwidth, the root of fSD over [0.1 hmax, hmax] by uniroot with tolerance 0.1 lower; 0 when the bracket has no sign change
fn bw_sj(a: *mem.Arena, x: []const f64) -> f64 {
    let n = x.len
    let nb = 1000usize
    let (d, e1) = mem.alloc[f64](a, nb)
    let (cnt, e2) = mem.alloc[f64](a, nb)
    let (s, e3) = ci.sorted_copy(a, x)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    let nf = f64(n)
    var m = 0.0f64
    var i = 0usize
    while i < n {
        m += x[i]
        i += 1usize
    }
    m = m / nf
    var v = 0.0f64
    i = 0usize
    while i < n {
        v += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    let sd = math.sqrt[f64](v / (nf - 1.0f64))
    var scale = sd
    let iqr = (ms.quant7(s, 0.75f64) - ms.quant7(s, 0.25f64)) / 1.349f64
    if iqr < scale { scale = iqr }
    bin_pairs(x, s[0usize], s[n - 1usize], d, cnt)
    let a1 = 1.24f64 * scale * math.pow[f64](nf, 0.0f64 - 1.0f64 / 7.0f64)
    let b1 = 1.23f64 * scale * math.pow[f64](nf, 0.0f64 - 1.0f64 / 9.0f64)
    var c = SjCtx{ n: n, nb: nb, d: d, cnt: cnt, a2: 0.0f64, c1: 1.0f64 / (2.0f64 * 1.7724538509055159f64 * nf) }
    let td = 0.0f64 - sj_phi(&c, b1, true)
    c.a2 = 1.357f64 * math.pow[f64](sj_phi(&c, a1, false) / td, 1.0f64 / 7.0f64)
    let hmax = 1.144f64 * scale * math.pow[f64](nf, 0.0f64 - 0.2f64)
    var lower = 0.1f64 * hmax
    var upper = hmax
    let tol = 0.1f64 * lower
    var itry = 1usize
    while sj_f(&c, lower) * sj_f(&c, upper) > 0.0f64 {
        if itry > 99usize { ret 0.0f64 / 0.0f64 }
        if itry % 2usize == 1usize { upper = upper * 1.2f64 } else { lower = lower / 1.2f64 }
        itry += 1usize
    }
    ret pw.zeroin[SjCtx](&c, sj_f, lower, upper, tol, 1000i64)
}
