// R gsDesign: the alpha spending functions of group sequential designs: Hwang-Shih-DeCani (sfHSD), power (sfPower), exponential
// (sfExponential), logistic, normal, Cauchy and extreme-value families in their two-parameter form (a, b), the beta distribution,
// and the Lan-DeMets O'Brien-Fleming and Pocock approximations. Each gives the cumulative alpha spent at information fraction t (capped at 1).
//
// And gsDesign() for test types 1 to 5 (one-sided, symmetric, binding beta spending, asymmetric, binding with astar) with the spending
// families and the O'Brien-Fleming, Pocock and Wang-Tsiatis bounds, sizing or given information; gsProbability (`gsprob`), gsCP (`gscp`),
// nNormal, nBinomial and nSurv (T and minfup given, one stratum, all four methods, sample size or power).
//
// Not here: the four-point parameterisations that solve for (a, b), sfPoints, sfStep, test types 6 to 8, separate spending times (usTime,
// lsTime), nSurv with several strata or an unknown T / minfup, gsSurv.

use e.math
use e.math.dist as dist
use e.math.nmath_beta as nb
use e.mem
use e.algo.stat.pwr as pw

fn pi() -> f64 { ret 3.141592653589793238462643383279f64 }

// kind: 0 HSD(gamma), 1 power(rho), 2 exponential(nu), 3 logistic(a, b), 4 normal(a, b), 5 Cauchy(a, b), 6 extreme value(a, b), 7 beta(a, b),
// 8 LDOF(rho; 1 is the plain approximation), 9 LDPocock
fn spend(kind: usize, alpha: f64, t0: f64, p1: f64, p2: f64) -> f64 {
    var t = t0
    if t > 1.0f64 { t = 1.0f64 }
    if kind == 0usize {
        if p1 == 0.0f64 { ret t * alpha }
        ret alpha * (1.0f64 - math.exp[f64](0.0f64 - t * p1)) / (1.0f64 - math.exp[f64](0.0f64 - p1))
    }
    if kind == 1usize { ret alpha * math.pow[f64](t, p1) }
    if kind == 2usize { ret math.pow[f64](alpha, math.pow[f64](t, 0.0f64 - p1)) }
    if kind == 8usize {
        let z = 0.0f64 - dist.qnorm(alpha / 2.0f64, 0.0f64, 1.0f64, true, false)
        ret 2.0f64 * (1.0f64 - dist.pnorm(z / math.pow[f64](t, p1 / 2.0f64), 0.0f64, 1.0f64, true, false))
    }
    if kind == 9usize { ret alpha * math.log[f64](1.0f64 + (math.exp[f64](1.0f64) - 1.0f64) * t) }
    if kind == 7usize { ret alpha * nb.pbeta(t, p1, p2, true, false) }
    if t >= 1.0f64 { ret alpha }
    if kind == 3usize {
        let xv = math.log[f64](t / (1.0f64 - t))
        let y = math.exp[f64](p1 + p2 * xv)
        ret alpha * y / (1.0f64 + y)
    }
    if kind == 4usize {
        let xv = dist.qnorm(t, 0.0f64, 1.0f64, true, false)
        ret alpha * dist.pnorm(p1 + p2 * xv, 0.0f64, 1.0f64, true, false)
    }
    if kind == 5usize {
        let xv = math.tan[f64](pi() * (t - 0.5f64))
        ret alpha * (0.5f64 + math.atan[f64](p1 + p2 * xv) / pi())
    }
    let xv = 0.0f64 - math.log[f64](0.0f64 - math.log[f64](t))
    ret alpha * math.exp[f64](0.0f64 - math.exp[f64](0.0f64 - p1 - p2 * xv))
}

// ---- the numerical integration of Jennison and Turnbull (gridpts, h1, hupdate, probrej, gsbound, gsbound1) as gsDesign's C code does it ----

fn pn(x: f64, lower: bool) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, lower, false) }

fn qn(p: f64, lower: bool) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, lower, false) }

fn xz() -> f64 { ret 20.0f64 }

fn rsq2pi() -> f64 { ret 0.3989422804014327f64 }

fn buf(ar: *mem.Arena, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](ar, n)
    if e != ok { ret s }
    var i = 0usize
    while i < s.len {
        s[i] = 0.0f64
        i += 1usize
    }
    ret s
}

fn fsum(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s
}

fn neg(ar: *mem.Arena, x: []const f64) -> []f64 {
    let o = buf(ar, x.len)
    var i = 0usize
    while i < x.len {
        o[i] = 0.0f64 - x[i]
        i += 1usize
    }
    ret o
}

fn const_vec(ar: *mem.Arena, n: usize, v: f64) -> []f64 {
    let o = buf(ar, n)
    var i = 0usize
    while i < n {
        o[i] = v
        i += 1usize
    }
    ret o
}

// last valid index written (the C `gridpts`)
fn gridpts(r: usize, mu: f64, lo: f64, hi: f64, z: []f64, w: []f64) -> usize {
    let rd = f64(r)
    let r2 = 2.0f64 * rd
    let r6 = 6usize * r
    let r5 = 5usize * r
    var j = 0usize
    var done = false
    w[0usize] = 0.0f64
    let zt0 = mu - 3.0f64 - 4.0f64 * math.log[f64](rd)
    if zt0 <= lo {
        z[0usize] = lo
    } else if zt0 >= hi {
        z[0usize] = hi
        w[0usize] = 0.0f64
        done = true
    } else {
        z[0usize] = zt0
    }
    var i = 2usize
    while i < r6 && !done {
        var zt = 0.0f64
        if i < r {
            zt = mu - 3.0f64 - 4.0f64 * math.log[f64](rd / f64(i))
        } else if i <= r5 {
            zt = mu + 3.0f64 * (0.0f64 - 1.0f64 + f64(i - r) / r2)
        } else {
            zt = mu + 3.0f64 + 4.0f64 * math.log[f64](rd / f64(r6 - i))
        }
        if zt > lo {
            j += 2usize
            z[j] = zt
            if zt >= hi {
                z[j] = hi
                done = true
            }
            z[j - 1usize] = (z[j] + z[j - 2usize]) / 2.0f64
        }
        i += 1usize
    }
    if j > 0usize {
        w[0usize] = (z[2usize] - z[0usize]) / 6.0f64
        w[j] = (z[j] - z[j - 2usize]) / 6.0f64
        w[j - 1usize] = 2.0f64 * (z[j] - z[j - 2usize]) / 3.0f64
    }
    var q = 1usize
    while q + 1usize < j {
        w[q] = 2.0f64 * (z[q + 1usize] - z[q - 1usize]) / 3.0f64
        w[q + 1usize] = (z[q + 3usize] - z[q - 1usize]) / 6.0f64
        q += 2usize
    }
    ret j
}

fn h1(theta: f64, m: usize, wgt: []const f64, info: f64, z: []const f64, h: []f64) {
    let mu = theta * math.sqrt[f64](info)
    var i = 0usize
    while i <= m {
        let x = z[i] - mu
        h[i] = wgt[i] * math.exp[f64](0.0f64 - x * x / 2.0f64) * rsq2pi()
        i += 1usize
    }
}

fn hupdate(theta: f64, wgt: []const f64, m1: usize, ikm1: f64, zkm1: []const f64, hkm1: []const f64, m2: usize, ik: f64, zk: []const f64, hk: []f64) {
    let deltak = ik - ikm1
    let rtdeltak = math.sqrt[f64](deltak)
    let rtik = math.sqrt[f64](ik)
    let rtikm1 = math.sqrt[f64](ikm1)
    var i = 0usize
    while i <= m2 {
        hk[i] = 0.0f64
        var ii = 0usize
        while ii <= m1 {
            let x = (zk[i] * rtik - zkm1[ii] * rtikm1 - theta * deltak) / rtdeltak
            hk[i] += hkm1[ii] * math.exp[f64](0.0f64 - x * x / 2.0f64) * rsq2pi() * rtik / rtdeltak
            ii += 1usize
        }
        hk[i] *= wgt[i]
        i += 1usize
    }
}

