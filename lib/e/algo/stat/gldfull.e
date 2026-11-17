// R gld, the generalised lambda distribution, whole of its distribution side: qgl, dqgl, pgl, dgl and rgl in the four
// parameterisations (0 fkml / fmkl, 1 rs, 2 fm5, 3 gpd = vsk), the validity check gl.check.lambda, the FKML moments
// (gld.moments), the GPD L-moments (gld.lmoments) and the closed-form GPD fit from L-moments with its standard errors
// (fit.gpd.lmom.given). The distribution function follows the package's C root finder (Newton with bisection, rtsafe).
// A parameter vector is lam[0..4] (lam[0..5] for fm5): fkml and rs (l1, l2, l3, l4); fm5 (l1, .., l5); gpd (alpha, beta, delta, lambda).
// The optimiser-driven fits (starship, fit.fkml, fit.fkml.moments) are in e.algo.stat.gldfit.

use e.algo.rand.r as rng
use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.math.special as sp

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pi_const() -> f64 { ret 3.141592653589793f64 }

// gl.check.lambda
fn check_lambda(param: i32, l: []const f64) -> bool {
    var i = 0usize
    var n = 4usize
    if param == 2i32 { n = 5usize }
    while i < n {
        if l[i] != l[i] { ret false }
        i += 1usize
    }
    let l2 = l[1usize]
    let l3 = l[2usize]
    let l4 = l[3usize]
    if param == 0i32 { ret l2 > 0.0f64 }
    if param == 2i32 { ret l2 > 0.0f64 }
    if param == 3i32 { ret l2 > 0.0f64 && l3 >= 0.0f64 && l3 <= 1.0f64 }
    if l3 * l4 >= 0.0f64 {
        if l3 >= 0.0f64 && l4 >= 0.0f64 {
            if l3 == 0.0f64 && l4 == 0.0f64 { ret true }
            ret l2 > 0.0f64
        }
        ret l2 <= 0.0f64
    }
    if l2 >= 0.0f64 { ret false }
    if l3 > 0.0f64 && l3 < 1.0f64 && l4 < 0.0f64 { ret false }
    if l4 > 0.0f64 && l4 < 1.0f64 && l3 < 0.0f64 { ret false }
    if l3 >= 0.0f64 - 1.0f64 && l3 < 0.0f64 && l4 >= 1.0f64 {
        ret !((math.pow[f64](1.0f64 - l3, 1.0f64 - l3) * math.pow[f64](l4 - 1.0f64, l4 - 1.0f64)) / math.pow[f64](l4 - l3, l4 - l3) > 0.0f64 - l3 / l4)
    }
    if l4 >= 0.0f64 - 1.0f64 && l4 < 0.0f64 && l3 >= 1.0f64 {
        ret !((math.pow[f64](1.0f64 - l4, 1.0f64 - l4) * math.pow[f64](l3 - 1.0f64, l3 - 1.0f64)) / math.pow[f64](l3 - l4, l3 - l4) > 0.0f64 - l4 / l3)
    }
    if l3 <= 0.0f64 - 1.0f64 && l4 >= 1.0f64 { ret l2 < 0.0f64 }
    if l4 <= 0.0f64 - 1.0f64 && l3 >= 1.0f64 { ret l2 < 0.0f64 }
    ret false
}

// qgl: the quantile function; NaN outside [0, 1] (not checked for rs)
fn qgl(param: i32, p: f64, l: []const f64) -> f64 {
    if param == 1i32 { ret l[0usize] + (math.pow[f64](p, l[2usize]) - math.pow[f64](1.0f64 - p, l[3usize])) / l[1usize] }
    if !(p <= 1.0f64 && p >= 0.0f64) { ret nan() }
    if param == 0i32 {
        let l1 = l[0usize]
        let l2 = l[1usize]
        let l3 = l[2usize]
        let l4 = l[3usize]
        if l3 == 0.0f64 {
            if l4 == 0.0f64 { ret l1 + (math.log[f64](p) - math.log[f64](1.0f64 - p)) / l2 }
            ret l1 + (math.log[f64](p) - (math.pow[f64](1.0f64 - p, l4) - 1.0f64) / l4) / l2
        }
        if l4 == 0.0f64 { ret l1 + ((math.pow[f64](p, l3) - 1.0f64) / l3 - math.log[f64](1.0f64 - p)) / l2 }
        ret l1 + ((math.pow[f64](p, l3) - 1.0f64) / l3 - (math.pow[f64](1.0f64 - p, l4) - 1.0f64) / l4) / l2
    }
    if param == 2i32 {
        let l1 = l[0usize]
        let l2 = l[1usize]
        let l3 = l[2usize]
        let l4 = l[3usize]
        let l5 = l[4usize]
        if l3 == 0.0f64 {
            if l4 == 0.0f64 { ret l1 + ((1.0f64 - l5) * math.log[f64](p) - (1.0f64 + l5) * math.log[f64](1.0f64 - p)) / l2 }
            ret l1 + ((1.0f64 - l5) * math.log[f64](p) - (1.0f64 + l5) * (math.pow[f64](1.0f64 - p, l4) - 1.0f64) / l4) / l2
        }
        if l4 == 0.0f64 { ret l1 + ((1.0f64 - l5) * (math.pow[f64](p, l3) - 1.0f64) / l3 - (1.0f64 + l5) * math.log[f64](1.0f64 - p)) / l2 }
        ret l1 + ((1.0f64 - l5) * (math.pow[f64](p, l3) - 1.0f64) / l3 - (1.0f64 + l5) * (math.pow[f64](1.0f64 - p, l4) - 1.0f64) / l4) / l2
    }
    let alpha = l[0usize]
    let beta = l[1usize]
    let delta = l[2usize]
    let lambda = l[3usize]
    if lambda == 0.0f64 { ret alpha + beta * ((1.0f64 - delta) * math.log[f64](p) - delta * math.log[f64](1.0f64 - p)) }
    if delta == 0.0f64 { ret alpha + beta * ((1.0f64 - delta) * (math.pow[f64](p, lambda) - 1.0f64) / lambda) }
    if delta == 1.0f64 { ret alpha + beta * (0.0f64 - delta * (math.pow[f64](1.0f64 - p, lambda) - 1.0f64) / lambda) }
    ret alpha + beta * ((1.0f64 - delta) * (math.pow[f64](p, lambda) - 1.0f64) / lambda - delta * (math.pow[f64](1.0f64 - p, lambda) - 1.0f64) / lambda)
}

