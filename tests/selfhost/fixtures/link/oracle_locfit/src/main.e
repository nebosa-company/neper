// e.algo.stat.locfitpkg against locfit local polynomial regression. tests/oracle/locfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R locfit`; the layout is at the top of scripts/r_oracle/groups/locfit.R.

use e.algo.stat.locfitpkg as lf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (out, e1) = mem.alloc[f64](a, n)
    if e1 != ok { ret nan }
    let x = z[4usize..4usize + n]
    let y = z[4usize + n..4usize + 2usize * n]
    if lf.lpfit(a, x, y, z[1usize], z[2usize], usize(z[3usize]), out) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        if str.eq(c.name, "rss") { s += (y[i] - out[i]) * (y[i] - out[i]) } else { s += out[i] * f64(i + 1usize) }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/locfit.json")
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
