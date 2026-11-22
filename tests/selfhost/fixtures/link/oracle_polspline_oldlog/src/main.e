// e.algo.stat.oldlogspline against polspline: oldlogspline() fits with censoring (coefficients, knots, bounds, AIC table)
// and doldlogspline, poldlogspline, qoldlogspline. tests/oracle/polspline_oldlog.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R polspline_oldlog`.

use e.algo.stat.logspline as lg
use e.algo.stat.oldlogspline as ol
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

type Cache = struct { key: []f64, fit: ol.OldFit, valid: bool, m: lg.LogSpline, mk: []f64, mc: []f64 }

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
    let nu = usize(z[0usize])
    let nr = usize(z[1usize])
    let nl = usize(z[2usize])
    let nint = usize(z[3usize])
    let nuser = usize(z[9usize])
    let o = 12usize + nuser
    if !cache.valid || !same(cache.key, key) {
        let (fit, e) = ol.oldlogspline_fit(a, z[o..o + nu], z[o + nu..o + nu + nr], z[o + nu + nr..o + nu + nr + nl], z[o + nu + nr + nl..o + nu + nr + nl + 2usize * nint], z[4usize] > 0.5f64, z[5usize], z[6usize] > 0.5f64, z[7usize], i64(z[8usize]), z[12usize..12usize + nuser], z[10usize], z[11usize] > 0.5f64)
        if e != ok { ret nan }
        cache.key = key
        cache.fit = fit
        cache.valid = true
        if fit.code == 0i64 {
            // oldlogspline.to.logspline: the nonzero knot coefficients
            var cnt = 0usize
            var i = 0usize
            while i < usize(fit.nk) {
                if fit.coef[2usize + i] != 0.0f64 { cnt += 1usize }
                i += 1usize
            }
            let (mk, e1) = mem.alloc[f64](a, cnt + 1usize)
            let (mc, e2) = mem.alloc[f64](a, cnt + 1usize)
            if e1 != ok || e2 != ok { ret nan }
            var j = 0usize
            i = 0usize
            while i < usize(fit.nk) {
                if fit.coef[2usize + i] != 0.0f64 {
                    mk[j] = fit.knots[i]
                    mc[j] = fit.coef[2usize + i]
                    j += 1usize
                }
                i += 1usize
            }
            cache.mk = mk[0usize..cnt]
            cache.mc = mc[0usize..cnt]
            cache.m = lg.LogSpline{ c0: fit.coef[0usize], c1: fit.coef[1usize], kc: cache.mc, knots: cache.mk, lower: fit.bound[0usize] > 0.0f64, lo: fit.bound[1usize], upper: fit.bound[2usize] > 0.0f64, hi: fit.bound[3usize] }
        }
    }
    let f = &cache.fit
    if f.code != 0i64 { ret nan }
    let what = usize(z[z.len - 2usize])
    let x = z[z.len - 1usize]
    if what == 0usize { ret f64(f.knots.len) }
    if what == 1usize { ret f.coef[usize(x)] }
    if what == 2usize { ret f.knots[usize(x)] }
    if what == 3usize { ret f.bound[usize(x)] }
    if what == 4usize { ret f64(f.logl.len) }
    if what == 5usize { ret f.logl[usize(x)] }
    if what == 6usize { ret f.penalty }
    if what == 7usize { ret f64(f.sample) }
    if what == 8usize { ret lg.dlogspline(&cache.m, x, false) }
    if what == 9usize {
        let (v, e) = lg.plogspline(a, &cache.m, x)
        if e != ok { ret nan }
        ret v
    }
    let (v, e) = lg.qlogspline(a, &cache.m, x)
    if e != ok { ret nan }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/polspline_oldlog.json")
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
