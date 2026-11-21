// e.algo.stat.mcmcpacklap against the Laplace marginal likelihood of MCMClogit and MCMCpoisson. tests/oracle/mcmcpacklap.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpacklap`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpacklap.R.

use e.algo.stat.mcmcpacklap as lap
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let kind = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    var o = 3usize
    let y = z[o..o + n]
    o += n
    let x = z[o..o + n * k]
    o += n * k
    let beta0 = z[o..o + k]
    o += k
    let b0 = z[o..o + k]
    o += k
    let bb = z[o..o + k * k]
    var ml = 0.0f64
    if lap.laplace(a, kind, y, x, n, k, b0, bb, beta0, &ml) != ok { ret nan }
    ret ml
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpacklap.json")
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
