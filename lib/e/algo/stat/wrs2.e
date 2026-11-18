// R WRS2, the deterministic part: Winsorized and trimmed location and scale (`winval`, `winmean`, `winvar`, `winse`, `trimse`, `tmean`,
// `pbos`), Yuen's trimmed-mean tests for two independent and two dependent groups (`yuen`, `yuend`, with their explanatory-power effect
// size when the groups have equal trimmed sizes), the heteroscedastic one-way test `t1way`, the Winsorized and percentage bend
// correlations (`wincor`, `pbcor`), the AKP effect size (`akp_d`), pairwise `lincon` comparisons with Hochberg's adjustment, the median
// one-way statistic `med1way` and `msmedse`. Samples are given as slices; a k-group design is one slice with the group sizes.
//
// Not here: everything that bootstraps or simulates (yuenbt, pb2gen, the unequal-n effect sizes, med1way's critical value), the
// studentised-maximum critical values of lincon, t2way and the rest of the package.

use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

error Malformed

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

// sorted copy
fn sorted(a: *mem.Arena, x: []const f64) -> []f64 {
    let (y, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret y }
    var i = 0usize
    while i < x.len {
        y[i] = x[i]
        i += 1usize
    }
    i = 1usize
    while i < x.len {
        let v = y[i]
        var j = i
        while j > 0usize && y[j - 1usize] > v {
            y[j] = y[j - 1usize]
            j -= 1usize
        }
        y[j] = v
        i += 1usize
    }
    ret y
}

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    ret s / f64(x.len)
}

fn var_of(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret s / f64(x.len - 1usize)
}

// mean(x, trim = tr): R drops floor(n tr) observations from each end
fn tmean(a: *mem.Arena, x: []const f64, tr: f64) -> f64 {
    let n = x.len
    let y = sorted(a, x)
    let lo = usize(math.floor[f64](f64(n) * tr))
    var s = 0.0f64
    var i = lo
    while i < n - lo {
        s += y[i]
        i += 1usize
    }
    ret s / f64(n - 2usize * lo)
}

// winval(x, tr): the values below the (floor(tr n) + 1)-th smallest raised to it and those above the matching largest lowered to it
fn winval(a: *mem.Arena, x: []const f64, tr: f64, out: []f64) {
    let n = x.len
    let y = sorted(a, x)
    let ibot = usize(math.floor[f64](tr * f64(n)))
    let xbot = y[ibot]
    let xtop = y[n - ibot - 1usize]
    var i = 0usize
    while i < n {
        var v = x[i]
        if v <= xbot { v = xbot }
        if v >= xtop { v = xtop }
        out[i] = v
        i += 1usize
    }
}

fn winmean(a: *mem.Arena, x: []const f64, tr: f64) -> f64 {
    let (w, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret nan() }
    winval(a, x, tr, w)
    ret mean_of(w)
}

fn winvar(a: *mem.Arena, x: []const f64, tr: f64) -> f64 {
    let (w, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret nan() }
    winval(a, x, tr, w)
    ret var_of(w)
}

fn winse(a: *mem.Arena, x: []const f64, tr: f64) -> f64 {
    let n = f64(x.len)
    let h = n - 2.0f64 * math.floor[f64](tr * n)
    ret ((n - 1.0f64) * math.sqrt[f64](winvar(a, x, tr))) / ((h - 1.0f64) * math.sqrt[f64](n))
}

fn trimse(a: *mem.Arena, x: []const f64, tr: f64) -> f64 {
    ret math.sqrt[f64](winvar(a, x, tr)) / ((1.0f64 - 2.0f64 * tr) * math.sqrt[f64](f64(x.len)))
}

// the median of a slice
fn median_of(a: *mem.Arena, x: []const f64) -> f64 {
    let y = sorted(a, x)
    let n = y.len
    if n % 2usize == 1usize { ret y[n / 2usize] }
    ret (y[n / 2usize - 1usize] + y[n / 2usize]) / 2.0f64
}

