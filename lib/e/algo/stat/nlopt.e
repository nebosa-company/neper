// NLopt as nloptr ships it (nlopt 2.10.0): the stopping tests of stop.c and the two CCSA methods of mma.c and
// ccsa_quadratic.c, ported statement for statement so the iterates, evaluation counts and return codes match.
//
// A problem is an objective f(ctx, x, grad) -> value (grad has length n when a gradient is wanted, length 0 when not)
// and inequality constraints cons(ctx, x, res, jac) filling m results c(x) <= 0 and, when jac is not empty, the m x n
// row-major Jacobian. ctol holds the per-constraint feasibility tolerance (nloptr's tol_constraints_ineq).
//
// Return codes are nlopt_result: 1 success, 2 stopval, 3 ftol, 4 xtol, 5 maxeval, 6 maxtime, -1 failure,
// -2 invalid args, -3 out of memory, -4 roundoff limited, -5 forced stop.
//
// Not here: maxtime (never reached on these sizes), the preconditioner of CCSAQ, a user-chosen dual algorithm.

use e.math
use e.mem

const SUCCESS: i64 = 1i64
const STOPVAL_REACHED: i64 = 2i64
const FTOL_REACHED: i64 = 3i64
const XTOL_REACHED: i64 = 4i64
const MAXEVAL_REACHED: i64 = 5i64
const FAILURE: i64 = 0i64 - 1i64
const INVALID_ARGS: i64 = 0i64 - 2i64
const OUT_OF_MEMORY: i64 = 0i64 - 3i64
const ROUNDOFF_LIMITED: i64 = 0i64 - 4i64

// xtol_abs of length 0 is the NULL of the C struct
type Stop = struct { n: usize, minf_max: f64, ftol_rel: f64, ftol_abs: f64, xtol_rel: f64, xtol_abs: []const f64, maxeval: i64, nevals: i64 }

fn inf() -> f64 { ret math.inf64() }

fn isinf(x: f64) -> bool { ret math.abs[f64](x) > 1.7976931348623157e308f64 }

fn isnan(x: f64) -> bool { ret x != x }

fn isfinite(x: f64) -> bool { ret x == x && math.abs[f64](x) <= 1.7976931348623157e308f64 }

fn sqr(x: f64) -> f64 { ret x * x }

fn relstop(vold: f64, vnew: f64, reltol: f64, abstol: f64) -> bool {
    if isinf(vold) { ret false }
    let d = math.abs[f64](vnew - vold)
    ret d < abstol || d < reltol * (math.abs[f64](vnew) + math.abs[f64](vold)) * 0.5f64 || (reltol > 0.0f64 && vnew == vold)
}

fn stop_ftol(s: *Stop, f: f64, oldf: f64) -> bool { ret relstop(oldf, f, s.ftol_rel, s.ftol_abs) }

fn stop_f(s: *Stop, f: f64, oldf: f64) -> bool { ret f <= s.minf_max || stop_ftol(s, f, oldf) }

fn stop_x(s: *Stop, x: []const f64, oldx: []const f64) -> bool {
    var dn = 0.0f64
    var vn = 0.0f64
    var i = 0usize
    while i < s.n {
        dn += math.abs[f64](x[i] - oldx[i])
        vn += math.abs[f64](x[i])
        i += 1usize
    }
    if dn < s.xtol_rel * vn { ret true }
    if s.xtol_abs.len == 0usize { ret false }
    i = 0usize
    while i < s.n {
        if math.abs[f64](x[i] - oldx[i]) >= s.xtol_abs[i] { ret false }
        i += 1usize
    }
    ret true
}

fn stop_dx(s: *Stop, x: []const f64, dx: []const f64) -> bool {
    var dn = 0.0f64
    var vn = 0.0f64
    var i = 0usize
    while i < s.n {
        dn += math.abs[f64](dx[i])
        vn += math.abs[f64](x[i])
        i += 1usize
    }
    if dn < s.xtol_rel * vn { ret true }
    if s.xtol_abs.len == 0usize { ret false }
    i = 0usize
    while i < s.n {
        if math.abs[f64](dx[i]) >= s.xtol_abs[i] { ret false }
        i += 1usize
    }
    ret true
}

fn stop_evals(s: *Stop) -> bool { ret s.maxeval > 0i64 && s.nevals >= s.maxeval }

