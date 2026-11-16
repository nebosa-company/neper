// e.algo.stat.boot against boot: the ordinary bootstrap of the mean, median, sd and variance under
// set.seed, and boot.ci norm, basic, perc and bca. tests/oracle/boot.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R boot`; the layout is at the top of
// scripts/r_oracle/groups/boot.R.

use e.algo.rand.r as rr
use e.algo.stat.boot as bt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[0usize]))
    let kind = u8(x[1usize])
    let nrep = usize(x[2usize])
    let conf = x[3usize]
    let n = usize(x[4usize])
    let data = x[5usize..5usize + n]
    let (b, e) = bt.boot(a, &g, data, kind, nrep)
    if e != ok { os.exit(6) }
    if str.eq(c.name, "t0") { ret b.t0 }
    if str.eq(c.name, "t") { ret b.t[usize(x[x.len - 1usize])] }
    if str.eq(c.name, "tsum") {
        var s = 0.0f64
        var i = 0usize
        while i < b.t.len {
            s += b.t[i]
            i += 1usize
        }
        ret s
    }
    var ck = 0u8
    if str.eq(c.name[3usize..8usize], "basic") { ck = 1u8 }
    if str.eq(c.name[3usize..7usize], "perc") { ck = 2u8 }
    if str.eq(c.name[3usize..6usize], "bca") { ck = 3u8 }
    let (lo, hi, ce) = bt.boot_ci(a, &b, data, ck, kind, conf)
    if ce != ok {
        if ce == bt.NotFiniteA { os.exit(31) }
        if ce == bt.NotFinite { os.exit(32) }
        os.exit(33)
        os.exit(7)
    }
    if str.eq(c.name[c.name.len - 2usize..c.name.len], "lo") { ret lo }
    ret hi
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/boot.json")
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
