// e.algo.stat.flexsurvpkg against flexsurv flexsurvreg. tests/oracle/flexsurv.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R flexsurv`; the layout is at the top of scripts/r_oracle/groups/flexsurv.R.

use e.algo.stat.flexsurvpkg as fl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let model = usize(z[2usize])
    var q = 2usize + k
    if model == 1usize { q = 1usize + k }
    let (par, e1) = mem.alloc[f64](a, q)
    if e1 != ok { ret nan }
    let ll = fl.fit(a, model, z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], z[3usize + 2usize * n..3usize + 2usize * n + n * k], n, k, par)
    if str.eq(c.name, "ll") { ret ll }
    var s = 0.0f64
    var i = 0usize
    while i < q {
        s += par[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/flexsurv.json")
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