// the maxeval / stopval part of the outer-loop test: 0 to go on, else the code
fn stop_code(s: *Stop, feasible: bool, minf: f64) -> i64 {
    if stop_evals(s) { ret MAXEVAL_REACHED }
    if feasible && minf < s.minf_max { ret STOPVAL_REACHED }
    ret 0i64
}

// tolerances of the dual (inner) solve: nlopt's defaults when no local optimiser is given
type DualSpec = struct { ftol_rel: f64, ftol_abs: f64, xtol_rel: f64, maxeval: i64 }

fn dual_default() -> DualSpec { ret DualSpec { ftol_rel: 1.0e-14f64, ftol_abs: 0.0f64, xtol_rel: 0.0f64, maxeval: 100000i64 } }

type Dual = struct {
    count: i64, n: usize, kind: i64,
    x: []f64, lb: []const f64, ub: []const f64, sigma: []f64, dfdx: []f64, dfcdx: []f64,
    fval: f64, rho: f64, fcval: []f64, rhoc: []f64, xcur: []f64, gval: f64, wval: f64, gcval: []f64
}

fn nocons(d: *Dual, x: []const f64, r: []f64, jac: []f64) { }

// MMA's dual objective (kind 0) and CCSA's (kind 1); y.len is the number of constraints
fn dual_func(d: *Dual, y: []const f64, grad: []f64) -> f64 {
    let n = d.n
    let m = y.len
    d.count += 1i64
    var val = d.fval
    d.gval = d.fval
    d.wval = 0.0f64
    var i = 0usize
    while i < m {
        if d.kind == 0i64 {
            d.gcval[i] = 0.0f64
            if !isnan(d.fcval[i]) { d.gcval[i] = d.fcval[i] }
        } else {
            d.gcval[i] = d.fcval[i]
        }
        val += y[i] * d.gcval[i]
        i += 1usize
    }
    var j = 0usize
    while j < n {
        if d.sigma[j] == 0.0f64 {
            d.xcur[j] = d.x[j]
        } else if d.kind == 0i64 {
            var u = d.dfdx[j]
            var v = math.abs[f64](d.dfdx[j]) * d.sigma[j] + 0.5f64 * d.rho
            i = 0usize
            while i < m {
                if !isnan(d.fcval[i]) {
                    u += d.dfcdx[i * n + j] * y[i]
                    v += (math.abs[f64](d.dfcdx[i * n + j]) * d.sigma[j] + 0.5f64 * d.rhoc[i]) * y[i]
                }
                i += 1usize
            }
            let sigma2 = sqr(d.sigma[j])
            u *= sigma2
            var dx = (u / v) / (0.0f64 - 1.0f64 - math.sqrt[f64](math.abs[f64](1.0f64 - sqr(u / (v * d.sigma[j])))))
            d.xcur[j] = d.x[j] + dx
            if d.xcur[j] > d.ub[j] {
                d.xcur[j] = d.ub[j]
            } else if d.xcur[j] < d.lb[j] {
                d.xcur[j] = d.lb[j]
            }
            if d.xcur[j] > d.x[j] + 0.9f64 * d.sigma[j] {
                d.xcur[j] = d.x[j] + 0.9f64 * d.sigma[j]
            } else if d.xcur[j] < d.x[j] - 0.9f64 * d.sigma[j] {
                d.xcur[j] = d.x[j] - 0.9f64 * d.sigma[j]
            }
            dx = d.xcur[j] - d.x[j]
            let dx2 = dx * dx
            let denominv = 1.0f64 / (sigma2 - dx2)
            val += (u * dx + v * dx2) * denominv
            let c = sigma2 * dx
            d.gval += (d.dfdx[j] * c + (math.abs[f64](d.dfdx[j]) * d.sigma[j] + 0.5f64 * d.rho) * dx2) * denominv
            d.wval += 0.5f64 * dx2 * denominv
            i = 0usize
            while i < m {
                if !isnan(d.fcval[i]) {
                    d.gcval[i] += (d.dfcdx[i * n + j] * c + (math.abs[f64](d.dfcdx[i * n + j]) * d.sigma[j] + 0.5f64 * d.rhoc[i]) * dx2) * denominv
                }
                i += 1usize
            }
        } else {
            var u = d.rho
            var v = d.dfdx[j]
            i = 0usize
            while i < m {
                u += d.rhoc[i] * y[i]
                v += d.dfcdx[i * n + j] * y[i]
                i += 1usize
            }
            let sigma2 = sqr(d.sigma[j])
            var dx = 0.0f64 - sigma2 * v / u
            if math.abs[f64](dx) > d.sigma[j] { dx = math.copysign[f64](d.sigma[j], dx) }
            d.xcur[j] = d.x[j] + dx
            if d.xcur[j] > d.ub[j] {
                d.xcur[j] = d.ub[j]
            } else if d.xcur[j] < d.lb[j] {
                d.xcur[j] = d.lb[j]
            }
            dx = d.xcur[j] - d.x[j]
            let dx2 = dx * dx
            val += v * dx + 0.5f64 * u * dx2 / sigma2
            let dx2sig = 0.5f64 * dx2 / sigma2
            d.gval += d.dfdx[j] * dx + d.rho * dx2sig
            d.wval += dx2sig
            i = 0usize
            while i < m {
                d.gcval[i] += d.dfcdx[i * n + j] * dx + d.rhoc[i] * dx2sig
                i += 1usize
            }
        }
        j += 1usize
    }
    if grad.len > 0usize {
        i = 0usize
        while i < m {
            grad[i] = 0.0f64 - d.gcval[i]
            i += 1usize
        }
    }
    ret 0.0f64 - val
}

