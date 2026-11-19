// R gsl: the Lambert W branches W0 and W-1 (specfunc/lambert.c) and the Hurwitz zeta function (specfunc/zeta.c, Euler-Maclaurin branch) with gsl's error estimates.
// Every function returns (value, error); the domain-error cases return what gsl stores in the result.

use e.math

fn c_eps() -> f64 { ret 2.2204460492503131e-16f64 }
fn fa(x: f64) -> f64 { ret math.abs[f64](x) }
fn fmax(a: f64, b: f64) -> f64 {
    if a > b { ret a }
    ret b
}

fn series_c(k: usize) -> f64 {
    if k == 0usize { ret -1.0f64 }
    if k == 1usize { ret 2.331643981597124203363536062168f64 }
    if k == 2usize { ret -1.812187885639363490240191647568f64 }
    if k == 3usize { ret 1.936631114492359755363277457668f64 }
    if k == 4usize { ret -2.353551201881614516821543561516f64 }
    if k == 5usize { ret 3.066858901050631912893148922704f64 }
    if k == 6usize { ret -4.175335600258177138854984177460f64 }
    if k == 7usize { ret 5.858023729874774148815053846119f64 }
    if k == 8usize { ret -8.401032217523977370984161688514f64 }
    if k == 9usize { ret 12.250753501314460424f64 }
    if k == 10usize { ret -18.100697012472442755f64 }
    ret 27.029044799010561650f64
}

fn series_eval(r: f64) -> f64 {
    let t8 = series_c(8usize) + r * (series_c(9usize) + r * (series_c(10usize) + r * series_c(11usize)))
    let t5 = series_c(5usize) + r * (series_c(6usize) + r * (series_c(7usize) + r * t8))
    let t1 = series_c(1usize) + r * (series_c(2usize) + r * (series_c(3usize) + r * (series_c(4usize) + r * t5)))
    ret series_c(0usize) + r * t1
}

fn halley(x: f64, w0: f64, max_iters: usize) -> (f64, f64) {
    var w = w0
    var i = 0usize
    while i < max_iters {
        let e = math.exp[f64](w)
        let p = w + 1.0f64
        var t = w * e - x
        if w > 0.0f64 {
            t = (t / p) / e
        }
        if !(w > 0.0f64) {
            t = t / (e * p - 0.5f64 * (p + 1.0f64) * t / p)
        }
        w -= t
        let tol = 10.0f64 * c_eps() * fmax(fa(w), 1.0f64 / (fa(p) * e))
        if fa(t) < tol { ret (w, 2.0f64 * tol) }
        i += 1usize
    }
    ret (w, fa(w))
}

