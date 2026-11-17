// e.algo.stat.loessfit against stats::loess (one predictor). tests/oracle/gbmloess.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gbmloess`.

use e.algo.rand.r as rng
use e.algo.stat.gbmfit as gb
use e.algo.stat.loessfit as lf
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let z = c.args
    let n = usize(z[1usize])
    var bad = 0usize
    let x = gb.af(a, n, &bad)
    let y = gb.af(a, n, &bad)
    let fit = gb.af(a, n, &bad)
    if bad != 0usize { ret nan }
    var rg: rng.Rng = zero
    rng.seed(&rg, i64(z[0usize]))
    var i = 0usize
    while i < n {
        if z[5usize] == 0.0f64 {
            x[i] = math.floor[f64](rng.norm(&rg) * 1000.0f64 + 0.5f64) / 1000.0f64
        } else {
            x[i] = f64(i + 1usize)
        }
        i += 1usize
    }
    var scale = 1.0f64
    if z[5usize] != 0.0f64 { scale = f64(n) / 6.0f64 }
    i = 0usize
    while i < n {
        y[i] = math.sin[f64](x[i] / scale) + rng.rnorm(&rg, 0.0f64, 1.0f64) * 0.4f64
        i += 1usize
    }
    var span = z[2usize]
    let deg = usize(z[4usize])
    if z[3usize] > 0.0f64 { span = lf.span_for_enp(z[3usize], deg) }
    if lf.loess_fitted(a, x, y, n, span, deg, fit) != ok { ret nan }
    ret fit[usize(z[6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gbmloess.json")
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
            if failures <= 10usize {
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
