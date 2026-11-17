// e.algo.stat.ggdistpkg against ggdist. tests/oracle/ggdist.json comes from
// `R_ORACLE_LIB=<dir with ggdist first> Rscript scripts/r_oracle/generate.R ggdist`; the layout is at the top of scripts/r_oracle/groups/ggdist.R.

use e.algo.stat.ggdistpkg as gd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = x[1usize..1usize + n]
    let w = x[1usize + n]
    let (s, e) = gd.sorted_of(a, d)
    if e != ok { os.exit(4) }
    if str.eq(c.name, "qi_lo") || str.eq(c.name, "qi_hi") {
        let (lo, hi) = gd.qi(s, w)
        if str.eq(c.name, "qi_lo") { ret lo }
        ret hi
    }
    if str.eq(c.name, "hdci_lo") || str.eq(c.name, "hdci_hi") {
        let (lo, hi, he) = gd.hdci(a, s, w)
        if he != ok { os.exit(5) }
        if str.eq(c.name, "hdci_lo") { ret lo }
        ret hi
    }
    if str.eq(c.name, "mode") {
        let (m, me) = gd.mode_of(a, d, s)
        if me != ok { os.exit(6) }
        ret m
    }
    var out: [16]f64 = zero
    let (cnt, he) = gd.hdi(a, d, s, w, out[0usize..16usize])
    if he != ok { os.exit(7) }
    if str.eq(c.name, "hdi_n") { ret f64(cnt) }
    let row = usize(x[2usize + n])
    if str.eq(c.name, "hdi_lo") { ret out[2usize * row] }
    ret out[2usize * row + 1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ggdist.json")
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
