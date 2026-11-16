// R cmprsk::crr, the point estimates: Fine-Gray regression of the subdistribution hazard of cause 1, Newton steps
// with step halving on Gray's `crrfsv` (objective, score, information) and `crrf` (objective), written line for line,
// with the censoring distribution weights of `crr` (Kaplan-Meier per censoring group, left limits).
//
// Data are sorted by time. ici is 0 censored, 1 the cause, 2 another cause; x (n by ncov) and x2 (n by ncov2) are
// column-major, tf (ndf by ncov2, column-major) the time functions of x2 at the distinct cause times; wt (ncg by n,
// column-major) holds the censoring weights; icg is the 0-based censoring group.
//
// Not here: the variance (`crrvv`), residuals, predict.crr.

use e.algo.stat.psych as ps
use e.math
use e.mem

type Data = struct { t2: []const f64, ici: []const i64, n: usize, x: []const f64, ncov: usize, x2: []const f64, ncov2: usize, tf: []const f64, ndf: usize, wt: []const f64, ncg: usize, icg: []const i64 }

// the weight for observation i, the censoring group's survival at the time; kept as the left limit
fn covt(d: *const Data, j: usize, k: usize, b: []const f64, xbt: []f64) -> f64 {
    var wk = 0.0f64
    var i = 0usize
    while i < d.ncov {
        xbt[i] = d.x[j + d.n * i]
        wk += xbt[i] * b[i]
        i += 1usize
    }
    i = 0usize
    while i < d.ncov2 {
        xbt[i + d.ncov] = d.x2[j + d.n * i] * d.tf[k + d.ndf * i]
        wk += xbt[i + d.ncov] * b[d.ncov + i]
        i += 1usize
    }
    ret wk
}

// Kaplan-Meier of the censoring times per group, evaluated just before each observation time: ncg by n column-major
fn censor_weights(a: *mem.Arena, t2: []const f64, ici: []const i64, icg: []const i64, ncg: usize, out: []f64) {
    let n = t2.len
    var g = 0usize
    while g < ncg {
        var i = 0usize
        var s = 1.0f64
        var tmax = 0.0f64
        var q = 0usize
        while q < n {
            if usize(icg[q]) == g { tmax = t2[q] }
            q += 1usize
        }
        while i < n {
            // every observation with time t2[i] sees the survival before any censoring at t2[i]
            var e = i
            while e + 1usize < n && t2[e + 1usize] == t2[i] { e += 1usize }
            var atrisk = 0.0f64
            var j = i
            while j < n {
                if usize(icg[j]) == g { atrisk += 1.0f64 }
                j += 1usize
            }
            var dc = 0.0f64
            j = i
            while j <= e {
                // R's approx() runs out at the group's last time and answers 0 beyond it
                if t2[j] * (1.0f64 - 2.220446049250313e-14f64) > tmax * (1.0f64 + 2.220446049250313e-15f64) { out[g + ncg * j] = 0.0f64 } else { out[g + ncg * j] = s }
                if usize(icg[j]) == g && ici[j] == 0i64 { dc += 1.0f64 }
                j += 1usize
            }
            if atrisk > 0.0f64 { s = s * (1.0f64 - dc / atrisk) }
            i = e + 1usize
        }
        g += 1usize
    }
}

