// Numerical derivatives as R's numDeriv computes them: `grad`, `jacobian`, `hessian` and `genD`
// with the Richardson, simple and complex-step methods and their options (eps, d, zero tol, r,
// v), so a result equals numDeriv's for the same function, point and options.
//
// A function is `fn(*Ctx, x, out)`: it reads the point `x` and writes its value (one number, or
// the `m` components of a vector) into `out`. The complex-step methods take the same shape over
// `Complex[f64]`. Matrices answer row-major, `m` rows by `n` columns.
//
// `grad` follows numDeriv's rule for what a function is: one value (`m == 1`) is a scalar
// function of the vector `x`; as many values as variables (`m == n`) is an elementwise function
// and is differentiated in one pass per step, as numDeriv does. `side` holds NaN (central), 1
// (forward) or -1 (backward) per variable; empty means every variable is central.
// `hessian` and `genD` assume Richardson and `v == 2`, as numDeriv's do.

use e.algo.complex as cx
use e.math
use e.mem

type Options = struct { eps: f64, d: f64, zero_tol: f64, r: usize, v: f64 }

error Shape
error NonFinite
error BadSide
error Unsupported

fn machine_eps() -> f64 { ret 0.0000000000000002220446049250313f64 }

// The options numDeriv gives `grad` and `jacobian`.
fn defaults() -> Options {
    ret Options { eps: 0.0001f64, d: 0.0001f64, zero_tol: math.sqrt[f64](machine_eps() / 0.0000007f64), r: 4usize, v: 2.0f64 }
}

// The options `hessian` and `genD`'s hessian use: the step d is 0.1.
fn hessian_defaults() -> Options {
    var o = defaults()
    o.d = 0.1f64
    ret o
}

fn is_nan(x: f64) -> bool { ret x != x }

fn side_at(side: []const f64, i: usize) -> f64 {
    if side.len == 0usize { ret 0.0f64 / 0.0f64 }
    ret side[i]
}

fn check_side(side: []const f64, n: usize) -> err {
    if side.len == 0usize { ret ok }
    if side.len != n { ret BadSide }
    var i = 0usize
    while i < n {
        if !is_nan(side[i]) && side[i] != 1.0f64 && side[i] != -1.0f64 { ret BadSide }
        i += 1usize
    }
    ret ok
}

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

// h = |d x| + eps for the variables below zero_tol in magnitude.
fn steps(a: *mem.Arena, x: []const f64, o: *const Options) -> ([]f64, err) {
    let (h, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (h, e) }
    var i = 0usize
    while i < x.len {
        h[i] = abs_of(o.d * x[i])
        if abs_of(x[i]) < o.zero_tol { h[i] = h[i] + o.eps }
        i += 1usize
    }
    ret (h, ok)
}

fn pow4(m: usize) -> f64 {
    var p = 1.0f64
    var i = 0usize
    while i < m {
        p = p * 4.0f64
        i += 1usize
    }
    ret p
}

// a[k], k < r, each `width` long, refined in place: a[k] <- (a[k+1] 4^m - a[k]) / (4^m - 1).
fn refine(a: []f64, r: usize, width: usize) {
    var m = 1usize
    while m < r {
        let p = pow4(m)
        var k = 0usize
        while k < r - m {
            var j = 0usize
            while j < width {
                a[k * width + j] = (a[(k + 1usize) * width + j] * p - a[k * width + j]) / (p - 1.0f64)
                j += 1usize
            }
            k += 1usize
        }
        m += 1usize
    }
}

// --- Jacobian.

