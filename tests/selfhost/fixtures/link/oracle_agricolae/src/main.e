// e.algo.stat.agricolae against agricolae. tests/oracle/agricolae.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R agricolae`; the layout is at the top of scripts/r_oracle/groups/agricolae.R.

use e.algo.stat.agricolae as ag
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let k = usize(x[2usize])
    let y = x[3usize..3usize + n]
    let (grp, e1) = mem.alloc[usize](a, n)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        grp[i] = usize(x[3usize + n + i])
        i += 1usize
    }
    let (mean, e2) = mem.alloc[f64](a, k)
    if e2 != ok { os.exit(6) }
    let (size, e3) = mem.alloc[f64](a, k)
    if e3 != ok { os.exit(7) }
    let w = ag.one_way(y, grp, k, mean, size)
    var s = 0.0f64
    var pos = 1usize
    var p = 0usize
    while p < k {
        var q = p + 1usize
        while q < k {
            let (d, pv, lo, hi) = ag.pairwise(w, mean, size, p, q, kind, 0.05f64)
            var v = d
            if str.eq(c.name, "p") { v = pv }
            if str.eq(c.name, "lcl") { v = lo }
            if str.eq(c.name, "ucl") { v = hi }
            s += v * f64(pos)
            pos += 1usize
            q += 1usize
        }
        p += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/agricolae.json")
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
