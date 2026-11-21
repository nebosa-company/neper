// e.algo.stat.afexaov against afex aov_ez (Type III, any between and within factors, unequal cells). tests/oracle/afexaov.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R afexaov`; the argument layout is at the top of scripts/r_oracle/groups/afexaov.R.

use e.algo.stat.afexaov as af
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn slot(name: str) -> usize {
    if str.eq(name, "F") { ret 0usize }
    if str.eq(name, "dfn") { ret 1usize }
    if str.eq(name, "dfd") { ret 2usize }
    if str.eq(name, "p") { ret 3usize }
    if str.eq(name, "ges") { ret 4usize }
    if str.eq(name, "gg") { ret 5usize }
    if str.eq(name, "hf") { ret 6usize }
    if str.eq(name, "ggp") { ret 7usize }
    if str.eq(name, "hfp") { ret 8usize }
    if str.eq(name, "W") { ret 9usize }
    if str.eq(name, "pW") { ret 10usize }
    ret 11usize
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let s = usize(z[0usize])
    let t = usize(z[1usize])
    let n = usize(z[2usize])
    let nbf = usize(z[3usize])
    let nwf = usize(z[4usize])
    let (bl, e1) = mem.alloc[usize](a, nbf + 1usize)
    let (wl, e2) = mem.alloc[usize](a, nwf + 1usize)
    if e1 != ok { ret nan }
    if e2 != ok { ret nan }
    var ks = 1usize
    var i = 0usize
    while i < nbf {
        bl[i] = usize(z[5usize + i])
        i += 1usize
    }
    i = 0usize
    while i < nwf {
        wl[i] = usize(z[5usize + nbf + i])
        ks *= wl[i]
        i += 1usize
    }
    let from = 5usize + nbf + nwf
    let nt = 1usize << u64(nwf)
    let (out, e3) = mem.alloc[f64](a, (1usize << u64(nbf)) * nt * 12usize)
    if e3 != ok { ret nan }
    if af.anova(a, z[from..from + n * (nbf + ks)], n, nbf, bl, nwf, wl, out) != ok { ret nan }
    ret out[(s * nt + t) * 12usize + slot(c.name)]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/afexaov.json")
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