// dqgl: the density at the p quantile (0 outside [0, 1] for gpd)
fn dqgl(param: i32, p: f64, l: []const f64) -> f64 {
    if param == 0i32 { ret l[1usize] / (math.pow[f64](p, l[2usize] - 1.0f64) + math.pow[f64](1.0f64 - p, l[3usize] - 1.0f64)) }
    if param == 1i32 { ret l[1usize] / (l[2usize] * math.pow[f64](p, l[2usize] - 1.0f64) + l[3usize] * math.pow[f64](1.0f64 - p, l[3usize] - 1.0f64)) }
    if param == 2i32 { ret l[1usize] / ((1.0f64 - l[4usize]) * math.pow[f64](p, l[2usize] - 1.0f64) + (1.0f64 + l[4usize]) * math.pow[f64](1.0f64 - p, l[3usize] - 1.0f64)) }
    if !(p <= 1.0f64 && p >= 0.0f64) { ret 0.0f64 }
    let beta = l[1usize]
    let delta = l[2usize]
    let lambda = l[3usize]
    if lambda == 0.0f64 { ret p * (1.0f64 - p) / (beta * (delta * p + (1.0f64 - delta) * (1.0f64 - p))) }
    ret 1.0f64 / (beta * ((1.0f64 - delta) * math.pow[f64](p, lambda - 1.0f64) + delta * math.pow[f64](1.0f64 - p, lambda - 1.0f64)))
}

// funcd: Q(u) - x and dQ/du, the root-finder's function in each parameterisation (the C code's)
fn funcd(param: i32, l: []const f64, u: f64, x: f64) -> (f64, f64) {
    if param == 0i32 {
        let a = l[0usize]
        let b = l[1usize]
        let c = l[2usize]
        let d = l[3usize]
        if c == 0.0f64 {
            if d == 0.0f64 { ret (a + (math.log[f64](u) - math.log[f64](1.0f64 - u)) / b - x, (1.0f64 / (u * (1.0f64 - u))) / b) }
            ret (a + (math.log[f64](u) - ((math.pow[f64](1.0f64 - u, d) - 1.0f64) / d)) / b - x, (1.0f64 / u + math.pow[f64](1.0f64 - u, d - 1.0f64)) / b)
        }
        if d == 0.0f64 { ret (a + (((math.pow[f64](u, c) - 1.0f64) / c) - math.log[f64](1.0f64 - u)) / b - x, (math.pow[f64](u, c - 1.0f64) + 1.0f64 / (1.0f64 - u)) / b) }
        ret (((math.pow[f64](u, c) - 1.0f64) / c - (math.pow[f64](1.0f64 - u, d) - 1.0f64) / d) / b + a - x, (math.pow[f64](u, c - 1.0f64) + math.pow[f64](1.0f64 - u, d - 1.0f64)) / b)
    }
    if param == 1i32 {
        let a = l[0usize]
        let b = l[1usize]
        let c = l[2usize]
        let d = l[3usize]
        if c == 0.0f64 {
            if d == 0.0f64 { ret (a - x, 0.0f64) }
            ret (a + (1.0f64 - math.pow[f64](1.0f64 - u, d)) / b - x, d * (math.pow[f64](1.0f64 - u, d - 1.0f64) / b))
        }
        if d == 0.0f64 { ret (a + (math.pow[f64](u, c) - 1.0f64) / b - x, c * math.pow[f64](u, c - 1.0f64) / b) }
        ret ((math.pow[f64](u, c) - math.pow[f64](1.0f64 - u, d)) / b + a - x, (c * math.pow[f64](u, c - 1.0f64) + d * math.pow[f64](1.0f64 - u, d - 1.0f64)) / b)
    }
    if param == 2i32 {
        let a = l[0usize]
        let b = l[1usize]
        let c = l[2usize]
        let d = l[3usize]
        let e = l[4usize]
        if c == 0.0f64 {
            if d == 0.0f64 { ret (a + ((1.0f64 - e) * math.log[f64](u) - (1.0f64 + e) * math.log[f64](1.0f64 - u)) / b - x, ((1.0f64 - e) / u + (1.0f64 + e) / (1.0f64 - u)) / b) }
            ret (a + ((1.0f64 - e) * math.log[f64](u) - ((1.0f64 + e) * (math.pow[f64](1.0f64 - u, d) - 1.0f64) / d)) / b - x, ((1.0f64 - e) / u + (1.0f64 + e) * math.pow[f64](1.0f64 - u, d - 1.0f64)) / b)
        }
        if d == 0.0f64 { ret (a + ((1.0f64 - e) * ((math.pow[f64](u, c) - 1.0f64) / c) - (1.0f64 + e) * math.log[f64](1.0f64 - u)) / b - x, ((1.0f64 - e) * math.pow[f64](u, c - 1.0f64) + (1.0f64 + e) / (1.0f64 - u)) / b) }
        ret (((1.0f64 - e) * (math.pow[f64](u, c) - 1.0f64) / c - (1.0f64 + e) * (math.pow[f64](1.0f64 - u, d) - 1.0f64) / d) / b + a - x, ((1.0f64 - e) * math.pow[f64](u, c - 1.0f64) + (1.0f64 + e) * math.pow[f64](1.0f64 - u, d - 1.0f64)) / b)
    }
    let alpha = l[0usize]
    let beta = l[1usize]
    let delta = l[2usize]
    let lambda = l[3usize]
    if lambda == 0.0f64 { ret (alpha + beta * ((1.0f64 - delta) * math.log[f64](u) - delta * math.log[f64](1.0f64 - u)) - x, beta * ((1.0f64 - delta) / u + delta / (1.0f64 - u))) }
    ret (alpha + beta * ((1.0f64 - delta) * (math.pow[f64](u, lambda) - 1.0f64) / lambda - (delta * (math.pow[f64](1.0f64 - u, lambda) - 1.0f64)) / lambda) - x, beta * ((1.0f64 - delta) * math.pow[f64](u, lambda - 1.0f64) + delta * math.pow[f64](1.0f64 - u, lambda - 1.0f64)))
}

