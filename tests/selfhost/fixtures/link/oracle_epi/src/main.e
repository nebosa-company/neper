// e.algo.stat.epi against Epi::twoby2. tests/oracle/epi.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R epi`; the layout is at the top of scripts/r_oracle/groups/epi.R.

use e.algo.stat.epi as ei
use e.algo.stat.epir as ep
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    let a = x[0usize]
    let b = x[1usize]
    let cc = x[2usize]
    let d = x[3usize]
    let w = usize(x[4usize])
    let z = 1.959963984540054f64
    if w < 3usize {
        let (e, lo, hi) = ei.bin_ci(a, a + b, z)
        if w == 0usize { ret e }
        if w == 1usize { ret lo }
        ret hi
    }
    if w < 6usize {
        let (e, lo, hi) = ei.bin_ci(cc, cc + d, z)
        if w == 3usize { ret e }
        if w == 4usize { ret lo }
        ret hi
    }
    let t = ep.Table2 { a: a, b: b, c: cc, d: d }
    if w < 9usize {
        let (e, lo, hi) = ep.risk_ratio(t, 0.95f64)
        if w == 6usize { ret e }
        if w == 7usize { ret lo }
        ret hi
    }
    if w < 12usize {
        let (e, lo, hi) = ep.odds_ratio(t, 0.95f64)
        if w == 9usize { ret e }
        if w == 10usize { ret lo }
        ret hi
    }
    if w < 15usize {
        let (e, lo, hi) = ei.newcombe(a, a + b, cc, cc + d, z)
        if w == 12usize { ret e }
        if w == 13usize { ret lo }
        ret hi
    }
    if w == 15usize { ret ei.asymptotic_p(a, b, cc, d) }
    ret ei.fisher_p(a, b, cc, d)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/epi.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
