// R nortest and moments: the Lilliefors, Cramer-von Mises, Shapiro-Francia and Pearson chi-square
// normality tests, and the moments helpers `moment`, `skewness`, `kurtosis` with the Jarque-Bera,
// D'Agostino, Anscombe-Glynn and Bonett-Seier tests. A test answers its statistic (and second statistic
// where the package gives one) and its p-value; the alternative is 0 two-sided, 1 less, 2 greater.
//
// Not here: the Anderson-Darling test (nortest ad.test) and the Geary and Wilk tests of moments.

use e.algo.sort
use e.math
use e.math.dist as dist
use e.math.nmath as nm
use e.mem

fn cmp_up(ctx: *u8, x: f64, y: f64) -> i32 {
    if x < y { ret 0i32 - 1i32 }
    if x > y { ret 1i32 }
    ret 0i32
}

fn sorted(a: *mem.Arena, x: []const f64) -> ([]f64, err) {
    let (d, e) = mem.alloc[f64](a, x.len)
    if e != ok { ret (d, e) }
    var i = 0usize
    while i < x.len {
        d[i] = x[i]
        i += 1usize
    }
    var ctx = 0u8
    sort.in_place_by[f64, u8](d, &ctx, cmp_up)
    ret (d, ok)
}

fn mean_of(x: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    var m = s / f64(x.len)
    var t = 0.0f64
    i = 0usize
    while i < x.len {
        t += x[i] - m
        i += 1usize
    }
    ret m + t / f64(x.len)
}

fn sd_of(x: []const f64) -> f64 {
    let m = mean_of(x)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    ret math.sqrt[f64](s / f64(x.len - 1usize))
}

fn pn(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }

// moment(x, order, central, absolute)
fn moment(x: []const f64, order: f64, central: bool, absolute: bool) -> f64 {
    var mu = 0.0f64
    if central { mu = mean_of(x) }
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        var v = x[i] - mu
        if absolute && v < 0.0f64 { v = 0.0f64 - v }
        s += math.pow[f64](v, order)
        i += 1usize
    }
    ret s / f64(x.len)
}

fn central_sums(x: []const f64) -> (f64, f64, f64, f64) {
    let m = mean_of(x)
    var m2 = 0.0f64
    var m3 = 0.0f64
    var m4 = 0.0f64
    var i = 0usize
    while i < x.len {
        let d = x[i] - m
        m2 += d * d
        m3 += d * d * d
        m4 += d * d * d * d
        i += 1usize
    }
    ret (m, m2, m3, m4)
}

fn skewness(x: []const f64) -> f64 {
    let n = f64(x.len)
    let (m, m2, m3, m4) = central_sums(x)
    ret (m3 / n) / math.pow[f64](m2 / n, 1.5f64)
}

fn kurtosis(x: []const f64) -> f64 {
    let n = f64(x.len)
    let (m, m2, m3, m4) = central_sums(x)
    ret n * m4 / (m2 * m2)
}

fn alt_p(p0: f64, alter: u8) -> f64 {
    var p = p0
    if alter == 0u8 {
        p = 2.0f64 * p
        if p > 1.0f64 { p = 2.0f64 - p }
    } else if alter == 2u8 {
        p = 1.0f64 - p
    }
    ret p
}

// Jarque-Bera by moments: (statistic, p-value)
fn jarque_test(x: []const f64) -> (f64, f64) {
    let n = f64(x.len)
    let k = kurtosis(x)
    let s = skewness(x)
    let jb = (n / 6.0f64) * (s * s + 0.25f64 * ((k - 3.0f64) * (k - 3.0f64)))
    ret (jb, 1.0f64 - nm.pchisq(jb, 2.0f64, true, false))
}

// agostino.test: (skewness, z, p)
fn agostino(x: []const f64, alter: u8) -> (f64, f64, f64) {
    let n = f64(x.len)
    let s3 = skewness(x)
    let y = s3 * math.sqrt[f64]((n + 1.0f64) * (n + 3.0f64) / (6.0f64 * (n - 2.0f64)))
    let b2 = 3.0f64 * (n * n + 27.0f64 * n - 70.0f64) * (n + 1.0f64) * (n + 3.0f64) / ((n - 2.0f64) * (n + 5.0f64) * (n + 7.0f64) * (n + 9.0f64))
    let w = math.sqrt[f64](0.0f64 - 1.0f64 + math.sqrt[f64](2.0f64 * (b2 - 1.0f64)))
    let d = 1.0f64 / math.sqrt[f64](math.log[f64](w))
    let aa = math.sqrt[f64](2.0f64 / (w * w - 1.0f64))
    let z = d * math.log[f64](y / aa + math.sqrt[f64]((y / aa) * (y / aa) + 1.0f64))
    ret (s3, z, alt_p(1.0f64 - pn(z), alter))
}

