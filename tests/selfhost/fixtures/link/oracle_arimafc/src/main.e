// e.algo.stat.arimafit and arimafc against forecast::Arima with seasonal terms. The layout is at the top of
// scripts/r_oracle/groups/arimafc.R; consecutive cases of one series and model share a fit.

use e.algo.stat.arimafit as af
use e.algo.stat.arimafc as fc
use e.algo.stat.fcast as fcast
use e.io
use e.mem
use e.math
use e.math.dist as dist
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct { key: []f64, fit: af.ArFit, mean: []f64, se: []f64, fitted: []f64, lam: f64, s2: f64, have: bool, good: bool }

fn same_key(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn build(a: *mem.Arena, x: []const f64, cache: *Cache) {
    cache.good = false
    let n = usize(x[10usize])
    let lam = x[9usize]
    let kind = usize(x[7usize])
    let (yt, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret }
    var i = 0usize
    while i < n {
        yt[i] = x[11usize + i]
        if lam != 5.0f64 { yt[i] = fcast.box_cox(x[11usize + i], lam) }
        i += 1usize
    }
    let f = af.arima_fit_s(a, yt, usize(x[0usize]), usize(x[1usize]), usize(x[2usize]), usize(x[3usize]), usize(x[4usize]), usize(x[5usize]), usize(x[6usize]), kind, 0.0f64 / 0.0f64, usize(x[8usize]))
    cache.fit = f
    cache.lam = lam
    cache.s2 = fc.arima_sigma2(f.resid, f.nused, f.nfree)
    if !f.good { ret }
    let (mean, e1) = mem.alloc[f64](a, 6usize)
    let (se, e2) = mem.alloc[f64](a, 6usize)
    let (fd, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret }
    cache.mean = mean
    cache.se = se
    cache.fitted = fd
    let beta = f.coef[f.coef.len - 1usize]
    if !fc.arima_fc(a, &cache.fit.model, cache.s2, kind, beta, n, 6usize, mean, se) { ret }
    i = 0usize
    while i < n {
        fd[i] = yt[i] - f.resid[i]
        i += 1usize
    }
    cache.good = true
}

fn back(v: f64, lam: f64) -> f64 {
    if lam == 5.0f64 { ret v }
    ret fcast.inv_box_cox(v, lam)
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let x = c.args
    let q = usize(x[0usize])
    let key = x[1usize..x.len]
    if !(cache.have && same_key(cache.key, key)) {
        cache.have = true
        cache.key = key
        build(a, key, cache)
    }
    if !cache.good { ret 0.0f64 / 0.0f64 }
    let f = &cache.fit
    let n = usize(x[11usize])
    if q == 1usize { ret 0.0f64 - 0.5f64 * f.value }
    if q == 5usize { ret cache.s2 }
    if q >= 2usize && q <= 4usize {
        let nstar = f64(f.nused)
        let npar = f64(f.nfree) + 1.0f64
        if q == 2usize { ret f.aic }
        if q == 3usize { ret f.aic + 2.0f64 * npar * (npar + 1.0f64) / (nstar - npar - 1.0f64) }
        ret f.aic + npar * (math.log[f64](nstar) - 2.0f64)
    }
    if q > 10usize && q < 100usize { ret f.coef[q - 11usize] }
    if q >= 500usize {
        let h = q - 501usize
        ret back(cache.mean[h] - dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false) * cache.se[h], cache.lam)
    }
    if q >= 400usize {
        let h = q - 401usize
        ret back(cache.mean[h] + dist.qnorm(0.9f64, 0.0f64, 1.0f64, true, false) * cache.se[h], cache.lam)
    }
    if q >= 300usize { ret cache.se[q - 301usize] }
    if q >= 200usize { ret back(cache.mean[q - 201usize], cache.lam) }
    ret back(cache.fitted[n + 100usize - q], cache.lam)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/arimafc.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var cache: Cache = zero
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c, &cache)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 600usize {
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    var k = 0usize
                    while k < 11usize && k < c.args.len {
                        let _ = str.push(&b, " ")
                        let _ = str.push_f64(&b, c.args[k])
                        k += 1usize
                    }
                    let _ = str.push(&b, " got ")
                    let _ = str.push_f64(&b, got)
                    let _ = str.push(&b, " want ")
                    let _ = str.push_f64(&b, c.want)
                    let _ = io.print(str.done(&b))
                    let _ = io.print("\n")
                }
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
