// R gld, the optimiser-driven fits, over R's optim Nelder-Mead (e.algo.stat.rnm): `starship` (the adaptive grid and then Nelder-Mead on the Anderson-Darling
// statistic, in the fkml, rs, fm5 and gpd parameterisations; fit.gpd(method = "SM") is the gpd one), `fit_fkml_moments` (fit.fkml.moments: Nelder-Mead inside
// constrOptim's barrier on the skewness and kurtosis), and `fit_fkml` (fit.fkml with method ML, MPS, TM, SM, TL, LMOM, DLA and MOM).
// The fits agree with R as far as the optimiser's own convergence (relative tolerance 1.5e-8 on the objective) allows.

use e.algo.sort
use e.algo.stat.gldfull as gl
use e.algo.stat.rnm as nmo
use e.math
use e.math.nmath_beta as nb
use e.math.special as sp
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn inf() -> f64 { ret 1.0f64 / 0.0f64 }

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

// quantile(x, p, type 7) of sorted data
fn q7(s: []const f64, p: f64) -> f64 {
    let n = s.len
    let index = 1.0f64 + f64(n - 1usize) * p
    let lo = math.floor[f64](index)
    let hi = math.ceil[f64](index)
    let qs = s[usize(lo) - 1usize]
    let xh = s[usize(hi) - 1usize]
    if index > lo && xh != qs {
        let h = index - lo
        ret (1.0f64 - h) * qs + h * xh
    }
    ret qs
}

type FitCtx = struct {
    kind: i32,
    param: i32,
    method: i32,
    x: []const f64,
    u: []f64,
    n: usize,
    eps: f64,
    pen: f64,
    t1: f64,
    t2: f64,
    scale: [5]f64,
    old: [2]f64,
    mu: f64,
    skew: f64,
    kurt: f64,
    variance: f64,
    w1: []f64,
    w2: []f64,
}

// ---- starship ----------------------------------------------------------------------------------------------------

// starship.obj: the Anderson-Darling statistic of the data under the parameter vector (54321 when the parameters are not valid)
fn starship_obj(param: i32, par: []const f64, x: []const f64, u: []f64, eps: f64) -> f64 {
    if !gl.check_lambda(param, par) { ret 54321.0f64 }
    let n = x.len
    var j = 0usize
    while j < n {
        u[j] = gl.pgl(param, x[j], par, eps, 500usize)
        j += 1usize
    }
    var sum = 0.0f64
    j = 1usize
    while j <= n {
        sum += ((2.0f64 * f64(j) - 1.0f64) / f64(n)) * (math.log[f64](u[j - 1usize]) + math.log[f64](1.0f64 - u[n - j]))
        j += 1usize
    }
    ret 0.0f64 - f64(n) - sum
}

// ---- fit.fkml's C objective -------------------------------------------------------------------------------------------

fn do_qf(u: f64, l1: f64, l2: f64, l3: f64, l4: f64) -> f64 {
    var l: [4]f64 = zero
    l[0usize] = l1
    l[1usize] = l2
    l[2usize] = l3
    l[3usize] = l4
    ret gl.qgl(0i32, u, l[0usize..4usize])
}

// do_Fx: F(x) by the root finder, without the bracket check, returning the last iterate when it does not settle
fn do_fx_cdf(x: f64, l1: f64, l2: f64, l3: f64, l4: f64, eps: f64) -> f64 {
    var l: [4]f64 = zero
    l[0usize] = l1
    l[1usize] = l2
    l[2usize] = l3
    l[3usize] = l4
    let extreme1 = do_qf(eps, l1, l2, l3, l4)
    let extreme2 = do_qf(1.0f64 - eps, l1, l2, l3, l4)
    if x < extreme1 { ret 0.0f64 }
    if x > extreme2 { ret 1.0f64 }
    var u1 = 0.0f64
    var u2 = 1.0f64
    if l3 <= 0.0f64 { u1 = eps }
    if l4 <= 0.0f64 { u2 = 1.0f64 - eps }
    let (fl, dl) = gl.funcd(0i32, l[0usize..4usize], u1, x)
    let (fh, dh) = gl.funcd(0i32, l[0usize..4usize], u2, x)
    var xl = 0.0f64
    var xh = 0.0f64
    if fl < 0.0f64 {
        xl = u1
        xh = u2
    } else {
        xh = u1
        xl = u2
    }
    var rts = 0.5f64 * (u1 + u2)
    var dxold = math.abs[f64](u2 - u1)
    var dx = dxold
    let (f0, df0) = gl.funcd(0i32, l[0usize..4usize], rts, x)
    var f = f0
    var df = df0
    var j = 1usize
    while j <= 500usize {
        if (((rts - xh) * df - f) * ((rts - xl) * df - f) >= 0.0f64) || (math.abs[f64](2.0f64 * f) > math.abs[f64](dxold * df)) {
            dxold = dx
            dx = 0.5f64 * (xh - xl)
            rts = xl + dx
            if xl == rts { ret rts }
        } else {
            dxold = dx
            dx = f / df
            let temp = rts
            rts = rts - dx
            if temp == rts { ret rts }
        }
        if math.abs[f64](dx) < eps { ret rts }
        let (f2, df2) = gl.funcd(0i32, l[0usize..4usize], rts, x)
        f = f2
        df = df2
        if f < 0.0f64 {
            xl = rts
        } else {
            xh = rts
        }
        j += 1usize
    }
    ret rts
}

