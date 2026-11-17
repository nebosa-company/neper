// R BiasedUrn, the multivariate moments and the odds and ball-count estimators, value for value.
//
// meanMFNCHypergeo / varMFNCHypergeo and the Wallenius twins call the package's `moments`, which at a precision
// of 0.1 or more is a closed-form approximation (Fisher: a Newton-like iteration for the common factor r that
// stops at 1e-5; Wallenius: Newton on the exponent t that stops at 1e-5) and below that an enumeration around
// the rounded approximate mean that stops a sweep once a term is under the precision and falling. Both are
// reproduced step for step, so the approximations and the truncated enumerations match R, not just the exact sums.
// oddsM*, numM* and the univariate numF / numW are the package's own closed forms and Newton iterations.

use e.algo.stat.biasedurn as bu
use e.math
use e.math.nmath as nm
use e.mem

fn nan_value() -> f64 { ret 0.0f64 / 0.0f64 }

fn lnfac(x: f64) -> f64 { ret nm.lgammafn(x + 1.0f64) }

// CFishersNCHypergeometric::mean, the root of the Cornfield equation
fn fnc_mean(n: f64, m: f64, nt: f64, odds: f64) -> f64 {
    if odds == 1.0f64 { ret m * n / nt }
    let a = (m + n) * odds + (nt - m - n)
    var b = a * a - 4.0f64 * odds * (odds - 1.0f64) * m * n
    if b > 0.0f64 { b = math.sqrt[f64](b) } else { b = 0.0f64 }
    ret (a - b) / (2.0f64 * (odds - 1.0f64))
}

// the approximate variance every class shares: N r1 r2 / ((N - 1) (m r2 + (N - m) r1)), zero when a factor is not positive
fn approx_var(mu: f64, m: f64, n: f64, nt: f64) -> f64 {
    let r1 = mu * (m - mu)
    let r2 = (n - mu) * (mu + nt - n - m)
    if r1 <= 0.0f64 || r2 <= 0.0f64 { ret 0.0f64 }
    let v = nt * r1 * r2 / ((nt - 1.0f64) * (m * r2 + (nt - m) * r1))
    if v < 0.0f64 { ret 0.0f64 }
    ret v
}

// CMultiFishersNCHypergeometric::mean1 over colours that are all used (count and odds positive)
fn mfnc_mean1(m: []const f64, w: []const f64, n: f64, mu: []f64) {
    let c = m.len
    var nu = 0.0f64
    var ws = 0.0f64
    var i = 0usize
    while i < c {
        nu += m[i]
        ws += m[i] * w[i]
        i += 1usize
    }
    if c == 1usize {
        mu[0] = n
        ret
    }
    if c == 2usize {
        mu[0] = fnc_mean(n, m[0], nu, w[0] / w[1])
        mu[1] = n - mu[0]
        ret
    }
    if n == nu {
        i = 0usize
        while i < c {
            mu[i] = m[i]
            i += 1usize
        }
        ret
    }
    var r = n * nu / ((nu - n) * ws)
    var iter = 0i64
    while true {
        var q = 0.0f64
        i = 0usize
        while i < c {
            q += m[i] * r * w[i] / (r * w[i] + 1.0f64)
            i += 1usize
        }
        let r1 = r
        r = r * n * (nu - q) / (q * (nu - n))
        iter += 1i64
        if math.abs[f64](r - r1) <= 1.0e-5f64 { break }
        if iter > 100i64 { break }
    }
    i = 0usize
    while i < c {
        mu[i] = m[i] * r * w[i] / (r * w[i] + 1.0f64)
        i += 1usize
    }
}

