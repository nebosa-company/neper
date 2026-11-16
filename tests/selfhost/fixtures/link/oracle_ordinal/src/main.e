// e.algo.stat.ordinalpkg against ordinal clm. tests/oracle/ordinal.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ordinal`; the layout is at the top of scripts/r_oracle/groups/ordinal.R.

use e.algo.stat.ordinalpkg as od
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let nk = usize(z[2usize])
    let link = usize(z[3usize])
    let (par, e1) = mem.alloc[f64](a, nk - 1usize + p)
    if e1 != ok { ret nan }
    let ll = od.clm(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], n, p, nk, link, par)
    if str.eq(c.name, "ll") { ret ll }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "theta") {
        while i < nk - 1usize {
            s += par[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    while i < p {
        s += par[nk - 1usize + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ordinal.json")
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
