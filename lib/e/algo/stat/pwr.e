// R pwr for the normal-based tests: pwr.p.test, pwr.2p.test, pwr.2p2n.test, pwr.norm.test and pwr.r.test,
// each as its power function and as the solution for any one unknown (effect size, sample size,
// significance level) with the same `uniroot` that pwr uses (R_zeroin2 with tolerance eps^(1/4), the same
// brackets), plus `es_h` (ES.h).
//
// Not here: the noncentral t, chi-squared and F designs (pwr.t.test, pwr.chisq.test, pwr.anova.test,
// pwr.f2.test), cohen.ES and the named effect sizes.

use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb

const TWO: u8 = 2u8

fn pn(x: f64, lower: bool) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, lower, false) }

fn qn(p: f64, lower: bool) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, lower, false) }

// the power of a z-type test at noncentrality delta = effect * sqrt(m); side 1 less, 2 two-sided, 3 greater
fn power_delta(delta: f64, sig: f64, side: u8) -> f64 {
    if side == 2u8 { ret pn(qn(sig / 2.0f64, false) - delta, false) + pn(qn(sig / 2.0f64, true) - delta, true) }
    if side == 3u8 { ret pn(qn(sig, false) - delta, false) }
    ret pn(qn(sig, true) - delta, true)
}

// R_zeroin2 as uniroot calls it: f(lower) and f(upper) known, tolerance tol, at most maxit steps
fn zeroin[Ctx: type](ctx: *Ctx, f: fn(*Ctx, f64) -> f64, lower: f64, upper: f64, tol: f64, maxit: i64) -> f64 {
    let eps = 2.220446049250313e-16f64
    var a = lower
    var b = upper
    var c = a
    var fa = f(ctx, a)
    var fb = f(ctx, b)
    var fc = fa
    if fa == 0.0f64 { ret a }
    if fb == 0.0f64 { ret b }
    var left = maxit + 1i64
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
        fb = f(ctx, b)
        if (fb > 0.0f64 && fc > 0.0f64) || (fb < 0.0f64 && fc < 0.0f64) {
            c = a
            fc = fa
        }
    }
    ret b
}

fn uniroot_tol() -> f64 { ret math.pow[f64](2.220446049250313e-16f64, 0.25f64) }

// the design: kind 0 pwr.p.test and pwr.norm.test (m = n), 1 pwr.2p.test (m = n / 2), 2 pwr.2p2n.test (m = n1 n2 / (n1 + n2))
type Problem = struct { kind: u8, side: u8, h: f64, n: f64, n2: f64, sig: f64, power: f64, unknown: u8 }

fn m_of(p: *const Problem, n: f64) -> f64 {
    if p.kind == 0u8 { ret n }
    if p.kind == 1u8 { ret n / 2.0f64 }
    ret n * p.n2 / (n + p.n2)
}

// the function whose root is wanted: power(parameters) - power; unknown 0 h, 1 n, 2 sig, 3 n2
fn residual(p: *const Problem, x: f64) -> f64 {
    var h = p.h
    var n = p.n
    var sig = p.sig
    var n2 = p.n2
    if p.unknown == 0u8 { h = x }
    if p.unknown == 1u8 { n = x }
    if p.unknown == 2u8 { sig = x }
    var q = *p
    if p.unknown == 3u8 { q.n2 = x }
    ret power_delta(h * math.sqrt[f64](m_of(&q, n)), sig, p.side) - p.power
}

fn power_of(p: *const Problem) -> f64 {
    var h = p.h
    if p.side == 2u8 && h < 0.0f64 { h = 0.0f64 - h }
    ret power_delta(h * math.sqrt[f64](m_of(p, p.n)), p.sig, p.side)
}

// solve for the unknown named in the problem
fn solve(p0: *const Problem) -> f64 {
    var p = *p0
    if p.side == 2u8 && p.h < 0.0f64 { p.h = 0.0f64 - p.h }
    var lo = 0.0f64
    var hi = 0.0f64
    if p.unknown == 0u8 {
        if p.side == 2u8 {
            lo = 1.0e-10f64
            hi = 10.0f64
        } else if p.side == 1u8 {
            lo = 0.0f64 - 10.0f64
            hi = 5.0f64
        } else {
            lo = 0.0f64 - 5.0f64
            hi = 10.0f64
        }
    } else if p.unknown == 2u8 {
        lo = 1.0e-10f64
        hi = 1.0f64 - 1.0e-10f64
    } else {
        lo = 2.0f64 + 1.0e-10f64
        hi = 1.0e9f64
    }
    ret zeroin[Problem](&p, residual_cb, lo, hi, uniroot_tol(), 1000i64)
}

fn residual_cb(p: *Problem, x: f64) -> f64 { ret residual(p, x) }

// ES.h
fn es_h(p1: f64, p2: f64) -> f64 { ret 2.0f64 * math.asin[f64](math.sqrt[f64](p1)) - 2.0f64 * math.asin[f64](math.sqrt[f64](p2)) }

// pwr.r.test power at n observations, correlation r, significance sig, side 1 less, 2 two-sided, 3 greater
fn power_r(n: f64, r0: f64, sig: f64, side: u8) -> f64 {
    var r = r0
    if side == 2u8 && r < 0.0f64 { r = 0.0f64 - r }
    if side == 1u8 { r = 0.0f64 - r }
    var sg = sig
    if side == 2u8 { sg = sig / 2.0f64 }
    let ttt = nb.qt(sg, n - 2.0f64, false, false)
    let rc = math.sqrt[f64](ttt * ttt / (ttt * ttt + n - 2.0f64))
    let zr = atanh(r) + r / (2.0f64 * (n - 1.0f64))
    let zrc = atanh(rc)
    var pw = pn((zr - zrc) * math.sqrt[f64](n - 3.0f64), true)
    if side == 2u8 { pw += pn((0.0f64 - zr - zrc) * math.sqrt[f64](n - 3.0f64), true) }
    ret pw
}

fn atanh(x: f64) -> f64 { ret 0.5f64 * math.log[f64]((1.0f64 + x) / (1.0f64 - x)) }