// rtsafe: the root of Q(u) = x on [u1, u2] (Newton, bisecting when it would leave the bracket); NaN when the ends do not bracket it
fn rtsafe(param: i32, l: []const f64, x: f64, u1: f64, u2: f64, xacc: f64, max_it: usize) -> f64 {
    let (fl, dl) = funcd(param, l, u1, x)
    let (fh, dh) = funcd(param, l, u2, x)
    if fl * fh >= 0.0f64 { ret nan() }
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
    let (f0, df0) = funcd(param, l, rts, x)
    var f = f0
    var df = df0
    var j = 1usize
    while j <= max_it {
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
        if math.abs[f64](dx) < xacc { ret rts }
        let (f2, df2) = funcd(param, l, rts, x)
        f = f2
        df = df2
        if f < 0.0f64 {
            xl = rts
        } else {
            xh = rts
        }
        j += 1usize
    }
    ret 0.0f64
}

// pgl for one point: the distribution function, the root of the quantile function; inverse_eps is the accuracy (R default 2.220446049250313e-16)
fn pgl(param: i32, x: f64, l: []const f64, inverse_eps: f64, max_it: usize) -> f64 {
    let min_e = qgl(param, inverse_eps, l)
    let max_e = qgl(param, 1.0f64 - inverse_eps, l)
    if x >= max_e { ret 1.0f64 }
    if x <= min_e { ret 0.0f64 }
    var u1 = 0.0f64
    var u2 = 1.0f64
    if param == 0i32 || param == 2i32 {
        if l[2usize] < 0.0f64 || l[3usize] < 0.0f64 {
            u1 = inverse_eps
            u2 = 1.0f64 - inverse_eps
        }
    }
    if param == 3i32 && l[3usize] < 0.0f64 {
        u1 = inverse_eps
        u2 = 1.0f64 - inverse_eps
    }
    ret rtsafe(param, l, x, u1, u2, inverse_eps, max_it)
}

// dgl for one point: the density (0 outside the support)
fn dgl(param: i32, x: f64, l: []const f64, inverse_eps: f64, max_it: usize) -> f64 {
    let e1 = qgl(param, 0.0f64, l)
    let e2 = qgl(param, 1.0f64, l)
    if !(x <= e2 && x >= e1) { ret 0.0f64 }
    let u = pgl(param, x, l, inverse_eps, max_it)
    ret dqgl(param, u, l)
}

// rgl: one value, the quantile function at the next uniform
fn rgl(param: i32, r: *rng.Rng, l: []const f64) -> f64 {
    let u = rng.unif(r)
    ret qgl(param, u, l)
}

// ---- moments -----------------------------------------------------------------------------------------------------

