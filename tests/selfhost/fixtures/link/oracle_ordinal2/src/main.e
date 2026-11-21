// e.algo.stat.ordinalpkg against ordinal clm (flexible links) and clmm. tests/oracle/ordinal2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ordinal2`; the layout is at the top of scripts/r_oracle/groups/ordinal2.R.

use e.algo.stat.ordinalpkg as od
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
    let nk = usize(z[2usize])
    let link = usize(z[3usize])
    let (wts, ew) = mem.alloc[f64](a, n)
    if ew != ok { ret nan }
    var iw = 0usize
    while iw < n {
        wts[iw] = 1.0f64
        iw += 1usize
    }
    if c.name.len > 1usize && c.name[0usize] == 102u8 {
        let (par, e1) = mem.alloc[f64](a, nk + p)
        if e1 != ok { ret nan }
        let ll = od.clm_flex(a, z[4usize + n..4usize + n + n * p], z[4usize..4usize + n], wts, n, p, nk, link, par)
        if str.eq(c.name, "fll") { ret ll }
        var s = 0.0f64
        var i = 0usize
        if str.eq(c.name, "fth") {
            while i < nk - 1usize {
                s += par[i] * f64(i + 1usize)
                i += 1usize
            }
            ret s
        }
        if str.eq(c.name, "flam") { ret par[nk - 1usize + p] }
        while i < p {
            s += par[nk - 1usize + i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ordinal2.json")
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