// the percentage bend midrange pbos(x, beta)
fn pbos(a: *mem.Arena, x: []const f64, beta: f64) -> f64 {
    let n = x.len
    let med = median_of(a, x)
    let (ad, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan() }
    var i = 0usize
    while i < n {
        ad[i] = math.abs[f64](x[i] - med)
        i += 1usize
    }
    let t = sorted(a, ad)
    let omhat = t[usize(math.floor[f64]((1.0f64 - beta) * f64(n))) - 1usize]
    var i1 = 0.0f64
    var i2 = 0.0f64
    var s = 0.0f64
    i = 0usize
    while i < n {
        let psi = (x[i] - med) / omhat
        if psi < 0.0f64 - 1.0f64 {
            i1 += 1.0f64
        } else if psi > 1.0f64 {
            i2 += 1.0f64
        } else {
            s += x[i]
        }
        i += 1usize
    }
    ret (s + omhat * (i2 - i1)) / (f64(n) - i1 - i2)
}

// the function x^2 dnorm(x) and the adaptive Simpson area() of WRS2 (limit 10, eps 1e-5)
fn dnormvar(x: f64) -> f64 { ret x * x * dist.dnorm(x, 0.0f64, 1.0f64, false) }

fn area_rec(a: f64, b: f64, fa: f64, fb: f64, limit: i64) -> f64 {
    let h = b - a
    let d = (a + b) / 2.0f64
    let fd = dnormvar(d)
    let a1 = ((fa + fb) * h) / 2.0f64
    let a2 = ((fa + 4.0f64 * fd + fb) * h) / 6.0f64
    if math.abs[f64](a1 - a2) < 1.0e-5f64 { ret a2 }
    if limit == 0i64 { ret a2 }
    ret area_rec(a, d, fa, fd, limit - 1i64) + area_rec(d, b, fd, fb, limit - 1i64)
}

// area(dnormvar, qnorm(tr), qnorm(1 - tr)) + 2 qnorm(tr)^2 tr, the Winsorized-variance correction
fn cterm(tr: f64) -> f64 {
    if tr == 0.0f64 { ret 1.0f64 }
    let lo = dist.qnorm(tr, 0.0f64, 1.0f64, true, false)
    let hi = dist.qnorm(1.0f64 - tr, 0.0f64, 1.0f64, true, false)
    ret area_rec(lo, hi, dnormvar(lo), dnormvar(hi), 10i64) + 2.0f64 * lo * lo * tr
}

type Yuen = struct { test: f64, lo: f64, hi: f64, p: f64, df: f64, diff: f64, se: f64, effsize: f64 }

// the Winsorized correlation, covariance, test statistic and p value
type Wc = struct { cor: f64, cov: f64, test: f64, p: f64 }

fn wincor(a: *mem.Arena, x: []const f64, y: []const f64, tr: f64) -> Wc {
    let n = x.len
    let (xv, e1) = mem.alloc[f64](a, n)
    let (yv, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret Wc { cor: nan(), cov: nan(), test: nan(), p: nan() } }
    winval(a, x, tr, xv)
    winval(a, y, tr, yv)
    let mx = mean_of(xv)
    let my = mean_of(yv)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    var i = 0usize
    while i < n {
        sxy += (xv[i] - mx) * (yv[i] - my)
        sxx += (xv[i] - mx) * (xv[i] - mx)
        syy += (yv[i] - my) * (yv[i] - my)
        i += 1usize
    }
    let wcor = sxy / math.sqrt[f64](sxx * syy)
    let wcov = sxy / f64(n - 1usize)
    let g = math.floor[f64](tr * f64(n))
    let test = wcor * math.sqrt[f64]((f64(n) - 2.0f64) / (1.0f64 - wcor * wcor))
    let p = 2.0f64 * (1.0f64 - nb.pt(math.abs[f64](test), f64(n) - 2.0f64 * g - 2.0f64, true, false))
    ret Wc { cor: wcor, cov: wcov, test: test, p: p }
}