fn bern_psi(n: usize, x0: f64) -> f64 {
    // polygamma of order n (0, 1 or 2) at x0 > 0: the recurrence up to 20, then the asymptotic series
    var x = x0
    var shift = 0.0f64
    while x < 20.0f64 {
        if n == 0usize { shift = shift - 1.0f64 / x }
        if n == 1usize { shift = shift + 1.0f64 / (x * x) }
        if n == 2usize { shift = shift - 2.0f64 / (x * x * x) }
        x = x + 1.0f64
    }
    let b2 = 1.0f64 / 6.0f64
    let b4 = 0.0f64 - 1.0f64 / 30.0f64
    let b6 = 1.0f64 / 42.0f64
    let b8 = 0.0f64 - 1.0f64 / 30.0f64
    let b10 = 5.0f64 / 66.0f64
    let b12 = 0.0f64 - 691.0f64 / 2730.0f64
    let b14 = 7.0f64 / 6.0f64
    let x2 = x * x
    if n == 0usize {
        let s = (b2 / 2.0f64 + (b4 / 4.0f64 + (b6 / 6.0f64 + (b8 / 8.0f64 + (b10 / 10.0f64 + (b12 / 12.0f64 + b14 / 14.0f64 / x2) / x2) / x2) / x2) / x2) / x2) / x2
        ret math.log[f64](x) - 0.5f64 / x - s + shift
    }
    if n == 1usize {
        let s = (b2 + (b4 + (b6 + (b8 + (b10 + (b12 + b14 / x2) / x2) / x2) / x2) / x2) / x2) / (x2 * x)
        ret 1.0f64 / x + 0.5f64 / x2 + s + shift
    }
    let s = (b2 * 3.0f64 + (b4 * 5.0f64 + (b6 * 7.0f64 + (b8 * 9.0f64 + (b10 * 11.0f64 + (b12 * 13.0f64 + b14 * 15.0f64 / x2) / x2) / x2) / x2) / x2) / x2) / (x2 * x2)
    ret 0.0f64 - 1.0f64 / x2 - 1.0f64 / (x2 * x) - s + shift
}

fn rbeta_fn(a: f64, b: f64) -> f64 {
    if a + b < 171.6f64 { ret (1.0f64 / nm.gammafn(a + b)) * nm.gammafn(a) * nm.gammafn(b) }
    ret math.exp[f64](nb.lbeta(a, b))
}

fn m3_one_zero(k: f64, lj: f64) -> f64 {
    let sg = math.pow[f64](0.0f64 - 1.0f64, k)
    let eul = 0.0f64 - bern_psi(0usize, 1.0f64)
    let d1 = eul + bern_psi(0usize, lj + 2.0f64)
    let d2 = eul + bern_psi(0usize, 2.0f64 * lj + 2.0f64)
    ret 3.0f64 * sg * (12.0f64 * math.pow[f64](lj, 5.0f64) + 10.0f64 * math.pow[f64](lj, 4.0f64) - 4.0f64 * math.pow[f64](lj, 3.0f64) - lj * lj + 4.0f64 * lj + 1.0f64) / (lj * lj * (lj + 1.0f64) * (2.0f64 * lj + 1.0f64) * (3.0f64 * lj + 1.0f64)) - 6.0f64 * sg * d1 / (lj * lj * (lj + 1.0f64)) + 3.0f64 * sg * d2 / (lj * lj * (2.0f64 * lj + 1.0f64)) + 3.0f64 * sg * (pi_const() * pi_const() / 6.0f64 + d1 * d1 - bern_psi(1usize, lj + 2.0f64)) / (lj * (lj + 1.0f64))
}

fn m4_one_zero(lj: f64) -> f64 {
    let zeta3 = 1.20205690315959f64
    let eul = 0.0f64 - bern_psi(0usize, 1.0f64)
    let p2 = pi_const() * pi_const()
    let d1 = eul + bern_psi(0usize, lj + 2.0f64)
    let d2 = eul + bern_psi(0usize, 2.0f64 * lj + 2.0f64)
    let d3 = eul + bern_psi(0usize, 3.0f64 * lj + 2.0f64)
    ret 4.0f64 * (144.0f64 * math.pow[f64](lj, 7.0f64) + 156.0f64 * math.pow[f64](lj, 6.0f64) - 18.0f64 * math.pow[f64](lj, 5.0f64) - 24.0f64 * math.pow[f64](lj, 4.0f64) + 7.0f64 * math.pow[f64](lj, 3.0f64) - 11.0f64 * lj * lj - 7.0f64 * lj - 1.0f64) / (math.pow[f64](lj, 3.0f64) * (lj + 1.0f64) * (2.0f64 * lj + 1.0f64) * (3.0f64 * lj + 1.0f64) * (4.0f64 * lj + 1.0f64)) + 12.0f64 * d1 / (math.pow[f64](lj, 3.0f64) * (lj + 1.0f64)) - 12.0f64 * d2 / (math.pow[f64](lj, 3.0f64) * (2.0f64 * lj + 1.0f64)) + 4.0f64 * d3 / (math.pow[f64](lj, 3.0f64) * (3.0f64 * lj + 1.0f64)) - 12.0f64 * (p2 / 6.0f64 + d1 * d1 - bern_psi(1usize, lj + 2.0f64)) / (lj * lj * (lj + 1.0f64)) + 6.0f64 * (p2 / 6.0f64 + d2 * d2 - bern_psi(1usize, 2.0f64 * lj + 2.0f64)) / (lj * lj * (2.0f64 * lj + 1.0f64)) + 4.0f64 * (3.0f64 * (p2 / 6.0f64 - bern_psi(1usize, lj + 2.0f64)) * d1 + d1 * d1 * d1 + 2.0f64 * zeta3 + bern_psi(2usize, lj + 2.0f64)) / (lj * (lj + 1.0f64))
}

fn vk_nonzero(k: usize, l3: f64, l4: f64) -> f64 {
    var ret_v = 0.0f64
    var sign = 1.0f64
    var j = 0usize
    while j <= k {
        let kj = f64(k - j)
        ret_v = ret_v + sign * sp.choose(f64(k), f64(j)) * rbeta_fn(l3 * kj + 1.0f64, l4 * f64(j) + 1.0f64) / (math.pow[f64](l3, kj) * math.pow[f64](l4, f64(j)))
        sign = 0.0f64 - sign
        j += 1usize
    }
    ret ret_v
}

