// e.algo.stat.dpill against KernSmooth dpill and bkde2D. tests/oracle/dpill.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dpill`; the layout is at the top of scripts/r_oracle/groups/dpill.R.

use e.algo.stat.dpill as dp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    if str.eq(c.name, "dpill") {
        let x = z[1usize..1usize + n]
        let y = z[1usize + n..1usize + 2usize * n]
        let p = 1usize + 2usize * n
        let m = usize(z[p + 4usize])
        let (h, e) = dp.dpill(a, x, y, z[p], z[p + 1usize], z[p + 2usize], z[p + 3usize], m, nan, nan)
        if e != ok { ret nan }
        ret h
    }
    let h1 = z[1usize]
    let h2 = z[2usize]
    let m1 = usize(z[3usize])
    let m2 = usize(z[4usize])
    let x = z[5usize..5usize + 2usize * n]
    let q = usize(z[5usize + 2usize * n])
    var lo1 = x[0usize]
    var hi1 = x[0usize]
    var lo2 = x[1usize]
    var hi2 = x[1usize]
    var i = 0usize
    while i < n {
        if x[2usize * i] < lo1 { lo1 = x[2usize * i] }
        if x[2usize * i] > hi1 { hi1 = x[2usize * i] }
        if x[2usize * i + 1usize] < lo2 { lo2 = x[2usize * i + 1usize] }
        if x[2usize * i + 1usize] > hi2 { hi2 = x[2usize * i + 1usize] }
        i += 1usize
    }
    let (fh, fe) = mem.alloc[f64](a, m1 * m2)
    if fe != ok { ret nan }
    if dp.bkde2d(a, x, n, h1, h2, m1, m2, lo1 - 1.5f64 * h1, hi1 + 1.5f64 * h1, lo2 - 1.5f64 * h2, hi2 + 1.5f64 * h2, fh) != ok { ret nan }
    var s = 0.0f64
    var mx = 0.0f64
    i = 0usize
    while i < m1 * m2 {
        if q == 0usize { s += fh[i] }
        if q == 1usize { s += f64(i + 1usize) * fh[i] }
        if fh[i] > mx { mx = fh[i] }
        i += 1usize
    }
    if q == 2usize { ret mx }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dpill.json")
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