// yuenv2's explanatory-power effect size for equal trimmed sizes: sqrt of the variance explained, or the squared Winsorized correlation
// with the group indicator when that exceeds one
fn yuen_effect(a: *mem.Arena, x: []const f64, y: []const f64, tr: f64) -> f64 {
    let n1 = x.len
    let n2 = y.len
    let h1 = f64(n1) - 2.0f64 * math.floor[f64](tr * f64(n1))
    let h2 = f64(n2) - 2.0f64 * math.floor[f64](tr * f64(n2))
    if h1 != h2 { ret nan() }
    let m1 = tmean(a, x, tr)
    let m2 = tmean(a, y, tr)
    let (pts, e) = mem.alloc[f64](a, n1 + n2)
    let (grp, e2) = mem.alloc[f64](a, n1 + n2)
    if e != ok || e2 != ok { ret nan() }
    var i = 0usize
    while i < n1 {
        pts[i] = x[i]
        grp[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n2 {
        pts[n1 + i] = y[i]
        grp[n1 + i] = 2.0f64
        i += 1usize
    }
    let mb = (m1 + m2) / 2.0f64
    let top = ((m1 - mb) * (m1 - mb) + (m2 - mb) * (m2 - mb)) / 1.0f64
    let bot = winvar(a, pts, tr) / cterm(tr)
    var epow = top / bot
    if epow > 1.0f64 {
        let wc = wincor(a, grp, pts, tr)
        epow = wc.cor * wc.cor
    }
    ret math.sqrt[f64](epow)
}

// yuen(x, y, tr): the two-sided test at alpha 0.05 with Welch-type degrees of freedom
fn yuen(a: *mem.Arena, x: []const f64, y: []const f64, tr: f64) -> Yuen {
    let n1 = f64(x.len)
    let n2 = f64(y.len)
    let h1 = n1 - 2.0f64 * math.floor[f64](tr * n1)
    let h2 = n2 - 2.0f64 * math.floor[f64](tr * n2)
    let q1 = (n1 - 1.0f64) * winvar(a, x, tr) / (h1 * (h1 - 1.0f64))
    let q2 = (n2 - 1.0f64) * winvar(a, y, tr) / (h2 * (h2 - 1.0f64))
    let df = (q1 + q2) * (q1 + q2) / ((q1 * q1 / (h1 - 1.0f64)) + (q2 * q2 / (h2 - 1.0f64)))
    let crit = nb.qt(1.0f64 - 0.025f64, df, true, false)
    let dif = tmean(a, x, tr) - tmean(a, y, tr)
    let se = math.sqrt[f64](q1 + q2)
    let test = math.abs[f64](dif / se)
    ret Yuen { test: test, lo: dif - crit * se, hi: dif + crit * se, p: 2.0f64 * (1.0f64 - nb.pt(test, df, true, false)), df: df, diff: dif, se: se, effsize: yuen_effect(a, x, y, tr) }
}

// yuend(x, y, tr) for paired data
fn yuend(a: *mem.Arena, x: []const f64, y: []const f64, tr: f64) -> Yuen {
    let n = f64(x.len)
    let h1 = n - 2.0f64 * math.floor[f64](tr * n)
    let q1 = (n - 1.0f64) * winvar(a, x, tr)
    let q2 = (n - 1.0f64) * winvar(a, y, tr)
    let wc = wincor(a, x, y, tr)
    let q3 = (n - 1.0f64) * wc.cov
    let df = h1 - 1.0f64
    let se = math.sqrt[f64]((q1 + q2 - 2.0f64 * q3) / (h1 * (h1 - 1.0f64)))
    let crit = nb.qt(1.0f64 - 0.025f64, df, true, false)
    let dif = tmean(a, x, tr) - tmean(a, y, tr)
    let test = dif / se
    ret Yuen { test: test, lo: dif - crit * se, hi: dif + crit * se, p: 2.0f64 * (1.0f64 - nb.pt(math.abs[f64](test), df, true, false)), df: df, diff: dif, se: se, effsize: yuen_effect(a, x, y, tr) }
}

type T1way = struct { test: f64, df1: f64, df2: f64, p: f64, effsize: f64 }

// t1way(x ~ g, tr): data is the concatenated groups, sizes their lengths. effsize is the equal-n form sqrt(var(means) / winvarN(all)),
// NaN for unequal sizes (R bootstraps it there)
fn t1way(a: *mem.Arena, data: []const f64, sizes: []const usize, tr: f64) -> T1way {
    let jn = sizes.len
    let (h, e1) = mem.alloc[f64](a, jn)
    let (w, e2) = mem.alloc[f64](a, jn)
    let (xbar, e3) = mem.alloc[f64](a, jn)
    if e1 != ok || e2 != ok || e3 != ok { ret T1way { test: nan(), df1: nan(), df2: nan(), p: nan(), effsize: nan() } }
    var off = 0usize
    var j = 0usize
    var equal = true
    while j < jn {
        let g = data[off..off + sizes[j]]
        let n = f64(sizes[j])
        h[j] = n - 2.0f64 * math.floor[f64](tr * n)
        w[j] = h[j] * (h[j] - 1.0f64) / ((n - 1.0f64) * winvar(a, g, tr))
        xbar[j] = tmean(a, g, tr)
        if sizes[j] != sizes[0usize] { equal = false }
        off += sizes[j]
        j += 1usize
    }
    var u = 0.0f64
    j = 0usize
    while j < jn {
        u += w[j]
        j += 1usize
    }
    var xtil = 0.0f64
    j = 0usize
    while j < jn {
        xtil += w[j] * xbar[j]
        j += 1usize
    }
    xtil = xtil / u
    let jf = f64(jn)
    var aa = 0.0f64
    var s2 = 0.0f64
    j = 0usize
    while j < jn {
        aa += w[j] * (xbar[j] - xtil) * (xbar[j] - xtil)
        s2 += (1.0f64 - w[j] / u) * (1.0f64 - w[j] / u) / (h[j] - 1.0f64)
        j += 1usize
    }
    aa = aa / (jf - 1.0f64)
    let bb = 2.0f64 * (jf - 2.0f64) * s2 / (jf * jf - 1.0f64)
    let test = aa / (bb + 1.0f64)
    let nu1 = jf - 1.0f64
    let nu2 = 1.0f64 / (3.0f64 * s2 / (jf * jf - 1.0f64))
    var eff = nan()
    if equal {
        let top = var_of(xbar)
        let bot = winvar(a, data, tr) / cterm_n(tr)
        eff = math.sqrt[f64](top / bot)
    }
    ret T1way { test: test, df1: nu1, df2: nu2, p: 1.0f64 - nb.pf(test, nu1, nu2, true, false), effsize: eff }
}

// the constant winvarN uses: tabulated for tr 0, 0.1 and 0.2, computed otherwise
fn cterm_n(tr: f64) -> f64 {
    if tr == 0.0f64 { ret 1.0f64 }
    if tr == 0.1f64 { ret 0.6786546f64 }
    if tr == 0.2f64 { ret 0.4120867f64 }
    ret cterm(tr)
}

// pbcor(x, y, beta): the percentage bend correlation with its t statistic and p value
fn pbcor(a: *mem.Arena, x: []const f64, y: []const f64, beta: f64) -> Wc {
    let n = x.len
    let (ad, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret Wc { cor: nan(), cov: nan(), test: nan(), p: nan() } }
    var sides = 0usize
    var sxx = 0.0f64
    var syy = 0.0f64
    var sab = 0.0f64
    let mx = median_of(a, x)
    let my = median_of(a, y)
    var i = 0usize
    while i < n {
        ad[i] = math.abs[f64](x[i] - mx)
        i += 1usize
    }
    let tx = sorted(a, ad)
    let ox = tx[usize(math.floor[f64]((1.0f64 - beta) * f64(n))) - 1usize]
    i = 0usize
    while i < n {
        ad[i] = math.abs[f64](y[i] - my)
        i += 1usize
    }
    let ty = sorted(a, ad)
    let oy = ty[usize(math.floor[f64]((1.0f64 - beta) * f64(n))) - 1usize]
    let px = pbos(a, x, beta)
    let py = pbos(a, y, beta)
    i = 0usize
    while i < n {
        var av = (x[i] - px) / ox
        var bv = (y[i] - py) / oy
        if av <= 0.0f64 - 1.0f64 { av = 0.0f64 - 1.0f64 }
        if av >= 1.0f64 { av = 1.0f64 }
        if bv <= 0.0f64 - 1.0f64 { bv = 0.0f64 - 1.0f64 }
        if bv >= 1.0f64 { bv = 1.0f64 }
        sab += av * bv
        sxx += av * av
        syy += bv * bv
        i += 1usize
    }
    sides += 0usize
    let r = sab / math.sqrt[f64](sxx * syy)
    let test = r * math.sqrt[f64]((f64(n) - 2.0f64) / (1.0f64 - r * r))
    ret Wc { cor: r, cov: nan(), test: test, p: 2.0f64 * (1.0f64 - nb.pt(math.abs[f64](test), f64(n) - 2.0f64, true, false)) }
}

// the AKP robust standardised mean difference of two groups: equal variances (pooled Winsorized) or not (the first group's)
fn akp_d(a: *mem.Arena, x: []const f64, y: []const f64, tr: f64, eqvar: bool) -> f64 {
    let n1 = f64(x.len)
    let n2 = f64(y.len)
    let s1 = winvar(a, x, tr)
    let s2 = winvar(a, y, tr)
    let sp = math.sqrt[f64](((n1 - 1.0f64) * s1 + (n2 - 1.0f64) * s2) / (n1 + n2 - 2.0f64))
    let ct = math.sqrt[f64](cterm(tr))
    if eqvar { ret ct * (tmean(a, x, tr) - tmean(a, y, tr)) / sp }
    ret ct * (tmean(a, x, tr) - tmean(a, y, tr)) / math.sqrt[f64](s1)
}

// msmedse(x): the Maritz-Jarrett-type standard error of the median used by med1way
fn msmedse(a: *mem.Arena, x: []const f64) -> f64 {
    let y = sorted(a, x)
    let n = f64(x.len)
    var av = math.round[f64]((n + 1.0f64) / 2.0f64 - dist.qnorm(0.995f64, 0.0f64, 1.0f64, true, false) * math.sqrt[f64](n / 4.0f64))
    if av == 0.0f64 { av = 1.0f64 }
    let top = n - av + 1.0f64
    let d = (y[usize(top) - 1usize] - y[usize(av) - 1usize]) / (2.0f64 * dist.qnorm(0.995f64, 0.0f64, 1.0f64, true, false))
    ret math.sqrt[f64](d * d)
}

// med1way's test statistic (its critical value is simulated)
fn med1way_stat(a: *mem.Arena, data: []const f64, sizes: []const usize) -> f64 {
    let jn = sizes.len
    let (w, e1) = mem.alloc[f64](a, jn)
    let (xb, e2) = mem.alloc[f64](a, jn)
    if e1 != ok || e2 != ok { ret nan() }
    var off = 0usize
    var j = 0usize
    while j < jn {
        let g = data[off..off + sizes[j]]
        let s = msmedse(a, g)
        w[j] = 1.0f64 / (s * s)
        xb[j] = median_of(a, g)
        off += sizes[j]
        j += 1usize
    }
    var u = 0.0f64
    var xt = 0.0f64
    j = 0usize
    while j < jn {
        u += w[j]
        xt += w[j] * xb[j]
        j += 1usize
    }
    xt = xt / u
    var t = 0.0f64
    j = 0usize
    while j < jn {
        t += w[j] * (xb[j] - xt) * (xb[j] - xt)
        j += 1usize
    }
    ret t / (f64(jn) - 1.0f64)
}

type Pair = struct { psihat: f64, test: f64, se: f64, df: f64, p: f64, padj: f64 }

// lincon(x ~ g, tr): every pair j < k, in R's order, with the raw two-sided p value and its Hochberg adjustment over all pairs
fn lincon(a: *mem.Arena, data: []const f64, sizes: []const usize, tr: f64) -> ([]Pair, err) {
    let jn = sizes.len
    let cc = jn * (jn - 1usize) / 2usize
    let (out, e) = mem.alloc[Pair](a, cc)
    if e != ok { ret (out, e) }
    let (w, e1) = mem.alloc[f64](a, jn)
    let (h, e2) = mem.alloc[f64](a, jn)
    let (xb, e3) = mem.alloc[f64](a, jn)
    if e1 != ok || e2 != ok || e3 != ok { ret (out, e1) }
    var off = 0usize
    var j = 0usize
    while j < jn {
        let g = data[off..off + sizes[j]]
        let n = f64(sizes[j])
        h[j] = n - 2.0f64 * math.floor[f64](tr * n)
        w[j] = ((n - 1.0f64) * winvar(a, g, tr)) / (h[j] * (h[j] - 1.0f64))
        xb[j] = tmean(a, g, tr)
        off += sizes[j]
        j += 1usize
    }
    var c = 0usize
    j = 0usize
    while j < jn {
        var k = j + 1usize
        while k < jn {
            let se = math.sqrt[f64](w[j] + w[k])
            let test = math.abs[f64](xb[j] - xb[k]) / se
            let df = (w[j] + w[k]) * (w[j] + w[k]) / (w[j] * w[j] / (h[j] - 1.0f64) + w[k] * w[k] / (h[k] - 1.0f64))
            out[c] = Pair { psihat: xb[j] - xb[k], test: test, se: se, df: df, p: 2.0f64 * (1.0f64 - nb.pt(test, df, true, false)), padj: 0.0f64 }
            c += 1usize
            k += 1usize
        }
        j += 1usize
    }
    // Hochberg: p sorted in decreasing order (ties keep their order) times 1, 2, ..., then the running minimum, capped at 1
    let (raw, e4) = mem.alloc[f64](a, cc)
    if e4 != ok { ret (out, e4) }
    var i = 0usize
    while i < cc {
        var rank = 0usize
        var q = 0usize
        while q < cc {
            if out[q].p > out[i].p || (out[q].p == out[i].p && q < i) { rank += 1usize }
            q += 1usize
        }
        raw[i] = out[i].p * f64(rank + 1usize)
        i += 1usize
    }
    i = 0usize
    while i < cc {
        var best = raw[i]
        var q = 0usize
        while q < cc {
            if out[q].p > out[i].p || (out[q].p == out[i].p && q < i) {
                if raw[q] < best { best = raw[q] }
            }
            q += 1usize
        }
        if best > 1.0f64 { best = 1.0f64 }
        out[i].padj = best
        i += 1usize
    }
    ret (out, ok)
}

// ---- t2way: the robust two-way ANOVA of WRS2 (trimmed means, winsorised variances of the cell means, Johansen's critical value and the search over
// alpha in steps of 1/1000). The cells are in R's order: cell (j, k) is group (j - 1) * K + k, the second factor fastest.

type T2way = struct { qa: f64, pa: f64, qb: f64, pb: f64, qab: f64, pab: f64 }

// the inverse of the n by n row-major matrix m (Gauss-Jordan with partial pivoting); out is n by n row-major
fn invert_small(a: *mem.Arena, m: []const f64, n: usize, out: []f64) -> err {
    let (w, e) = mem.alloc[f64](a, n * 2usize * n)
    if e != ok { ret e }
    var i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            w[i * 2usize * n + j] = m[i * n + j]
            w[i * 2usize * n + n + j] = 0.0f64
            j += 1usize
        }
        w[i * 2usize * n + n + i] = 1.0f64
        i += 1usize
    }
    var col = 0usize
    while col < n {
        var piv = col
        var r = col + 1usize
        while r < n {
            if math.abs[f64](w[r * 2usize * n + col]) > math.abs[f64](w[piv * 2usize * n + col]) { piv = r }
            r += 1usize
        }
        if w[piv * 2usize * n + col] == 0.0f64 { ret Malformed }
        if piv != col {
            var k = 0usize
            while k < 2usize * n {
                let t = w[col * 2usize * n + k]
                w[col * 2usize * n + k] = w[piv * 2usize * n + k]
                w[piv * 2usize * n + k] = t
                k += 1usize
            }
        }
        let d = w[col * 2usize * n + col]
        var k = 0usize
        while k < 2usize * n {
            w[col * 2usize * n + k] = w[col * 2usize * n + k] / d
            k += 1usize
        }
        r = 0usize
        while r < n {
            if r != col {
                let f = w[r * 2usize * n + col]
                k = 0usize
                while k < 2usize * n {
                    w[r * 2usize * n + k] = w[r * 2usize * n + k] - f * w[col * 2usize * n + k]
                    k += 1usize
                }
            }
            r += 1usize
        }
        col += 1usize
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < n {
            out[i * n + j] = w[i * 2usize * n + n + j]
            j += 1usize
        }
        i += 1usize
    }
    ret ok
}

