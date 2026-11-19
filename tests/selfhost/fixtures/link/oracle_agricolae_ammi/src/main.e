// e.algo.stat.agricolae AMMI against agricolae. tests/oracle/agricolae_ammi.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R agricolae_ammi`; the layout is at the top of scripts/r_oracle/groups/agricolae_ammi.R.

use e.algo.stat.agricolae as ag
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let ng = usize(x[0usize])
    let ne = usize(x[1usize])
    let what = usize(x[4usize])
    let idx = usize(x[5usize])
    let (r, e) = ag.ammi(a, x[6usize..6usize + ng * ne], ng, ne, x[2usize], x[3usize])
    if e != ok { os.exit(5) }
    if what == 0usize { ret r.percent[idx] }
    if what == 1usize { ret r.acum[idx] }
    if what == 2usize { ret r.df[idx] }
    if what == 3usize { ret r.ss[idx] }
    if what == 4usize { ret r.ms[idx] }
    if what == 5usize { ret r.f[idx] }
    if what == 6usize { ret r.p[idx] }
    if what == 7usize { ret r.scoreg[idx] }
    if what == 8usize { ret r.scoree[idx] }
    if what == 9usize { ret r.gmean[idx] }
    if what == 10usize { ret r.emean[idx] }
    ret f64(r.rows)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/agricolae_ammi.json")
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
