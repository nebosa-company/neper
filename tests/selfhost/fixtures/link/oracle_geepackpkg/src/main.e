// e.algo.stat.geepackpkg against geepack. tests/oracle/geepackpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R geepackpkg`; the layout is at the top of scripts/r_oracle/groups/geepackpkg.R.

use e.algo.stat.geepackpkg as gp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/geepackpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let k = usize(x[3usize])
        let m = usize(x[4usize])
        let p = usize(x[5usize])
        let n = k * m
        let (beta, e1) = mem.alloc[f64](a, p)
        if e1 != ok { os.exit(5) }
        let (vb, e2) = mem.alloc[f64](a, p * p)
        if e2 != ok { os.exit(6) }
        let (phi, alpha, e3) = gp.geeglm_gaussian(a, x[6usize..6usize + n], x[6usize + n..6usize + n + n * p], k, m, p, x[2usize] == 1.0f64, beta, vb)
        if e3 != ok { os.exit(7) }
        var got = 0.0f64
        let what = usize(x[0usize])
        let idx = usize(x[1usize])
        if what == 0usize { got = beta[idx] }
        if what == 1usize { got = vb[idx] }
        if what == 2usize { got = phi }
        if what == 3usize { got = alpha }
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