// WRS2::johan: the statistic of the contrasts cmat (q by p, row-major) on the cell means vmean with squared standard errors vsq and sizes h,
// and its critical value at alpha; returns (statistic, critical value)
fn johan(a: *mem.Arena, cmat: []const f64, q: usize, p: usize, vmean: []const f64, vsq: []const f64, h: []const f64, alpha: f64) -> (f64, f64, err) {
    // test = C diag(vsq) C'  (q by q)
    let (test, e1) = mem.alloc[f64](a, q * q)
    if e1 != ok { ret (0.0f64, 0.0f64, e1) }
    var r = 0usize
    while r < q {
        var s = 0usize
        while s < q {
            var acc = 0.0f64
            var k = 0usize
            while k < p {
                acc += cmat[r * p + k] * vsq[k] * cmat[s * p + k]
                k += 1usize
            }
            test[r * q + s] = acc
            s += 1usize
        }
        r += 1usize
    }
    let (invc, e2) = mem.alloc[f64](a, q * q)
    if e2 != ok { ret (0.0f64, 0.0f64, e2) }
    let e3 = invert_small(a, test, q, invc)
    if e3 != ok { ret (0.0f64, 0.0f64, e3) }
    // u = C vmean, stat = u' invc u
    let (u, e4) = mem.alloc[f64](a, q)
    if e4 != ok { ret (0.0f64, 0.0f64, e4) }
    r = 0usize
    while r < q {
        var acc = 0.0f64
        var k = 0usize
        while k < p {
            acc += cmat[r * p + k] * vmean[k]
            k += 1usize
        }
        u[r] = acc
        r += 1usize
    }
    var stat = 0.0f64
    r = 0usize
    while r < q {
        var s = 0usize
        while s < q {
            stat += u[r] * invc[r * q + s] * u[s]
            s += 1usize
        }
        r += 1usize
    }
    // M = C' invc C; R_ii = vsq_i M_ii; A = sum_i R_ii^2 / (h_i - 1)
    var aa = 0.0f64
    var i = 0usize
    while i < p {
        var m = 0.0f64
        r = 0usize
        while r < q {
            var s = 0usize
            while s < q {
                m += cmat[r * p + i] * invc[r * q + s] * cmat[s * p + i]
                s += 1usize
            }
            r += 1usize
        }
        let rii = vsq[i] * m
        aa += rii * rii / (h[i] - 1.0f64)
        i += 1usize
    }
    let df = f64(q)
    var crit = nm.qchisq(1.0f64 - alpha, df, true, false)
    crit = crit + (crit / (2.0f64 * df)) * aa * (1.0f64 + 3.0f64 * crit / (df + 2.0f64))
    ret (stat, crit, ok)
}

