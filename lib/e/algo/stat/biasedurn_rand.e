// R BiasedUrn, the random variates: rFNCHypergeo and rWNCHypergeo under set.seed, draw for draw.
//
// The package's samplers are Agner Fog's StochasticLib classes over R's uniform generator. The variate is one of:
// the table method (one uniform per variate, taken when the call asks for enough variates that building the table
// pays: nran above 4 and half the table length below nran), or, per variate, Fisher's chop-down inversion
// (n < 30, N < 1024, odds in 1e-5 .. 1e5) or ratio of uniforms, and Wallenius' urn simulation (n < 30), table
// (n N < 10000), chop-down from the mean (variance < 4) or ratio of uniforms; odds 1 is the hypergeometric
// (inversion from the mode, or ratio of uniforms past N 680 / n 70). Each is reproduced with the same constants and
// the same order of uniforms, so equal seeds give equal integers.
//
// Not here: Wallenius' ratio of uniforms past variance 4 for n N >= 10000 (its acceptance step draws normals through
// a Bernoulli test on the Laplace expansion), reported as NaN.

use e.algo.rand.r as rng
use e.algo.stat.biasedurn as bu
use e.algo.stat.biasedurn_mv as mv
use e.math
use e.mem

fn lnpk(k: f64, l: f64, m: f64, n: f64) -> f64 { ret mv.lnfac(k) + mv.lnfac(m - k) + mv.lnfac(n - k) + mv.lnfac(l + k) }

// ---- Hypergeometric(n, m, N), StochasticLib1 ----

fn hyp_inversion(rg: *rng.Rng, n: f64, m: f64, nn: f64) -> f64 {
    let l = nn - m - n
    let mp = m + 1.0f64
    let np = n + 1.0f64
    let p = mp / (nn + 2.0f64)
    let modef = np * p
    var hmode = math.floor[f64](modef)
    var hmp = hmode + 1.0f64
    if hmode == modef && p == 0.5f64 {
        hmp = hmode
        hmode = hmode - 1.0f64
    }
    let fm = math.exp[f64](mv.lnfac(nn - m) - mv.lnfac(l + hmode) - mv.lnfac(n - hmode) + mv.lnfac(m) - mv.lnfac(m - hmode) - mv.lnfac(hmode) - mv.lnfac(nn) + mv.lnfac(nn - n) + mv.lnfac(n))
    var bound = math.floor[f64](modef + 11.0f64 * math.sqrt[f64](modef * (1.0f64 - p) * (1.0f64 - n / nn) + 1.0f64))
    if bound > n { bound = n }
    while true {
        var u = rng.unif(rg)
        u -= fm
        if u <= 0.0f64 { ret hmode }
        var c = fm
        var d = fm
        var k1 = hmp - 1.0f64
        var k2 = hmode + 1.0f64
        var i = 1.0f64
        while i <= hmode {
            var divisor = (np - k1) * (mp - k1)
            u *= divisor
            d *= divisor
            c *= k1 * (l + k1)
            u -= c
            if u <= 0.0f64 { ret hmp - i - 1.0f64 }
            divisor = k2 * (l + k2)
            u *= divisor
            c *= divisor
            d *= (np - k2) * (mp - k2)
            u -= d
            if u <= 0.0f64 { ret hmode + i }
            k1 -= 1.0f64
            k2 += 1.0f64
            i += 1.0f64
        }
        k2 = hmp + hmode
        i = k2
        while i <= bound {
            let divisor = k2 * (l + k2)
            u *= divisor
            d *= (np - k2) * (mp - k2)
            u -= d
            if u <= 0.0f64 { ret i }
            i += 1.0f64
            k2 += 1.0f64
        }
    }
    ret 0.0f64
}

