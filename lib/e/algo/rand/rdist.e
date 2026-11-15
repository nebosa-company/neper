// R's random variate generators over e.algo.rand.r's Mersenne-Twister stream, value for value:
// `rgamma` (Ahrens and Dieter GS and GD), `rchisq`, `rt`, `rbeta` (Cheng's BB and BC), `rbinom`
// (BTPEC), `rpois` (Ahrens and Dieter PD), `rnbinom`, `rgeom`, `rweibull`, `rlnorm`, `rlogis` and
// `rcauchy`, ported from R's nmath. The C code keeps the set-up of the last call in statics; the
// numbers it draws do not depend on them, so each call here sets up again.
//
// Not here: `rhyper`, `rnchisq`, `rmultinom`, `rsignrank`, `rwilcox`, rbinom for n >= 2^31 (R
// answers it through `qbinom`), and rbinom where `k * k` overflows a C int (n past about 4e5).

use e.algo.rand.r as rng
use e.math
use e.math.special as special
use e.mem

fn finite(x: f64) -> bool { ret x == x && x - x == 0.0f64 }

fn sqrt_of(x: f64) -> f64 { ret math.sqrt[f64](x) }

fn abs_of(x: f64) -> f64 {
    if x < 0.0f64 { ret 0.0f64 - x }
    ret x
}

fn posinf() -> f64 { ret 1.0f64 / 0.0f64 }

fn expm1(x: f64) -> f64 {
    let u = math.exp[f64](x)
    if u == 1.0f64 { ret x }
    let um1 = u - 1.0f64
    if um1 == -1.0f64 { ret -1.0f64 }
    if u == posinf() { ret u }
    ret um1 * x / math.log[f64](u)
}

// The polynomial of rgamma's GD algorithm in v.
fn gd_poly(v: f64) -> f64 {
    ret ((((((0.1233795f64 * v - 0.1367177f64) * v + 0.1423657f64) * v - 0.1662921f64) * v + 0.2000062f64) * v - 0.250003f64) * v + 0.3333333f64) * v
}

// rgamma(a, scale)
fn rgamma(r: *rng.Rng, a: f64, scale: f64) -> f64 {
    if a != a || scale != scale { ret special.nan() }
    if a <= 0.0f64 || scale <= 0.0f64 {
        if scale == 0.0f64 || a == 0.0f64 { ret 0.0f64 }
        ret special.nan()
    }
    if !finite(a) || !finite(scale) { ret posinf() }
    if a < 1.0f64 {
        let e = 1.0f64 + 0.36787944117144232159f64 * a
        var x = 0.0f64
        var go = true
        while go {
            let p = e * rng.unif(r)
            if p >= 1.0f64 {
                x = 0.0f64 - math.log[f64]((e - p) / a)
                if rng.exp_unit(r) >= (1.0f64 - a) * math.log[f64](x) { go = false }
            } else {
                x = math.exp[f64](math.log[f64](p) / a)
                if rng.exp_unit(r) >= x { go = false }
            }
        }
        ret scale * x
    }
    let s2 = a - 0.5f64
    let s = sqrt_of(s2)
    let d = 5.656854f64 - s * 12.0f64
    var t = rng.norm(r)
    var x = s + 0.5f64 * t
    let ret_val = x * x
    if t >= 0.0f64 { ret scale * ret_val }
    var u = rng.unif(r)
    if d * u <= t * t * t { ret scale * ret_val }
    let rr = 1.0f64 / a
    let q0 = ((((((0.0002424f64 * rr + 0.00024511f64) * rr - 0.00007388f64) * rr + 0.00144121f64) * rr + 0.00801191f64) * rr + 0.02083148f64) * rr + 0.04166669f64) * rr
    var b = 0.0f64
    var si = 0.0f64
    var c = 0.0f64
    if a <= 3.686f64 {
        b = 0.463f64 + s + 0.178f64 * s2
        si = 1.235f64
        c = 0.195f64 / s - 0.079f64 + 0.16f64 * s
    } else if a <= 13.022f64 {
        b = 1.654f64 + 0.0076f64 * s2
        si = 1.68f64 / s + 0.275f64
        c = 0.062f64 / s + 0.024f64
    } else {
        b = 1.77f64
        si = 0.75f64
        c = 0.1515f64 / s
    }
    var q = 0.0f64
    if x > 0.0f64 {
        let v = t / (s + s)
        if abs_of(v) <= 0.25f64 {
            q = q0 + 0.5f64 * t * t * gd_poly(v)
        } else {
            q = q0 - s * t + 0.25f64 * t * t + (s2 + s2) * math.log[f64](1.0f64 + v)
        }
        if math.log[f64](1.0f64 - u) <= q { ret scale * ret_val }
    }
    var go = true
    while go {
        let e = rng.exp_unit(r)
        u = rng.unif(r)
        u = u + u - 1.0f64
        if u < 0.0f64 { t = b - si * e } else { t = b + si * e }
        if t >= -0.71874483771719f64 {
            let v = t / (s + s)
            if abs_of(v) <= 0.25f64 {
                q = q0 + 0.5f64 * t * t * gd_poly(v)
            } else {
                q = q0 - s * t + 0.25f64 * t * t + (s2 + s2) * math.log[f64](1.0f64 + v)
            }
            if q > 0.0f64 {
                let w = expm1(q)
                if c * abs_of(u) <= w * math.exp[f64](e - 0.5f64 * t * t) { go = false }
            }
        }
    }
    x = s + 0.5f64 * t
    ret scale * x * x
}

