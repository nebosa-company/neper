// e.algo.stat.dfree against nloptr BOBYQA on a battery of smooth test functions in a box.
// tests/oracle/dfree.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dfree`; the layout
// is at the top of scripts/r_oracle/groups/dfree.R.

use e.algo.stat.dfree as df
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pw(v: f64) -> f64 { ret v * v }

fn obj(ctx: *u8, x: []const f64) -> f64 {
    let which = usize(*ctx)
    let n = x.len
    var s = 0.0f64
    if which == 0usize {
        var i = 0usize
        while i + 1usize < n {
            s += 100.0f64 * pw(x[i + 1usize] - x[i] * x[i]) + pw(1.0f64 - x[i])
            i += 1usize
        }
        ret s
    }
    if which == 1usize {
        ret pw(1.5f64 - x[0usize] + x[0usize] * x[1usize]) + pw(2.25f64 - x[0usize] + x[0usize] * x[1usize] * x[1usize]) + pw(2.625f64 - x[0usize] + x[0usize] * x[1usize] * x[1usize] * x[1usize])
    }
    if which == 2usize { ret pw(x[0usize] * x[0usize] + x[1usize] - 11.0f64) + pw(x[0usize] + x[1usize] * x[1usize] - 7.0f64) }
    if which == 3usize { ret pw(x[0usize] + 2.0f64 * x[1usize] - 7.0f64) + pw(2.0f64 * x[0usize] + x[1usize] - 5.0f64) }
    var i = 0usize
    while i < n {
        s += pw(x[i] - f64(i + 1usize)) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var dummy = u8(x[0usize])
    let n = usize(x[1usize])
    let (x0, e) = mem.alloc[f64](a, n)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        x0[i] = x[2usize + i]
        i += 1usize
    }
    let (v, fe) = df.minimize_box(a, obj, &dummy, x0, x[2usize + n..2usize + 2usize * n], x[2usize + 2usize * n..2usize + 3usize * n], 1.0e-14f64)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "val") { ret v }
    ret x0[usize(x[2usize + 3usize * n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dfree.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