// CMultiWalleniusNCHypergeometric::mean, ntot the count of every colour (zero weights included)
fn mwnc_mean(m: []const f64, w: []const f64, n: f64, ntot: f64, mu: []f64) {
    let c = m.len
    var i = 0usize
    if n == 0.0f64 {
        while i < c {
            mu[i] = 0.0f64
            i += 1usize
        }
        ret
    }
    var wm = 0.0f64
    while i < c {
        wm += w[i] * m[i]
        i += 1usize
    }
    let omr = ntot / wm
    var t = 0.0f64 - 1.0f64
    var iter = 0i64
    while true {
        var h = 0.0f64
        var hd = 0.0f64
        i = 0usize
        while i < c {
            let e = math.exp[f64](t * w[i] * omr)
            h += m[i] * (1.0f64 - e)
            hd -= m[i] * w[i] * omr * e
            i += 1usize
        }
        let t1 = t
        t -= (h - n) / hd
        if t >= 0.0f64 { t = 0.5f64 * t1 }
        iter += 1i64
        if math.abs[f64](h - n) <= 1.0e-5f64 { break }
        if iter > 20i64 { break }
    }
    i = 0usize
    while i < c {
        mu[i] = m[i] * (1.0f64 - math.exp[f64](t * w[i] * omr))
        i += 1usize
    }
}

type MomCtx = struct { kind: usize, c: usize, m: []const f64, w: []const f64, logw: []const f64, n: f64, xm: []f64, rem: []f64, xi: []f64, sx: []f64, sxx: []f64, sn: f64, acc: f64, scale: f64, mfac: f64 }

fn en_lng(g: *MomCtx, x: []const f64) -> f64 {
    var s = g.mfac - g.scale
    var i = 0usize
    while i < g.c {
        s += x[i] * g.logw[i] - lnfac(x[i]) - lnfac(g.m[i] - x[i])
        i += 1usize
    }
    ret s
}

fn en_loop(g: *MomCtx, n: f64, c: usize) -> f64 {
    if c == g.c - 1usize {
        g.xi[c] = n
        var s1 = 0.0f64
        if g.kind == 0usize { s1 = math.exp[f64](en_lng(g, g.xi)) } else { s1 = bu.mwall_term(g.xi, g.m, g.w) }
        var i = 0usize
        while i < g.c {
            g.sx[i] += s1 * g.xi[i]
            g.sxx[i] += s1 * g.xi[i] * g.xi[i]
            i += 1usize
        }
        g.sn += 1.0f64
        ret s1
    }
    var xmin = n - g.rem[c]
    if xmin < 0.0f64 { xmin = 0.0f64 }
    var xmax = g.m[c]
    if xmax > n { xmax = n }
    var x0 = g.xm[c]
    if x0 < xmin { x0 = xmin }
    if x0 > xmax { x0 = xmax }
    var sum = 0.0f64
    var s2 = 0.0f64
    var x = x0
    while x <= xmax {
        g.xi[c] = x
        let s1 = en_loop(g, n - x, c + 1usize)
        sum += s1
        if s1 < g.acc && s1 < s2 { break }
        s2 = s1
        x += 1.0f64
    }
    x = x0 - 1.0f64
    while x >= xmin {
        g.xi[c] = x
        let s1 = en_loop(g, n - x, c + 1usize)
        sum += s1
        if s1 < g.acc && s1 < s2 { break }
        s2 = s1
        x -= 1.0f64
    }
    ret sum
}

