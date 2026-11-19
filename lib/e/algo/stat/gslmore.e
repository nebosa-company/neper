// R gsl, the rest of the exported special functions that have a closed form or a stable recurrence over what gslfns and gslcoulomb hold: the integer-order and scaled Bessel
// functions and their array forms, spherical Bessel functions, the Legendre arrays with the four normalisations and their first and second derivatives, hydrogenic
// radial functions, 2F1 with conjugate parameters, small helpers (pow_int, fact, lngamma_sgn, lnpoch_sgn, erf_Z, erf_Q, ...).

use e.math
use e.math.special as sp
use e.math.dist as dist
use e.mem
use e.math.quadpack as qp
use e.algo.stat.gslfns as gs
use e.algo.stat.gslcoulomb as gc

fn mpi() -> f64 { ret 3.141592653589793238462643383279f64 }
fn ab(x: f64) -> f64 { ret math.abs[f64](x) }

// e^x K_nu(x), x > 0: the trapezoid rule on integral_0^inf exp(-x (cosh t - 1)) cosh(nu t) dt with a step that follows the width of the integrand
fn kn_sc(nu: f64, x: f64) -> f64 {
    var h = 0.1f64
    if 0.3f64 / math.sqrt[f64](x) < h { h = 0.3f64 / math.sqrt[f64](x) }
    if 0.5f64 / (1.0f64 + ab(nu)) < h { h = 0.5f64 / (1.0f64 + ab(nu)) }
    var s = 0.5f64
    var k = 1usize
    while k < 400000usize {
        let t = h * f64(k)
        let ex = x * (math.exp[f64](t) + math.exp[f64](0.0f64 - t) - 2.0f64) / 2.0f64 - ab(nu) * t
        if ex > 70.0f64 { break }
        s += math.exp[f64](0.0f64 - x * (math.exp[f64](t) + math.exp[f64](0.0f64 - t) - 2.0f64) / 2.0f64) * (math.exp[f64](nu * t) + math.exp[f64](0.0f64 - nu * t)) / 2.0f64
        k += 1usize
    }
    ret s * h
}

// e^(-x) I_nu(x), x > 0, nu >= 0: the power series (every term positive) or Hankel's expansion
fn in_sc(nu: f64, x: f64) -> f64 {
    if x == 0.0f64 {
        if nu == 0.0f64 { ret 1.0f64 }
        ret 0.0f64
    }
    if x > 30.0f64 && 4.0f64 * nu * nu < x / 2.0f64 || x > 600.0f64 {
        var term = 1.0f64
        var sum = 1.0f64
        let mu = 4.0f64 * nu * nu
        var k = 1usize
        while k < 80usize {
            let kk = 2.0f64 * f64(k) - 1.0f64
            let nt = term * (0.0f64 - (mu - kk * kk)) / (8.0f64 * f64(k) * x)
            if ab(nt) > ab(term) { break }
            term = nt
            sum += term
            if ab(term) < 1.0e-18f64 { break }
            k += 1usize
        }
        ret sum / math.sqrt[f64](2.0f64 * mpi() * x)
    }
    let hx = x / 2.0f64
    var t = math.exp[f64](nu * math.log[f64](hx) - sp.lgamma(nu + 1.0f64) - x)
    var s = t
    var k = 0usize
    while k < 3000usize {
        t = t * hx * hx / (f64(k + 1usize) * (f64(k + 1usize) + nu))
        s += t
        if t < s * 1.0e-18f64 && f64(k) > hx { break }
        k += 1usize
    }
    ret s
}

fn bessel_in(n: i64, x: f64) -> f64 {
    var nn = n
    if nn < 0i64 { nn = 0i64 - nn }
    var v = in_sc(f64(nn), ab(x)) * math.exp[f64](ab(x))
    if x < 0.0f64 && nn % 2i64 == 1i64 { v = 0.0f64 - v }
    ret v
}

