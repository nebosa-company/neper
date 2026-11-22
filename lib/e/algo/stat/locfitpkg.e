// R locfit (1.5-9.12) for one predictor, ported from the package's C source: local polynomial regression and
// local likelihood (gaussian, binomial, poisson, gamma, geometric, weibull, circular, huber, cauchy, probab and the r/q forms, with their links, prior weights), degree 0 to 3, nearest-neighbour
// bandwidth nn and fixed bandwidth h (together: the larger), ten kernels, and the four evaluation
// structures dat (ev = dat()), tree (the default rbox(), the adaptive tree), kdtree and grid with cubic
// Hermite interpolation between the fitted vertices, as R's fitted() and predict() do.
//
// A vertex is a 12-wide record in the table `vt` (the V_ constants): the fit at one point, with the local
// slope, the variance norm nlx, the influence norm t0 and their slopes, the local likelihood and the two
// traces behind the local degrees of freedom. `summ` gives the fit's likelihood, degrees of freedom and
// residual variance (R's gcv(), cp(), aic()); `se` the standard errors of predict(se.fit = TRUE).
//
// sp, the settings: 0 kernel (R's integer: 1 rect, 2 epan, 3 bisq, 4 tcub, 5 trwt, 6 gauss, 7 tria, 8 quqt,
// 9 6cub, 11 expl), 1 deg, 2 family (0 gaussian, 1 binomial, 2 poisson, 3 gamma, 4 geometric, 5 weibull, 6 circular, 7 huber,
// 8 cauchy, 9 probab), 3 nn, 4 h, 5 ev (0 tree, 2 dat,
// 3 grid, 4 kdtree), 6 cut, 7 grid points, 8 quasi (1: estimate the residual variance), 9 acri (1 cp, 2 ici, 3 mindex, 4 ok),
// 10 adpen, 11 fixed k, 12 link, 13 robust (R's r prefix); the response array holds y then the prior weights.
//
// Not here: several predictors, the density, rate and hazard families, censoring, base offsets, scale and angular
// styles, derivative fits, degree orders, the global robust scale of quasi huber and cauchy (summaries only), phull
// and kdcenter structures.

use e.math
use e.mem



const VS: usize = 17usize
const V_X: usize = 0usize
const V_H: usize = 1usize
const V_C0: usize = 2usize
const V_C1: usize = 3usize
const V_N0: usize = 4usize
const V_N1: usize = 5usize
const V_T0: usize = 6usize
const V_T1: usize = 7usize
const V_LIK: usize = 8usize
const V_TR0: usize = 9usize
const V_TR2: usize = 10usize
const V_ST: usize = 11usize
const V_S1: usize = 12usize
const V_S5: usize = 13usize
const V_RAW: usize = 14usize
const V_M: usize = 15usize
const V_MM: usize = 16usize

const W_COEF: usize = 0usize
const W_NLX: usize = 1usize
const W_T0: usize = 2usize
const W_LIK: usize = 3usize
const W_RDF: usize = 4usize

error TooManyVertices

type Jac = struct { z: []f64, q: []f64, wk: []f64, dg: []f64, p: usize, dec: bool }

type Des = struct { m: usize, p: usize, x: []f64, w: []f64, y: []const f64, pw: []const f64, sc: []f64, th: []f64, fam: usize, rs: f64, qs: usize, s0: f64, llk: f64, status: usize }

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn wk(u0: f64, kern: usize) -> f64 {
    var u = math.abs[f64](u0)
    if kern == 1usize {
        if u > 1.0f64 { ret 0.0f64 }
        ret 1.0f64
    }
    if kern == 2usize {
        if u > 1.0f64 { ret 0.0f64 }
        ret 1.0f64 - u * u
    }
    if kern == 3usize {
        if u > 1.0f64 { ret 0.0f64 }
        u = 1.0f64 - u * u
        ret u * u
    }
    if kern == 4usize {
        if u > 1.0f64 { ret 0.0f64 }
        u = 1.0f64 - u * u * u
        ret u * u * u
    }
    if kern == 5usize {
        if u > 1.0f64 { ret 0.0f64 }
        u = 1.0f64 - u * u
        ret u * u * u
    }
    if kern == 6usize {
        let g = 2.5f64 * u
        ret math.exp[f64](0.0f64 - g * g / 2.0f64)
    }
    if kern == 7usize {
        if u > 1.0f64 { ret 0.0f64 }
        ret 1.0f64 - u
    }
    if kern == 8usize {
        if u > 1.0f64 { ret 0.0f64 }
        u = 1.0f64 - u * u
        ret u * u * u * u
    }
    if kern == 9usize {
        if u > 1.0f64 { ret 0.0f64 }
        u = 1.0f64 - u * u * u
        u = u * u * u
        ret u * u
    }
    ret math.exp[f64](0.0f64 - 3.0f64 * u)
}

fn expit(x: f64) -> f64 {
    if x < 0.0f64 {
        let u = math.exp[f64](x)
        ret u / (1.0f64 + u)
    }
    ret 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - x))
}

fn lf_exp(x: f64) -> f64 {
    if x > 700.0f64 { ret 1.014232054735004e+304f64 }
    ret math.exp[f64](x)
}

// the family code of sp: the family sp[2] (0 gaussian, 1 binomial, 2 poisson, 3 gamma, 4 geometric, 5 weibull,
// 6 circular, 7 huber, 8 cauchy, 9 probab) plus 16 times the link (R's integers: 3 identity, 4 log, 5 logit,
// 6 inverse, 7 sqrt, 8 arcsin; sp[12] = 0, 1 or 2 is the family's default) plus 256 for a robust family (sp[13]
// = 1, R's r prefix)
fn famcode(sp: []const f64) -> usize {
    let fam = usize(sp[2usize])
    var lin = usize(sp[12usize])
    if lin < 3usize {
        lin = 4usize
        if fam == 0usize || fam == 6usize || fam == 7usize || fam == 8usize { lin = 3usize }
        if fam == 1usize { lin = 5usize }
        if fam == 3usize && usize(sp[12usize]) == 2usize { lin = 6usize }
    }
    var rob = 0usize
    if sp.len > 13usize && sp[13usize] == 1.0f64 { rob = 1usize }
    ret fam + 16usize * lin + 256usize * rob
}

fn invlink(th: f64, lin: usize) -> f64 {
    if lin == 3usize { ret th }
    if lin == 4usize { ret lf_exp(th) }
    if lin == 5usize { ret expit(th) }
    if lin == 6usize { ret 1.0f64 / th }
    if lin == 7usize { ret th * math.abs[f64](th) }
    ret math.sin[f64](th) * math.sin[f64](th)
}

// the response scale of predict() for the family code: R's trans
fn trans(fc: usize, th: f64) -> f64 {
    let lin = (fc / 16usize) % 16usize
    if lin == 7usize {
        if th < 0.0f64 { ret 0.0f64 }
        ret th * th
    }
    if lin == 8usize {
        let s = math.sin[f64](th)
        if s < 0.0f64 { ret 0.0f64 }
        ret s * s
    }
    ret invlink(th, lin)
}

// robustify: the Huber-type cap on the deviance with scale rs
fn robustify(r: []f64, rs: f64) {
    let sc = rs * 2.0f64
    if r[0usize] > 0.0f64 - sc * sc / 2.0f64 {
        r[0usize] = r[0usize] / (sc * sc)
        r[2usize] = r[2usize] / (sc * sc)
        r[3usize] = r[3usize] / (sc * sc)
        ret
    }
    let z = math.sqrt[f64](0.0f64 - 2.0f64 * r[0usize])
    r[3usize] = ((0.0f64 - sc) * r[2usize] * r[2usize] / (z * z * z) + sc * r[3usize] / z) / (sc * sc)
    r[2usize] = r[2usize] * (1.0f64 / (z * sc))
    r[0usize] = 0.5f64 - z / sc
}

