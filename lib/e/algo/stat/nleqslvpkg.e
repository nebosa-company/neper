// R nleqslv and rootSolve::multiroot: the root of a nonlinear system from a starting point, on a fixed set of two- and three-equation systems, by Newton's method with a
// forward-difference Jacobian, a backtracking line search on the residual norm and a Levenberg-Marquardt step when no damped Newton step reduces it. It reaches the root nleqslv and multiroot reach; the package's trust-region global strategies,
// Broyden updates, termination codes and iteration counts are not reproduced.
//
// Also rootSolve::gradient and hessian (forward and centred, perturbation max(|x| 1e-8, 1e-8)) on two polynomial test functions. Not here: user functions, the pwl and double-dogleg strategies, Broyden, jacobian.full.

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

// rootSolve::gradient and hessian on polynomial test functions (so the finite differences are bit-reproducible): function 0 is the scalar x1^3 x2 + 2 x2^2 - 3 x1 x2,
// function 1 the pair (x1^2 x2 - x3, x1 + x2 x3^2) of three variables

fn poly_dim(fid: usize) -> usize {
    if fid == 1usize { ret 3usize }
    ret 2usize
}

fn poly_out(fid: usize) -> usize {
    if fid == 1usize { ret 2usize }
    ret 1usize
}

fn poly_f(fid: usize, x: []const f64, out: []f64) {
    if fid == 0usize {
        out[0usize] = x[0usize] * x[0usize] * x[0usize] * x[1usize] + 2.0f64 * x[1usize] * x[1usize] - x[0usize] * x[1usize] * 3.0f64
    } else {
        out[0usize] = x[0usize] * x[0usize] * x[1usize] - x[2usize]
        out[1usize] = x[0usize] + x[1usize] * x[2usize] * x[2usize]
    }
}

fn perturb(v: f64) -> f64 {
    var d = math.abs[f64](v) * 1.0e-8f64
    if d < 1.0e-8f64 { d = 1.0e-8f64 }
    ret d
}

// gradient(f, x, centered): the Nf by Nx matrix of finite differences into jac (row-major); xw is scratch of Nx values, f0 and f1 of Nf
fn fd_gradient(fid: usize, x: []const f64, centered: bool, jac: []f64, xw: []f64, f0: []f64, f1: []f64) {
    let nx = poly_dim(fid)
    let nf = poly_out(fid)
    var fb: [2]f64 = zero
    var i = 0usize
    while i < nx {
        xw[i] = x[i]
        i += 1usize
    }
    poly_f(fid, xw, f0)
    var j = 0usize
    while j < nx {
        let d = perturb(x[j])
        xw[j] = xw[j] + d
        poly_f(fid, xw, f1)
        if centered {
            xw[j] = x[j] - d
            poly_f(fid, xw, fb[0usize..2usize])
        }
        var r = 0usize
        while r < nf {
            var del = (f1[r] - f0[r]) / d
            if centered { del = (del - (fb[r] - f0[r]) / d) / 2.0f64 }
            jac[r * nx + j] = del
            r += 1usize
        }
        xw[j] = x[j]
        j += 1usize
    }
}

// hessian(f, x, centered) of the scalar function 0: reference gradient forward, perturbed gradients as asked; into hess (2 by 2 row-major)
fn fd_hessian(x: []const f64, centered: bool, hess: []f64) {
    var xw: [2]f64 = zero
    var f0: [1]f64 = zero
    var f1: [1]f64 = zero
    var ref: [2]f64 = zero
    var g: [2]f64 = zero
    fd_gradient(0usize, x, false, ref[0usize..2usize], xw[0usize..2usize], f0[0usize..1usize], f1[0usize..1usize])
    var xp: [2]f64 = zero
    var j = 0usize
    while j < 2usize {
        let d = perturb(x[j])
        xp[0usize] = x[0usize]
        xp[1usize] = x[1usize]
        xp[j] = xp[j] + d
        fd_gradient(0usize, xp[0usize..2usize], centered, g[0usize..2usize], xw[0usize..2usize], f0[0usize..1usize], f1[0usize..1usize])
        var r = 0usize
        var col: [2]f64 = zero
        while r < 2usize {
            col[r] = (g[r] - ref[r]) / d
            r += 1usize
        }
        if centered {
            xp[0usize] = x[0usize]
            xp[1usize] = x[1usize]
            xp[j] = x[j] - d
            fd_gradient(0usize, xp[0usize..2usize], centered, g[0usize..2usize], xw[0usize..2usize], f0[0usize..1usize], f1[0usize..1usize])
            r = 0usize
            while r < 2usize {
                col[r] = (col[r] - (g[r] - ref[r]) / d) / 2.0f64
                r += 1usize
            }
        }
        r = 0usize
        while r < 2usize {
            hess[r * 2usize + j] = col[r]
            r += 1usize
        }
        j += 1usize
    }
}
