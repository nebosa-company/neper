// e.algo.stat.hetgppkg against hetGP mleHomGP with known hyperparameters. tests/oracle/hetgp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hetgp`; the layout is at the top of scripts/r_oracle/groups/hetgp.R.

use e.algo.stat.hetgppkg as hg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let d = usize(z[1usize])
    let m = usize(z[2usize])
    let (out, e1) = mem.alloc[f64](a, 3usize + 3usize * m)
    if e1 != ok { ret nan }
    var o = 4usize
    let theta = z[o..o + d]
    o += d
    let x = z[o..o + n * d]
    o += n * d
    let y = z[o..o + n]
    o += n
    let xt = z[o..o + m * d]
    if hg.homgp(a, x, y, n, d, theta, z[3usize], xt, m, out) != ok { ret nan }
    if str.eq(c.name, "beta0") { ret out[0usize] }
    if str.eq(c.name, "nu") { ret out[1usize] }
    if str.eq(c.name, "ll") { ret out[2usize] }
    var blk = 0usize
    if str.eq(c.name, "sd2") { blk = 1usize }
    if str.eq(c.name, "nugs") { blk = 2usize }
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += out[3usize + blk * m + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hetgp.json")
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
