// e.algo.stat.hoslem against ResourceSelection::hoslem.test. tests/oracle/hoslem.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hoslem`; the layout is at the top of
// scripts/r_oracle/groups/hoslem.R.

use e.algo.stat.hoslem as hl
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if c.name[0usize] == 99u8 { ret hl.caic(z[0usize], z[1usize], z[2usize], z[3usize]) }
    if c.name[0usize] == 119u8 {
        let wn = usize(z[0usize])
        let wp = usize(z[1usize])
        let (wo, we) = mem.alloc[f64](a, 8usize * wp)
        if we != ok { ret nan }
        if hl.wrsi(a, z[2usize..2usize + wn], z[2usize + wn..2usize + wn + wn * wp], wn, wp, wo) != ok { ret nan }
        ret wo[usize(z[2usize + wn + wn * wp])]
    }
    let g = usize(z[0usize])
    let n = usize(z[1usize])
    let y = z[2usize..2usize + n]
    let yh = z[2usize + n..2usize + 2usize * n]
    let q = usize(z[2usize + 2usize * n])
    let (o0, e1) = mem.alloc[f64](a, g + 1usize)
    let (o1, e2) = mem.alloc[f64](a, g + 1usize)
    let (x0, e3) = mem.alloc[f64](a, g + 1usize)
    let (x1, e4) = mem.alloc[f64](a, g + 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    let (r, e) = hl.hoslem(a, y, yh, g, o0, o1, x0, x1)
    if e != ok { ret nan }
    if q == 0usize { ret r.chisq }
    if q == 1usize { ret r.df }
    if q == 2usize { ret r.pvalue }
    let big = r.bins
    let t = q - 3usize
    if t < big { ret o0[t] }
    if t < 2usize * big { ret o1[t - big] }
    if t < 3usize * big { ret x0[t - 2usize * big] }
    ret x1[t - 3usize * big]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hoslem.json")
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