fn bessel_kn(n: i64, x: f64) -> f64 { ret kn_sc(f64(n), x) * math.exp[f64](0.0f64 - x) }

// J_nu(x) for real nu >= 0, x > 0: Bessel's integral, the second part for non-integer nu, by adaptive quadrature (e.math.quadpack)
type Jc = struct { nu: f64, x: f64, kind: usize }

fn jc_fn(c: *Jc, t: f64) -> f64 {
    if c.kind == 0usize { ret math.cos[f64](c.nu * t - c.x * math.sin[f64](t)) }
    ret math.exp[f64](0.0f64 - c.x * (math.exp[f64](t) - math.exp[f64](0.0f64 - t)) / 2.0f64 - c.nu * t)
}

fn bessel_jnu_q(a: *mem.Arena, nu: f64, x: f64) -> f64 {
    var c: Jc = zero
    c.nu = nu
    c.x = x
    c.kind = 0usize
    let (r1, _e1) = qp_qags(a, &c, 0.0f64, mpi())
    var v = r1 / mpi()
    let fr = nu - math.floor[f64](nu)
    if fr != 0.0f64 {
        c.kind = 1usize
        let (r2, _e2) = qp_qagi(a, &c)
        v -= math.sin[f64](nu * mpi()) / mpi() * r2
    }
    ret v
}

fn qp_qags(a: *mem.Arena, c: *Jc, lo: f64, hi: f64) -> (f64, i64) {
    let (r, e) = qp.qags[Jc](a, c, jc_fn, lo, hi, 0.0f64, 0.0000000000001f64, 400usize)
    if e != ok { ret (0.0f64 / 0.0f64, 1i64) }
    ret (r.result, 0i64)
}

fn qp_qagi(a: *mem.Arena, c: *Jc) -> (f64, i64) {
    let (r, e) = qp.qagi[Jc](a, c, jc_fn, 0.0f64, 1i64, 0.0f64, 0.0000000000001f64, 400usize)
    if e != ok { ret (0.0f64 / 0.0f64, 1i64) }
    ret (r.result, 0i64)
}

// spherical Bessel j_l(x), l = 0..=lmax into out, x > 0: the series for small x, Miller's backward recurrence above
fn sph_j_array(lmax: usize, x: f64, out: []f64) {
    if x <= 2.0f64 {
        var l = 0usize
        while l <= lmax {
            // x^l / (2l+1)!! sum (-x^2/2)^k / (k! (2l+3)(2l+5)...(2l+2k+1))
            var dfac = 1.0f64
            var i = 1usize
            while i <= l {
                dfac *= f64(2usize * i + 1usize)
                i += 1usize
            }
            var term = math.pow[f64](x, f64(l)) / dfac
            var s = term
            var k = 1usize
            while k < 60usize {
                term = term * (0.0f64 - x * x / 2.0f64) / (f64(k) * f64(2usize * l + 2usize * k + 1usize))
                s += term
                if ab(term) < 1.0e-19f64 * ab(s) { break }
                k += 1usize
            }
            out[l] = s
            l += 1usize
        }
        ret
    }
    let start = lmax + 40usize + usize(x)
    var up = 0.0f64
    var cur = 1.0e-250f64
    var l = start
    var j0u = 0.0f64
    var j1u = 0.0f64
    while l >= 1usize {
        let down = f64(2usize * l + 1usize) / x * cur - up
        up = cur
        cur = down
        let ll = l - 1usize
        if ll <= lmax { out[ll] = cur }
        if ll == 1usize { j1u = cur }
        if ll == 0usize { j0u = cur }
        l -= 1usize
    }
    let sx = math.sin[f64](x)
    let cx = math.cos[f64](x)
    let t0 = sx / x
    let t1 = sx / (x * x) - cx / x
    var scale = t0 / j0u
    if ab(t1) > ab(t0) { scale = t1 / j1u }
    var i = 0usize
    while i <= lmax {
        out[i] = out[i] * scale
        i += 1usize
    }
}

