// R tseries: `bds.test` (the Brock-Dechert-Scheinkman statistic for embedding dimensions 2 to m and each eps, the counting
// of LeBaron's bit grid done as the pair counts it equals) and `tsbootstrap` (the stationary and the block resampling of
// boot.c on R's stream, with the bootstrap of a statistic of the series: replicates, bias and standard error).
//
// Not here: the other tseries tests and portfolio.optim.

use e.algo.linalg.decomp as decomp
use e.algo.rand.r as rng
use e.algo.stat.olsfit as ols
use e.math
use e.math.dist as dist
use e.mem

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn ipow(x: f64, m: usize) -> f64 {
    var y = 1.0f64
    var j = 0usize
    while j < m {
        y *= x
        j += 1usize
    }
    ret y
}

// the normalised statistic of cstat(c, cm, k, m, n)
fn cstat(c: f64, cm: f64, k: f64, m: usize, n: usize) -> f64 {
    var sigma = 0.0f64
    var j = 1usize
    while j + 1usize <= m {
        sigma += 2.0f64 * ipow(k, m - j) * ipow(c, 2usize * j)
        j += 1usize
    }
    let mm = f64(m)
    sigma += ipow(k, m) + (mm - 1.0f64) * (mm - 1.0f64) * ipow(c, 2usize * m) - mm * mm * k * ipow(c, 2usize * m - 2usize)
    sigma *= 4.0f64
    let std = math.sqrt[f64](sigma / f64(n))
    ret (cm - ipow(c, m)) / std
}

// bds.test(x, m, eps): stat[(d - 2)] for d = 2 .. m, one eps
fn bds_stat(a: *mem.Arena, x: []const f64, m: usize, eps: f64, out: []f64) -> err {
    let n = x.len
    let nobs = n - (m - 1usize)
    let nd = f64(nobs)
    // the close pairs among the first nobs points in the first dimension: d_i the number of neighbours
    let (dcount, e1) = mem.alloc[f64](a, nobs)
    if e1 != ok { ret e1 }
    var sum_d = 0.0f64
    var sum_d2 = 0.0f64
    var i = 0usize
    while i < nobs {
        var cnt = 0.0f64
        var j = 0usize
        while j < nobs {
            if j != i {
                var df = x[i] - x[j]
                if df < 0.0f64 { df = 0.0f64 - df }
                if df <= eps { cnt += 1.0f64 }
            }
            j += 1usize
        }
        sum_d += cnt
        sum_d2 += cnt * cnt
        i += 1usize
    }
    let k = (sum_d2 - sum_d) / (nd * (nd - 1.0f64) * (nd - 2.0f64))
    let c1 = sum_d / (nd * (nd - 1.0f64))
    var d = 2usize
    while d <= m {
        var count = 0.0f64
        i = 0usize
        while i < nobs {
            var j = i + 1usize
            while j < nobs {
                var close = true
                var t = 0usize
                while t < d && close {
                    var df = x[i + t] - x[j + t]
                    if df < 0.0f64 { df = 0.0f64 - df }
                    if df > eps { close = false }
                    t += 1usize
                }
                if close { count += 1.0f64 }
                j += 1usize
            }
            i += 1usize
        }
        let cd = 2.0f64 * count / (nd * (nd - 1.0f64))
        out[d - 2usize] = cstat(c1, cd, k, d, nobs)
        d += 1usize
    }
    ret ok
}

fn wrap(i: i64, n: i64) -> i64 {
    if i < 1i64 { ret i % n + n }
    if i > n { ret (i - 1i64) % n + 1i64 }
    ret i
}

fn disuni(g: *rng.Rng, n: i64) -> i64 { ret i64(rng.unif(g) * f64(n) + 1.0f64) }

fn geodev(g: *rng.Rng, p: f64) -> i64 {
    let b = (0.0f64 - 1.0f64) / math.log[f64](1.0f64 - p)
    let y = rng.exp_unit(g)
    ret i64(b * y)
}

// boot.sample(x, b, type): type 0 the stationary bootstrap with the geometric parameter b, 1 the blockwise bootstrap of length b
fn boot_sample(g: *rng.Rng, x: []const f64, b: f64, qtype: u8, out: []f64) {
    let n = i64(x.len)
    var i = 1i64
    if qtype == 0u8 {
        while i <= n {
            let bi = disuni(g, n)
            let l = geodev(g, b)
            var j = 0i64
            while j < l && i <= n {
                out[usize(i - 1i64)] = x[usize(wrap(bi + j, n) - 1i64)]
                i += 1i64
                j += 1i64
            }
        }
    } else {
        let l = i64(b)
        while i <= n {
            let bi = disuni(g, n - l + 1i64)
            var j = 0i64
            while j < l && i <= n {
                out[usize(i - 1i64)] = x[usize(bi + j - 1i64)]
                i += 1i64
                j += 1i64
            }
        }
    }
}

