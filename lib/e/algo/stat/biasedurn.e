// R BiasedUrn, the univariate part: Fisher's and Wallenius' noncentral hypergeometric distributions of the number
// x of red balls among n drawn from m1 red and m2 white, with odds ratio w: the whole mass function over the
// support, from which `p` (cumulative), `q` (quantile), `mean`, `var` and `mode` follow, and `odds_fisher` (the odds that make an observed count the expectation) and `mode_fisher` (the closed-form mode). Fisher's is the normalised `C(m1, x) C(m2, n - x) w^x`; Wallenius' is the
// same binomial product times `int_0^1 (1 - t^(w/D))^x (1 - t^(1/D))^(n-x) dt` with
// `D = w (m1 - x) + (m2 - n + x)`, integrated by tanh-sinh quadrature after the substitution `t = u^D`.
//
// Not here: the multivariate variants, random variates, the stochastic odds estimation, the `precision`
// argument (the quadrature is fixed and accurate to about 1e-12).

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

fn lchoose(n: f64, k: f64) -> f64 { ret nm.lgammafn(n + 1.0f64) - nm.lgammafn(k + 1.0f64) - nm.lgammafn(n - k + 1.0f64) }

fn lo_of(m2: f64, n: f64) -> f64 {
    if n - m2 > 0.0f64 { ret n - m2 }
    ret 0.0f64
}

fn hi_of(m1: f64, n: f64) -> f64 {
    if n < m1 { ret n }
    ret m1
}

// Fisher: pmf[k] for x = lo + k; returns the count
fn fisher_pmf(m1: f64, m2: f64, n: f64, w: f64, pmf: []f64) -> usize {
    let lo = lo_of(m2, n)
    let hi = hi_of(m1, n)
    let cnt = usize(hi - lo) + 1usize
    var mx = 0.0f64 - 1.0e300f64
    var k = 0usize
    while k < cnt {
        let x = lo + f64(k)
        let l = lchoose(m1, x) + lchoose(m2, n - x) + x * math.log[f64](w)
        pmf[k] = l
        if l > mx { mx = l }
        k += 1usize
    }
    var s = 0.0f64
    k = 0usize
    while k < cnt {
        pmf[k] = math.exp[f64](pmf[k] - mx)
        s += pmf[k]
        k += 1usize
    }
    k = 0usize
    while k < cnt {
        pmf[k] = pmf[k] / s
        k += 1usize
    }
    ret cnt
}

// integrand of Wallenius in u = t^(1/D): (1 - u^w)^x (1 - u)^(n-x) D u^(D-1), at u with log u = lu and 1 - u = omu
fn wall_integrand(x: f64, n: f64, w: f64, d: f64, lu: f64, omu: f64) -> f64 {
    var v = d * math.exp[f64]((d - 1.0f64) * lu)
    if x > 0.0f64 { v = v * math.pow[f64](0.0f64 - dist.expm1(w * lu), x) }
    if n - x > 0.0f64 { v = v * math.pow[f64](omu, n - x) }
    ret v
}

fn wallenius_term(x: f64, m1: f64, m2: f64, n: f64, w: f64) -> f64 {
    let d = w * (m1 - x) + (m2 - n + x)
    let pi = 3.141592653589793f64
    let h = 1.0f64 / 32.0f64
    var s = 0.0f64
    var j = 0i64 - 160i64
    while j <= 160i64 {
        let t = f64(j) * h
        let ex = math.exp[f64](t)
        let sh = (ex - 1.0f64 / ex) / 2.0f64
        let ch = (ex + 1.0f64 / ex) / 2.0f64
        let a = pi / 2.0f64 * sh
        // u = 1 / (1 + e^(-2a)), 1 - u = 1 / (1 + e^(2a))
        var u = 0.0f64
        var omu = 0.0f64
        var lu = 0.0f64
        if a >= 0.0f64 {
            let e = math.exp[f64](0.0f64 - 2.0f64 * a)
            u = 1.0f64 / (1.0f64 + e)
            omu = e / (1.0f64 + e)
            lu = 0.0f64 - dist.log1p(e)
        } else {
            let e = math.exp[f64](2.0f64 * a)
            u = e / (1.0f64 + e)
            omu = 1.0f64 / (1.0f64 + e)
            lu = 2.0f64 * a - dist.log1p(e)
        }
        // weight dt-density of the tanh-sinh map on [0, 1]: (pi / 4) cosh t / cosh^2(a)
        let e2 = math.exp[f64](a)
        let cha = (e2 + 1.0f64 / e2) / 2.0f64
        let wt = pi / 4.0f64 * ch / (cha * cha)
        if wt > 1.0e-300f64 && u > 0.0f64 { s += wt * wall_integrand(x, n, w, d, lu, omu) }
        j += 1i64
    }
    ret s * h * math.exp[f64](lchoose(m1, x) + lchoose(m2, n - x))
}

