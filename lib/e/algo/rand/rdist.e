// R's random variate generators over e.algo.rand.r's Mersenne-Twister stream, value for value:
// `rgamma` (Ahrens and Dieter GS and GD), `rchisq`, `rt`, `rbeta` (Cheng's BB and BC), `rbinom`
// (BTPEC), `rpois` (Ahrens and Dieter PD), `rnbinom`, `rgeom`, `rweibull`, `rlnorm`, `rlogis` and
// `rcauchy`, ported from R's nmath. The C code keeps the set-up of the last call in statics; the
// numbers it draws do not depend on them, so each call here sets up again.
//
// Also here: rhyper, rnchisq, rmultinom, rsignrank, rwilcox, sample with prob, rbinom and rhyper
// past INT_MAX (through qbinom and qhyper), and BTPEC's int-wrapped `k * k`.

use e.algo.rand.r as rng
use e.math
use e.math.special as special
use e.math.nmath_beta as nb
use e.mem

error TooBig

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
    if rn >= 2147483647.0f64 { ret nb.qbinom(rng.unif(r), rn, pp, false, false) }
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
                    let kk2 = (0i64 - (i64(kf) * i64(kf)) + 2147483648i64) % 4294967296i64
                    var wrapped = kk2
                    if wrapped < 0i64 { wrapped += 4294967296i64 }
                    let ynorm = f64(wrapped - 2147483648i64) / (2.0f64 * npq)
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

// --- rhyper, rnchisq, rmultinom, rsignrank, rwilcox, sample with prob

// ln(i!) as rhyper.c's afc: a table up to 7, Stirling's series after.
fn afc(i: i64) -> f64 {
    if i < 0i64 { ret -1.0f64 }
    if i == 0i64 || i == 1i64 { ret 0.0f64 }
    if i == 2i64 { ret 0.69314718055994530941723212145817f64 }
    if i == 3i64 { ret 1.79175946922805500081247735838070f64 }
    if i == 4i64 { ret 3.17805383034794561964694160129705f64 }
    if i == 5i64 { ret 4.78749174278204599424770093452324f64 }
    if i == 6i64 { ret 6.57925121201010099506017829290394f64 }
    if i == 7i64 { ret 8.52516136106541430016553103634712f64 }
    let di = f64(i)
    let i2 = di * di
    ret (di + 0.5f64) * math.log[f64](di) - di + 0.918938533204672741780329736406f64 + (0.0833333333333333f64 - 0.00277777777777778f64 / i2) / di
}

