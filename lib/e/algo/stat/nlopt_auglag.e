// NLopt's augmented Lagrangian (algs/auglag, Birgin and Martinez) for nloptr's NLOPT_LD_AUGLAG and NLOPT_LD_AUGLAG_EQ,
// ported statement for statement. The sub-problem is solved by one of the ported gradient methods:
// local algorithm ids 0 MMA, 1 CCSAQ, 2 LBFGS, 3 VAR1, 4 VAR2, 5 TNEWTON, 6 TNEWTON_RESTART, 7 TNEWTON_PRECOND,
// 8 TNEWTON_PRECOND_RESTART, 9 SLSQP. The constraint blocks follow nloptr: one inequality block (c <= 0, tolerance ctol) and one
// equality block (h = 0, tolerance htol), each a vector function with an optional row-major Jacobian.
//
// Not here: derivative-free local solvers (COBYLA, BOBYQA, Nelder-Mead), maxtime.

use e.math
use e.mem
use e.algo.stat.nlopt as nl
use e.algo.stat.nlopt_luksan as lk
use e.algo.stat.nlopt_slsqp as sl

// settings of the local optimiser as nloptr passes them (its own defaults, not the outer ones)
type Local = struct { alg: i64, ftol_rel: f64, ftol_abs: f64, xtol_rel: f64, maxeval: i64, mf: usize }

type AlD[C: type] = struct {
    f: fn(*C, []const f64, []f64) -> f64,
    ineq: fn(*C, []const f64, []f64, []f64),
    eqc: fn(*C, []const f64, []f64, []f64),
    ctx: *C, n: usize, mm: usize, pp: usize, mi: usize, me: usize,
    lambda: []f64, mu: []f64, rho: f64, restmp: []f64, gradtmp: []f64, stop: *nl.Stop
}

fn al_obj[C: type](d: *AlD[C], x: []const f64, grad: []f64) -> f64 {
    let n = d.n
    var gradtmp = d.gradtmp[0usize..0usize]
    if grad.len > 0usize { gradtmp = d.gradtmp }
    var l = d.f(d.ctx, x, grad)
    d.stop.nevals += 1i64
    if d.pp > 0usize {
        d.eqc(d.ctx, x, d.restmp, gradtmp)
        var k = 0usize
        while k < d.pp {
            let h = d.restmp[k] + d.lambda[k] / d.rho
            l += 0.5f64 * d.rho * h * h
            if grad.len > 0usize {
                var j = 0usize
                while j < n {
                    grad[j] += (d.rho * h) * gradtmp[k * n + j]
                    j += 1usize
                }
            }
            k += 1usize
        }
    }
    if d.mm > 0usize {
        d.ineq(d.ctx, x, d.restmp, gradtmp)
        var k = 0usize
        while k < d.mm {
            let fc = d.restmp[k] + d.mu[k] / d.rho
            if fc > 0.0f64 {
                l += 0.5f64 * d.rho * fc * fc
                if grad.len > 0usize {
                    var j = 0usize
                    while j < n {
                        grad[j] += (d.rho * fc) * gradtmp[k * n + j]
                        j += 1usize
                    }
                }
            }
            k += 1usize
        }
    }
    ret l
}

// the inequality block handed to the sub-solver (AUGLAG_EQ)
fn al_ineq[C: type](d: *AlD[C], x: []const f64, r: []f64, jac: []f64) { d.ineq(d.ctx, x, r, jac) }

fn al_noeq[C: type](d: *AlD[C], x: []const f64, r: []f64, jac: []f64) { }