// probpos (upper) and probneg (lower): the probability of crossing bk at analysis k given the density h on the grid z at k - 1
fn probx(theta: f64, m: usize, bk: f64, z: []const f64, h: []const f64, ikm1: f64, ik: f64, upper: bool) -> f64 {
    let mu = theta * (ik - ikm1)
    let rtdeltak = math.sqrt[f64](ik - ikm1)
    let rtik = math.sqrt[f64](ik)
    let rtikm1 = math.sqrt[f64](ikm1)
    var prob = 0.0f64
    var i = 0usize
    while i <= m {
        let x = (z[i] * rtikm1 + mu - bk * rtik) / rtdeltak
        prob += pn(x, upper) * h[i]
        i += 1usize
    }
    ret prob
}

// one theta of C probrej: plo and phi receive the nanal rejection probabilities from offset off
fn probrej1(ar: *mem.Arena, theta: f64, info: []const f64, lo: []const f64, hi: []const f64, r: usize, plo: []f64, phi: []f64, off: usize) {
    let nanal = info.len
    let wk = 12usize * r + 8usize
    var z1 = buf(ar, wk)
    var w1 = buf(ar, wk)
    var h = buf(ar, wk)
    var z2 = buf(ar, wk)
    var w2 = buf(ar, wk)
    var h2 = buf(ar, wk)
    var mu = theta * math.sqrt[f64](info[0usize])
    plo[off] = pn(mu - lo[0usize], false)
    phi[off] = pn(hi[0usize] - mu, false)
    var m1 = gridpts(r, mu, lo[0usize], hi[0usize], z1, w1)
    h1(theta, m1, w1, info[0usize], z1, h)
    var i = 1usize
    while i < nanal {
        phi[off + i] = probx(theta, m1, hi[i], z1, h, info[i - 1usize], info[i], true)
        plo[off + i] = probx(theta, m1, lo[i], z1, h, info[i - 1usize], info[i], false)
        if i < nanal - 1usize {
            mu = theta * math.sqrt[f64](info[i])
            let m2 = gridpts(r, mu, lo[i], hi[i], z2, w2)
            hupdate(theta, w2, m1, info[i - 1usize], z1, h, m2, info[i], z2, h2)
            m1 = m2
            let tz = z1
            z1 = z2
            z2 = tz
            let tw = w1
            w1 = w2
            w2 = tw
            let th = h
            h = h2
            h2 = th
        }
        i += 1usize
    }
}

type Prob = struct { nanal: usize, ntheta: usize, plo: []f64, phi: []f64, powr: []f64, futile: []f64, en: []f64 }

// gsprob: the nanal x ntheta probabilities are column-major (theta varies slowest) as in R
fn gsprob(ar: *mem.Arena, theta: []const f64, info: []const f64, lo: []const f64, hi: []const f64, r: usize, overrun: f64) -> Prob {
    let nanal = info.len
    let nt = theta.len
    let plo = buf(ar, nanal * nt)
    let phi = buf(ar, nanal * nt)
    let powr = buf(ar, nt)
    let futile = buf(ar, nt)
    let en = buf(ar, nt)
    let iover = buf(ar, nanal)
    var q = 0usize
    while q < nanal {
        iover[q] = info[q] + overrun
        if iover[q] > info[nanal - 1usize] { iover[q] = info[nanal - 1usize] }
        q += 1usize
    }
    iover[nanal - 1usize] = info[nanal - 1usize]
    var t = 0usize
    while t < nt {
        probrej1(ar, theta[t], info, lo, hi, r, plo, phi, t * nanal)
        var i = 0usize
        var sp = 0.0f64
        var sl = 0.0f64
        var se = 0.0f64
        while i < nanal {
            sp += phi[t * nanal + i]
            sl += plo[t * nanal + i]
            se += iover[i] * (plo[t * nanal + i] + phi[t * nanal + i])
            i += 1usize
        }
        powr[t] = sp
        futile[t] = sl
        en[t] = se + info[nanal - 1usize] * (1.0f64 - sp - sl)
        t += 1usize
    }
    ret Prob { nanal: nanal, ntheta: nt, plo: plo, phi: phi, powr: powr, futile: futile, en: en }
}

fn gsprob1(ar: *mem.Arena, theta: f64, info: []const f64, lo: []const f64, hi: []const f64, r: usize) -> Prob {
    let th = buf(ar, 1usize)
    th[0usize] = theta
    ret gsprob(ar, th, info, lo, hi, r, 0.0f64)
}

type Bnd = struct { lo: []f64, hi: []f64, fail: i64 }

// C gsbound: lower (a) and upper (b) bounds under theta = 0 from the spend of each at every analysis
fn gsbound(ar: *mem.Arena, info: []const f64, problo: []const f64, probhi: []const f64, tol: f64, r: usize) -> Bnd {
    let nanal = info.len
    let av = buf(ar, nanal)
    let bv = buf(ar, nanal)
    if problo[0usize] <= 0.0f64 { av[0usize] = 0.0f64 - xz() } else { av[0usize] = qn(problo[0usize], true) }
    if probhi[0usize] <= 0.0f64 { bv[0usize] = xz() } else { bv[0usize] = qn(probhi[0usize], false) }
    let wk = 12usize * r + 8usize
    var z1 = buf(ar, wk)
    var w1 = buf(ar, wk)
    var h = buf(ar, wk)
    var z2 = buf(ar, wk)
    var w2 = buf(ar, wk)
    var h2 = buf(ar, wk)
    var m1 = gridpts(r, 0.0f64, av[0usize], bv[0usize], z1, w1)
    h1(0.0f64, m1, w1, info[0usize], z1, h)
    var rtik = math.sqrt[f64](info[0usize])
    var i = 1usize
    while i < nanal {
        let rtikm1 = rtik
        rtik = math.sqrt[f64](info[i])
        let rtdeltak = math.sqrt[f64](info[i] - info[i - 1usize])
        var atem2 = 0.0f64
        var btem2 = 0.0f64
        var atem = 0.0f64
        var btem = 0.0f64
        if problo[i] <= 0.0f64 { atem2 = 0.0f64 - xz() } else { atem2 = qn(problo[i], true) }
        if probhi[i] <= 0.0f64 { btem2 = xz() } else { btem2 = qn(probhi[i], false) }
        var adelta = 1.0f64
        var bdelta = 1.0f64
        var j = 0usize
        while (adelta > tol || bdelta > tol) && j < 20usize {
            j += 1usize
            var plo = 0.0f64
            var phi = 0.0f64
            var dplo = 0.0f64
            var dphi = 0.0f64
            atem = atem2
            btem = btem2
            var ii = 0usize
            while ii <= m1 {
                let xlo = (z1[ii] * rtikm1 - atem * rtik) / rtdeltak
                let xhi = (z1[ii] * rtikm1 - btem * rtik) / rtdeltak
                plo += h[ii] * pn(xlo, false)
                phi += h[ii] * pn(xhi, true)
                dplo += h[ii] * math.exp[f64](0.0f64 - xlo * xlo / 2.0f64) * rsq2pi() * rtik / rtdeltak
                dphi -= h[ii] * math.exp[f64](0.0f64 - xhi * xhi / 2.0f64) * rsq2pi() * rtik / rtdeltak
                ii += 1usize
            }
            adelta = problo[i] - plo
            if adelta > dplo {
                atem2 = atem + 1.0f64
            } else if adelta < 0.0f64 - dplo {
                atem2 = atem - 1.0f64
            } else {
                atem2 = atem + (problo[i] - plo) / dplo
            }
            if atem2 > xz() { atem2 = xz() } else if atem2 < 0.0f64 - xz() { atem2 = 0.0f64 - xz() }
            bdelta = probhi[i] - phi
            if bdelta < dphi {
                btem2 = btem + 1.0f64
            } else if bdelta > 0.0f64 - dphi {
                btem2 = btem - 1.0f64
            } else {
                btem2 = btem + (probhi[i] - phi) / dphi
            }
            if btem2 > xz() { btem2 = xz() } else if btem2 < 0.0f64 - xz() { btem2 = 0.0f64 - xz() }
            if atem2 > btem2 { atem2 = btem2 }
            adelta = math.abs[f64](atem2 - atem)
            bdelta = math.abs[f64](btem2 - btem)
        }
        av[i] = atem
        bv[i] = btem
        if adelta > tol || bdelta > tol { ret Bnd { lo: av, hi: bv, fail: 1i64 } }
        if i < nanal - 1usize {
            let m2 = gridpts(r, 0.0f64, av[i], bv[i], z2, w2)
            hupdate(0.0f64, w2, m1, info[i - 1usize], z1, h, m2, info[i], z2, h2)
            m1 = m2
            let tz = z1
            z1 = z2
            z2 = tz
            let tw = w1
            w1 = w2
            w2 = tw
            let th = h
            h = h2
            h2 = th
        }
        i += 1usize
    }
    ret Bnd { lo: av, hi: bv, fail: 0i64 }
}