// r = (likelihood, mean, first and second derivative of the log likelihood in theta) for one observation with
// prior weight w and robust scale rs; the status: 0 ok, 81 bad parameters (LF_BADP), 82 link invalid for the family
fn links0(fc: usize, th: f64, y: f64, w: f64, rs: f64, r: []f64) -> usize {
    let fam = fc % 16usize
    let lin = (fc / 16usize) % 16usize
    let mean = invlink(th, lin)
    r[1usize] = mean
    if fam == 0usize {
        let z = y - mean
        r[0usize] = 0.0f64 - w * z * z / 2.0f64
        if lin == 3usize {
            r[2usize] = w * z
            r[3usize] = w
            ret 0usize
        }
        if lin == 4usize {
            r[2usize] = w * z * mean
            r[3usize] = w * mean * mean
            ret 0usize
        }
        if lin == 5usize {
            r[2usize] = w * z * mean * (1.0f64 - mean)
            r[3usize] = w * mean * mean * (1.0f64 - mean) * (1.0f64 - mean)
            ret 0usize
        }
        ret 82usize
    }
    if fam == 1usize {
        let wp = w * mean
        if lin == 3usize {
            if mean <= 0.0f64 && y > 0.0f64 { ret 81usize }
            if mean >= 1.0f64 && y < w { ret 81usize }
            r[0usize] = 0.0f64
            r[2usize] = 0.0f64
            r[3usize] = 0.0f64
            if y > 0.0f64 {
                r[0usize] += y * math.log[f64](wp / y)
                r[2usize] += y / mean
                r[3usize] += y / (mean * mean)
            }
            if y < w {
                r[0usize] += (w - y) * math.log[f64]((w - wp) / (w - y))
                r[2usize] -= (w - y) / (1.0f64 - mean)
                r[3usize] += (w - y) / ((1.0f64 - mean) * (1.0f64 - mean))
            }
            ret 0usize
        }
        if lin == 5usize {
            if y < 0.0f64 || y > w {
                r[0usize] = 0.0f64
                r[2usize] = 0.0f64
                r[3usize] = 0.0f64
                ret 0usize
            }
            var lk = 0.0f64
            if th < 0.0f64 { lk = th * y - w * math.log[f64](1.0f64 + math.exp[f64](th)) } else { lk = th * (y - w) - w * math.log[f64](1.0f64 + math.exp[f64](0.0f64 - th)) }
            if y > 0.0f64 { lk -= y * math.log[f64](y / w) }
            if y < w { lk -= (w - y) * math.log[f64](1.0f64 - y / w) }
            r[0usize] = lk
            r[2usize] = y - wp
            r[3usize] = wp * (1.0f64 - mean)
            ret 0usize
        }
        if lin == 8usize {
            if mean <= 0.0f64 && y > 0.0f64 { ret 81usize }
            if mean >= 1.0f64 && y < w { ret 81usize }
            if th < 0.0f64 || th > 1.5707963267948966f64 { ret 81usize }
            r[0usize] = 0.0f64
            r[2usize] = 0.0f64
            r[3usize] = 0.0f64
            if y > 0.0f64 {
                r[2usize] += 2.0f64 * y * math.sqrt[f64]((1.0f64 - mean) / mean)
                r[0usize] += y * math.log[f64](wp / y)
            }
            if y < w {
                r[2usize] -= 2.0f64 * (w - y) * math.sqrt[f64](mean / (1.0f64 - mean))
                r[0usize] += (w - y) * math.log[f64]((w - wp) / (w - y))
            }
            r[3usize] = 4.0f64 * w
            ret 0usize
        }
        ret 82usize
    }
    if fam == 2usize || fam == 9usize {
        let wmu = w * mean
        if lin == 4usize {
            if y < 0.0f64 {
                r[0usize] = 0.0f64
                r[2usize] = 0.0f64
                r[3usize] = 0.0f64
                ret 0usize
            }
            var lk = y - wmu
            r[2usize] = y - wmu
            if y > 0.0f64 { lk += y * (th - math.log[f64](y / w)) }
            r[0usize] = lk
            r[3usize] = wmu
            ret 0usize
        }
        if mean <= 0.0f64 && y > 0.0f64 { ret 81usize }
        var lk = y - wmu
        if lin == 3usize {
            r[2usize] = 0.0f64 - w
            r[3usize] = 0.0f64
            if y > 0.0f64 {
                lk += y * math.log[f64](wmu / y)
                r[2usize] += y / mean
                r[3usize] = y / (mean * mean)
            }
            r[0usize] = lk
            ret 0usize
        }
        if lin == 7usize {
            r[2usize] = 0.0f64 - 2.0f64 * w * th
            r[3usize] = 2.0f64 * w
            if y > 0.0f64 {
                lk += y * math.log[f64](wmu / y)
                r[2usize] += 2.0f64 * y / th
                r[3usize] += 2.0f64 * y / mean
            }
            r[0usize] = lk
            ret 0usize
        }
        ret 82usize
    }
    if fam == 3usize {
        if mean <= 0.0f64 && y > 0.0f64 { ret 81usize }
        if lin == 4usize {
            var lk = 0.0f64 - y / mean + w * (1.0f64 - th)
            if y > 0.0f64 { lk += w * math.log[f64](y / w) }
            r[0usize] = lk
            r[2usize] = y / mean - w
            r[3usize] = y / mean
            ret 0usize
        }
        if lin == 6usize || lin == 3usize {
            var lk = 0.0f64 - y / mean + w - w * math.log[f64](mean)
            if y > 0.0f64 { lk += w * math.log[f64](y / w) }
            r[0usize] = lk
            if lin == 6usize {
                r[2usize] = 0.0f64 - y + w * mean
                r[3usize] = w * mean * mean
            } else {
                r[2usize] = (y - mean) / (mean * mean)
                r[3usize] = w / (mean * mean)
            }
            ret 0usize
        }
        ret 82usize
    }
    if fam == 4usize {
        let p = 1.0f64 / (1.0f64 + mean)
        var lk = (y + w) * math.log[f64]((y / w + 1.0f64) / (mean + 1.0f64))
        if y > 0.0f64 { lk += y * math.log[f64](w * mean / y) }
        r[0usize] = lk
        if lin == 4usize {
            r[2usize] = (y - w * mean) * p
            r[3usize] = (y + w) * p * (1.0f64 - p)
            ret 0usize
        }
        if lin == 3usize {
            r[2usize] = (y - w * mean) / (mean * (1.0f64 + mean))
            r[3usize] = w / (mean * (1.0f64 + mean))
            ret 0usize
        }
        ret 82usize
    }
    if fam == 5usize {
        let yy = math.pow[f64](y, w)
        var lk = 1.0f64 - yy / mean - th
        if yy > 0.0f64 { lk += math.log[f64](w * yy) }
        r[0usize] = lk
        r[2usize] = 0.0f64 - 1.0f64 + yy / mean
        r[3usize] = yy / mean
        ret 0usize
    }
    if fam == 6usize {
        r[2usize] = w * math.sin[f64](y - mean)
        r[3usize] = w * math.cos[f64](y - mean)
        r[0usize] = r[3usize] - w
        ret 0usize
    }
    if fam == 7usize {
        var sw = 1.0f64
        if w != 1.0f64 { sw = math.sqrt[f64](w) }
        let z = sw * (y - mean) / rs
        var az = z
        if az < 0.0f64 { az = 0.0f64 - az }
        if az < 2.0f64 { r[0usize] = 0.0f64 - z * z / 2.0f64 } else { r[0usize] = 2.0f64 * (1.0f64 - az) }
        if z < 0.0f64 - 2.0f64 {
            r[2usize] = 0.0f64 - sw * 2.0f64 / rs
            r[3usize] = 0.0f64
            ret 0usize
        }
        if z > 2.0f64 {
            r[2usize] = sw * 2.0f64 / rs
            r[3usize] = 0.0f64
            ret 0usize
        }
        r[2usize] = sw * z / rs
        r[3usize] = w / (rs * rs)
        ret 0usize
    }
    if fam == 8usize {
        if lin != 3usize { ret 82usize }
        let z = w * (y - th) / rs
        r[0usize] = 0.0f64 - math.log[f64](1.0f64 + z * z)
        r[2usize] = 2.0f64 * w * z / (rs * (1.0f64 + z * z))
        r[3usize] = 2.0f64 * w * w * (1.0f64 - z * z) / (rs * rs * (1.0f64 + z * z) * (1.0f64 + z * z))
        ret 0usize
    }
    ret 82usize
}

// links0 with the robust cap of the r families (R's links)
fn links(fc: usize, th: f64, y: f64, w: f64, rs: f64, r: []f64) -> usize {
    let st = links0(fc % 256usize, th, y, w, rs, r)
    if st != 0usize { ret st }
    let fam = fc % 16usize
    if fc >= 256usize && fam != 5usize && fam != 7usize && fam != 8usize { robustify(r, rs) }
    ret 0usize
}

// Jacobi eigen-decomposition of the symmetric d x d matrix x (row-major, left diagonal), vectors in pm
fn eig_dec(x: []f64, pm: []f64, d: usize) {
    var i = 0usize
    while i < d {
        var j = 0usize
        while j < d {
            pm[i * d + j] = 0.0f64
            if i == j { pm[i * d + j] = 1.0f64 }
            j += 1usize
        }
        i += 1usize
    }
    var iter = 0usize
    while iter < 20usize {
        var ms = false
        i = 0usize
        while i < d {
            var j = i + 1usize
            while j < d {
                let xij = x[i * d + j]
                if xij * xij > 1.0e-15f64 * math.abs[f64](x[i * d + i] * x[j * d + j]) {
                    var c = (x[j * d + j] - x[i * d + i]) / 2.0f64
                    var s = 0.0f64 - xij
                    let r = math.sqrt[f64](c * c + s * s)
                    c = c / r
                    var sg = 0.0f64 - 1.0f64
                    if s > 0.0f64 { sg = 1.0f64 }
                    s = math.sqrt[f64]((1.0f64 - c) / 2.0f64) * sg
                    c = math.sqrt[f64]((1.0f64 + c) / 2.0f64)
                    var k = 0usize
                    while k < d {
                        let u = x[i * d + k]
                        let v = x[j * d + k]
                        x[i * d + k] = u * c + v * s
                        x[j * d + k] = v * c - u * s
                        k += 1usize
                    }
                    k = 0usize
                    while k < d {
                        let u = x[k * d + i]
                        let v = x[k * d + j]
                        x[k * d + i] = u * c + v * s
                        x[k * d + j] = v * c - u * s
                        k += 1usize
                    }
                    x[i * d + j] = 0.0f64
                    x[j * d + i] = 0.0f64
                    k = 0usize
                    while k < d {
                        let u = pm[k * d + i]
                        let v = pm[k * d + j]
                        pm[k * d + i] = u * c + v * s
                        pm[k * d + j] = v * c - u * s
                        k += 1usize
                    }
                    ms = true
                }
                j += 1usize
            }
            i += 1usize
        }
        if !ms { ret }
        iter += 1usize
    }
}