// the moments of colour `idx` (what 0 mean, 1 variance) of the multivariate Fisher (kind 0) or Wallenius (kind 1)
// distribution at the package's precision `prec`; every colour of count 0 or odds 0 is out of the urn
fn mv_moment(a: *mem.Arena, kind: usize, prec: f64, m: []const f64, odds: []const f64, n: f64, what: usize, idx: usize) -> f64 {
    let call = m.len
    var cu = 0usize
    var ntot = 0.0f64
    var i = 0usize
    while i < call {
        ntot += m[i]
        if m[i] > 0.0f64 && odds[i] > 0.0f64 { cu += 1usize }
        i += 1usize
    }
    if !(m[idx] > 0.0f64 && odds[idx] > 0.0f64) { ret 0.0f64 }
    let (mu, e1) = mem.alloc[f64](a, cu)
    let (um, e2) = mem.alloc[f64](a, cu)
    let (uw, e3) = mem.alloc[f64](a, cu)
    let (lw, e4) = mem.alloc[f64](a, cu)
    let (xm, e5) = mem.alloc[f64](a, cu)
    let (rem, e6) = mem.alloc[f64](a, cu)
    let (xi, e7) = mem.alloc[f64](a, cu)
    let (sx, e8) = mem.alloc[f64](a, cu)
    let (sxx, e9) = mem.alloc[f64](a, cu)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret nan_value() }
    var k = 0usize
    var at = 0usize
    var nu = 0.0f64
    i = 0usize
    while i < call {
        if m[i] > 0.0f64 && odds[i] > 0.0f64 {
            um[k] = m[i]
            uw[k] = odds[i]
            lw[k] = math.log[f64](odds[i])
            nu += m[i]
            if i == idx { at = k }
            k += 1usize
        }
        i += 1usize
    }
    var nt = nu
    if kind == 1usize { nt = ntot }
    if kind == 0usize { mfnc_mean1(um, uw, n, mu) } else { mwnc_mean(um, uw, n, ntot, mu) }
    if prec >= 0.1f64 {
        if what == 0usize { ret mu[at] }
        ret approx_var(mu[at], um[at], n, nt)
    }
    // the enumeration: rounded approximate means, forced to total n, are where each sweep starts
    var tot = 0.0f64
    i = 0usize
    while i < cu {
        xm[i] = math.floor[f64](mu[i] + 0.4999999f64)
        tot += xm[i]
        i += 1usize
    }
    var guard = 0usize
    while tot < n && guard < 100000usize {
        i = 0usize
        while i < cu && tot < n {
            if xm[i] < um[i] {
                xm[i] += 1.0f64
                tot += 1.0f64
            }
            i += 1usize
        }
        guard += 1usize
    }
    guard = 0usize
    while tot > n && guard < 100000usize {
        i = 0usize
        while i < cu && tot > n {
            if xm[i] > 0.0f64 {
                xm[i] -= 1.0f64
                tot -= 1.0f64
            }
            i += 1usize
        }
        guard += 1usize
    }
    var run = 0.0f64
    i = cu
    while i > 0usize {
        i -= 1usize
        rem[i] = run
        run += um[i]
    }
    var mfac = 0.0f64
    i = 0usize
    while i < cu {
        mfac += lnfac(um[i])
        sx[i] = 0.0f64
        sxx[i] = 0.0f64
        i += 1usize
    }
    var g = MomCtx{ kind: kind, c: cu, m: um, w: uw, logw: lw, n: n, xm: xm, rem: rem, xi: xi, sx: sx, sxx: sxx, sn: 0.0f64, acc: prec, scale: 0.0f64, mfac: mfac }
    if kind == 0usize { g.scale = en_lng(&g, xm) }
    let total = en_loop(&g, n, 0usize)
    let mean = g.sx[at] / total
    if what == 0usize { ret mean }
    ret g.sxx[at] / total - mean * mean
}

// ---- oddsMFNCHypergeo / oddsMWNCHypergeo: the colour farthest from its limits is the reference with odds 1 ----

fn odds_m(kind: usize, mu: []const f64, m: []const f64, n: f64, idx: usize) -> f64 {
    let c = m.len
    var nt = 0.0f64
    var i = 0usize
    while i < c {
        nt += m[i]
        i += 1usize
    }
    var xd0 = 0.0f64
    var c0 = 0usize
    i = 0usize
    while i < c {
        let x1 = math.max[f64](0.0f64, m[i] + n - nt)
        let x2 = math.min[f64](n, m[i])
        var xd1 = mu[i] - x1
        let xd2 = x2 - mu[i]
        if xd2 < xd1 { xd1 = xd2 }
        if xd1 > xd0 {
            xd0 = xd1
            c0 = i
        }
        i += 1usize
    }
    if xd0 == 0.0f64 { ret nan_value() }
    if idx == c0 { ret 1.0f64 }
    let x1 = math.max[f64](0.0f64, m[idx] + n - nt)
    let x2 = math.min[f64](n, m[idx])
    if x1 == x2 { ret nan_value() }
    if mu[idx] <= x1 {
        if mu[idx] == x1 { ret 0.0f64 }
        ret nan_value()
    }
    if mu[idx] >= x2 {
        if mu[idx] == x2 { ret 1.0f64 / 0.0f64 }
        ret nan_value()
    }
    if kind == 0usize { ret mu[idx] * (m[c0] - mu[c0]) / (mu[c0] * (m[idx] - mu[idx])) }
    ret math.log[f64](1.0f64 - mu[idx] / m[idx]) / math.log[f64](1.0f64 - mu[c0] / m[c0])
}

