// R EnvStats: Rosner's generalised ESD test for outliers (rosnerTest and its critical values), the normal tolerance
// interval factors (tolIntNormK) for the one-sided content, the expectation and the Wald-Wolfowitz two-sided content
// types, and the normal prediction interval factor (predIntNormK) for one future observation or a Bonferroni set.
// The non-central t quantile is R's own bisection (qnt.c).
//
// Not here: the exact two-sided tolerance factor (a nested integral and optimiser), the exact multiple-prediction
// factor (Dunnett's multivariate t), the other estimation, interval and testing families of the package.

use e.algo.stat.nortest as nt
use e.algo.stat.pwr as pwr
use e.algo.stat.test as tst
use e.math
use e.math.dist as dist
use e.math.nchisq as nc
use e.math.nmath as nm
use e.math.nmath_beta as nb
use e.mem

type Rosner = struct { n: usize, k: usize, mean: []f64, sd: []f64, value: []f64, obs: []f64, r: []f64, lambda: []f64, outlier: []bool, nout: usize }

// the critical value lambda_{i+1} for a sample of n with i observations already removed (k = i + 1)
fn rosner_lambda(n: usize, k: usize, alpha: f64) -> f64 {
    let l = f64(k) - 1.0f64
    let p = 1.0f64 - (alpha / 2.0f64) / (f64(n) - l)
    let tc = nb.qt(p, f64(n) - l - 2.0f64, true, false)
    ret tc * (f64(n) - l - 1.0f64) / math.sqrt[f64]((f64(n) - l - 2.0f64 + tc * tc) * (f64(n) - l))
}

fn rosner_test(a: *mem.Arena, x: []const f64, k: usize, alpha: f64) -> (Rosner, err) {
    var r: Rosner = zero
    let n = x.len
    r.n = n
    r.k = k
    let (mean, e1) = mem.alloc[f64](a, k)
    let (sd, e2) = mem.alloc[f64](a, k)
    let (val, e3) = mem.alloc[f64](a, k)
    let (obs, e4) = mem.alloc[f64](a, k)
    let (rr, e5) = mem.alloc[f64](a, k)
    let (lam, e6) = mem.alloc[f64](a, k)
    let (out, e7) = mem.alloc[bool](a, k)
    let (cur, e8) = mem.alloc[f64](a, n)
    let (num, e9) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret (r, mem.Full) }
    let nan = 0.0f64 / 0.0f64
    var i = 0usize
    while i < n {
        cur[i] = x[i]
        num[i] = i + 1usize
        i += 1usize
    }
    var m = n
    var stopped = false
    i = 0usize
    while i < k {
        mean[i] = nan
        sd[i] = nan
        val[i] = nan
        obs[i] = nan
        rr[i] = nan
        out[i] = false
        if !stopped {
            var s = 0.0f64
            var j = 0usize
            while j < m {
                s += cur[j]
                j += 1usize
            }
            let mu = s / f64(m)
            var ss = 0.0f64
            j = 0usize
            while j < m {
                ss += (cur[j] - mu) * (cur[j] - mu)
                j += 1usize
            }
            let sdv = math.sqrt[f64](ss / f64(m - 1usize))
            mean[i] = mu
            sd[i] = sdv
            if sdv > 0.0f64 {
                var best = 0usize
                var bz = math.abs[f64](cur[0usize] - mu) / sdv
                j = 1usize
                while j < m {
                    let z = math.abs[f64](cur[j] - mu) / sdv
                    if z > bz {
                        bz = z
                        best = j
                    }
                    j += 1usize
                }
                rr[i] = bz
                val[i] = cur[best]
                obs[i] = f64(num[best])
                j = best
                while j + 1usize < m {
                    cur[j] = cur[j + 1usize]
                    num[j] = num[j + 1usize]
                    j += 1usize
                }
                m -= 1usize
            } else {
                stopped = true
            }
        }
        lam[i] = rosner_lambda(n, i + 1usize, alpha)
        i += 1usize
    }
    var last = 0usize
    var any = false
    i = 0usize
    while i < k {
        if rr[i] == rr[i] && rr[i] > lam[i] {
            last = i
            any = true
        }
        i += 1usize
    }
    var cnt = 0usize
    i = 0usize
    while i < k {
        if any && i <= last { out[i] = true }
        if out[i] { cnt += 1usize }
        i += 1usize
    }
    r.mean = mean
    r.sd = sd
    r.value = val
    r.obs = obs
    r.r = rr
    r.lambda = lam
    r.outlier = out
    r.nout = cnt
    ret (r, ok)
}

// R's qnt: bisection on the non-central t distribution function
fn qnt(p0: f64, df: f64, ncp: f64) -> f64 {
    let eps = 1.0e-11f64
    let accu = 1.0e-13f64
    let de = 2.220446049250313e-16f64
    if p0 > 1.0f64 - de { ret 1.0f64 / 0.0f64 }
    var pp = p0 * (1.0f64 + eps)
    if pp > 1.0f64 - de { pp = 1.0f64 - de }
    var ux = ncp
    if ux < 1.0f64 { ux = 1.0f64 }
    while ux < 1.0e300f64 && nc.pnt(ux, df, ncp, true, false) < pp { ux *= 2.0f64 }
    pp = p0 * (1.0f64 - eps)
    var lx = 0.0f64 - ncp
    if lx > 0.0f64 - 1.0f64 { lx = 0.0f64 - 1.0f64 }
    while lx > 0.0f64 - 1.0e300f64 && nc.pnt(lx, df, ncp, true, false) > pp { lx *= 2.0f64 }
    var go = true
    while go {
        let nx = 0.5f64 * (lx + ux)
        if nc.pnt(nx, df, ncp, true, false) > p0 { ux = nx } else { lx = nx }
        var mx = math.abs[f64](lx)
        if math.abs[f64](ux) > mx { mx = math.abs[f64](ux) }
        go = ux - lx > mx * accu
    }
    ret 0.5f64 * (lx + ux)
}

// tolIntNormK: kind 0 content one-sided, 1 content two-sided Wald-Wolfowitz, 2 expectation one-sided, 3 expectation two-sided
fn tol_k(n: f64, coverage: f64, conf: f64, kind: i64) -> f64 {
    let df = n - 1.0f64
    if kind == 0i64 { ret qnt(conf, df, dist.qnorm(coverage, 0.0f64, 1.0f64, true, false) * math.sqrt[f64](n)) / math.sqrt[f64](n) }
    if kind == 2i64 { ret math.sqrt[f64](1.0f64 + 1.0f64 / n) * nb.qt(coverage, df, true, false) }
    if kind == 3i64 { ret math.sqrt[f64](1.0f64 + 1.0f64 / n) * nb.qt(1.0f64 - (1.0f64 - coverage) / 2.0f64, df, true, false) }
    // the half-width r with pnorm(x + r) - pnorm(x - r) = coverage, x = 1 / sqrt(n), found by bisection
    let x = 1.0f64 / math.sqrt[f64](n)
    var lo = 0.0f64
    var hi = 10.0f64
    var it = 0usize
    while it < 200usize {
        let mid = 0.5f64 * (lo + hi)
        let cv = dist.pnorm(x + mid, 0.0f64, 1.0f64, true, false) - dist.pnorm(x - mid, 0.0f64, 1.0f64, true, false)
        if cv < coverage { lo = mid } else { hi = mid }
        it += 1usize
    }
    let u = math.sqrt[f64](df / nm.qchisq(1.0f64 - conf, df, true, false))
    ret 0.5f64 * (lo + hi) * u
}

// predIntNormK for one future mean of n_mean observations (k = 1, exact) or k future means by Bonferroni; two_sided picks the tails
fn pred_k(n: f64, n_mean: f64, k: f64, two_sided: bool, conf: f64) -> f64 {
    var a = 1.0f64 - conf
    if k > 1.0f64 { a = a / k }
    if two_sided { a = a / 2.0f64 }
    ret nb.qt(1.0f64 - a, n - 1.0f64, true, false) * math.sqrt[f64](1.0f64 / n_mean + 1.0f64 / n)
}

// ---- kendallTrendTest ----