fn jac_dec(j: *Jac) {
    if j.dec { ret }
    let p = j.p
    var i = 0usize
    while i < p {
        let zi = j.z[i * (p + 1usize)]
        j.dg[i] = 0.0f64
        if zi > 0.0f64 { j.dg[i] = 1.0f64 / math.sqrt[f64](zi) }
        i += 1usize
    }
    i = 0usize
    while i < p {
        var c = 0usize
        while c < p {
            j.z[i * p + c] = j.z[i * p + c] * (j.dg[i] * j.dg[c])
            c += 1usize
        }
        i += 1usize
    }
    eig_dec(j.z, j.q, p)
    j.dec = true
}

// v <- (X^T W X)^-1 v by the scaled eigen-decomposition; the rank
fn jac_solve(j: *Jac, v: []f64) -> usize {
    jac_dec(j)
    let p = j.p
    var i = 0usize
    while i < p {
        v[i] = v[i] * j.dg[i]
        i += 1usize
    }
    var mx = j.z[0usize]
    i = 1usize
    while i < p {
        if j.z[i * (p + 1usize)] > mx { mx = j.z[i * (p + 1usize)] }
        i += 1usize
    }
    let tol = 1.0e-8f64 * mx
    var rank = 0usize
    i = 0usize
    while i < p {
        var s = 0.0f64
        var c = 0usize
        while c < p {
            s += j.q[c * p + i] * v[c]
            c += 1usize
        }
        j.wk[i] = s
        i += 1usize
    }
    i = 0usize
    while i < p {
        if j.z[i * p + i] > tol {
            j.wk[i] = j.wk[i] / j.z[i * (p + 1usize)]
            rank += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        var s = 0.0f64
        var c = 0usize
        while c < p {
            s += j.q[i * p + c] * j.wk[c]
            c += 1usize
        }
        v[i] = s
        i += 1usize
    }
    i = 0usize
    while i < p {
        v[i] = v[i] * j.dg[i]
        i += 1usize
    }
    ret rank
}

// the local likelihood, its gradient f1 and information jj.z at coef; the status codes are NR_OK 0,
// NR_BREAK 2, NR_REDUCE 3, the design's status LF_OK 0, LF_OOB 2, LF_PF 3. lk[0] receives the likelihood.
fn likereg(d: *Des, jj: *Jac, coef: []f64, f1: []f64, lk: []f64, r: []f64) -> usize {
    let p = d.p
    d.status = 0usize
    var l = 0.0f64
    var c = 0usize
    while c < p * p {
        jj.z[c] = 0.0f64
        c += 1usize
    }
    c = 0usize
    while c < p {
        f1[c] = 0.0f64
        c += 1usize
    }
    var i = 0usize
    while i < d.m {
        var t = 0.0f64
        c = 0usize
        while c < p {
            t += coef[c] * d.x[i * p + c]
            c += 1usize
        }
        d.th[i] = t
        let ls = links(d.fam, t, d.y[i], d.pw[i], d.rs, r)
        if ls == 81usize {
            d.status = 81usize
            lk[0usize] = 0.0f64 - 1.0e300f64
            ret 3usize
        }
        if ls != 0usize {
            d.status = ls
            ret 2usize
        }
        let ww = d.w[i]
        l += ww * r[0usize]
        c = 0usize
        while c < p {
            f1[c] += d.x[i * p + c] * ww * r[2usize]
            c += 1usize
        }
        let cc = ww * r[3usize]
        var a1 = 0usize
        while a1 < p {
            var a2 = 0usize
            while a2 < p {
                jj.z[a1 * p + a2] += cc * d.x[i * p + a1] * d.x[i * p + a2]
                a2 += 1usize
            }
            a1 += 1usize
        }
        i += 1usize
    }
    jj.dec = false
    lk[0usize] = l
    d.llk = l
    let fam = d.fam % 16usize
    let lin = (d.fam / 16usize) % 16usize
    if fam == 0usize && lin == 3usize && d.fam < 256usize { ret 2usize }
    if fam == 2usize || fam == 3usize || fam == 4usize || fam == 5usize {
        if lin == 4usize && math.abs[f64](coef[0usize]) > 700.0f64 {
            d.status = 2usize
            ret 3usize
        }
        if l > 0.0f64 - 1.0e-5f64 * d.s0 {
            d.status = 3usize
            ret 3usize
        }
    }
    if fam == 1usize {
        if l > 0.0f64 - 1.0e-5f64 * d.s0 {
            d.status = 3usize
            ret 3usize
        }
        if math.abs[f64](coef[0usize]) > 700.0f64 {
            d.status = 2usize
            ret 3usize
        }
    }
    ret 0usize
}

// Newton-Raphson with step halving, as max_nr
fn max_nr(d: *Des, jj: *Jac, cf: []f64, oc: []f64, f1: []f64, delta: []f64, tol: f64, r: []f64) {
    let p = d.p
    var lka = [1]f64{ 0.0f64 }
    let lk = lka[0usize..1usize]
    var fr = likereg(d, jj, cf, f1, lk, r)
    var f = lk[0usize]
    var it = 0usize
    while it < 20usize {
        var i = 0usize
        while i < p {
            oc[i] = cf[i]
            i += 1usize
        }
        let old_f = f
        let rank = jac_solve(jj, f1)
        i = 0usize
        while i < p {
            delta[i] = f1[i]
            i += 1usize
        }
        if rank == 0usize { delta[0usize] = (0.0f64 - f) / f1[0usize] }
        var lambda = 1.0f64
        var nc = 0.0f64
        var nd = 0.0f64
        i = 0usize
        while i < p {
            nc += oc[i] * oc[i]
            nd += delta[i] * delta[i]
            i += 1usize
        }
        var cut = math.sqrt[f64](nc / nd)
        if cut > 1.0f64 { cut = 1.0f64 }
        cut = cut * 0.0001f64
        var go = true
        while go {
            i = 0usize
            while i < p {
                cf[i] = oc[i] + lambda * delta[i]
                i += 1usize
            }
            lk[0usize] = old_f - 1.0f64
            fr = likereg(d, jj, cf, f1, lk, r)
            f = lk[0usize]
            if fr == 2usize { ret }
            if fr == 3usize { lambda = lambda / 2.0f64 } else { lambda = lambda / 10.0f64 }
            go = lambda > cut && f <= old_f - 1.0e-3f64
        }
        if f < old_f - 1.0e-3f64 { ret }
        if fr == 3usize { ret }
        if math.abs[f64](f - old_f) < tol { ret }
        it += 1usize
    }
}

// the global parametric fit about xbar, whose value is taken off the local fits and put back on the interpolant
type Pc = struct { coef: []f64, jac: Jac, xbar: f64, on: bool }

// out[j] = (x)^(j - nd) / (j - nd)! for j >= nd: the polynomial basis (nd = 0) or its first derivative (nd = 1)
fn basis(dx: f64, deg: usize, nd: usize, out: []f64) {
    var j = 0usize
    while j <= deg {
        out[j] = 0.0f64
        j += 1usize
    }
    if nd == 0usize { out[0usize] = 1.0f64 }
    if deg == 0usize { ret }
    var ff = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    ff[nd] = 1.0f64
    j = nd + 1usize
    while j <= deg {
        ff[j] = ff[j - 1usize] * dx / f64(j - nd)
        j += 1usize
    }
    j = 1usize
    while j <= deg {
        out[j] = ff[j]
        j += 1usize
    }
}


// the median of x[0..n] as lf_robust.c's median (a bisection on the values)
fn median(x: []f64, n: usize) -> f64 {
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 0usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    if lo == hi { ret lo }
    lo = lo - (hi - lo)
    hi = hi + (hi - lo)
    i = 0usize
    while i < n {
        if x[i] > lo && x[i] < hi {
            let s = x[i]
            var lt = 0usize
            var eq = 0usize
            var gt = 0usize
            var j = 0usize
            while j < n {
                if x[j] < s { lt += 1usize }
                if x[j] == s { eq += 1usize }
                if x[j] > s { gt += 1usize }
                j += 1usize
            }
            if 2usize * (lt + eq) > n && 2usize * (gt + eq) > n { ret s }
            if 2usize * (lt + eq) <= n { lo = s }
            if 2usize * (gt + eq) <= n { hi = s }
        }
        i += 1usize
    }
    ret (hi + lo) / 2.0f64
}

// robustscale: the square root of the median deviance of the fit cf (the family without its robust cap, scale 1)
fn robscale(d: *Des, cf: []f64, rr: []f64) -> f64 {
    let p = d.p
    var i = 0usize
    while i < d.m {
        var t = 0.0f64
        var c = 0usize
        while c < p {
            t += cf[c] * d.x[i * p + c]
            c += 1usize
        }
        d.th[i] = t
        let _ = links0(d.fam % 256usize, t, d.y[i], d.pw[i], 1.0f64, rr)
        d.sc[i] = 0.0f64 - 2.0f64 * rr[0usize]
        i += 1usize
    }
    let rs = math.sqrt[f64](median(d.sc, d.m))
    if rs == 0.0f64 { ret 1.0f64 }
    ret rs
}

// lfinit (reginit, robustinit or circinit) and lfiter on the design d, with lf_robust's fixed point for the scale
// when the family is a quasi robust one: the status (0 ok, 2 out of bounds, 3 perfect fit, 6 no points with weight,
// 7 initial failure), the coefficients in cf
fn nrfit(d: *Des, jj: *Jac, cf: []f64, oc: []f64, g1: []f64, dl: []f64, rr: []f64) -> usize {
    let p = d.p
    let fam = d.fam % 16usize
    let lin = (d.fam / 16usize) % 16usize
    var s0 = 0.0f64
    var s1 = 0.0f64
    var tol = 1.0e-6f64
    var c = 0usize
    while c < p {
        cf[c] = 0.0f64
        c += 1usize
    }
    var i = 0usize
    d.status = 0usize
    d.rs = 1.0f64
    d.s0 = 0.0f64
    if fam == 7usize || fam == 8usize {
        while i < d.m {
            d.sc[i] = d.y[i]
            i += 1usize
        }
        cf[0usize] = median(d.sc, d.m)
    } else {
        if fam == 6usize {
            var ss = 0.0f64
            var sc2 = 0.0f64
            while i < d.m {
                ss += d.w[i] * d.pw[i] * math.sin[f64](d.y[i])
                sc2 += d.w[i] * d.pw[i] * math.cos[f64](d.y[i])
                i += 1usize
            }
            cf[0usize] = math.atan2[f64](ss, sc2)
        } else {
            while i < d.m {
                var yi = d.y[i]
                if fam == 0usize { yi = d.pw[i] * yi }
                if fam == 1usize {
                    if yi < 0.0f64 { yi = 0.0f64 }
                    if yi > d.pw[i] { yi = d.pw[i] }
                }
                if fam == 5usize { yi = math.pow[f64](yi, d.pw[i]) }
                if fam >= 2usize && yi < 0.0f64 { yi = 0.0f64 }
                s1 += d.w[i] * yi
                s0 += d.w[i] * d.pw[i]
                i += 1usize
            }
            d.s0 = s0
            tol = 1.0e-6f64 * s0
            if s0 == 0.0f64 { ret 6usize }
            if lin == 3usize {
                cf[0usize] = s1 / s0
            }
            if lin == 4usize {
                if s1 <= 0.0f64 {
                    cf[0usize] = 0.0f64 - 1000.0f64
                    ret 7usize
                }
                cf[0usize] = math.log[f64](s1 / s0)
            }
            if lin == 5usize {
                if s1 <= 0.0f64 {
                    cf[0usize] = 0.0f64 - 1000.0f64
                    ret 7usize
                }
                if s1 >= s0 {
                    cf[0usize] = 1000.0f64
                    ret 7usize
                }
                let pr = s1 / s0
                cf[0usize] = math.log[f64](pr / (1.0f64 - pr))
            }
            if lin == 6usize {
                if s1 <= 0.0f64 {
                    cf[0usize] = 1000.0f64
                    ret 7usize
                }
                cf[0usize] = s0 / s1
            }
            if lin == 7usize { cf[0usize] = math.sqrt[f64](s1 / s0) }
            if lin == 8usize { cf[0usize] = math.asin[f64](math.sqrt[f64](s1 / s0)) }
        }
    }
    if d.qs == 1usize && (d.fam >= 256usize || fam == 7usize || fam == 8usize) {
        var x = math.log[f64](robscale(d, cf, rr))
        var it = 0usize
        var go = true
        while go && it < 20usize {
            var x1 = x
            if d.status == 0usize {
                d.rs = math.exp[f64](x)
                max_nr(d, jj, cf, oc, g1, dl, tol, rr)
                if d.status == 0usize {
                    x1 = math.log[f64](robscale(d, cf, rr))
                    if x1 < x - 0.2f64 { x1 = x - 0.2f64 }
                }
            }
            var df = x1 - x
            if df < 0.0f64 { df = 0.0f64 - df }
            if df < 1.0e-6f64 { go = false }
            x = x1
            it += 1usize
        }
    } else {
        max_nr(d, jj, cf, oc, g1, dl, tol, rr)
    }
    if d.status == 2usize {
        c = 0usize
        while c < p {
            cf[c] = 0.0f64
            c += 1usize
        }
    }
    ret d.status
}

error ParametricFit

// the parametric component: the unweighted fit of the same degree and family over all points about their mean
fn pcomp(a: *mem.Arena, x: []const f64, y: []const f64, sp: []const f64) -> (Pc, err) {
    let n = x.len
    let deg = usize(sp[1usize])
    let p = deg + 1usize
    let (dx, e3) = mem.alloc[f64](a, n * p)
    let (th, e6) = mem.alloc[f64](a, n)
    let (dw, e5) = mem.alloc[f64](a, n)
    let (zz, e7) = mem.alloc[f64](a, p * p)
    let (qq, e8) = mem.alloc[f64](a, p * p)
    let (wv, e9) = mem.alloc[f64](a, 2usize * p)
    let (cf, e10) = mem.alloc[f64](a, p)
    let (oc, e11) = mem.alloc[f64](a, p)
    let (g1, e12) = mem.alloc[f64](a, p)
    let (dl, e13) = mem.alloc[f64](a, p)
    let (rr, e16) = mem.alloc[f64](a, 4usize)
    let (cw, e17) = mem.alloc[f64](a, p)
    let (sc, e19) = mem.alloc[f64](a, n)
    let (dq, e18) = mem.alloc[f64](a, p)
    let jj = Jac{ z: zz, q: qq, wk: wv[0usize..p], dg: wv[p..2usize * p], p: p, dec: false }
    let pcv = Pc{ coef: cw, jac: jj, xbar: 0.0f64, on: true }
    if e3 != ok { ret (pcv, e3) }
    if e5 != ok { ret (pcv, e5) }
    if e6 != ok { ret (pcv, e6) }
    if e7 != ok { ret (pcv, e7) }
    if e8 != ok { ret (pcv, e8) }
    if e9 != ok { ret (pcv, e9) }
    if e10 != ok { ret (pcv, e10) }
    if e11 != ok { ret (pcv, e11) }
    if e12 != ok { ret (pcv, e12) }
    if e13 != ok { ret (pcv, e13) }
    if e16 != ok { ret (pcv, e16) }
    if e17 != ok { ret (pcv, e17) }
    if e18 != ok { ret (pcv, e18) }
    if e19 != ok { ret (pcv, e19) }
    var xb = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < n {
        xb += x[i] * y[n + i]
        sw += y[n + i]
        i += 1usize
    }
    xb = xb / sw
    var bs = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let bsl = bs[0usize..4usize]
    i = 0usize
    while i < n {
        basis(x[i] - xb, deg, 0usize, bsl)
        var c = 0usize
        while c < p {
            dx[i * p + c] = bsl[c]
            c += 1usize
        }
        dw[i] = 1.0f64
        i += 1usize
    }
    if usize(sp[2usize]) == 7usize || usize(sp[2usize]) == 8usize {
        // noparcomp: the robust huber and cauchy families have none
        ret (Pc{ coef: cw, jac: jj, xbar: xb, on: false }, ok)
    }
    var ds = Des{ m: n, p: p, x: dx, w: dw, y: y[0usize..n], pw: y[n..2usize * n], sc: sc, th: th, fam: famcode(sp), rs: 1.0f64, qs: usize(sp[8usize]), s0: 0.0f64, llk: 0.0f64, status: 0usize }
    var jw = jj
    let st = nrfit(&ds, &jw, cf, oc, g1, dl, rr)
    if st == 6usize || st == 7usize || st == 2usize { ret (pcv, ParametricFit) }
    i = 0usize
    while i < p {
        cw[i] = cf[i]
        i += 1usize
    }
    var pc2 = Pc{ coef: cw, jac: jw, xbar: xb, on: true }
    ret (pc2, ok)
}

// sqrt of v' Z^-1 v for the parametric component's information (jacob_qf), v overwritten
fn pc_qf(jj: *Jac, v: []f64) -> f64 {
    jac_dec(jj)
    let p = jj.p
    var i = 0usize
    while i < p {
        v[i] = v[i] * jj.dg[i]
        i += 1usize
    }
    var mx = jj.z[0usize]
    i = 1usize
    while i < p {
        if jj.z[i * (p + 1usize)] > mx { mx = jj.z[i * (p + 1usize)] }
        i += 1usize
    }
    let tol = 1.0e-8f64 * mx
    var sum = 0.0f64
    i = 0usize
    while i < p {
        if jj.z[i * p + i] > tol {
            jj.wk[i] = 0.0f64
            var c = 0usize
            while c < p {
                jj.wk[i] += jj.q[c * p + i] * v[c]
                c += 1usize
            }
            sum += jj.wk[i] * jj.wk[i] / jj.z[i * p + i]
        }
        i += 1usize
    }
    ret sum
}

// addparcomp: the parametric component's value (what = W_COEF) or norm (W_NLX, W_T0) at x0
fn addpar(pc: *Pc, deg: usize, what: usize, x0: f64) -> f64 {
    if !pc.on { ret 0.0f64 }
    var bs = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let bsl = bs[0usize..4usize]
    basis(x0 - pc.xbar, deg, 0usize, bsl)
    let p = deg + 1usize
    if what == W_COEF {
        var s = 0.0f64
        var c = 0usize
        while c < p {
            s += pc.coef[c] * bsl[c]
            c += 1usize
        }
        ret s
    }
    if what == W_NLX || what == W_T0 { ret math.sqrt[f64](pc_qf(&pc.jac, bsl)) }
    ret 0.0f64
}

fn sgn(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

// W'(u) / W(u); NaN for the kernels the package does not define it for
fn wdw(u: f64, kern: usize) -> f64 {
    let eps = 1.0e-10f64
    if kern == 6usize { ret 0.0f64 - 6.25f64 * u }
    if math.abs[f64](u) >= 1.0f64 { ret 0.0f64 }
    if kern == 1usize { ret 0.0f64 }
    if kern == 7usize { ret (0.0f64 - sgn(u)) / (1.0f64 - math.abs[f64](u) + eps) }
    if kern == 2usize { ret (0.0f64 - 2.0f64 * u) / (1.0f64 - u * u + eps) }
    if kern == 3usize { ret (0.0f64 - 4.0f64 * u) / (1.0f64 - u * u + eps) }
    if kern == 5usize { ret (0.0f64 - 6.0f64 * u) / (1.0f64 - u * u + eps) }
    if kern == 4usize { ret (0.0f64 - 9.0f64 * sgn(u) * u * u) / (1.0f64 - u * u * math.abs[f64](u) + eps) }
    if kern == 11usize {
        if u > 0.0f64 { ret 0.0f64 - 3.0f64 }
        ret 3.0f64
    }
    ret nan()
}

// R's qr on the n x 2 column-major matrix x: the Householder triangularisation, row pivoted as the package does
fn qr2(x: []f64, n: usize) {
    var j = 0usize
    while j < 2usize {
        var mi = j
        var mx = math.abs[f64](x[(n + 1usize) * j])
        var nx = mx * mx
        var i = j + 1usize
        while i < n {
            nx += x[j * n + i] * x[j * n + i]
            if math.abs[f64](x[j * n + i]) > mx {
                mi = i
                mx = math.abs[f64](x[j * n + i])
            }
            i += 1usize
        }
        i = j
        while i < 2usize {
            let t = x[i * n + j]
            x[i * n + j] = x[i * n + mi]
            x[i * n + mi] = t
            i += 1usize
        }
        if x[(n + 1usize) * j] > 0.0f64 {
            i = j
            while i < 2usize {
                x[i * n + j] = 0.0f64 - x[i * n + j]
                i += 1usize
            }
        }
        nx = math.sqrt[f64](nx)
        let c = nx * (nx - x[(n + 1usize) * j])
        if c != 0.0f64 {
            i = j + 1usize
            while i < 2usize {
                var s = 0.0f64
                var k = j
                while k < n {
                    s += x[i * n + k] * x[j * n + k]
                    k += 1usize
                }
                s = (s - nx * x[i * n + j]) / c
                k = j
                while k < n {
                    x[i * n + k] -= s * x[j * n + k]
                    k += 1usize
                }
                x[i * n + j] += s * nx
                i += 1usize
            }
            x[j * n + j] = nx
        }
        j += 1usize
    }
}

// the simultaneous-band integrand at the fit just made: ||l'(x) orthogonal to l(x)|| / ||l(x)|| for the weight
// diagram l of the local fit and its derivative (wdiag with deg 1, the package's scbfitter, one predictor)
fn wdet(d: *Des, jj: *Jac, ix: []usize, di: []f64, x: []const f64, x0: f64, h: f64, kern: usize, lw: []f64, f1: []f64, rr: []f64) -> f64 {
    let m = d.m
    let p = d.p
    let lx = lw[0usize..m]
    let lxd = lw[m..2usize * m]
    var c = 0usize
    while c < p {
        f1[c] = 0.0f64
        c += 1usize
    }
    f1[0usize] = 1.0f64
    let _ = jac_solve(jj, f1)
    var i = 0usize
    while i < m {
        var s = 0.0f64
        c = 0usize
        while c < p {
            s += f1[c] * d.x[i * p + c]
            c += 1usize
        }
        lx[i] = s
        let dfx = x[ix[i]] - x0
        let dd = di[ix[i]]
        var wg = 0.0f64
        if dd != 0.0f64 { wg = (0.0f64 - wdw(dd / h, kern)) * dfx / (h * dd * 1.0f64 * 1.0f64) }
        lxd[i] = lx[i] * d.w[i] * wg
        lx[i] = lx[i] * d.w[i]
        i += 1usize
    }
    // nnresproj: the residual projection of lxd
    c = 0usize
    while c < p {
        f1[c] = 0.0f64
        c += 1usize
    }
    var j = 0usize
    while j < m {
        let _ = links(d.fam, d.th[j], d.y[j], d.pw[j], d.rs, rr)
        c = 0usize
        while c < p {
            f1[c] += rr[3usize] * d.x[j * p + c] * lxd[j]
            c += 1usize
        }
        j += 1usize
    }
    let _ = jac_solve(jj, f1)
    i = 0usize
    while i < m {
        var s = 0.0f64
        c = 0usize
        while c < p {
            s += f1[c] * d.x[i * p + c]
            c += 1usize
        }
        lxd[i] -= s * d.w[i]
        i += 1usize
    }
    basis(0.0f64, p - 1usize, 1usize, f1)
    let _ = jac_solve(jj, f1)
    var k = 0usize
    while k < m {
        c = 0usize
        while c < p {
            lxd[k] += f1[c] * d.x[k * p + c] * d.w[k]
            c += 1usize
        }
        k += 1usize
    }
    i = 0usize
    while i < m {
        let _ = links(d.fam, d.th[i], d.y[i], d.pw[i], d.rs, rr)
        let sq = math.sqrt[f64](math.abs[f64](rr[3usize]))
        lx[i] = lx[i] * sq
        lxd[i] = lxd[i] * sq
        i += 1usize
    }
    qr2(lw, m)
    ret lw[m + 1usize] / lw[0usize]
}

// the kernel weight of a point at distance di for bandwidth h
fn rowweight(di: f64, h: f64, kern: usize) -> f64 {
    if h == 0.0f64 {
        if di == 0.0f64 { ret 1.0f64 }
        ret 0.0f64
    }
    ret wk(di / h, kern)
}

// design row m for data point i about x0
fn addrow(dx: []f64, dy: []f64, dw: []f64, m: usize, x: []const f64, y: []const f64, x0: f64, i: usize, p: usize, wt: f64, ix: []usize) {
    ix[m] = i
    let d1 = x[i] - x0
    dx[m * p] = 1.0f64
    var q = 1usize
    var ff = 1.0f64
    while q < p {
        ff = ff * d1 / f64(q)
        dx[m * p + q] = ff
        q += 1usize
    }
    dy[m] = y[i]
    dy[x.len + m] = y[x.len + i]
    dw[m] = wt
}

// the fit at x0: writes the vertex record out[0..VS]
fn vertex1(a: *mem.Arena, x: []const f64, y: []const f64, sp: []const f64, pc: *Pc, x0: f64, out: []f64, det: []f64) -> err {
    let n = x.len
    let nf = f64(n)
    let kern = usize(sp[0usize])
    let deg = usize(sp[1usize])
    let fam = famcode(sp)
    let p = deg + 1usize
    let (di, e1) = mem.alloc[f64](a, n)
    let (ds, e2) = mem.alloc[f64](a, n)
    let (dx, e3) = mem.alloc[f64](a, n * p)
    let (dy, e4) = mem.alloc[f64](a, 2usize * n)
    let (dw, e5) = mem.alloc[f64](a, n)
    let (th, e6) = mem.alloc[f64](a, n)
    let (zz, e7) = mem.alloc[f64](a, p * p)
    let (qq, e8) = mem.alloc[f64](a, p * p)
    let (wv, e9) = mem.alloc[f64](a, 4usize * p + 8usize)
    let (cf, e10) = mem.alloc[f64](a, p)
    let (oc, e11) = mem.alloc[f64](a, p)
    let (g1, e12) = mem.alloc[f64](a, p)
    let (dl, e13) = mem.alloc[f64](a, p)
    let (m2, e14) = mem.alloc[f64](a, p * p)
    let (m12, e15) = mem.alloc[f64](a, p * p)
    let (rr, e16) = mem.alloc[f64](a, 4usize)
    let (ix, e17) = mem.alloc[usize](a, n)
    let (lw, e18) = mem.alloc[f64](a, 2usize * n)
    if e17 != ok { ret e17 }
    if e18 != ok { ret e18 }
    if e1 != ok { ret e1 }
    if e2 != ok { ret e2 }
    if e3 != ok { ret e3 }
    if e4 != ok { ret e4 }
    if e5 != ok { ret e5 }
    if e6 != ok { ret e6 }
    if e7 != ok { ret e7 }
    if e8 != ok { ret e8 }
    if e9 != ok { ret e9 }
    if e10 != ok { ret e10 }
    if e11 != ok { ret e11 }
    if e12 != ok { ret e12 }
    if e13 != ok { ret e13 }
    if e14 != ok { ret e14 }
    if e15 != ok { ret e15 }
    if e16 != ok { ret e16 }
    var i = 0usize
    while i < n {
        di[i] = math.abs[f64](x[i] - x0)
        ds[i] = di[i]
        i += 1usize
    }
    // the bandwidth: the k-th nearest distance (nn) or the fixed h, the larger
    var kf = math.floor[f64](nf * sp[3usize] + 1.0e-12f64)
    if sp[11usize] > 0.0f64 { kf = sp[11usize] }
    var nnh = 0.0f64
    if kf >= 1.0f64 {
        i = 1usize
        while i < n {
            let v = ds[i]
            var j = i
            while j > 0usize && ds[j - 1usize] > v {
                ds[j] = ds[j - 1usize]
                j -= 1usize
            }
            ds[j] = v
            i += 1usize
        }
        if kf < nf {
            nnh = ds[usize(kf) - 1usize]
        } else {
            nnh = ds[n - 1usize] * math.exp[f64](math.log[f64](kf / nf))
        }
    }
    var h = nnh
    if sp[4usize] > h { h = sp[4usize] }
    // the points with weight, in nbhd1's order for sorted x (outward from the nearest point, left side first)
    // and in index order otherwise: the order the sums are accumulated in
    var m = 0usize
    var srtd = true
    i = 1usize
    while i < n {
        if x[i] < x[i - 1usize] { srtd = false }
        i += 1usize
    }
    if srtd && kf <= nf {
        var z = 0usize
        if x0 <= x[0usize] {
            z = 0usize
        } else {
            if x0 >= x[n - 1usize] {
                z = n - 1usize
            } else {
                var l = 0usize
                var r = n - 1usize
                while r - l > 1usize {
                    z = (r + l) / 2usize
                    if x[z] > x0 { r = z } else { l = z }
                }
                if x0 - x[l] > x[r] - x0 { z = r } else { z = l }
            }
        }
        if x[z] > x0 && z > 0usize { z -= 1usize }
        var go = true
        var k = z
        if x[z] > x0 { go = false }
        while go {
            let wt = rowweight(di[k], h, kern)
            if wt > 0.0f64 {
                addrow(dx, dy, dw, m, x, y, x0, k, p, wt, ix)
                m += 1usize
                if k == 0usize { go = false } else { k -= 1usize }
            } else {
                go = false
            }
        }
        go = true
        k = z + 1usize
        if x[z] > x0 { k = 0usize }
        while go && k < n {
            let wt = rowweight(di[k], h, kern)
            if wt > 0.0f64 {
                addrow(dx, dy, dw, m, x, y, x0, k, p, wt, ix)
                m += 1usize
                k += 1usize
            } else {
                go = false
            }
        }
    } else {
        i = 0usize
        while i < n {
            let wt = rowweight(di[i], h, kern)
            if wt > 0.0f64 {
                addrow(dx, dy, dw, m, x, y, x0, i, p, wt, ix)
                m += 1usize
            }
            i += 1usize
        }
    }
    var c = 0usize
    while c < VS {
        out[c] = 0.0f64
        c += 1usize
    }
    out[V_X] = x0
    out[V_H] = h
    var jj = Jac{ z: zz, q: qq, wk: wv[0usize..p], dg: wv[p..2usize * p], p: p, dec: false }
    var ds2 = Des{ m: m, p: p, x: dx, w: dw, y: dy[0usize..n], pw: dy[n..2usize * n], sc: ds, th: th, fam: fam, rs: 1.0f64, qs: usize(sp[8usize]), s0: 0.0f64, llk: 0.0f64, status: 0usize }
    let st = nrfit(&ds2, &jj, cf, oc, g1, dl, rr)
    // the parametric component comes off the local fit (subparcomp)
    let dpx = x0 - pc.xbar
    var bs = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let bsl = bs[0usize..4usize]
    var gv = 0.0f64
    if pc.on {
        basis(dpx, deg, 0usize, bsl)
        c = 0usize
        while c < p {
            gv += pc.coef[c] * bsl[c]
            c += 1usize
        }
    }
    out[V_C0] = cf[0usize] - gv
    if p > 1usize {
        gv = 0.0f64
        if pc.on {
            basis(dpx, deg, 1usize, bsl)
            c = 0usize
            while c < p {
                gv += pc.coef[c] * bsl[c]
                c += 1usize
            }
        }
        out[V_C1] = cf[1usize] - gv
    }
    if det.len > 0usize { det[0usize] = nan() }
    out[V_ST] = f64(st)
    out[V_RAW] = cf[0usize]
    out[V_M] = f64(m)
    if st != 0usize && st != 2usize { ret ok }
    // vmat: M2 = X^T W^2 V X, M12 = (X^T W V X)^-1 M2, tr0 = sum W, tr2 = trace M12
    var tr0 = 0.0f64
    var s1w = 0.0f64
    c = 0usize
    while c < p * p {
        m2[c] = 0.0f64
        c += 1usize
    }
    i = 0usize
    while i < m {
        let _ = links(fam, th[i], dy[i], dy[n + i], ds2.rs, rr)
        let ww = dw[i] * dw[i] * rr[3usize]
        tr0 += dw[i]
        s1w += dw[i] * dw[i]
        var a1 = 0usize
        while a1 < p {
            var a2 = 0usize
            while a2 < p {
                m2[a1 * p + a2] += ww * dx[i * p + a1] * dx[i * p + a2]
                a2 += 1usize
            }
            a1 += 1usize
        }
        i += 1usize
    }
    c = 0usize
    while c < p * p {
        m12[c] = m2[c]
        c += 1usize
    }
    i = 0usize
    while i < p {
        let _ = jac_solve(&jj, m12[i * p..i * p + p])
        i += 1usize
    }
    var tr2 = 0.0f64
    i = 0usize
    while i < p {
        tr2 += m12[i * (p + 1usize)]
        i += 1usize
    }
    // the standard deviation of the fit's value (local_df's tr[5]): sqrt(f1' M2 f1) with f1 = M1^-1 e0
    c = 0usize
    while c < p {
        dl[c] = 0.0f64
        c += 1usize
    }
    dl[0usize] = 1.0f64
    let _ = jac_solve(&jj, dl)
    var q5 = 0.0f64
    i = 0usize
    while i < p {
        var k5 = 0usize
        while k5 < p {
            q5 += dl[i] * m2[i * p + k5] * dl[k5]
            k5 += 1usize
        }
        i += 1usize
    }
    out[V_S1] = s1w
    out[V_S5] = math.sqrt[f64](q5)
    // lf_vcov: the covariance M1^-1 M2 M1^-1 through the Cholesky factor of M2
    var j = 0usize
    while j < p {
        var k = p * j + j
        i = 0usize
        while i < j {
            m2[k] -= m2[p * j + i] * m2[p * j + i]
            i += 1usize
        }
        if m2[k] <= 0.0f64 {
            i = j
            while i < p {
                m2[p * i + j] = 0.0f64
                i += 1usize
            }
        } else {
            m2[k] = math.sqrt[f64](m2[k])
            i = j + 1usize
            while i < p {
                k = 0usize
                while k < j {
                    m2[p * i + j] -= m2[p * i + k] * m2[p * j + k]
                    k += 1usize
                }
                m2[p * i + j] = m2[p * i + j] / m2[p * j + j]
                i += 1usize
            }
        }
        j += 1usize
    }
    j = 0usize
    while j < p {
        i = j + 1usize
        while i < p {
            m2[p * j + i] = 0.0f64
            i += 1usize
        }
        j += 1usize
    }
    i = 0usize
    while i < p {
        j = 0usize
        while j < i {
            m2[j * p + i] = m2[i * p + j]
            m2[i * p + j] = 0.0f64
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < p {
        let _ = jac_solve(&jj, m2[i * p..i * p + p])
        i += 1usize
    }
    i = 0usize
    while i < p {
        j = 0usize
        while j < p {
            var s = 0.0f64
            var k = 0usize
            while k < p {
                s += m2[k * p + i] * m2[k * p + j]
                k += 1usize
            }
            m12[i * p + j] = s
            j += 1usize
        }
        i += 1usize
    }
    c = 0usize
    while c < p {
        g1[c] = 0.0f64
        c += 1usize
    }
    g1[0usize] = 1.0f64
    let _ = jac_solve(&jj, g1)
    var v0 = math.sqrt[f64](m12[0usize])
    var v1 = 0.0f64
    if p > 1usize { v1 = m12[1usize] }
    if v0 > 0.0f64 { v1 = v1 / v0 }
    var t0 = math.sqrt[f64](g1[0usize])
    var t1 = 0.0f64
    if p > 1usize { t1 = g1[1usize] }
    if t0 > 0.0f64 { t1 = t1 / t0 }
    // subparcomp2: the parametric component's share of the variance and influence norms
    if pc.on {
        basis(dpx, deg, 0usize, bsl)
        c = 0usize
        while c < p {
            g1[c] = bsl[c]
            c += 1usize
        }
        let _ = jac_solve(&pc.jac, g1)
        var tp = 0.0f64
        c = 0usize
        while c < p {
            tp += bsl[c] * g1[c]
            c += 1usize
        }
        tp = math.sqrt[f64](tp)
        v0 -= tp
        t0 -= tp
        if tp != 0.0f64 && p > 1usize {
            basis(dpx, deg, 1usize, bsl)
            var t1p = 0.0f64
            c = 0usize
            while c < p {
                t1p += bsl[c] * g1[c]
                c += 1usize
            }
            t1p = t1p / tp
            v1 -= t1p
            t1 -= t1p
        }
    }
    if sp[9usize] == 3.0f64 {
        // mmse: the weight diagram's variance plus the squared bias bound
        c = 0usize
        while c < p {
            g1[c] = 0.0f64
            c += 1usize
        }
        g1[0usize] = 1.0f64
        let _ = jac_solve(&jj, g1)
        var sv = 0.0f64
        var sbb = 0.0f64
        i = 0usize
        while i < m {
            var s = 0.0f64
            c = 0usize
            while c < p {
                s += g1[c] * dx[i * p + c]
                c += 1usize
            }
            let l = s * dw[i]
            sv += l * l
            var dp = di[ix[i]]
            var j2 = 0usize
            while j2 < deg {
                dp = dp * di[ix[i]]
                j2 += 1usize
            }
            sbb += math.abs[f64](l) * dp
            i += 1usize
        }
        var p1 = 1.0f64
        var j3 = 1usize
        while j3 <= deg + 1usize {
            p1 = p1 * f64(j3)
            j3 += 1usize
        }
        out[V_MM] = sv + sbb * sbb * sp[10usize] * sp[10usize] / (p1 * p1)
    }
    if det.len > 0usize { det[0usize] = wdet(&ds2, &jj, ix, di, x, x0, h, kern, lw, g1, rr) }
    out[V_N0] = v0
    out[V_N1] = v1
    out[V_T0] = t0
    out[V_T1] = t1
    out[V_LIK] = ds2.llk
    out[V_TR0] = tr0
    out[V_TR2] = tr2
    ret ok
}

error Unsupported

fn adcri(lk: f64, t0: f64, t2: f64, pen: f64) -> f64 {
    var m = 0.0f64 - 2.0f64 * lk
    if t0 - t2 > m { m = t0 - t2 }
    ret (m + pen * t2) / t0
}

// the fit at x0 with a bandwidth chosen locally by the adaptive criterion sp[9] (1 cp, 2 ici, 4 ok) with penalty
// sp[10], as the package's alocfit; no criterion (0) is the plain fit. mindex is not supported.
fn vertex(a: *mem.Arena, x: []const f64, y: []const f64, sp: []const f64, pc: *Pc, x0: f64, out: []f64, det: []f64) -> err {
    let cri = usize(sp[9usize])
    if cri == 0usize { ret vertex1(a, x, y, sp, pc, x0, out, det) }
    if cri != 1usize && cri != 2usize && cri != 3usize && cri != 4usize { ret Unsupported }
    let n = x.len
    let nf = f64(n)
    let p = usize(sp[1usize]) + 1usize
    let pen = sp[10usize]
    var sba = [14]f64{ sp[0usize], sp[1usize], sp[2usize], sp[3usize], sp[4usize], sp[5usize], sp[6usize], sp[7usize], sp[8usize], 0.0f64, 0.0f64, 0.0f64, sp[12usize], sp[13usize] }
    let sb = sba[0usize..14usize]
    var ra = [17]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let ro = ra[0usize..17usize]
    let start = mem.mark(a)
    var zf = math.floor[f64](nf * sp[3usize])
    if cri != 4usize && zf < f64(p + 2usize) { zf = f64(p + 2usize) }
    var zlast = zf
    var go = true
    while go {
        sb[3usize] = 0.0f64
        if cri == 3usize {
            sb[9usize] = 3.0f64
            sb[10usize] = pen
        }
        sb[11usize] = zf
        zlast = zf
        let e = vertex1(a, x, y, sb, pc, x0, ro, det[0usize..0usize])
        mem.reset(a, start)
        if e != ok { ret e }
        if zf < ro[V_M] { zf = ro[V_M] }
        zf += 1.0f64
        go = zf <= nf && (ro[V_H] == 0.0f64 || ro[V_ST] != 0.0f64)
    }
    if cri == 4usize {
        sb[11usize] = zlast
        ret vertex1(a, x, y, sb, pc, x0, out, det)
    }
    let hmin = ro[V_H]
    var mcp = adcri(ro[V_LIK], ro[V_S1], ro[V_TR2], pen)
    if cri == 3usize { mcp = ro[V_MM] }
    var clo = ro[V_RAW] - pen * ro[V_S5]
    var cup = ro[V_RAW] + pen * ro[V_S5]
    // aband2: widen the bandwidth by 1.3 until the criterion has risen for good
    sb[11usize] = 0.0f64
    var h1 = ro[V_H]
    var hc = ro[V_H]
    var done = false
    var nu1 = 0.0f64
    var inc = 0usize
    var ncp = 0.0f64
    while !done && nu1 < (nf - f64(p)) * 0.95f64 {
        sb[4usize] = (1.0f64 + 0.3f64) * hc
        let e = vertex1(a, x, y, sb, pc, x0, ro, det[0usize..0usize])
        mem.reset(a, start)
        if e != ok { ret e }
        hc = ro[V_H]
        nu1 = ro[V_S1] - ro[V_TR2]
        if cri == 2usize {
            let tlo = ro[V_RAW] - pen * ro[V_S5]
            let tup = ro[V_RAW] + pen * ro[V_S5]
            done = tlo > cup || tup < clo
            if !done {
                if tlo > clo { clo = tlo }
                if tup < cup { cup = tup }
                h1 = hc
            }
        } else {
            var cp = adcri(ro[V_LIK], ro[V_S1], ro[V_TR2], pen)
            if cri == 3usize { cp = ro[V_MM] }
            if cp < mcp {
                mcp = cp
                h1 = hc
            }
            if cri == 3usize {
                if cp > ncp { inc += 1usize } else { inc = 0usize }
                ncp = cp
                done = inc >= 3usize
            } else {
                if cp >= ncp { inc += 1usize } else { inc = 0usize }
                ncp = cp
                done = inc >= 10usize || (inc >= 3usize && (ro[V_S1] - ro[V_TR2]) >= 10.0f64 && cp > 1.5f64 * mcp)
            }
        }
    }
    // aband3: a finer search about the best bandwidth so far
    let h0 = h1
    var i = 0.0f64 - 2.0f64
    if cri == 2usize { i = 1.0f64 }
    if h0 == hmin { i = 1.0f64 }
    while i <= 2.0f64 {
        if i == 0.0f64 { i = 1.0f64 }
        sb[4usize] = h0 * (1.0f64 + 0.1f64 * i)
        let e = vertex1(a, x, y, sb, pc, x0, ro, det[0usize..0usize])
        mem.reset(a, start)
        if e != ok { ret e }
        hc = ro[V_H]
        if cri == 2usize {
            let tlo = ro[V_RAW] - pen * ro[V_S5]
            let tup = ro[V_RAW] + pen * ro[V_S5]
            if tlo > cup || tup < clo {
                i = 2.0f64
            } else {
                h1 = hc
                if tlo > clo { clo = tlo }
                if tup < cup { cup = tup }
            }
        } else {
            var cp = adcri(ro[V_LIK], ro[V_S1], ro[V_TR2], pen)
            if cri == 3usize { cp = ro[V_MM] }
            if cp < mcp {
                mcp = cp
                h1 = hc
            } else {
                if i > 0.0f64 { i = 2.0f64 }
            }
        }
        i += 1.0f64
    }
    sb[4usize] = h1
    ret vertex1(a, x, y, sb, pc, x0, out, det)
}

// sort the records vt[0..nv] by x
fn sort_vertices(vt: []f64, nv: usize) {
    var i = 1usize
    while i < nv {
        var j = i
        while j > 0usize && vt[(j - 1usize) * VS + V_X] > vt[j * VS + V_X] {
            var c = 0usize
            while c < VS {
                let t = vt[j * VS + c]
                vt[j * VS + c] = vt[(j - 1usize) * VS + c]
                vt[(j - 1usize) * VS + c] = t
                c += 1usize
            }
            j -= 1usize
        }
        i += 1usize
    }
}

// the fitting vertices of the evaluation structure into vt (capacity cap records); the count. The data
// structures dat is kept in data order, the others sorted by x.
fn build(a: *mem.Arena, x: []const f64, y: []const f64, sp: []const f64, pc: *Pc, vt: []f64, cap: usize) -> (usize, err) {
    let n = x.len
    let ev = usize(sp[5usize])
    var lo = x[0usize]
    var hi = x[0usize]
    var i = 1usize
    while i < n {
        if x[i] < lo { lo = x[i] }
        if x[i] > hi { hi = x[i] }
        i += 1usize
    }
    var nv = 0usize
    let start = mem.mark(a)
    if ev == 2usize {
        i = 0usize
        while i < n {
            let e = vertex(a, x, y, sp, pc, x[i], vt[i * VS..i * VS + VS], vt[0usize..0usize])
            if e != ok { ret (0usize, e) }
            mem.reset(a, start)
            i += 1usize
        }
        ret (n, ok)
    }
    if ev == 3usize {
        let mg = usize(sp[7usize])
        i = 0usize
        while i < mg {
            var xv = lo
            if mg > 1usize {
                let u0 = f64(i)
                let u1 = f64(mg - 1usize - i)
                xv = (u1 * lo + u0 * hi) / f64(mg - 1usize)
            }
            let e = vertex(a, x, y, sp, pc, xv, vt[i * VS..i * VS + VS], vt[0usize..0usize])
            if e != ok { ret (0usize, e) }
            mem.reset(a, start)
            i += 1usize
        }
        sort_vertices(vt, mg)
        ret (mg, ok)
    }
    var e0 = vertex(a, x, y, sp, pc, lo, vt[0usize..VS], vt[0usize..0usize])
    mem.reset(a, start)
    if e0 != ok { ret (0usize, e0) }
    e0 = vertex(a, x, y, sp, pc, hi, vt[VS..2usize * VS], vt[0usize..0usize])
    mem.reset(a, start)
    if e0 != ok { ret (0usize, e0) }
    nv = 2usize
    if ev == 0usize {
        let cut = sp[6usize]
        let (stk, es) = mem.alloc[usize](a, 2usize * cap)
        if es != ok { ret (0usize, es) }
        let base = mem.mark(a)
        var top = 0usize
        stk[0usize] = 0usize
        stk[1usize] = 1usize
        top = 1usize
        while top > 0usize {
            top -= 1usize
            let ia = stk[2usize * top]
            let ib = stk[2usize * top + 1usize]
            let ha = vt[ia * VS + V_H]
            let hb = vt[ib * VS + V_H]
            var hmin = 0.0f64
            if ha > 0.0f64 { hmin = ha }
            if hb > 0.0f64 && (hmin == 0.0f64 || hb < hmin) { hmin = hb }
            let le = vt[ib * VS + V_X] - vt[ia * VS + V_X]
            var score = 0.0f64
            if hmin == 0.0f64 { score = 2.0f64 * le / (hi - lo) } else { score = le / hmin }
            if cut < score {
                if nv >= cap { ret (0usize, TooManyVertices) }
                let xm = (vt[ia * VS + V_X] + vt[ib * VS + V_X]) / 2.0f64
                let e = vertex(a, x, y, sp, pc, xm, vt[nv * VS..nv * VS + VS], vt[0usize..0usize])
                mem.reset(a, base)
                if e != ok { ret (0usize, e) }
                if top + 2usize > cap { ret (0usize, TooManyVertices) }
                stk[2usize * top] = ia
                stk[2usize * top + 1usize] = nv
                stk[2usize * top + 2usize] = nv
                stk[2usize * top + 3usize] = ib
                top += 2usize
                nv += 1usize
            }
        }
        sort_vertices(vt, nv)
        ret (nv, ok)
    }
    // kdtree: split the sorted data at the median until a cell holds fewer than fc points
    let (srt, ek) = mem.alloc[f64](a, n)
    if ek != ok { ret (0usize, ek) }
    i = 0usize
    while i < n {
        srt[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < n {
        let v = srt[i]
        var j = i
        while j > 0usize && srt[j - 1usize] > v {
            srt[j] = srt[j - 1usize]
            j -= 1usize
        }
        srt[j] = v
        i += 1usize
    }
    var alp = sp[3usize]
    if alp > 1.0f64 { alp = 1.0f64 }
    let fc = usize(sp[6usize] / 4.0f64 * f64(n) * alp)
    let (stk, es) = mem.alloc[usize](a, 2usize * cap)
    if es != ok { ret (0usize, es) }
    let base = mem.mark(a)
    var top = 1usize
    stk[0usize] = 0usize
    stk[1usize] = n - 1usize
    while top > 0usize {
        top -= 1usize
        let l = stk[2usize * top]
        let r = stk[2usize * top + 1usize]
        if r - l >= fc && srt[l] != srt[r] {
            var m = (l + r) / 2usize
            let t = srt[m]
            while m < r && srt[m + 1usize] == t { m += 1usize }
            if m != r {
                if nv >= cap { ret (0usize, TooManyVertices) }
                var dup = false
                var q = 2usize
                while q < nv {
                    if vt[q * VS + V_X] == t { dup = true }
                    q += 1usize
                }
                if !dup {
                    let e = vertex(a, x, y, sp, pc, t, vt[nv * VS..nv * VS + VS], vt[0usize..0usize])
                    mem.reset(a, base)
                    if e != ok { ret (0usize, e) }
                    nv += 1usize
                }
                stk[2usize * top] = l
                stk[2usize * top + 1usize] = m
                stk[2usize * top + 2usize] = m + 1usize
                stk[2usize * top + 3usize] = r
                top += 2usize
            }
        }
    }
    sort_vertices(vt, nv)
    ret (nv, ok)
}

// one fitted quantity of vertex v: a (value, slope) pair
fn pair(vt: []const f64, v: usize, what: usize, hasd: bool, out: []f64) {
    out[1usize] = 0.0f64
    let b = v * VS
    if what == W_COEF {
        out[0usize] = vt[b + V_C0]
        if hasd { out[1usize] = vt[b + V_C1] }
        ret
    }
    if what == W_NLX {
        out[0usize] = vt[b + V_N0]
        if hasd { out[1usize] = vt[b + V_N1] }
        ret
    }
    if what == W_T0 {
        out[0usize] = vt[b + V_T0]
        if hasd { out[1usize] = vt[b + V_T1] }
        ret
    }
    if what == W_LIK {
        out[0usize] = vt[b + V_LIK]
        ret
    }
    out[0usize] = vt[b + V_TR0] - vt[b + V_TR2]
}

// the interpolant at x0 over the sorted vertices (tree, kdtree, grid), the cubic Hermite of rectcell_interp
fn interp(vt: []const f64, nv: usize, what: usize, hasd: bool, x0: f64) -> f64 {
    var pla = [2]f64{ 0.0f64, 0.0f64 }
    let pl = pla[0usize..2usize]
    var pra = [2]f64{ 0.0f64, 0.0f64 }
    let pr = pra[0usize..2usize]
    if nv == 1usize {
        pair(vt, 0usize, what, hasd, pl)
        ret pl[0usize]
    }
    var j = 0usize
    while j + 2usize < nv && vt[(j + 1usize) * VS + V_X] <= x0 { j += 1usize }
    pair(vt, j, what, hasd, pl)
    pair(vt, j + 1usize, what, hasd, pr)
    let xl = vt[j * VS + V_X]
    let xr = vt[(j + 1usize) * VS + V_X]
    let z = xr - xl
    let nc1 = !hasd || what == W_LIK || what == W_RDF
    var f = 0.0f64
    if nc1 {
        if z == 0.0f64 {
            f = pl[0usize]
        } else {
            let hh = x0 - xl
            f = ((z - hh) * pl[0usize] + hh * pr[0usize]) / z
        }
    } else {
        var p0 = 1.0f64
        var p1 = 0.0f64
        var p2 = 0.0f64
        var p3 = 0.0f64
        if z != 0.0f64 {
            let h = (x0 - xl) / z
            if h < 0.0f64 {
                p2 = h
            } else {
                if h > 1.0f64 {
                    p0 = 0.0f64
                    p1 = 1.0f64
                    p3 = h - 1.0f64
                } else {
                    p1 = h * h * (3.0f64 - 2.0f64 * h)
                    p0 = 1.0f64 - p1
                    p2 = h * (1.0f64 - h) * (1.0f64 - h)
                    p3 = h * h * (h - 1.0f64)
                }
            }
        }
        p2 = p2 * z
        p3 = p3 * z
        f = p0 * pl[0usize] + p1 * pr[0usize] + p2 * pl[1usize] + p3 * pr[1usize]
    }
    if (what == W_T0 || what == W_NLX) && f < 0.0f64 { f = 0.0f64 }
    ret f
}

// the fit's quantity at data point i: the vertex itself for dat, the interpolant otherwise
fn at_data(vt: []const f64, nv: usize, sp: []const f64, pc: *Pc, what: usize, x: []const f64, i: usize) -> f64 {
    let hasd = sp[1usize] > 0.0f64
    if usize(sp[5usize]) == 2usize {
        var pla = [2]f64{ 0.0f64, 0.0f64 }
    let pl = pla[0usize..2usize]
        pair(vt, i, what, hasd, pl)
        var f = pl[0usize]
        if (what == W_T0 || what == W_NLX) && f < 0.0f64 { f = 0.0f64 }
        ret f + addpar(pc, usize(sp[1usize]), what, x[i])
    }
    ret interp(vt, nv, what, hasd, x[i]) + addpar(pc, usize(sp[1usize]), what, x[i])
}

// the fit's quantity at x0 (not for dat, which R cannot interpolate)
fn at(vt: []const f64, nv: usize, sp: []const f64, pc: *Pc, what: usize, x0: f64) -> f64 {
    ret interp(vt, nv, what, sp[1usize] > 0.0f64, x0) + addpar(pc, usize(sp[1usize]), what, x0)
}

// out = (log likelihood, trace of the hat matrix, its variance trace, residual variance): ressumm
fn summ(x: []const f64, y: []const f64, sp: []const f64, pc: *Pc, vt: []const f64, nv: usize, out: []f64) {
    let n = x.len
    let fam = famcode(sp)
    var ra = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let r = ra[0usize..4usize]
    var llk = 0.0f64
    var df0 = 0.0f64
    var df1 = 0.0f64
    var r1 = 0.0f64
    var r2 = 0.0f64
    var i = 0usize
    while i < n {
        let th = at_data(vt, nv, sp, pc, W_COEF, x, i)
        let _ = links(fam, th, y[i], y[n + i], 1.0f64, r)
        var t1 = at_data(vt, nv, sp, pc, W_NLX, x, i)
        var t0 = at_data(vt, nv, sp, pc, W_T0, x, i)
        t1 = t1 * t1 * r[3usize]
        t0 = t0 * t0 * r[3usize]
        if t1 > 1.0f64 { t1 = 1.0f64 }
        if t0 > 1.0f64 { t0 = 1.0f64 }
        llk += r[0usize]
        df0 += t0
        df1 += t1
        if y[n + i] > 0.0f64 {
            r1 += r[2usize] * r[2usize] / y[n + i]
            r2 += r[3usize] / y[n + i]
        }
        i += 1usize
    }
    var rv = 1.0f64
    if sp[8usize] == 1.0f64 {
        let rdf = f64(n) - 2.0f64 * df0 + df1
        if rdf >= 1.0f64 { rv = r1 / r2 * f64(n) / rdf }
    }
    out[0usize] = llk
    out[1usize] = df0
    out[2usize] = df1
    out[3usize] = rv
}

// predict(se.fit = TRUE) standard error at x0: kind 0 global, 1 local, 2 prediction; rv the residual variance
fn se(vt: []const f64, nv: usize, sp: []const f64, pc: *Pc, rv: f64, x0: f64, kind: usize) -> f64 {
    var s = at(vt, nv, sp, pc, W_NLX, x0)
    if kind == 0usize { ret s * math.sqrt[f64](rv) }
    if kind == 1usize {
        let lik = at(vt, nv, sp, pc, W_LIK, x0)
        let rdf = at(vt, nv, sp, pc, W_RDF, x0)
        ret s * math.sqrt[f64](0.0f64 - 2.0f64 * lik / rdf)
    }
    ret math.sqrt[f64](rv) * math.sqrt[f64](1.0f64 + s * s)
}
