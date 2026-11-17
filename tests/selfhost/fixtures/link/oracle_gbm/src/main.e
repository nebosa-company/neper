// e.algo.stat.gbmpkg against gbm. tests/oracle/gbm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gbm`; the layout is at the top of scripts/r_oracle/groups/gbm.R.

use e.algo.stat.gbmpkg as gb
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (f, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan }
    let xm = z[8usize + n..8usize + n + n * p]
    let y = z[8usize..8usize + n]
    var ge = ok
    if c.name[0usize] == 98u8 {
        ge = gb.bernoulli(a, xm, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), f)
    } else if c.name[0usize] == 112u8 {
        ge = gb.poisson(a, xm, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), f)
    } else {
        ge = gb.gaussian(a, xm, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), f)
    }
    if ge != ok { ret nan }
    ret f[usize(z[6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gbm.json")
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
