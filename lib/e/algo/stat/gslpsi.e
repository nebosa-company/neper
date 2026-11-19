// R gsl: psi (digamma) of a real argument, psi of an integer, the trigamma function (real and integer argument) and the polygamma functions with gsl's error estimates, a port of
// specfunc/psi.c over the generated Chebyshev tables. The table-driven integer forms take their value from the harmonic sum and Hurwitz zeta (equal to the tables to rounding) with the
// error gsl records. Every function returns (value, error); a domain error returns (0, 0).

use e.math
use e.algo.stat.gslcheb as ch
use e.algo.stat.gslw as gw
use e.algo.stat.gslairy as ga
use e.algo.stat.gslcoulomb as gc

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn mpi() -> f64 { ret 3.141592653589793238462643383279f64 }

fn psi(x: f64) -> (f64, f64) {
    let y = fa(x)
    if x == 0.0f64 || x == -1.0f64 || x == -2.0f64 { ret (0.0f64, 0.0f64) }
    if y >= 2.0f64 {
        let (cv, ce) = ch.cvv_psi_apsi(8.0f64 / (y * y) - 1.0f64)
        if x < 0.0f64 {
            let s = math.sin[f64](mpi() * x)
            let c = math.cos[f64](mpi() * x)
            if fa(s) < 2.0f64 * 1.4916681462400413e-154f64 { ret (0.0f64, 0.0f64) }
            let v = math.log[f64](y) - 0.5f64 / x + cv - mpi() * c / s
            ret (v, mpi() * fa(x) * c_eps() / (s * s) + ce + c_eps() * fa(v))
        }
        let v = math.log[f64](y) - 0.5f64 / x + cv
        ret (v, ce + c_eps() * fa(v))
    }
    if x < -1.0f64 {
        let v = x + 2.0f64
        let t1 = 1.0f64 / x
        let t2 = 1.0f64 / (x + 1.0f64)
        let t3 = 1.0f64 / v
        let (cv, ce) = ch.cvv_psi_psi(2.0f64 * v - 1.0f64)
        let r = 0.0f64 - (t1 + t2 + t3) + cv
        ret (r, c_eps() * (fa(t1) + fa(x / (t2 * t2)) + fa(x / (t3 * t3))) + ce + c_eps() * fa(r))
    }
    if x < 0.0f64 {
        let v = x + 1.0f64
        let t1 = 1.0f64 / x
        let t2 = 1.0f64 / v
        let (cv, ce) = ch.cvv_psi_psi(2.0f64 * v - 1.0f64)
        let r = 0.0f64 - (t1 + t2) + cv
        ret (r, c_eps() * (fa(t1) + fa(x / (t2 * t2))) + ce + c_eps() * fa(r))
    }
    if x < 1.0f64 {
        let t1 = 1.0f64 / x
        let (cv, ce) = ch.cvv_psi_psi(2.0f64 * x - 1.0f64)
        let r = 0.0f64 - t1 + cv
        ret (r, c_eps() * t1 + ce + c_eps() * fa(r))
    }
    let v = x - 1.0f64
    let (cv, ce) = ch.cvv_psi_psi(2.0f64 * v - 1.0f64)
    ret (cv, ce)
}

// psi(n) for an integer n >= 1: gsl's table below 101 (error eps |value|), the asymptotic series above
fn psi_int(n: usize) -> (f64, f64) {
    if n == 0usize { ret (0.0f64, 0.0f64) }
    if n <= 100usize {
        var h = 0.0f64
        var k = n - 1usize
        while k >= 1usize {
            h += 1.0f64 / f64(k)
            k -= 1usize
        }
        let v = h - 0.577215664901532860606512090082f64
        ret (v, c_eps() * fa(v))
    }
    let nf = f64(n)
    let ni2 = (1.0f64 / nf) * (1.0f64 / nf)
    let ser = ni2 * (-1.0f64 / 12.0f64 + ni2 * (1.0f64 / 120.0f64 + ni2 * (-1.0f64 / 252.0f64 + ni2 * (1.0f64 / 240.0f64))))
    let v = math.log[f64](nf) - 0.5f64 / nf + ser
    ret (v, c_eps() * (fa(math.log[f64](nf)) + fa(0.5f64 / nf) + fa(ser)) + c_eps() * fa(v))
}

fn lnfact(n: usize) -> (f64, f64) {
    if n <= 170usize {
        var r = 1.0f64
        var i = 2usize
        while i <= n {
            r = r * f64(i)
            i += 1usize
        }
        let v = math.log[f64](r)
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    let (v, e) = gc.lngamma_e(f64(n) + 1.0f64)
    ret (v, e)
}

// psi^(n)(x) for n >= 1, x > 0 (A&S 6.4.10)
fn psi_n_xg0(n: usize, x: f64) -> (f64, f64) {
    let (hv, he) = gw.hzeta(f64(n) + 1.0f64, x)
    let (lv, le) = lnfact(n)
    let (v, e) = ga.exp_mult_err(lv, le, hv, he)
    if n % 2usize == 0usize { ret (0.0f64 - v, e) }
    ret (v, e)
}

fn psi_1_int(n: usize) -> (f64, f64) {
    if n == 0usize { ret (0.0f64, 0.0f64) }
    if n <= 100usize {
        let (v, _e) = gw.hzeta(2.0f64, f64(n))
        ret (v, c_eps() * v)
    }
    let nf = f64(n)
    let ni2 = (1.0f64 / nf) * (1.0f64 / nf)
    let ser = ni2 * ni2 * (-1.0f64 / 30.0f64 + ni2 * (1.0f64 / 42.0f64 + -1.0f64 / 30.0f64 * ni2))
    let v = (1.0f64 + 0.5f64 / nf + 1.0f64 / (6.0f64 * nf * nf) + ser) / nf
    ret (v, c_eps() * v)
}

fn psi_1(x: f64) -> (f64, f64) {
    if x == 0.0f64 || x == -1.0f64 || x == -2.0f64 { ret (0.0f64, 0.0f64) }
    if x > 0.0f64 {
        let (v, e) = psi_n_xg0(1usize, x)
        ret (v, e)
    }
    if x > -5.0f64 {
        let mm = -math.floor[f64](x)
        let fx = x + mm
        if fx == 0.0f64 { ret (0.0f64, 0.0f64) }
        var sum = 0.0f64
        var m = 0.0f64
        while m < mm {
            sum += 1.0f64 / ((x + m) * (x + m))
            m += 1.0f64
        }
        let (v, e) = psi_n_xg0(1usize, fx)
        ret (v + sum, e + mm * c_eps() * sum)
    }
    let sin_px = math.sin[f64](mpi() * x)
    let d = mpi() * mpi() / (sin_px * sin_px)
    let (rv, re) = psi_n_xg0(1usize, 1.0f64 - x)
    ret (d - rv, re + 2.0f64 * c_eps() * d)
}

fn psi_n(n: usize, x: f64) -> (f64, f64) {
    if n == 0usize {
        let (v, e) = psi(x)
        ret (v, e)
    }
    if n == 1usize {
        let (v, e) = psi_1(x)
        ret (v, e)
    }
    if x <= 0.0f64 { ret (0.0f64, 0.0f64) }
    let (v, e) = psi_n_xg0(n, x)
    ret (v, e)
}
