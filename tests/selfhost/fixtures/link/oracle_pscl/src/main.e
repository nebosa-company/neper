// e.algo.stat.psclpkg against pscl zeroinfl and hurdle. tests/oracle/pscl.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pscl`; the layout is at the top of scripts/r_oracle/groups/pscl.R.

use e.algo.stat.psclpkg as ps
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
    let q = usize(z[2usize])
    let kind = usize(z[3usize])
    let (par, e1) = mem.alloc[f64](a, p + q)
    if e1 != ok { ret nan }
    let y = z[4usize..4usize + n]
    let x = z[4usize + n..4usize + n + n * p]
    let zz = z[4usize + n + n * p..4usize + n + n * p + n * q]
    var ll = 0.0f64
    if kind == 0usize { ll = ps.zeroinfl(a, x, zz, y, n, p, q, par) } else { ll = ps.hurdle(a, x, zz, y, n, p, q, par) }
    if str.eq(c.name, "ll") { ret ll }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "secount") || str.eq(c.name, "sezero") {
        let (se, e2) = mem.alloc[f64](a, p + q)
        if e2 != ok { ret nan }
        if ps.standard_errors(a, kind, x, zz, y, n, p, q, par, se) != ok { ret nan }
        if str.eq(c.name, "secount") {
            while i < p {
                s += se[i] * f64(i + 1usize)
                i += 1usize
            }
        } else {
            while i < q {
                s += se[p + i] * f64(i + 1usize)
                i += 1usize
            }
        }
        ret s
    }
    if str.eq(c.name, "count") {
        while i < p {
            s += par[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    while i < q {
        s += par[p + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pscl.json")
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
