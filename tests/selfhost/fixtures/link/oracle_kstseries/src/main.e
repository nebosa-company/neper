// e.algo.stat.kstseries against KernSmooth (bkde, dpik) and tseries (jarque.bera.test, runs.test).
// tests/oracle/kstseries.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// kstseries`; the layout is at the top of scripts/r_oracle/groups/kstseries.R.

use e.algo.stat.kstseries as ks
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn stat_of(v: []const f64, j: u8) -> f64 {
    if j == 0u8 { ret v[0usize] }
    if j == 1u8 { ret v[v.len - 1usize] }
    if j == 4u8 { ret f64(v.len) }
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if j == 2u8 { s += v[i] } else { s += f64(i + 1usize) * v[i] }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "dpik") {
        let n = usize(x[0usize])
        let (h, e) = ks.dpik(a, x[1usize..1usize + n])
        if e != ok { os.exit(6) }
        ret h
    }
    if str.eq(c.name, "jb_stat") || str.eq(c.name, "jb_p") {
        let n = usize(x[0usize])
        let (s, p) = ks.jarque_bera(x[1usize..1usize + n])
        if str.eq(c.name, "jb_stat") { ret s }
        ret p
    }
    if str.eq(c.name, "runs_stat") || str.eq(c.name, "runs_p") {
        let n = usize(x[0usize])
        let (bits, be) = mem.alloc[i64](a, n)
        if be != ok { os.exit(5) }
        var i = 0usize
        while i < n {
            bits[i] = i64(x[1usize + i])
            i += 1usize
        }
        let (s, p) = ks.runs_test(bits)
        if str.eq(c.name, "runs_stat") { ret s }
        ret p
    }
    let n = usize(x[3usize])
    let (gx, gy, e) = ks.bkde(a, x[4usize..4usize + n], u8(x[0usize]), x[1usize], usize(x[2usize]))
    if e != ok { os.exit(7) }
    let j = u8(x[x.len - 1usize])
    if str.eq(c.name, "bkde_x") { ret stat_of(gx, j) }
    ret stat_of(gy, j)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kstseries.json")
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
