// e.algo.stat.rootsolvefull against rootSolve::steady (stode) and jacobian.full. tests/oracle/rootsolvefull.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rootsolvefull`; the case layouts are at the top of scripts/r_oracle/groups/rootsolvefull.R.

use e.algo.stat.rootsolvefull as rs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rootsolvefull.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let x = c.args
        let sid = usize(x[0usize])
        let n = rs.dim_of(sid)
        var got = 0.0f64
        if str.eq(c.name, "jacfull") {
            let np = usize(x[4usize])
            let (jac, e1) = mem.alloc[f64](a, n * n)
            if e1 != ok { os.exit(5) }
            rs.jacobian_full(a, sid, x[5usize..5usize + np], x[5usize + np..5usize + np + n], x[3usize], jac)
            got = jac[usize(x[1usize]) * n + usize(x[2usize])]
        } else {
            let np = usize(x[7usize])
            let (y, e2) = mem.alloc[f64](a, n)
            if e2 != ok { os.exit(5) }
            var i = 0usize
            while i < n {
                y[i] = x[8usize + np + i]
                i += 1usize
            }
            let (iter, steady, prec) = rs.stode(a, sid, x[8usize..8usize + np], y, x[3usize], x[4usize], x[5usize], usize(x[6usize]), x[2usize] != 0.0f64)
            if str.eq(c.name, "stode_y") { got = y[usize(x[1usize])] }
            if str.eq(c.name, "stode_iter") { got = f64(iter) }
            if str.eq(c.name, "stode_ok") { got = f64(steady) }
            if str.eq(c.name, "stode_prec") { got = prec }
            if str.eq(c.name, "mroot_f") {
                let (fv, e3) = mem.alloc[f64](a, n)
                if e3 != ok { os.exit(5) }
                rs.rhs(sid, x[8usize..8usize + np], y, fv)
                got = fv[usize(x[1usize])]
            }
        }
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
