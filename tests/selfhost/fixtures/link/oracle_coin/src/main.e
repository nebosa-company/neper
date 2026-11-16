// e.algo.stat.coinpkg against coin asymptotic tests. tests/oracle/coin.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R coin`; the layout is at the top of scripts/r_oracle/groups/coin.R.

use e.algo.stat.coinpkg as cn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let kind = usize(z[1usize])
    let k = usize(z[2usize])
    let y = z[3usize..3usize + n]
    let g = z[3usize + n..3usize + 2usize * n]
    var s = 0.0f64
    var p = 0.0f64
    if kind == 4usize {
        let (s1, p1) = cn.kruskal(a, y, g, k)
        s = s1
        p = p1
    } else if kind == 5usize {
        let (s1, p1) = cn.spearman(a, g, y)
        s = s1
        p = p1
    } else {
        let (s1, p1) = cn.two_sample(a, y, g, kind)
        s = s1
        p = p1
    }
    if str.eq(c.name, "stat") { ret s }
    ret p
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/coin.json")
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