fn rhyper(r: *rng.Rng, nn1in0: f64, nn2in0: f64, kkin0: f64) -> f64 {
    if !finite(nn1in0) || !finite(nn2in0) || !finite(kkin0) { ret special.nan() }
    let nn1in = math.round[f64](nn1in0)
    let nn2in = math.round[f64](nn2in0)
    let kkin = math.round[f64](kkin0)
    let nn = nn1in + nn2in
    if nn1in < 0.0f64 || nn2in < 0.0f64 || kkin < 0.0f64 || kkin > nn1in + nn2in { ret special.nan() }
    if nn1in >= 2147483647.0f64 || nn2in >= 2147483647.0f64 || kkin >= 2147483647.0f64 {
        if kkin == 1.0f64 { ret rbinom(r, kkin, nn1in / (nn1in + nn2in)) }
        ret nb.qhyper(rng.unif(r), nn1in, nn2in, kkin, false, false)
    }
    let nn1 = i64(nn1in)
    let nn2 = i64(nn2in)
    let kk = i64(kkin)
    var n1 = nn1
    var n2 = nn2
    if nn1 > nn2 {
        n1 = nn2
        n2 = nn1
    }
    var k = kk
    if f64(kk) + f64(kk) >= nn { k = i64(nn - f64(kk)) }
    let m = i64((f64(k) + 1.0f64) * (f64(n1) + 1.0f64) / (nn + 2.0f64))
    var minjx = 0i64
    if k - n2 > 0i64 { minjx = k - n2 }
    var maxjx = n1
    if k < n1 { maxjx = k }
    var ix = 0i64
    if minjx == maxjx {
        ix = maxjx
    } else if m - minjx < 10i64 {
        let scale = 1.0e25f64
        let con = 57.5646273248511421f64
        var lw = 0.0f64
        if k < n2 {
            lw = afc(n2) + afc(n1 + n2 - k) - afc(n2 - k) - afc(n1 + n2)
        } else {
            lw = afc(n1) + afc(k) - afc(k - n2) - afc(n1 + n2)
        }
        let w = math.exp[f64](lw + con)
        if w <= 0.0f64 { ret special.nan() }
        var go = true
        while go {
            var p = w
            ix = minjx
            var u = rng.unif(r) * scale
            var restart = false
            while u > p && !restart {
                u = u - p
                p = p * ((f64(n1) - f64(ix)) * f64(k - ix))
                ix += 1i64
                p = p / f64(ix) / f64(n2 - k + ix)
                if ix > maxjx { restart = true }
            }
            if !restart { go = false }
        }
    } else {
        let s = sqrt_of((nn - f64(k)) * f64(k) * f64(n1) * f64(n2) / (nn - 1.0f64) / nn / nn)
        let d = f64(i64(1.5f64 * s)) + 0.5f64
        let xl = f64(m) - d + 0.5f64
        let xr = f64(m) + d + 0.5f64
        let a = afc(m) + afc(n1 - m) + afc(k - m) + afc(n2 - k + m)
        let kl = math.exp[f64](a - afc(i64(xl)) - afc(i64(f64(n1) - xl)) - afc(i64(f64(k) - xl)) - afc(i64(f64(n2 - k) + xl)))
        let kr = math.exp[f64](a - afc(i64(xr - 1.0f64)) - afc(i64(f64(n1) - xr + 1.0f64)) - afc(i64(f64(k) - xr + 1.0f64)) - afc(i64(f64(n2 - k) + xr - 1.0f64)))
        let lamdl = 0.0f64 - math.log[f64](xl * (f64(n2 - k) + xl) / (f64(n1) - xl + 1.0f64) / (f64(k) - xl + 1.0f64))
        let lamdr = 0.0f64 - math.log[f64]((f64(n1) - xr + 1.0f64) * (f64(k) - xr + 1.0f64) / xr / (f64(n2 - k) + xr))
        let p1 = d + d
        let p2 = p1 + kl / lamdl
        let p3 = p2 + kr / lamdr
        var reject = true
        var n_uv = 0i64
        while reject {
            let u = rng.unif(r) * p3
            var v = rng.unif(r)
            n_uv += 1i64
            if n_uv >= 10000i64 { ret special.nan() }
            var skip = false
            if u < p1 {
                ix = i64(xl + u)
            } else if u <= p2 {
                ix = i64(xl + math.log[f64](v) / lamdl)
                if ix < minjx { skip = true } else { v = v * (u - p1) * lamdl }
            } else {
                ix = i64(xr - math.log[f64](v) / lamdr)
                if ix > maxjx { skip = true } else { v = v * (u - p2) * lamdr }
            }
            if !skip {
                if m < 100i64 || ix <= 50i64 {
                    var f = 1.0f64
                    if m < ix {
                        var i = m + 1i64
                        while i <= ix {
                            f = f * f64(n1 - i + 1i64) * f64(k - i + 1i64) / f64(n2 - k + i) / f64(i)
                            i += 1i64
                        }
                    } else if m > ix {
                        var i = ix + 1i64
                        while i <= m {
                            f = f * f64(i) * f64(n2 - k + i) / f64(n1 - i + 1i64) / f64(k - i + 1i64)
                            i += 1i64
                        }
                    }
                    if v <= f { reject = false }
                } else {
                    let deltal = 0.0078f64
                    let deltau = 0.0034f64
                    let y = f64(ix)
                    let y1 = y + 1.0f64
                    let ym = y - f64(m)
                    let yn = f64(n1) - y + 1.0f64
                    let yk = f64(k) - y + 1.0f64
                    let nk = f64(n2 - k) + y1
                    let rr = (0.0f64 - ym) / y1
                    let ss = ym / yn
                    let tt = ym / yk
                    let ee = (0.0f64 - ym) / nk
                    let g = yn * yk / (y1 * nk) - 1.0f64
                    var dg = 1.0f64
                    if g < 0.0f64 { dg = 1.0f64 + g }
                    let gu = g * (1.0f64 + g * (-0.5f64 + g / 3.0f64))
                    let gl = gu - 0.25f64 * (g * g * g * g) / dg
                    let xm = f64(m) + 0.5f64
                    let xn = f64(n1 - m) + 0.5f64
                    let xk = f64(k - m) + 0.5f64
                    let nm = f64(n2 - k) + xm
                    let ub = y * gu - f64(m) * gl + deltau + xm * rr * (1.0f64 + rr * (-0.5f64 + rr / 3.0f64)) + xn * ss * (1.0f64 + ss * (-0.5f64 + ss / 3.0f64)) + xk * tt * (1.0f64 + tt * (-0.5f64 + tt / 3.0f64)) + nm * ee * (1.0f64 + ee * (-0.5f64 + ee / 3.0f64))
                    let alv = math.log[f64](v)
                    if alv > ub {
                        reject = true
                    } else {
                        var dr = xm * (rr * rr * rr * rr)
                        if rr < 0.0f64 { dr = dr / (1.0f64 + rr) }
                        var ds = xn * (ss * ss * ss * ss)
                        if ss < 0.0f64 { ds = ds / (1.0f64 + ss) }
                        var dt = xk * (tt * tt * tt * tt)
                        if tt < 0.0f64 { dt = dt / (1.0f64 + tt) }
                        var de = nm * (ee * ee * ee * ee)
                        if ee < 0.0f64 { de = de / (1.0f64 + ee) }
                        if alv < ub - 0.25f64 * (dr + ds + dt + de) + (y + f64(m)) * (gl - gu) - deltal {
                            reject = false
                        } else if alv <= a - afc(ix) - afc(n1 - ix) - afc(k - ix) - afc(n2 - k + ix) {
                            reject = false
                        } else {
                            reject = true
                        }
                    }
                }
            }
        }
    }
    if f64(kk) + f64(kk) >= nn {
        if nn1 > nn2 { ix = kk - nn2 + ix } else { ix = nn1 - ix }
    } else if nn1 > nn2 {
        ix = kk - ix
    }
    ret f64(ix)
}

