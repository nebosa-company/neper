// e.algo.stat.unmarkedpkg's occupancy model against unmarked::occu. tests/oracle/unmarked.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R unmarked`; the layout is at the top of scripts/r_oracle/groups/unmarked.R.

use e.algo.stat.unmarkedpkg as um
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let mm = usize(z[0usize])
    let jj = usize(z[1usize])
    let p1 = usize(z[2usize])
    let p2 = usize(z[3usize])
    let y0 = 4usize
    let x0 = y0 + mm * jj
    let z0 = x0 + mm * p1
    let (out, e1) = mem.alloc[f64](a, p1 + p2 + 1usize)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    if !um.occu(a, z[x0..x0 + mm * p1], z[z0..z0 + mm * p2], z[y0..y0 + mm * jj], mm, jj, p1, p2, out) { ret 0.0f64 / 0.0f64 }
    ret out[usize(z[z0 + mm * p2])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/unmarked.json")
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