// one local solve of the sub-problem; xcur is the start and the answer
fn run_local[C: type](ar: *mem.Arena, loc: Local, d: *AlD[C], subm: usize, ctol: []const f64, lb: []const f64, ub: []const f64, xcur: []f64, stop: *nl.Stop) -> (f64, i64) {
    let a = loc.alg
    var v = 0.0f64
    var c = 0i64
    if a == 0i64 || a == 1i64 {
        let (v1, c1) = nl.mma_minimize[AlD[C]](ar, a, al_obj[C], al_ineq[C], d, subm, ctol, lb, ub, xcur, stop, nl.dual_default(), 0i64, 1.0f64, lb[0usize..0usize])
        v = v1
        c = c1
    } else if a == 9i64 {
        let (v1, c1) = sl.slsqp_minimize[AlD[C]](ar, al_obj[C], al_ineq[C], al_noeq[C], d, subm, ctol, 0usize, ctol, lb, ub, xcur, stop)
        v = v1
        c = c1
    } else if a == 2i64 {
        let (v1, c1) = lk.lbfgs[AlD[C]](ar, al_obj[C], d, lb, ub, xcur, stop, loc.mf, 0.0f64)
        v = v1
        c = c1
    } else if a == 3i64 || a == 4i64 {
        let (v1, c1) = lk.varmetric[AlD[C]](ar, al_obj[C], d, lb, ub, xcur, stop, loc.mf, a - 2i64, 0.0f64)
        v = v1
        c = c1
    } else {
        let k = a - 5i64
        let (v1, c1) = lk.tnewton[AlD[C]](ar, al_obj[C], d, lb, ub, xcur, stop, loc.mf, 1i64 + k % 2i64, 1i64 + k / 2i64, 0.0f64)
        v = v1
        c = c1
    }
    ret (v, c)
}