// vk(k, l3, l4): the k-th moment of the standardised quantile function
fn vk(k: usize, l3: f64, l4: f64) -> f64 {
    let p2 = pi_const() * pi_const()
    if l3 == 0.0f64 {
        if l4 == 0.0f64 {
            if k == 1usize { ret 0.0f64 }
            if k == 2usize { ret p2 / 3.0f64 }
            if k == 3usize { ret 0.0f64 }
            ret 7.0f64 * p2 * p2 / 15.0f64
        }
        if k == 1usize { ret (0.0f64 - l4) / (l4 + 1.0f64) }
        if k == 2usize {
            let e1 = 2.0f64 * (2.0f64 * l4 * l4 * l4 + l4 * l4 - l4 - 1.0f64) / (l4 * (l4 + 1.0f64) * (2.0f64 * l4 + 1.0f64))
            let e2 = 2.0f64 * (0.0f64 - bern_psi(0usize, 1.0f64) + bern_psi(0usize, l4 + 2.0f64)) / (l4 * (l4 + 1.0f64))
            ret e1 + e2
        }
        if k == 3usize { ret m3_one_zero(3.0f64, l4) }
        ret m4_one_zero(l4)
    }
    if l4 == 0.0f64 {
        if k == 1usize { ret l3 / (l3 + 1.0f64) }
        if k == 2usize {
            let eul = 0.0f64 - bern_psi(0usize, 1.0f64)
            ret 2.0f64 * (2.0f64 * l3 * l3 * l3 + l3 * l3 - l3 - 1.0f64) / (l3 * (l3 + 1.0f64) * (2.0f64 * l3 + 1.0f64)) + 2.0f64 * (eul + bern_psi(0usize, l3 + 2.0f64)) / (l3 * (l3 + 1.0f64))
        }
        if k == 3usize { ret m3_one_zero(4.0f64, l3) }
        ret m4_one_zero(l3)
    }
    ret vk_nonzero(k, l3, l4)
}

// gld.moments(par, "fkml", ratios): out = (mean, variance, a3, a4) (or the 3rd and 4th moments when ratios is false); NaN where undefined
fn fkml_moments(par: []const f64, ratios: bool, out: []f64) {
    out[0usize] = nan()
    out[1usize] = nan()
    out[2usize] = nan()
    out[3usize] = nan()
    if par[3usize] <= 0.0f64 - 1.0f64 || par[2usize] <= 0.0f64 - 1.0f64 { ret }
    var calc2 = true
    var calc3 = true
    var calc4 = true
    if par[3usize] <= 0.0f64 - 0.5f64 || par[2usize] <= 0.0f64 - 0.5f64 {
        calc2 = false
        calc3 = false
        calc4 = false
    }
    if par[3usize] <= 0.0f64 - 1.0f64 / 3.0f64 || par[2usize] <= 0.0f64 - 1.0f64 / 3.0f64 {
        calc3 = false
        calc4 = false
    }
    if par[3usize] <= 0.0f64 - 0.25f64 || par[2usize] <= 0.0f64 - 0.25f64 { calc4 = false }
    let v1 = vk(1usize, par[2usize], par[3usize])
    var v2 = nan()
    var v3 = nan()
    var v4 = nan()
    if calc2 || calc3 { v2 = vk(2usize, par[2usize], par[3usize]) }
    if calc3 { v3 = vk(3usize, par[2usize], par[3usize]) }
    if calc4 { v4 = vk(4usize, par[2usize], par[3usize]) }
    var a3 = nan()
    var a4 = nan()
    if ratios && calc3 {
        let sl = v2 - v1 * v1
        a3 = (v3 - 3.0f64 * v1 * v2 + 2.0f64 * v1 * v1 * v1) / math.pow[f64](sl, 1.5f64)
        if calc4 { a4 = (v4 - 4.0f64 * v1 * v3 + 6.0f64 * v1 * v1 * v2 - 3.0f64 * v1 * v1 * v1 * v1) / (sl * sl) }
    } else {
        if calc3 { a3 = v3 - 3.0f64 * v1 * v2 + 2.0f64 * v1 * v1 * v1 }
        if calc4 { a4 = v4 - 4.0f64 * v1 * v3 + 6.0f64 * v1 * v1 * v2 - 3.0f64 * v1 * v1 * v1 * v1 }
    }
    var sigmasq = nan()
    if calc2 { sigmasq = (v2 - v1 * v1) / (par[1usize] * par[1usize]) }
    var mean = par[0usize] + v1 / par[1usize]
    if !(par[2usize] == 0.0f64 || par[3usize] == 0.0f64 || par[2usize] == par[3usize]) { mean = par[0usize] + (v1 - 1.0f64 / par[2usize] + 1.0f64 / par[3usize]) / par[1usize] }
    out[0usize] = mean
    out[1usize] = sigmasq
    out[2usize] = a3
    out[3usize] = a4
}