// objective (negative log partial likelihood), with the score s and information v at b
fn crrfsv(a: *mem.Arena, d: *const Data, b: []const f64, np: usize, s: []f64, v: []f64) -> f64 {
    let n = d.n
    let (xb, e1) = mem.alloc[f64](a, np)
    let (xbt, e2) = mem.alloc[f64](a, np)
    let (vt, e3) = mem.alloc[f64](a, np * np)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var lik = 0.0f64
    var i = 0usize
    while i < np {
        s[i] = 0.0f64
        var j = 0usize
        while j < np { v[i + np * j] = 0.0f64
            j += 1usize }
        i += 1usize
    }
    var iuc = n
    var ldf = d.ndf + 1usize
    while true {
        // the next failure time, scanning down
        var found = false
        var cft = 0.0f64
        var q = iuc
        while q >= 1usize {
            if d.ici[q - 1usize] == 1i64 {
                cft = d.t2[q - 1usize]
                found = true
                break
            }
            q -= 1usize
        }
        if !found { ret lik }
        iuc = q
        ldf -= 1usize
        var twf = 0.0f64
        var itmp = iuc
        i = iuc
        while i >= 1usize {
            if d.t2[i - 1usize] < cft { break }
            itmp = i
            if d.ici[i - 1usize] == 1i64 {
                let wk = covt(d, i - 1usize, ldf - 1usize, b, xbt)
                twf += 1.0f64
                lik = lik - wk
                var j = 0usize
                while j < np { s[j] = s[j] - xbt[j]
                    j += 1usize }
            }
            i -= 1usize
        }
        iuc = itmp
        var xb1 = 0.0f64
        var xb1o = 0.0f64
        i = 0usize
        while i < np {
            xb[i] = 0.0f64
            var j = 0usize
            while j < np { vt[i + np * j] = 0.0f64
                j += 1usize }
            i += 1usize
        }
        i = 1usize
        while i <= n {
            var twt = 0.0f64
            var skip = false
            if d.t2[i - 1usize] < cft {
                if d.ici[i - 1usize] <= 1i64 { skip = true } else {
                    let wk = covt(d, i - 1usize, ldf - 1usize, b, xbt)
                    let g = usize(d.icg[i - 1usize])
                    twt = math.exp[f64](wk) * d.wt[g + d.ncg * (iuc - 1usize)] / d.wt[g + d.ncg * (i - 1usize)]
                }
            } else {
                let wk = covt(d, i - 1usize, ldf - 1usize, b, xbt)
                twt = math.exp[f64](wk)
            }
            if !skip {
                xb1 += twt
                var j = 0usize
                while j < np {
                    xb[j] += twt * xbt[j]
                    xbt[j] = xbt[j] - xb[j] / xb1
                    j += 1usize
                }
                if xb1o > 0.0f64 {
                    twt = xb1 * twt / xb1o
                    var k = 0usize
                    while k < np {
                        j = k
                        while j < np {
                            vt[k + np * j] += twt * xbt[k] * xbt[j]
                            j += 1usize
                        }
                        k += 1usize
                    }
                }
                xb1o = xb1
            }
            i += 1usize
        }
        lik = lik + twf * math.log[f64](xb1)
        let twt = twf / xb1
        i = 0usize
        while i < np {
            s[i] += twt * xb[i]
            var j = i
            while j < np {
                v[i + np * j] += twt * vt[i + np * j]
                v[j + np * i] = v[i + np * j]
                j += 1usize
            }
            i += 1usize
        }
        iuc -= 1usize
        if iuc == 0usize { ret lik }
    }
}

// objective only
fn crrf(d: *const Data, b: []const f64, np: usize, xbt: []f64) -> f64 {
    let n = d.n
    var lik = 0.0f64
    var iuc = n
    var ldf = d.ndf + 1usize
    while true {
        var found = false
        var cft = 0.0f64
        var q = iuc
        while q >= 1usize {
            if d.ici[q - 1usize] == 1i64 {
                cft = d.t2[q - 1usize]
                found = true
                break
            }
            q -= 1usize
        }
        if !found { ret lik }
        iuc = q
        ldf -= 1usize
        var twf = 0.0f64
        var itmp = iuc
        var i = iuc
        while i >= 1usize {
            if d.t2[i - 1usize] < cft { break }
            itmp = i
            if d.ici[i - 1usize] == 1i64 {
                let wk = covt(d, i - 1usize, ldf - 1usize, b, xbt)
                twf += 1.0f64
                lik = lik - wk
            }
            i -= 1usize
        }
        iuc = itmp
        var xb1 = 0.0f64
        i = 1usize
        while i <= n {
            if d.t2[i - 1usize] < cft {
                if d.ici[i - 1usize] > 1i64 {
                    let wk = covt(d, i - 1usize, ldf - 1usize, b, xbt)
                    let g = usize(d.icg[i - 1usize])
                    xb1 += math.exp[f64](wk) * d.wt[g + d.ncg * (iuc - 1usize)] / d.wt[g + d.ncg * (i - 1usize)]
                }
            } else {
                let wk = covt(d, i - 1usize, ldf - 1usize, b, xbt)
                xb1 += math.exp[f64](wk)
            }
            i += 1usize
        }
        lik = lik + twf * math.log[f64](xb1)
        iuc -= 1usize
        if iuc == 0usize { ret lik }
    }
}

