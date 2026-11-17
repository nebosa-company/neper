// R BiasedUrn, the univariate part: Fisher's and Wallenius' noncentral hypergeometric distributions of the number
// x of red balls among n drawn from m1 red and m2 white, with odds ratio w: the whole mass function over the
// support, from which `p` (cumulative), `q` (quantile), `mean`, `var` and `mode` follow, and `odds_fisher` (the odds that make an observed count the expectation) and `mode_fisher` (the closed-form mode). Fisher's is the normalised `C(m1, x) C(m2, n - x) w^x`; Wallenius' is the
// same binomial product times `int_0^1 (1 - t^(w/D))^x (1 - t^(1/D))^(n-x) dt` with
// `D = w (m1 - x) + (m2 - n + x)`, integrated by tanh-sinh quadrature after the substitution `t = u^D`.
//
// The multivariate moments, odds and ball-count estimators are in biasedurn_mv.e, the univariate moments at a given precision in
// biasedurn_uni.e and the random variates in biasedurn_rand.e. Not here: the `precision` argument of the mass function itself
// (the quadrature is refined to about 1e-14, where the package stops at the precision asked, 1e-7 by default).

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

// integrand of Wallenius in u = t^(1/D), as a log: lc + ln D + (D - 1) ln u + x ln(1 - u^w) + (n - x) ln(1 - u), at u with log u = lu and 1 - u = omu
fn wall_integrand(x: f64, n: f64, w: f64, d: f64, lu: f64, omu: f64, lc: f64) -> f64 {
    var lv = lc + math.log[f64](d) + (d - 1.0f64) * lu
    if x > 0.0f64 { lv += x * math.log[f64](0.0f64 - dist.expm1(w * lu)) }
    if n - x > 0.0f64 { lv += (n - x) * math.log[f64](omu) }
    ret math.exp[f64](lv)
}

// tanh-sinh sum at node spacing h
fn wallenius_sum(x: f64, n: f64, w: f64, d: f64, lc: f64, h: f64) -> f64 {
    let pi = 3.141592653589793f64
    var s = 0.0f64
    let jmax = i64(5.0f64 / h)
    var j = 0i64 - jmax
    while j <= jmax {
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
        if wt > 1.0e-300f64 && u > 0.0f64 && omu > 0.0f64 { s += wt * wall_integrand(x, n, w, d, lu, omu, lc) }
        j += 1i64
    }
    ret s * h
}

// the node spacing is halved from 1/32 until two successive sums agree, so a peaked integrand (large n) is resolved
fn wallenius_term(x: f64, m1: f64, m2: f64, n: f64, w: f64) -> f64 {
    let d = w * (m1 - x) + (m2 - n + x)
    let lc = lchoose(m1, x) + lchoose(m2, n - x)
    var h = 1.0f64 / 32.0f64
    var prev = wallenius_sum(x, n, w, d, lc, h)
    var lvl = 0usize
    while lvl < 4usize {
        h = h / 2.0f64
        let cur = wallenius_sum(x, n, w, d, lc, h)
        let dd = math.abs[f64](cur - prev)
        prev = cur
        if dd <= 1.0e-14f64 * cur || cur == 0.0f64 { break }
        lvl += 1usize
    }
    ret prev
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

// oddsWNCHypergeo(mu, m1, m2, n): the odds that make mu the Wallenius expectation, log(1 - mu / m1) / log(1 - (n - mu) / m2)
fn odds_wall(mu: f64, m1: f64, m2: f64, n: f64) -> f64 { ret math.log[f64](1.0f64 - mu / m1) / math.log[f64](1.0f64 - (n - mu) / m2) }

// modeFNCHypergeo: floor(2 C / (B + sqrt(B^2 - 4 A C))) with A = w - 1, B = (m1 + n + 2) w + m2 - n,
// C = (m1 + 1)(n + 1) w, and floor((m1 + 1)(n + 1) / (m1 + m2 + 2)) at w = 1
fn mode_fisher(m1: f64, m2: f64, n: f64, w: f64) -> f64 {
    if w == 1.0f64 { ret math.floor[f64]((m1 + 1.0f64) * (n + 1.0f64) / (m1 + m2 + 2.0f64)) }
    let aa = w - 1.0f64
    let bb = (m1 + n + 2.0f64) * w + m2 - n
    let cc = (m1 + 1.0f64) * (n + 1.0f64) * w
    ret math.floor[f64](2.0f64 * cc / (bb + math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)))
}

// ---- the multivariate variants (dMFNCHypergeo, dMWNCHypergeo, their means and variances) by enumerating the support ----

// Wallenius' probability of the colour counts x from the urn m with odds w: the product of binomials times int (1 - t^(w_i / D))^x_i dt, D = sum w_i (m_i - x_i), by the same tanh-sinh quadrature as the two-colour case
fn mwall_term(x: []const f64, m: []const f64, w: []const f64) -> f64 {
    let c = x.len
    var d = 0.0f64
    var i = 0usize
    while i < c {
        d += w[i] * (m[i] - x[i])
        i += 1usize
    }
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
        var lu = 0.0f64
        if a >= 0.0f64 {
            let e = math.exp[f64](0.0f64 - 2.0f64 * a)
            lu = 0.0f64 - dist.log1p(e)
        } else {
            let e = math.exp[f64](2.0f64 * a)
            lu = 2.0f64 * a - dist.log1p(e)
        }
        let e2 = math.exp[f64](a)
        let cha = (e2 + 1.0f64 / e2) / 2.0f64
        let wt = pi / 4.0f64 * ch / (cha * cha)
        var v = d * math.exp[f64]((d - 1.0f64) * lu)
        i = 0usize
        while i < c {
            if x[i] > 0.0f64 { v = v * math.pow[f64](0.0f64 - dist.expm1(w[i] * lu), x[i]) }
            i += 1usize
        }
        if wt > 1.0e-300f64 && v == v { s += wt * v }
        j += 1i64
    }
    var lc = 0.0f64
    i = 0usize
    while i < c {
        lc += lchoose(m[i], x[i])
        i += 1usize
    }
    ret s * h * math.exp[f64](lc)
}