fn hyp_rou(rg: *rng.Rng, n: f64, m: f64, nn: f64) -> f64 {
    let l = nn - m - n
    let rnn = 1.0f64 / (nn * (nn + 2.0f64))
    let my = n * m * rnn * (nn + 2.0f64)
    let hmode = math.floor[f64]((n + 1.0f64) * (m + 1.0f64) * rnn * nn)
    let v = n * m * (nn - m) * (nn - n) / (nn * nn * (nn - 1.0f64))
    let h = math.sqrt[f64](2.943035529371538573f64 * (v + 0.5f64)) + 0.8989161620588987408f64
    let a = my + 0.5f64
    let g = lnpk(hmode, l, m, n)
    var bound = math.floor[f64](a + 4.0f64 * h)
    if bound > n { bound = n }
    var k = 0.0f64
    while true {
        let u = rng.unif(rg)
        if u == 0.0f64 { continue }
        let x = a + h * (rng.unif(rg) - 0.5f64) / u
        if x < 0.0f64 || x > 2.0e9f64 { continue }
        k = math.floor[f64](x)
        if k > bound { continue }
        let lf = g - lnpk(k, l, m, n)
        if u * (4.0f64 - u) - 3.0f64 <= lf { break }
        if u * (u - lf) > 1.0f64 { continue }
        if 2.0f64 * math.log[f64](u) <= lf { break }
    }
    ret k
}

fn hypergeometric(rg: *rng.Rng, n0: f64, m0: f64, nn: f64) -> f64 {
    var n = n0
    var m = m0
    var fak = 1.0f64
    var addd = 0.0f64
    let half = math.floor[f64](nn / 2.0f64)
    if m > half {
        m = nn - m
        fak = 0.0f64 - 1.0f64
        addd = n
    }
    if n > half {
        n = nn - n
        addd += fak * m
        fak = 0.0f64 - fak
    }
    if n > m {
        let t = n
        n = m
        m = t
    }
    if n == 0.0f64 { ret addd }
    var x = 0.0f64
    if nn > 680.0f64 || n > 70.0f64 { x = hyp_rou(rg, n, m, nn) } else { x = hyp_inversion(rg, n, m, nn) }
    ret x * fak + addd
}

// ---- Fisher's noncentral hypergeometric, StochasticLib3 ----

fn fnc_inversion(rg: *rng.Rng, n: f64, m: f64, nn: f64, odds: f64) -> f64 {
    let l = nn - m - n
    var f0 = 1.0e-100f64
    var sum = f0
    var f = f0
    var scale = 1.0f64
    var a1 = m
    var a2 = n
    var b1 = 1.0f64
    var b2 = l + 1.0f64
    var x = 1.0f64
    while x <= n {
        let f1 = a1 * a2 * odds
        let f2 = b1 * b2
        a1 -= 1.0f64
        a2 -= 1.0f64
        b1 += 1.0f64
        b2 += 1.0f64
        f *= f1
        sum *= f2
        scale *= f2
        sum += f
        x += 1.0f64
    }
    f0 *= scale
    let fscale = sum
    var u = rng.unif(rg) * fscale
    f = f0
    x = 0.0f64
    a1 = m
    a2 = n
    b1 = 0.0f64
    b2 = l
    while true {
        u -= f
        if u <= 0.0f64 { break }
        x += 1.0f64
        b1 += 1.0f64
        b2 += 1.0f64
        f *= a1 * a2 * odds
        u *= b1 * b2
        a1 -= 1.0f64
        a2 -= 1.0f64
        if x >= n { break }
    }
    ret x
}

fn fnc_rou(rg: *rng.Rng, n: f64, m: f64, nn: f64, odds: f64) -> f64 {
    let l = nn - m - n
    let mu = mv.fnc_mean(n, m, nn, odds)
    let v = mv.approx_var(mu, m, n, nn)
    let a = mu + 0.5f64
    let h = 1.028f64 + 1.717f64 * math.sqrt[f64](v + 0.5f64) + 0.032f64 * math.abs[f64](math.log[f64](odds))
    var bound = math.floor[f64](mu + 4.0f64 * h)
    if bound > n { bound = n }
    var hmode = math.floor[f64](mu)
    let g1 = (m - hmode) * (n - hmode) * odds
    let g2 = (hmode + 1.0f64) * (l + hmode + 1.0f64)
    if g1 > g2 && hmode < n { hmode += 1.0f64 }
    let lnodds = math.log[f64](odds)
    let lfm = hmode * lnodds - lnpk(hmode, l, m, n)
    var k = 0.0f64
    while true {
        let u = rng.unif(rg)
        if u == 0.0f64 { continue }
        let x = a + h * (rng.unif(rg) - 0.5f64) / u
        if x < 0.0f64 || x > 2.0e9f64 { continue }
        k = math.floor[f64](x)
        if k > bound { continue }
        let lf = k * lnodds - lnpk(k, l, m, n) - lfm
        if u * (4.0f64 - u) - 3.0f64 <= lf { break }
        if u * (u - lf) > 1.0f64 { continue }
        if 2.0f64 * math.log[f64](u) <= lf { break }
    }
    ret k
}

