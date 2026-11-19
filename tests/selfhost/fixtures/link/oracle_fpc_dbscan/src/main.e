// e.algo.stat.fpc dbscan against fpc. tests/oracle/fpc_dbscan.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fpc_dbscan`; the layout is at the top of scripts/r_oracle/groups/fpc_dbscan.R.

use e.algo.stat.fpc as fp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (cv, e0) = mem.alloc[i64](a, n)
    let (sd, e1) = mem.alloc[bool](a, n)
    if e0 != ok || e1 != ok { os.exit(4) }
    let e = fp.dbscan(a, z[6usize..6usize + n * p], n, p, z[2usize], usize(z[3usize]), cv, sd)
    if e != ok { os.exit(5) }
    let idx = usize(z[5usize])
    if usize(z[4usize]) == 0usize { ret f64(cv[idx]) }
    if sd[idx] { ret 1.0f64 }
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fpc_dbscan.json")
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
