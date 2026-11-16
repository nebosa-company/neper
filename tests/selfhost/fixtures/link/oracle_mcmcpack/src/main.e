// e.algo.stat.mcmcpackpkg against MCMCpack densities. tests/oracle/mcmcpack.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpack`; the layout is at the top of scripts/r_oracle/groups/mcmcpack.R.

use e.algo.stat.mcmcpackpkg as mp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "dinvgamma") { ret mp.dinvgamma(z[0usize], z[1usize], z[2usize]) }
    if str.eq(c.name, "ddirichlet") {
        let k = usize(z[0usize])
        ret mp.ddirichlet(z[1usize..1usize + k], z[1usize + k..1usize + 2usize * k])
    }
    let p = usize(z[0usize])
    ret mp.wishart(a, z[2usize..2usize + p * p], z[2usize + p * p..2usize + 2usize * p * p], p, z[1usize], str.eq(c.name, "diwish"), false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpack.json")
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
