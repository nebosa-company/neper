// e.algo.stat.multcomppkg against multcomp glht. tests/oracle/multcomp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R multcomp`; the layout is at the top of scripts/r_oracle/groups/multcomp.R.

use e.algo.stat.multcomppkg as mc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[2usize])
    let (out, e1) = mem.alloc[f64](a, 6usize * m)
    if e1 != ok { ret nan }
    let x = z[3usize..3usize + n * p]
    let y = z[3usize + n * p..3usize + n * p + n]
    let k = z[3usize + n * p + n..3usize + n * p + n + m * p]
    if mc.glht(a, x, y, n, p, k, m, out) != ok { ret nan }
    var slot = 0usize
    if str.eq(c.name, "se") { slot = 1usize }
    if str.eq(c.name, "t") { slot = 2usize }
    if str.eq(c.name, "p") { slot = 3usize }
    if str.eq(c.name, "bonf") { slot = 4usize }
    if str.eq(c.name, "holm") { slot = 5usize }
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += out[slot * m + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/multcomp.json")
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
