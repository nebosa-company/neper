// R gsl, the Fermi-Dirac integrals with gsl_sf_result.err: m1, 0, 1, 2, mhalf, half, 3half, inc_0 and the integer order (j <= -2 by the polynomial form, x < 0 by the Levin-u series, the series
// for x < 1.5 and the asymptotic expansion). fd_UMseries_int (the confluent hypergeometric fallback when the asymptotic expansion fails) is not here.
// Every function returns (value, error); an underflow returns (0, 0).

use e.math
use e.mem
use e.os
use e.algo.stat.gslcheb2 as ch
use e.algo.stat.gslcoulomb as gc
use e.algo.stat.gslerr as ge
use e.algo.stat.gslerr2 as g2
use e.algo.stat.gslzeta as gz

fn d_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn da(x: f64) -> f64 { ret math.abs[f64](x) }
fn d_logmin() -> f64 { ret -7.0839641853226408e+02f64 }

fn grab(a: *mem.Arena, n: usize) -> []f64 {
    let (p, g) = mem.alloc[f64](a, n)
    if g != ok { os.exit(4) }
    ret p
}

fn fd_m1(x: f64) -> (f64, f64) {
    if x < d_logmin() { ret (0.0f64, 0.0f64) }
    if x < 0.0f64 {
        let ex = math.exp[f64](x)
        let v = ex / (1.0f64 + ex)
        ret (v, 2.0f64 * (da(x) + 1.0f64) * d_eps() * da(v))
    }
    let ex2 = math.exp[f64](0.0f64 - x)
    ret (1.0f64 / (1.0f64 + ex2), 2.0f64 * d_eps() * (x + 1.0f64) * ex2)
}

fn fd_0(x: f64) -> (f64, f64) {
    if x < d_logmin() { ret (0.0f64, 0.0f64) }
    if x < -5.0f64 {
        let ex = math.exp[f64](x)
        let ser = 1.0f64 - ex * (0.5f64 - ex * (1.0f64 / 3.0f64 - ex * (1.0f64 / 4.0f64 - ex * (1.0f64 / 5.0f64 - ex / 6.0f64))))
        let v = ex * ser
        ret (v, 2.0f64 * d_eps() * da(v))
    }
    if x < 10.0f64 { ret (math.log[f64](1.0f64 + math.exp[f64](x)), da(x * d_eps())) }
    let ex2 = math.exp[f64](0.0f64 - x)
    ret (x + ex2 * (1.0f64 - 0.5f64 * ex2 + ex2 * ex2 / 3.0f64 - ex2 * ex2 * ex2 / 4.0f64), (x + ex2) * d_eps())
}

// the series for x < -1: term *= -ex * rat^p, p the power of (n-1)/n (the integer orders 1, 2 and the half orders)
fn fd_series_neg(x: f64, p: f64, nmax: i64) -> (f64, f64) {
    let ex = math.exp[f64](x)
    var term = ex
    var sum = ex
    var n = 2i64
    while n < nmax {
        let rat = (f64(n) - 1.0f64) / f64(n)
        term = term * (0.0f64 - ex * math.pow[f64](rat, p))
        sum = sum + term
        if da(term / sum) < d_eps() { break }
        n += 1i64
    }
    ret (sum, 2.0f64 * d_eps() * da(sum))
}