// do_fx: the FKML density at the depth u, 0 outside the support
fn do_fx_pdf(u: f64, x: f64, l1: f64, l2: f64, l3: f64, l4: f64) -> f64 {
    var umin = 1.0e-8f64
    if l3 > 0.0f64 { umin = 0.0f64 }
    var umax = 1.0f64 - 1.0e-8f64
    if l4 > 0.0f64 { umax = 1.0f64 }
    let e1 = do_qf(umin, l1, l2, l3, l4)
    let e2 = do_qf(umax, l1, l2, l3, l4)
    if x < e1 || x > e2 { ret 0.0f64 }
    if (u == 0.0f64 && l3 < 1.0f64) || (u == 1.0f64 && l4 < 1.0f64) { ret 0.0f64 }
    ret l2 / (math.pow[f64](u, l3 - 1.0f64) + math.pow[f64](1.0f64 - u, l4 - 1.0f64))
}

fn int_term(a: f64, b: f64, l3: f64, l4: f64) -> f64 {
    let tol = 1.0e-5f64
    if math.abs[f64](l3) < tol {
        if math.abs[f64](l4) < tol { ret gl.rbeta_fn(a + 1.0f64, b + 1.0f64) * (gl.bern_psi(0usize, a + 1.0f64) - gl.bern_psi(0usize, b + 1.0f64)) }
        ret gl.rbeta_fn(a + 1.0f64, b + 1.0f64) * (gl.bern_psi(0usize, a + 1.0f64) - gl.bern_psi(0usize, a + b + 2.0f64)) - gl.rbeta_fn(a + 1.0f64, l4 + b + 1.0f64) / l4
    }
    if math.abs[f64](l4) < tol { ret gl.rbeta_fn(l3 + a + 1.0f64, b + 1.0f64) / l3 - gl.rbeta_fn(a + 1.0f64, b + 1.0f64) * (gl.bern_psi(0usize, b + 1.0f64) - gl.bern_psi(0usize, a + b + 2.0f64)) }
    ret gl.rbeta_fn(l3 + a + 1.0f64, b + 1.0f64) / l3 - gl.rbeta_fn(a + 1.0f64, l4 + b + 1.0f64) / l4
}

fn tl_moments(r: usize, t1: f64, t2: f64, l2: f64, l3: f64, l4: f64) -> f64 {
    var sum = 0.0f64
    var k = 0usize
    let rf = f64(r)
    while k < r {
        let kf = f64(k)
        let a = rf - kf + t1 - 1.0f64
        let b = kf + t2
        sum = sum + math.pow[f64](0.0f64 - 1.0f64, kf) * sp.choose(rf - 1.0f64, kf) * sp.choose(rf + t1 + t2 - 1.0f64, kf + t2) * int_term(a, b, l3, l4)
        k += 1usize
    }
    ret (rf + t1 + t2) / (rf * l2) * sum
}