// anscombe.test: (kurtosis, z, p)
fn anscombe(x: []const f64, alter: u8) -> (f64, f64, f64) {
    let n = f64(x.len)
    let b = kurtosis(x)
    let eb2 = 3.0f64 * (n - 1.0f64) / (n + 1.0f64)
    let vb2 = 24.0f64 * n * (n - 2.0f64) * (n - 3.0f64) / ((n + 1.0f64) * (n + 1.0f64) * (n + 3.0f64) * (n + 5.0f64))
    let m3 = (6.0f64 * (n * n - 5.0f64 * n + 2.0f64) / ((n + 7.0f64) * (n + 9.0f64))) * math.sqrt[f64]((6.0f64 * (n + 3.0f64) * (n + 5.0f64)) / (n * (n - 2.0f64) * (n - 3.0f64)))
    let a = 6.0f64 + (8.0f64 / m3) * (2.0f64 / m3 + math.sqrt[f64](1.0f64 + 4.0f64 / (m3 * m3)))
    let xx = (b - eb2) / math.sqrt[f64](vb2)
    let z = (1.0f64 - 2.0f64 / (9.0f64 * a) - math.pow[f64]((1.0f64 - 2.0f64 / a) / (1.0f64 + xx * math.sqrt[f64](2.0f64 / (a - 4.0f64))), 1.0f64 / 3.0f64)) / math.sqrt[f64](2.0f64 / (9.0f64 * a))
    ret (b, z, alt_p(1.0f64 - pn(z), alter))
}

// bonett.test: (tau, z, p)
fn bonett(x: []const f64, alter: u8) -> (f64, f64, f64) {
    let n = f64(x.len)
    let m = mean_of(x)
    var ss = 0.0f64
    var sa = 0.0f64
    var i = 0usize
    while i < x.len {
        ss += (x[i] - m) * (x[i] - m)
        var d = x[i] - m
        if d < 0.0f64 { d = 0.0f64 - d }
        sa += d
        i += 1usize
    }
    let rho = math.sqrt[f64](ss / n)
    let tau = sa / n
    let omega = 13.29f64 * (math.log[f64](rho) - math.log[f64](tau))
    let z = math.sqrt[f64](n + 2.0f64) * (omega - 3.0f64) / 3.54f64
    ret (tau, z, alt_p(1.0f64 - pn(z), alter))
}

// lillie.test: (D, p)
fn lillie(a: *mem.Arena, x: []const f64) -> (f64, f64, err) {
    let (s, e) = sorted(a, x)
    if e != ok { ret (0.0f64, 0.0f64, e) }
    let n = s.len
    let nf = f64(n)
    let m = mean_of(s)
    let sd = sd_of(s)
    var k = 0.0f64
    var i = 0usize
    while i < n {
        let p = pn((s[i] - m) / sd)
        let dp = f64(i + 1usize) / nf - p
        let dm = p - f64(i) / nf
        if dp > k { k = dp }
        if dm > k { k = dm }
        i += 1usize
    }
    var kd = k
    var nd = nf
    if n > 100usize {
        kd = k * math.pow[f64](nf / 100.0f64, 0.49f64)
        nd = 100.0f64
    }
    var pv = math.exp[f64](0.0f64 - 7.01256f64 * kd * kd * (nd + 2.78019f64) + 2.99587f64 * kd * math.sqrt[f64](nd + 2.78019f64) - 0.122119f64 + 0.974598f64 / math.sqrt[f64](nd) + 1.67997f64 / nd)
    if pv > 0.1f64 {
        let kk = (math.sqrt[f64](nf) - 0.01f64 + 0.85f64 / math.sqrt[f64](nf)) * k
        if kk <= 0.302f64 {
            pv = 1.0f64
        } else if kk <= 0.5f64 {
            pv = 2.76773f64 - 19.828315f64 * kk + 80.709644f64 * kk * kk - 138.55152f64 * kk * kk * kk + 81.218052f64 * kk * kk * kk * kk
        } else if kk <= 0.9f64 {
            pv = 0.0f64 - 4.901232f64 + 40.662806f64 * kk - 97.490286f64 * kk * kk + 94.029866f64 * kk * kk * kk - 32.355711f64 * kk * kk * kk * kk
        } else if kk <= 1.31f64 {
            pv = 6.198765f64 - 19.558097f64 * kk + 23.186922f64 * kk * kk - 12.234627f64 * kk * kk * kk + 2.423045f64 * kk * kk * kk * kk
        } else {
            pv = 0.0f64
        }
    }
    ret (k, pv, ok)
}

