// e.algo.stat.fdapkg against fda. tests/oracle/fda.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fda`; the layout is at the top of scripts/r_oracle/groups/fda.R.

use e.algo.stat.fdapkg as fa
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let norder = usize(z[0usize])
    let nb = usize(z[1usize])
    let (o, e) = mem.alloc[f64](a, nb + norder)
    if e != ok { ret nan }
    if fa.eval_bspline(a, norder, z[5usize..5usize + nb], z[3usize], usize(z[2usize]), o) != ok { ret nan }
    ret o[usize(z[4usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fda.json")
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
