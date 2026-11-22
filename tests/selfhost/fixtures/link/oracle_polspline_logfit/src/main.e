// e.algo.stat.logspline_fit against polspline: logspline() fits (knots, coefficients, AIC table) and the density they give.
// tests/oracle/polspline_logfit.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R polspline_logfit`.

use e.algo.stat.logspline as ls
use e.algo.stat.logspline_fit as lf
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

type Cache = struct { key: []f64, fit: lf.LsFit, lower: bool, lo: f64, upper: bool, hi: f64, valid: bool }

fn same(x: []const f64, y: []const f64) -> bool {
    if x.len != y.len { ret false }
    var i = 0usize
    while i < x.len {
        if x[i] != y[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let z = c.args
    let key = z[0usize..z.len - 2usize]
    let n = usize(z[0usize])
    let nuser = usize(z[9usize])
    let xs = z[10usize + nuser..10usize + nuser + n]
    if !cache.valid || !same(cache.key, key) {
        let (fit, e) = lf.logspline_fit(a, xs, i64(z[1usize]), i64(z[2usize]), z[3usize] > 0.5f64, z[4usize], z[5usize] > 0.5f64, z[6usize], z[7usize], i64(z[8usize]), z[10usize..10usize + nuser])
        if e != ok { ret nan }
        cache.key = key
        cache.fit = fit
        cache.lower = z[3usize] > 0.5f64
        cache.lo = z[4usize]
        cache.upper = z[5usize] > 0.5f64
        cache.hi = z[6usize]
        cache.valid = true
    }
    let what = usize(z[z.len - 2usize])
    let x = z[z.len - 1usize]
    let f = &cache.fit
    if f.code != 0i64 { ret nan }
    if what == 0usize { ret f64(f.nknots) }
    if what == 1usize { ret f.coef[usize(x)] }
    if what == 2usize { ret f.coef[2usize + usize(x)] }
    if what == 3usize { ret f.knots[usize(x)] }
    if what == 4usize { ret f.penalty }
    if what == 5usize { ret f64(f.mind) }
    // the table the R wrapper builds: model dimensions 2.. (labelled by knots 3..) that were fitted (ad != 0)
    var rows = 0usize
    var pick = 0usize
    var t = 1usize
    while t <= usize(f.ndim) {
        if f.ad[t] != 0 {
            if rows == usize(x) { pick = t }
            rows += 1usize
        }
        t += 1usize
    }
    if what == 6usize { ret f64(rows) }
    if what == 7usize { ret f64(f.ad[pick]) }
    if what == 8usize { ret f.logl[pick] }
    if what == 9usize { ret f64(pick + 2usize) }
    var m: ls.LogSpline = zero
    m.c0 = f.coef[0usize]
    m.c1 = f.coef[1usize]
    m.kc = f.coef[2usize..2usize + f.nknots]
    m.knots = f.knots[0usize..f.nknots]
    m.lower = cache.lower
    m.lo = cache.lo
    m.upper = cache.upper
    m.hi = cache.hi
    ret ls.dlogspline(&m, xs[usize(x)], false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/polspline_logfit.json")
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
            if failures <= 8usize {
                var tail: [3]f64 = zero
                tail[0usize] = f64(at)
                tail[1usize] = c.args[c.args.len - 2usize]
                tail[2usize] = c.args[c.args.len - 1usize]
                let short = oracle.Case{ name: c.name, args: tail[0usize..3usize], want: c.want, rel: c.rel, abs: c.abs, text: c.text, inputs: c.inputs }
                let _ = io.print(oracle.describe(a, &short, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