fn sort_f(v: []f64) {
    var i = 1usize
    while i < v.len {
        let t = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > t {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = t
        i += 1usize
    }
}

fn median_sorted(v: []const f64) -> f64 {
    let n = v.len
    if n % 2usize == 1usize { ret v[n / 2usize] }
    ret (v[n / 2usize - 1usize] + v[n / 2usize]) / 2.0f64
}

// sum over the tie groups of the sorted values of f(t)
fn tie_sums(s: []const f64, k: usize) -> f64 {
    var total = 0.0f64
    var i = 0usize
    while i < s.len {
        var j = i
        while j + 1usize < s.len && s[j + 1usize] == s[i] { j += 1usize }
        let t = f64(j - i + 1usize)
        if k == 1usize { total += t * (t - 1.0f64) }
        if k == 2usize { total += t * (t - 1.0f64) * (2.0f64 * t + 5.0f64) }
        if k == 3usize { total += t * (t - 1.0f64) * (t - 2.0f64) }
        i = j + 1usize
    }
    ret total
}

// EnvStats::kendallTrendTest: out receives S, var.S, z, p, tau, slope, intercept, the confidence limits (lower, upper) and the number of slopes; alt 0 two-sided, 1 greater, 2 less
fn kendall_trend(a: *mem.Arena, y: []const f64, x: []const f64, alt: usize, correct: bool, conf: f64, out: []f64) -> err {
    let n = y.len
    let nf = f64(n)
    var s = 0.0f64
    let np0 = n * (n - 1usize) / 2usize
    let (sl, e1) = mem.alloc[f64](a, np0)
    let (sx, e2) = mem.alloc[f64](a, n)
    let (sy, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var cnt = 0usize
    var i = 1usize
    while i < n {
        var j = 0usize
        while j < i {
            let pr = (x[i] - x[j]) * (y[i] - y[j])
            if pr > 0.0f64 { s += 1.0f64 }
            if pr < 0.0f64 { s -= 1.0f64 }
            let q = (y[i] - y[j]) / (x[i] - x[j])
            if q - q == 0.0f64 {
                sl[cnt] = q
                cnt += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let slopes = sl[0usize..cnt]
    sort_f(slopes)
    i = 0usize
    while i < n {
        sx[i] = x[i]
        sy[i] = y[i]
        i += 1usize
    }
    sort_f(sx)
    sort_f(sy)
    let tau = 2.0f64 * s / (nf * (nf - 1.0f64))
    let slope = median_sorted(slopes)
    let intercept = median_sorted(sy) - slope * median_sorted(sx)
    var v1 = (nf * (nf - 1.0f64) * (2.0f64 * nf + 5.0f64) - tie_sums(sx, 2usize) - tie_sums(sy, 2usize)) / 18.0f64
    var v2 = 0.0f64
    if n > 2usize { v2 = (tie_sums(sx, 3usize) * tie_sums(sy, 3usize)) / (9.0f64 * nf * (nf - 1.0f64) * (nf - 2.0f64)) }
    let v3 = (tie_sums(sx, 1usize) * tie_sums(sy, 1usize)) / (2.0f64 * nf * (nf - 1.0f64))
    let vars = v1 + v2 + v3
    var z = s / math.sqrt[f64](vars)
    if correct {
        var sg = 0.0f64
        if s > 0.0f64 { sg = 1.0f64 }
        if s < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        z = (s - sg) / math.sqrt[f64](vars)
    }
    var p = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false)
    if alt == 1usize { p = 1.0f64 - dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
    if alt == 2usize { p = dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
    let alpha = 1.0f64 - conf
    var zq = dist.qnorm(conf, 0.0f64, 1.0f64, true, false)
    if alt == 0usize { zq = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false) }
    let npr = f64(cnt)
    let ca = zq * math.sqrt[f64](vars)
    let m1 = (npr - ca) / 2.0f64
    let m2 = (npr + ca) / 2.0f64
    let nan = 0.0f64 / 0.0f64
    var lcl = nan
    var ucl = nan
    if alt == 0usize {
        lcl = interp1(slopes, m1)
        ucl = interp1(slopes, m2 + 1.0f64)
    } else if alt == 1usize {
        lcl = interp1(slopes, m1)
        ucl = 1.0f64 / 0.0f64
    } else {
        lcl = 0.0f64 - 1.0f64 / 0.0f64
        ucl = interp1(slopes, m2 + 1.0f64)
    }
    out[0usize] = s
    out[1usize] = vars
    out[2usize] = z
    out[3usize] = p
    out[4usize] = tau
    out[5usize] = slope
    out[6usize] = intercept
    out[7usize] = lcl
    out[8usize] = ucl
    out[9usize] = npr
    v1 += 0.0f64
    v2 += 0.0f64
    ret ok
}

// approx(1:n, v, xout): linear interpolation on the index, NaN outside 1..n
fn interp1(v: []const f64, xo: f64) -> f64 {
    let n = v.len
    if xo < 1.0f64 || xo > f64(n) || xo != xo { ret 0.0f64 / 0.0f64 }
    let lo = math.floor[f64](xo)
    if lo >= f64(n) { ret v[n - 1usize] }
    let i = usize(lo) - 1usize
    let fr = xo - lo
    ret v[i] + (v[i + 1usize] - v[i]) * fr
}

// ---- kendallSeasonalTrendTest (independent observations) ----

// the finite pairwise slopes of y against x, unsorted; answers the count (np0 = n (n - 1) / 2 spaces in out)
fn pair_slopes(y: []const f64, x: []const f64, out: []f64) -> usize {
    var cnt = 0usize
    var i = 1usize
    while i < y.len {
        var j = 0usize
        while j < i {
            let q = (y[i] - y[j]) / (x[i] - x[j])
            if q - q == 0.0f64 {
                out[cnt] = q
                cnt += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    ret cnt
}

// EnvStats::kendallSeasonalTrendTest with independent.obs = TRUE and finite data: season holds numeric season ids and year the years; out receives the heterogeneity chi-square and its p value, z and its p value, tau, slope, intercept, the confidence limits, S, var.S, the number of slopes and the number of seasons used (0..10)
fn kendall_seasonal(a: *mem.Arena, y: []const f64, season: []const f64, year: []const f64, alt: usize, correct: bool, conf: f64, out: []f64) -> err {
    let n = y.len
    let nan = 0.0f64 / 0.0f64
    let (ids, e0) = mem.alloc[f64](a, n)
    let (sy, e1) = mem.alloc[f64](a, n)
    let (sx, e2) = mem.alloc[f64](a, n)
    let (allsl, e3) = mem.alloc[f64](a, n * n + 1usize)
    let (ints, e4) = mem.alloc[f64](a, n)
    let (zs, e5) = mem.alloc[f64](a, n)
    let (ko, e6) = mem.alloc[f64](a, 10usize)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret mem.Full }
    var ns = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < ns {
            if ids[j] == season[i] { seen = true }
            j += 1usize
        }
        if !seen {
            ids[ns] = season[i]
            ns += 1usize
        }
        i += 1usize
    }
    sort_f(ids[0usize..ns])
    var nslopes = 0usize
    var sumn = 0.0f64
    var sumtau = 0.0f64
    var stot = 0.0f64
    var vtot = 0.0f64
    var nact = 0usize
    var sumz = 0.0f64
    var sumz2 = 0.0f64
    var k = 0usize
    while k < ns {
        var m = 0usize
        i = 0usize
        while i < n {
            if season[i] == ids[k] {
                sy[m] = y[i]
                sx[m] = year[i]
                m += 1usize
            }
            i += 1usize
        }
        var distinct = false
        i = 1usize
        while i < m {
            if sx[i] != sx[0usize] { distinct = true }
            i += 1usize
        }
        if m >= 2usize && distinct {
            let ek = kendall_trend(a, sy[0usize..m], sx[0usize..m], 0usize, true, 0.95f64, ko)
            if ek != ok { ret ek }
            let c = pair_slopes(sy[0usize..m], sx[0usize..m], allsl[nslopes..n * n])
            nslopes += c
            sumn += f64(m)
            sumtau += f64(m) * ko[4usize]
            stot += ko[0usize]
            vtot += ko[1usize]
            ints[nact] = ko[6usize]
            let zv = ko[0usize] / math.sqrt[f64](ko[1usize])
            zs[nact] = zv
            sumz += zv
            sumz2 += zv * zv
            nact += 1usize
        }
        k += 1usize
    }
    let slopes = allsl[0usize..nslopes]
    sort_f(slopes)
    sort_f(ints[0usize..nact])
    let kf = f64(nact)
    let chisq = sumz2 - kf * (sumz / kf) * (sumz / kf)
    out[0usize] = chisq
    out[1usize] = 1.0f64 - nm.pchisq(chisq, kf - 1.0f64, true, false)
    var z = stot / math.sqrt[f64](vtot)
    if correct {
        var sg = 0.0f64
        if stot > 0.0f64 { sg = 1.0f64 }
        if stot < 0.0f64 { sg = 0.0f64 - 1.0f64 }
        z = (stot - sg) / math.sqrt[f64](vtot)
    }
    var p = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false)
    if alt == 1usize { p = 1.0f64 - dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
    if alt == 2usize { p = dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
    out[2usize] = z
    out[3usize] = p
    out[4usize] = sumtau / sumn
    out[5usize] = median_sorted(slopes)
    out[6usize] = median_sorted(ints[0usize..nact])
    let alpha = 1.0f64 - conf
    var zq = dist.qnorm(conf, 0.0f64, 1.0f64, true, false)
    if alt == 0usize { zq = dist.qnorm(1.0f64 - alpha / 2.0f64, 0.0f64, 1.0f64, true, false) }
    let npr = f64(nslopes)
    let ca = zq * math.sqrt[f64](vtot)
    let m1 = (npr - ca) / 2.0f64
    let m2 = (npr + ca) / 2.0f64
    var lcl = nan
    var ucl = nan
    if alt == 0usize {
        lcl = interp1(slopes, m1)
        ucl = interp1(slopes, m2 + 1.0f64)
    } else if alt == 1usize {
        lcl = interp1(slopes, m1)
        ucl = 1.0f64 / 0.0f64
    } else {
        lcl = 0.0f64 - 1.0f64 / 0.0f64
        ucl = interp1(slopes, m2 + 1.0f64)
    }
    out[7usize] = lcl
    out[8usize] = ucl
    out[9usize] = stot
    out[10usize] = vtot
    out[11usize] = npr
    out[12usize] = kf
    ret ok
}

// ---- gofTest for the normal and lognormal distributions ----

// nortest::ad.test: the Anderson-Darling statistic A and its p value from the sample sorted in x
fn ad_normal(x: []const f64) -> (f64, f64) {
    let n = x.len
    let nf = f64(n)
    var mean = 0.0f64
    var i = 0usize
    while i < n {
        mean += x[i]
        i += 1usize
    }
    mean = mean / nf
    var ss = 0.0f64
    i = 0usize
    while i < n {
        ss += (x[i] - mean) * (x[i] - mean)
        i += 1usize
    }
    let sd = math.sqrt[f64](ss / (nf - 1.0f64))
    var h = 0.0f64
    i = 0usize
    while i < n {
        let l1 = dist.pnorm((x[i] - mean) / sd, 0.0f64, 1.0f64, true, true)
        let l2 = dist.pnorm(0.0f64 - (x[n - 1usize - i] - mean) / sd, 0.0f64, 1.0f64, true, true)
        h += (2.0f64 * f64(i + 1usize) - 1.0f64) * (l1 + l2)
        i += 1usize
    }
    let aa = 0.0f64 - nf - h / nf
    let a2 = (1.0f64 + 0.75f64 / nf + 2.25f64 / (nf * nf)) * aa
    var p = 3.7e-24f64
    if a2 < 0.2f64 {
        p = 1.0f64 - math.exp[f64](0.0f64 - 13.436f64 + 101.14f64 * a2 - 223.73f64 * a2 * a2)
    } else if a2 < 0.34f64 {
        p = 1.0f64 - math.exp[f64](0.0f64 - 8.318f64 + 42.796f64 * a2 - 59.938f64 * a2 * a2)
    } else if a2 < 0.6f64 {
        p = math.exp[f64](0.9177f64 - 4.279f64 * a2 - 1.38f64 * a2 * a2)
    } else if a2 < 10.0f64 {
        p = math.exp[f64](1.2937f64 - 5.709f64 * a2 + 0.0186f64 * a2 * a2)
    }
    ret (aa, p)
}

// EnvStats::gofTest of y against the normal (lnorm = false) or lognormal distribution: test 0 Shapiro-Wilk (W), 1 Shapiro-Francia (W'), 2 Anderson-Darling (A), 3 Cramer-von Mises, 4 Lilliefors, 5 zero skew (the skewness, with z in out[2]; alt 0 two-sided, 1 less, 2 greater), 6 probability plot correlation (the correlation); out receives the statistic, the p value and z
fn gof_test(a: *mem.Arena, y: []const f64, test: usize, lnorm: bool, alt: usize, out: []f64) -> err {
    let n = y.len
    let (x, e1) = mem.alloc[f64](a, n)
    let (sc, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret mem.Full }
    var i = 0usize
    while i < n {
        x[i] = y[i]
        if lnorm { x[i] = math.log[f64](y[i]) }
        i += 1usize
    }
    out[2usize] = 0.0f64 / 0.0f64
    if test == 0usize {
        let (r, e) = tst.shapiro_wilk(x, sc)
        if e != ok { ret e }
        out[0usize] = r.statistic
        out[1usize] = r.p_value
        out[2usize] = dist.qnorm(r.p_value, 0.0f64, 1.0f64, false, false)
    } else if test == 1usize || test == 6usize {
        let (w, p, e) = nt.sf(a, x)
        if e != ok { ret e }
        out[0usize] = w
        out[1usize] = p
        let u = math.log[f64](f64(n))
        let v = math.log[f64](u)
        let mu = 0.0f64 - 1.2725f64 + 1.0521f64 * (v - u)
        let sig = 1.0308f64 - 0.26758f64 * (v + 2.0f64 / u)
        out[2usize] = (math.log[f64](1.0f64 - w) - mu) / sig
        if test == 6usize { out[0usize] = math.sqrt[f64](w) }
    } else if test == 2usize {
        sort_f(x)
        let (aa, p) = ad_normal(x)
        out[0usize] = aa
        out[1usize] = p
    } else if test == 3usize {
        let (w, p, e) = nt.cvm(a, x)
        if e != ok { ret e }
        out[0usize] = w
        out[1usize] = p
    } else if test == 4usize {
        let (d, p, e) = nt.lillie(a, x)
        if e != ok { ret e }
        out[0usize] = d
        out[1usize] = p
    } else {
        let nf = f64(n)
        var mean = 0.0f64
        i = 0usize
        while i < n {
            mean += x[i]
            i += 1usize
        }
        mean = mean / nf
        var m2 = 0.0f64
        var m3 = 0.0f64
        i = 0usize
        while i < n {
            let d = x[i] - mean
            m2 += d * d
            m3 += d * d * d
            i += 1usize
        }
        m2 = m2 / nf
        m3 = m3 / nf
        let sb1 = m3 / math.pow[f64](m2, 1.5f64)
        var z = sb1 / math.sqrt[f64]((6.0f64 * (nf - 2.0f64)) / ((nf + 1.0f64) * (nf + 3.0f64)))
        if n < 150usize {
            let beta2 = (3.0f64 * (nf * nf + 27.0f64 * nf - 70.0f64) * (nf + 1.0f64) * (nf + 3.0f64)) / ((nf - 2.0f64) * (nf + 5.0f64) * (nf + 7.0f64) * (nf + 9.0f64))
            let w = math.sqrt[f64](0.0f64 - 1.0f64 + math.sqrt[f64](2.0f64 * beta2 - 2.0f64))
            let delta = 1.0f64 / math.sqrt[f64](math.log[f64](w))
            let alpha = math.sqrt[f64](2.0f64 / (w * w - 1.0f64))
            z = z / alpha
            z = delta * math.log[f64](z + math.sqrt[f64](z * z + 1.0f64))
        }
        var p = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false)
        if alt == 1usize { p = dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
        if alt == 2usize { p = 1.0f64 - dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
        out[0usize] = sb1
        out[1usize] = p
        out[2usize] = z
    }
    ret ok
}

// ---- the power and sample size of the t test (tTestPower, tTestN) ----

// EnvStats::tTestPower: alt 0 two-sided, 1 less, 2 greater; the exact power by the non-central t (one-sided) and the non-central F (two-sided), or the central-t approximation
fn tt_power(n1: f64, n2: f64, dos: f64, alpha: f64, two_sample: bool, alt: usize, approx: bool) -> f64 {
    var df = n1 - 1.0f64
    var ncp = math.sqrt[f64](n1) * dos
    if two_sample {
        df = n1 + n2 - 2.0f64
        ncp = math.sqrt[f64](1.0f64 / (1.0f64 / n1 + 1.0f64 / n2)) * dos
    }
    if approx {
        if alt == 1usize { ret nb.pt(nb.qt(alpha, df, true, false) - ncp, df, true, false) }
        if alt == 2usize { ret 1.0f64 - nb.pt(nb.qt(1.0f64 - alpha, df, true, false) - ncp, df, true, false) }
        ret nb.pt(nb.qt(alpha / 2.0f64, df, true, false) - ncp, df, true, false) + 1.0f64 - nb.pt(nb.qt(1.0f64 - alpha / 2.0f64, df, true, false) - ncp, df, true, false)
    }
    if alt == 1usize { ret nc.pnt(nb.qt(alpha, df, true, false), df, ncp, true, false) }
    if alt == 2usize { ret 1.0f64 - nc.pnt(nb.qt(1.0f64 - alpha, df, true, false), df, ncp, true, false) }
    ret 1.0f64 - nc.pnf(nb.qf(1.0f64 - alpha, 1.0f64, df, true, false), 1.0f64, df, ncp * ncp, true, false)
}

// EnvStats::tTestN: the smallest whole sample size (per group) whose power reaches `power`, searched on (2, n_max) as the package does by root finding and rounded up
fn tt_n(dos: f64, alpha: f64, power: f64, two_sample: bool, alt: usize, approx: bool, n_max: f64) -> f64 {
    let p2 = tt_power(2.0f64, 2.0f64, dos, alpha, two_sample, alt, approx)
    if p2 >= power { ret 2.0f64 }
    let pm = tt_power(n_max, n_max, dos, alpha, two_sample, alt, approx)
    if pm < power { ret 0.0f64 / 0.0f64 }
    var lo = 2.0f64
    var hi = n_max
    var it = 0usize
    while it < 200usize {
        let mid = 0.5f64 * (lo + hi)
        if tt_power(mid, mid, dos, alpha, two_sample, alt, approx) < power { lo = mid } else { hi = mid }
        it += 1usize
    }
    ret math.ceil[f64](0.5f64 * (lo + hi))
}

// ---- confidence interval widths for the normal mean (ciNormHalfWidth, ciNormN) ----

// ciNormHalfWidth for one sample (n2 = 0) or two samples of n1 and n2
fn ci_norm_hw(n1: f64, n2: f64, sigma: f64, conf: f64, two_sample: bool) -> f64 {
    let p = 1.0f64 - (1.0f64 - conf) / 2.0f64
    if two_sample { ret nb.qt(p, n1 + n2 - 2.0f64, true, false) * sigma * math.sqrt[f64](1.0f64 / n1 + 1.0f64 / n2) }
    ret nb.qt(p, n1 - 1.0f64, true, false) * sigma / math.sqrt[f64](n1)
}

// ciNormN: the smallest whole n (per group) whose half-width is at most hw
fn ci_norm_n(hw: f64, sigma: f64, conf: f64, two_sample: bool, n_max: f64) -> f64 {
    var tf = 1.0f64
    if two_sample { tf = 2.0f64 }
    let sf = math.sqrt[f64](tf) * sigma
    let p = 1.0f64 - (1.0f64 - conf) / 2.0f64
    let hw2 = sf / math.sqrt[f64](2.0f64) * nb.qt(p, tf, true, false)
    if hw2 <= hw { ret 2.0f64 }
    let hwm = sf / math.sqrt[f64](n_max) * nb.qt(p, tf * (n_max - 1.0f64), true, false)
    if hwm > hw { ret 0.0f64 / 0.0f64 }
    var lo = 2.0f64
    var hi = n_max
    var it = 0usize
    while it < 200usize {
        let mid = 0.5f64 * (lo + hi)
        if sf / math.sqrt[f64](mid) * nb.qt(p, tf * (mid - 1.0f64), true, false) > hw { lo = mid } else { hi = mid }
        it += 1usize
    }
    ret math.ceil[f64](0.5f64 * (lo + hi))
}

// ---- the power and sample size of the test of proportions (propTestPower, propTestN) ----

fn pn(x: f64) -> f64 { ret dist.pnorm(x, 0.0f64, 1.0f64, true, false) }

fn qn(p: f64) -> f64 { ret dist.qnorm(p, 0.0f64, 1.0f64, true, false) }

// EnvStats::propTestPower, alt 0 two-sided, 1 less, 2 greater. One sample (p1 against p2 = the null p0, n1 the size): the normal approximation with the optional
// continuity correction, or the exact binomial power (NaN when the true level exceeds alpha). Two samples: the approximation only.
fn prop_power(n1: f64, p1: f64, n2: f64, p2: f64, alpha: f64, two_sample: bool, alt: usize, approx: bool, correct: bool) -> f64 {
    var ta = alpha
    if alt == 0usize { ta = alpha / 2.0f64 }
    let q1 = 1.0f64 - p1
    let q2 = 1.0f64 - p2
    if two_sample {
        let delta = p1 - p2
        let nf = 1.0f64 / n1 + 1.0f64 / n2
        var cf = 0.0f64
        if correct { cf = 0.5f64 * nf }
        if math.abs[f64](delta) < cf { cf = 0.0f64 }
        let z = qn(1.0f64 - ta)
        let pb = (n1 * p1 + n2 * p2) / (n1 + n2)
        let qb = 1.0f64 - pb
        let se = math.sqrt[f64](p1 * q1 / n1 + p2 * q2 / n2)
        let sh = math.sqrt[f64](pb * qb * nf)
        let lo = pn((0.0f64 - z * sh - delta - cf) / se)
        let hi = 1.0f64 - pn((z * sh - delta + cf) / se)
        if alt == 1usize { ret lo }
        if alt == 2usize { ret hi }
        ret lo + hi
    }
    let p0 = p2
    let q0 = 1.0f64 - p0
    let n = n1
    if approx {
        let delta = p1 - p0
        var cf = 0.0f64
        if correct { cf = 1.0f64 / (2.0f64 * n) }
        if math.abs[f64](delta) < cf { cf = 0.0f64 }
        let z = qn(1.0f64 - ta)
        let r0 = math.sqrt[f64](p0 * q0 / (p1 * q1))
        let se = math.sqrt[f64](p1 * q1 / n)
        let lo = pn(0.0f64 - z * r0 - (delta + cf) / se)
        let hi = 1.0f64 - pn(z * r0 - (delta - cf) / se)
        if alt == 1usize { ret lo }
        if alt == 2usize { ret hi }
        ret lo + hi
    }
    let (power, tru) = prop_exact(n, p1, p0, ta, alt)
    if tru > alpha { ret 0.0f64 / 0.0f64 }
    ret power
}

// EnvStats::propTestN by the normal approximation: which 0 the size of the first (or only) sample, 1 the second sample's (ratio times it), rounded up
fn prop_n(p1: f64, p2: f64, alpha: f64, power: f64, two_sample: bool, alt: usize, ratio: f64, correct: bool, which: usize) -> f64 {
    var ta = alpha
    if alt == 0usize { ta = alpha / 2.0f64 }
    var nv = 0.0f64
    if two_sample {
        let pb = (p1 + ratio * p2) / (ratio + 1.0f64)
        let qb = 1.0f64 - pb
        let delta = math.abs[f64](p1 - p2)
        let s = qn(1.0f64 - ta) * math.sqrt[f64]((ratio + 1.0f64) * pb * qb) + qn(power) * math.sqrt[f64](ratio * p1 * (1.0f64 - p1) + p2 * (1.0f64 - p2))
        nv = s * s / (ratio * delta * delta)
        if correct {
            let u = 1.0f64 + math.sqrt[f64](1.0f64 + (2.0f64 * (ratio + 1.0f64)) / (ratio * nv * delta))
            nv = (nv / 4.0f64) * u * u
        }
        if which == 1usize { ret math.ceil[f64](ratio * nv) }
        ret math.ceil[f64](nv)
    }
    let s = qn(power) * math.sqrt[f64](p1 * (1.0f64 - p1)) - qn(ta) * math.sqrt[f64](p2 * (1.0f64 - p2))
    nv = s * s / ((p2 - p1) * (p2 - p1))
    if correct {
        let u = 1.0f64 + math.sqrt[f64](1.0f64 + 2.0f64 / (nv * math.abs[f64](p2 - p1)))
        nv = (nv / 4.0f64) * u * u
    }
    ret math.ceil[f64](nv)
}

// ---- confidence interval half widths for a binomial proportion (ciBinomHalfWidth) ----

// method 0 score (prop.test's Wilson interval, with the continuity correction), 1 exact (Clopper-Pearson, one sample), 2 adjusted Wald, 3 Wald; x1/n1 the proportion, x2/n2 the second sample
fn ci_binom_hw(n1: f64, x1: f64, n2: f64, x2: f64, conf: f64, two_sample: bool, method: usize, correct: bool) -> f64 {
    let a = 1.0f64 - conf
    let z = qn(1.0f64 - a / 2.0f64)
    let p1 = x1 / n1
    if !two_sample {
        if method == 3usize {
            var cf = 0.0f64
            if correct { cf = 0.5f64 / n1 }
            ret z * math.sqrt[f64](p1 * (1.0f64 - p1) / n1) + cf
        }
        var lo = 0.0f64
        var hi = 1.0f64
        if method == 0usize {
            var yates = 0.0f64
            if correct { yates = math.min[f64](0.5f64, math.abs[f64](x1 - n1 * 0.5f64)) }
            let z22 = z * z / (2.0f64 * n1)
            var pc = p1 + yates / n1
            if pc < 1.0f64 { hi = (pc + z22 + z * math.sqrt[f64](pc * (1.0f64 - pc) / n1 + z22 / (2.0f64 * n1))) / (1.0f64 + 2.0f64 * z22) }
            pc = p1 - yates / n1
            if pc > 0.0f64 { lo = (pc + z22 - z * math.sqrt[f64](pc * (1.0f64 - pc) / n1 + z22 / (2.0f64 * n1))) / (1.0f64 + 2.0f64 * z22) }
            lo = math.max[f64](lo, 0.0f64)
            hi = math.min[f64](hi, 1.0f64)
        } else if method == 1usize {
            if x1 > 0.0f64 { lo = nb.qbeta(a / 2.0f64, x1, n1 - x1 + 1.0f64, true, false) }
            if x1 < n1 { hi = nb.qbeta(1.0f64 - a / 2.0f64, x1 + 1.0f64, n1 - x1, true, false) }
        } else {
            let c2 = z * z
            let pa = (x1 + c2 / 2.0f64) / (n1 + c2)
            let h = z * math.sqrt[f64](pa * (1.0f64 - pa) / (n1 + c2))
            lo = math.max[f64](0.0f64, pa - h)
            hi = math.min[f64](1.0f64, pa + h)
        }
        ret (hi - lo) / 2.0f64
    }
    let p2 = x2 / n2
    if method == 0usize {
        let delta = p1 - p2
        let nf = 1.0f64 / n1 + 1.0f64 / n2
        var yates = 0.0f64
        if correct { yates = math.min[f64](0.5f64, math.abs[f64](delta) / nf) }
        let w = z * math.sqrt[f64](p1 * (1.0f64 - p1) / n1 + p2 * (1.0f64 - p2) / n2) + yates * nf
        let lo = math.max[f64](delta - w, 0.0f64 - 1.0f64)
        let hi = math.min[f64](delta + w, 1.0f64)
        ret (hi - lo) / 2.0f64
    }
    if method == 2usize {
        let c2 = z * z
        let a1 = (x1 + c2 / 4.0f64) / (n1 + c2 / 2.0f64)
        let a2 = (x2 + c2 / 4.0f64) / (n2 + c2 / 2.0f64)
        ret z * math.sqrt[f64](a1 * (1.0f64 - a1) / (n1 + c2 / 2.0f64) + a2 * (1.0f64 - a2) / (n2 + c2 / 2.0f64))
    }
    var cf = 0.0f64
    if correct { cf = 0.5f64 * (1.0f64 / n1 + 1.0f64 / n2) }
    ret z * math.sqrt[f64](p1 * (1.0f64 - p1) / n1 + p2 * (1.0f64 - p2) / n2) + cf
}

// EnvStats' rounding of a proportion to a count of n: the nearer of floor and ceiling of n p, a tie going to the one nearer 0.5
fn binom_count(n: f64, p: f64) -> f64 {
    let hi = math.ceil[f64](n * p) / n
    let lo = math.floor[f64](n * p) / n
    if hi == lo { ret math.round[f64](n * p) }
    let dh = hi - p
    let dl = p - lo
    var high = dh < dl
    if math.abs[f64](dh - dl) <= 2.220446049250313e-16f64 { high = math.abs[f64](hi - 0.5f64) <= math.abs[f64](lo - 0.5f64) }
    if high { ret math.round[f64](n * hi) }
    ret math.round[f64](n * lo)
}

// EnvStats::ciBinomN (the first sample's size): the smallest n from n_min on whose half width is within tol_hw of the request and whose rounded proportions are within tol_p of the given ones, NaN when none up to n_max
fn ci_binom_n(hw: f64, p1: f64, p2: f64, conf: f64, two_sample: bool, method: usize, ratio: f64, correct: bool, n_min: f64, n_max: f64, tol_hw: f64, tol_p: f64) -> f64 {
    var n = n_min
    while n <= n_max {
        let x1 = binom_count(n, p1)
        var h = 0.0f64
        var ok1 = math.abs[f64](p1 - x1 / n) <= tol_p
        if two_sample {
            let m2 = math.round[f64](n * ratio)
            let x2 = binom_count(m2, p2)
            ok1 = ok1 && math.abs[f64](p2 - x2 / m2) <= tol_p
            h = ci_binom_hw(n, x1, m2, x2, conf, true, method, correct)
        } else {
            h = ci_binom_hw(n, x1, n, 0.0f64, conf, false, method, correct)
        }
        if h - hw <= tol_hw && ok1 { ret n }
        n += 1.0f64
    }
    ret 0.0f64 / 0.0f64
}

// the exact binomial power and attained level of the one-sample test (ta the one-sided level, alt as in prop_power), by the package's critical values
fn prop_exact(n: f64, p1: f64, p0: f64, ta: f64, alt: usize) -> (f64, f64) {
    var power = 0.0f64
    var tru = 0.0f64
    if alt == 1usize {
        var qc = nb.qbinom(ta, n, p0, true, false)
        if nb.pbinom(qc, n, p0, true, false) > ta { qc = math.max[f64](qc - 1.0f64, 0.0f64) }
        power = nb.pbinom(qc, n, p1, true, false)
        tru = nb.pbinom(qc, n, p0, true, false)
    } else if alt == 2usize {
        var qc = nb.qbinom(1.0f64 - ta, n, p0, true, false)
        if 1.0f64 - nb.pbinom(qc, n, p0, true, false) > ta { qc = math.min[f64](qc + 1.0f64, n) }
        power = 1.0f64 - nb.pbinom(qc, n, p1, true, false)
        tru = 1.0f64 - nb.pbinom(qc, n, p0, true, false)
    } else {
        var ql = nb.qbinom(ta, n, p0, true, false)
        if nb.pbinom(ql, n, p0, true, false) > ta { ql = math.max[f64](ql - 1.0f64, 0.0f64) }
        var qu = nb.qbinom(1.0f64 - ta, n, p0, true, false)
        if 1.0f64 - nb.pbinom(qu, n, p0, true, false) > ta { qu = math.min[f64](qu + 1.0f64, n) }
        power = nb.pbinom(ql, n, p1, true, false) + 1.0f64 - nb.pbinom(qu, n, p1, true, false)
        tru = nb.pbinom(ql, n, p0, true, false) + 1.0f64 - nb.pbinom(qu, n, p0, true, false)
    }
    ret (power, tru)
}

// EnvStats::propTestN with approx = FALSE (one sample): the first n from n_min with the exact power at least `power` and the attained level within tol_alpha of alpha (the package bounds a scan by uniroot, which does not change the first such n); NaN when none by n_max
fn prop_n_exact(p1: f64, p0: f64, alpha: f64, power: f64, alt: usize, n_min: f64, n_max: f64, tol_alpha: f64) -> f64 {
    var ta = alpha
    if alt == 0usize { ta = alpha / 2.0f64 }
    var n = n_min
    while n <= n_max {
        let (pw, tru) = prop_exact(n, p1, p0, ta, alt)
        if tru <= alpha && pw >= power && math.abs[f64](tru - alpha) <= tol_alpha { ret n }
        n += 1.0f64
    }
    ret 0.0f64 / 0.0f64
}

// ---- predIntNormN: the sample size for a prediction interval half width (Bonferroni, two-sided) ----

fn pi_norm_hw(n: f64, n_mean: f64, k: f64, sigma: f64, conf: f64) -> f64 { ret pred_k(n, n_mean, k, true, conf) * sigma }

// EnvStats::predIntNormN: the root of the half width gap on (2, n_max) rounded up (2 when n = 2 is enough, NaN when n_max is not)
fn pi_norm_n(hw: f64, n_mean: f64, k: f64, sigma: f64, conf: f64, n_max: f64) -> f64 {
    if pi_norm_hw(2.0f64, n_mean, k, sigma, conf) <= hw { ret 2.0f64 }
    if pi_norm_hw(n_max, n_mean, k, sigma, conf) > hw { ret 0.0f64 / 0.0f64 }
    var lo = 2.0f64
    var hi = n_max
    var it = 0usize
    while it < 200usize {
        let mid = 0.5f64 * (lo + hi)
        if pi_norm_hw(mid, n_mean, k, sigma, conf) > hw { lo = mid } else { hi = mid }
        it += 1usize
    }
    ret math.ceil[f64](0.5f64 * (lo + hi))
}

// EnvStats::tolIntNormN (the Wald-Wolfowitz two-sided factor, the only method the package allows): `expectation` is predIntNormN at the coverage; content bisects the half width gap on (2, n_max) and rounds up
fn tol_int_norm_n(hw: f64, sigma: f64, coverage: f64, conf: f64, expectation: bool, n_max: f64) -> f64 {
    if expectation { ret pi_norm_n(hw, 1.0f64, 1.0f64, sigma, coverage, n_max) }
    if tol_k(2.0f64, coverage, conf, 1i64) * sigma <= hw { ret 2.0f64 }
    if tol_k(n_max, coverage, conf, 1i64) * sigma > hw { ret 0.0f64 / 0.0f64 }
    var lo = 2.0f64
    var hi = n_max
    var it = 0usize
    while it < 200usize {
        let mid = 0.5f64 * (lo + hi)
        if tol_k(mid, coverage, conf, 1i64) * sigma > hw { lo = mid } else { hi = mid }
        it += 1usize
    }
    ret math.ceil[f64](0.5f64 * (lo + hi))
}

// EnvStats::predIntNormTestPower for one future mean (k = 1, the exact factor). With n_mean = 1 the package answers through tTestPower (a two-sample test against one observation);
// otherwise it takes the upper tail of the non-central t at the factor for either limit, which the port repeats
fn pi_norm_power(n: f64, n_mean: f64, dos: f64, conf: f64, upper: bool) -> f64 {
    if dos == 0.0f64 { ret 1.0f64 - conf }
    if n_mean == 1.0f64 {
        var alt = 1usize
        if upper { alt = 2usize }
        ret tt_power(n, 1.0f64, dos, 1.0f64 - conf, true, alt, false)
    }
    let kf = pred_k(n, n_mean, 1.0f64, false, conf)
    let dum = math.sqrt[f64]((n_mean * n) / (n_mean + n))
    let ncp = dum * dos
    if upper { ret nc.pnt(dum * kf, n - 1.0f64, ncp, false, false) }
    ret nc.pnt(0.0f64 - dum * kf, n - 1.0f64, ncp, false, false)
}

// ---- linearTrendTestPower and linearTrendTestN ----

// EnvStats::linearTrendTestPower for the sampling times 1..n (sxx = (n - 1) var(x) = n (n^2 - 1) / 12 unless given); alt 0 two-sided, 1 less, 2 greater
fn lt_power(n: f64, sxx: f64, slope: f64, alpha: f64, alt: usize, approx: bool) -> f64 {
    let df = n - 2.0f64
    let ncp = math.sqrt[f64](sxx) * slope
    if approx {
        if alt == 1usize { ret nb.pt(nb.qt(alpha, df, true, false) - ncp, df, true, false) }
        if alt == 2usize { ret 1.0f64 - nb.pt(nb.qt(1.0f64 - alpha, df, true, false) - ncp, df, true, false) }
        ret nb.pt(nb.qt(alpha / 2.0f64, df, true, false) - ncp, df, true, false) + 1.0f64 - nb.pt(nb.qt(1.0f64 - alpha / 2.0f64, df, true, false) - ncp, df, true, false)
    }
    if alt == 1usize { ret nc.pnt(nb.qt(alpha, df, true, false), df, ncp, true, false) }
    if alt == 2usize { ret 1.0f64 - nc.pnt(nb.qt(1.0f64 - alpha, df, true, false), df, ncp, true, false) }
    ret 1.0f64 - nc.pnf(nb.qf(1.0f64 - alpha, 1.0f64, df, true, false), 1.0f64, df, ncp * ncp, true, false)
}

fn lt_power_n(n: f64, slope: f64, alpha: f64, alt: usize, approx: bool) -> f64 {
    ret lt_power(n, n * (n * n - 1.0f64) / 12.0f64, slope, alpha, alt, approx)
}

// EnvStats::linearTrendTestN: the first whole n from 3 whose power reaches the request (the package roots a step function of n and rounds up), NaN beyond n_max
fn lt_n(slope: f64, alpha: f64, power: f64, alt: usize, approx: bool, n_max: f64) -> f64 {
    var n = 3.0f64
    while n <= n_max {
        if lt_power_n(n, slope, alpha, alt, approx) >= power { ret n }
        n += 1.0f64
    }
    ret 0.0f64 / 0.0f64
}

// ---- aovPower and aovN: the one-way analysis of variance with equal or unequal group sizes ----

// EnvStats::aovPower: groups of sizes n[g] with means mu[g] and a common sigma
fn aov_power(n: []const f64, mu: []const f64, sigma: f64, alpha: f64) -> f64 {
    let g = n.len
    var tot = 0.0f64
    var sm = 0.0f64
    var i = 0usize
    while i < g {
        tot += n[i]
        sm += n[i] * mu[i]
        i += 1usize
    }
    let mbar = sm / tot
    var ss = 0.0f64
    i = 0usize
    while i < g {
        ss += n[i] * (mu[i] - mbar) * (mu[i] - mbar)
        i += 1usize
    }
    let df1 = f64(g) - 1.0f64
    let df2 = tot - f64(g)
    ret 1.0f64 - nc.pnf(nb.qf(1.0f64 - alpha, df1, df2, true, false), df1, df2, ss / (sigma * sigma), true, false)
}

// EnvStats::aovPower with the group counts of the means (ncp from `nc_n` per group) and the degrees of freedom of `df_n` per group, the split the package's aovN has when it roots over a real n
fn aov_power_split(nc_n: f64, df_n: f64, mu: []const f64, sigma: f64, alpha: f64) -> f64 {
    let g = f64(mu.len)
    var sm = 0.0f64
    var i = 0usize
    while i < mu.len {
        sm += mu[i]
        i += 1usize
    }
    let mbar = sm / g
    var ss = 0.0f64
    i = 0usize
    while i < mu.len {
        ss += nc_n * (mu[i] - mbar) * (mu[i] - mbar)
        i += 1usize
    }
    let df1 = g - 1.0f64
    let df2 = g * df_n - g
    ret 1.0f64 - nc.pnf(nb.qf(1.0f64 - alpha, df1, df2, true, false), df1, df2, ss / (sigma * sigma), true, false)
}

// EnvStats::aovN: the package roots power - aovPower over a real n, where the group counts are truncated (so the power is a step function of n that rises at each whole n).
// uniroot ends on the side of the jump with the smaller |gap|; rounding up then gives the first whole n reaching the power when that is the left side, and one more when it is the right.
fn aov_n(mu: []const f64, sigma: f64, alpha: f64, power: f64, n_max: f64) -> f64 {
    var n = 2.0f64
    if aov_power_split(2.0f64, 2.0f64, mu, sigma, alpha) >= power { ret 2.0f64 }
    n = 3.0f64
    while n <= n_max {
        let fr = aov_power_split(n, n, mu, sigma, alpha)
        if fr >= power {
            let fl = aov_power_split(n - 1.0f64, n, mu, sigma, alpha)
            if math.abs[f64](power - fl) < math.abs[f64](fr - power) { ret n }
            ret n + 1.0f64
        }
        n += 1.0f64
    }
    ret 0.0f64 / 0.0f64
}

// ---- ciNparConfLevel and ciNparN: the confidence level of a nonparametric interval for a quantile ----

// ci_type 0 two-sided, 1 lower, 2 upper; lcl is the lower rank, nu the n + 1 - upper rank (the package's n.plus.one.minus.ucl.rank)
fn ci_npar_conf(n: f64, p: f64, lcl: f64, nu: f64, ci_type: usize) -> f64 {
    let ucl = (n + 1.0f64) - nu
    if ci_type == 1usize { ret 1.0f64 - nb.pbinom(lcl - 1.0f64, n, p, true, false) }
    if ci_type == 2usize { ret nb.pbinom(ucl - 1.0f64, n, p, true, false) }
    ret nb.pbinom(ucl - 1.0f64, n, p, true, false) - nb.pbinom(lcl - 1.0f64, n, p, true, false)
}

// ciNparN: the package minimises the squared gap over a real n from `start`, rounds up and steps back one when n - 1 already reaches the level, which is the smallest whole n from the start reaching it
fn ci_npar_n(p: f64, lcl: f64, nu: f64, ci_type: usize, conf: f64, n_max: f64) -> f64 {
    var start = 2.0f64
    if ci_type == 0usize { start = math.max[f64](2.0f64, lcl + nu) }
    var n = start
    while n <= n_max {
        if ci_type != 0usize || lcl < (n + 1.0f64) - nu {
            if ci_npar_conf(n, p, lcl, nu, ci_type) >= conf { ret n }
        }
        n += 1.0f64
    }
    ret 0.0f64 / 0.0f64
}

// ---- nonparametric tolerance and prediction intervals: confidence level and size ----

// tolIntNparConfLevel: ti_type 0 two-sided, 1 lower, 2 upper; ltl and nu the lower rank and n + 1 - upper rank
fn tol_npar_conf(n: f64, cover: f64, ltl: f64, nu0: f64, ti_type: usize) -> f64 {
    var l = ltl
    var nu = nu0
    if ti_type == 2usize { l = 0.0f64 }
    if ti_type == 1usize { nu = 0.0f64 }
    let utl = n + 1.0f64 - nu
    ret 1.0f64 - nb.pbeta(cover, utl - l, nu + l, true, false)
}

// tolIntNparN: expectation is ceiling((l + nu) / (1 - coverage) - 1); content is the smallest whole n whose level reaches conf (the package rounds up an nlminb root of the squared gap)
fn tol_npar_n(cover: f64, conf: f64, expectation: bool, ltl: f64, nu0: f64, ti_type: usize, n_max: f64) -> f64 {
    var l = ltl
    var nu = nu0
    if ti_type == 2usize { l = 0.0f64 }
    if ti_type == 1usize { nu = 0.0f64 }
    if expectation { ret math.ceil[f64]((l + nu) / (1.0f64 - cover) - 1.0f64) }
    var n = 2.0f64
    while n <= n_max {
        if n + 1.0f64 - nu - l > 0.0f64 && tol_npar_conf(n, cover, l, nu, ti_type) >= conf { ret n }
        n += 1.0f64
    }
    ret 0.0f64 / 0.0f64
}

// predIntNparConfLevel for k of m future observations
fn pred_npar_conf(n: f64, k: f64, m: f64, lpl: f64, nu: f64) -> f64 {
    var s = 0.0f64
    var v = k
    while v <= m {
        let t = nb.lchoose_int(m - v + lpl + nu - 1.0f64, m - v) + nb.lchoose_int(v + n - lpl - nu, v) - nb.lchoose_int(n + m, m)
        s += math.exp[f64](t)
        v += 1.0f64
    }
    ret s
}

type PnCtx = struct { k: f64, m: f64, lpl: f64, nu: f64, conf: f64 }

fn pn_gap(c: *PnCtx, nw: f64) -> f64 { ret pred_npar_conf(math.trunc[f64](nw), c.k, c.m, c.lpl, c.nu) - c.conf }

// EnvStats::predIntNparN as the package computes it: the starting size when it already reaches conf; otherwise a closed form (one-sided, or two-sided with k = m and
// both ranks 1) with a one-step correction, or a root of the level over (n_min, n_max) by uniroot at tolerance 1 (R_zeroin2), truncated and bumped by one when the gap at the root is not positive.
// pi_type 0 two-sided, 1 lower, 2 upper
fn pred_npar_n(k: f64, m: f64, lpl: f64, nu: f64, pi_type: usize, conf: f64, n_max: f64) -> f64 {
    let n_min = math.max[f64](2.0f64, lpl + nu)
    if pred_npar_conf(n_min, k, m, lpl, nu) >= conf { ret n_min }
    if pred_npar_conf(n_max, k, m, lpl, nu) < conf { ret 0.0f64 / 0.0f64 }
    var simple = k == m
    var n = 0.0f64
    if pi_type == 0usize {
        let a = 1.0f64 - conf
        let b = conf * (1.0f64 - 2.0f64 * m) - 1.0f64
        let cc = conf * m * (1.0f64 - m)
        n = math.trunc[f64]((0.0f64 - b + math.sqrt[f64](b * b - 4.0f64 * a * cc)) / (2.0f64 * a))
        if (n * (n - 1.0f64)) / ((n + m) * (n + m - 1.0f64)) < conf { n += 1.0f64 }
        if lpl > 1.0f64 || nu > 1.0f64 { simple = false }
    } else {
        n = math.trunc[f64]((m * conf) / (1.0f64 - conf))
        if n / (n + m) < conf { n += 1.0f64 }
        if (pi_type == 2usize && nu > 1.0f64) || (pi_type == 1usize && lpl > 1.0f64) { simple = false }
    }
    if simple { ret n }
    var ctx = PnCtx{ k: k, m: m, lpl: lpl, nu: nu, conf: conf }
    let root = pwr.zeroin[PnCtx](&ctx, pn_gap, n_min, n_max, 1.0f64, 1000i64)
    if pn_gap(&ctx, root) > 0.0f64 { ret math.trunc[f64](root) }
    ret math.trunc[f64](root) + 1.0f64
}

// ---- gofTest for the exponential and gamma distributions: Chen and Balakrishnan (1995) ----

fn digamma_x(x0: f64) -> f64 {
    var x = x0
    var r = 0.0f64
    while x < 12.0f64 {
        r -= 1.0f64 / x
        x += 1.0f64
    }
    let f = 1.0f64 / (x * x)
    ret r + math.log[f64](x) - 0.5f64 / x - f * (1.0f64 / 12.0f64 - f * (1.0f64 / 120.0f64 - f * (1.0f64 / 252.0f64 - f * (1.0f64 / 240.0f64 - f * (1.0f64 / 132.0f64)))))
}

fn trigamma_x(x0: f64) -> f64 {
    var x = x0
    var r = 0.0f64
    while x < 12.0f64 {
        r += 1.0f64 / (x * x)
        x += 1.0f64
    }
    let f = 1.0f64 / (x * x)
    ret r + 1.0f64 / x + 0.5f64 * f + f / x * (1.0f64 / 6.0f64 - f * (1.0f64 / 30.0f64 - f * (1.0f64 / 42.0f64 - f * (1.0f64 / 30.0f64 - f * (5.0f64 / 66.0f64)))))
}

// the gamma maximum likelihood shape: the root of log s - digamma(s) = log(mean) - mean(log y), by Newton from the moment start
fn gamma_mle_shape(y: []const f64) -> f64 {
    let n = f64(y.len)
    var sm = 0.0f64
    var sl = 0.0f64
    var i = 0usize
    while i < y.len {
        sm += y[i]
        sl += math.log[f64](y[i])
        i += 1usize
    }
    let c = math.log[f64](sm / n) - sl / n
    var s = (3.0f64 - c + math.sqrt[f64]((c - 3.0f64) * (c - 3.0f64) + 24.0f64 * c)) / (12.0f64 * c)
    var it = 0usize
    while it < 100usize {
        let g = math.log[f64](s) - digamma_x(s) - c
        let d = 1.0f64 / s - trigamma_x(s)
        let step = g / d
        s -= step
        if s <= 0.0f64 { s = 1.0e-8f64 }
        if math.abs[f64](step) < 1.0e-14f64 * s { it = 100usize } else { it += 1usize }
    }
    ret s
}

// gofTest(distribution = "exp" or "gamma", test = sw, sf, ad, cvm or ppcc): the data go through qnorm of the fitted distribution function (the exponential rate 1 / mean, the gamma maximum
// likelihood fit) and the normal test of that is the answer; kind 0 exponential, 1 gamma; test as in gof_test
fn gof_test_cb(a: *mem.Arena, y: []const f64, test: usize, kind: usize, out: []f64) -> err {
    let n = y.len
    let (z, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret mem.Full }
    var sm = 0.0f64
    var i = 0usize
    while i < n {
        sm += y[i]
        i += 1usize
    }
    let mean = sm / f64(n)
    var shape = 1.0f64
    if kind == 1usize { shape = gamma_mle_shape(y) }
    let scale = mean / shape
    i = 0usize
    while i < n {
        z[i] = dist.qnorm(nm.pgamma(y[i], shape, scale, true, false), 0.0f64, 1.0f64, true, false)
        i += 1usize
    }
    ret gof_test(a, z, test, false, 0usize, out)
}

// ---- kendallSeasonalTrendTest modified for serial correlation (independent.obs = FALSE) ----

fn mid_ranks(v: []const f64, out: []f64) {
    let n = v.len
    var i = 0usize
    while i < n {
        var less = 0usize
        var eq = 0usize
        var j = 0usize
        while j < n {
            if v[j] < v[i] { less += 1usize }
            if v[j] == v[i] { eq += 1usize }
            j += 1usize
        }
        out[i] = f64(less) + (f64(eq) + 1.0f64) / 2.0f64
        i += 1usize
    }
}

fn sign_f(x: f64) -> f64 {
    if x > 0.0f64 { ret 1.0f64 }
    if x < 0.0f64 { ret 0.0f64 - 1.0f64 }
    ret 0.0f64
}

// every season observed once in every year (the package's requirement); the rows of a season pair across seasons by their order of appearance. Same `out` layout as kendall_seasonal, with the chi-square, z, p, interval
// and var.S replaced by the serial-correlation forms (out[10] is the total of the variance-covariance matrix of the seasonal S)
fn kendall_seasonal_sc(a: *mem.Arena, y: []const f64, season: []const f64, year: []const f64, alt: usize, correct: bool, conf: f64, out: []f64) -> err {
    let n = y.len
    let e0 = kendall_seasonal(a, y, season, year, alt, correct, conf, out)
    if e0 != ok { ret e0 }
    let ns = usize(out[12usize])
    let ny = n / ns
    let (ids, e1) = mem.alloc[f64](a, ns)
    let (rk, e2) = mem.alloc[f64](a, n)
    let (tau, e3) = mem.alloc[f64](a, ns)
    let (vs, e4) = mem.alloc[f64](a, ns)
    let (cv, e5) = mem.alloc[f64](a, ns * ns)
    let (sy, e6) = mem.alloc[f64](a, ny)
    let (sx, e7) = mem.alloc[f64](a, ny)
    let (ko, e8) = mem.alloc[f64](a, 10usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret mem.Full }
    var cnt = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < cnt {
            if ids[j] == season[i] { seen = true }
            j += 1usize
        }
        if !seen {
            ids[cnt] = season[i]
            cnt += 1usize
        }
        i += 1usize
    }
    sort_f(ids[0usize..ns])
    var k = 0usize
    while k < ns {
        var m = 0usize
        i = 0usize
        while i < n {
            if season[i] == ids[k] {
                sy[m] = y[i]
                sx[m] = year[i]
                m += 1usize
            }
            i += 1usize
        }
        mid_ranks(sy[0usize..ny], rk[k * ny..k * ny + ny])
        let ek = kendall_trend(a, sy[0usize..ny], sx[0usize..ny], 0usize, true, 0.95f64, ko)
        if ek != ok { ret ek }
        tau[k] = ko[4usize]
        vs[k] = ko[1usize]
        cv[k * ns + k] = ko[1usize]
        k += 1usize
    }
    let nyf = f64(ny)
    var si = 1usize
    while si < ns {
        var sj = 0usize
        while sj < si {
            var kk = 0.0f64
            var p1 = 0usize
            while p1 < ny {
                var p2 = p1 + 1usize
                while p2 < ny {
                    kk += sign_f(rk[si * ny + p2] - rk[si * ny + p1]) * sign_f(rk[sj * ny + p2] - rk[sj * ny + p1])
                    p2 += 1usize
                }
                p1 += 1usize
            }
            var dot = 0.0f64
            p1 = 0usize
            while p1 < ny {
                dot += rk[si * ny + p1] * rk[sj * ny + p1]
                p1 += 1usize
            }
            let rv = 4.0f64 * dot - nyf * (nyf + 1.0f64) * (nyf + 1.0f64)
            let c = (kk + rv) / 3.0f64
            cv[si * ns + sj] = c
            cv[sj * ns + si] = c
            sj += 1usize
        }
        si += 1usize
    }
    var vtot = 0.0f64
    var q = 0usize
    while q < ns * ns {
        vtot += cv[q]
        q += 1usize
    }
    // chi-square: v = C tau, W = C (M V M) C' with C = [1, -I], M = diag(2 / (n (n - 1)))
    let g = ns - 1usize
    let (vec, e9) = mem.alloc[f64](a, g)
    let (wm, e10) = mem.alloc[f64](a, g * g)
    let (mv, e11) = mem.alloc[f64](a, ns * ns)
    if e9 != ok || e10 != ok || e11 != ok { ret mem.Full }
    let mf = 2.0f64 / (nyf * (nyf - 1.0f64))
    q = 0usize
    while q < ns * ns {
        mv[q] = mf * mf * cv[q]
        q += 1usize
    }
    var r = 0usize
    while r < g {
        vec[r] = tau[0usize] - tau[r + 1usize]
        var c2 = 0usize
        while c2 < g {
            wm[r * g + c2] = mv[0usize] - mv[0usize * ns + c2 + 1usize] - mv[(r + 1usize) * ns + 0usize] + mv[(r + 1usize) * ns + c2 + 1usize]
            c2 += 1usize
        }
        r += 1usize
    }
    // solve W x = vec by Gaussian elimination with partial pivoting
    var col = 0usize
    while col < g {
        var piv = col
        var rr = col + 1usize
        while rr < g {
            if math.abs[f64](wm[rr * g + col]) > math.abs[f64](wm[piv * g + col]) { piv = rr }
            rr += 1usize
        }
        if piv != col {
            var cc = 0usize
            while cc < g {
                let t = wm[col * g + cc]
                wm[col * g + cc] = wm[piv * g + cc]
                wm[piv * g + cc] = t
                cc += 1usize
            }
            let tv = vec[col]
            vec[col] = vec[piv]
            vec[piv] = tv
        }
        rr = col + 1usize
        while rr < g {
            let f = wm[rr * g + col] / wm[col * g + col]
            var cc = col
            while cc < g {
                wm[rr * g + cc] -= f * wm[col * g + cc]
                cc += 1usize
            }
            vec[rr] -= f * vec[col]
            rr += 1usize
        }
        col += 1usize
    }
    var xs = 0.0f64
    // chisq = v' W^-1 v: back substitute on the eliminated system for x = W^-1 v, then dot with the original v
    let (v0, e12) = mem.alloc[f64](a, g)
    let (xv, e13) = mem.alloc[f64](a, g)
    if e12 != ok || e13 != ok { ret mem.Full }
    r = 0usize
    while r < g {
        v0[r] = tau[0usize] - tau[r + 1usize]
        r += 1usize
    }
    var bi = g
    while bi > 0usize {
        let rowi = bi - 1usize
        var s = vec[rowi]
        var cc = rowi + 1usize
        while cc < g {
            s -= wm[rowi * g + cc] * xv[cc]
            cc += 1usize
        }
        xv[rowi] = s / wm[rowi * g + rowi]
        bi -= 1usize
    }
    r = 0usize
    while r < g {
        xs += v0[r] * xv[r]
        r += 1usize
    }
    out[0usize] = xs
    out[1usize] = 1.0f64 - nm.pchisq(xs, f64(g), true, false)
    let stot = out[9usize]
    var z = stot / math.sqrt[f64](vtot)
    if correct { z = (stot - sign_f(stot)) / math.sqrt[f64](vtot) }
    var p = 2.0f64 * dist.pnorm(0.0f64 - math.abs[f64](z), 0.0f64, 1.0f64, true, false)
    if alt == 1usize { p = 1.0f64 - dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
    if alt == 2usize { p = dist.pnorm(z, 0.0f64, 1.0f64, true, false) }
    out[2usize] = z
    out[3usize] = p
    out[10usize] = vtot
    ret ok
}

// ---- gofGroupTest: a normality test per group, the group p-values combined by the Wilk-Shapiro test of uniformity ----

// y has n values, grp their group ids (the groups taken in increasing id order, as split does); test as in gof_test; method 0 normal scores (sum of qnorm(p) over sqrt(G), p = pnorm of it), 1 chi-square scores
// (-2 sum log p against chi-square with 2 G degrees of freedom, upper tail); out[0] the group statistic, out[1] its p-value, out[2] the number of groups
fn gof_group(a: *mem.Arena, y: []const f64, grp: []const f64, test: usize, method: usize, out: []f64) -> err {
    let n = y.len
    let (ids, e1) = mem.alloc[f64](a, n)
    let (sub, e2) = mem.alloc[f64](a, n)
    let (go, e3) = mem.alloc[f64](a, 3usize)
    if e1 != ok || e2 != ok || e3 != ok { ret mem.Full }
    var ng = 0usize
    var i = 0usize
    while i < n {
        var seen = false
        var j = 0usize
        while j < ng {
            if ids[j] == grp[i] { seen = true }
            j += 1usize
        }
        if !seen {
            ids[ng] = grp[i]
            ng += 1usize
        }
        i += 1usize
    }
    sort_f(ids[0usize..ng])
    var sumq = 0.0f64
    var sumc = 0.0f64
    var g = 0usize
    while g < ng {
        var m = 0usize
        i = 0usize
        while i < n {
            if grp[i] == ids[g] {
                sub[m] = y[i]
                m += 1usize
            }
            i += 1usize
        }
        let ge = gof_test(a, sub[0usize..m], test, false, 0usize, go)
        if ge != ok { ret ge }
        sumq += dist.qnorm(go[1usize], 0.0f64, 1.0f64, true, false)
        sumc += 0.0f64 - 2.0f64 * math.log[f64](go[1usize])
        g += 1usize
    }
    let gf = f64(ng)
    if method == 0usize {
        let st = sumq / math.sqrt[f64](gf)
        out[0usize] = st
        out[1usize] = dist.pnorm(st, 0.0f64, 1.0f64, true, false)
    } else {
        out[0usize] = sumc
        out[1usize] = nm.pchisq(sumc, 2.0f64 * gf, false, false)
    }
    out[2usize] = gf
    ret ok
}

// enorm(x, ci = TRUE): the mean and standard deviation and the confidence limits of the mean (param 0, t interval) or the variance (param 1, chi-square interval); ci_type 0 two-sided,
// 1 lower (UCL = Inf), 2 upper (LCL = -Inf, or 0 for the variance); out = (mean, sd, LCL, UCL)
fn e_norm(x: []const f64, conf: f64, param: usize, ci_type: usize, out: []f64) {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / n
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        ss += (x[i] - m) * (x[i] - m)
        i += 1usize
    }
    let v = ss / (n - 1.0f64)
    let sd = math.sqrt[f64](v)
    out[0usize] = m
    out[1usize] = sd
    let alpha = 1.0f64 - conf
    var lcl = 0.0f64
    var ucl = 0.0f64
    if param == 0usize {
        let se = sd / math.sqrt[f64](n)
        if ci_type == 0usize {
            let t = nb.qt(1.0f64 - alpha / 2.0f64, n - 1.0f64, true, false)
            lcl = m - t * se
            ucl = m + t * se
        } else if ci_type == 1usize {
            lcl = m - nb.qt(1.0f64 - alpha, n - 1.0f64, true, false) * se
            ucl = math.inf64()
        } else {
            lcl = 0.0f64 - math.inf64()
            ucl = m + nb.qt(1.0f64 - alpha, n - 1.0f64, true, false) * se
        }
    } else {
        if ci_type == 0usize {
            lcl = (n - 1.0f64) * v / nm.qchisq(1.0f64 - alpha / 2.0f64, n - 1.0f64, true, false)
            ucl = (n - 1.0f64) * v / nm.qchisq(alpha / 2.0f64, n - 1.0f64, true, false)
        } else if ci_type == 1usize {
            lcl = (n - 1.0f64) * v / nm.qchisq(1.0f64 - alpha, n - 1.0f64, true, false)
            ucl = math.inf64()
        } else {
            lcl = 0.0f64
            ucl = (n - 1.0f64) * v / nm.qchisq(alpha, n - 1.0f64, true, false)
        }
    }
    out[2usize] = lcl
    out[3usize] = ucl
}

// eexp(x, ci = TRUE): the rate 1 / mean(x) and its exact chi-square limits qchisq(., 2 n) / (2 n mean); ci_type as in e_norm; out = (rate, LCL, UCL)
fn e_exp(x: []const f64, conf: f64, ci_type: usize, out: []f64) {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += x[i]
        i += 1usize
    }
    m = m / n
    out[0usize] = 1.0f64 / m
    let alpha = 1.0f64 - conf
    let d = 2.0f64 * n * m
    if ci_type == 0usize {
        out[1usize] = nm.qchisq(alpha / 2.0f64, 2.0f64 * n, true, false) / d
        out[2usize] = nm.qchisq(1.0f64 - alpha / 2.0f64, 2.0f64 * n, true, false) / d
    } else if ci_type == 1usize {
        out[1usize] = nm.qchisq(alpha, 2.0f64 * n, true, false) / d
        out[2usize] = math.inf64()
    } else {
        out[1usize] = 0.0f64
        out[2usize] = nm.qchisq(1.0f64 - alpha, 2.0f64 * n, true, false) / d
    }
}

// epois(x, ci = TRUE): lambda = mean(x) and the exact limits qchisq(alpha / 2, 2 sum) / (2 n) and qchisq(1 - alpha / 2, 2 (sum + 1)) / (2 n); ci_type as in e_norm; out = (lambda, LCL, UCL)
fn e_pois(x: []const f64, conf: f64, ci_type: usize, out: []f64) {
    let n = f64(x.len)
    var s = 0.0f64
    var i = 0usize
    while i < x.len {
        s += x[i]
        i += 1usize
    }
    out[0usize] = s / n
    let alpha = 1.0f64 - conf
    if ci_type == 0usize {
        out[1usize] = nm.qchisq(alpha / 2.0f64, 2.0f64 * s, true, false) / (2.0f64 * n)
        out[2usize] = nm.qchisq(1.0f64 - alpha / 2.0f64, 2.0f64 * (s + 1.0f64), true, false) / (2.0f64 * n)
    } else if ci_type == 1usize {
        out[1usize] = nm.qchisq(alpha, 2.0f64 * s, true, false) / (2.0f64 * n)
        out[2usize] = math.inf64()
    } else {
        out[1usize] = 0.0f64
        out[2usize] = nm.qchisq(1.0f64 - alpha, 2.0f64 * (s + 1.0f64), true, false) / (2.0f64 * n)
    }
}

// egamma(x, method): shape and scale by maximum likelihood (0), the bias-corrected maximum likelihood (1: shape (n - 3) shape / n + 2 / (3 n), scale mean / shape) or the method of
// moments (2, with the divisor n variance); out = (shape, scale)
fn e_gamma(y: []const f64, method: usize, out: []f64) {
    let n = f64(y.len)
    var m = 0.0f64
    var i = 0usize
    while i < y.len {
        m += y[i]
        i += 1usize
    }
    m = m / n
    if method == 2usize {
        var v = 0.0f64
        i = 0usize
        while i < y.len {
            v += (y[i] - m) * (y[i] - m)
            i += 1usize
        }
        v = v / n
        out[0usize] = m * m / v
        out[1usize] = v / m
        ret
    }
    var shape = gamma_mle_shape(y)
    if method == 1usize { shape = (n - 3.0f64) / n * shape + 2.0f64 / (3.0f64 * n) }
    out[0usize] = shape
    out[1usize] = m / shape
}

// elnorm(x, method): meanlog and sdlog of log(x) by the minimum variance unbiased estimator (0, divisor n - 1) or maximum likelihood (1, divisor n); out = (meanlog, sdlog)
fn e_lnorm(x: []const f64, method: usize, out: []f64) {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        m += math.log[f64](x[i])
        i += 1usize
    }
    m = m / n
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        let d = math.log[f64](x[i]) - m
        ss += d * d
        i += 1usize
    }
    var den = n - 1.0f64
    if method == 1usize { den = n }
    out[0usize] = m
    out[1usize] = math.sqrt[f64](ss / den)
}

// eweibull(x, method = "mle"): the shape k solves sum(x^k log x) / sum(x^k) - 1 / k = mean(log x) (Newton from the moment start), scale (sum(x^k) / n)^(1 / k); out = (shape, scale)
fn e_weibull(x: []const f64, out: []f64) {
    let n = f64(x.len)
    var ml = 0.0f64
    var i = 0usize
    while i < x.len {
        ml += math.log[f64](x[i])
        i += 1usize
    }
    ml = ml / n
    var k = 1.0f64
    var it = 0usize
    while it < 200usize {
        var s0 = 0.0f64
        var s1 = 0.0f64
        var s2 = 0.0f64
        i = 0usize
        while i < x.len {
            let lx = math.log[f64](x[i])
            let xk = math.exp[f64](k * lx)
            s0 += xk
            s1 += xk * lx
            s2 += xk * lx * lx
            i += 1usize
        }
        let f = s1 / s0 - 1.0f64 / k - ml
        let df = (s2 * s0 - s1 * s1) / (s0 * s0) + 1.0f64 / (k * k)
        var step = f / df
        if k - step <= 0.0f64 { step = k / 2.0f64 }
        k -= step
        if math.abs[f64](step) < 1.0e-14f64 * k { it = 200usize } else { it += 1usize }
    }
    var s0 = 0.0f64
    i = 0usize
    while i < x.len {
        s0 += math.exp[f64](k * math.log[f64](x[i]))
        i += 1usize
    }
    out[0usize] = k
    out[1usize] = math.exp[f64](math.log[f64](s0 / n) / k)
}

// eqnorm(x, p, ci = TRUE) (lognormal = false) or eqlnorm (true, on log(x), the results exponentiated): the mvue quantile mean + qnorm(p) sd and its exact limits mean + sd qnt(., n - 1, qnorm(p) sqrt(n)) / sqrt(n);
// ci_type 0 two-sided, 1 lower (UCL Inf), 2 upper (LCL -Inf); out = (quantile, LCL, UCL)
fn e_qnorm(x: []const f64, p: f64, conf: f64, ci_type: usize, lognormal: bool, out: []f64) {
    let n = f64(x.len)
    var m = 0.0f64
    var i = 0usize
    while i < x.len {
        if lognormal { m += math.log[f64](x[i]) } else { m += x[i] }
        i += 1usize
    }
    m = m / n
    var ss = 0.0f64
    i = 0usize
    while i < x.len {
        var v = x[i]
        if lognormal { v = math.log[f64](x[i]) }
        ss += (v - m) * (v - m)
        i += 1usize
    }
    let s = math.sqrt[f64](ss / (n - 1.0f64))
    let z = dist.qnorm(p, 0.0f64, 1.0f64, true, false)
    let alpha = 1.0f64 - conf
    let rn = math.sqrt[f64](n)
    var q = m + z * s
    var lcl = 0.0f64
    var ucl = 0.0f64
    if ci_type == 0usize {
        lcl = m + s * qnt(alpha / 2.0f64, n - 1.0f64, z * rn) / rn
        ucl = m + s * qnt(1.0f64 - alpha / 2.0f64, n - 1.0f64, z * rn) / rn
    } else if ci_type == 1usize {
        lcl = m + s * qnt(alpha, n - 1.0f64, z * rn) / rn
        ucl = math.inf64()
    } else {
        lcl = 0.0f64 - math.inf64()
        ucl = m + s * qnt(1.0f64 - alpha, n - 1.0f64, z * rn) / rn
    }
    if lognormal {
        q = math.exp[f64](q)
        lcl = math.exp[f64](lcl)
        ucl = math.exp[f64](ucl)
    }
    out[0usize] = q
    out[1usize] = lcl
    out[2usize] = ucl
}