fn rchisq(r: *rng.Rng, df: f64) -> f64 {
    if !finite(df) || df < 0.0f64 { ret special.nan() }
    ret rgamma(r, df / 2.0f64, 2.0f64)
}

fn rt(r: *rng.Rng, df: f64) -> f64 {
    if df != df || df <= 0.0f64 { ret special.nan() }
    if !finite(df) { ret rng.norm(r) }
    let num = rng.norm(r)
    ret num / sqrt_of(rchisq(r, df) / df)
}

fn fsign(x: f64, y: f64) -> f64 {
    if y >= 0.0f64 { ret abs_of(x) }
    ret 0.0f64 - abs_of(x)
}

// Step F of rpois: (px, py, fx, fy).
fn pois_f(mu: f64, pois: f64, fk: f64, difmuk: f64, s: f64, omega: f64, c3: f64, c2: f64, c1: f64, c0: f64) -> (f64, f64, f64, f64) {
    var px = 0.0f64
    var py = 0.0f64
    if pois < 10.0f64 {
        var fact = 1.0f64
        var i = 2.0f64
        while i <= pois {
            fact = fact * i
            i += 1.0f64
        }
        px = 0.0f64 - mu
        py = math.pow[f64](mu, pois) / fact
    } else {
        var del = 0.0833333333333333333f64 / fk
        del = del * (1.0f64 - 4.8f64 * del * del)
        let v = difmuk / fk
        if abs_of(v) <= 0.25f64 {
            px = fk * v * v * (((((((0.1250060f64 * v - 0.1384794f64) * v + 0.1421878f64) * v - 0.1661269f64) * v + 0.2000118f64) * v - 0.2500068f64) * v + 0.3333333f64) * v - 0.5f64) - del
        } else {
            px = fk * math.log[f64](1.0f64 + v) - difmuk - del
        }
        py = 0.398942280401432677939946059934f64 / sqrt_of(fk)
    }
    var x = (0.5f64 - difmuk) / s
    x = x * x
    let fx = -0.5f64 * x
    let fy = omega * (((c3 * x + c2) * x + c1) * x + c0)
    ret (px, py, fx, fy)
}

