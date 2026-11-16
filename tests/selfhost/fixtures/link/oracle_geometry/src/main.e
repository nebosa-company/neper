// e.algo.stat.geometrypkg against geometry convhulln. tests/oracle/geometry.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R geometry`; the layout is at the top of scripts/r_oracle/groups/geometry.R.

use e.algo.stat.geometrypkg as gm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let d = usize(z[1usize])
    var out: [3]f64 = zero
    if d == 2usize { gm.hull2(z[2usize..2usize + n * 2usize], n, out[0usize..3usize]) } else { gm.hull3(z[2usize..2usize + n * 3usize], n, out[0usize..3usize]) }
    if str.eq(c.name, "facets") { ret out[0usize] }
    if str.eq(c.name, "boundary") { ret out[1usize] }
    ret out[2usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/geometry.json")
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
