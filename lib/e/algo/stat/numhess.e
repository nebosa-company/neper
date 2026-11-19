// the standard errors a fitting routine reports from its Hessian: the square roots of the diagonal of the inverse of the Hessian of an objective (minus a log-likelihood) at the estimates, by second central differences.

use e.math
use e.mem
use e.algo.stat.quantreg as qrb

// the inverse of the Hessian of f at est (k parameters, second central differences with step 1e-4, at most 8 parameters): what unmarked reports from optim's Hessian of minus the log-likelihood;
// false when the Hessian is singular
fn hessian_inv[C: type](a: *mem.Arena, ctx: *C, f: fn(*C, []const f64) -> f64, est: []const f64, k: usize, inv: []f64) -> bool {
    let (par, e2) = mem.alloc[f64](a, k)
    let (hs, e3) = mem.alloc[f64](a, k * k)
    let (col, e4) = mem.alloc[f64](a, k)
    if e2 != ok || e3 != ok || e4 != ok { ret false }
    var i = 0usize
    while i < k {
        par[i] = est[i]
        i += 1usize
    }
    let h = 1.0e-4f64
    let f0 = f(ctx, par[0usize..k])
    i = 0usize
    while i < k {
        var l = i
        while l < k {
            var v = 0.0f64
            if i == l {
                par[i] = est[i] + h
                let fp = f(ctx, par[0usize..k])
                par[i] = est[i] - h
                let fm = f(ctx, par[0usize..k])
                par[i] = est[i]
                v = (fp - 2.0f64 * f0 + fm) / (h * h)
            } else {
                par[i] = est[i] + h
                par[l] = est[l] + h
                let fpp = f(ctx, par[0usize..k])
                par[l] = est[l] - h
                let fpm = f(ctx, par[0usize..k])
                par[i] = est[i] - h
                let fmm = f(ctx, par[0usize..k])
                par[l] = est[l] + h
                let fmp = f(ctx, par[0usize..k])
                par[i] = est[i]
                par[l] = est[l]
                v = (fpp - fpm - fmp + fmm) / (4.0f64 * h * h)
            }
            hs[i * k + l] = v
            hs[l * k + i] = v
            l += 1usize
        }
        i += 1usize
    }
    var cj = 0usize
    while cj < k {
        var t = 0usize
        var mat: [64]f64 = zero
        while t < k * k {
            mat[t] = hs[t]
            t += 1usize
        }
        t = 0usize
        while t < k {
            col[t] = 0.0f64
            t += 1usize
        }
        col[cj] = 1.0f64
        if !qrb.solve_dense(mat[0usize..k * k], col, k) { ret false }
        t = 0usize
        while t < k {
            inv[t * k + cj] = col[t]
            t += 1usize
        }
        cj += 1usize
    }
    ret true
}

// the square roots of the diagonal of that inverse
fn hessian_se[C: type](a: *mem.Arena, ctx: *C, f: fn(*C, []const f64) -> f64, est: []const f64, k: usize, out: []f64) -> bool {
    let (inv, e1) = mem.alloc[f64](a, k * k)
    if e1 != ok { ret false }
    if !hessian_inv[C](a, ctx, f, est, k, inv) { ret false }
    var i = 0usize
    while i < k {
        out[i] = math.sqrt[f64](inv[i * k + i])
        i += 1usize
    }
    ret true
}