// the statistic of the contrasts (it does not depend on alpha)
fn johan_stat(a: *mem.Arena, cmat: []const f64, q: usize, p: usize, vmean: []const f64, vsq: []const f64, h: []const f64) -> (f64, err) {
    let (s, _, e) = johan(a, cmat, q, p, vmean, vsq, h, 0.5f64)
    ret (s, e)
}

// the p value as WRS2 searches it: the first alpha in steps of 1/1000 at which the statistic exceeds the critical value (irem / 1000), 0.999 when none does
fn johan_p(a: *mem.Arena, cmat: []const f64, q: usize, p: usize, vmean: []const f64, vsq: []const f64, h: []const f64, stat: f64) -> (f64, err) {
    var irem = 999usize
    var i = 1usize
    while i <= 999usize {
        let (_, crit, e) = johan(a, cmat, q, p, vmean, vsq, h, f64(i) / 1000.0f64)
        if e != ok { ret (0.0f64, e) }
        irem = i
        if stat > crit { break }
        i += 1usize
    }
    ret (f64(irem) / 1000.0f64, ok)
}

// the A, B and AB contrasts of J by K cells (q rows each, row-major over the p = J K cells)
fn t2_contrasts(a: *mem.Arena, jn: usize, kn: usize, which: usize, out: []f64) -> err {
    let p = jn * kn
    var ri = 0usize
    var j = 0usize
    var k = 0usize
    if which == 0usize {
        // A: cj (J - 1 by J) kron ik (1 by K ones)
        while j + 1usize < jn {
            k = 0usize
            while k < kn {
                out[j * p + j * kn + k] = 1.0f64
                out[j * p + (j + 1usize) * kn + k] = 0.0f64 - 1.0f64
                k += 1usize
            }
            j += 1usize
        }
        ret ok
    }
    if which == 1usize {
        // B: ij (1 by J ones) kron ck (K - 1 by K)
        var i = 0usize
        while i + 1usize < kn {
            var jj = 0usize
            while jj < jn {
                out[i * p + jj * kn + i] = 1.0f64
                out[i * p + jj * kn + i + 1usize] = 0.0f64 - 1.0f64
                jj += 1usize
            }
            i += 1usize
        }
        ret ok
    }
    // AB: cj kron ck, row ri * (K - 1) + rk
    ri = 0usize
    while ri + 1usize < jn {
        var rk = 0usize
        while rk + 1usize < kn {
            let row = ri * (kn - 1usize) + rk
            var jc = ri
            while jc <= ri + 1usize {
                var kc = rk
                while kc <= rk + 1usize {
                    var sj = 1.0f64
                    if jc != ri { sj = 0.0f64 - 1.0f64 }
                    var sk = 1.0f64
                    if kc != rk { sk = 0.0f64 - 1.0f64 }
                    out[row * p + jc * kn + kc] = sj * sk
                    kc += 1usize
                }
                jc += 1usize
            }
            rk += 1usize
        }
        ri += 1usize
    }
    ret ok
}

