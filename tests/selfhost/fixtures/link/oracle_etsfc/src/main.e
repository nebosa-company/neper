// e.algo.stat.etsfc against forecast::ets: class3 and simulated prediction intervals, and ets(lambda = ...). The layout is at
// the top of scripts/r_oracle/groups/etsfc.R; consecutive cases of one series and model share a fit.

use e.algo.rand.r as rr
use e.algo.stat.etsfc as ef
use e.algo.stat.etsfit as es
use e.algo.stat.fcast as fcast
use e.io
use e.mem
use e.math
use e.math.dist as dist
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct {
    key: []f64, fit: es.EtsFit, mean: []f64, up80: []f64, lo80: []f64, up95: []f64, lo95: []f64, fitted: []f64, have: bool, good: bool
}

fn same_key(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn buf(a: *mem.Arena, n: usize) -> []f64 {
    let (s, e) = mem.alloc[f64](a, n + 1usize)
    ret s[0usize..n]
}

fn limits(a: *mem.Arena, c: *Cache, h: usize, sd: []const f64, lam: f64) {
    let z80 = dist.qnorm(0.9f64, 0.0f64, 1.0f64, true, false)
    let z95 = dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false)
    var i = 0usize
    while i < h {
        c.up80[i] = c.mean[i] + z80 * sd[i]
        c.lo80[i] = c.mean[i] - z80 * sd[i]
        c.up95[i] = c.mean[i] + z95 * sd[i]
        c.lo95[i] = c.mean[i] - z95 * sd[i]
        i += 1usize
    }
}

fn back(c: *Cache, h: usize, lam: f64) {
    var i = 0usize
    while i < h {
        c.mean[i] = fcast.inv_box_cox(c.mean[i], lam)
        c.up80[i] = fcast.inv_box_cox(c.up80[i], lam)
        c.lo80[i] = fcast.inv_box_cox(c.lo80[i], lam)
        c.up95[i] = fcast.inv_box_cox(c.up95[i], lam)
        c.lo95[i] = fcast.inv_box_cox(c.lo95[i], lam)
        i += 1usize
    }
}

// "int" key: e, t, s, damped, m, n, seed, y...; "lam" key: m, n, lambda, y...
fn build(a: *mem.Arena, x: []const f64, is_int: bool, c: *Cache) {
    c.good = false
    let h = 6usize
    c.mean = buf(a, h)
    c.up80 = buf(a, h)
    c.lo80 = buf(a, h)
    c.up95 = buf(a, h)
    c.lo95 = buf(a, h)
    let sd = buf(a, h)
    let vr = buf(a, h)
    if is_int {
        let n = usize(x[5usize])
        let y = x[7usize..7usize + n]
        c.fit = es.ets_fit(a, y, usize(x[0usize]), usize(x[1usize]), usize(x[2usize]), x[3usize] != 0.0f64, usize(x[4usize]))
        if !c.fit.good { ret }
        es.ets_point(a, &c.fit, h, c.mean)
        var i = 0usize
        if es.ets_var(a, &c.fit, h, vr) {
            i = 0usize
            while i < h {
                sd[i] = math.sqrt[f64](vr[i])
                i += 1usize
            }
            limits(a, c, h, sd, 5.0f64)
        } else if c.fit.et == 2usize && c.fit.st == 2usize && c.fit.tt != 2usize {
            let mu = buf(a, h)
            ef.ets_class3(a, &c.fit, h, mu, vr)
            i = 0usize
            while i < h {
                sd[i] = math.sqrt[f64](vr[i])
                i += 1usize
            }
            limits(a, c, h, sd, 5.0f64)
        } else {
            var g: rr.Rng = zero
            rr.seed(&g, i64(x[6usize]))
            if !ef.ets_sim_pi(a, &c.fit, h, 5000usize, &g, c.lo80, c.up80, c.lo95, c.up95) { ret }
        }
        c.good = true
        ret
    }
    let n = usize(x[1usize])
    let lam = x[2usize]
    let yt = buf(a, n)
    var i = 0usize
    while i < n {
        yt[i] = fcast.box_cox(x[3usize + i], lam)
        i += 1usize
    }
    c.fit = es.ets_auto_o(a, yt, usize(x[0usize]), 0usize, false, true)
    if !c.fit.good { ret }
    es.ets_point(a, &c.fit, h, c.mean)
    if !es.ets_var(a, &c.fit, h, vr) { ret }
    i = 0usize
    while i < h {
        sd[i] = math.sqrt[f64](vr[i])
        i += 1usize
    }
    limits(a, c, h, sd, lam)
    back(c, h, lam)
    c.fitted = buf(a, n)
    i = 0usize
    while i < n {
        c.fitted[i] = fcast.inv_box_cox(c.fit.fitted[i], lam)
        i += 1usize
    }
    c.good = true
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let x = c.args
    let q = usize(x[0usize])
    let is_int = str.eq(c.name, "int")
    let key = x[1usize..x.len]
    if !(cache.have && same_key(cache.key, key)) {
        cache.have = true
        cache.key = key
        build(a, key, is_int, cache)
    }
    if !cache.good { ret nan() }
    if !is_int {
        let f = &cache.fit
        if q == 1usize {
            var cd = f64(f.tt * 10usize + f.st + f.et * 100usize)
            if f.damped { cd += 1000.0f64 }
            ret cd
        }
        if q == 2usize { ret f.aicc }
        if q == 3usize { ret f.loglik }
        if q == 4usize { ret f.sigma2 }
        if q == 5usize { ret f.alpha }
        if q < 200usize { ret cache.fitted[usize(x[2usize]) + 100usize - q] }
    }
    if q >= 700usize { ret cache.lo95[q - 701usize] }
    if q >= 600usize { ret cache.lo80[q - 601usize] }
    if q >= 500usize { ret cache.up95[q - 501usize] }
    if q >= 400usize { ret cache.up80[q - 401usize] }
    ret cache.mean[q - 201usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/etsfc.json")
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
            if failures <= 300usize {
                let (initial, be) = str.builder(a, 160usize)
                if be == ok {
                    var b = initial
                    let _ = str.push(&b, c.name)
                    var k = 0usize
                    while k < 8usize && k < c.args.len {
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