type Fit = struct { loglik: f64, loglik_null: f64, converged: bool }

// b holds the start and receives the coefficients; score receives the score at the answer (the sign of R's `score`)
fn crr(a: *mem.Arena, d: *const Data, np: usize, gtol: f64, maxiter: usize, b: []f64, score: []f64) -> (Fit, err) {
    var fit: Fit = zero
    let (s, e1) = mem.alloc[f64](a, np)
    let (h, e2) = mem.alloc[f64](a, np * np)
    let (inv, e3) = mem.alloc[f64](a, np * np)
    let (sc, e4) = mem.alloc[f64](a, np)
    let (bn, e5) = mem.alloc[f64](a, np)
    let (xbt, e6) = mem.alloc[f64](a, np)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret (fit, e1) }
    var lik = 0.0f64
    var ll = 0usize
    while true {
        lik = crrfsv(a, d, b, np, s, h)
        var m1 = 0.0f64
        var j = 0usize
        while j < np {
            var bj = math.abs[f64](b[j])
            if bj < 1.0f64 { bj = 1.0f64 }
            let t = math.abs[f64](s[j]) * bj
            if t > m1 { m1 = t }
            j += 1usize
        }
        var sl = math.abs[f64](lik)
        if sl < 1.0f64 { sl = 1.0f64 }
        if m1 < sl * gtol {
            fit.converged = true
            break
        }
        if ll == maxiter {
            fit.converged = false
            break
        }
        if !ps.invert(a, h, np, inv) { ret (fit, Singular) }
        j = 0usize
        while j < np {
            var t = 0.0f64
            var l = 0usize
            while l < np {
                t += inv[j * np + l] * s[l]
                l += 1usize
            }
            sc[j] = 0.0f64 - t
            bn[j] = b[j] + sc[j]
            j += 1usize
        }
        var fbn = crrf(d, bn, np, xbt)
        var i = 0usize
        var slope = 0.0f64
        j = 0usize
        while j < np { slope += sc[j] * s[j]
            j += 1usize }
        while fbn != fbn || fbn > lik + 1.0e-4f64 * slope {
            i += 1usize
            j = 0usize
            while j < np {
                sc[j] = sc[j] * 0.5f64
                bn[j] = b[j] + sc[j]
                j += 1usize
            }
            fbn = crrf(d, bn, np, xbt)
            if i > 20usize { break }
            slope = 0.0f64
            j = 0usize
            while j < np { slope += sc[j] * s[j]
                j += 1usize }
        }
        if i > 20usize {
            fit.converged = false
            break
        }
        j = 0usize
        while j < np { b[j] = bn[j]
            j += 1usize }
        ll += 1usize
    }
    var j = 0usize
    while j < np {
        score[j] = 0.0f64 - s[j]
        j += 1usize
    }
    fit.loglik = 0.0f64 - lik
    var z0 = 0usize
    while z0 < np { bn[z0] = 0.0f64
        z0 += 1usize }
    fit.loglik_null = 0.0f64 - crrf(d, bn, np, xbt)
    ret (fit, ok)
}

error Singular