// gld.lmoments(pars, order, ratios, type = "GPD") for one order (1 .. any); high is whether any requested order exceeds 4 (the package then uses the gamma formula for every order above 2)
fn gpd_lmoment(pars: []const f64, order: usize, ratios: bool, high: bool) -> f64 {
    let alpha = pars[0usize]
    let beta = pars[1usize]
    let delta = pars[2usize]
    let lambda = pars[3usize]
    if lambda <= 0.0f64 - 1.0f64 { ret 1.0f64 / 0.0f64 }
    let l1 = alpha + (beta * (2.0f64 * delta - 1.0f64)) / (lambda + 1.0f64)
    let l2 = beta / ((lambda + 1.0f64) * (lambda + 2.0f64))
    if order == 1usize { ret l1 }
    if order == 2usize { ret l2 }
    let ord = f64(order)
    if order > 4usize || (high && order > 2usize) {
        if ratios { ret (nm.gammafn(3.0f64 + lambda) * nm.gammafn(ord - 1.0f64 - lambda)) / (nm.gammafn(1.0f64 - lambda) * nm.gammafn(ord + 1.0f64 + lambda)) }
        ret (nm.gammafn(1.0f64 + lambda) * nm.gammafn(ord - 1.0f64 - lambda)) / (nm.gammafn(1.0f64 - lambda) * nm.gammafn(ord + 1.0f64 + lambda))
    }
    let t3 = ((2.0f64 * delta - 1.0f64) * (1.0f64 - lambda)) / (lambda + 3.0f64)
    let t4 = ((lambda - 1.0f64) * (lambda - 2.0f64)) / ((lambda + 3.0f64) * (lambda + 4.0f64))
    if order == 3usize {
        if ratios { ret t3 }
        ret t3 * l2
    }
    if ratios { ret t4 }
    ret t4 * l2
}

// ---- fit.gpd.lmom.given ------------------------------------------------------------------------------------------