fn sph_y_array(lmax: usize, x: f64, out: []f64) {
    let sx = math.sin[f64](x)
    let cx = math.cos[f64](x)
    out[0usize] = 0.0f64 - cx / x
    if lmax >= 1usize { out[1usize] = 0.0f64 - cx / (x * x) - sx / x }
    var l = 2usize
    while l <= lmax {
        out[l] = f64(2usize * l - 1usize) / x * out[l - 1usize] - out[l - 2usize]
        l += 1usize
    }
}

// e^(-x) i_l(x) and e^x k_l(x), the scaled modified spherical Bessel functions (GSL: i_l = sqrt(pi / 2x) I_{l+1/2}, k_l scaled = e^x sqrt(pi / 2x) K_{l+1/2})
fn sph_i_scaled(l: usize, x: f64) -> f64 { ret math.sqrt[f64](mpi() / (2.0f64 * x)) * in_sc(f64(l) + 0.5f64, x) }

fn sph_k_scaled(l: usize, x: f64) -> f64 { ret math.sqrt[f64](mpi() / (2.0f64 * x)) * kn_sc(f64(l) + 0.5f64, x) }

// ---- Legendre arrays: out index l * (lmax + 1) + m (row l, column m) as R lays them out. norm: 1 none, 2 Schmidt, 3 spherical harmonic, 4 full; csphase -1 includes (-1)^m
fn leg_norm(norm: usize, l: usize, m: usize) -> f64 {
    if norm == 1usize { ret 1.0f64 }
    // (l - m)! / (l + m)!
    var r = 1.0f64
    var i = l - m + 1usize
    while i <= l + m {
        r = r / f64(i)
        i += 1usize
    }
    if norm == 2usize {
        if m == 0usize { ret 1.0f64 }
        ret math.sqrt[f64](2.0f64 * r)
    }
    if norm == 3usize { ret math.sqrt[f64]((2.0f64 * f64(l) + 1.0f64) / (4.0f64 * mpi()) * r) }
    ret math.sqrt[f64]((f64(l) + 0.5f64) * r)
}

// unnormalised P_l^m(x), without the Condon-Shortley phase, for -1 < x < 1, l >= m
fn leg_plm(l: usize, m: usize, x: f64) -> f64 {
    var pmm = 1.0f64
    let s = math.sqrt[f64](1.0f64 - x * x)
    var i = 1usize
    while i <= m {
        pmm = pmm * f64(2usize * i - 1usize) * s
        i += 1usize
    }
    if l == m { ret pmm }
    var pm1 = x * f64(2usize * m + 1usize) * pmm
    if l == m + 1usize { ret pm1 }
    var pm2 = pmm
    var ll = m + 2usize
    while ll <= l {
        let p = (x * f64(2usize * ll - 1usize) * pm1 - f64(ll + m - 1usize) * pm2) / f64(ll - m)
        pm2 = pm1
        pm1 = p
        ll += 1usize
    }
    ret pm1
}

// kind 0 P, 1 dP/dx, 2 dP/dtheta (x = cos theta), 3 d2P/dx2, 4 d2P/dtheta2 of the normalised function
fn leg_value(kind: usize, norm: usize, csphase: f64, l: usize, m: usize, x: f64) -> f64 {
    var sg = 1.0f64
    if m % 2usize == 1usize && csphase < 0.0f64 { sg = -1.0f64 }
    let f = sg * leg_norm(norm, l, m)
    let p = leg_plm(l, m, x)
    if kind == 0usize { ret f * p }
    var pl1 = 0.0f64
    if l > m { pl1 = leg_plm(l - 1usize, m, x) }
    let om = 1.0f64 - x * x
    // (x^2 - 1) P' = l x P - (l + m) P_{l-1}
    let dp = (f64(l) * x * p - f64(l + m) * pl1) / (0.0f64 - om)
    if kind == 1usize { ret f * dp }
    let sn = math.sqrt[f64](om)
    if kind == 2usize { ret f * (0.0f64 - sn * dp) }
    let lf = f64(l)
    let d2p = (2.0f64 * x * dp - (lf * (lf + 1.0f64) - f64(m * m) / om) * p) / om
    if kind == 3usize { ret f * d2p }
    ret f * (om * d2p - x * dp)
}