// R gsBound1 (the C gsbound1 plus its R-side repair of crossed bounds): the upper bound b that spends probhi given
// the fixed lower bound alo and drift theta; lo receives the lower crossing probability at each analysis
fn gsbound1(ar: *mem.Arena, theta: f64, info: []const f64, alo: []const f64, probhi: []const f64, tol: f64, r: usize) -> Bnd {
    let nanal = info.len
    let bv = buf(ar, nanal)
    let pl = buf(ar, nanal)
    var rtik = math.sqrt[f64](info[0usize])
    var mu = rtik * theta
    pl[0usize] = pn(mu - alo[0usize], false)
    if probhi[0usize] <= 0.0f64 { bv[0usize] = xz() } else { bv[0usize] = dist.qnorm(probhi[0usize], mu, 1.0f64, false, false) }
    var bad = 0i64
    if nanal > 1usize {
        let wk = 12usize * r + 8usize
        var z1 = buf(ar, wk)
        var w1 = buf(ar, wk)
        var h = buf(ar, wk)
        var z2 = buf(ar, wk)
        var w2 = buf(ar, wk)
        var h2 = buf(ar, wk)
        var m1 = gridpts(r, mu, alo[0usize], bv[0usize], z1, w1)
        h1(theta, m1, w1, info[0usize], z1, h)
        var i = 1usize
        while i < nanal {
            let rtikm1 = rtik
            rtik = math.sqrt[f64](info[i])
            mu = rtik * theta
            let rtdeltak = math.sqrt[f64](info[i] - info[i - 1usize])
            var btem2 = 0.0f64
            var btem = 0.0f64
            var plo = 0.0f64
            if probhi[i] <= 0.0f64 { btem2 = xz() } else { btem2 = dist.qnorm(probhi[i], mu, 1.0f64, false, false) }
            var bdelta = 1.0f64
            var j = 0usize
            while bdelta > tol && j < 20usize {
                j += 1usize
                var phi = 0.0f64
                var dphi = 0.0f64
                plo = 0.0f64
                btem = btem2
                var ii = 0usize
                while ii <= m1 {
                    let xhi = (z1[ii] * rtikm1 - btem * rtik + theta * (info[i] - info[i - 1usize])) / rtdeltak
                    phi += pn(xhi, true) * h[ii]
                    let xlo = (z1[ii] * rtikm1 - alo[i] * rtik + theta * (info[i] - info[i - 1usize])) / rtdeltak
                    plo += pn(xlo, false) * h[ii]
                    dphi -= h[ii] * math.exp[f64](0.0f64 - xhi * xhi / 2.0f64) * rsq2pi() * rtik / rtdeltak
                    ii += 1usize
                }
                bdelta = probhi[i] - phi
                if bdelta < dphi {
                    btem2 = btem + 1.0f64
                } else if bdelta > 0.0f64 - dphi {
                    btem2 = btem - 1.0f64
                } else {
                    btem2 = btem + (probhi[i] - phi) / dphi
                }
                if btem2 > xz() { btem2 = xz() } else if btem2 < 0.0f64 - xz() { btem2 = 0.0f64 - xz() }
                bdelta = math.abs[f64](btem2 - btem)
            }
            bv[i] = btem
            pl[i] = plo
            if bdelta > tol { bad = 1i64 }
            if i < nanal - 1usize {
                let m2 = gridpts(r, mu, alo[i], bv[i], z2, w2)
                hupdate(theta, w2, m1, info[i - 1usize], z1, h, m2, info[i], z2, h2)
                m1 = m2
                let tz = z1
                z1 = z2
                z2 = tz
                let tw = w1
                w1 = w2
                w2 = tw
                let th = h
                h = h2
                h2 = th
            }
            i += 1usize
        }
    }
    if bad == 0i64 {
        var crossed = false
        var q = 0usize
        while q < nanal {
            if bv[q] - alo[q] < 0.0f64 {
                bv[q] = alo[q]
                crossed = true
            }
            q += 1usize
        }
        if crossed {
            let zp = gsprob1(ar, theta, info, alo, bv, r)
            var s = 0usize
            while s < nanal {
                pl[s] = zp.plo[s]
                s += 1usize
            }
        }
    }
    ret Bnd { lo: pl, hi: bv, fail: bad }
}

// ---- gsDesign(): test types 1 to 4 for the spending families and the Wang-Tsiatis (OF, Pocock, WT) bounds ----

// upk / lok: 0 to 9 are the spending kinds of `spend`; upk 100 O'Brien-Fleming, 101 Pocock, 102 Wang-Tsiatis (up1 is Delta)
type Spec = struct { k: usize, tt: usize, alpha: f64, beta: f64, delta: f64, n_fix: f64, timing: []const f64, n_i: []const f64, maxn: f64, upk: usize, up1: f64, up2: f64, lok: usize, lo1: f64, lo2: f64, tol: f64, r: usize, overrun: f64, astar: f64 }

// the bounds are upper and lower; uprob and lprob are k x 2 (theta 0 then delta), column-major; uspend and lspend are the per-analysis spends
type Design = struct { k: usize, delta: f64, n_fix: f64, timing: []f64, n_i: []f64, upper: []f64, lower: []f64, uspend: []f64, lspend: []f64, uprob: []f64, lprob: []f64, en: []f64, fail: bool }

fn spend_vec(ar: *mem.Arena, kind: usize, alpha: f64, t: []const f64, p1: f64, p2: f64) -> []f64 {
    let o = buf(ar, t.len)
    var q1 = p1
    if kind == 8usize && (p1 < 0.005f64 || p1 > 20.0f64) { q1 = 1.0f64 }
    var i = 0usize
    while i < t.len {
        o[i] = spend(kind, alpha, t[i], q1, p2)
        i += 1usize
    }
    ret o
}

fn incr(ar: *mem.Arena, cum: []const f64) -> []f64 {
    let o = buf(ar, cum.len)
    var i = 0usize
    while i < cum.len {
        o[i] = cum[i]
        if i > 0usize { o[i] = cum[i] - cum[i - 1usize] }
        i += 1usize
    }
    ret o
}

fn scaled(ar: *mem.Arena, t: []const f64, m: f64) -> []f64 {
    let o = buf(ar, t.len)
    var i = 0usize
    while i < t.len {
        o[i] = t[i] * m
        i += 1usize
    }
    ret o
}

// kind 0 gsbetadiff, 1 gsbetadiff1, 2 WTdiff (prob holds b = timing^(Delta - 1/2); a is -c b when scalar_a)
type RootCtx = struct { ar: *mem.Arena, kind: usize, theta: f64, beta: f64, alpha: f64, time: []const f64, lo: []const f64, hi: []const f64, tol: f64, r: usize, prob: []const f64, scalar_a: bool }