fn fd_1(x: f64) -> (f64, f64) {
    if x < d_logmin() { ret (0.0f64, 0.0f64) }
    if x < -1.0f64 {
        let (v, e) = fd_series_neg(x, 2.0f64, 100i64)
        ret (v, e)
    }
    if x < 1.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_1_a(x)
        ret (v, e)
    }
    if x < 4.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_1_b(2.0f64 / 3.0f64 * (x - 1.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 10.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_1_c(1.0f64 / 3.0f64 * (x - 4.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 30.0f64 {
        let (cv, ce) = ch.cvv_fermi_dirac_fd_1_d(0.1f64 * x - 2.0f64)
        let v = cv * x * x
        ret (v, ce * x * x + d_eps() * da(v))
    }
    if x < 1.0f64 / 1.4901161193847656e-08f64 {
        let (cv, ce) = ch.cvv_fermi_dirac_fd_1_e(60.0f64 / x - 1.0f64)
        let v = cv * x * x
        ret (v, ce * x * x + d_eps() * da(v))
    }
    let v = 0.5f64 * x * x
    ret (v, 2.0f64 * d_eps() * da(v))
}

fn fd_2(x: f64) -> (f64, f64) {
    if x < d_logmin() { ret (0.0f64, 0.0f64) }
    if x < -1.0f64 {
        let (v, e) = fd_series_neg(x, 3.0f64, 100i64)
        ret (v, e)
    }
    if x < 1.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_2_a(x)
        ret (v, e)
    }
    if x < 4.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_2_b(2.0f64 / 3.0f64 * (x - 1.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 10.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_2_c(1.0f64 / 3.0f64 * (x - 4.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 30.0f64 {
        let (cv, ce) = ch.cvv_fermi_dirac_fd_2_d(0.1f64 * x - 2.0f64)
        let v = cv * x * x * x
        ret (v, ce * x * x * x + 3.0f64 * d_eps() * da(v))
    }
    if x < 1.0f64 / 6.0554544523933429e-06f64 {
        let (cv, ce) = ch.cvv_fermi_dirac_fd_2_e(60.0f64 / x - 1.0f64)
        let v = cv * x * x * x
        ret (v, ce * x * x * x + 3.0f64 * d_eps() * da(v))
    }
    let v = 1.0f64 / 6.0f64 * x * x * x
    ret (v, 3.0f64 * d_eps() * da(v))
}

// the series of the half orders: term *= -ex * rat^k (rat = (n-1)/n), k = 1/2 + the integer part; the powers are applied as in gsl
fn fd_half_series(x: f64, kind: usize) -> (f64, f64) {
    let ex = math.exp[f64](x)
    var term = ex
    var sum = ex
    var nmax = 100i64
    if kind == 0usize { nmax = 200i64 }
    var n = 2i64
    while n < nmax {
        let rat = (f64(n) - 1.0f64) / f64(n)
        if kind == 0usize { term = term * (0.0f64 - ex * math.sqrt[f64](rat)) }
        if kind == 1usize { term = term * (0.0f64 - ex * rat * math.sqrt[f64](rat)) }
        if kind == 2usize { term = term * (0.0f64 - ex * rat * rat * math.sqrt[f64](rat)) }
        sum = sum + term
        if da(term / sum) < d_eps() { break }
        n += 1i64
    }
    ret (sum, 2.0f64 * da(sum) * d_eps())
}

// the Levin-u series of gsl's fd_neg for x < 0 and order j
fn fd_neg(a: *mem.Arena, j: f64, x: f64) -> (f64, f64) {
    if x < d_logmin() { ret (0.0f64, 0.0f64) }
    if x < -1.0f64 && x < 0.0f64 - da(j + 1.0f64) {
        let ex = math.exp[f64](x)
        var term = ex
        var sum = ex
        var n = 2i64
        while n < 100i64 {
            let rat = (f64(n) - 1.0f64) / f64(n)
            let p = math.pow[f64](rat, j + 1.0f64)
            term = term * (0.0f64 - ex * p)
            sum = sum + term
            if da(term / sum) < d_eps() { break }
            n += 1i64
        }
        ret (sum, 2.0f64 * d_eps() * da(sum))
    }
    let qnum = grab(a, 101usize)
    let qden = grab(a, 101usize)
    var s = 0.0f64
    var xn = x
    let ex2 = 0.0f64 - math.exp[f64](x)
    var enx = 0.0f64 - ex2
    var f = 0.0f64
    var f_previous = 0.0f64
    var jterm = 0i64
    while jterm <= 100i64 {
        let p = math.pow[f64](f64(jterm) + 1.0f64, j + 1.0f64)
        let term = enx / p
        f_previous = f
        if jterm == 0i64 { s = 0.0f64 }
        s += term
        let it = usize(jterm)
        qden[it] = 1.0f64 / (term * (f64(jterm) + 1.0f64) * (f64(jterm) + 1.0f64))
        qnum[it] = s * qden[it]
        if jterm > 0i64 {
            var factor = 1.0f64
            let ratio = f64(jterm) / (f64(jterm) + 1.0f64)
            var jj = jterm - 1i64
            while jj >= 0i64 {
                let c = factor * (f64(jj) + 1.0f64) / (f64(jterm) + 1.0f64)
                factor = factor * ratio
                let u = usize(jj)
                qden[u] = qden[u + 1usize] - c * qden[u]
                qnum[u] = qnum[u + 1usize] - c * qnum[u]
                jj -= 1i64
            }
        }
        f = qnum[0usize] / qden[0usize]
        xn += x
        if da(f - f_previous) < da(f) * 2.0f64 * d_eps() || xn < d_logmin() { break }
        enx = enx * ex2
        jterm += 1i64
    }
    ret (f, da(f - f_previous) + 2.0f64 * d_eps() * da(f))
}

// eta at an integer, negative arguments from the Bernoulli numbers (gsl reads a table of the same values)
fn eta_i(n: i64) -> f64 {
    if n >= 0i64 {
        let (v, _e) = gz.eta_int(usize(n))
        ret v
    }
    if n % 2i64 == 0i64 { ret 0.0f64 }
    let m = (1i64 - n) / 2i64
    let (z, _ze) = gz.zeta(f64(2i64 * m))
    var sg = 1.0f64
    if m % 2i64 == 0i64 { sg = -1.0f64 }
    let b = sg * 2.0f64 * g2.fact_val(usize(2i64 * m)) * z / math.pow[f64](2.0f64 * 3.141592653589793238462643383279f64, f64(2i64 * m))
    ret (math.pow[f64](2.0f64, f64(2i64 * m)) - 1.0f64) * b / f64(2i64 * m)
}

fn fd_asymp(a: *mem.Arena, j: f64, x: f64) -> (f64, f64) {
    var j_integer = false
    if da(j - math.floor[f64](j + 0.5f64)) < 100.0f64 * d_eps() { j_integer = true }
    let (lgv, lge) = gc.lngamma_e(j + 2.0f64)
    var seqn_val = 0.5f64
    var seqn_err = 0.0f64
    let xm2 = (1.0f64 / x) / x
    var xgam = 1.0f64
    var add = 1.7976931348623157e308f64
    var n = 1i64
    while n <= 200i64 {
        let add_previous = add
        let etav = eta_i(2i64 * n)
        xgam = xgam * xm2 * (j + 1.0f64 - f64(2i64 * n - 2i64)) * (j + 1.0f64 - f64(2i64 * n - 1i64))
        add = etav * xgam
        if !j_integer && da(add) > da(add_previous) { break }
        if da(add / seqn_val) < d_eps() { break }
        seqn_val += add
        seqn_err += 2.0f64 * d_eps() * da(add)
        n += 1i64
    }
    seqn_err += da(add)
    let (fv, fe) = fd_neg(a, j, 0.0f64 - x)
    let ln_x = math.log[f64](x)
    let t1 = (j + 1.0f64) * ln_x
    let arg_v = t1 - lgv
    let arg_e = d_eps() * (da(t1) + da(lgv)) + lge
    let (exv, exe, _st) = gc.exp_err(arg_v, arg_e)
    let cos_term = math.cos[f64](j * 3.141592653589793238462643383279f64)
    let v = cos_term * fv + 2.0f64 * seqn_val * exv
    var er = da(2.0f64 * exe * seqn_val)
    er += da(2.0f64 * exv * seqn_err)
    er += da(cos_term) * fe
    er += 4.0f64 * d_eps() * da(v)
    ret (v, er)
}

fn fd_series_int(j: i64, x: f64) -> (f64, f64) {
    var sum = 0.0f64
    var pow_factor = 1.0f64
    var del = pow_factor * eta_i(j + 1i64)
    sum += del
    var n = 1i64
    while n <= j + 2i64 {
        pow_factor = pow_factor * (x / f64(n))
        del = pow_factor * eta_i(j + 1i64 - n)
        sum += del
        if da(del / sum) < d_eps() { break }
        n += 1i64
    }
    if j < 32i64 {
        let (pw, _pe) = ge.e_pow_int(x, j)
        let pre2 = pw / g2.fact_val(usize(j))
        var pf = x * x * x * x / (f64((j + 4i64) * (j + 3i64) * (j + 2i64) * (j + 1i64)))
        var sum2 = eta_i(-3i64) * pf
        var m = 3i64
        while m < 24i64 {
            pf = pf * (x * x / f64((j + 2i64 * m) * (j + 2i64 * m - 1i64)))
            sum2 += eta_i(1i64 - 2i64 * m) * pf
            m += 1i64
        }
        sum += pre2 * sum2
    }
    ret (sum, 2.0f64 * d_eps() * da(sum))
}

fn fd_nint(a: *mem.Arena, j: i64, x: f64) -> (f64, f64) {
    let q = grab(a, 102usize)
    let n = usize(0i64 - (j + 1i64))
    q[1usize] = 1.0f64
    var k = 2usize
    while k <= n {
        q[k] = 0.0f64 - q[k - 1usize]
        var i = k - 1usize
        while i >= 2usize {
            q[i] = f64(i) * q[i] - f64(k - (i - 1usize)) * q[i - 1usize]
            i -= 1usize
        }
        k += 1usize
    }
    var av = 0.0f64
    var f = 0.0f64
    if x >= 0.0f64 {
        av = math.exp[f64](0.0f64 - x)
        f = q[1usize]
        var i2 = 2usize
        while i2 <= n {
            f = f * av + q[i2]
            i2 += 1usize
        }
    }
    if x < 0.0f64 {
        av = math.exp[f64](x)
        f = q[n]
        var i3 = n - 1usize
        while i3 >= 1usize {
            f = f * av + q[i3]
            i3 -= 1usize
        }
    }
    let (p, _pe) = ge.e_pow_int(1.0f64 + av, j)
    ret (f * av * p, 3.0f64 * d_eps() * da(f * av * p))
}

fn fd_int(a: *mem.Arena, j: i64, x: f64) -> (f64, f64) {
    if j < -1i64 {
        let (v, e) = fd_nint(a, j, x)
        ret (v, e)
    }
    if j == -1i64 {
        let (v, e) = fd_m1(x)
        ret (v, e)
    }
    if j == 0i64 {
        let (v, e) = fd_0(x)
        ret (v, e)
    }
    if j == 1i64 {
        let (v, e) = fd_1(x)
        ret (v, e)
    }
    if j == 2i64 {
        let (v, e) = fd_2(x)
        ret (v, e)
    }
    if x < 0.0f64 {
        let (v, e) = fd_neg(a, f64(j), x)
        ret (v, e)
    }
    if x == 0.0f64 {
        let (v, e) = gz.eta_int(usize(j + 1i64))
        ret (v, e)
    }
    if x < 1.5f64 {
        let (v, e) = fd_series_int(j, x)
        ret (v, e)
    }
    let (fv, fe) = fd_asymp(a, f64(j), x)
    ret (fv, fe + 2.0f64 * d_eps() * da(fv))
}

fn fd_mhalf(a: *mem.Arena, x: f64) -> (f64, f64) {
    if x < d_logmin() { ret (0.0f64, 0.0f64) }
    if x < -1.0f64 {
        let (v, e) = fd_half_series(x, 0usize)
        ret (v, e)
    }
    if x < 1.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_mhalf_a(x)
        ret (v, e)
    }
    if x < 4.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_mhalf_b(2.0f64 / 3.0f64 * (x - 1.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 10.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_mhalf_c(1.0f64 / 3.0f64 * (x - 4.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 30.0f64 {
        let rtx = math.sqrt[f64](x)
        let (cv, ce) = ch.cvv_fermi_dirac_fd_mhalf_d(0.1f64 * x - 2.0f64)
        let v = cv * rtx
        ret (v, ce * rtx + 0.5f64 * d_eps() * da(v))
    }
    let (v2, e2) = fd_asymp(a, -0.5f64, x)
    ret (v2, e2)
}

fn fd_half(a: *mem.Arena, x: f64) -> (f64, f64) {
    if x < d_logmin() { ret (0.0f64, 0.0f64) }
    if x < -1.0f64 {
        let (v, e) = fd_half_series(x, 1usize)
        ret (v, e)
    }
    if x < 1.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_half_a(x)
        ret (v, e)
    }
    if x < 4.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_half_b(2.0f64 / 3.0f64 * (x - 1.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 10.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_half_c(1.0f64 / 3.0f64 * (x - 4.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 30.0f64 {
        let x32 = x * math.sqrt[f64](x)
        let (cv, ce) = ch.cvv_fermi_dirac_fd_half_d(0.1f64 * x - 2.0f64)
        let v = cv * x32
        ret (v, ce * x32 + 1.5f64 * d_eps() * da(v))
    }
    let (v2, e2) = fd_asymp(a, 0.5f64, x)
    ret (v2, e2)
}

fn fd_3half(a: *mem.Arena, x: f64) -> (f64, f64) {
    if x < d_logmin() { ret (0.0f64, 0.0f64) }
    if x < -1.0f64 {
        let (v, e) = fd_half_series(x, 2usize)
        ret (v, e)
    }
    if x < 1.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_3half_a(x)
        ret (v, e)
    }
    if x < 4.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_3half_b(2.0f64 / 3.0f64 * (x - 1.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 10.0f64 {
        let (v, e) = ch.cvv_fermi_dirac_fd_3half_c(1.0f64 / 3.0f64 * (x - 4.0f64) - 1.0f64)
        ret (v, e)
    }
    if x < 30.0f64 {
        let x52 = x * x * math.sqrt[f64](x)
        let (cv, ce) = ch.cvv_fermi_dirac_fd_3half_d(0.1f64 * x - 2.0f64)
        let v = cv * x52
        ret (v, ce * x52 + 2.5f64 * d_eps() * da(v))
    }
    let (v2, e2) = fd_asymp(a, 1.5f64, x)
    ret (v2, e2)
}

fn fd_inc_0(x: f64, b: f64) -> (f64, f64) {
    if b < 0.0f64 { ret (0.0f64, 0.0f64) }
    let arg = b - x
    let (fv, fe) = fd_0(arg)
    ret (fv - arg, fe + d_eps() * (da(x) + da(b)))
}
