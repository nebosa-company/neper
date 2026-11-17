// R stats bandwidth selectors by cross-validation: bw.ucv and bw.bcv for n <= 500 (pair-count binning, nb = 1000), each the minimiser of its criterion over [0.1 hmax, hmax] by R's optimize.
//
// Not here: bw.SJ, and the binned counting R uses for n > 500.

use e.algo.stat.fdrtool as fd
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
    let dd = (xmax - xmin) * 1.01f64 / f64(nb)
    i = 0usize
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
    let hmax = 1.144f64 * math.sqrt[f64](v) * math.pow[f64](f64(n), 0.0f64 - 0.2f64)
    var c = BwCtx{ n: n, nb: nb, d: d, cnt: cnt, kind: kind }
    ret fd.brent_min_tol[BwCtx](&c, bw_obj, 0.1f64 * hmax, hmax, 0.01f64 * hmax)
}