fn root_f(c: *RootCtx, x: f64) -> f64 {
    let mk = mem.mark(c.ar)
    var res = 0.0f64
    if c.kind == 0usize {
        let info = scaled(c.ar, c.time, x)
        let p = gsprob1(c.ar, c.theta, info, c.lo, c.hi, c.r)
        res = c.beta - 1.0f64 + fsum(p.phi)
    } else if c.kind == 1usize {
        let info = scaled(c.ar, c.time, x)
        let x1 = gsbound1(c.ar, 0.0f64 - c.theta, info, neg(c.ar, c.hi), c.prob, c.tol, c.r)
        let p = gsprob1(c.ar, c.theta, info, neg(c.ar, x1.hi), c.hi, c.r)
        res = fsum(c.prob) - 1.0f64 + p.powr[0usize]
    } else {
        let hb = scaled(c.ar, c.prob, x)
        var av = c.lo
        if c.scalar_a { av = neg(c.ar, hb) }
        let p = gsprob1(c.ar, 0.0f64, c.time, av, hb, c.r)
        res = c.alpha - fsum(p.phi)
    }
    mem.reset(c.ar, mk)
    ret res
}

fn root_of(c: *RootCtx, lower: f64, upper: f64) -> f64 { ret pw.zeroin[RootCtx](c, root_f, lower, upper, c.tol, 1000i64) }

// WT: the constant of a Wang-Tsiatis bound; a_scalar is the two-sided call (a = 1 in R)
fn wt_const(ar: *mem.Arena, dd: f64, alpha: f64, a_scalar: bool, timing: []const f64, tol: f64, r: usize) -> f64 {
    let bvec = buf(ar, timing.len)
    var q = 0usize
    while q < timing.len {
        bvec[q] = math.pow[f64](timing[q], dd - 0.5f64)
        q += 1usize
    }
    let am = const_vec(ar, timing.len, 0.0f64 - xz())
    var c = RootCtx { ar: ar, kind: 2usize, theta: 0.0f64, beta: 0.0f64, alpha: alpha, time: timing, lo: am, hi: am, tol: tol, r: r, prob: bvec, scalar_a: a_scalar }
    var c0 = 0.0f64
    if !a_scalar {
        var i = 0.0f64
        while root_f(&c, i) >= 0.0f64 { i = i - 1.0f64 }
        c0 = i
    }
    var j = 2.0f64
    while root_f(&c, j) <= 0.0f64 { j = j + 1.0f64 }
    ret pw.zeroin[RootCtx](&c, root_f, c0, j, tol, 1000i64)
}

fn wt_delta(upk: usize, up1: f64) -> f64 {
    if upk == 102usize { ret up1 }
    if upk == 101usize { ret 0.5f64 }
    ret 0.0f64
}

type InfoSet = struct { info: []f64, lo: []f64, hi: []f64 }

// gsI1: the information that gives the lower bound its beta spending, and the bounds there
fn gsi1(ar: *mem.Arena, theta: f64, timing: []const f64, beta: []const f64, bv: []const f64, ilow: f64, ihigh: f64, tol: f64, r: usize) -> InfoSet {
    let k = timing.len
    let tx = scaled(ar, timing, 1.0f64 / timing[k - 1usize])
    var c = RootCtx { ar: ar, kind: 1usize, theta: theta, beta: 0.0f64, alpha: 0.0f64, time: tx, lo: bv, hi: bv, tol: tol, r: r, prob: beta, scalar_a: false }
    let rt = pw.zeroin[RootCtx](&c, root_f, ilow, ihigh, tol, 1000i64)
    let info = scaled(ar, tx, rt)
    let x = gsbound1(ar, 0.0f64 - theta, info, neg(ar, bv), beta, tol, r)
    x.hi[k - 1usize] = 0.0f64 - bv[k - 1usize]
    ret InfoSet { info: info, lo: neg(ar, x.hi), hi: scaled(ar, bv, 1.0f64) }
}

fn fill_probs(ar: *mem.Arena, d: *Design, theta1: f64, lo: []const f64, hi: []const f64, r: usize, overrun: f64, want_lower: bool) {
    let th = buf(ar, 2usize)
    th[1usize] = theta1
    let y = gsprob(ar, th, d.n_i, lo, hi, r, overrun)
    d.uprob = y.phi
    d.lprob = y.plo
    d.en = y.en
    d.upper = scaled(ar, hi, 1.0f64)
    d.lower = scaled(ar, lo, 1.0f64)
}

fn bracket_i(ar: *mem.Arena, theta: f64, timing: []const f64, beta: []const f64, bv: []const f64, i0: f64, ilow0: f64, tol: f64, r: usize, nfix: f64) -> (f64, f64, bool) {
    var c = RootCtx { ar: ar, kind: 1usize, theta: theta, beta: 0.0f64, alpha: 0.0f64, time: timing, lo: bv, hi: bv, tol: tol, r: r, prob: beta, scalar_a: false }
    var ilow = ilow0
    var ihigh = 1.2f64 * i0
    while 0.0f64 > root_f(&c, ihigh) {
        if ihigh > 5.0f64 * nfix { ret (ilow, ihigh, false) }
        ilow = ihigh
        ihigh = ihigh * 1.2f64
    }
    ret (ilow, ihigh, true)
}

fn dtype1(ar: *mem.Arena, s: *const Spec, d: *Design, ucum: []const f64, delta: f64, nfix: f64, sizing: bool) {
    let k = s.k
    let av = const_vec(ar, k, 0.0f64 - xz())
    var bound = buf(ar, k)
    if s.upk >= 100usize {
        let dd = wt_delta(s.upk, s.up1)
        let cp = wt_const(ar, dd, s.alpha, false, d.timing, s.tol, s.r)
        var q = 0usize
        while q < k {
            bound[q] = cp * math.pow[f64](d.timing[q], dd - 0.5f64)
            q += 1usize
        }
        d.uspend = gsprob1(ar, 0.0f64, d.timing, av, bound, s.r).phi
    } else {
        d.uspend = incr(ar, ucum)
        bound = gsbound1(ar, 0.0f64, d.timing, av, d.uspend, s.tol, s.r).hi
    }
    if sizing {
        var c = RootCtx { ar: ar, kind: 0usize, theta: delta, beta: s.beta, alpha: 0.0f64, time: d.timing, lo: av, hi: bound, tol: s.tol, r: s.r, prob: av, scalar_a: false }
        let rt = pw.zeroin[RootCtx](&c, root_f, nfix, 10.0f64 * nfix, s.tol, 1000i64)
        d.n_i = scaled(ar, d.timing, rt)
    }
    fill_probs(ar, d, delta, av, bound, s.r, s.overrun, false)
}

fn dtype2(ar: *mem.Arena, s: *const Spec, d: *Design, ucum: []const f64, lcum: []const f64, astar: f64, delta: f64, nfix: f64, sizing: bool) {
    let k = s.k
    var lo = buf(ar, k)
    var hi = buf(ar, k)
    if s.upk >= 100usize {
        let dd = wt_delta(s.upk, s.up1)
        let cp = wt_const(ar, dd, s.alpha, true, d.timing, s.tol, s.r)
        var q = 0usize
        while q < k {
            hi[q] = cp * math.pow[f64](d.timing[q], dd - 0.5f64)
            lo[q] = 0.0f64 - hi[q]
            q += 1usize
        }
        d.uspend = gsprob1(ar, 0.0f64, d.timing, lo, hi, s.r).phi
        if sizing {
            var c = RootCtx { ar: ar, kind: 0usize, theta: delta, beta: s.beta, alpha: 0.0f64, time: d.timing, lo: lo, hi: hi, tol: s.tol, r: s.r, prob: lo, scalar_a: false }
            let rt = pw.zeroin[RootCtx](&c, root_f, nfix, 10.0f64 * nfix, s.tol, 1000i64)
            d.n_i = scaled(ar, d.timing, rt)
        }
    } else {
        let fp = incr(ar, ucum)
        d.uspend = fp
        var tn = fp
        if s.tt == 5usize { tn = incr(ar, lcum) }
        if sizing {
            let x = gsbound(ar, d.timing, tn, fp, s.tol, s.r)
            let alpha = fsum(fp)
            let zz = qn(alpha, true) + qn(s.beta, true)
            let i0 = (zz / delta) * (zz / delta)
            let tx = scaled(ar, d.timing, 1.0f64 / d.timing[k - 1usize])
            var c = RootCtx { ar: ar, kind: 0usize, theta: delta, beta: s.beta, alpha: 0.0f64, time: tx, lo: x.lo, hi: x.hi, tol: s.tol, r: s.r, prob: lo, scalar_a: false }
            let rt = pw.zeroin[RootCtx](&c, root_f, i0, 10.0f64 * i0, s.tol, 1000i64)
            d.n_i = scaled(ar, tx, rt)
            if !(s.tt == 2usize || astar < 1.0f64 - s.alpha) { x.lo[k - 1usize] = x.hi[k - 1usize] }
            lo = x.lo
            hi = x.hi
        } else {
            let x = gsbound(ar, d.n_i, tn, fp, s.tol, s.r)
            lo = x.lo
            hi = x.hi
        }
        d.lspend = tn
    }
    if s.upk >= 100usize { d.lspend = scaled(ar, d.uspend, 1.0f64) }
    fill_probs(ar, d, delta, lo, hi, s.r, s.overrun, true)
}