fn tl_sample_moments(r: usize, t1: f64, t2: f64, x: []const f64) -> f64 {
    let n = x.len
    var sum = 0.0f64
    let rf = f64(r)
    var i = 0usize
    while i < n {
        var k = 0usize
        while k < r {
            let kf = f64(k)
            sum = sum + math.pow[f64](0.0f64 - 1.0f64, kf) * sp.choose(rf - 1.0f64, kf) * sp.choose(f64(i), rf - kf + t1 - 1.0f64) * sp.choose(f64(n - i) - 1.0f64, kf + t2) * x[i]
            k += 1usize
        }
        i += 1usize
    }
    ret sum / (rf * sp.choose(f64(n), rf + t1 + t2))
}

// compute_l1_l2: the TL-moment matching l2 and l1 for the shapes (l3, l4); out = (l1, l2)
fn tl_l1_l2(l3: f64, l4: f64, x: []const f64, t1: f64, t2: f64, out: []f64) {
    let l2 = tl_moments(2usize, t1, t2, 1.0f64, l3, l4) / tl_sample_moments(2usize, t1, t2, x)
    var shift = 0.0f64
    let tol = 1.0e-5f64
    if math.abs[f64](l3) < tol {
        if math.abs[f64](l4) >= tol { shift = 0.0f64 - 1.0f64 / (l2 * l4) }
    } else if math.abs[f64](l4) < tol {
        shift = 1.0f64 / (l2 * l3)
    } else {
        shift = 1.0f64 / (l2 * l3) - 1.0f64 / (l2 * l4)
    }
    out[1usize] = l2
    out[0usize] = shift + tl_sample_moments(1usize, t1, t2, x) - tl_moments(1usize, t1, t2, l2, l3, l4)
}

// conditions: whether the TL-moment fit is valid at the shapes; out = (l1, l2) as computed
fn tl_conditions(l3: f64, l4: f64, x: []const f64, t1: f64, t2: f64, out: []f64) -> bool {
    if !(l3 > 0.0f64 - (1.0f64 + t1) && l4 > 0.0f64 - (1.0f64 + t2)) { ret false }
    tl_l1_l2(l3, l4, x, t1, t2, out)
    if !(tl_moments(2usize, t1, t2, out[1usize], l3, l4) > 0.0f64) { ret false }
    let m2 = tl_moments(2usize, t1, t2, 1.0f64, l3, l4)
    let tau3 = tl_moments(3usize, t1, t2, 1.0f64, l3, l4) / m2
    if !(0.0f64 - 1.0f64 < tau3 && tau3 < 1.0f64) { ret false }
    let tau4 = tl_moments(4usize, t1, t2, 1.0f64, l3, l4) / m2
    if !(0.25f64 * (5.0f64 * tau3 * tau3 - 1.0f64) <= tau4 && tau4 < 1.0f64) { ret false }
    ret do_qf(0.0f64, out[0usize], out[1usize], l3, l4) <= x[0usize] && do_qf(1.0f64, out[0usize], out[1usize], l3, l4) >= x[x.len - 1usize]
}

