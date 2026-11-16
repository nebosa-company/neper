// e.ml.cluster.density (kNNdist and lof) against dbscan. tests/oracle/dbscanpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dbscanpkg`; the layout is at the top of scripts/r_oracle/groups/dbscanpkg.R.

use e.io
use e.ml.cluster.density as dn
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let p = usize(x[2usize])
    let row = usize(x[3usize])
    let pts = x[4usize..4usize + n * d]
    let (o, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(5) }
    let (kd, e2) = mem.alloc[f64](a, n)
    if e2 != ok { os.exit(6) }
    let (lr, e3) = mem.alloc[f64](a, n)
    if e3 != ok { os.exit(7) }
    let (sc, e4) = mem.alloc[f64](a, n)
    if e4 != ok { os.exit(8) }
    if str.eq(c.name, "knnd") {
        dn.knn_distance(pts, n, d, p, o, sc)
        ret o[row]
    }
    dn.lof(pts, n, d, p, o, kd, lr, sc)
    ret o[row]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dbscanpkg.json")
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