// gsDType3b with the analyses cut to k: bounds for given information n_i, iterating the two spends until they agree
fn dtype3b(ar: *mem.Arena, s: *const Spec, k: usize, timing: []const f64, n_i: []const f64, ucum: []const f64, lcum: []const f64, delta: f64) -> Design {
    let falseneg = incr(ar, lcum)
    let falsepos = incr(ar, ucum)
    let trueneg = const_vec(ar, k, (1.0f64 - s.alpha) / f64(k))
    let x1 = gsbound(ar, timing, trueneg, falsepos, s.tol, s.r)
    var upper = buf(ar, k)
    var lower = buf(ar, k)
    if k == 1usize {
        upper = x1.hi
        lower = x1.hi
    } else {
        var x2b = gsbound1(ar, 0.0f64 - delta, n_i, neg(ar, x1.hi), falseneg, s.tol, s.r).hi
        x2b[k - 1usize] = 0.0f64 - x1.hi[k - 1usize]
        let th1 = buf(ar, 1usize)
        th1[0usize] = delta
        var x2a = neg(ar, x2b)
        var x2bb = scaled(ar, x1.hi, 1.0f64)
        var x3p = gsprob1(ar, 0.0f64, n_i, x2a, x2bb, 18usize).powr[0usize]
        var flag = s.tol + 1.0f64
        while flag > s.tol {
            let aold = x2a
            let bold = x2bb
            let alphaold = x3p
            let av = scaled(ar, x2a, 1.0f64)
            av[k - 1usize] = 0.0f64 - xz()
            let x4 = gsbound1(ar, 0.0f64, n_i, av, falsepos, 1.0e-6f64, 18usize)
            let x2 = gsbound1(ar, 0.0f64 - delta, n_i, neg(ar, x4.hi), falseneg, s.tol, s.r)
            x2a = neg(ar, x2.hi)
            x2bb = x4.hi
            x3p = gsprob1(ar, 0.0f64, n_i, x2a, x2bb, 18usize).powr[0usize]
            flag = 0.0f64
            var q = 0usize
            while q < k {
                let da = math.abs[f64](x2a[q] - aold[q])
                let db = math.abs[f64](x2bb[q] - bold[q])
                if da > flag { flag = da }
                if db > flag { flag = db }
                q += 1usize
            }
            let dp = math.abs[f64](alphaold - x3p)
            if dp > flag { flag = dp }
        }
        upper = x2bb
        lower = x2a
    }
    var d = Design { k: k, delta: delta, n_fix: 0.0f64, timing: scaled(ar, timing, 1.0f64), n_i: scaled(ar, n_i, 1.0f64), upper: upper, lower: lower, uspend: falsepos, lspend: falseneg, uprob: buf(ar, 2usize * k), lprob: buf(ar, 2usize * k), en: buf(ar, 2usize), fail: false }
    fill_probs(ar, &d, delta, lower, upper, 18usize, s.overrun, true)
    ret d
}

fn dtype3a(ar: *mem.Arena, s: *const Spec, d: *Design, ucum: []const f64, lcum: []const f64, delta: f64) {
    var x = dtype3b(ar, s, s.k, d.timing, d.n_i, ucum, lcum, delta)
    if s.tt == 3usize {
        var sp = 0.0f64
        var q = 0usize
        while q < x.k {
            sp += x.uprob[q]
            q += 1usize
        }
        if !(sp > s.alpha - s.tol) {
            let pwr = 1.0f64 - s.beta
            var tot = 0.0f64
            var ii = 0usize
            while ii < s.k {
                tot += x.uprob[x.k + ii]
                if tot > pwr - s.tol { break }
                ii += 1usize
            }
            var kk = ii + 1usize
            if kk > s.k { kk = s.k }
            let uc = scaled(ar, ucum, 1.0f64)
            let lc = scaled(ar, lcum, 1.0f64)
            uc[kk - 1usize] = s.alpha
            lc[kk - 1usize] = s.beta
            x = dtype3b(ar, s, kk, d.timing[0usize..kk], d.n_i[0usize..kk], uc[0usize..kk], lc[0usize..kk], delta)
        }
    }
    d.k = x.k
    d.timing = x.timing
    d.n_i = x.n_i
    d.upper = x.upper
    d.lower = x.lower
    d.uspend = x.uspend
    d.lspend = x.lspend
    d.uprob = x.uprob
    d.lprob = x.lprob
    d.en = x.en
}

fn dtype3ss(ar: *mem.Arena, s: *const Spec, d: *Design, ucum: []const f64, lcum: []const f64, delta: f64, nfix: f64) {
    let k = s.k
    let falsepos = incr(ar, ucum)
    let falseneg = incr(ar, lcum)
    let trueneg = const_vec(ar, k, (1.0f64 - s.alpha) / f64(k))
    let x1 = gsbound(ar, d.timing, trueneg, falsepos, s.tol, s.r)
    let (il0, ih0, ok0) = bracket_i(ar, delta, d.timing, falseneg, x1.hi, nfix, nfix / 3.0f64, s.tol, s.r, nfix)
    var ilow = il0
    var ihigh = ih0
    var x2 = gsi1(ar, delta, d.timing, falseneg, x1.hi, ilow, ihigh, s.tol, s.r)
    var gspowr = gsprob1(ar, 0.0f64, x2.info, x2.lo, x2.hi, 18usize).powr[0usize]
    var flag = math.abs[f64](gspowr - s.alpha)
    var jj = 0usize
    var x3 = gsprob1(ar, 0.0f64, x2.info, x2.lo, x2.hi, 18usize)
    while flag > s.tol && jj < 100usize {
        let av = scaled(ar, x2.lo, 1.0f64)
        av[k - 1usize] = 0.0f64 - xz()
        let x4 = gsbound1(ar, 0.0f64, x2.info, av, falsepos, 1.0e-6f64, 18usize)
        let (il2, ih2, ok2) = bracket_i(ar, delta, d.timing, falseneg, x4.hi, nfix, nfix / 3.0f64, s.tol, s.r, nfix)
        ilow = il2
        ihigh = ih2
        x2 = gsi1(ar, delta, d.timing, falseneg, x4.hi, ilow, ihigh, s.tol, s.r)
        x3 = gsprob1(ar, 0.0f64, x2.info, x2.lo, x2.hi, 18usize)
        gspowr = x3.powr[0usize]
        flag = math.abs[f64](gspowr - s.alpha)
        var q = 0usize
        while q < k {
            let dq = math.abs[f64](falsepos[q] - x3.phi[q])
            if dq > flag { flag = dq }
            q += 1usize
        }
        jj += 1usize
    }
    d.n_i = x2.info
    d.uspend = falsepos
    d.lspend = falseneg
    fill_probs(ar, d, delta, x2.lo, x2.hi, 18usize, s.overrun, true)
}

