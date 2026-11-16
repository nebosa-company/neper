// e.algo.stat.xgboostpkg against xgboost reg:squarederror (exact). tests/oracle/xgboost.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R xgboost`; the layout is at the top of scripts/r_oracle/groups/xgboost.R.

use e.algo.stat.xgboostpkg as xg
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (pred, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret nan }
    let y = z[8usize..8usize + n]
    let x = z[8usize + n..8usize + n + n * p]
    if xg.boost(a, x, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), z[5usize], z[6usize], z[7usize], pred) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "rmse") {
        while i < n {
            s += (pred[i] - y[i]) * (pred[i] - y[i])
            i += 1usize
        }
        ret math.sqrt[f64](s / f64(n))
    }
    while i < n {
        s += pred[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/xgboost.json")
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
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
