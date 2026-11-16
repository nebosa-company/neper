// e.algo.stat.surveypkg against survey svymean, svytotal and svyratio. tests/oracle/survey.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R survey`; the layout is at the top of scripts/r_oracle/groups/survey.R.

use e.algo.stat.surveypkg as sv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let nh = usize(z[1usize])
    let np = usize(z[2usize])
    let (out, e1) = mem.alloc[f64](a, 6usize)
    if e1 != ok { ret nan }
    let o = 3usize
    if sv.estimates(a, z[o..o + n], z[o + n..o + 2usize * n], z[o + 2usize * n..o + 3usize * n], z[o + 3usize * n..o + 4usize * n], z[o + 4usize * n..o + 5usize * n], z[o + 5usize * n..o + 5usize * n + nh], nh, np, out) != ok { ret nan }
    if str.eq(c.name, "mean") { ret out[0usize] }
    if str.eq(c.name, "semean") { ret out[1usize] }
    if str.eq(c.name, "total") { ret out[2usize] }
    if str.eq(c.name, "setotal") { ret out[3usize] }
    if str.eq(c.name, "ratio") { ret out[4usize] }
    ret out[5usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/survey.json")
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