// cvm.test: (W, p)
fn cvm(a: *mem.Arena, x: []const f64) -> (f64, f64, err) {
    let (s, e) = sorted(a, x)
    if e != ok { ret (0.0f64, 0.0f64, e) }
    let n = s.len
    let nf = f64(n)
    let m = mean_of(s)
    let sd = sd_of(s)
    var w = 1.0f64 / (12.0f64 * nf)
    var i = 0usize
    while i < n {
        let p = pn((s[i] - m) / sd)
        let t = p - (2.0f64 * f64(i + 1usize) - 1.0f64) / (2.0f64 * nf)
        w += t * t
        i += 1usize
    }
    let ww = (1.0f64 + 0.5f64 / nf) * w
    var pv = 7.37e-10f64
    if ww < 0.0275f64 {
        pv = 1.0f64 - math.exp[f64](0.0f64 - 13.953f64 + 775.5f64 * ww - 12542.61f64 * ww * ww)
    } else if ww < 0.051f64 {
        pv = 1.0f64 - math.exp[f64](0.0f64 - 5.903f64 + 179.546f64 * ww - 1515.29f64 * ww * ww)
    } else if ww < 0.092f64 {
        pv = math.exp[f64](0.886f64 - 31.62f64 * ww + 10.897f64 * ww * ww)
    } else if ww < 1.1f64 {
        pv = math.exp[f64](1.111f64 - 34.242f64 * ww + 12.832f64 * ww * ww)
    }
    ret (w, pv, ok)
}

// sf.test: (W, p)
fn sf(a: *mem.Arena, x: []const f64) -> (f64, f64, err) {
    let (s, e) = sorted(a, x)
    if e != ok { ret (0.0f64, 0.0f64, e) }
    let n = s.len
    let nf = f64(n)
    let (y, ye) = mem.alloc[f64](a, n)
    if ye != ok { ret (0.0f64, 0.0f64, ye) }
    var i = 0usize
    while i < n {
        y[i] = dist.qnorm((f64(i + 1usize) - 0.375f64) / (nf + 1.0f64 - 0.75f64), 0.0f64, 1.0f64, true, false)
        i += 1usize
    }
    let mx = mean_of(s)
    let my = mean_of(y)
    var sxy = 0.0f64
    var sxx = 0.0f64
    var syy = 0.0f64
    i = 0usize
    while i < n {
        sxy += (s[i] - mx) * (y[i] - my)
        sxx += (s[i] - mx) * (s[i] - mx)
        syy += (y[i] - my) * (y[i] - my)
        i += 1usize
    }
    let r = sxy / math.sqrt[f64](sxx * syy)
    let w = r * r
    let u = math.log[f64](nf)
    let v = math.log[f64](u)
    let mu = 0.0f64 - 1.2725f64 + 1.0521f64 * (v - u)
    let sig = 1.0308f64 - 0.26758f64 * (v + 2.0f64 / u)
    let z = (math.log[f64](1.0f64 - w) - mu) / sig
    ret (w, 1.0f64 - pn(z), ok)
}

// pearson.test with the default class count (ceiling(2 n^(2/5))) when classes is 0: (P, p, classes)
fn pearson(a: *mem.Arena, x: []const f64, classes0: usize, adjust: bool) -> (f64, f64, usize, err) {
    let n = x.len
    let nf = f64(n)
    var nc = classes0
    if nc == 0usize { nc = usize(math.ceil[f64](2.0f64 * math.pow[f64](nf, 0.4f64))) }
    let m = mean_of(x)
    let sd = sd_of(x)
    let (count, ce) = mem.alloc[f64](a, nc)
    if ce != ok { ret (0.0f64, 0.0f64, nc, ce) }
    var i = 0usize
    while i < nc {
        count[i] = 0.0f64
        i += 1usize
    }
    i = 0usize
    while i < n {
        let cls = usize(math.floor[f64](1.0f64 + f64(nc) * pn((x[i] - m) / sd)))
        if cls >= 1usize && cls <= nc { count[cls - 1usize] += 1.0f64 }
        i += 1usize
    }
    let xpec = nf / f64(nc)
    var p = 0.0f64
    i = 0usize
    while i < nc {
        p += (count[i] - xpec) * (count[i] - xpec) / xpec
        i += 1usize
    }
    var dfd = 0usize
    if adjust { dfd = 2usize }
    ret (p, nm.pchisq(p, f64(nc - dfd - 1usize), false, false), nc, ok)
}