fn nu(i: usize, x: f64) -> f64 {
    let l = x
    if i == 1usize { ret (2.0f64 * l + 1.0f64) * (2.0f64 * l + 3.0f64) * (2.0f64 * l + 5.0f64) * (2.0f64 * l + 7.0f64) * (l * l + 2.0f64 * l - 5.0f64) * (l * l + 2.0f64 * l - 5.0f64) }
    if i == 2usize { ret 4.0f64 * pw(l, 10.0f64) + 32.0f64 * pw(l, 9.0f64) + 51.0f64 * pw(l, 8.0f64) - 104.0f64 * pw(l, 7.0f64) - 43.0f64 * pw(l, 6.0f64) + 735.0f64 * pw(l, 5.0f64) + 995.0f64 * pw(l, 4.0f64) + 6418.0f64 * pw(l, 3.0f64) + 22611.0f64 * l * l + 27911.0f64 * l + 13966.0f64 }
    if i == 3usize { ret (l + 3.0f64) * (pw(l, 13.0f64) + 17.0f64 * pw(l, 12.0f64) + 99.0f64 * pw(l, 11.0f64) + 255.0f64 * pw(l, 10.0f64) + 667.0f64 * pw(l, 9.0f64) + 3595.0f64 * pw(l, 8.0f64) + 8745.0f64 * pw(l, 7.0f64) - 17879.0f64 * pw(l, 6.0f64) - 149808.0f64 * pw(l, 5.0f64) - 312756.0f64 * pw(l, 4.0f64) - 103684.0f64 * pw(l, 3.0f64) + 432056.0f64 * l * l + 215458.0f64 * l - 367080.0f64) }
    if i == 4usize { ret (l + 4.0f64) * (l + 4.0f64) * (l * l - 2.0f64 * l - 11.0f64) * (l * l - 2.0f64 * l - 11.0f64) }
    if i == 5usize { ret pw(l, 8.0f64) + 8.0f64 * pw(l, 7.0f64) + 12.0f64 * pw(l, 6.0f64) - 84.0f64 * pw(l, 5.0f64) - 405.0f64 * pw(l, 4.0f64) - 492.0f64 * pw(l, 3.0f64) + 548.0f64 * l * l + 964.0f64 * l - 840.0f64 }
    if i == 6usize { ret 2.0f64 / (l * (l + 1.0f64) * (l + 2.0f64)) }
    if i == 7usize { ret 4.0f64 * pw(l, 15.0f64) + 52.0f64 * pw(l, 14.0f64) + 243.0f64 * pw(l, 13.0f64) + 167.0f64 * pw(l, 12.0f64) - 2343.0f64 * pw(l, 11.0f64) - 3244.0f64 * pw(l, 10.0f64) + 27697.0f64 * pw(l, 9.0f64) + 74517.0f64 * pw(l, 8.0f64) + 8739.0f64 * pw(l, 7.0f64) + 244921.0f64 * pw(l, 6.0f64) + 1532136.0f64 * pw(l, 5.0f64) + 1771024.0f64 * pw(l, 4.0f64) - 923048.0f64 * pw(l, 3.0f64) - 1541641.0f64 * l * l + 686268.0f64 * l + 550620.0f64 }
    if i == 8usize { ret 4.0f64 * pw(l, 9.0f64) + 32.0f64 * pw(l, 8.0f64) + 35.0f64 * pw(l, 7.0f64) - 216.0f64 * pw(l, 6.0f64) - 159.0f64 * pw(l, 5.0f64) + 1053.0f64 * pw(l, 4.0f64) + 350.0f64 * pw(l, 3.0f64) - 1451.0f64 * l * l + 148.0f64 * l + 420.0f64 }
    if i == 9usize { ret 8.0f64 * pw(l, 10.0f64) + 124.0f64 * pw(l, 9.0f64) + 822.0f64 * pw(l, 8.0f64) + 3133.0f64 * pw(l, 7.0f64) + 7894.0f64 * pw(l, 6.0f64) + 14519.0f64 * pw(l, 5.0f64) + 22236.0f64 * pw(l, 4.0f64) + 35026.0f64 * pw(l, 3.0f64) + 53894.0f64 * l * l + 54316.0f64 * l + 22696.0f64 }
    if i == 10usize { ret 4.0f64 * pw(l, 14.0f64) + 84.0f64 * pw(l, 13.0f64) + 757.0f64 * pw(l, 12.0f64) + 3614.0f64 * pw(l, 11.0f64) + 7369.0f64 * pw(l, 10.0f64) - 18988.0f64 * pw(l, 9.0f64) - 199465.0f64 * pw(l, 8.0f64) - 747082.0f64 * pw(l, 7.0f64) - 1606417.0f64 * pw(l, 6.0f64) - 1893644.0f64 * pw(l, 5.0f64) - 580072.0f64 * pw(l, 4.0f64) + 1264048.0f64 * pw(l, 3.0f64) + 1118160.0f64 * l * l - 396656.0f64 * l - 567840.0f64 }
    if i == 11usize { ret 8.0f64 * pw(l, 15.0f64) + 172.0f64 * pw(l, 14.0f64) + 1742.0f64 * pw(l, 13.0f64) + 10633.0f64 * pw(l, 12.0f64) + 39856.0f64 * pw(l, 11.0f64) + 79701.0f64 * pw(l, 10.0f64) + 31792.0f64 * pw(l, 9.0f64) - 125933.0f64 * pw(l, 8.0f64) + 172824.0f64 * pw(l, 7.0f64) + 1449179.0f64 * pw(l, 6.0f64) + 2083778.0f64 * pw(l, 5.0f64) + 200988.0f64 * pw(l, 4.0f64) - 1588440.0f64 * pw(l, 3.0f64) - 552332.0f64 * l * l + 624208.0f64 * l + 283920.0f64 }
    if i == 12usize { ret 18.0f64 * (l + 1.0f64) * (l + 3.0f64) * (2.0f64 * l * l + 3.0f64 * l + 2.0f64) }
    if i == 13usize { ret 2.0f64 * pw(l, 10.0f64) + 29.0f64 * pw(l, 9.0f64) + 149.0f64 * pw(l, 8.0f64) + 253.0f64 * pw(l, 7.0f64) - 575.0f64 * pw(l, 6.0f64) - 3857.0f64 * pw(l, 5.0f64) - 8701.0f64 * pw(l, 4.0f64) - 6229.0f64 * pw(l, 3.0f64) + 11573.0f64 * l * l + 14412.0f64 * l - 15120.0f64 }
    if i == 14usize { ret 29.0f64 * pw(l, 7.0f64) + 206.0f64 * pw(l, 6.0f64) - 119.0f64 * pw(l, 5.0f64) - 3822.0f64 * pw(l, 4.0f64) - 7189.0f64 * pw(l, 3.0f64) + 5506.0f64 * l * l + 13279.0f64 * l - 10290.0f64 }
    if i == 15usize { ret 4.0f64 * pw(l, 11.0f64) + 28.0f64 * pw(l, 10.0f64) - 49.0f64 * pw(l, 9.0f64) - 699.0f64 * pw(l, 8.0f64) - 1280.0f64 * pw(l, 7.0f64) - 1601.0f64 * pw(l, 6.0f64) - 11409.0f64 * pw(l, 5.0f64) - 22185.0f64 * pw(l, 4.0f64) + 5456.0f64 * pw(l, 3.0f64) + 23485.0f64 * l * l - 6654.0f64 * l - 7560.0f64 }
    if i == 16usize { ret 8.0f64 * pw(l, 13.0f64) + 44.0f64 * pw(l, 12.0f64) - 282.0f64 * pw(l, 11.0f64) - 1699.0f64 * pw(l, 10.0f64) + 4418.0f64 * pw(l, 9.0f64) + 32076.0f64 * pw(l, 8.0f64) - 1094.0f64 * pw(l, 7.0f64) - 164198.0f64 * pw(l, 6.0f64) + 24618.0f64 * pw(l, 5.0f64) + 557596.0f64 * pw(l, 4.0f64) - 7256.0f64 * pw(l, 3.0f64) - 643599.0f64 * l * l + 100548.0f64 * l + 185220.0f64 }
    ret 4.0f64 * pw(l, 5.0f64) + 4.0f64 * pw(l, 4.0f64) - 17.0f64 * pw(l, 3.0f64) + 43.0f64 * l * l - 14.0f64 * l + 16.0f64
}

fn pw(x: f64, y: f64) -> f64 { ret math.pow[f64](x, y) }

// BetaLambdaLambda(lambda)
fn beta_ll(l: f64) -> f64 {
    if l == 0.0f64 - 0.5f64 { ret 0.0f64 }
    if l <= 0.0f64 && l == math.floor[f64](l) { ret nan() }
    let g = nm.gammafn(l + 1.0f64)
    ret (2.0f64 * g * g) / (l * nm.gammafn(2.0f64 * l + 1.0f64))
}

