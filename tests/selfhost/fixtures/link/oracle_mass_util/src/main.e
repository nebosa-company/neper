// e.algo.stat.massutil against MASS Null, area and lm.gls. The layout of every case is at the top of scripts/r_oracle/groups/mass_util.R.

use e.algo.stat.massutil as mu
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "area") { ret mu.area(usize(z[0usize]), z[1usize], z[2usize], i64(z[3usize]), z[4usize]) }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    if str.eq(c.name, "null") {
        let (out, e) = mem.alloc[f64](a, n * n)
        if e != ok { ret nan() }
        let (k, e2) = mu.null_space(a, z[3usize..3usize + n * p], n, p, out)
        if e2 != ok { ret nan() }
        if usize(z[2usize]) == 1usize { ret f64(k) }
        ret wsum(out[0usize..n * k])
    }
    let mode = usize(z[3usize])
    let w = z[4usize..4usize + n * n]
    let x = z[4usize + n * n..4usize + n * n + n * p]
    let y = z[4usize + n * n + n * p..4usize + n * n + n * p + n]
    let (g, e3) = mu.lm_gls(a, x, n, p, y, w, z[2usize] != 0.0f64)
    if e3 != ok { ret nan() }
    if mode == 0usize { ret wsum(g.coef[0usize..p]) }
    if mode == 1usize { ret wsum(g.fitted) }
    if mode == 2usize { ret wsum(g.resid) }
    ret f64(g.rank)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_util.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                var shown = *c
                if shown.args.len > 14usize { shown.args = c.args[0usize..14usize] }
                let _ = io.print(oracle.describe(a, &shown, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
