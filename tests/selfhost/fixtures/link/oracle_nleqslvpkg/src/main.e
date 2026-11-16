// e.algo.stat.nleqslvpkg against nleqslv and multiroot. tests/oracle/nleqslvpkg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nleqslvpkg`; the layout is at the top of scripts/r_oracle/groups/nleqslvpkg.R.

use e.algo.stat.nleqslvpkg as nl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nleqslvpkg.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        if str.eq(c.name, "grad") || str.eq(c.name, "hess") {
            var gv = 0.0f64
            if str.eq(c.name, "hess") {
                var hs: [4]f64 = zero
                nl.fd_hessian(x[4usize..6usize], x[1usize] == 1.0f64, hs[0usize..4usize])
                gv = hs[usize(x[2usize]) * 2usize + usize(x[3usize])]
            } else {
                let fid = usize(x[0usize])
                let nxx = nl.poly_dim(fid)
                let nff = nl.poly_out(fid)
                var jb: [6]f64 = zero
                var xwb: [3]f64 = zero
                var f0b: [2]f64 = zero
                var f1b: [2]f64 = zero
                nl.fd_gradient(fid, x[4usize..4usize + nxx], x[1usize] == 1.0f64, jb[0usize..6usize], xwb[0usize..3usize], f0b[0usize..2usize], f1b[0usize..2usize])
                let _ = nff
                gv = jb[usize(x[2usize]) * nxx + usize(x[3usize])]
            }
            if !oracle.agrees(gv, c) {
                failures += 1usize
                if failures <= 12usize {
                    let _ = io.print(oracle.describe(a, c, gv))
                    let _ = io.print("\n")
                }
            }
            at += 1usize
            continue
        }
        let sys = usize(x[0usize])
        let n = nl.dim_of(sys)
        let (root, e1) = mem.alloc[f64](a, n)
        if e1 != ok { os.exit(5) }
        let iters = nl.solve(a, sys, x[2usize..2usize + n], root)
        var got = 0.0f64 - 1.0e9f64
        if iters > 0usize { got = root[usize(x[1usize])] }
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