fn fmin(a: f64, b: f64) -> f64 {
    if a < b { ret a }
    ret b
}

fn fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

// kind 0 is MMA (NLOPT_LD_MMA), kind 1 CCSA with quadratic penalty (NLOPT_LD_CCSAQ). sigma_init of length 0 is no
// initial step. x is the start and receives the best point; answers (minf, code).
fn mma_minimize[C: type](ar: *mem.Arena, kind: i64, f: fn(*C, []const f64, []f64) -> f64, cons: fn(*C, []const f64, []f64, []f64), ctx: *C, m: usize, ctol: []const f64, lb: []const f64, ub: []const f64, x: []f64, stop: *Stop, dual: DualSpec, inner_maxeval: i64, rho_init: f64, sigma_init: []const f64) -> (f64, i64) {
    let n = x.len
    let rhomin = 1.0e-5f64
    let (sigma, e1) = mem.alloc[f64](ar, n)
    let (dfdx, e2) = mem.alloc[f64](ar, n)
    let (dfdx_cur, e3) = mem.alloc[f64](ar, n)
    let (xcur, e4) = mem.alloc[f64](ar, n)
    let (xprev, e5) = mem.alloc[f64](ar, n)
    let (xprevprev, e6) = mem.alloc[f64](ar, n)
    let (fcval, e7) = mem.alloc[f64](ar, m + 1usize)
    let (fcval_cur, e8) = mem.alloc[f64](ar, m + 1usize)
    let (rhoc, e9) = mem.alloc[f64](ar, m + 1usize)
    let (gcval, e10) = mem.alloc[f64](ar, m + 1usize)
    let (dual_lb, e11) = mem.alloc[f64](ar, m + 1usize)
    let (dual_ub, e12) = mem.alloc[f64](ar, m + 1usize)
    let (y, e13) = mem.alloc[f64](ar, m + 1usize)
    let (dfcdx, e14) = mem.alloc[f64](ar, m * n + 1usize)
    let (dfcdx_cur, e15) = mem.alloc[f64](ar, m * n + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok || e11 != ok || e12 != ok || e13 != ok || e14 != ok || e15 != ok { ret (0.0f64, OUT_OF_MEMORY) }
    var dd = Dual { count: 0i64, n: n, kind: kind, x: x, lb: lb, ub: ub, sigma: sigma, dfdx: dfdx, dfcdx: dfcdx, fval: 0.0f64, rho: 0.0f64, fcval: fcval, rhoc: rhoc, xcur: xcur, gval: 0.0f64, wval: 0.0f64, gcval: gcval }
    var j = 0usize
    while j < n {
        if sigma_init.len > 0usize && sigma_init[j] > 0.0f64 {
            sigma[j] = sigma_init[j]
        } else if isinf(ub[j]) || isinf(lb[j]) {
            sigma[j] = 1.0f64
        } else {
            sigma[j] = 0.5f64 * (ub[j] - lb[j])
        }
        j += 1usize
    }
    var rho = rho_init
    var i = 0usize
    while i < m {
        rhoc[i] = rho_init
        dual_lb[i] = 0.0f64
        y[i] = 0.0f64
        dual_ub[i] = inf()
        i += 1usize
    }
    var fcur = f(ctx, x, dfdx)
    var minf = fcur
    dd.fval = fcur
    stop.nevals += 1i64
    i = 0usize
    while i < n {
        xcur[i] = x[i]
        i += 1usize
    }
    var feasible = true
    var infeasibility = 0.0f64
    if m > 0usize { cons(ctx, x, fcval, dfcdx) }
    i = 0usize
    while i < m {
        feasible = feasible && (fcval[i] <= 0.0f64 || isnan(fcval[i]))
        if fcval[i] > infeasibility { infeasibility = fcval[i] }
        i += 1usize
    }
    if !feasible {
        i = 0usize
        while i < m {
            dual_ub[i] = 1.0e40f64
            i += 1usize
        }
    }
    var k = 0usize
    while true {
        var inner_nevals = 0i64
        let fprev = fcur
        var code = stop_code(stop, feasible, minf)
        if code != 0i64 { ret (minf, code) }
        k += 1usize
        if k > 1usize {
            i = 0usize
            while i < n {
                xprevprev[i] = xprev[i]
                i += 1usize
            }
        }
        i = 0usize
        while i < n {
            xprev[i] = xcur[i]
            i += 1usize
        }
        while true {
            dd.rho = rho
            dd.count = 0i64
            if m > 0usize {
                let mk = mem.mark(ar)
                var dstop = Stop { n: m, minf_max: 0.0f64 - inf(), ftol_rel: dual.ftol_rel, ftol_abs: dual.ftol_abs, xtol_rel: dual.xtol_rel, xtol_abs: y[0usize..0usize], maxeval: dual.maxeval, nevals: 0i64 }
                let ysl = y[0usize..m]
                let (_md, rc) = mma_minimize[Dual](ar, 0i64, dual_func, nocons, &dd, 0usize, y[0usize..0usize], dual_lb[0usize..m], dual_ub[0usize..m], ysl, &dstop, dual, 0i64, 1.0f64, y[0usize..0usize])
                mem.reset(ar, mk)
                if rc < 0i64 { ret (minf, rc) }
            }
            let ysl2 = y[0usize..m]
            let _d = dual_func(&dd, ysl2, y[0usize..0usize])
            fcur = f(ctx, xcur, dfdx_cur)
            stop.nevals += 1i64
            inner_nevals += 1i64
            var feasible_cur = true
            var infeasibility_cur = 0.0f64
            var new_infeasible_constraint = false
            var inner_done = dd.gval >= fcur
            if m > 0usize { cons(ctx, xcur, fcval_cur, dfcdx_cur) }
            i = 0usize
            while i < m {
                if !isnan(fcval_cur[i]) {
                    feasible_cur = feasible_cur && fcval_cur[i] <= ctol[i]
                    if kind == 0i64 {
                        if !isnan(fcval[i]) {
                            inner_done = inner_done && dd.gcval[i] >= fcval_cur[i]
                        } else if fcval_cur[i] > 0.0f64 {
                            new_infeasible_constraint = true
                        }
                    } else {
                        inner_done = inner_done && dd.gcval[i] >= fcval_cur[i]
                    }
                    if fcval_cur[i] > infeasibility_cur { infeasibility_cur = fcval_cur[i] }
                }
                i += 1usize
            }
            inner_done = inner_done || (inner_maxeval > 0i64 && inner_nevals == inner_maxeval)
            if (fcur < minf && (inner_done || feasible_cur || !feasible)) || (!feasible && infeasibility_cur < infeasibility) {
                minf = fcur
                dd.fval = fcur
                infeasibility = infeasibility_cur
                i = 0usize
                while i < m {
                    fcval[i] = fcval_cur[i]
                    i += 1usize
                }
                i = 0usize
                while i < n {
                    x[i] = xcur[i]
                    dfdx[i] = dfdx_cur[i]
                    i += 1usize
                }
                i = 0usize
                while i < n * m {
                    dfcdx[i] = dfcdx_cur[i]
                    i += 1usize
                }
                if infeasibility_cur == 0.0f64 {
                    if !feasible {
                        i = 0usize
                        while i < m {
                            dual_ub[i] = inf()
                            i += 1usize
                        }
                    }
                    feasible = true
                } else if kind == 0i64 && new_infeasible_constraint {
                    feasible = false
                }
            }
            code = stop_code(stop, feasible, minf)
            if code != 0i64 { ret (minf, code) }
            if inner_done { break }
            if fcur > dd.gval { rho = fmin(10.0f64 * rho, 1.1f64 * (rho + (fcur - dd.gval) / dd.wval)) }
            i = 0usize
            while i < m {
                if (kind == 1i64 || !isnan(fcval_cur[i])) && fcval_cur[i] > dd.gcval[i] {
                    rhoc[i] = fmin(10.0f64 * rhoc[i], 1.1f64 * (rhoc[i] + (fcval_cur[i] - dd.gcval[i]) / dd.wval))
                }
                i += 1usize
            }
        }
        var rcode = 0i64
        if stop_ftol(stop, fcur, fprev) { rcode = FTOL_REACHED }
        if stop_x(stop, xcur, xprev) { rcode = XTOL_REACHED }
        if rcode != 0i64 { ret (minf, rcode) }
        rho = fmax(0.1f64 * rho, rhomin)
        i = 0usize
        while i < m {
            rhoc[i] = fmax(0.1f64 * rhoc[i], rhomin)
            i += 1usize
        }
        if k > 1usize {
            j = 0usize
            while j < n {
                let dx2 = (xcur[j] - xprev[j]) * (xprev[j] - xprevprev[j])
                var gam = 1.0f64
                if dx2 < 0.0f64 {
                    gam = 0.7f64
                } else if dx2 > 0.0f64 {
                    gam = 1.2f64
                }
                sigma[j] *= gam
                if !isinf(ub[j]) && !isinf(lb[j]) {
                    sigma[j] = fmin(sigma[j], 10.0f64 * (ub[j] - lb[j]))
                    if kind == 0i64 {
                        sigma[j] = fmax(sigma[j], 0.01f64 * (ub[j] - lb[j]))
                    } else {
                        sigma[j] = fmax(sigma[j], 1.0e-8f64 * (ub[j] - lb[j]))
                    }
                }
                j += 1usize
            }
        }
    }
    ret (minf, FAILURE)
}

// nloptr's check.derivatives: the analytic m x n Jacobian (row-major) against the forward finite difference of
// finite.diff (step sqrt(eps) * max(|x|, 1), the step recomputed as the representable difference). fd and rel receive
// the m x n difference quotients and relative errors (the analytic value where the quotient is 0); answers how many
// relative errors exceed tol. func fills m values, jac fills m * n.
fn check_derivatives[C: type](ar: *mem.Arena, func: fn(*C, []const f64, []f64), jac: fn(*C, []const f64, []f64), ctx: *C, x: []const f64, m: usize, tol: f64, ana: []f64, fd: []f64, rel: []f64) -> usize {
    let n = x.len
    let (xp, e1) = mem.alloc[f64](ar, n + 1usize)
    let (fx, e2) = mem.alloc[f64](ar, m + 1usize)
    let (fp, e3) = mem.alloc[f64](ar, m + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0usize }
    jac(ctx, x, ana)
    func(ctx, x, fx)
    let step = 1.4901161193847656e-08f64
    var j = 0usize
    while j < n {
        var i = 0usize
        while i < n {
            xp[i] = x[i]
            i += 1usize
        }
        var sv = fmax(math.abs[f64](x[j]), 1.0f64) * step
        xp[j] = x[j] + sv
        sv = xp[j] - x[j]
        func(ctx, xp[0usize..n], fp)
        i = 0usize
        while i < m {
            fd[i * n + j] = (fp[i] - fx[i]) / sv
            i += 1usize
        }
        j += 1usize
    }
    var flagged = 0usize
    var k = 0usize
    while k < m * n {
        if fd[k] == 0.0f64 {
            rel[k] = ana[k]
        } else {
            rel[k] = math.abs[f64]((ana[k] - fd[k]) / fd[k])
        }
        if rel[k] > tol { flagged += 1usize }
        k += 1usize
    }
    ret flagged
}