// ---- the neural network tests: terasvirta.test and white.test (x is n by nin column-major, y has n values)

fn scaled(a: *mem.Arena, v: []const f64, n: usize, cols: usize) -> ([]f64, err) {
    let (o, e) = mem.alloc[f64](a, n * cols)
    if e != ok { ret (o, e) }
    var c = 0usize
    while c < cols {
        var m = 0.0f64
        var i = 0usize
        while i < n {
            m += v[c * n + i]
            i += 1usize
        }
        m = m / f64(n)
        var s = 0.0f64
        i = 0usize
        while i < n {
            s += (v[c * n + i] - m) * (v[c * n + i] - m)
            i += 1usize
        }
        let sd = math.sqrt[f64](s / f64(n - 1usize))
        i = 0usize
        while i < n {
            o[c * n + i] = (v[c * n + i] - m) / sd
            i += 1usize
        }
        c += 1usize
    }
    ret (o, ok)
}

// regress u on the columns of cols (n by p, plus an intercept) and answer the residual sum of squares
fn rss_of(a: *mem.Arena, cols: []const f64, n: usize, p: usize, u: []const f64) -> (f64, err) {
    let (d, e) = mem.alloc[f64](a, n * (p + 1usize))
    if e != ok { ret (0.0f64, e) }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * p {
        d[n + i] = cols[i]
        i += 1usize
    }
    let (o, oe) = ols.fit(a, d, n, p + 1usize, u)
    if oe != ok { ret (0.0f64, oe) }
    ret (o.rss, ok)
}

// answers (statistic, df1, df2) for type Chisq (df2 is 0) or F
fn nn_finish(ssr0: f64, ssr: f64, n: usize, nin: usize, mdf: usize, ftype: bool) -> (f64, f64, f64) {
    let t = f64(n)
    if !ftype { ret (t * math.log[f64](ssr0 / ssr), f64(mdf), 0.0f64) }
    let d2 = t - f64(mdf) - f64(nin)
    ret (((ssr0 - ssr) / f64(mdf)) / (ssr / d2), f64(mdf), d2)
}

// terasvirta.test(x, y, type, scale)
fn terasvirta(a: *mem.Arena, x0: []const f64, y0: []const f64, n: usize, nin: usize, ftype: bool, scale: bool) -> (f64, f64, f64, err) {
    var x = x0
    var y = y0
    if scale {
        let (xs, e1) = scaled(a, x0, n, nin)
        let (ys, e2) = scaled(a, y0, n, 1usize)
        if e1 != ok { ret (0.0f64, 0.0f64, 0.0f64, e1) }
        if e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e2) }
        x = xs
        y = ys
    }
    let (r0, re0) = olsres(a, x, n, nin, y)
    if re0 != ok { ret (0.0f64, 0.0f64, 0.0f64, re0) }
    let ssr0 = r0.rss
    // the squares and the cubes of the regressors
    var m = 0usize
    var i = 0usize
    while i < nin {
        var j = i
        while j < nin {
            m += 1usize
            var k = j
            while k < nin {
                m += 1usize
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let p = nin + m
    let (cols, ce) = mem.alloc[f64](a, n * p)
    if ce != ok { ret (0.0f64, 0.0f64, 0.0f64, ce) }
    var c = 0usize
    while c < nin * n {
        cols[c] = x[c]
        c += 1usize
    }
    var at = nin
    i = 0usize
    while i < nin {
        var j = i
        while j < nin {
            var t = 0usize
            while t < n {
                cols[at * n + t] = x[i * n + t] * x[j * n + t]
                t += 1usize
            }
            at += 1usize
            j += 1usize
        }
        i += 1usize
    }
    i = 0usize
    while i < nin {
        var j = i
        while j < nin {
            var k = j
            while k < nin {
                var t = 0usize
                while t < n {
                    cols[at * n + t] = x[i * n + t] * x[j * n + t] * x[k * n + t]
                    t += 1usize
                }
                at += 1usize
                k += 1usize
            }
            j += 1usize
        }
        i += 1usize
    }
    let (ssr, e2) = rss_of(a, cols, n, p, r0.resid)
    if e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e2) }
    // m counts the squares and the cubes: nin (nin + 1) / 2 + nin (nin + 1) (nin + 2) / 6
    let (st, d1, d2) = nn_finish(ssr0, ssr, n, nin, nin * (nin + 1usize) / 2usize + nin * (nin + 1usize) * (nin + 2usize) / 6usize, ftype)
    ret (st, d1, d2, ok)
}

