// e.algo.stat.etsfit against forecast::ets: single fits and the ZZZ search. The layout is at the top of
// scripts/r_oracle/groups/etsfit.R; consecutive cases of one series and model share a fit.

use e.algo.stat.etsfit as es
use e.algo.stat.fcast as fcast
use e.math.dist as dist
use e.io
use e.mem
use e.math
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct { key: []f64, fit: es.EtsFit, fc: []f64, vr: []f64, have: bool }

fn same_key(a: []const f64, b: []const f64) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn quantity(c: *Cache, q: usize) -> f64 {
    let f = &c.fit
    if !f.good { ret 0.0f64 / 0.0f64 }
    if q == 1usize { ret f.loglik }
    if q == 2usize { ret f.aic }
    if q == 3usize { ret f.aicc }
    if q == 4usize { ret f.bic }
    if q == 5usize { ret f.sigma2 }
    if q == 6usize { ret f.mse }
    if q == 7usize { ret f.amse }
    if q == 8usize { ret f.alpha }
    if q == 9usize { ret f.beta }
    if q == 10usize { ret f.gamma }
    if q == 11usize { ret f.phi }
    if q >= 300usize { ret math.sqrt[f64](c.vr[q - 301usize]) }
    if q >= 200usize { ret c.fc[q - 201usize] }
    if q >= 100usize { ret f.fitted[f.n + 100usize - q] }
    ret f.init[q - 12usize]
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let x = c.args
    let q = usize(x[0usize])
    if str.eq(c.name, "theta") {
        let tn = usize(x[2usize])
        let (mean, me) = mem.alloc[f64](a, 6usize)
        let (se, se2) = mem.alloc[f64](a, 6usize)
        if me != ok || se2 != ok { ret 0.0f64 / 0.0f64 }
        if !es.thetaf(a, x[3usize..3usize + tn], usize(x[1usize]), 6usize, mean, se, mean[0usize..0usize]) { ret 0.0f64 / 0.0f64 }
        if q > 10usize { ret se[q - 11usize] }
        ret mean[q - 1usize]
    }
    if str.eq(c.name, "theta2") {
        let m = usize(x[1usize])
        let tn = usize(x[2usize])
        let lam = x[3usize]
        let (mean, me) = mem.alloc[f64](a, 6usize)
        let (se, se2) = mem.alloc[f64](a, 6usize)
        let (fd, fe) = mem.alloc[f64](a, tn)
        let (yt, ye) = mem.alloc[f64](a, tn)
        if me != ok || se2 != ok || fe != ok || ye != ok { ret 0.0f64 / 0.0f64 }
        var i = 0usize
        while i < tn {
            yt[i] = x[4usize + i]
            if lam != 5.0f64 { yt[i] = fcast.box_cox(x[4usize + i], lam) }
            i += 1usize
        }
        if !es.thetaf(a, yt, m, 6usize, mean, se, fd) { ret 0.0f64 / 0.0f64 }
        var out = 0.0f64
        if q == 99usize { out = fd[0usize] }
        if q > 100usize && q < 104usize { out = fd[tn + 100usize - q] }
        if q > 200usize && q < 207usize { out = mean[q - 201usize] }
        if q > 400usize && q < 407usize { out = mean[q - 401usize] + dist.qnorm(0.9f64, 0.0f64, 1.0f64, true, false) * se[q - 401usize] }
        if q > 700usize { out = mean[q - 701usize] - dist.qnorm(0.975f64, 0.0f64, 1.0f64, true, false) * se[q - 701usize] }
        if lam != 5.0f64 { out = fcast.inv_box_cox(out, lam) }
        ret out
    }
    let key = x[1usize..x.len]
    if !(cache.have && same_key(cache.key, key)) {
        cache.have = true
        cache.key = key
        var fit: es.EtsFit = zero
        if str.eq(c.name, "fit") {
            let n = usize(x[6usize])
            fit = es.ets_fit(a, x[7usize..7usize + n], usize(x[1usize]), usize(x[2usize]), usize(x[3usize]), x[4usize] != 0.0f64, usize(x[5usize]))
        } else {
            let n = usize(x[2usize])
            fit = es.ets_auto(a, x[3usize..3usize + n], usize(x[1usize]), 0usize, str.eq(c.name, "autom"))
        }
        cache.fit = fit
        let (fc, e) = mem.alloc[f64](a, 6usize)
        if e != ok { ret 0.0f64 / 0.0f64 }
        cache.fc = fc
        let (vr, ve) = mem.alloc[f64](a, 6usize)
        if ve != ok { ret 0.0f64 / 0.0f64 }
        cache.vr = vr
        if fit.good { es.ets_point(a, &cache.fit, 6usize, fc) }
        if fit.good { let _ = es.ets_var(a, &cache.fit, 6usize, vr) }
    }
    if str.eq(c.name, "auto") || str.eq(c.name, "autom") {
        let f = &cache.fit
        if !f.good { ret 0.0f64 / 0.0f64 }
        if q == 1usize {
            var cd = f64(f.tt * 10usize + f.st + f.et * 100usize)
            if f.damped { cd += 1000.0f64 }
            ret cd
        }
        if q == 2usize { ret f.aicc }
        if q == 3usize { ret f.alpha }
    }
    ret quantity(cache, q)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/etsfit.json")
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
            if failures <= 40usize {
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
