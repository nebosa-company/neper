// e.algo.stat.autoarima against forecast::auto.arima, ndiffs, nsdiffs, ocsb.test and uroot::ch.test. The layout is at the
// top of scripts/r_oracle/groups/autoarima.R; consecutive "auto" cases of one series and setting share a search.

use e.algo.stat.autoarima as aa
use e.algo.stat.arimafc as fc
use e.io
use e.mem
use e.math
use e.math.dist as dist
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct { key: []f64, res: aa.AaRes, mean: []f64, se: []f64, have: bool, good: bool }

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

// key: stepwise, appr, test, stest, m, n, y...
fn build(a: *mem.Arena, x: []const f64, cache: *Cache) {
    cache.good = false
    let n = usize(x[5usize])
    let (res, e) = aa.auto_arima(a, x[6usize..6usize + n], usize(x[4usize]), x[0usize] != 0.0f64, usize(x[1usize]), usize(x[2usize]), usize(x[3usize]))
    cache.res = res
    if e != ok { ret }
    let (mean, e1) = mem.alloc[f64](a, 6usize)
    let (se, e2) = mem.alloc[f64](a, 6usize)
    if e1 != ok || e2 != ok { ret }
    cache.mean = mean
    cache.se = se
    var kind = 0usize
    if res.cst {
        kind = 1usize
        if res.d + res.sd == 1usize { kind = 2usize }
    }
    let f = &cache.res.fit
    var beta = 0.0f64
    if kind > 0usize { beta = f.coef[f.coef.len - 1usize] }
    if !fc.arima_fc(a, &cache.res.fit.model, cache.res.sigma2, kind, beta, n, 6usize, mean, se) { ret }
    cache.good = true
}

fn auto_answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let x = c.args
    let q = usize(x[0usize])
    let key = x[1usize..x.len]
    if !(cache.have && same_key(cache.key, key)) {
        cache.have = true
        cache.key = key
        build(a, key, cache)
    }
    if !cache.good { ret nan() }
    let r = &cache.res
    let f = &cache.res.fit
    if q == 1usize { ret f64(r.p) }
    if q == 2usize { ret f64(r.d) }
    if q == 3usize { ret f64(r.q) }
    if q == 4usize { ret f64(r.sp) }
    if q == 5usize { ret f64(r.sd) }
    if q == 6usize { ret f64(r.sq) }
    if q == 7usize {
        if r.cst { ret 1.0f64 }
        ret 0.0f64
    }
    if q == 8usize { ret r.ic }
    if q == 9usize { ret 0.0f64 - 0.5f64 * f.value }
    if q == 10usize { ret r.sigma2 }
    if q >= 300usize { ret cache.se[q - 301usize] }
    if q >= 200usize { ret cache.mean[q - 201usize] }
    ret f.coef[q - 21usize]
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let x = c.args
    if str.eq(c.name, "ndiffs") {
        let n = usize(x[2usize])
        ret f64(aa.ndiffs_t(a, x[3usize..3usize + n], usize(x[0usize]), usize(x[1usize])))
    }
    if str.eq(c.name, "nsdiffs") {
        let n = usize(x[3usize])
        ret f64(aa.nsdiffs_t(a, x[4usize..4usize + n], usize(x[2usize]), usize(x[0usize]), usize(x[1usize])))
    }
    if str.eq(c.name, "ocsb") {
        let n = usize(x[2usize])
        let (stat, crit, lag, good) = aa.ocsb_run(a, x[3usize..3usize + n], usize(x[1usize]))
        let q = usize(x[0usize])
        if q == 1usize { ret stat }
        if q == 2usize { ret crit }
        ret f64(lag)
    }
    if str.eq(c.name, "ch") {
        let n = usize(x[2usize])
        let (stat, pv) = aa.ch_joint_p(a, x[3usize..3usize + n], usize(x[1usize]))
        if usize(x[0usize]) == 1usize { ret stat }
        ret pv
    }
    ret auto_answer(a, c, cache)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/autoarima.json")
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