// sub_has_fc: NLOPT_LD_AUGLAG_EQ (inequalities go to the sub-solver). mi and me count the inequality and equality
// results; ctol and htol hold their tolerances. x is the start and the answer; answers (minf, code).
fn auglag[C: type](ar: *mem.Arena, f: fn(*C, []const f64, []f64) -> f64, ineq: fn(*C, []const f64, []f64, []f64), eqc: fn(*C, []const f64, []f64, []f64), ctx: *C, mi: usize, ctol: []const f64, me: usize, htol: []const f64, lb: []const f64, ub: []const f64, x: []f64, stop: *nl.Stop, loc: Local, sub_has_fc: bool) -> (f64, i64) {
    let n = x.len
    let tau = 0.5f64
    let gam = 10.0f64
    let lam_min = 0.0f64 - 1.0e20f64
    let lam_max = 1.0e20f64
    let mu_max = 1.0e20f64
    var mm = mi
    var subm = mi
    if sub_has_fc {
        mm = 0usize
    } else {
        subm = 0usize
    }
    var maxdim = me
    if mm > maxdim { maxdim = mm }
    let (xcur0, e1) = mem.alloc[f64](ar, n + 1usize)
    let xcur = xcur0[0usize..n]
    let (restmp, e2) = mem.alloc[f64](ar, maxdim + 1usize)
    let (gradtmp, e3) = mem.alloc[f64](ar, n * maxdim + 1usize)
    let (lambda, e4) = mem.alloc[f64](ar, me + 1usize)
    let (mu, e5) = mem.alloc[f64](ar, mm + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret (0.0f64, nl.OUT_OF_MEMORY) }
    var i = 0usize
    while i < n {
        xcur[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < n * maxdim + 1usize {
        gradtmp[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < me + 1usize {
        lambda[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < mm + 1usize {
        mu[i] = 0.0f64
        i += 1usize
    }
    var d = AlD[C] { f: f, ineq: ineq, eqc: eqc, ctx: ctx, n: n, mm: mm, pp: me, mi: mi, me: me, lambda: lambda, mu: mu, rho: 1.0f64, restmp: restmp, gradtmp: gradtmp, stop: stop }
    var minf = nl.inf()
    var minf_penalty = nl.inf()
    var minf_feasible = false
    var icm = nl.inf()
    var fcur = 0.0f64
    var penalty = 0.0f64
    var feasible = true
    var code = nl.SUCCESS
    let empty = x[0usize..0usize]
    if d.pp > 0usize || d.mm > 0usize {
        var con2 = 0.0f64
        stop.nevals += 1i64
        fcur = f(ctx, xcur, empty)
        penalty = 0.0f64
        feasible = true
        if d.pp > 0usize {
            eqc(ctx, xcur, restmp, empty)
            var k = 0usize
            while k < d.pp {
                let hi = restmp[k]
                penalty += math.abs[f64](hi)
                feasible = feasible && math.abs[f64](hi) <= htol[k]
                con2 += hi * hi
                k += 1usize
            }
        }
        if d.mm > 0usize {
            ineq(ctx, xcur, restmp, empty)
            var k = 0usize
            while k < d.mm {
                let fci = restmp[k]
                if fci > 0.0f64 { penalty += fci }
                feasible = feasible && fci <= ctol[k]
                if fci > 0.0f64 { con2 += fci * fci }
                k += 1usize
            }
        }
        minf = fcur
        minf_penalty = penalty
        minf_feasible = feasible
        if con2 > 0.0f64 {
            d.rho = nl.fmax(1.0e-6f64, nl.fmin(10.0f64, 2.0f64 * math.abs[f64](minf) / con2))
        } else {
            d.rho = 10.0f64
        }
    } else {
        d.rho = 1.0f64
    }
    while true {
        let prev_icm = icm
        let mk = mem.mark(ar)
        var sub_minf = 1.0f64
        if true {
            var sstop = nl.Stop { n: n, minf_max: 0.0f64 - nl.inf(), ftol_rel: loc.ftol_rel, ftol_abs: loc.ftol_abs, xtol_rel: loc.xtol_rel, xtol_abs: xcur[0usize..0usize], maxeval: loc.maxeval, nevals: 0i64 }
            if d.mm == 0usize && d.pp == 0usize { sstop.minf_max = stop.minf_max }
            let rem = stop.maxeval - stop.nevals
            if sstop.maxeval <= 0i64 || (rem > 0i64 && rem < sstop.maxeval) { sstop.maxeval = rem }
            let (sm, rc) = run_local[C](ar, loc, &d, subm, ctol, lb, ub, xcur, &sstop)
            sub_minf = sm
            code = rc
        }
        mem.reset(ar, mk)
        if code < 0i64 { break }
        stop.nevals += 1i64
        fcur = f(ctx, xcur, empty)
        icm = 0.0f64
        penalty = 0.0f64
        feasible = true
        if d.pp > 0usize {
            eqc(ctx, xcur, restmp, empty)
            var k = 0usize
            while k < d.pp {
                let hi = restmp[k]
                let newlam = lambda[k] + d.rho * hi
                penalty += math.abs[f64](hi)
                feasible = feasible && math.abs[f64](hi) <= htol[k]
                icm = nl.fmax(icm, math.abs[f64](hi))
                lambda[k] = nl.fmin(nl.fmax(lam_min, newlam), lam_max)
                k += 1usize
            }
        }
        if d.mm > 0usize {
            ineq(ctx, xcur, restmp, empty)
            var k = 0usize
            while k < d.mm {
                let fci = restmp[k]
                let newmu = mu[k] + d.rho * fci
                if fci > 0.0f64 { penalty += fci }
                feasible = feasible && fci <= ctol[k]
                icm = nl.fmax(icm, math.abs[f64](nl.fmax(fci, 0.0f64 - mu[k] / d.rho)))
                mu[k] = nl.fmin(nl.fmax(0.0f64, newmu), mu_max)
                k += 1usize
            }
        }
        if icm > tau * prev_icm { d.rho *= gam }
        if (feasible && (!minf_feasible || penalty < minf_penalty || fcur < minf)) || (!minf_feasible && penalty < minf_penalty) {
            code = nl.SUCCESS
            if feasible {
                if fcur < stop.minf_max {
                    code = nl.STOPVAL_REACHED
                } else if nl.stop_ftol(stop, fcur, minf) {
                    code = nl.FTOL_REACHED
                } else if nl.stop_x(stop, xcur, x) {
                    code = nl.XTOL_REACHED
                }
            }
            minf = fcur
            minf_penalty = penalty
            minf_feasible = feasible
            i = 0usize
            while i < n {
                x[i] = xcur[i]
                i += 1usize
            }
            if code != nl.SUCCESS { break }
        }
        if nl.stop_evals(stop) {
            code = nl.MAXEVAL_REACHED
            break
        }
        if icm == 0.0f64 {
            code = nl.FTOL_REACHED
            break
        }
    }
    ret (minf, code)
}
