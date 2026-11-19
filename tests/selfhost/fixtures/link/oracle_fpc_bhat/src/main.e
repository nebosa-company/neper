// e.algo.stat.fpc's bhattacharyya_dist against fpc. tests/oracle/fpc_bhat.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_bhat`; the layout is at the top of scripts/r_oracle/groups/fpc_bhat.R.

use e.algo.stat.fpc as fp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let d = usize(z[0usize])
    let (v, e) = fp.bhattacharyya_dist(a, z[1usize..1usize + d], z[1usize + d..1usize + 2usize * d], z[1usize + 2usize * d..1usize + 2usize * d + d * d], z[1usize + 2usize * d + d * d..1usize + 2usize * d + 2usize * d * d], d)
    if e != ok { ret 0.0f64 / 0.0f64 }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_bhat.json")
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
