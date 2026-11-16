// e.algo.stat.gparot varimax_stats and promax_stats against stats::varimax and stats::promax.
// tests/oracle/promax.json comes from `Rscript scripts/r_oracle/generate.R promax`; the layout is at the top of
// scripts/r_oracle/groups/promax.R.

use e.algo.stat.gparot as gp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let kind = usize(z[0usize])
    let p = usize(z[1usize])
    let k = usize(z[2usize])
    let m = z[3usize]
    let l = z[4usize..4usize + p * k]
    let q = usize(z[4usize + p * k])
    var ld: []f64 = zero
    var rot: []f64 = zero
    var e = ok
    if kind == 0usize {
        let (a1, b1, e1) = gp.varimax_stats(a, l, p, k, true, 1.0e-5f64)
        ld = a1
        rot = b1
        e = e1
    } else {
        let (a1, b1, e1) = gp.promax_stats(a, l, p, k, m)
        ld = a1
        rot = b1
        e = e1
    }
    if e != ok { ret nan }
    if q < p * k { ret ld[q] }
    ret rot[q - p * k]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/promax.json")
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