// t2way(data, sizes, J, K, tr): the statistics and p values for the A, B and AB contrasts, given the cells in R's order
fn t2way(a: *mem.Arena, data: []const f64, sizes: []const usize, jn: usize, kn: usize, tr: f64) -> (T2way, err) {
    let p = jn * kn
    var out: T2way = zero
    let (tmeans, e1) = mem.alloc[f64](a, p)
    let (hh, e2) = mem.alloc[f64](a, p)
    let (vsq, e3) = mem.alloc[f64](a, p)
    if e1 != ok || e2 != ok || e3 != ok { ret (out, Malformed) }
    var off = 0usize
    var g = 0usize
    while g < p {
        let n = sizes[g]
        let x = data[off..off + n]
        tmeans[g] = tmean(a, x, tr)
        hh[g] = f64(n) - 2.0f64 * math.floor[f64](tr * f64(n))
        vsq[g] = (f64(n) - 1.0f64) * winvar(a, x, tr) / (hh[g] * (hh[g] - 1.0f64))
        off += n
        g += 1usize
    }
    let qa = jn - 1usize
    let qb = kn - 1usize
    let qab = (jn - 1usize) * (kn - 1usize)
    let (ca, e4) = mem.alloc[f64](a, qa * p)
    let (cb, e5) = mem.alloc[f64](a, qb * p)
    let (cab, e6) = mem.alloc[f64](a, qab * p)
    if e4 != ok || e5 != ok || e6 != ok { ret (out, Malformed) }
    var z = 0usize
    while z < qa * p {
        ca[z] = 0.0f64
        z += 1usize
    }
    z = 0usize
    while z < qb * p {
        cb[z] = 0.0f64
        z += 1usize
    }
    z = 0usize
    while z < qab * p {
        cab[z] = 0.0f64
        z += 1usize
    }
    let e7 = t2_contrasts(a, jn, kn, 0usize, ca)
    let e8 = t2_contrasts(a, jn, kn, 1usize, cb)
    let e9 = t2_contrasts(a, jn, kn, 2usize, cab)
    if e7 != ok || e8 != ok || e9 != ok { ret (out, Malformed) }
    let (qs_a, ea) = johan_stat(a, ca, qa, p, tmeans, vsq, hh)
    if ea != ok { ret (out, ea) }
    let (pa, pea) = johan_p(a, ca, qa, p, tmeans, vsq, hh, qs_a)
    if pea != ok { ret (out, pea) }
    let (qs_b, eb) = johan_stat(a, cb, qb, p, tmeans, vsq, hh)
    if eb != ok { ret (out, eb) }
    let (pb, peb) = johan_p(a, cb, qb, p, tmeans, vsq, hh, qs_b)
    if peb != ok { ret (out, peb) }
    let (qs_ab, eab) = johan_stat(a, cab, qab, p, tmeans, vsq, hh)
    if eab != ok { ret (out, eab) }
    let (pab, peab) = johan_p(a, cab, qab, p, tmeans, vsq, hh, qs_ab)
    if peab != ok { ret (out, peab) }
    out.qa = qs_a
    out.pa = pa
    out.qb = qs_b
    out.pb = pb
    out.qab = qs_ab
    out.pab = pab
    ret (out, ok)
}