fn fnc_draw(rg: *rng.Rng, n0: f64, m0: f64, nn: f64, odds0: f64) -> f64 {
    var n = n0
    var m = m0
    var odds = odds0
    if odds == 0.0f64 { ret 0.0f64 }
    if odds == 1.0f64 { ret hypergeometric(rg, n, m, nn) }
    var fak = 1.0f64
    var addd = 0.0f64
    let half = math.floor[f64](nn / 2.0f64)
    if m > half {
        m = nn - m
        fak = 0.0f64 - 1.0f64
        addd = n
    }
    if n > half {
        n = nn - n
        addd += fak * m
        fak = 0.0f64 - fak
    }
    if n > m {
        let t = n
        n = m
        m = t
    }
    if n == 0.0f64 || odds == 0.0f64 { ret addd }
    if fak < 0.0f64 { odds = 1.0f64 / odds }
    var x = 0.0f64
    if n < 30.0f64 && nn < 1024.0f64 && odds > 1.0e-5f64 && odds < 1.0e5f64 { x = fnc_inversion(rg, n, m, nn, odds) } else { x = fnc_rou(rg, n, m, nn, odds) }
    ret x * fak + addd
}

// ---- Wallenius' noncentral hypergeometric, StochasticLib3 ----

// CWalleniusNCHypergeometric::mean
fn wnc_mean(n: f64, m: f64, nn: f64, omega: f64) -> f64 {
    let xmin = math.max[f64](0.0f64, m + n - nn)
    let xmax = math.min[f64](n, m)
    if omega == 1.0f64 { ret m * n / nn }
    if omega == 0.0f64 { ret 0.0f64 }
    if xmin == xmax { ret xmin }
    let a = (m + n) * omega + (nn - m - n)
    var b = a * a - 4.0f64 * omega * (omega - 1.0f64) * m * n
    if b > 0.0f64 { b = math.sqrt[f64](b) } else { b = 0.0f64 }
    var mean = (a - b) / (2.0f64 * (omega - 1.0f64))
    if mean < xmin { mean = xmin }
    if mean > xmax { mean = xmax }
    let m1r = 1.0f64 / m
    let m2r = 1.0f64 / (nn - m)
    var iter = 0i64
    while true {
        let mean1 = mean
        var g = 0.0f64
        var gd = 0.0f64
        if omega > 1.0f64 {
            let e1 = 1.0f64 - (n - mean) * m2r
            var e2 = 0.0f64
            if e1 >= 1.0e-14f64 { e2 = math.pow[f64](e1, omega - 1.0f64) }
            g = e2 * e1 + (mean - m) * m1r
            gd = e2 * omega * m2r + m1r
        } else {
            let omr = 1.0f64 / omega
            let e1 = 1.0f64 - mean * m1r
            var e2 = 0.0f64
            if e1 >= 1.0e-14f64 { e2 = math.pow[f64](e1, omr - 1.0f64) }
            g = 1.0f64 - (n - mean) * m2r - e2 * e1
            gd = e2 * omr * m1r + m2r
        }
        mean -= g / gd
        if mean < xmin { mean = xmin }
        if mean > xmax { mean = xmax }
        iter += 1i64
        if math.abs[f64](mean1 - mean) <= 2.0e-6f64 { break }
        if iter > 40i64 { break }
    }
    ret mean
}

fn wnc_prob(x: f64, n: f64, m: f64, nn: f64, omega: f64) -> f64 { ret bu.wallenius_term(x, m, nn - m, n, omega) }

fn wnc_urn(rg: *rng.Rng, n0: f64, m0: f64, nn: f64, odds: f64) -> f64 {
    var n = n0
    var m = m0
    var x = 0.0f64
    var m2 = nn - m
    var mw1 = m * odds
    var mw2 = m2
    while true {
        let u = rng.unif(rg)
        if u * (mw1 + mw2) < mw1 {
            x += 1.0f64
            m -= 1.0f64
            if m == 0.0f64 { break }
            mw1 = m * odds
        } else {
            m2 -= 1.0f64
            if m2 == 0.0f64 {
                x += n - 1.0f64
                break
            }
            mw2 = m2
        }
        n -= 1.0f64
        if n <= 0.0f64 { break }
    }
    ret x
}