fn dtype4a(ar: *mem.Arena, s: *const Spec, d: *Design, ucum: []const f64, lcum: []const f64, delta: f64) {
    let k = s.k
    let falseneg = incr(ar, lcum)
    let falsepos = incr(ar, ucum)
    let x1 = gsbound1(ar, 0.0f64, d.n_i, const_vec(ar, k, 0.0f64 - xz()), falsepos, s.tol, s.r)
    let x2 = gsbound1(ar, 0.0f64 - delta, d.n_i, neg(ar, x1.hi), falseneg, s.tol, s.r)
    if 0.0f64 - x2.hi[k - 1usize] > x1.hi[k - 1usize] - s.tol { x2.hi[k - 1usize] = 0.0f64 - x1.hi[k - 1usize] }
    d.uspend = falsepos
    d.lspend = falseneg
    fill_probs(ar, d, delta, neg(ar, x2.hi), x1.hi, 18usize, s.overrun, true)
}

fn dtype4ss(ar: *mem.Arena, s: *const Spec, d: *Design, ucum: []const f64, lcum: []const f64, delta: f64, nfix: f64) {
    let k = s.k
    let falsepos = incr(ar, ucum)
    let falseneg = incr(ar, lcum)
    let x0 = gsbound1(ar, 0.0f64, d.timing, const_vec(ar, k, 0.0f64 - xz()), falsepos, s.tol, s.r)
    let (ilow, ihigh, okb) = bracket_i(ar, delta, d.timing, falseneg, x0.hi, nfix, 0.98f64 * nfix, s.tol, s.r, nfix)
    let xx = gsi1(ar, delta, d.timing, falseneg, x0.hi, ilow, ihigh, s.tol, s.r)
    d.n_i = xx.info
    d.uspend = falsepos
    d.lspend = falseneg
    fill_probs(ar, d, delta, xx.lo, x0.hi, s.r, s.overrun, true)
}

// gsDesign(k, test.type, alpha, beta, delta, n.fix, timing, n.I, sfu, sfl, tol, r) with the defaults of R
fn gs_design(ar: *mem.Arena, s: *const Spec) -> Design {
    let k = s.k
    var delta = s.delta
    var nfix = s.n_fix
    let zz = qn(s.alpha, true) + qn(s.beta, true)
    if delta == 0.0f64 {
        delta = math.abs[f64](zz) / math.sqrt[f64](nfix)
    } else {
        nfix = (zz / delta) * (zz / delta)
    }
    let sizing = s.n_i.len == 0usize
    var d = Design { k: k, delta: delta, n_fix: nfix, timing: buf(ar, k), n_i: buf(ar, k), upper: buf(ar, k), lower: buf(ar, k), uspend: buf(ar, k), lspend: buf(ar, k), uprob: buf(ar, 2usize * k), lprob: buf(ar, 2usize * k), en: buf(ar, 2usize), fail: false }
    if sizing {
        var q = 0usize
        while q < k {
            d.timing[q] = s.timing[q]
            q += 1usize
        }
    } else {
        var mx = s.maxn
        if mx <= 0.0f64 {
            var q = 0usize
            while q < k {
                if s.n_i[q] > mx { mx = s.n_i[q] }
                q += 1usize
            }
        }
        var q = 0usize
        while q < k {
            d.n_i[q] = s.n_i[q]
            d.timing[q] = s.n_i[q] / mx
            q += 1usize
        }
    }
    var ucum = buf(ar, k)
    if s.upk < 100usize { ucum = spend_vec(ar, s.upk, s.alpha, d.timing, s.up1, s.up2) }
    var lcum = buf(ar, k)
    var astar = s.astar
    if astar == 0.0f64 { astar = 1.0f64 - s.alpha }
    if s.tt == 5usize {
        lcum = spend_vec(ar, s.lok, astar, d.timing, s.lo1, s.lo2)
    } else if s.tt >= 3usize {
        lcum = spend_vec(ar, s.lok, s.beta, d.timing, s.lo1, s.lo2)
    }
    if s.tt == 1usize {
        dtype1(ar, s, &d, ucum, delta, nfix, sizing)
    } else if s.tt == 2usize || s.tt == 5usize {
        dtype2(ar, s, &d, ucum, lcum, astar, delta, nfix, sizing)
    } else if s.tt == 3usize {
        if sizing { dtype3ss(ar, s, &d, ucum, lcum, delta, nfix) } else { dtype3a(ar, s, &d, ucum, lcum, delta) }
    } else {
        if sizing { dtype4ss(ar, s, &d, ucum, lcum, delta, nfix) } else { dtype4a(ar, s, &d, ucum, lcum, delta) }
    }
    ret d
}

// gsCP: the conditional power of the rest of a design (n.I, lower, upper bounds; lower ignored when one_sided) given z at analysis i (1-based)
fn gscp(ar: *mem.Arena, ninfo: []const f64, lo: []const f64, hi: []const f64, one_sided: bool, i: usize, zi: f64, theta: []const f64, r: usize) -> Prob {
    let k = ninfo.len
    let knew = k - i
    let inew = buf(ar, knew)
    let anew = buf(ar, knew)
    let bnew = buf(ar, knew)
    let ti = ninfo[i - 1usize] / ninfo[k - 1usize]
    var j = 0usize
    while j < knew {
        let tj = ninfo[i + j] / ninfo[k - 1usize]
        inew[j] = ninfo[i + j] - ninfo[i - 1usize]
        bnew[j] = (hi[i + j] * math.sqrt[f64](tj) - zi * math.sqrt[f64](ti)) / math.sqrt[f64](tj - ti)
        if one_sided {
            anew[j] = 0.0f64 - xz()
        } else {
            anew[j] = (lo[i + j] * math.sqrt[f64](tj) - zi * math.sqrt[f64](ti)) / math.sqrt[f64](tj - ti)
        }
        j += 1usize
    }
    ret gsprob(ar, theta, inew, anew, bnew, r, 0.0f64)
}

// ---- survival sample size: eEvents1 and nSurv (LFPWE) for one stratum ----

type Ev = struct { d: f64, n: f64 }

fn has_value(x: []const f64, m: usize, v: f64) -> bool {
    var i = 0usize
    while i < m {
        if x[i] == v { ret true }
        i += 1usize
    }
    ret false
}