fn jacobian_richardson[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), m: usize, x: []const f64, side: []const f64, o: *const Options) -> ([]f64, err) {
    var none: []f64 = zero
    let n = x.len
    let side_error = check_side(side, n)
    if side_error != ok { ret (none, side_error) }
    let (h, h_error) = steps(a, x, o)
    if h_error != ok { ret (none, h_error) }
    let (table, t_error) = mem.alloc[f64](a, o.r * n * m)
    let (xp, xp_error) = mem.alloc[f64](a, n)
    let (xm, xm_error) = mem.alloc[f64](a, n)
    let (fp, fp_error) = mem.alloc[f64](a, m)
    let (fm, fm_error) = mem.alloc[f64](a, m)
    if t_error != ok || xp_error != ok || xm_error != ok || fp_error != ok || fm_error != ok { ret (none, t_error) }
    var k = 0usize
    while k < o.r {
        var i = 0usize
        while i < n {
            var ph = h[i]
            var mh = h[i]
            let s = side_at(side, i)
            if s == 1.0f64 {
                ph = 2.0f64 * ph
                mh = 0.0f64
            }
            if s == -1.0f64 {
                mh = 2.0f64 * mh
                ph = 0.0f64
            }
            var q = 0usize
            while q < n {
                xp[q] = x[q]
                xm[q] = x[q]
                q += 1usize
            }
            xp[i] = x[i] + ph
            xm[i] = x[i] - mh
            f(ctx, xp, fp)
            f(ctx, xm, fm)
            var j = 0usize
            while j < m {
                table[(k * n + i) * m + j] = (fp[j] - fm[j]) / (2.0f64 * h[i])
                j += 1usize
            }
            i += 1usize
        }
        var i2 = 0usize
        while i2 < n {
            h[i2] = h[i2] / o.v
            i2 += 1usize
        }
        k += 1usize
    }
    refine(table, o.r, n * m)
    let (out, out_error) = mem.alloc[f64](a, m * n)
    if out_error != ok { ret (none, out_error) }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < m {
            out[j * n + i] = table[i * m + j]
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

fn jacobian_simple[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), m: usize, x: []const f64, side: []const f64, eps: f64) -> ([]f64, err) {
    var none: []f64 = zero
    let n = x.len
    let side_error = check_side(side, n)
    if side_error != ok { ret (none, side_error) }
    let (f0, e0) = mem.alloc[f64](a, m)
    let (f1, e1) = mem.alloc[f64](a, m)
    let (dx, e2) = mem.alloc[f64](a, n)
    let (out, e3) = mem.alloc[f64](a, m * n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret (none, e0) }
    f(ctx, x, f0)
    var i = 0usize
    while i < n {
        var step = eps
        if side_at(side, i) == -1.0f64 { step = 0.0f64 - eps }
        var q = 0usize
        while q < n {
            dx[q] = x[q]
            q += 1usize
        }
        dx[i] = dx[i] + step
        f(ctx, dx, f1)
        var j = 0usize
        while j < m {
            out[j * n + i] = (f1[j] - f0[j]) / step
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

fn jacobian_complex[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const cx.Complex[f64], []cx.Complex[f64]), m: usize, x: []const f64) -> ([]f64, err) {
    var none: []f64 = zero
    let n = x.len
    let (z, e0) = mem.alloc[cx.Complex[f64]](a, n)
    let (v, e1) = mem.alloc[cx.Complex[f64]](a, m)
    let (out, e2) = mem.alloc[f64](a, m * n)
    if e0 != ok || e1 != ok || e2 != ok { ret (none, e0) }
    var i = 0usize
    while i < n {
        var q = 0usize
        while q < n {
            z[q] = cx.make[f64](x[q], 0.0f64)
            q += 1usize
        }
        z[i] = cx.make[f64](x[i], machine_eps())
        f(ctx, z, v)
        var j = 0usize
        while j < m {
            out[j * n + i] = v[j].im / machine_eps()
            j += 1usize
        }
        i += 1usize
    }
    ret (out, ok)
}

// --- Gradient.

fn grad_richardson[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), m: usize, x: []const f64, side: []const f64, o: *const Options) -> ([]f64, err) {
    var none: []f64 = zero
    let n = x.len
    if m != 1usize && m != n { ret (none, Shape) }
    if m != n {
        // A scalar function of several variables: numDeriv's per-variable loop, with its
        // guard that a first-order estimate under 1e-20 stays zero at the finer steps.
        let side_error = check_side(side, n)
        if side_error != ok { ret (none, side_error) }
        let (h, h_error) = steps(a, x, o)
        if h_error != ok { ret (none, h_error) }
        let (table, t_error) = mem.alloc[f64](a, o.r * n)
        let (xp, xp_error) = mem.alloc[f64](a, n)
        let (xm, xm_error) = mem.alloc[f64](a, n)
        let (fp, fp_error) = mem.alloc[f64](a, 1usize)
        let (fm, fm_error) = mem.alloc[f64](a, 1usize)
        if t_error != ok || xp_error != ok || xm_error != ok || fp_error != ok || fm_error != ok { ret (none, t_error) }
        var k = 0usize
        while k < o.r {
            var i = 0usize
            while i < n {
                var ph = h[i]
                var mh = h[i]
                let s = side_at(side, i)
                if s == 1.0f64 {
                    ph = 2.0f64 * ph
                    mh = 0.0f64
                }
                if s == -1.0f64 {
                    mh = 2.0f64 * mh
                    ph = 0.0f64
                }
                if k != 0usize && abs_of(table[(k - 1usize) * n + i]) < 0.00000000000000000001f64 {
                    table[k * n + i] = 0.0f64
                } else {
                    var q = 0usize
                    while q < n {
                        xp[q] = x[q]
                        xm[q] = x[q]
                        q += 1usize
                    }
                    xp[i] = x[i] + ph
                    xm[i] = x[i] - mh
                    f(ctx, xp, fp)
                    f(ctx, xm, fm)
                    table[k * n + i] = (fp[0usize] - fm[0usize]) / (2.0f64 * h[i])
                }
                if is_nan(table[k * n + i]) { ret (none, NonFinite) }
                i += 1usize
            }
            var i2 = 0usize
            while i2 < n {
                h[i2] = h[i2] / o.v
                i2 += 1usize
            }
            k += 1usize
        }
        refine(table, o.r, n)
        let (out, out_error) = mem.alloc[f64](a, n)
        if out_error != ok { ret (none, out_error) }
        var i = 0usize
        while i < n {
            out[i] = table[i]
            i += 1usize
        }
        ret (out, ok)
    }
    // As many values as variables: one pass per step over the whole vector.
    let side_error = check_side(side, n)
    if side_error != ok { ret (none, side_error) }
    let (h, h_error) = steps(a, x, o)
    if h_error != ok { ret (none, h_error) }
    let (table, t_error) = mem.alloc[f64](a, o.r * n)
    let (xp, xp_error) = mem.alloc[f64](a, n)
    let (xm, xm_error) = mem.alloc[f64](a, n)
    let (fp, fp_error) = mem.alloc[f64](a, n)
    let (fm, fm_error) = mem.alloc[f64](a, n)
    if t_error != ok || xp_error != ok || xm_error != ok || fp_error != ok || fm_error != ok { ret (none, t_error) }
    var k = 0usize
    while k < o.r {
        var i = 0usize
        while i < n {
            var ph = h[i]
            var mh = h[i]
            let s = side_at(side, i)
            if s == 1.0f64 {
                ph = 2.0f64 * ph
                mh = 0.0f64
            }
            if s == -1.0f64 {
                mh = 2.0f64 * mh
                ph = 0.0f64
            }
            xp[i] = x[i] + ph
            xm[i] = x[i] - mh
            i += 1usize
        }
        f(ctx, xp, fp)
        f(ctx, xm, fm)
        i = 0usize
        while i < n {
            table[k * n + i] = (fp[i] - fm[i]) / (2.0f64 * h[i])
            if is_nan(table[k * n + i]) { ret (none, NonFinite) }
            h[i] = h[i] / o.v
            i += 1usize
        }
        k += 1usize
    }
    refine(table, o.r, n)
    let (out, out_error) = mem.alloc[f64](a, n)
    if out_error != ok { ret (none, out_error) }
    var i = 0usize
    while i < n {
        out[i] = table[i]
        i += 1usize
    }
    ret (out, ok)
}

fn grad_simple[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), m: usize, x: []const f64, side: []const f64, eps: f64) -> ([]f64, err) {
    var none: []f64 = zero
    let n = x.len
    if m != 1usize && m != n { ret (none, Shape) }
    if m != n {
        let (r, e) = jacobian_simple[Ctx](a, ctx, f, m, x, side, eps)
        ret (r, e)
    }
    let side_error = check_side(side, n)
    if side_error != ok { ret (none, side_error) }
    let (f0, e0) = mem.alloc[f64](a, n)
    let (f1, e1) = mem.alloc[f64](a, n)
    let (xe, e2) = mem.alloc[f64](a, n)
    let (out, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { ret (none, e0) }
    f(ctx, x, f0)
    var i = 0usize
    while i < n {
        var step = eps
        if side_at(side, i) == -1.0f64 { step = 0.0f64 - eps }
        xe[i] = x[i] + step
        out[i] = step
        i += 1usize
    }
    f(ctx, xe, f1)
    i = 0usize
    while i < n {
        out[i] = (f1[i] - f0[i]) / out[i]
        i += 1usize
    }
    ret (out, ok)
}

fn grad_complex[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const cx.Complex[f64], []cx.Complex[f64]), m: usize, x: []const f64) -> ([]f64, err) {
    var none: []f64 = zero
    let n = x.len
    if m != 1usize && m != n { ret (none, Shape) }
    if m != n {
        let (r, e) = jacobian_complex[Ctx](a, ctx, f, m, x)
        ret (r, e)
    }
    let (z, e0) = mem.alloc[cx.Complex[f64]](a, n)
    let (v, e1) = mem.alloc[cx.Complex[f64]](a, n)
    let (out, e2) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok { ret (none, e0) }
    var i = 0usize
    while i < n {
        z[i] = cx.make[f64](x[i], machine_eps())
        i += 1usize
    }
    f(ctx, z, v)
    i = 0usize
    while i < n {
        out[i] = v[i].im / machine_eps()
        i += 1usize
    }
    ret (out, ok)
}

// --- genD and the hessian.

// numDeriv's genD: the first derivatives, then the lower triangle of the second, as the
// columns of D (m rows by n (n + 3) / 2): D[:, i] = dF/dx_i, then F''(i, j) for j <= i.
fn gen_d[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), m: usize, x: []const f64, o: *const Options) -> ([]f64, err) {
    var none: []f64 = zero
    if o.v != 2.0f64 { ret (none, Unsupported) }
    let n = x.len
    let r = o.r
    let cols = n * (n + 3usize) / 2usize
    let (h0, h0_error) = steps(a, x, o)
    let (h, h_error) = mem.alloc[f64](a, n)
    let (d, d_error) = mem.alloc[f64](a, m * cols)
    let (f0, e0) = mem.alloc[f64](a, m)
    let (f1, e1) = mem.alloc[f64](a, m)
    let (f2, e2) = mem.alloc[f64](a, m)
    let (dap, e3) = mem.alloc[f64](a, r * m)
    let (hap, e4) = mem.alloc[f64](a, r * m)
    let (hdiag, e5) = mem.alloc[f64](a, m * n)
    let (xp, e6) = mem.alloc[f64](a, n)
    let (xm, e7) = mem.alloc[f64](a, n)
    if h0_error != ok || h_error != ok || d_error != ok || e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok { ret (none, d_error) }
    f(ctx, x, f0)
    var i = 0usize
    while i < n {
        var q = 0usize
        while q < n {
            h[q] = h0[q]
            q += 1usize
        }
        var k = 0usize
        while k < r {
            q = 0usize
            while q < n {
                xp[q] = x[q]
                xm[q] = x[q]
                q += 1usize
            }
            xp[i] = x[i] + h[i]
            xm[i] = x[i] - h[i]
            f(ctx, xp, f1)
            f(ctx, xm, f2)
            var j = 0usize
            while j < m {
                dap[k * m + j] = (f1[j] - f2[j]) / (2.0f64 * h[i])
                hap[k * m + j] = (f1[j] - 2.0f64 * f0[j] + f2[j]) / (h[i] * h[i])
                j += 1usize
            }
            q = 0usize
            while q < n {
                h[q] = h[q] / o.v
                q += 1usize
            }
            k += 1usize
        }
        refine(dap, r, m)
        refine(hap, r, m)
        var j = 0usize
        while j < m {
            d[j * cols + i] = dap[j]
            hdiag[j * n + i] = hap[j]
            j += 1usize
        }
        i += 1usize
    }
    var u = n
    i = 0usize
    while i < n {
        var jj = 0usize
        while jj <= i {
            if i == jj {
                var j = 0usize
                while j < m {
                    d[j * cols + u] = hdiag[j * n + i]
                    j += 1usize
                }
            } else {
                var q = 0usize
                while q < n {
                    h[q] = h0[q]
                    q += 1usize
                }
                var k = 0usize
                while k < r {
                    q = 0usize
                    while q < n {
                        xp[q] = x[q]
                        xm[q] = x[q]
                        q += 1usize
                    }
                    xp[i] = xp[i] + h[i]
                    xp[jj] = xp[jj] + h[jj]
                    xm[i] = xm[i] - h[i]
                    xm[jj] = xm[jj] - h[jj]
                    f(ctx, xp, f1)
                    f(ctx, xm, f2)
                    var j = 0usize
                    while j < m {
                        dap[k * m + j] = (f1[j] - 2.0f64 * f0[j] + f2[j] - hdiag[j * n + i] * (h[i] * h[i]) - hdiag[j * n + jj] * (h[jj] * h[jj])) / (2.0f64 * h[i] * h[jj])
                        j += 1usize
                    }
                    q = 0usize
                    while q < n {
                        h[q] = h[q] / o.v
                        q += 1usize
                    }
                    k += 1usize
                }
                refine(dap, r, m)
                var j = 0usize
                while j < m {
                    d[j * cols + u] = dap[j]
                    j += 1usize
                }
            }
            u += 1usize
            jj += 1usize
        }
        i += 1usize
    }
    ret (d, ok)
}