fn wnc_inversion(rg: *rng.Rng, n: f64, m: f64, nn: f64, odds: f64, acc: f64) -> f64 {
    var accura = acc * 0.01f64
    if accura > 1.0e-7f64 { accura = 1.0e-7f64 }
    let x1s = math.floor[f64](wnc_mean(n, m, nn, odds))
    let xmin = math.max[f64](0.0f64, m + n - nn)
    let xmax = math.min[f64](n, m)
    while true {
        var x1 = x1s
        var x2 = x1s + 1.0f64
        var down = true
        var up = true
        var u = rng.unif(rg)
        while down || up {
            if down {
                if x1 < xmin {
                    down = false
                } else {
                    let f = wnc_prob(x1, n, m, nn, odds)
                    u -= f
                    if u <= 0.0f64 { ret x1 }
                    x1 -= 1.0f64
                    if f < accura { down = false }
                }
            }
            if up {
                if x2 > xmax {
                    up = false
                } else {
                    let f = wnc_prob(x2, n, m, nn, odds)
                    u -= f
                    if u <= 0.0f64 { ret x2 }
                    x2 += 1.0f64
                    if f < accura { up = false }
                }
            }
        }
    }
    ret 0.0f64
}

// the 512-entry table of one call: probabilities from the support with the tails under the cutoff dropped
fn wnc_table(rg: *rng.Rng, a: *mem.Arena, n: f64, m: f64, nn: f64, odds: f64, acc: f64) -> f64 {
    let lo = math.max[f64](0.0f64, m + n - nn)
    let hi = math.min[f64](n, m)
    let (tab, e) = mem.alloc[f64](a, usize(hi - lo) + 2usize)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var cutoff = 0.01f64 * acc
    if cutoff <= 0.0f64 || cutoff > 0.1f64 { cutoff = 0.01f64 * acc }
    var x1 = lo
    var x2 = hi
    var k = 0usize
    while lo + f64(k) <= hi {
        tab[k] = wnc_prob(lo + f64(k), n, m, nn, odds)
        k += 1usize
    }
    while x1 < hi && tab[usize(x1 - lo)] < cutoff { x1 += 1.0f64 }
    while x2 > lo && tab[usize(x2 - lo)] < cutoff { x2 -= 1.0f64 }
    if x2 - x1 + 1.0f64 > 512.0f64 { ret 0.0f64 / 0.0f64 }
    while true {
        var u = rng.unif(rg)
        var x = x1
        while x <= x2 {
            u -= tab[usize(x - lo)]
            if u < 0.0f64 { ret x }
            x += 1.0f64
        }
    }
    ret 0.0f64
}

fn wnc_draw(rg: *rng.Rng, a: *mem.Arena, n: f64, m: f64, nn: f64, odds: f64, acc: f64) -> f64 {
    if n >= nn || m >= nn || n <= 0.0f64 || m <= 0.0f64 || odds <= 0.0f64 {
        if n == 0.0f64 || m == 0.0f64 { ret 0.0f64 }
        if m == nn { ret n }
        if n == nn { ret m }
        ret 0.0f64
    }
    if odds == 1.0f64 { ret hypergeometric(rg, n, m, nn) }
    if n < 30.0f64 { ret wnc_urn(rg, n, m, nn, odds) }
    if n * nn < 10000.0f64 { ret wnc_table(rg, a, n, m, nn, odds, acc) }
    let mean = wnc_mean(n, m, nn, odds)
    let v = mv.approx_var(mean, m, n, nn)
    if v < 4.0f64 { ret wnc_inversion(rg, n, m, nn, odds, acc) }
    ret 0.0f64 / 0.0f64
}

// ---- the R entry points: nran variates, a table when nran is large enough ----

fn num_sd(acc: f64) -> f64 {
    let fract = [10]f64{ 2.699796e-03f64, 4.652582e-04f64, 6.334248e-05f64, 6.795346e-06f64, 5.733031e-07f64, 3.797912e-08f64, 1.973175e-09f64, 8.032001e-11f64, 2.559625e-12f64, 6.381783e-14f64 }
    var i = 0usize
    while i < 10usize {
        if acc >= fract[i] { ret f64(i) + 6.0f64 }
        i += 1usize
    }
    ret 16.0f64
}