// rpois(mu)
fn rpois(r: *rng.Rng, mu: f64) -> f64 {
    if !finite(mu) || mu < 0.0f64 { ret special.nan() }
    if mu <= 0.0f64 { ret 0.0f64 }
    if mu < 10.0f64 {
        let m = 35usize
        let p0 = math.exp[f64](0.0f64 - mu)
        while true {
            let u = rng.unif(r)
            if u <= p0 { ret 0.0f64 }
            var p = p0
            var q = p0
            var k = 1usize
            while k <= m {
                p = p * (mu / f64(k))
                q = q + p
                if u <= q { ret f64(k) }
                k += 1usize
            }
        }
    }
    let s = sqrt_of(mu)
    let d = 6.0f64 * mu * mu
    let big_l = math.floor[f64](mu - 1.1484f64)
    let g = mu + s * rng.norm(r)
    var pois = -1.0f64
    var fk = 0.0f64
    var difmuk = 0.0f64
    var u = 0.0f64
    if g >= 0.0f64 {
        pois = math.floor[f64](g)
        if pois >= big_l { ret pois }
        fk = pois
        difmuk = mu - fk
        u = rng.unif(r)
        if d * u >= difmuk * difmuk * difmuk { ret pois }
    }
    let omega = 0.398942280401432677939946059934f64 / s
    let b1 = 0.0416666666666666667f64 / mu
    let b2 = 0.3f64 * b1 * b1
    let c3 = 0.1428571428571428571f64 * b1 * b2
    let c2 = b2 - 15.0f64 * c3
    let c1 = b1 - 6.0f64 * b2 + 45.0f64 * c3
    let c0 = 1.0f64 - b1 + 3.0f64 * b2 - 15.0f64 * c3
    let c = 0.1069f64 / mu
    if g >= 0.0f64 {
        let (px, py, fx, fy) = pois_f(mu, pois, fk, difmuk, s, omega, c3, c2, c1, c0)
        if fy - u * fy <= py * math.exp[f64](px - fx) { ret pois }
    }
    while true {
        let e = rng.exp_unit(r)
        u = 2.0f64 * rng.unif(r) - 1.0f64
        let t = 1.8f64 + fsign(e, u)
        if t > -0.6744f64 {
            pois = math.floor[f64](mu + s * t)
            fk = pois
            difmuk = mu - fk
            let (px, py, fx, fy) = pois_f(mu, pois, fk, difmuk, s, omega, c3, c2, c1, c0)
            if c * abs_of(u) <= py * math.exp[f64](px + e) - fy * math.exp[f64](fx + e) { ret pois }
        }
    }
    ret pois
}

fn pow_di(x: f64, n: i64) -> f64 {
    var xn = 1.0f64
    var m = n
    var y = x
    if m < 0i64 {
        m = 0i64 - m
        y = 1.0f64 / x
    }
    while m > 0i64 {
        if (m & 1i64) != 0i64 { xn = xn * y }
        m = m / 2i64
        if m > 0i64 { y = y * y }
    }
    ret xn
}

