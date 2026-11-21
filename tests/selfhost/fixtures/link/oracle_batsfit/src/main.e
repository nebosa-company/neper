// e.algo.stat.batsfit against forecast::bats and forecast::tbats. The layout is at the top of scripts/r_oracle/groups/batsfit.R;
// consecutive cases of one fit share it.

use e.algo.stat.batsfit as bf
use e.io
use e.mem
use e.math
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct {
    key: []f64, fit: bf.BatsFit, mean: []f64, lo80: []f64, up80: []f64, lo95: []f64, up95: []f64, have: bool
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

fn build(a: *mem.Arena, key: []const f64, c: *Cache) {
    let kind = usize(key[0usize])
    let bcm = usize(key[1usize])
    let trm = usize(key[2usize])
    let dpm = usize(key[3usize])
    let arma = key[4usize] != 0.0f64
    let adj = key[5usize] != 0.0f64
    let freq = usize(key[6usize])
    let nper = usize(key[7usize])
    let per = key[8usize..8usize + nper]
    let n = usize(key[8usize + nper])
    let y = key[9usize + nper..9usize + nper + n]
    if kind == 0usize {
        c.fit = bf.bats_fit(a, y, freq, per, bcm, trm, dpm, arma, 0.0f64, 1.0f64, adj)
    } else {
        c.fit = bf.tbats_fit(a, y, freq, per, bcm, trm, dpm, arma, 0.0f64, 1.0f64, adj)
    }
    let h = 8usize
    c.mean = buf(a, h)
    c.lo80 = buf(a, h)
    c.up80 = buf(a, h)
    c.lo95 = buf(a, h)
    c.up95 = buf(a, h)
    if !c.fit.good { ret }
    bf.bats_forecast(a, &c.fit, h, 80.0f64, c.mean, c.lo80, c.up80)
    bf.bats_forecast(a, &c.fit, h, 95.0f64, c.mean, c.lo95, c.up95)
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
    let f = &cache.fit
    if !f.good { ret nan() }
    if q == 1usize { ret f.lam }
    if q == 2usize { ret f.alpha }
    if q == 3usize { ret f.beta }
    if q == 4usize { ret f.phi }
    if q == 5usize { ret f.loglik }
    if q == 6usize { ret f.aic }
    if q == 7usize { ret f.variance }
    if q == 8usize { ret f64(f.sp.p) }
    if q == 9usize { ret f64(f.sp.q) }
    if q == 10usize { ret f64(f.d) }
    if q == 11usize { ret f64(f.code) }
    if q == 12usize {
        if f.sp.tb { ret 1.0f64 }
        ret 0.0f64
    }
    if q >= 1400usize { ret cache.up95[q - 1401usize] }
    if q >= 1300usize { ret cache.lo95[q - 1301usize] }
    if q >= 1200usize { ret cache.up80[q - 1201usize] }
    if q >= 1100usize { ret cache.lo80[q - 1101usize] }
    if q >= 1000usize { ret cache.mean[q - 1001usize] }
    if q >= 800usize { ret f.x[(f.n - 1usize) * f.d + (q - 801usize)] }
    if q >= 700usize { ret f.errors[f.n + 700usize - q] }
    if q >= 600usize { ret f.fitted[f.n + 600usize - q] }
    if q >= 500usize { ret f.seed[q - 501usize] }
    if q >= 400usize { ret f64(f.sp.kv[q - 401usize]) }
    if q >= 300usize { ret f.mac[q - 301usize] }
    if q >= 200usize { ret f.arc[q - 201usize] }
    ret f.gam[q - 101usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/batsfit.json")
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
                    while k < 1usize && k < c.args.len {
                        let _ = str.push(&b, " q")
                        let _ = str.push_f64(&b, c.args[k])
                        k += 1usize
                    }
                    let _ = str.push(&b, " n")
                    let _ = str.push_f64(&b, f64(cache.fit.n))
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