fn olsres(a: *mem.Arena, x: []const f64, n: usize, nin: usize, y: []const f64) -> (ols.Ols, err) {
    let (d, e) = mem.alloc[f64](a, n * (nin + 1usize))
    var none: ols.Ols = zero
    if e != ok { ret (none, e) }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < n * nin {
        d[n + i] = x[i]
        i += 1usize
    }
    let (o, oe) = ols.fit(a, d, n, nin + 1usize, y)
    ret (o, oe)
}

// white.test(x, y, qstar, q, range, type, scale): the random weights are runif on R's stream
fn white(a: *mem.Arena, g: *rng.Rng, x0: []const f64, y0: []const f64, n: usize, nin: usize, qstar: usize, q: usize, range: f64, ftype: bool, scale: bool) -> (f64, f64, f64, err) {
    var x = x0
    var y = y0
    if scale {
        let (xs, e1) = scaled(a, x0, n, nin)
        let (ys, e2) = scaled(a, y0, n, 1usize)
        if e1 != ok { ret (0.0f64, 0.0f64, 0.0f64, e1) }
        if e2 != ok { ret (0.0f64, 0.0f64, 0.0f64, e2) }
        x = xs
        y = ys
    }
    let (r0, re0) = olsres(a, x, n, nin, y)
    if re0 != ok { ret (0.0f64, 0.0f64, 0.0f64, re0) }
    let ssr0 = r0.rss
    let mx = range / 2.0f64
    let (gam, ge) = mem.alloc[f64](a, (nin + 1usize) * q)
    if ge != ok { ret (0.0f64, 0.0f64, 0.0f64, ge) }
    var i = 0usize
    while i < (nin + 1usize) * q {
        gam[i] = 0.0f64 - mx + (2.0f64 * mx) * rng.unif(g)
        i += 1usize
    }
    let (ph, pe) = mem.alloc[f64](a, n * q)
    if pe != ok { ret (0.0f64, 0.0f64, 0.0f64, pe) }
    var c = 0usize
    while c < q {
        i = 0usize
        while i < n {
            var s = gam[c * (nin + 1usize)]
            var j = 0usize
            while j < nin {
                s += x[j * n + i] * gam[c * (nin + 1usize) + j + 1usize]
                j += 1usize
            }
            ph[c * n + i] = 1.0f64 / (1.0f64 + math.exp[f64](0.0f64 - s))
            i += 1usize
        }
        c += 1usize
    }
    // prcomp(phantom, scale. = TRUE): the centred, unit-variance columns and their right singular vectors
    let (z, ze) = scaled(a, ph, n, q)
    if ze != ok { ret (0.0f64, 0.0f64, 0.0f64, ze) }
    let (sv, se) = decomp.svd(a, z, n, q)
    if se != ok { ret (0.0f64, 0.0f64, 0.0f64, se) }
    let (pcs, pce) = mem.alloc[f64](a, n * qstar)
    if pce != ok { ret (0.0f64, 0.0f64, 0.0f64, pce) }
    var j = 0usize
    while j < qstar {
        i = 0usize
        while i < n {
            pcs[j * n + i] = sv.u[(j + 1usize) * n + i] * sv.d[j + 1usize]
            i += 1usize
        }
        j += 1usize
    }
    // u ~ x + phantomstar
    let p = nin + qstar
    let (cols, cke) = mem.alloc[f64](a, n * p)
    if cke != ok { ret (0.0f64, 0.0f64, 0.0f64, cke) }
    i = 0usize
    while i < n * nin {
        cols[i] = x[i]
        i += 1usize
    }
    i = 0usize
    while i < n * qstar {
        cols[n * nin + i] = pcs[i]
        i += 1usize
    }
    let (ssr, e3) = rss_of(a, cols, n, p, r0.resid)
    if e3 != ok { ret (0.0f64, 0.0f64, 0.0f64, e3) }
    let t = f64(n)
    if !ftype { ret (t * math.log[f64](ssr0 / ssr), f64(qstar), 0.0f64, ok) }
    let d2 = t - f64(qstar) - f64(nin)
    ret (((ssr0 - ssr) / f64(qstar)) / (ssr / d2), f64(qstar), d2, ok)
}