fn rnchisq(r: *rng.Rng, df: f64, lambda: f64) -> f64 {
    if df != df || !finite(lambda) || df < 0.0f64 || lambda < 0.0f64 { ret special.nan() }
    if lambda == 0.0f64 {
        if df == 0.0f64 { ret 0.0f64 }
        ret rgamma(r, df / 2.0f64, 2.0f64)
    }
    var x = rpois(r, lambda / 2.0f64)
    if x > 0.0f64 { x = rchisq(r, 2.0f64 * x) }
    if df > 0.0f64 { x = x + rgamma(r, df / 2.0f64, 2.0f64) }
    ret x
}

fn rsignrank(r: *rng.Rng, n0: f64) -> f64 {
    if n0 != n0 { ret n0 }
    let n = math.round[f64](n0)
    if n < 0.0f64 { ret special.nan() }
    if n == 0.0f64 { ret 0.0f64 }
    var total = 0.0f64
    let k = i64(n)
    var i = 0i64
    while i < k {
        i += 1i64
        total = total + f64(i) * math.floor[f64](rng.unif(r) + 0.5f64)
    }
    ret total
}

fn rwilcox(a: *mem.Arena, r: *rng.Rng, m0: f64, n0: f64) -> f64 {
    if m0 != m0 || n0 != n0 { ret m0 + n0 }
    let m = math.round[f64](m0)
    let n = math.round[f64](n0)
    if m < 0.0f64 || n < 0.0f64 { ret special.nan() }
    if m == 0.0f64 || n == 0.0f64 { ret 0.0f64 }
    if m + n > 2147483647.0f64 { ret special.nan() }
    var k = i64(m + n)
    let (x, e) = mem.alloc[i64](a, usize(k) + 1usize)
    if e != ok { ret special.nan() }
    var i = 0i64
    while i < k {
        x[usize(i)] = i
        i += 1i64
    }
    var total = 0.0f64
    i = 0i64
    while f64(i) < n {
        let j = i64(rng.unif_index(r, f64(k)))
        total = total + f64(x[usize(j)])
        k -= 1i64
        x[usize(j)] = x[usize(k)]
        i += 1i64
    }
    ret total - n * (n - 1.0f64) / 2.0f64
}

