// e.algo.stat.tsne against Rtsne with theta = 0. tests/oracle/tsne.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R tsne`; the layout is at the top of scripts/r_oracle/groups/tsne.R.

use e.algo.stat.tsne as ts
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let dims = usize(x[2usize])
    let (y, e1) = mem.alloc[f64](a, n * dims)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n * dims {
        y[i] = x[11usize + n * d + i]
        i += 1usize
    }
    if ts.tsne_exact(a, x[11usize..11usize + n * d], n, d, dims, x[3usize], y, usize(x[4usize]), usize(x[5usize]), usize(x[6usize]), x[7usize], x[8usize], x[9usize], x[10usize], x[11usize + n * d + n * dims + 1usize] != 0.0f64) != ok { os.exit(6) }
    ret y[usize(x[11usize + n * d + n * dims])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/tsne.json")
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
            if failures <= 6usize {
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
