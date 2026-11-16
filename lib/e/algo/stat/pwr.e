// R pwr for the normal-based tests: pwr.p.test, pwr.2p.test, pwr.2p2n.test, pwr.norm.test and pwr.r.test,
// each as its power function and as the solution for any one unknown (effect size, sample size,
// significance level) with the same `uniroot` that pwr uses (R_zeroin2 with tolerance eps^(1/4), the same
// brackets), plus `es_h` (ES.h).
//
// And the non-central designs (pwr.t.test, pwr.t2n.test, pwr.chisq.test, pwr.anova.test, pwr.f2.test). Not here:
// the named effect sizes of cohen.ES.

use e.math
use e.mem
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.math.nmath as nm
use e.math.nchisq as nc

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

// ---- the non-central designs: pwr.t.test (kind 0 one sample or paired, 1 two sample), pwr.t2n.test (2), pwr.chisq.test (3),
// pwr.anova.test (4) and pwr.f2.test (5). es is d, w, f or f2; n is n, n1, N or the group size; n2 is n2, the degrees of freedom df,
// k or u (kind 5: n2 is v and k is u). unknown: 0 es, 1 n, 2 sig, 3 n2, 4 k.
type NcProblem = struct { kind: u8, side: u8, es: f64, n: f64, n2: f64, k: f64, sig: f64, power: f64, unknown: u8 }

fn t_power(nu: f64, ncp: f64, sig: f64, side: u8) -> f64 {
    if side == 1u8 { ret nc.pnt(nb.qt(sig, nu, true, false), nu, ncp, true, false) }
    if side == 2u8 {
        let qu = nb.qt(sig / 2.0f64, nu, false, false)
        ret nc.pnt(qu, nu, ncp, false, false) + nc.pnt(0.0f64 - qu, nu, ncp, true, false)
    }
    ret nc.pnt(nb.qt(sig, nu, false, false), nu, ncp, false, false)
}

fn nc_power_at(p: *const NcProblem, es: f64, n: f64, n2: f64, k: f64, sig: f64) -> f64 {
    if p.kind == 0u8 { ret t_power(n - 1.0f64, math.sqrt[f64](n) * es, sig, p.side) }
    if p.kind == 1u8 { ret t_power((n - 1.0f64) * 2.0f64, math.sqrt[f64](n / 2.0f64) * es, sig, p.side) }
    if p.kind == 2u8 { ret t_power(n + n2 - 2.0f64, es * (1.0f64 / math.sqrt[f64](1.0f64 / n + 1.0f64 / n2)), sig, p.side) }
    if p.kind == 3u8 {
        let kc = nm.qchisq(sig, n2, false, false)
        ret nc.pnchisq(kc, n2, n * es * es, false, false)
    }
    if p.kind == 4u8 {
        let lambda = k * n * es * es
        ret nc.pnf(nb.qf(sig, k - 1.0f64, (n - 1.0f64) * k, false, false), k - 1.0f64, (n - 1.0f64) * k, lambda, false, false)
    }
    let lambda = es * (k + n + 1.0f64)
    ret nc.pnf(nb.qf(sig, k, n, false, false), k, n, lambda, false, false)
}

fn nc_power(p: *const NcProblem) -> f64 {
    var es = p.es
    if p.kind <= 2u8 && p.side == 2u8 && es < 0.0f64 { es = 0.0f64 - es }
    ret nc_power_at(p, es, p.n, p.n2, p.k, p.sig)
}

fn nc_residual(p: *NcProblem, x: f64) -> f64 {
    var es = p.es
    var n = p.n
    var n2 = p.n2
    var k = p.k
    var sig = p.sig
    if p.unknown == 0u8 { es = x }
    if p.unknown == 1u8 { n = x }
    if p.unknown == 2u8 { sig = x }
    if p.unknown == 3u8 { n2 = x }
    if p.unknown == 4u8 { k = x }
    ret nc_power_at(p, es, n, n2, k, sig) - p.power
}