// fit_fkml: the objective of the fkml fits for one method (1 ML, 2 MPS, 3 TM, 4 SM, 5 TL, 6 DLA) at (l1, l2, l3, l4); x sorted. tl_out receives (l1, l2) of the TL fit.
fn fit_fkml_value(c: *FitCtx, method: i32, l1: f64, l2: f64, l3: f64, l4: f64, tl_out: []f64) -> f64 {
    if l2 <= 0.0f64 { ret c.pen }
    let x = c.x
    let n = c.n
    let nf = f64(n)
    let eps = c.eps
    if method == 1i32 {
        var out = 0.0f64
        var i = 0usize
        while i < n {
            let u = do_fx_cdf(x[i], l1, l2, l3, l4, eps)
            let d = do_fx_pdf(u, x[i], l1, l2, l3, l4)
            if d == 0.0f64 {
                out = 0.0f64 - inf()
                i = n
            } else {
                out += math.log[f64](d)
                i += 1usize
            }
        }
        ret 0.0f64 - out / nf
    }
    if method == 2i32 || method == 3i32 {
        var m = n
        if method == 3i32 { m = n - 1usize }
        let f = c.w1
        let zz = c.w2
        var i = 0usize
        while i < m {
            if method == 3i32 { zz[i] = (x[i] + x[i + 1usize]) / 2.0f64 } else { zz[i] = x[i] }
            f[i] = do_fx_cdf(zz[i], l1, l2, l3, l4, eps)
            i += 1usize
        }
        var out = 0.0f64
        if f[0usize] == 0.0f64 || f[m - 1usize] == 1.0f64 {
            out = 0.0f64 - inf()
        } else {
            out = math.log[f64](f[0usize]) + math.log[f64](1.0f64 - f[m - 1usize])
            i = 1usize
            while i < m {
                var diff = f[i] - f[i - 1usize]
                if diff <= 0.0f64 {
                    let u = do_fx_cdf(zz[i - 1usize], l1, l2, l3, l4, eps)
                    let d = do_fx_pdf(u, zz[i - 1usize], l1, l2, l3, l4)
                    if d == 0.0f64 {
                        out = 0.0f64 - inf()
                        i = m
                    } else {
                        diff = d
                    }
                }
                if i < m {
                    out += math.log[f64](diff)
                    i += 1usize
                }
            }
        }
        if method == 2i32 { ret 0.0f64 - out / (nf + 1.0f64) }
        ret 0.0f64 - out / nf
    }
    if method == 4i32 {
        var out = 0.0f64
        var i = 0usize
        while i < n {
            let u = do_fx_cdf(x[i], l1, l2, l3, l4, eps)
            if u == 0.0f64 || u == 1.0f64 {
                out = 0.0f64 - inf()
                i = n
            } else {
                out += f64(2usize * i + 1usize) * math.log[f64](u) + f64(2usize * (n - i) - 1usize) * math.log[f64](1.0f64 - u)
                i += 1usize
            }
        }
        ret 0.0f64 - nf - out / nf
    }
    if method == 5i32 {
        if !tl_conditions(l3, l4, x, c.t1, c.t2, tl_out) { ret c.pen }
        let m2 = tl_moments(2usize, c.t1, c.t2, 1.0f64, l3, l4)
        let tau3 = tl_moments(3usize, c.t1, c.t2, 1.0f64, l3, l4) / m2
        let tau4 = tl_moments(4usize, c.t1, c.t2, 1.0f64, l3, l4) / m2
        let s2 = tl_sample_moments(2usize, c.t1, c.t2, x)
        let tau3s = tl_sample_moments(3usize, c.t1, c.t2, x) / s2
        let tau4s = tl_sample_moments(4usize, c.t1, c.t2, x) / s2
        ret (tau3 - tau3s) * (tau3 - tau3s) + (tau4 - tau4s) * (tau4 - tau4s)
    }
    var out = 0.0f64
    var i = 0usize
    while i < n {
        let p = nb.qbeta(0.5f64, f64(i + 1usize), f64(n - i), true, false)
        let m = do_qf(p, l1, l2, l3, l4)
        out += math.abs[f64](x[i] - m)
        i += 1usize
    }
    ret out
}

// ---- the objective for Nelder-Mead --------------------------------------------------------------------------------

// kind 0 starship, 1 fkml method, 2 TL (l3, l4), 3 constrOptim barrier of the moment fit
fn fit_obj(c: *FitCtx, p: []const f64) -> f64 {
    var par: [5]f64 = zero
    var i = 0usize
    while i < p.len {
        par[i] = p[i] * c.scale[i]
        i += 1usize
    }
    if c.kind == 0i32 {
        var np = 4usize
        if c.param == 2i32 { np = 5usize }
        ret starship_obj(c.param, par[0usize..np], c.x, c.u, c.eps)
    }
    var tl: [2]f64 = zero
    if c.kind == 1i32 {
        ret fit_fkml_value(c, c.method, par[0usize], par[1usize], par[2usize], par[3usize], tl[0usize..2usize])
    }
    if c.kind == 2i32 { ret fit_fkml_value(c, 5i32, 0.0f64, 1.0f64, par[0usize], par[1usize], tl[0usize..2usize]) }
    ret moment_barrier(c, par[0usize], par[1usize])
}

fn moment_f(c: *FitCtx, l3: f64, l4: f64) -> f64 {
    let v1 = gl.vk(1usize, l3, l4)
    let v2 = gl.vk(2usize, l3, l4)
    let v3 = gl.vk(3usize, l3, l4)
    let v4 = gl.vk(4usize, l3, l4)
    let sl = v2 - v1 * v1
    let a3 = (v3 - 3.0f64 * v1 * v2 + 2.0f64 * v1 * v1 * v1) / math.pow[f64](sl, 1.5f64)
    let a4 = (v4 - 4.0f64 * v1 * v3 + 6.0f64 * v1 * v1 * v2 - 3.0f64 * v1 * v1 * v1 * v1) / (sl * sl)
    ret (c.skew - a3) * (c.skew - a3) + (c.kurt - a4) * (c.kurt - a4)
}