fn wallenius_pmf(m1: f64, m2: f64, n: f64, w: f64, pmf: []f64) -> usize {
    let lo = lo_of(m2, n)
    let hi = hi_of(m1, n)
    let cnt = usize(hi - lo) + 1usize
    var k = 0usize
    while k < cnt {
        pmf[k] = wallenius_term(lo + f64(k), m1, m2, n, w)
        k += 1usize
    }
    ret cnt
}

// d, p (lower tail), q, mean, var, mode of a pmf over lo.. (kind: 0 d at x, 1 p at x, 2 q at prob, 3 mean, 4 var, 5 mode)
fn summarise(pmf: []const f64, cnt: usize, lo: f64, kind: u8, arg: f64) -> f64 {
    if kind == 0u8 {
        let k = arg - lo
        if k < 0.0f64 || k >= f64(cnt) { ret 0.0f64 }
        ret pmf[usize(k)]
    }
    if kind == 1u8 {
        var s = 0.0f64
        var k = 0usize
        while k < cnt && lo + f64(k) <= arg {
            s += pmf[k]
            k += 1usize
        }
        ret s
    }
    if kind == 2u8 {
        var s = 0.0f64
        var k = 0usize
        while k < cnt {
            s += pmf[k]
            if s >= arg * (1.0f64 - 64.0f64 * 2.220446049250313e-16f64) { ret lo + f64(k) }
            k += 1usize
        }
        ret lo + f64(cnt - 1usize)
    }
    if kind == 5u8 {
        var best = 0usize
        var k = 1usize
        while k < cnt {
            if pmf[k] > pmf[best] { best = k }
            k += 1usize
        }
        ret lo + f64(best)
    }
    var s0 = 0.0f64
    var s1 = 0.0f64
    var s2 = 0.0f64
    var k = 0usize
    while k < cnt {
        let x = lo + f64(k)
        s0 += pmf[k]
        s1 += pmf[k] * x
        s2 += pmf[k] * x * x
        k += 1usize
    }
    let mean = s1 / s0
    if kind == 3u8 { ret mean }
    ret s2 / s0 - mean * mean
}

// oddsFNCHypergeo(x, m1, m2, n): the odds ratio that makes the observed count x the cell expectation of the
// 2 by 2 table, `x (m2 - n + x) / ((m1 - x) (n - x))`
fn odds_fisher(x: f64, m1: f64, m2: f64, n: f64) -> f64 { ret x * (m2 - n + x) / ((m1 - x) * (n - x)) }

// modeFNCHypergeo: floor(2 C / (B + sqrt(B^2 - 4 A C))) with A = w - 1, B = (m1 + n + 2) w + m2 - n,
// C = (m1 + 1)(n + 1) w, and floor((m1 + 1)(n + 1) / (m1 + m2 + 2)) at w = 1
fn mode_fisher(m1: f64, m2: f64, n: f64, w: f64) -> f64 {
    if w == 1.0f64 { ret math.floor[f64]((m1 + 1.0f64) * (n + 1.0f64) / (m1 + m2 + 2.0f64)) }
    let aa = w - 1.0f64
    let bb = (m1 + n + 2.0f64) * w + m2 - n
    let cc = (m1 + 1.0f64) * (n + 1.0f64) * w
    ret math.floor[f64](2.0f64 * cc / (bb + math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)))
}
