// e.algo.stat.logistf against logistf. tests/oracle/logistf.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R logistf`; the layout is at the top of scripts/r_oracle/groups/logistf.R.

use e.algo.stat.logistf as lf
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let which = usize(x[2usize])
    let y = x[3usize..3usize + n]
    let des = x[3usize + n..3usize + n + n * p]
    let (f, e) = lf.firth(a, des, y, n, p, p)
    if e != ok { os.exit(5) }
    if which < 10usize { ret f.beta[which] }
    if which < 20usize { ret math_sqrt(f.cov[(which - 10usize) * p + (which - 10usize)]) }
    if which < 30usize {
        let (pv, e2) = lf.prof_p(a, des, y, n, p, f.pll, which - 20usize)
        if e2 != ok { os.exit(6) }
        ret pv
    }
    if which == 30usize { ret f.pll }
    let (nl, e3) = lf.null_pll(a, des, y, n, p)
    if e3 != ok { os.exit(7) }
    ret nl
}

fn math_sqrt(v: f64) -> f64 {
    var g = v
    if g <= 0.0f64 { ret 0.0f64 }
    var i = 0usize
    while i < 80usize {
        g = 0.5f64 * (g + v / g)
        i += 1usize
    }
    ret g
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/logistf.json")
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
