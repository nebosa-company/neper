// e.algo.stat.lpsolvepkg's lp_sens against lpSolve's compute.sens output. tests/oracle/lpsolve_sens.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lpsolve_sens`; the layout is at the top of scripts/r_oracle/groups/lpsolve_sens.R.

use e.algo.stat.lpsolvepkg as lps
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let m = usize(z[1usize])
    let mx = usize(z[2usize]) == 1usize
    let (x, e0) = mem.alloc[f64](a, n)
    let (du, e1) = mem.alloc[f64](a, m + n)
    let (df, e2) = mem.alloc[f64](a, m + n)
    let (dt, e3) = mem.alloc[f64](a, m + n)
    let (cf, e4) = mem.alloc[f64](a, n)
    let (ct, e5) = mem.alloc[f64](a, n)
    let (geq, e6) = mem.alloc[bool](a, m)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok { ret nan }
    var i = 0usize
    while i < m {
        geq[i] = !mx
        i += 1usize
    }
    let (v, e) = lps.lp_sens(a, z[3usize..3usize + n], z[3usize + n..3usize + n + m * n], z[3usize + n + m * n..3usize + n + m * n + m], m, n, geq, mx, x, du, df, dt, cf, ct)
    let _ = v
    if e != ok { ret nan }
    let field = usize(z[3usize + n + m * n + m])
    let k = usize(z[3usize + n + m * n + m + 1usize]) - 1usize
    if field == 0usize { ret du[k] }
    if field == 1usize { ret df[k] }
    if field == 2usize { ret dt[k] }
    if field == 3usize { ret cf[k] }
    ret ct[k]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lpsolve_sens.json")
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