// The Richardson hessian of a scalar function, n by n.
fn hessian_richardson[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const f64, []f64), x: []const f64, o: *const Options) -> ([]f64, err) {
    var none: []f64 = zero
    let n = x.len
    let (d, d_error) = gen_d[Ctx](a, ctx, f, 1usize, x, o)
    if d_error != ok { ret (none, d_error) }
    let (hm, h_error) = mem.alloc[f64](a, n * n)
    if h_error != ok { ret (none, h_error) }
    var u = n
    var i = 0usize
    while i < n {
        var j = 0usize
        while j <= i {
            hm[i * n + j] = d[u]
            hm[j * n + i] = d[u]
            u += 1usize
            j += 1usize
        }
        i += 1usize
    }
    ret (hm, ok)
}

// The complex-step hessian: the Richardson Jacobian of the complex-step gradient.
type StepCtx[Ctx: type] = struct { a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const cx.Complex[f64], []cx.Complex[f64]) }

fn step_gradient[Ctx: type](sc: *StepCtx[Ctx], x: []const f64, out: []f64) {
    let (g, e) = jacobian_complex[Ctx](sc.a, sc.ctx, sc.f, 1usize, x)
    if e != ok { ret }
    var i = 0usize
    while i < x.len {
        out[i] = g[i]
        i += 1usize
    }
}

fn hessian_complex[Ctx: type](a: *mem.Arena, ctx: *Ctx, f: fn(*Ctx, []const cx.Complex[f64], []cx.Complex[f64]), x: []const f64, o: *const Options) -> ([]f64, err) {
    var sc = StepCtx[Ctx] { a: a, ctx: ctx, f: f }
    let empty: []const f64 = zero
    let (r, e) = jacobian_richardson[StepCtx[Ctx]](a, &sc, step_gradient[Ctx], x.len, x, empty, o)
    ret (r, e)
}