// eEvents1(simple = TRUE, Tfinal = NULL): expected events d and enrolled n of one arm
fn eevents1(ar: *mem.Arena, lambda: []const f64, eta0: []const f64, gamma: []const f64, rr: []const f64, ss: []const f64, tt: f64, minfup: f64) -> Ev {
    let nlam = lambda.len
    let nr = rr.len
    let ns = ss.len
    let eta = buf(ar, nlam)
    var i = 0usize
    while i < nlam {
        if eta0.len == 1usize { eta[i] = eta0[0usize] } else { eta[i] = eta0[i] }
        i += 1usize
    }
    let t1 = buf(ar, ns + 1usize)
    var m1 = 0usize
    var cs = 0.0f64
    i = 0usize
    while i < ns {
        cs += ss[i]
        if cs < tt {
            t1[m1] = cs
            m1 += 1usize
        }
        i += 1usize
    }
    t1[m1] = tt
    m1 += 1usize
    let t2r = buf(ar, nr)
    var cr = 0.0f64
    var sr = 0.0f64
    i = 0usize
    while i < nr {
        cr += rr[i]
        t2r[i] = tt - cr
        if t2r[i] < minfup { t2r[i] = minfup }
        sr += rr[i]
        i += 1usize
    }
    var nu = 0usize
    i = 0usize
    while i < nr {
        if !has_value(t2r, i, t2r[i]) { nu += 1usize }
        i += 1usize
    }
    let geff = buf(ar, gamma.len)
    i = 0usize
    while i < gamma.len {
        if i + 1usize <= nu { geff[i] = gamma[i] }
        i += 1usize
    }
    let t2 = buf(ar, nr + 2usize)
    var m2 = 1usize
    t2[0usize] = tt
    i = 0usize
    while i < nr {
        if t2r[i] > 0.0f64 && !has_value(t2, m2, t2r[i]) {
            t2[m2] = t2r[i]
            m2 += 1usize
        }
        i += 1usize
    }
    let t3 = buf(ar, m1 + m2 + 1usize)
    var m3 = 0usize
    i = 0usize
    while i < m1 {
        if !has_value(t3, m3, t1[i]) {
            t3[m3] = t1[i]
            m3 += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < m2 {
        if !has_value(t3, m3, t2[i]) {
            t3[m3] = t2[i]
            m3 += 1usize
        }
        i += 1usize
    }
    i = 1usize
    while i < m3 {
        let v = t3[i]
        var j = i
        while j > 0usize && t3[j - 1usize] > v {
            t3[j] = t3[j - 1usize]
            j -= 1usize
        }
        t3[j] = v
        i += 1usize
    }
    if sr >= tt {
        t2[m2] = 0.0f64
        m2 += 1usize
    }
    let np = m3
    let s = buf(ar, np)
    i = 0usize
    while i < np {
        s[i] = t3[i]
        if i > 0usize { s[i] = t3[i] - t3[i - 1usize] }
        i += 1usize
    }
    let lam = const_vec(ar, np, lambda[nlam - 1usize])
    let et = const_vec(ar, np, eta[nlam - 1usize])
    let gam = buf(ar, np)
    var q1 = m1
    while q1 >= 1usize {
        var j = 0usize
        while j < np {
            if t3[j] <= t1[q1 - 1usize] {
                var li = q1 - 1usize
                if li >= nlam { li = nlam - 1usize }
                lam[j] = lambda[li]
                et[j] = eta[li]
            }
            j += 1usize
        }
        q1 -= 1usize
    }
    var top = gamma.len + 1usize
    if m2 < top { top = m2 }
    var g = top
    while g >= 2usize {
        var j = 0usize
        while j < np {
            if t3[j] > t2[g - 1usize] { gam[j] = geff[g - 2usize] }
            j += 1usize
        }
        g -= 1usize
    }
    var qprev = 1.0f64
    var pcum = 0.0f64
    var dsum = 0.0f64
    var nsum = 0.0f64
    i = 0usize
    while i < np {
        let sm = lam[i] + et[i]
        let q = math.exp[f64](0.0f64 - sm * s[i])
        var p = lam[i] / sm * qprev * (1.0f64 - q)
        if p != p { p = 0.0f64 }
        var bb = gam[i] / sm * lam[i] * (s[i] - (1.0f64 - q) / sm)
        if bb != bb { bb = 0.0f64 }
        dsum += pcum * gam[i] * s[i] + qprev * bb
        pcum += p
        qprev = qprev * q
        nsum += gam[i] * s[i]
        i += 1usize
    }
    ret Ev { d: dsum, n: nsum }
}

// nSurv(T, minfup both given) through LFPWE for one stratum; beta < 0 asks for the power. method 0 LachinFoulkes, 1 Schoenfeld, 2 Freedman, 3 BernsteinLagakos.
// out: 0 sample size N, 1 events d, 2 power, 3 first accrual rate (scaled), 4 eDC, 5 eDE, 6 eDC0, 7 eDE0, 8 eNC, 9 eNE, 10 first R
fn nsurv(ar: *mem.Arena, hr: f64, hr0: f64, ratio: f64, alpha: f64, beta: f64, sided: f64, tt: f64, minfup: f64, method: usize, r0: []const f64, gamma0: []const f64, ss: []const f64, lambda: []const f64, eta_c: []const f64, eta_e: []const f64, out: []f64) {
    let zalpha = 0.0f64 - qn(alpha / sided, true)
    var zbeta = 0.0f64
    if beta >= 0.0f64 { zbeta = 0.0f64 - qn(beta, true) }
    var rr = scaled(ar, r0, 1.0f64)
    var gamma = scaled(ar, gamma0, 1.0f64)
    let span = tt - minfup
    if r0.len == 1usize {
        rr = const_vec(ar, 1usize, span)
    } else if fsum(r0) != span {
        let cr = buf(ar, r0.len)
        var acc = 0.0f64
        var i = 0usize
        while i < r0.len {
            acc += r0[i]
            cr[i] = acc
            i += 1usize
        }
        let last = r0.len - 1usize
        var nc = r0.len
        if cr[last] < span {
            cr[last] = span
        } else {
            i = 0usize
            while i < r0.len {
                if cr[i] > span { cr[i] = span }
                i += 1usize
            }
            let un = buf(ar, r0.len)
            nc = 0usize
            i = 0usize
            while i < r0.len {
                if !has_value(un, nc, cr[i]) {
                    un[nc] = cr[i]
                    nc += 1usize
                }
                i += 1usize
            }
            i = 0usize
            while i < nc {
                cr[i] = un[i]
                i += 1usize
            }
        }
        rr = buf(ar, nc)
        i = 0usize
        while i < nc {
            rr[i] = cr[i]
            if i > 0usize { rr[i] = cr[i] - cr[i - 1usize] }
            i += 1usize
        }
        if nc != r0.len { gamma = scaled(ar, gamma0[0usize..nc], 1.0f64) }
    }
    let qe = ratio / (1.0f64 + ratio)
    let qc = 1.0f64 - qe
    let gamma_c = scaled(ar, gamma, qc)
    let gamma_e = scaled(ar, gamma, qe)
    let ec = eevents1(ar, lambda, eta_c, gamma_c, rr, ss, tt, minfup)
    let ee = eevents1(ar, scaled(ar, lambda, hr), eta_e, gamma_e, rr, ss, tt, minfup)
    var edc0 = eevents1(ar, lambda, eta_c, gamma_c, rr, ss, tt, minfup).d
    var ede0 = eevents1(ar, lambda, eta_e, gamma_e, rr, ss, tt, minfup).d
    let total_d1 = (ec.d + ee.d) / (ec.n + ee.n)
    let mx = ec.n + ee.n
    var n = 1.0f64
    var power_val = 0.0f64
    var have_power = false
    if method == 0usize {
        let lc0 = scaled(ar, lambda, (1.0f64 + hr * ratio) / (1.0f64 + hr0 * ratio))
        edc0 = eevents1(ar, lc0, eta_c, gamma_c, rr, ss, tt, minfup).d
        ede0 = eevents1(ar, scaled(ar, lc0, hr0), eta_e, gamma_e, rr, ss, tt, minfup).d
        let var0 = 1.0f64 / (1.0f64 / (1.0f64 / edc0 + 1.0f64 / ede0))
        let var1 = 1.0f64 / (1.0f64 / (1.0f64 / ec.d + 1.0f64 / ee.d))
        let dl = math.abs[f64](math.log[f64](hr / hr0))
        if beta < 0.0f64 {
            power_val = pn(0.0f64 - (zalpha * math.sqrt[f64](var0) - dl) / math.sqrt[f64](var1), true)
            have_power = true
        } else {
            let z = (zalpha * math.sqrt[f64](var0) + zbeta * math.sqrt[f64](var1)) / dl
            n = z * z
        }
    } else if method == 1usize {
        let vs = 1.0f64 / (qe * (1.0f64 - qe))
        if beta < 0.0f64 {
            let dcur = mx * total_d1
            let zb = math.sqrt[f64](dcur) * math.abs[f64](math.log[f64](hr)) / math.sqrt[f64](vs) - zalpha
            power_val = pn(zb, true)
            have_power = true
        } else {
            let lh = math.log[f64](hr)
            let dreq = (zalpha + zbeta) * (zalpha + zbeta) * vs / (lh * lh)
            n = dreq / total_d1 / mx
        }
    } else if method == 2usize {
        let dl = (hr - 1.0f64) / (hr + 1.0f64 / ratio)
        if beta < 0.0f64 {
            let dcur = mx * total_d1
            let zb = math.sqrt[f64](dcur / ratio) * math.abs[f64](dl) - zalpha
            power_val = pn(zb, true)
            have_power = true
        } else {
            let zz = (zalpha + zbeta) / dl
            let dreq = zz * zz * ratio
            n = dreq / total_d1 / mx
        }
    } else {
        var edeb = 0.0f64
        if hr0 == 1.0f64 {
            edeb = eevents1(ar, lambda, eta_e, gamma_e, rr, ss, tt, minfup).d
        } else {
            edeb = eevents1(ar, scaled(ar, lambda, hr0), eta_e, gamma_e, rr, ss, tt, minfup).d
        }
        let var1 = 1.0f64 / (1.0f64 / (1.0f64 / ec.d + 1.0f64 / ee.d))
        let var0 = 1.0f64 / (1.0f64 / (1.0f64 / edc0 + 1.0f64 / edeb))
        let dl = math.abs[f64](math.log[f64](hr / hr0))
        if beta < 0.0f64 {
            power_val = pn(0.0f64 - (zalpha * math.sqrt[f64](var0) - dl) / math.sqrt[f64](var1), true)
            have_power = true
        } else {
            let z = (zalpha * math.sqrt[f64](var0) + zbeta * math.sqrt[f64](var1)) / dl
            n = z * z
        }
    }
    if !have_power { power_val = 1.0f64 - beta }
    out[0usize] = n * mx
    out[1usize] = n * (ec.d + ee.d)
    out[2usize] = power_val
    out[3usize] = n * gamma[0usize]
    out[4usize] = ec.d * n
    out[5usize] = ee.d * n
    out[6usize] = edc0 * n
    out[7usize] = ede0 * n
    out[8usize] = ec.n * n
    out[9usize] = ee.n * n
    out[10usize] = rr[0usize]
}

// ---- sample size for two means and two proportions ----

type SizeOut = struct { val: f64, n: f64, sigma0: f64, sigma1: f64, p10: f64, p20: f64 }

// nNormal(outtype = 3): val is n when n_in <= 0 (the sample size) and the power otherwise; sigma0 is the standard error of the difference at n = 1
fn nnormal(delta1: f64, sd: f64, sd2: f64, alpha: f64, beta: f64, ratio: f64, sided: f64, delta0: f64, n_in: f64) -> SizeOut {
    let xi = ratio / (1.0f64 + ratio)
    let se = math.sqrt[f64](sd2 * sd2 / xi + sd * sd / (1.0f64 - xi))
    let theta1 = (delta1 - delta0) / se
    if n_in <= 0.0f64 {
        let z = (qn(alpha / sided, true) + qn(beta, true)) / theta1
        let n = z * z
        ret SizeOut { val: n, n: n, sigma0: se / math.sqrt[f64](n), sigma1: 0.0f64, p10: 0.0f64, p20: 0.0f64 }
    }
    let powr = pn(math.sqrt[f64](n_in) * theta1 - qn(1.0f64 - alpha / sided, true), true)
    ret SizeOut { val: powr, n: n_in, sigma0: se / math.sqrt[f64](n_in), sigma1: 0.0f64, p10: 0.0f64, p20: 0.0f64 }
}

// nBinomial(outtype = 3); scale 0 difference, 1 risk ratio, 2 odds ratio (and lnor); n_in <= 0 asks for the sample size
fn nbinomial(p1: f64, p2: f64, alpha: f64, beta: f64, delta0: f64, ratio: f64, sided0: f64, scale: usize, n_in: f64) -> SizeOut {
    var sided = sided0
    if sided != 2.0f64 { sided = 1.0f64 }
    let zbeta = qn(1.0f64 - beta, true)
    let zalpha = qn(1.0f64 - alpha / sided, true)
    let d0 = delta0 == 0.0f64
    var p10 = 0.0f64
    var p20 = 0.0f64
    var sigma0 = 0.0f64
    var sigma1 = 0.0f64
    var eff = 0.0f64
    if scale == 0usize {
        let aa = 1.0f64 + ratio
        let bb = 0.0f64 - (aa + p1 + ratio * p2 + delta0 * (ratio + 2.0f64))
        let cc = delta0 * delta0 + delta0 * (2.0f64 * p1 + aa) + p1 + ratio * p2
        let dd = 0.0f64 - p1 * delta0 * (1.0f64 + delta0)
        let vv = math.pow[f64](bb / (3.0f64 * aa), 3.0f64) - bb * cc / 6.0f64 / (aa * aa) + dd / 2.0f64 / aa
        var sg = 0.0f64
        if vv > 0.0f64 { sg = 1.0f64 } else if vv < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        var iz = 0.0f64
        if vv == 0.0f64 { iz = 1.0f64 }
        let uu = (sg + iz) * math.sqrt[f64]((bb / 3.0f64 / aa) * (bb / 3.0f64 / aa) - cc / 3.0f64 / aa)
        let ww = (pi() + math.acos[f64](vv / math.pow[f64](uu, 3.0f64))) / 3.0f64
        p10 = 2.0f64 * uu * math.cos[f64](ww) - bb / 3.0f64 / aa
        p20 = p10 - delta0
        if d0 {
            p10 = (p1 + ratio * p2) / (1.0f64 + ratio)
            p20 = p10
        }
        sigma0 = math.sqrt[f64]((p10 * (1.0f64 - p10) + p20 * (1.0f64 - p20) / ratio) * (ratio + 1.0f64))
        sigma1 = math.sqrt[f64]((p1 * (1.0f64 - p1) + p2 * (1.0f64 - p2) / ratio) * (ratio + 1.0f64))
        eff = p1 - p2 - delta0
    } else if scale == 1usize {
        let rr = math.exp[f64](delta0)
        let aa = 1.0f64 + ratio
        let bb = 0.0f64 - (rr * (1.0f64 + ratio * p2) + ratio + p1)
        let cc = rr * (p1 + ratio * p2)
        p10 = (0.0f64 - bb - math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)) / 2.0f64 / aa
        p20 = p10 / rr
        if d0 {
            p10 = (p1 + ratio * p2) / (1.0f64 + ratio)
            p20 = p10
        }
        sigma0 = math.sqrt[f64]((ratio + 1.0f64) * (p10 * (1.0f64 - p10) + rr * rr * p20 * (1.0f64 - p20) / ratio))
        sigma1 = math.sqrt[f64]((ratio + 1.0f64) * (p1 * (1.0f64 - p1) + rr * rr * p2 * (1.0f64 - p2) / ratio))
        eff = p1 - p2 * rr
    } else {
        let orr = math.exp[f64](0.0f64 - delta0)
        let aa = orr - 1.0f64
        let bb = 1.0f64 + ratio * orr + (1.0f64 - orr) * (ratio * p2 + p1)
        let cc = 0.0f64 - (ratio * p2 + p1)
        p10 = (0.0f64 - bb + math.sqrt[f64](bb * bb - 4.0f64 * aa * cc)) / 2.0f64 / aa
        p20 = orr * p10 / (1.0f64 + p10 * (orr - 1.0f64))
        if d0 {
            p10 = (p1 + ratio * p2) / (1.0f64 + ratio)
            p20 = p10
        }
        sigma0 = math.sqrt[f64]((ratio + 1.0f64) * (1.0f64 / p10 / (1.0f64 - p10) + 1.0f64 / p20 / (1.0f64 - p20) / ratio))
        sigma1 = math.sqrt[f64]((ratio + 1.0f64) * (1.0f64 / p1 / (1.0f64 - p1) + 1.0f64 / p2 / (1.0f64 - p2) / ratio))
        eff = math.log[f64](orr / p2 * (1.0f64 - p2) * p1 / (1.0f64 - p1))
    }
    if n_in <= 0.0f64 {
        let z = (zalpha * sigma0 + zbeta * sigma1) / eff
        let n = z * z
        ret SizeOut { val: n, n: n, sigma0: sigma0, sigma1: sigma1, p10: p10, p20: p20 }
    }
    let powr = pn(0.0f64 - (qn(1.0f64 - alpha / sided, true) - math.sqrt[f64](n_in) * (eff / sigma0)) * sigma0 / sigma1, true)
    ret SizeOut { val: powr, n: n_in, sigma0: sigma0, sigma1: sigma1, p10: p10, p20: p20 }
}