// constrOptim's R(theta, theta.old) with ui = I and ci = -0.25 + eps
fn moment_barrier(c: *FitCtx, l3: f64, l4: f64) -> f64 {
    let ci = 0.0f64 - 0.25f64 + 2.220446049250313e-16f64
    let g1 = l3 - ci
    let g2 = l4 - ci
    if g1 < 0.0f64 || g2 < 0.0f64 { ret nan() }
    let go1 = c.old[0usize] - ci
    let go2 = c.old[1usize] - ci
    var bar = (go1 * math.log[f64](g1) - l3) + (go2 * math.log[f64](g2) - l4)
    if bar != bar || bar - bar != 0.0f64 { bar = 0.0f64 - inf() }
    ret moment_f(c, l3, l4) - c.mu * bar
}

// ---- drivers -------------------------------------------------------------------------------------------------------

// the package's default search grids into g, the count answered: 0 starship fkml and fm5 (11), 1 starship rs (6), 2 starship gpd lambda (8), 3 starship gpd delta (3), 4 starship fm5 l5 (5), 5 fit.fkml (10)
fn grid_fill(which: usize, g: []f64) -> usize {
    var v: [11]f64 = zero
    var n = 0usize
    if which == 0usize || which == 5usize {
        v[0usize] = 0.0f64 - 1.5f64
        v[1usize] = 0.0f64 - 1.0f64
        v[2usize] = 0.0f64 - 0.5f64
        v[3usize] = 0.0f64 - 0.1f64
        v[4usize] = 0.0f64
        v[5usize] = 0.1f64
        v[6usize] = 0.2f64
        v[7usize] = 0.4f64
        v[8usize] = 0.8f64
        v[9usize] = 1.0f64
        v[10usize] = 1.5f64
        n = 11usize
        if which == 5usize {
            v[0usize] = 0.0f64 - 0.9f64
            v[1usize] = 0.0f64 - 0.5f64
            v[2usize] = 0.0f64 - 0.1f64
            v[3usize] = 0.0f64
            v[4usize] = 0.1f64
            v[5usize] = 0.2f64
            v[6usize] = 0.4f64
            v[7usize] = 0.8f64
            v[8usize] = 1.0f64
            v[9usize] = 1.5f64
            n = 10usize
        }
    }
    if which == 1usize {
        v[0usize] = 0.1f64
        v[1usize] = 0.2f64
        v[2usize] = 4.0f64
        v[3usize] = 0.8f64
        v[4usize] = 1.0f64
        v[5usize] = 1.5f64
        n = 6usize
    }
    if which == 2usize {
        v[0usize] = 0.0f64 - 1.5f64
        v[1usize] = 0.0f64 - 0.5f64
        v[2usize] = 0.0f64
        v[3usize] = 0.2f64
        v[4usize] = 0.4f64
        v[5usize] = 0.8f64
        v[6usize] = 1.5f64
        v[7usize] = 5.0f64
        n = 8usize
    }
    if which == 3usize {
        v[0usize] = 0.3f64
        v[1usize] = 0.5f64
        v[2usize] = 0.7f64
        n = 3usize
    }
    if which == 4usize {
        v[0usize] = 0.0f64 - 0.5f64
        v[1usize] = 0.0f64 - 0.25f64
        v[2usize] = 0.0f64
        v[3usize] = 0.25f64
        v[4usize] = 0.5f64
        n = 5usize
    }
    var i = 0usize
    while i < n {
        g[i] = v[i]
        i += 1usize
    }
    ret n
}

fn new_ctx(a: *mem.Arena, kind: i32, param: i32, x: []const f64) -> (FitCtx, err) {
    let n = x.len
    let (u, e1) = mem.alloc[f64](a, n)
    let (w1, e2) = mem.alloc[f64](a, n)
    let (w2, e3) = mem.alloc[f64](a, n)
    var sc: [5]f64 = zero
    var ol: [2]f64 = zero
    var i = 0usize
    while i < 5usize {
        sc[i] = 1.0f64
        i += 1usize
    }
    var c = FitCtx { kind: kind, param: param, method: 0i32, x: x, u: u, n: n, eps: 2.220446049250313e-16f64, pen: 1.0e20f64, t1: 0.0f64, t2: 0.0f64, scale: sc, old: ol, mu: 1.0e-4f64, skew: 0.0f64, kurt: 0.0f64, variance: 1.0f64, w1: w1, w2: w2 }
    if e1 != ok { ret (c, e1) }
    if e2 != ok { ret (c, e2) }
    ret (c, e3)
}

