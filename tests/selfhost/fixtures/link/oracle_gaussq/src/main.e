// e.algo.stat.gaussq against statmod: gauss.quad and gauss.quad.prob. tests/oracle/gaussq.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gaussq`; the layout is at the top of
// scripts/r_oracle/groups/gaussq.R.

use e.algo.stat.gaussq as gq
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let id = usize(z[0usize])
    let n = usize(z[1usize])
    let p1 = z[2usize]
    let p2 = z[3usize]
    let i = usize(z[6usize])
    let (nodes, e1) = mem.alloc[f64](a, n)
    let (w, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    var good = false
    if id < 10usize {
        good = gq.gauss_quad(a, n, u8(id), p1, p2, nodes, w)
    } else {
        let d = u8(id - 10usize)
        good = gq.gauss_quad_prob(a, n, d, p1, p2, p1, p2, p1, p2, nodes, w)
    }
    if !good { ret nan }
    if str.eq(c.name, "node") { ret nodes[i] }
    ret w[i]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gaussq.json")
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