// ---- hydrogenic radial functions and 2F1 with conjugate parameters
fn hydrogenic_r(n: usize, l: usize, z: f64, r: f64) -> f64 {
    let rho = 2.0f64 * z * r / f64(n)
    // (2Z/n)^(3/2) sqrt((n - l - 1)! / (2 n (n + l)!)) e^(-rho/2) rho^l L_{n-l-1}^{2l+1}(rho)
    var q = 1.0f64
    var i = n - l
    while i <= n + l {
        q = q / f64(i)
        i += 1usize
    }
    let nrm = math.pow[f64](2.0f64 * z / f64(n), 1.5f64) * math.sqrt[f64](q / (2.0f64 * f64(n)))
    ret nrm * math.exp[f64](0.0f64 - rho / 2.0f64) * math.pow[f64](rho, f64(l)) * gs.laguerre_n(n - l - 1usize, 2.0f64 * f64(l) + 1.0f64, rho)
}

// Re 2F1(ar + i ai, ar - i ai; c; x) for |x| < 1: every term of the series is real
fn hyperg_2f1_conj(ar: f64, ai: f64, c: f64, x: f64) -> f64 {
    var t = 1.0f64
    var s = 1.0f64
    var k = 0usize
    while k < 5000usize {
        let kf = f64(k)
        t = t * ((ar + kf) * (ar + kf) + ai * ai) / ((c + kf) * (kf + 1.0f64)) * x
        s += t
        if ab(t) < 1.0e-18f64 * ab(s) { break }
        k += 1usize
    }
    ret s
}

fn pow_int(x0: f64, n: i64) -> f64 {
    var x = x0
    var un = n
    if n < 0i64 {
        x = 1.0f64 / x
        un = 0i64 - n
    }
    var v = 1.0f64
    while true {
        if un % 2i64 == 1i64 { v = v * x }
        un = un / 2i64
        x = x * x
        if un == 0i64 { break }
    }
    ret v
}

fn fact(n: usize) -> f64 {
    var r = 1.0f64
    var i = 2usize
    while i <= n {
        r = r * f64(i)
        i += 1usize
    }
    ret r
}

// ln |Gamma(x)| and the sign of Gamma(x)
fn lngamma_abs(x: f64) -> f64 {
    if x > -1.0f64 {
        let (v, _e) = gc.lngamma_e(x)
        ret v
    }
    ret sp.lgamma(x)
}

fn gamma_sign(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    let fl = math.floor[f64](x)
    var par = fl - 2.0f64 * math.floor[f64](fl / 2.0f64)
    if par == 0.0f64 { ret 1.0f64 }
    par = 1.0f64
    ret -1.0f64
}

fn erf_z(x: f64) -> f64 { ret math.exp[f64](0.0f64 - x * x / 2.0f64) / math.sqrt[f64](2.0f64 * mpi()) }

fn erf_q(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, false, false) }

fn legendre_q1(x: f64) -> f64 { ret x * gs.legendre_q0(x) - 1.0f64 }

fn expint_e2(x: f64) -> f64 { ret math.exp[f64](0.0f64 - x) - x * gs.expint_e1(x) }

fn zetam1_int(n: usize) -> f64 { ret gs.hzeta(f64(n), 2.0f64) }

fn poly_eval(c: []const f64, n: usize, x: f64) -> f64 {
    var v = c[n - 1usize]
    var i = n - 1usize
    while i > 0usize {
        i -= 1usize
        v = c[i] + x * v
    }
    ret v
}