// rbinom(n, p)
fn rbinom(r: *rng.Rng, nin: f64, pp: f64) -> f64 {
    if !finite(nin) { ret special.nan() }
    let rn = math.round[f64](nin)
    if rn != nin { ret special.nan() }
    if !finite(pp) || rn < 0.0f64 || pp < 0.0f64 || pp > 1.0f64 { ret special.nan() }
    if rn == 0.0f64 || pp == 0.0f64 { ret 0.0f64 }
    if pp == 1.0f64 { ret rn }
    if rn >= 2147483647.0f64 { ret special.nan() }
    let n = i64(rn)
    var p = pp
    if 1.0f64 - pp < p { p = 1.0f64 - pp }
    let q = 1.0f64 - p
    let np = f64(n) * p
    let rr = p / q
    let g = rr * f64(n + 1i64)
    var ix = 0i64
    if np < 30.0f64 {
        let qn = pow_di(q, n)
        var go = true
        while go {
            ix = 0i64
            var f = qn
            var u = rng.unif(r)
            var inner = true
            while inner {
                if u < f {
                    go = false
                    inner = false
                } else if ix > 110i64 {
                    inner = false
                } else {
                    u = u - f
                    ix += 1i64
                    f = f * (g / f64(ix) - rr)
                }
            }
        }
    } else {
        let ffm = np + p
        let m = i64(ffm)
        let fm = f64(m)
        let npq = np * q
        let p1 = f64(i64(2.195f64 * sqrt_of(npq) - 4.6f64 * q)) + 0.5f64
        let xm = fm + 0.5f64
        let xl = xm - p1
        let xr = xm + p1
        let c = 0.134f64 + 20.5f64 / (15.3f64 + fm)
        var al = (ffm - xl) / (ffm - xl * p)
        let xll = al * (1.0f64 + 0.5f64 * al)
        al = (xr - ffm) / (xr * q)
        let xlr = al * (1.0f64 + 0.5f64 * al)
        let p2 = p1 * (1.0f64 + c + c)
        let p3 = p2 + c / xll
        let p4 = p3 + c / xlr
        var go = true
        while go {
            let u = rng.unif(r) * p4
            var v = rng.unif(r)
            var skip = false
            var accepted = false
            if u <= p1 {
                ix = i64(xm - p1 * v + u)
                accepted = true
            } else if u <= p2 {
                let x = xl + (u - p1) / c
                v = v * c + 1.0f64 - abs_of(xm - x) / p1
                if v > 1.0f64 || v <= 0.0f64 { skip = true } else { ix = i64(x) }
            } else if u > p3 {
                ix = i64(xr - math.log[f64](v) / xlr)
                if ix > n { skip = true } else { v = v * (u - p3) * xlr }
            } else {
                ix = i64(xl + math.log[f64](v) / xll)
                if ix < 0i64 { skip = true } else { v = v * (u - p2) * xll }
            }
            if !skip && !accepted {
                var k = ix - m
                if k < 0i64 { k = 0i64 - k }
                let kf = f64(k)
                if k <= 20i64 || kf >= npq / 2.0f64 - 1.0f64 {
                    var f = 1.0f64
                    if m < ix {
                        var i = m + 1i64
                        while i <= ix {
                            f = f * (g / f64(i) - rr)
                            i += 1i64
                        }
                    } else if m != ix {
                        var i = ix + 1i64
                        while i <= m {
                            f = f / (g / f64(i) - rr)
                            i += 1i64
                        }
                    }
                    if v <= f { accepted = true }
                } else {
                    let amaxp = (kf / npq) * ((kf * (kf / 3.0f64 + 0.625f64) + 0.1666666666666f64) / npq + 0.5f64)
                    let ynorm = (0.0f64 - kf * kf) / (2.0f64 * npq)
                    let alv = math.log[f64](v)
                    if alv < ynorm - amaxp {
                        accepted = true
                    } else if alv <= ynorm + amaxp {
                        let x1 = f64(ix + 1i64)
                        let f1 = fm + 1.0f64
                        let z = f64(n + 1i64) - fm
                        let w = f64(n - ix) + 1.0f64
                        let z2 = z * z
                        let x2 = x1 * x1
                        let f2 = f1 * f1
                        let w2 = w * w
                        let bound = xm * math.log[f64](f1 / x1) + (f64(n - m) + 0.5f64) * math.log[f64](z / w) + f64(ix - m) * math.log[f64](w * p / (x1 * q)) + (13860.0f64 - (462.0f64 - (132.0f64 - (99.0f64 - 140.0f64 / f2) / f2) / f2) / f2) / f1 / 166320.0f64 + (13860.0f64 - (462.0f64 - (132.0f64 - (99.0f64 - 140.0f64 / z2) / z2) / z2) / z2) / z / 166320.0f64 + (13860.0f64 - (462.0f64 - (132.0f64 - (99.0f64 - 140.0f64 / x2) / x2) / x2) / x2) / x1 / 166320.0f64 + (13860.0f64 - (462.0f64 - (132.0f64 - (99.0f64 - 140.0f64 / w2) / w2) / w2) / w2) / w / 166320.0f64
                        if alv <= bound { accepted = true }
                    }
                }
            }
            if accepted { go = false }
        }
    }
    if pp > 0.5f64 { ix = n - ix }
    ret f64(ix)
}

