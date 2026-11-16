// R osqp solve_osqp: the convex quadratic program minimise 1/2 x'Px + q'x subject to l <= Ax <= u by the OSQP ADMM iteration (rho 0.1, sigma 1e-6, alpha 1.6, fixed rho) run until the primal and dual residuals are below 1e-11; dense matrices, row-major. With P positive definite the solution is unique and equals osqp's to its tolerance.
//
// Not here: sparse matrices, adaptive rho, polishing, infeasibility certificates, warm starts, code generation.

use e.algo.stat.gparot as gp
use e.math
use e.mem

// x receives the primal solution; returns the objective, NaN when the iteration limit is hit
fn solve(a: *mem.Arena, p: []const f64, q: []const f64, am: []const f64, l: []const f64, u: []const f64, n: usize, m: usize, x: []f64) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let rho = 0.1f64
    let sigma = 1.0e-6f64
    let alpha = 1.6f64
    let (kk, e1) = mem.alloc[f64](a, n * n)
    let (z, e2) = mem.alloc[f64](a, m)
    let (y, e3) = mem.alloc[f64](a, m)
    let (rhs, e4) = mem.alloc[f64](a, n)
    let (zt, e5) = mem.alloc[f64](a, m)
    let (xt, e6) = mem.alloc[f64](a, n)
    let (zn, e7) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret nan }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            var s = p[i * n + j]
            if i == j { s += sigma }
            var r = 0usize
            while r < m {
                s += rho * am[r * n + i] * am[r * n + j]
                r += 1usize
            }
            kk[i * n + j] = s
            j += 1usize
        }
        x[i] = 0.0f64
        i += 1usize
    }
    let (ki, ge) = gp.invert(a, kk, n)
    if ge != ok { ret nan }
    i = 0usize
    while i < m {
        z[i] = 0.0f64
        y[i] = 0.0f64
        i += 1usize
    }
    var it = 0usize
    while it < 2000000usize {
        i = 0usize
        while i < n {
            var s = sigma * x[i] - q[i]
            var r = 0usize
            while r < m {
                s += am[r * n + i] * (rho * z[r] - y[r])
                r += 1usize
            }
            rhs[i] = s
            i += 1usize
        }
        i = 0usize
        while i < n {
            var s = 0.0f64
            var j = 0usize
            while j < n {
                s += ki[i * n + j] * rhs[j]
                j += 1usize
            }
            xt[i] = s
            i += 1usize
        }
        var r = 0usize
        while r < m {
            var s = 0.0f64
            var j = 0usize
            while j < n {
                s += am[r * n + j] * xt[j]
                j += 1usize
            }
            zt[r] = s
            r += 1usize
        }
        var dx = 0.0f64
        i = 0usize
        while i < n {
            let nx = alpha * xt[i] + (1.0f64 - alpha) * x[i]
            if math.abs[f64](nx - x[i]) > dx { dx = math.abs[f64](nx - x[i]) }
            x[i] = nx
            i += 1usize
        }
        var dz = 0.0f64
        r = 0usize
        while r < m {
            let rel = alpha * zt[r] + (1.0f64 - alpha) * z[r]
            var v = rel + y[r] / rho
            if v < l[r] { v = l[r] }
            if v > u[r] { v = u[r] }
            zn[r] = v
            y[r] = y[r] + rho * (rel - v)
            if math.abs[f64](v - z[r]) > dz { dz = math.abs[f64](v - z[r]) }
            z[r] = v
            r += 1usize
        }
        if dx < 1.0e-12f64 && dz < 1.0e-12f64 {
            // the OSQP residuals: primal |Ax - z|, dual |Px + q + A'y|
            var rp = 0.0f64
            r = 0usize
            while r < m {
                var s = 0.0f64
                var j = 0usize
                while j < n {
                    s += am[r * n + j] * x[j]
                    j += 1usize
                }
                if math.abs[f64](s - z[r]) > rp { rp = math.abs[f64](s - z[r]) }
                r += 1usize
            }
            var rd = 0.0f64
            i = 0usize
            while i < n {
                var s = q[i]
                var j = 0usize
                while j < n {
                    s += p[i * n + j] * x[j]
                    j += 1usize
                }
                r = 0usize
                while r < m {
                    s += am[r * n + i] * y[r]
                    r += 1usize
                }
                if math.abs[f64](s) > rd { rd = math.abs[f64](s) }
                i += 1usize
            }
            if rp < 1.0e-11f64 && rd < 1.0e-11f64 { break }
        }
        it += 1usize
    }
    var obj = 0.0f64
    i = 0usize
    while i < n {
        obj += q[i] * x[i]
        var j = 0usize
        while j < n {
            obj += 0.5f64 * x[i] * p[i * n + j] * x[j]
            j += 1usize
        }
        i += 1usize
    }
    ret obj
}
