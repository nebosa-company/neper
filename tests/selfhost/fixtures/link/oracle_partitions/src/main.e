// e.algo.parts against partitions: P, Q, parts, restrictedparts, diffparts. tests/oracle/partitions.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R partitions`; the layout is at the top of
// scripts/r_oracle/groups/partitions.R.

use e.algo.parts as pt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let m = usize(x[2usize])
    if kind <= 1usize {
        let (v, e) = pt.count(a, n, kind == 1usize)
        if e != ok { ret 0.0f64 / 0.0f64 }
        ret v
    }
    let cap = 400000usize
    let (out, oe) = mem.alloc[f64](a, cap)
    if oe != ok { ret 0.0f64 / 0.0f64 }
    var cols = 0usize
    var rows = n
    var ce = ok
    if kind >= 5usize {
        rows = m
        let (cc, e) = pt.compositions(a, n, m, kind == 5usize, out)
        cols = cc
        ce = e
    } else if kind == 2usize {
        let (cc, e) = pt.parts(a, n, out)
        cols = cc
        ce = e
    } else if kind == 3usize {
        rows = m
        let (cc, e) = pt.by_length(a, n, m, m, false, out)
        cols = cc
        ce = e
    } else {
        rows = 0usize
        while (rows + 1usize) * (rows + 2usize) / 2usize <= n { rows += 1usize }
        let (cc, e) = pt.by_length(a, n, rows, rows, true, out)
        cols = cc
        ce = e
    }
    if ce != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "cols") { ret f64(cols) }
    var s = 0.0f64
    var i = 0usize
    while i < cols * rows {
        if str.eq(c.name, "sum") { s += out[i] } else { s += f64(i + 1usize) * out[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/partitions.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