// a * b as the sum of two doubles, exactly (Dekker's split).
fn two_prod(a: f64, b: f64) -> (f64, f64) {
    let p = a * b
    let ta = 134217729.0f64 * a
    let ah = ta - (ta - a)
    let al = a - ah
    let tb = 134217729.0f64 * b
    let bh = tb - (tb - b)
    let bl = b - bh
    let e = ((ah * bh - p) + ah * bl + al * bh) + al * bl
    ret (p, e)
}

// rmultinom(1, n, prob): the counts of one draw (prob should sum to 1). The running total of the
// remaining probability is a double-double, standing in for R's long double.
fn rmultinom(a: *mem.Arena, r: *rng.Rng, n0: i64, prob: []const f64) -> ([]i64, err) {
    var none: []i64 = zero
    let kk = prob.len
    let (out, e) = mem.alloc[i64](a, kk + 1usize)
    if e != ok { ret (none, e) }
    var k = 0usize
    while k < kk {
        out[k] = 0i64
        k += 1usize
    }
    if kk < 1usize || n0 < 0i64 { ret (none, TooBig) }
    var hi = 0.0f64
    var lo = 0.0f64
    k = 0usize
    while k < kk {
        let pp = prob[k]
        if !finite(pp) || pp < 0.0f64 || pp > 1.0f64 { ret (none, TooBig) }
        let t = hi + pp
        let bb = t - hi
        lo = lo + ((hi - (t - bb)) + (pp - bb))
        hi = t
        k += 1usize
    }
    let total0 = hi + lo
    var diff = total0 - 1.0f64
    if diff < 0.0f64 { diff = 0.0f64 - diff }
    if diff > 0.0000001f64 { ret (none, TooBig) }
    var n = n0
    if n == 0i64 { ret (out[0usize..kk], ok) }
    if kk == 1usize && total0 == 0.0f64 { ret (out[0usize..kk], ok) }
    k = 0usize
    while k + 1usize < kk {
        if prob[k] != 0.0f64 {
            // pp = prob[k] / p_tot with p_tot = hi + lo, one correction for the low word
            let q1 = prob[k] / hi
            let (ph, pe) = two_prod(q1, hi)
            let resid = ((prob[k] - ph) - pe) - q1 * lo
            let pp = q1 + resid / hi
            if pp < 1.0f64 {
                out[k] = i64(rbinom(r, f64(n), pp))
            } else {
                out[k] = n
            }
            n -= out[k]
        } else {
            out[k] = 0i64
        }
        if n <= 0i64 { ret (out[0usize..kk], ok) }
        let t = hi - prob[k]
        let bb = t - hi
        lo = lo + ((hi - (t - bb)) + (0.0f64 - prob[k] - bb))
        hi = t
        k += 1usize
    }
    out[kk - 1usize] = n
    ret (out[0usize..kk], ok)
}