// rbeta(a, b)
fn rbeta(r: *rng.Rng, aa: f64, bb: f64) -> f64 {
    if aa != aa || bb != bb || aa < 0.0f64 || bb < 0.0f64 { ret special.nan() }
    if !finite(aa) && !finite(bb) { ret 0.5f64 }
    if aa == 0.0f64 && bb == 0.0f64 {
        if rng.unif(r) < 0.5f64 { ret 0.0f64 }
        ret 1.0f64
    }
    if !finite(aa) || bb == 0.0f64 { ret 1.0f64 }
    if !finite(bb) || aa == 0.0f64 { ret 0.0f64 }
    let expmax = 1024.0f64 * 0.693147180559945309417232121458f64
    let dbl_max = 1.7976931348623157e308f64
    var a = aa
    var b = bb
    if bb < aa {
        a = bb
        b = aa
    }
    let alpha = a + b
    if a <= 1.0f64 {
        let beta = 1.0f64 / a
        let delta = 1.0f64 + b - a
        let k1 = delta * (0.0138889f64 + 0.0416667f64 * a) / (b * beta - 0.777778f64)
        let k2 = 0.25f64 + (0.5f64 + 0.25f64 / delta) * a
        var w = 0.0f64
        var go = true
        while go {
            let u1 = rng.unif(r)
            let u2 = rng.unif(r)
            var skip = false
            var z = 0.0f64
            var decided = false
            if u1 < 0.5f64 {
                let y = u1 * u2
                z = u1 * y
                if 0.25f64 * u2 + z - y >= k1 { skip = true }
            } else {
                z = u1 * u1 * u2
                if z <= 0.25f64 {
                    let v = beta * math.log[f64](u1 / (1.0f64 - u1))
                    if v <= expmax {
                        w = b * math.exp[f64](v)
                        if !finite(w) { w = dbl_max }
                    } else {
                        w = dbl_max
                    }
                    go = false
                    decided = true
                } else if z >= k2 {
                    skip = true
                }
            }
            if !skip && !decided {
                let v = beta * math.log[f64](u1 / (1.0f64 - u1))
                if v <= expmax {
                    w = b * math.exp[f64](v)
                    if !finite(w) { w = dbl_max }
                } else {
                    w = dbl_max
                }
                if alpha * (math.log[f64](alpha / (a + w)) + v) - 1.3862944f64 >= math.log[f64](z) { go = false }
            }
        }
        if aa == a { ret a / (a + w) }
        ret w / (a + w)
    }
    let beta = sqrt_of((alpha - 2.0f64) / (2.0f64 * a * b - alpha))
    let gamma = a + 1.0f64 / beta
    var w = 0.0f64
    var go = true
    while go {
        let u1 = rng.unif(r)
        let u2 = rng.unif(r)
        let v = beta * math.log[f64](u1 / (1.0f64 - u1))
        if v <= expmax {
            w = a * math.exp[f64](v)
            if !finite(w) { w = dbl_max }
        } else {
            w = dbl_max
        }
        let z = u1 * u1 * u2
        let rr = gamma * v - 1.3862944f64
        let s = a + rr - w
        if s + 2.609438f64 >= 5.0f64 * z {
            go = false
        } else {
            let t = math.log[f64](z)
            if s > t {
                go = false
            } else if !(rr + alpha * math.log[f64](alpha / (b + w)) < t) {
                go = false
            }
        }
    }
    if aa != a { ret b / (b + w) }
    ret w / (b + w)
}

fn rnbinom(r: *rng.Rng, size0: f64, prob: f64) -> f64 {
    var size = size0
    if !finite(prob) || size != size || size <= 0.0f64 || prob <= 0.0f64 || prob > 1.0f64 { ret special.nan() }
    if !finite(size) { size = 1.7976931348623157e308f64 / 2.0f64 }
    if prob == 1.0f64 { ret 0.0f64 }
    ret rpois(r, rgamma(r, size, (1.0f64 - prob) / prob))
}

fn rnbinom_mu(r: *rng.Rng, size0: f64, mu: f64) -> f64 {
    var size = size0
    if !finite(mu) || size != size || size <= 0.0f64 || mu < 0.0f64 { ret special.nan() }
    if !finite(size) { size = 1.7976931348623157e308f64 / 2.0f64 }
    if mu == 0.0f64 { ret 0.0f64 }
    ret rpois(r, rgamma(r, size, mu / size))
}

fn rgeom(r: *rng.Rng, p: f64) -> f64 {
    if !finite(p) || p <= 0.0f64 || p > 1.0f64 { ret special.nan() }
    ret rpois(r, rng.exp_unit(r) * ((1.0f64 - p) / p))
}

fn rweibull(r: *rng.Rng, shape: f64, scale: f64) -> f64 {
    if !finite(shape) || !finite(scale) || shape <= 0.0f64 || scale <= 0.0f64 {
        if scale == 0.0f64 { ret 0.0f64 }
        ret special.nan()
    }
    ret scale * math.pow[f64](0.0f64 - math.log[f64](rng.unif(r)), 1.0f64 / shape)
}

fn rlnorm(r: *rng.Rng, meanlog: f64, sdlog: f64) -> f64 {
    if meanlog != meanlog || !finite(sdlog) || sdlog < 0.0f64 { ret special.nan() }
    ret math.exp[f64](rng.rnorm(r, meanlog, sdlog))
}

fn rlogis(r: *rng.Rng, location: f64, scale: f64) -> f64 {
    if location != location || !finite(scale) { ret special.nan() }
    if scale == 0.0f64 || !finite(location) { ret location }
    let u = rng.unif(r)
    ret location + scale * math.log[f64](u / (1.0f64 - u))
}

fn rcauchy(r: *rng.Rng, location: f64, scale: f64) -> f64 {
    if location != location || !finite(scale) || scale < 0.0f64 { ret special.nan() }
    if scale == 0.0f64 || !finite(location) { ret location }
    ret location + scale * math.tan[f64](3.141592653589793238462643383280f64 * rng.unif(r))
}