// uniroot over the brackets pwr uses
fn nc_solve(p0: *const NcProblem) -> f64 {
    var p = *p0
    if p.kind <= 2u8 && p.side == 2u8 && p.es < 0.0f64 { p.es = 0.0f64 - p.es }
    var lo = 0.0f64
    var hi = 0.0f64
    if p.unknown == 2u8 {
        lo = 1.0e-10f64
        hi = 1.0f64 - 1.0e-10f64
    } else if p.kind <= 2u8 {
        if p.unknown == 0u8 {
            if p.side == 2u8 {
                lo = 1.0e-7f64
                hi = 10.0f64
            } else if p.side == 1u8 {
                lo = 0.0f64 - 10.0f64
                hi = 5.0f64
            } else {
                lo = 0.0f64 - 5.0f64
                hi = 10.0f64
            }
        } else {
            lo = 2.0f64 + 1.0e-10f64
            hi = 1.0e9f64
        }
    } else if p.kind == 3u8 {
        if p.unknown == 0u8 {
            lo = 1.0e-10f64
            hi = 1.0e9f64
        } else {
            lo = 1.0f64 + 1.0e-10f64
            hi = 1.0e9f64
        }
    } else if p.kind == 4u8 {
        if p.unknown == 4u8 {
            lo = 2.0f64 + 1.0e-10f64
            hi = 100.0f64
        } else if p.unknown == 1u8 {
            lo = 2.0f64 + 1.0e-10f64
            hi = 1.0e9f64
        } else {
            lo = 1.0e-7f64
            hi = 1.0e7f64
        }
    } else {
        if p.unknown == 4u8 {
            lo = 1.0f64 + 1.0e-10f64
            hi = 100.0f64
        } else if p.unknown == 1u8 {
            lo = 1.0f64 + 1.0e-10f64
            hi = 1.0e9f64
        } else {
            lo = 1.0e-7f64
            hi = 1.0e7f64
        }
    }
    ret zeroin[NcProblem](&p, nc_residual, lo, hi, uniroot_tol(), 1000i64)
}

// pwr.r.test solved for one unknown (0 r, 1 n, 2 sig) from the power
type RProblem = struct { side: u8, r: f64, n: f64, sig: f64, power: f64, unknown: u8 }

fn r_residual(p: *RProblem, x: f64) -> f64 {
    var r = p.r
    var n = p.n
    var sig = p.sig
    if p.unknown == 0u8 { r = x }
    if p.unknown == 1u8 { n = x }
    if p.unknown == 2u8 { sig = x }
    ret power_r(n, r, sig, p.side) - p.power
}

fn r_solve(p0: *const RProblem) -> f64 {
    var p = *p0
    if p.side == 2u8 && p.r < 0.0f64 { p.r = 0.0f64 - p.r }
    var lo = 4.0f64 + 1.0e-10f64
    var hi = 1.0e9f64
    if p.unknown == 0u8 {
        hi = 1.0f64 - 1.0e-10f64
        if p.side == 2u8 { lo = 1.0e-10f64 } else { lo = 0.0f64 - 1.0f64 + 1.0e-10f64 }
    }
    if p.unknown == 2u8 {
        lo = 1.0e-10f64
        hi = 1.0f64 - 1.0e-10f64
    }
    ret zeroin[RProblem](&p, r_residual, lo, hi, uniroot_tol(), 1000i64)
}

// cohen.ES: test 0 p, 1 t, 2 r, 3 anov, 4 chisq, 5 f2; size 0 small, 1 medium, 2 large
fn cohen_es(test: u8, size: u8) -> f64 {
    if test == 0u8 || test == 1u8 {
        if size == 0u8 { ret 0.2f64 }
        if size == 1u8 { ret 0.5f64 }
        ret 0.8f64
    }
    if test == 2u8 || test == 4u8 {
        if size == 0u8 { ret 0.1f64 }
        if size == 1u8 { ret 0.3f64 }
        ret 0.5f64
    }
    if test == 3u8 {
        if size == 0u8 { ret 0.1f64 }
        if size == 1u8 { ret 0.25f64 }
        ret 0.4f64
    }
    if size == 0u8 { ret 0.02f64 }
    if size == 1u8 { ret 0.15f64 }
    ret 0.35f64
}

// ES.w1(P0, P1) and ES.w2(P) on a nr by nc row-major table
fn es_w1(p0: []const f64, p1: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < p0.len {
        s += (p1[i] - p0[i]) * (p1[i] - p0[i]) / p0[i]
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

fn es_w2(a: *mem.Arena, p: []const f64, nr: usize, ncl: usize) -> f64 {
    let (rs, e1) = mem.alloc[f64](a, nr)
    let (cs, e2) = mem.alloc[f64](a, ncl)
    if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < nr {
        rs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < ncl {
        cs[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < nr {
        var j = 0usize
        while j < ncl {
            rs[i] += p[i * ncl + j]
            cs[j] += p[i * ncl + j]
            j += 1usize
        }
        i += 1usize
    }
    var s = 0.0f64
    i = 0usize
    while i < nr {
        var j = 0usize
        while j < ncl {
            let p0 = rs[i] * cs[j]
            s += (p[i * ncl + j] - p0) * (p[i * ncl + j] - p0) / p0
            j += 1usize
        }
        i += 1usize
    }
    ret math.sqrt[f64](s)
}