fn sane_prec(prec: f64) -> f64 {
    if !(prec == prec) || prec < 0.0f64 || prec > 1.0f64 { ret 1.0e-7f64 }
    ret prec
}

// the length MakeTable(buffer, 0, ...) reports for Fisher's distribution
fn fnc_buflen(m1: f64, m2: f64, n: f64, odds: f64, prec: f64) -> f64 {
    let nn = m1 + m2
    let x1 = math.max[f64](0.0f64, n + m1 - nn)
    let x2 = math.min[f64](n, m1)
    if x1 == x2 || odds <= 0.0f64 { ret 1.0f64 }
    let len = x2 - x1 + 1.0f64
    if len > 200.0f64 {
        let mu = mv.fnc_mean(n, m1, nn, odds)
        let i = math.floor[f64](num_sd(prec) * math.sqrt[f64](mv.approx_var(mu, m1, n, nn)) + 0.5f64)
        if i < len { ret i }
    }
    ret len
}

fn wnc_buflen(m1: f64, m2: f64, n: f64, odds: f64, prec: f64) -> f64 {
    let nn = m1 + m2
    if n == 0.0f64 || m1 == 0.0f64 || n == nn || m1 == nn || odds <= 0.0f64 { ret 1.0f64 }
    let need = math.min[f64](math.min[f64](nn - m1, m1), n)
    let area = n * need
    var use_table = area < 5000.0f64
    if area < 10000.0f64 && nn > 1000.0f64 * n { use_table = true }
    var i1 = need + 2.0f64
    if !use_table && i1 > 200.0f64 {
        let mu = wnc_mean(n, m1, nn, odds)
        let i2 = math.floor[f64](num_sd(prec) * math.sqrt[f64](mv.approx_var(mu, m1, n, nn)) + 0.5f64)
        if i1 > i2 { i1 = i2 }
    }
    ret i1
}

// the table of Fisher's distribution the way CFishersNCHypergeometric::MakeTable lays it out in `len` entries; returns x of the first entry in xfirst and the entry count
type Tab = struct { first: f64, count: usize }

fn fnc_make_table(tab: []f64, len: usize, m: f64, nn: f64, n: f64, odds: f64, cutoff: f64) -> Tab {
    let l = n + m - nn
    let x1 = math.max[f64](l, 0.0f64)
    let x2 = math.min[f64](n, m)
    if x1 == x2 || odds <= 0.0f64 {
        tab[0usize] = 1.0f64
        ret Tab{ first: x1, count: 1usize }
    }
    let md = bu.mode_fisher(m, nn - m, n, odds)
    let half = len / 2usize
    var i0 = 0usize
    let a0 = usize(md - x1)
    if a0 <= half {
        i0 = a0
    } else if usize(x2 - md) <= half {
        let t = i64(len) - i64(x2 - md) - 1i64
        if t > 0i64 { i0 = usize(t) }
    } else {
        i0 = half
    }
    var i1 = 0usize
    let d1 = i64(i0) - i64(md - x1)
    if d1 > 0i64 { i1 = usize(d1) }
    var i2 = len - 1usize
    let e2 = usize(i64(i0) + i64(x2 - md))
    if e2 < i2 { i2 = e2 }
    tab[i0] = 1.0f64
    var f = 1.0f64
    var x = md
    var i = i0
    while i > i1 {
        i -= 1usize
        f *= x * (x - l) / ((m - x + 1.0f64) * (n - x + 1.0f64) * odds)
        x -= 1.0f64
        tab[i] = f
        if f < cutoff {
            i1 = i
            break
        }
    }
    var j = 0usize
    if i1 > 0usize {
        while i1 + j <= i2 && j <= i0 - i1 {
            tab[j] = tab[i1 + j]
            j += 1usize
        }
        i0 -= i1
        i2 -= i1
        i1 = 0usize
    }
    f = 1.0f64
    x = md
    i = i0
    while i < i2 {
        i += 1usize
        f *= (m - x) * (n - x) * odds / ((x + 1.0f64) * (x + 1.0f64 - l))
        x += 1.0f64
        tab[i] = f
        if f < cutoff {
            i2 = i
            break
        }
    }
    ret Tab{ first: md - f64(i0), count: i2 + 1usize }
}

