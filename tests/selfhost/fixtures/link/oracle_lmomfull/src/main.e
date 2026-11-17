// e.algo.stat.lmomfull against lmom: lmr, qua, cdf and pel of every distribution, and samlmu with trimming.
// tests/oracle/lmomfull.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lmomfull`; the
// argument layouts are at the top of scripts/r_oracle/groups/lmomfull.R.

use e.algo.stat.lmomfull as lm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    var out: [32]f64 = zero
    if str.eq(c.name, "sam") {
        let nmom = usize(z[0usize])
        let n = usize(z[4usize])
        if lm.samlmu_trim(a, z[5usize..5usize + n], nmom, usize(z[1usize]), usize(z[2usize]), z[3usize] != 0.0f64, out[0usize..32usize]) != ok { ret nan }
        ret out[usize(z[5usize + n])]
    }
    let kind = i32(z[0usize])
    if str.eq(c.name, "lmr") {
        let np = usize(z[2usize])
        let r = lm.lmrx(kind, z[3usize..3usize + np], usize(z[1usize]), out[0usize..32usize])
        if r != 0i32 { ret nan }
        ret out[usize(z[3usize + np])]
    }
    if str.eq(c.name, "qua") {
        let np = usize(z[2usize])
        ret lm.quax(kind, z[1usize], z[3usize..3usize + np])
    }
    if str.eq(c.name, "cdf") {
        let np = usize(z[2usize])
        ret lm.cdfx(kind, z[1usize], z[3usize..3usize + np])
    }
    let nl = usize(z[3usize])
    var bound = nan
    if z[1usize] != 0.0f64 { bound = z[2usize] }
    let r = lm.pelx(kind, z[4usize..4usize + nl], bound, out[0usize..32usize])
    if r == 7000i32 || r == 7010i32 { ret nan }
    if r == 2i32 || r >= 4i32 && r < 7000i32 { ret nan }
    ret out[usize(z[4usize + nl])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lmomfull.json")
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