// optim(start, fit_obj, method = "Nelder-Mead", control = list(maxit = maxit, parscale = c.scale)): the minimiser into out; answers (value, function count, fail code)
fn run_nm(a: *mem.Arena, c: *FitCtx, start: []const f64, maxit: usize, out: []f64) -> (f64, usize, usize) {
    var s: [5]f64 = zero
    var xo: [5]f64 = zero
    let np = start.len
    var i = 0usize
    while i < np {
        s[i] = start[i] / c.scale[i]
        i += 1usize
    }
    let (v, cnt, fail) = nmo.nmmin[FitCtx](a, c, fit_obj, s[0usize..np], 0.0f64 - inf(), 1.4901161193847656e-08f64, 1.0f64, 0.5f64, 2.0f64, maxit, 1.0f64, xo[0usize..np])
    i = 0usize
    while i < np {
        out[i] = xo[i] * c.scale[i]
        i += 1usize
    }
    ret (v, cnt, fail)
}

fn sorted_copy(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (s, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (s, e) }
    var i = 0usize
    while i < x.len {
        s[i] = x[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](s, &ctx, cmp_up)
    ret (s, ok)
}

// starship.adaptivegrid: the grid search over (l3, l4[, l5]) with l1, l2 guessed from the quartiles; lam receives the best vector, the answer is its response
fn adaptive_grid(c: *FitCtx, param: i32, ld: []const f64, lc: []const f64, le: []const f64, lam: []f64) -> f64 {
    let x = c.x
    let iqr = q7(x, 0.75f64) - q7(x, 0.25f64)
    let med = q7(x, 0.5f64)
    var best = 1000.0f64
    var np = 4usize
    var ne = 1usize
    if param == 2i32 {
        np = 5usize
        ne = le.len
    }
    var ie = 0usize
    while ie < ne {
        var id = 0usize
        while id < ld.len {
            var ic = 0usize
            while ic < lc.len {
                var t: [5]f64 = zero
                t[0usize] = 0.0f64
                t[1usize] = 1.0f64
                t[2usize] = lc[ic]
                t[3usize] = ld[id]
                if param == 2i32 { t[4usize] = le[ie] }
                let iqr1 = gl.qgl(param, 0.75f64, t[0usize..np]) - gl.qgl(param, 0.25f64, t[0usize..np])
                let lbguess = iqr1 / iqr
                var ib = 0usize
                while ib < 5usize {
                    var mult = 0.5f64
                    if ib == 1usize { mult = 0.7f64 }
                    if ib == 2usize { mult = 1.0f64 }
                    if ib == 3usize { mult = 1.5f64 }
                    if ib == 4usize { mult = 2.0f64 }
                    let lb = mult * lbguess
                    t[1usize] = lb
                    var ia = 0usize
                    while ia < 5usize {
                        var pp = 0.65f64
                        if ia == 1usize { pp = 0.55f64 }
                        if ia == 2usize { pp = 0.5f64 }
                        if ia == 3usize { pp = 0.45f64 }
                        if ia == 4usize { pp = 0.35f64 }
                        let la = med - gl.qgl(param, pp, t[0usize..np])
                        var v: [5]f64 = zero
                        v[0usize] = la
                        v[1usize] = lb
                        v[2usize] = lc[ic]
                        v[3usize] = ld[id]
                        if param == 2i32 { v[4usize] = le[ie] }
                        let resp = starship_obj(param, v[0usize..np], x, c.u, c.eps)
                        if resp < best {
                            best = resp
                            var k = 0usize
                            while k < np {
                                lam[k] = v[k]
                                k += 1usize
                            }
                        }
                        ia += 1usize
                    }
                    ib += 1usize
                }
                ic += 1usize
            }
            id += 1usize
        }
        ie += 1usize
    }
    ret best
}

// starship(data, param): the grid and then Nelder-Mead. param 0 fkml, 1 rs, 2 fm5, 3 gpd; the grids are the package's defaults.
// lam receives the fit (4 or 5 values); info = (grid response, grid l1 .. l5, optim value, function count, fail code)
fn starship(a: *mem.Arena, param: i32, data: []const f64, eps: f64, lam: []f64, info: []f64) -> err {
    let (x, e1) = sorted_copy(a, data)
    if e1 != ok { ret e1 }
    let (c0, e2) = new_ctx(a, 0i32, param, x)
    if e2 != ok { ret e2 }
    var c = c0
    c.eps = eps
    var ld: [11]f64 = zero
    var lc: [11]f64 = zero
    var le: [5]f64 = zero
    var nld = grid_fill(0usize, ld[0usize..11usize])
    var nlc = nld
    lc = ld
    if param == 1i32 {
        nld = grid_fill(1usize, ld[0usize..11usize])
        nlc = grid_fill(1usize, lc[0usize..11usize])
    }
    if param == 3i32 {
        nld = grid_fill(2usize, ld[0usize..11usize])
        nlc = grid_fill(3usize, lc[0usize..11usize])
    }
    let nle = grid_fill(4usize, le[0usize..5usize])
    var np = 4usize
    if param == 2i32 { np = 5usize }
    var g: [5]f64 = zero
    let resp = adaptive_grid(&c, param, ld[0usize..nld], lc[0usize..nlc], le[0usize..nle], g[0usize..np])
    info[0usize] = resp
    var k = 0usize
    while k < 5usize {
        info[1usize + k] = g[k]
        k += 1usize
    }
    c.scale[0usize] = math.abs[f64](g[0usize])
    if c.scale[0usize] < 1.0f64 { c.scale[0usize] = 1.0f64 }
    c.scale[1usize] = math.abs[f64](g[1usize])
    c.scale[2usize] = 1.0f64
    c.scale[3usize] = 1.0f64
    c.scale[4usize] = 1.0f64
    let (v, cnt, fail) = run_nm(a, &c, g[0usize..np], 500usize, lam)
    info[6usize] = v
    info[7usize] = f64(cnt)
    info[8usize] = f64(fail)
    ret ok
}

// fit.fkml.moments: the skewness and kurtosis of the data matched by Nelder-Mead inside constrOptim's barrier; lam receives (l1 .. l4); info = (value, outer iterations)
fn fit_fkml_moments(a: *mem.Arena, data: []const f64, lam: []f64, info: []f64) -> err {
    let n = data.len
    let nf = f64(n)
    var sum = 0.0f64
    var i = 0usize
    while i < n {
        sum += data[i]
        i += 1usize
    }
    let mean = sum / nf
    var ss = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    i = 0usize
    while i < n {
        let d = data[i] - mean
        ss += d * d
        m3 += d * d * d
        m4 += d * d * d * d
        i += 1usize
    }
    let variance = ss / (nf - 1.0f64)
    let skew = (m3 / nf) / math.pow[f64](variance, 1.5f64)
    let kurt = (m4 / nf) / (variance * variance)
    let (c0, e) = new_ctx(a, 3i32, 0i32, data)
    if e != ok { ret e }
    var c = c0
    c.skew = skew
    c.kurt = kurt
    var theta: [2]f64 = zero
    var apar: [2]f64 = zero
    var obj = moment_f(&c, theta[0usize], theta[1usize])
    c.old[0usize] = theta[0usize]
    c.old[1usize] = theta[1usize]
    var r = moment_barrier(&c, theta[0usize], theta[1usize])
    var outer = 1usize
    var done = false
    while outer <= 100usize && !done {
        let obj_old = obj
        let r_old = r
        c.old[0usize] = theta[0usize]
        c.old[1usize] = theta[1usize]
        let (v, cnt, fail) = run_nm(a, &c, theta[0usize..2usize], 500usize, apar[0usize..2usize])
        r = v
        if r - r == 0.0f64 && r_old - r_old == 0.0f64 && math.abs[f64](r - r_old) < (0.001f64 + math.abs[f64](r)) * 1.0e-5f64 {
            done = true
        } else {
            theta[0usize] = apar[0usize]
            theta[1usize] = apar[1usize]
            obj = moment_f(&c, theta[0usize], theta[1usize])
            if obj > obj_old {
                done = true
            } else {
                outer += 1usize
            }
        }
    }
    let l3 = apar[0usize]
    let l4 = apar[1usize]
    let v1 = gl.vk(1usize, l3, l4)
    let l2 = math.sqrt[f64]((gl.vk(2usize, l3, l4) - v1 * v1) / variance)
    var l1 = nan()
    if l3 == 0.0f64 || l4 == 0.0f64 || l3 == l4 {
        l1 = mean - v1 / l2
    } else {
        l1 = mean - (v1 - 1.0f64 / l3 + 1.0f64 / l4) / l2
    }
    lam[0usize] = l1
    lam[1usize] = l2
    lam[2usize] = l3
    lam[3usize] = l4
    info[0usize] = moment_f(&c, l3, l4)
    info[1usize] = f64(outer)
    ret ok
}

// fit.fkml(x, method, t1, t2, l3.grid, l4.grid): method 1 ML, 2 MPS, 3 TM, 4 SM, 5 TL / LMOM, 6 DLA, 7 MOM; lam receives (l1 .. l4); info = (optim value, function count, fail code, start l1 .. l4)
// pen is optim.penalty (1e20); a TL fit whose optimum is the penalty has no estimate and reports fail code 99
fn fit_fkml(a: *mem.Arena, data: []const f64, method: i32, t1: f64, t2: f64, g3: []const f64, g4: []const f64, eps: f64, pen: f64, lam: []f64, info: []f64) -> err {
    if method == 7i32 { ret fit_fkml_moments(a, data, lam, info) }
    let (x, e1) = sorted_copy(a, data)
    if e1 != ok { ret e1 }
    let (c0, e2) = new_ctx(a, 1i32, 0i32, x)
    if e2 != ok { ret e2 }
    var c = c0
    c.eps = eps
    c.pen = pen
    c.method = method
    c.t1 = t1
    c.t2 = t2
    let iqr = q7(x, 0.75f64) - q7(x, 0.25f64)
    let med = q7(x, 0.5f64)
    var tl: [2]f64 = zero
    var best = inf()
    var start: [4]f64 = zero
    start[1usize] = 1.0f64
    start[2usize] = 0.0f64 - 0.1f64
    start[3usize] = 0.0f64 - 0.1f64
    var i = 0usize
    while i < g3.len {
        var j = 0usize
        while j < g4.len {
            let l3 = g3[i]
            let l4 = g4[j]
            var obj = 0.0f64
            if method == 5i32 {
                obj = fit_fkml_value(&c, 5i32, 0.0f64, 1.0f64, l3, l4, tl[0usize..2usize])
                if obj < best {
                    best = obj
                    start[2usize] = l3
                    start[3usize] = l4
                }
            } else {
                let l2 = (do_qf(0.75f64, 0.0f64, 1.0f64, l3, l4) - do_qf(0.25f64, 0.0f64, 1.0f64, l3, l4)) / iqr
                let l1 = med - do_qf(0.5f64, 0.0f64, l2, l3, l4)
                obj = fit_fkml_value(&c, method, l1, l2, l3, l4, tl[0usize..2usize])
                if obj < best {
                    best = obj
                    start[0usize] = l1
                    start[1usize] = l2
                    start[2usize] = l3
                    start[3usize] = l4
                }
            }
            j += 1usize
        }
        i += 1usize
    }
    var est: [4]f64 = zero
    if method == 5i32 {
        c.kind = 2i32
        let (v, cnt, fail) = run_nm(a, &c, start[2usize..4usize], 10000usize, est[0usize..2usize])
        let valid = tl_conditions(est[0usize], est[1usize], x, t1, t2, tl[0usize..2usize])
        lam[0usize] = tl[0usize]
        lam[1usize] = tl[1usize]
        lam[2usize] = est[0usize]
        lam[3usize] = est[1usize]
        info[0usize] = v
        info[1usize] = f64(cnt)
        info[2usize] = f64(fail)
        if v == pen { info[2usize] = 99.0f64 }
    } else {
        let (v, cnt, fail) = run_nm(a, &c, start[0usize..4usize], 10000usize, lam)
        info[0usize] = v
        info[1usize] = f64(cnt)
        info[2usize] = f64(fail)
    }
    i = 0usize
    while i < 4usize {
        info[3usize + i] = start[i]
        i += 1usize
    }
    ret ok
}