fn lambert_w0(x: f64) -> (f64, f64) {
    let one_over_e = 1.0f64 / 2.718281828459045235360287471353f64
    let q = x + one_over_e
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    if q < 0.0f64 { ret (-1.0f64, math.sqrt[f64](0.0f64 - q)) }
    if q == 0.0f64 { ret (-1.0f64, c_eps()) }
    if q < 1.0e-03f64 {
        let v = series_eval(math.sqrt[f64](q))
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    var w = 0.0f64
    if x < 1.0f64 {
        let p = math.sqrt[f64](2.0f64 * 2.718281828459045235360287471353f64 * q)
        w = -1.0f64 + p * (1.0f64 + p * (-1.0f64 / 3.0f64 + p * 11.0f64 / 72.0f64))
    }
    if !(x < 1.0f64) {
        w = math.log[f64](x)
        if x > 3.0f64 { w -= math.log[f64](w) }
    }
    let (v, e) = halley(x, w, 10usize)
    ret (v, e)
}

fn lambert_wm1(x: f64) -> (f64, f64) {
    if x > 0.0f64 {
        let (v, e) = lambert_w0(x)
        ret (v, e)
    }
    if x == 0.0f64 { ret (0.0f64, 0.0f64) }
    let q = x + 1.0f64 / 2.718281828459045235360287471353f64
    if q < 0.0f64 { ret (-1.0f64, math.sqrt[f64](0.0f64 - q)) }
    var w = 0.0f64
    if x < -1.0e-6f64 {
        let r = 0.0f64 - math.sqrt[f64](q)
        w = series_eval(r)
        if q < 3.0e-3f64 { ret (w, 5.0f64 * c_eps() * fa(w)) }
    }
    if !(x < -1.0e-6f64) {
        let l1 = math.log[f64](0.0f64 - x)
        let l2 = math.log[f64](0.0f64 - l1)
        w = l1 - l2 + l2 / l1
    }
    let (v, e) = halley(x, w, 32usize)
    ret (v, e)
}

fn hzeta_c(j: usize) -> f64 {
    if j == 0usize { ret 1.0f64 }
    if j == 1usize { ret 0.083333333333333333333333333333f64 }
    if j == 2usize { ret -0.00138888888888888888888888888889f64 }
    if j == 3usize { ret 0.000033068783068783068783068783069f64 }
    if j == 4usize { ret -8.2671957671957671957671957672e-07f64 }
    if j == 5usize { ret 2.0876756987868098979210090321e-08f64 }
    if j == 6usize { ret -5.2841901386874931848476822022e-10f64 }
    if j == 7usize { ret 1.3382536530684678832826980975e-11f64 }
    if j == 8usize { ret -3.3896802963225828668301953912e-13f64 }
    if j == 9usize { ret 8.5860620562778445641359054504e-15f64 }
    if j == 10usize { ret -2.1748686985580618730415164239e-16f64 }
    if j == 11usize { ret 5.5090028283602295152026526089e-18f64 }
    if j == 12usize { ret -1.3954464685812523340707686264e-19f64 }
    if j == 13usize { ret 3.5347070396294674716932299778e-21f64 }
    ret -8.9535174270375468504026113181e-23f64
}

fn hzeta(s: f64, q: f64) -> (f64, f64) {
    if s <= 1.0f64 || q <= 0.0f64 { ret (0.0f64, 0.0f64) }
    let max_bits = 54.0f64
    let ln_term0 = 0.0f64 - s * math.log[f64](q)
    if ln_term0 < -7.0839641853226408e+02f64 + 1.0f64 { ret (0.0f64, 0.0f64) }
    if ln_term0 > 7.0978271289338397e+02f64 - 1.0f64 { ret (1.0f64 / 0.0f64, 1.0f64 / 0.0f64) }
    if (s > max_bits && q < 1.0f64) || (s > 0.5f64 * max_bits && q < 0.25f64) {
        let v = math.pow[f64](q, 0.0f64 - s)
        ret (v, 2.0f64 * c_eps() * fa(v))
    }
    if s > 0.5f64 * max_bits && q < 1.0f64 {
        let p1 = math.pow[f64](q, 0.0f64 - s)
        let p2 = math.pow[f64](q / (1.0f64 + q), s)
        let p3 = math.pow[f64](q / (2.0f64 + q), s)
        let v = p1 * (1.0f64 + p2 + p3)
        ret (v, c_eps() * (0.5f64 * s + 2.0f64) * fa(v))
    }
    let jmax = 12usize
    let kmax = 10usize
    let pmax = math.pow[f64](f64(kmax) + q, 0.0f64 - s)
    var scp = s
    var pcp = pmax / (f64(kmax) + q)
    var ans = pmax * ((f64(kmax) + q) / (s - 1.0f64) + 0.5f64)
    var k = 0usize
    while k < kmax {
        ans += math.pow[f64](f64(k) + q, 0.0f64 - s)
        k += 1usize
    }
    var j = 0usize
    while j <= jmax {
        let delta = hzeta_c(j + 1usize) * scp * pcp
        ans += delta
        if fa(delta / ans) < 0.5f64 * c_eps() { break }
        scp *= (s + f64(2usize * j + 1usize)) * (s + f64(2usize * j + 2usize))
        pcp /= (f64(kmax) + q) * (f64(kmax) + q)
        j += 1usize
    }
    ret (ans, 2.0f64 * (f64(jmax) + 1.0f64) * c_eps() * fa(ans))
}
