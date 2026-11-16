// R nleqslv and rootSolve::multiroot: the root of a nonlinear system from a starting point, on a fixed set of two- and three-equation systems, by Newton's method with a
// forward-difference Jacobian, a backtracking line search on the residual norm and a Levenberg-Marquardt step when no damped Newton step reduces it. It reaches the root nleqslv and multiroot reach; the package's trust-region global strategies,
// Broyden updates, termination codes and iteration counts are not reproduced.
//
// Not here: user functions, the pwl and double-dogleg strategies, Broyden, jacobian.full, gradient and hessian.

use e.algo.stat.carlmtest as ols
use e.math
use e.mem

// the equations of system `sys` at x (written to out): 0 circle and exponential, 1 three-variable polynomial, 2 trigonometric pair, 3 Rosenbrock gradient zero, 4 logistic-exponential pair
fn system(sys: usize, x: []const f64, out: []f64) {
    if sys == 0usize {
        out[0usize] = x[0usize] * x[0usize] + x[1usize] * x[1usize] - 4.0f64
        out[1usize] = math.exp[f64](x[0usize]) + x[1usize] - 1.0f64
    } else if sys == 1usize {
        out[0usize] = x[0usize] + x[1usize] + x[2usize] - 3.0f64
        out[1usize] = x[0usize] * x[0usize] + x[1usize] * x[1usize] + x[2usize] * x[2usize] - 5.0f64
        out[2usize] = math.exp[f64](x[0usize]) + x[0usize] * x[1usize] - x[2usize] - 1.0f64
    } else if sys == 2usize {
        out[0usize] = math.sin[f64](x[0usize]) + x[1usize] - 1.2f64
        out[1usize] = x[0usize] - math.cos[f64](x[1usize]) + 0.3f64
    } else if sys == 3usize {
        out[0usize] = 0.0f64 - 400.0f64 * x[0usize] * (x[1usize] - x[0usize] * x[0usize]) - 2.0f64 * (1.0f64 - x[0usize])
        out[1usize] = 200.0f64 * (x[1usize] - x[0usize] * x[0usize])
    } else {
        out[0usize] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x[0usize])) + x[1usize] - 1.5f64
        out[1usize] = x[0usize] * x[1usize] - 0.5f64 - math.exp[f64](0.0f64 - x[1usize])
    }
}

fn dim_of(sys: usize) -> usize {
    if sys == 1usize { ret 3usize }
    ret 2usize
}

fn norm2(f: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += f[i] * f[i]
        i += 1usize
    }
    ret math.sqrt[f64](s)
}

// the root of system `sys` from x0, into x; returns the iterations used, or 0 when it did not converge in 200
fn solve(a: *mem.Arena, sys: usize, x0: []const f64, x: []f64) -> usize {
    let n = dim_of(sys)
    let (f, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret 0usize }
    let (f2, e2) = mem.alloc[f64](a, n)
    if e2 != ok { ret 0usize }
    let (jac, e3) = mem.alloc[f64](a, n * n)
    if e3 != ok { ret 0usize }
    let (ji, e4) = mem.alloc[f64](a, n * n)
    if e4 != ok { ret 0usize }
    let (xt, e5) = mem.alloc[f64](a, n)
    if e5 != ok { ret 0usize }
    let (dx, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret 0usize }
    var i = 0usize
    while i < n {
        x[i] = x0[i]
        i += 1usize
    }
    var it = 0usize
    while it < 200usize {
        system(sys, x, f)
        var m = 0.0f64
        i = 0usize
        while i < n {
            if math.abs[f64](f[i]) > m { m = math.abs[f64](f[i]) }
            i += 1usize
        }
        if m <= 1.0e-10f64 { ret it + 1usize }
        var j = 0usize
        while j < n {
            var h = 1.0e-7f64 * math.abs[f64](x[j])
            if h < 1.0e-7f64 { h = 1.0e-7f64 }
            i = 0usize
            while i < n {
                xt[i] = x[i]
                i += 1usize
            }
            xt[j] = x[j] + h
            system(sys, xt, f2)
            i = 0usize
            while i < n {
                jac[i * n + j] = (f2[i] - f[i]) / h
                i += 1usize
            }
            j += 1usize
        }
        if ols.inverse(a, jac, n, ji) != ok { ret 0usize }
        i = 0usize
        while i < n {
            var s = 0.0f64
            j = 0usize
            while j < n {
                s += ji[i * n + j] * f[j]
                j += 1usize
            }
            dx[i] = 0.0f64 - s
            i += 1usize
        }
        let f0 = norm2(f, n)
        var lam = 1.0f64
        var tries = 0usize
        while tries < 40usize {
            i = 0usize
            while i < n {
                xt[i] = x[i] + lam * dx[i]
                i += 1usize
            }
            system(sys, xt, f2)
            if norm2(f2, n) < f0 || lam < 1.0e-10f64 { break }
            lam = lam / 2.0f64
            tries += 1usize
        }
        // when no damped Newton step reduces the residual, a Levenberg-Marquardt step (J'J + mu I) dx = -J'f with growing mu
        system(sys, xt, f2)
        if norm2(f2, n) >= f0 {
            var mu = 1.0e-4f64
            var found = false
            var round = 0usize
            while round < 60usize && !found {
                let (jtj, e7) = mem.alloc[f64](a, n * n)
                if e7 != ok { ret 0usize }
                let (jti, e8) = mem.alloc[f64](a, n * n)
                if e8 != ok { ret 0usize }
                var p = 0usize
                while p < n {
                    var q = 0usize
                    while q < n {
                        var s = 0.0f64
                        var r = 0usize
                        while r < n {
                            s += jac[r * n + p] * jac[r * n + q]
                            r += 1usize
                        }
                        if p == q { s += mu }
                        jtj[p * n + q] = s
                        q += 1usize
                    }
                    p += 1usize
                }
                if ols.inverse(a, jtj, n, jti) != ok { ret 0usize }
                p = 0usize
                while p < n {
                    var s = 0.0f64
                    var q = 0usize
                    while q < n {
                        var gq = 0.0f64
                        var r = 0usize
                        while r < n {
                            gq += jac[r * n + q] * f[r]
                            r += 1usize
                        }
                        s += jti[p * n + q] * gq
                        q += 1usize
                    }
                    xt[p] = x[p] - s
                    p += 1usize
                }
                system(sys, xt, f2)
                if norm2(f2, n) < f0 { found = true } else { mu = mu * 4.0f64 }
                round += 1usize
            }
            if !found { ret 0usize }
        }
        i = 0usize
        while i < n {
            x[i] = xt[i]
            i += 1usize
        }
        it += 1usize
    }
    ret 0usize
}
