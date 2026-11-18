// e.algo.stat.ismev's gev.fit with a location covariate against ismev::gev.fit(x, ydat = z, mul = 1). tests/oracle/ismev_cov.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ismev_cov`; the layout of every case is at the top of scripts/r_oracle/groups/ismev_cov.R.

use e.algo.stat.ismev as im
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let which = usize(z[0usize])
    let n = usize(z[1usize])
    let x = z[2usize..2usize + n]
    let zc = z[2usize + n..2usize + 2usize * n]
    let (dm, e0) = mem.alloc[f64](a, 2usize * n)
    if e0 != ok { os.exit(10) }
    var i = 0usize
    while i < n {
        dm[i * 2usize] = 1.0f64
        dm[i * 2usize + 1usize] = zc[i]
        i += 1usize
    }
    let (f, fe) = im.fit_mul(a, x, dm, 2usize)
    if fe != ok { os.exit(11) }
    if which == 99usize { ret f.nllh }
    if which >= 10usize { ret f.se[which - 10usize] }
    ret f.par[which]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ismev_cov.json")
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
