// e.algo.stat.heft against polspline: heft() fits (knots, thetas, AIC table, log standard errors) and the hazard they give.
// tests/oracle/polspline_heft.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R polspline_heft`.

use e.algo.stat.heft as hf
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

type Cache = struct { key: []f64, fit: hf.HeftFit, shift: f64, valid: bool }

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
    let nuser = usize(z[2usize])
    let o = 3usize + nuser
    let xs = z[o + 8usize..o + 8usize + n]
    if !cache.valid || !same(cache.key, key) {
        let (dl, ed) = mem.alloc[i64](a, n)
        if ed != ok { ret nan }
        var i = 0usize
        while i < n {
            dl[i] = i64(z[o + 8usize + n + i])
            i += 1usize
        }
        let (fit, e) = hf.heft_fit(a, xs, dl, z[1usize], z[3usize..3usize + nuser], z[o..o + 5usize], z[o + 5usize], i64(z[o + 6usize]), i64(z[o + 7usize]))
        if e != ok { ret nan }
        cache.key = key
        cache.fit = fit
        cache.shift = z[o + 5usize]
        cache.valid = true
    }
    let what = usize(z[z.len - 2usize])
    let x = z[z.len - 1usize]
    let f = &cache.fit
    if f.code != 0i64 { ret nan }
    let nk = f.nk
    // R: logl[2:(nk+1)] and adddel[2:(nk+1)] (1-based), i.e. C indices 1..nk
    if what == 0usize { ret f64(nk) }
    if what == 1usize { ret f.knots[usize(x)] }
    if what == 2usize { ret f.theta[usize(x)] }
    if what == 3usize { ret f.theta[nk + usize(x)] }
    if what == 4usize { ret f.theta[nk + 2usize + usize(x)] }
    if what == 5usize {
        if usize(x) == 0usize { ret f.logse0 }
        ret f.logse1
    }
    if what == 6usize {
        let v = f.logl[1usize + usize(x)]
        if f.ad[1usize + usize(x)] == 2 { ret 0.0f64 }
        if math.abs[f64](v) < 1.0e-100f64 { ret 0.0f64 }
        ret v
    }
    if what == 7usize { ret f64(f.ad[1usize + usize(x)]) }
    if what == 8usize {
        if z[1usize] < 0.0f64 { ret math.log[f64](f64(n)) }
        ret z[1usize]
    }
    if what == 9usize { ret cache.shift }
    ret hf.hheft(f, cache.shift, xs[usize(x)])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/polspline_heft.json")
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
