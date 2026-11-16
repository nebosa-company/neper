// e.algo.stat.boot, balanced and parametric simulation, against boot under set.seed. tests/oracle/boot2.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R boot2`; the layout is at the top of
// scripts/r_oracle/groups/boot2.R.

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
    let sim = usize(x[1usize])
    let kind = u8(x[2usize])
    let nrep = usize(x[3usize])
    let conf = x[4usize]
    let n = usize(x[5usize])
    let data = x[6usize..6usize + n]
    var b: bt.Boot = zero
    var e = ok
    if sim == 0usize {
        let (bb, be) = bt.boot_balanced(a, &g, data, kind, nrep)
        b = bb
        e = be
    } else {
        let (bb, be) = bt.boot_parametric_norm(a, &g, data, kind, nrep, x[6usize + n], x[7usize + n])
        b = bb
        e = be
    }
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
    if ce != ok { os.exit(33) }
    if str.eq(c.name[c.name.len - 2usize..c.name.len], "lo") { ret lo }
    ret hi
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/boot2.json")
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
