// e.algo.stat.matchitpkg against MatchIt nearest-neighbour matching. tests/oracle/matchit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R matchit`; the layout is at the top of scripts/r_oracle/groups/matchit.R.

use e.algo.stat.matchitpkg as mt
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
    let (w, e1) = mem.alloc[f64](a, n)
    let (ps, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    if mt.nearest(a, z[3usize + n..3usize + n + n * p], z[3usize..3usize + n], n, p, usize(z[2usize]), w, ps) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        if str.eq(c.name, "nmatched") {
            if w[i] > 0.0f64 { s += 1.0f64 }
        } else {
            s += w[i] * f64(i + 1usize)
        }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/matchit.json")
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