type MvCtx = struct { c: usize, m: []const f64, odds: []const f64, n: f64, kind: usize, cur: []f64, xq: []const f64, s0: f64, s1: []f64, s2: []f64, pq: f64 }

fn mv_walk(g: *MvCtx, pos: usize, rem: f64) {
    if pos == g.c - 1usize {
        if rem > g.m[pos] { ret }
        g.cur[pos] = rem
        var p = 0.0f64
        if g.kind == 0usize {
            var lw = 0.0f64
            var i = 0usize
            while i < g.c {
                lw += lchoose(g.m[i], g.cur[i]) + g.cur[i] * math.log[f64](g.odds[i])
                i += 1usize
            }
            p = math.exp[f64](lw)
        } else {
            p = mwall_term(g.cur, g.m, g.odds)
        }
        g.s0 += p
        var same = g.xq.len == g.c
        var i = 0usize
        while i < g.c {
            g.s1[i] += p * g.cur[i]
            g.s2[i] += p * g.cur[i] * g.cur[i]
            if same && g.xq[i] != g.cur[i] { same = false }
            i += 1usize
        }
        if same { g.pq = p }
        ret
    }
    var v = 0.0f64
    while v <= g.m[pos] && v <= rem {
        g.cur[pos] = v
        mv_walk(g, pos + 1usize, rem - v)
        v += 1.0f64
    }
}

// kind 0 Fisher, 1 Wallenius; what 0 the probability of xq, 1 the mean of colour idx, 2 its variance
fn mv_value(a: *mem.Arena, kind: usize, m: []const f64, odds: []const f64, n: f64, xq: []const f64, what: usize, idx: usize) -> f64 {
    let c = m.len
    let (cur, e1) = mem.alloc[f64](a, c)
    let (s1, e2) = mem.alloc[f64](a, c)
    let (s2, e3) = mem.alloc[f64](a, c)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < c {
        s1[i] = 0.0f64
        s2[i] = 0.0f64
        i += 1usize
    }
    var g = MvCtx{ c: c, m: m, odds: odds, n: n, kind: kind, cur: cur, xq: xq, s0: 0.0f64, s1: s1, s2: s2, pq: 0.0f64 }
    mv_walk(&g, 0usize, n)
    if what == 0usize { ret g.pq / g.s0 }
    let mean = g.s1[idx] / g.s0
    if what == 1usize { ret mean }
    ret g.s2[idx] / g.s0 - mean * mean
}

// ---- Wallenius' multivariate probability by the same tanh-sinh sum, in logs and refined until it settles (large counts) ----

fn mwall_sum(x: []const f64, w: []const f64, d: f64, lc: f64, h: f64) -> f64 {
    let pi = 3.141592653589793f64
    let c = x.len
    var s = 0.0f64
    let jmax = i64(5.0f64 / h)
    var j = 0i64 - jmax
    while j <= jmax {
        let t = f64(j) * h
        let ex = math.exp[f64](t)
        let sh = (ex - 1.0f64 / ex) / 2.0f64
        let ch = (ex + 1.0f64 / ex) / 2.0f64
        let a = pi / 2.0f64 * sh
        var omu = 0.0f64
        var lu = 0.0f64
        if a >= 0.0f64 {
            let e = math.exp[f64](0.0f64 - 2.0f64 * a)
            omu = e / (1.0f64 + e)
            lu = 0.0f64 - dist.log1p(e)
        } else {
            let e = math.exp[f64](2.0f64 * a)
            omu = 1.0f64 / (1.0f64 + e)
            lu = 2.0f64 * a - dist.log1p(e)
        }
        let e2 = math.exp[f64](a)
        let cha = (e2 + 1.0f64 / e2) / 2.0f64
        let wt = pi / 4.0f64 * ch / (cha * cha)
        if wt > 1.0e-300f64 && omu > 0.0f64 {
            var lv = lc + math.log[f64](d) + (d - 1.0f64) * lu
            var i = 0usize
            while i < c {
                if x[i] > 0.0f64 {
                    if w[i] == 1.0f64 { lv += x[i] * math.log[f64](omu) } else { lv += x[i] * math.log[f64](0.0f64 - dist.expm1(w[i] * lu)) }
                }
                i += 1usize
            }
            s += wt * math.exp[f64](lv)
        }
        j += 1i64
    }
    ret s * h
}

fn mwall_prob(x: []const f64, m: []const f64, w: []const f64) -> f64 {
    let c = x.len
    var d = 0.0f64
    var lc = 0.0f64
    var i = 0usize
    while i < c {
        d += w[i] * (m[i] - x[i])
        lc += lchoose(m[i], x[i])
        i += 1usize
    }
    var h = 1.0f64 / 32.0f64
    var prev = mwall_sum(x, w, d, lc, h)
    var lvl = 0usize
    while lvl < 4usize {
        h = h / 2.0f64
        let cur = mwall_sum(x, w, d, lc, h)
        let dd = math.abs[f64](cur - prev)
        prev = cur
        if dd <= 1.0e-14f64 * cur || cur == 0.0f64 { break }
        lvl += 1usize
    }
    ret prev
}