// sample.int(n, size, replace, prob): 1-based; revsort's heap sort for the order of ties and Walker's
// alias method when more than 200 of the n * p are above 0.1, as R's do_sample does.
fn sample_prob(a: *mem.Arena, r: *rng.Rng, n: usize, size: usize, replace: bool, prob: []const f64) -> ([]i64, err) {
    var none: []i64 = zero
    if prob.len != n { ret (none, TooBig) }
    if !replace && size > n { ret (none, TooBig) }
    let (p, pe) = mem.alloc[f64](a, n + 1usize)
    let (perm, ppe) = mem.alloc[i64](a, n + 1usize)
    let (ans, ae) = mem.alloc[i64](a, size + 1usize)
    if pe != ok { ret (none, pe) }
    if ppe != ok { ret (none, ppe) }
    if ae != ok { ret (none, ae) }
    var sum = 0.0f64
    var npos = 0usize
    var i = 0usize
    while i < n {
        if !finite(prob[i]) || prob[i] < 0.0f64 { ret (none, TooBig) }
        if prob[i] > 0.0f64 {
            npos += 1usize
            sum = sum + prob[i]
        }
        i += 1usize
    }
    if npos == 0usize || (!replace && size > npos) { ret (none, TooBig) }
    i = 0usize
    while i < n {
        p[i] = prob[i] / sum
        perm[i] = i64(i) + 1i64
        i += 1usize
    }
    let draw_with_replacement = replace || size < 2usize
    var nc = 0usize
    i = 0usize
    while i < n {
        if f64(n) * p[i] > 0.1f64 { nc += 1usize }
        i += 1usize
    }
    if replace && nc > 200usize {
        // Walker's alias method
        let (q, qe) = mem.alloc[f64](a, n + 1usize)
        let (hl, hle) = mem.alloc[i64](a, n + 1usize)
        let (alias, ale) = mem.alloc[i64](a, n + 1usize)
        if qe != ok { ret (none, qe) }
        if hle != ok { ret (none, hle) }
        if ale != ok { ret (none, ale) }
        var h = -1i64
        var l = i64(n)
        i = 0usize
        while i < n {
            q[i] = p[i] * f64(n)
            alias[i] = 0i64
            if q[i] < 1.0f64 {
                h += 1i64
                hl[usize(h)] = i64(i)
            } else {
                l -= 1i64
                hl[usize(l)] = i64(i)
            }
            i += 1usize
        }
        if h >= 0i64 && l < i64(n) {
            var k = 0usize
            var brk = false
            while k + 1usize < n && !brk {
                let ii = hl[k]
                let jj = hl[usize(l)]
                alias[usize(ii)] = jj
                q[usize(jj)] = q[usize(jj)] + (q[usize(ii)] - 1.0f64)
                if q[usize(jj)] < 1.0f64 { l += 1i64 }
                if l >= i64(n) { brk = true }
                k += 1usize
            }
        }
        var s2 = 0usize
        while s2 < size {
            let kk = usize(i64(rng.unif_index(r, f64(n))))
            let ru = rng.unif(r)
            if ru < q[kk] { ans[s2] = i64(kk) + 1i64 } else { ans[s2] = alias[kk] + 1i64 }
            s2 += 1usize
        }
        ret (ans[0usize..size], ok)
    }
    // revsort: p descending with perm along, R's heap sort (the order of ties is its own)
    if n > 1usize {
        var l2 = n / 2usize + 1usize
        var ir = n
        var go = true
        while go {
            var ra = 0.0f64
            var ii = 0i64
            if l2 > 1usize {
                l2 -= 1usize
                ra = p[l2 - 1usize]
                ii = perm[l2 - 1usize]
            } else {
                ra = p[ir - 1usize]
                ii = perm[ir - 1usize]
                p[ir - 1usize] = p[0usize]
                perm[ir - 1usize] = perm[0usize]
                ir -= 1usize
                if ir == 1usize {
                    p[0usize] = ra
                    perm[0usize] = ii
                    go = false
                }
            }
            if go {
                var ci = l2
                var cj = l2 * 2usize
                while cj <= ir {
                    if cj < ir && p[cj - 1usize] > p[cj] { cj += 1usize }
                    if ra > p[cj - 1usize] {
                        p[ci - 1usize] = p[cj - 1usize]
                        perm[ci - 1usize] = perm[cj - 1usize]
                        ci = cj
                        cj += ci
                    } else {
                        cj = ir + 1usize
                    }
                }
                p[ci - 1usize] = ra
                perm[ci - 1usize] = ii
            }
        }
    }
    if draw_with_replacement {
        i = 1usize
        while i < n {
            p[i] = p[i] + p[i - 1usize]
            i += 1usize
        }
        var s = 0usize
        while s < size {
            let ru = rng.unif(r)
            var j = 0usize
            while j + 1usize < n && ru > p[j] { j += 1usize }
            ans[s] = perm[j]
            s += 1usize
        }
        ret (ans[0usize..size], ok)
    }
    var totalmass = 1.0f64
    var n1 = n - 1usize
    var s = 0usize
    while s < size {
        let rtm = totalmass * rng.unif(r)
        var mass = 0.0f64
        var j = 0usize
        while j < n1 {
            mass = mass + p[j]
            if rtm <= mass { break }
            j += 1usize
        }
        ans[s] = perm[j]
        totalmass = totalmass - p[j]
        var q = j
        while q < n1 {
            p[q] = p[q + 1usize]
            perm[q] = perm[q + 1usize]
            q += 1usize
        }
        if n1 > 0usize { n1 -= 1usize }
        s += 1usize
    }
    ret (ans[0usize..size], ok)
}