// rFNCHypergeo(nran, m1, m2, n, odds, precision) into out[0..nran]
fn r_fisher(rg: *rng.Rng, a: *mem.Arena, nran: usize, m1: f64, m2: f64, n: f64, odds: f64, prec0: f64, out: []f64) {
    let prec = sane_prec(prec0)
    let nn = m1 + m2
    var k = 0usize
    if nran > 4usize {
        let blen = fnc_buflen(m1, m2, n, odds, prec)
        let bl = usize(blen)
        if bl / 2usize < nran {
            var len = bl
            if len == 0usize { len = 1usize }
            let (tab, e) = mem.alloc[f64](a, len + 1usize)
            if e != ok { ret }
            let t = fnc_make_table(tab, len, m1, nn, n, odds, prec * 0.001f64)
            var s = 0.0f64
            var q = 0usize
            while q < t.count {
                s += tab[q]
                tab[q] = s
                q += 1usize
            }
            let last = t.first + f64(t.count - 1usize)
            while k < nran {
                let u = rng.unif(rg) * s
                q = 0usize
                while q + 1usize < t.count && !(u < tab[q]) { q += 1usize }
                var x = t.first + f64(q)
                if x > last { x = last }
                out[k] = x
                k += 1usize
            }
            ret
        }
    }
    while k < nran {
        out[k] = fnc_draw(rg, n, m1, nn, odds)
        k += 1usize
    }
}

// rWNCHypergeo(nran, m1, m2, n, odds, precision) into out[0..nran]
fn r_wall(rg: *rng.Rng, a: *mem.Arena, nran: usize, m1: f64, m2: f64, n: f64, odds: f64, prec0: f64, out: []f64) {
    let prec = sane_prec(prec0)
    let nn = m1 + m2
    var k = 0usize
    if nran > 4usize {
        let blen = wnc_buflen(m1, m2, n, odds, prec)
        let bl = usize(blen)
        if bl / 2usize < nran {
            let lo = math.max[f64](0.0f64, n + m1 - nn)
            let hi = math.min[f64](n, m1)
            var size = bl
            if size == 0usize { size = 1usize }
            let (buf, e) = mem.alloc[f64](a, size + 1usize)
            if e != ok { ret }
            var cnt = 1usize
            var firstx = lo
            if lo == hi || odds <= 0.0f64 {
                buf[0usize] = 1.0f64
            } else {
                // MakeTable, one value at a time from floor(mean): the left tail keeps its first value under the cutoff, a full table loses its right end
                let cutoff = prec * 0.001f64
                let mean = math.floor[f64](wnc_mean(n, m1, nn, odds))
                var xl = mean + 1.0f64
                var il = size
                while xl > lo {
                    xl -= 1.0f64
                    il -= 1usize
                    let y = wnc_prob(xl, n, m1, nn, odds)
                    buf[il] = y
                    if y < cutoff || il == 0usize { break }
                }
                let nl = size - il
                var z = 0usize
                while z < nl {
                    buf[z] = buf[il + z]
                    z += 1usize
                }
                var i2 = nl - 1usize
                var xr = mean
                while xr < hi {
                    if i2 == size - 1usize { break }
                    xr += 1.0f64
                    i2 += 1usize
                    let y = wnc_prob(xr, n, m1, nn, odds)
                    buf[i2] = y
                    if y < cutoff { break }
                }
                firstx = xl
                cnt = i2 + 1usize
            }
            var s = 0.0f64
            var q = 0usize
            while q < cnt {
                s += buf[q]
                buf[q] = s
                q += 1usize
            }
            let lastx = firstx + f64(cnt - 1usize)
            while k < nran {
                let u = rng.unif(rg) * s
                q = 0usize
                while q + 1usize < cnt && !(u < buf[q]) { q += 1usize }
                var x = firstx + f64(q)
                if x > lastx { x = lastx }
                out[k] = x
                k += 1usize
            }
            ret
        }
    }
    while k < nran {
        out[k] = wnc_draw(rg, a, n, m1, nn, odds, prec)
        k += 1usize
    }
}