// the standard errors of a GPD fit by L-moments (alpha, beta, delta, lambda) at sample size n; needs lambda > -1/2
fn gpd_se(alpha: f64, beta: f64, delta: f64, l: f64, n: f64, out: []f64) {
    let om = delta * (1.0f64 - delta)
    let bl = beta_ll(l)
    out[0usize] = beta * math.sqrt[f64](1.0f64 / (n * (l - 1.0f64) * (l - 1.0f64) * (l + 2.0f64) * nu(1usize, l))) * math.sqrt[f64](nu(2usize, l) - (om / (l * (l + 1.0f64))) * ((nu(3usize, l) / 4.0f64 - om * nu(4usize, l) * nu(5usize, l)) * bl + nu(6usize, l) * (nu(7usize, l) - 4.0f64 * om * nu(4usize, l) * nu(8usize, l))))
    out[1usize] = beta * math.sqrt[f64](1.0f64 / (n * (l + 2.0f64) * nu(1usize, l)) * (nu(9usize, l) - (om / (l * (l + 1.0f64))) * (nu(10usize, l) / 4.0f64 * bl + nu(6usize, l) * nu(11usize, l))))
    out[2usize] = math.sqrt[f64](((l + 1.0f64) * (l + 2.0f64) * (l + 3.0f64)) / (n * (l - 1.0f64) * (l - 1.0f64) * nu(1usize, l))) * math.sqrt[f64](nu(12usize, l) - om / l * (1.0f64 / 4.0f64 * (nu(13usize, l) - 12.0f64 * om * nu(14usize, l)) * bl - nu(6usize, l) / (l + 3.0f64) * (3.0f64 * nu(15usize, l) + om * nu(16usize, l))))
    out[3usize] = math.sqrt[f64](((l + 1.0f64) * (l + 2.0f64) * (l + 3.0f64) * (l + 3.0f64) * (l + 4.0f64) * (l + 4.0f64)) / (n * nu(1usize, l)) * (nu(17usize, l) - om / l * (1.0f64 / 4.0f64 * nu(5usize, l) * bl + nu(6usize, l) * nu(8usize, l))))
}

// fit.gpd.lmom.given(c(l1, l2, t3, t4)): out[0..4] region A estimate, out[4..8] region B estimate, se[0..4] / se[4..8] their standard errors at sample size n
// (NaN when not defined, as when lambda <= -1/2, and NaN for lambda itself in the lambda = 0 case). status: 0 fine, 1 impossible L-moments (nothing computed).
// lambda_zero_eps is R's LambdaZeroEpsilon (1e-15).
fn fit_gpd_lmom_given(lm: []const f64, n: f64, lambda_zero_eps: f64, out: []f64, se: []f64) -> i32 {
    var i = 0usize
    while i < 8usize {
        out[i] = nan()
        se[i] = nan()
        i += 1usize
    }
    let t4 = lm[3usize]
    let t3 = lm[2usize]
    let l2 = lm[1usize]
    let l1 = lm[0usize]
    if math.abs[f64](t3) >= 1.0f64 { ret 1i32 }
    if (5.0f64 * t3 * t3 - 1.0f64) / 4.0f64 > t4 { ret 1i32 }
    if t4 < 0.0f64 - 0.25f64 { ret 1i32 }
    if t4 >= 1.0f64 { ret 1i32 }
    if t4 * t4 + 98.0f64 * t4 + 1.0f64 < 0.0f64 { ret 1i32 }
    let el1 = 3.0f64 + 7.0f64 * t4
    let el2 = math.sqrt[f64](t4 * t4 + 98.0f64 * t4 + 1.0f64)
    let denom = 2.0f64 * (1.0f64 - t4)
    var side = 0usize
    while side < 2usize {
        var lam = (el1 - el2) / denom
        if side == 1usize { lam = (el1 + el2) / denom }
        let del = 0.5f64 * (1.0f64 - (t3 * (lam + 3.0f64)) / (lam - 1.0f64))
        let bet = l2 * (lam + 1.0f64) * (lam + 2.0f64)
        let alp = l1 + (bet * (1.0f64 - 2.0f64 * del)) / (lam + 1.0f64)
        var is_sld = false
        if side == 0usize && math.abs[f64](lam) < lambda_zero_eps {
            is_sld = true
            lam = 0.0f64
        }
        var est: [4]f64 = zero
        est[0usize] = alp
        est[1usize] = bet
        est[2usize] = del
        est[3usize] = lam
        if check_lambda(3i32, est[0usize..4usize]) {
            var k = 0usize
            while k < 4usize {
                out[side * 4usize + k] = est[k]
                k += 1usize
            }
            if n == n {
                var s: [4]f64 = zero
                if is_sld || (side == 1usize && lam == 0.0f64) {
                    let omega = del * (1.0f64 - del)
                    let p2 = pi_const() * pi_const()
                    s[0usize] = bet * math.sqrt[f64]((57.0f64 + (125.0f64 * p2 - 1308.0f64) * omega) / (15.0f64 * n))
                    s[1usize] = bet * math.sqrt[f64](4.0f64 / (3.0f64 * n) * (1.0f64 - (p2 - 8.0f64) * omega))
                    s[2usize] = math.sqrt[f64]((8.0f64 - (397.0f64 + 160.0f64 * omega - 20.0f64 * p2 * (omega + 2.0f64)) * omega) / (15.0f64 * n))
                    s[3usize] = nan()
                    k = 0usize
                    while k < 4usize {
                        se[side * 4usize + k] = s[k]
                        k += 1usize
                    }
                } else if lam > 0.0f64 - 0.5f64 {
                    gpd_se(alp, bet, del, lam, n, s[0usize..4usize])
                    k = 0usize
                    while k < 4usize {
                        se[side * 4usize + k] = s[k]
                        k += 1usize
                    }
                }
            }
        }
        side += 1usize
    }
    ret 0i32
}
