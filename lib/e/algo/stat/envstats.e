// R EnvStats: Rosner's generalised ESD test for outliers (rosnerTest and its critical values), the normal tolerance
// interval factors (tolIntNormK) for the one-sided content, the expectation and the Wald-Wolfowitz two-sided content
// types, and the normal prediction interval factor (predIntNormK) for one future observation or a Bonferroni set.
// The non-central t quantile is R's own bisection (qnt.c).
//
// Not here: the exact two-sided tolerance factor (a nested integral and optimiser), the exact multiple-prediction
// factor (Dunnett's multivariate t), the other estimation, interval and testing families of the package.

use e.algo.stat.nortest as nt
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