// ---- numFNCHypergeo / numWNCHypergeo: the colour counts that make mu the mean at odds `odds`; returns m1 ----

fn num_fisher(mu: f64, n: f64, nt: f64, odds: f64) -> f64 {
    let mu2 = n - mu
    let muo = mu / odds
    ret (muo * (nt - mu2) + mu * mu2) / (muo + mu2)
}

fn num_wall(mu: f64, n: f64, nt: f64, odds: f64) -> f64 {
    let mu2 = n - mu
    var m1 = nt * mu / n
    var m2 = nt - m1
    var iter = 0i64
    var last = m1
    while true {
        last = m1
        let z = math.log[f64](1.0f64 - mu / m1) - odds * math.log[f64](1.0f64 - mu2 / m2)
        let zd = mu / (m1 * (m1 - mu)) + odds * mu2 / (m2 * (m2 - mu2))
        m1 -= z / zd
        if m1 <= mu { m1 = (last + mu) / 2.0f64 }
        m2 = nt - m1
        if m2 <= mu2 {
            m2 = (nt - last + mu2) / 2.0f64
            m1 = nt - m2
        }
        iter += 1i64
        if math.abs[f64](m1 - last) <= nt * 1.0e-10f64 { break }
        if iter > 200i64 { break }
    }
    ret m1
}

// numMFNCHypergeo / numMWNCHypergeo for colour idx: mu is rescaled to total n, then Newton on r (Fisher) or t (Wallenius)
fn num_m(kind: usize, mu: []const f64, odds: []const f64, n: f64, nt: f64, idx: usize, a: *mem.Arena) -> f64 {
    let c = mu.len
    let (mm, e) = mem.alloc[f64](a, c)
    if e != ok { ret nan_value() }
    var smu = 0.0f64
    var i = 0usize
    while i < c {
        smu += mu[i]
        i += 1usize
    }
    i = 0usize
    while i < c {
        mm[i] = mu[i] * (n / smu)
        i += 1usize
    }
    if n == nt { ret mm[idx] }
    var iter = 0i64
    if kind == 0usize {
        var r = 1.0f64
        var lastr = r
        while true {
            lastr = r
            var z = 0.0f64
            var zd = 0.0f64
            i = 0usize
            while i < c {
                z += mm[i] * (1.0f64 + 1.0f64 / (r * odds[i]))
                zd -= mm[i] / (odds[i] * r * r)
                i += 1usize
            }
            r -= (z - nt) / zd
            if r <= 0.0f64 {
                if r < 0.0f64 - lastr { r = lastr * 0.125f64 } else { r = lastr * 0.5f64 }
            }
            iter += 1i64
            if math.abs[f64](r - lastr) <= r * 1.0e-8f64 { break }
            if iter > 200i64 { break }
        }
        ret mm[idx] * (r * odds[idx] + 1.0f64) / (r * odds[idx])
    }
    var t = 0.0f64 - 1.0f64
    var lastt = t
    while true {
        lastt = t
        var z = 0.0f64
        var zd = 0.0f64
        var again = true
        while again {
            again = false
            z = 0.0f64
            zd = 0.0f64
            i = 0usize
            while i < c {
                let eot = math.exp[f64](odds[i] * t)
                let eot1 = 1.0f64 - eot
                if eot1 <= 0.0f64 || eot <= 0.0f64 {
                    t = 0.125f64 * lastt
                    again = true
                    break
                }
                z += mm[i] / eot1
                zd += mm[i] * odds[i] * eot / (eot1 * eot1)
                i += 1usize
            }
        }
        t -= (z - nt) / zd
        if t >= 0.0f64 {
            if t > 0.0f64 - lastt { t = lastt * 0.125f64 } else { t = lastt * 0.5f64 }
        }
        iter += 1i64
        if math.abs[f64](t - lastt) <= 0.0f64 - t * 1.0e-8f64 { break }
        if iter > 200i64 { break }
    }
    ret mm[idx] / (1.0f64 - math.exp[f64](odds[idx] * t))
}
