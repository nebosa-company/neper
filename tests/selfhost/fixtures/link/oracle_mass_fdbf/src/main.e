// e.algo.stat.fitdist's fitdistr2_start (beta and F) against MASS fitdistr(x, "beta" / "f", start). tests/oracle/mass_fdbf.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_fdbf`; the layout is at the top of scripts/r_oracle/groups/mass_fdbf.R.

use e.algo.stat.fitdist as fdi
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let z = c.args
    let n = usize(z[1usize])
    let (fo, fe) = mem.alloc[f64](a, 5usize)
    if fe != ok { ret nan }
    if fdi.fitdistr2_start(a, z[5usize..5usize + n], usize(z[0usize]), z[3usize], z[4usize], fo) != ok { ret nan }
    ret fo[usize(z[2usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_fdbf.json")
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
