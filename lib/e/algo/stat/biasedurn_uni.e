// R BiasedUrn, the univariate mean and variance at the package's precision, and the range functions.
//
// meanFNCHypergeo / varFNCHypergeo / meanWNCHypergeo / varWNCHypergeo return the closed-form approximation at a precision of
// 0.1 or more (Cornfield's root for Fisher, a Newton iteration for Wallenius; the variance formula is shared) and below it
// sum the probabilities outward from the integer part of that approximate mean until a term falls under a tenth of the
// precision. Both are reproduced, so a loose precision gives R's loose answer and a tight one its exact sums.
// minHypergeo, maxHypergeo, minMHypergeo and maxMHypergeo are the support limits.

use e.algo.stat.biasedurn as bu
use e.algo.stat.biasedurn_mv as mv
use e.algo.stat.biasedurn_rand as br
use e.math
use e.mem

fn nan_of() -> f64 { ret 0.0f64 / 0.0f64 }

fn min_hyper(m1: f64, m2: f64, n: f64) -> f64 { ret math.max[f64](0.0f64, n - m2) }

fn max_hyper(m1: f64, m2: f64, n: f64) -> f64 { ret math.min[f64](n, m1) }

// the range of colour i of an urn with counts m, n drawn: minMHypergeo and maxMHypergeo
fn min_mhyper(mi: f64, nt: f64, n: f64) -> f64 { ret math.max[f64](0.0f64, n - (nt - mi)) }

fn max_mhyper(mi: f64, n: f64) -> f64 { ret math.min[f64](n, mi) }

// kind 0 Fisher, 1 Wallenius; what 0 the mean, 1 the variance
fn uni_moment(a: *mem.Arena, kind: usize, prec0: f64, m1: f64, m2: f64, n: f64, w: f64, what: usize) -> f64 {
    var prec = prec0
    if !(prec == prec) || prec < 0.0f64 { prec = 1.0e-7f64 }
    let nn = m1 + m2
    var mean0 = 0.0f64
    if kind == 0usize { mean0 = mv.fnc_mean(n, m1, nn, w) } else { mean0 = br.wnc_mean(n, m1, nn, w) }
    if prec >= 0.1f64 {
        if what == 0usize { ret mean0 }
        ret mv.approx_var(mean0, m1, n, nn)
    }
    let lo = bu.lo_of(m2, n)
    let hi = bu.hi_of(m1, n)
    let (pmf, e) = mem.alloc[f64](a, usize(hi - lo) + 2usize)
    if e != ok { ret nan_of() }
    if kind == 0usize { let _ = bu.fisher_pmf(m1, m2, n, w, pmf) }
    let accur = 0.1f64 * prec
    let xm = math.trunc[f64](mean0)
    var sy = 0.0f64
    var sxy = 0.0f64
    var sxxy = 0.0f64
    var x = xm
    while x <= hi {
        var y = 0.0f64
        if kind == 0usize { y = pmf[usize(x - lo)] } else { y = br.wnc_prob(x, n, m1, nn, w) }
        let d = x - xm
        sy += y
        sxy += d * y
        sxxy += d * d * y
        if y < accur && x != xm { break }
        x += 1.0f64
    }
    x = xm - 1.0f64
    while x >= lo {
        var y = 0.0f64
        if kind == 0usize { y = pmf[usize(x - lo)] } else { y = br.wnc_prob(x, n, m1, nn, w) }
        let d = x - xm
        sy += y
        sxy += d * y
        sxxy += d * d * y
        if y < accur { break }
        x -= 1.0f64
    }
    let me = sxy / sy
    if what == 0usize { ret xm + me }
    let v = sxxy / sy - me * me
    if v < 0.0f64 { ret 0.0f64 }
    ret v
}
