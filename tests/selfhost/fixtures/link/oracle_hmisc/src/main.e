// e.algo.stat.hmisc against Hmisc: binconf, wtd.mean, wtd.var and somers2. tests/oracle/hmisc.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hmisc`; the layout is at the top of
// scripts/r_oracle/groups/hmisc.R.

use e.algo.stat.hmisc as hm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "wq") {
        let n = usize(x[0usize])
        let k = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, k)
        if e != ok { ret nan }
        if hm.wtd_quantile(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[3usize + 2usize * n..3usize + 2usize * n + k], o) != ok { ret nan }
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "hdq") {
        let n = usize(x[0usize])
        ret hm.hd_quantile(a, x[2usize..2usize + n], x[1usize])
    }
    if str.eq(c.name, "rc") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, 2usize)
        if e != ok { ret nan }
        if hm.rcorr_pair(a, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], x[1usize] == 1.0f64, o) != ok { ret nan }
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "cut") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, usize(x[1usize]) + 2usize)
        if e != ok { ret nan }
        let cnt = hm.cut2_cuts(a, x[3usize..3usize + n], usize(x[1usize]), o)
        if x[2usize] < 0.0f64 { ret f64(cnt) }
        ret o[usize(x[2usize])]
    }
    if str.eq(c.name, "axt") {
        let n = usize(x[0usize])
        ret hm.approx_extrap(x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], x[1usize])
    }
    if str.eq(c.name, "rcc") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, 7usize)
        if e != ok { ret nan }
        hm.rcorr_cens(x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], x[2usize + 2usize * n..2usize + 3usize * n], o)
        ret o[usize(x[1usize])]
    }
    if str.eq(c.name, "wrk") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { ret nan }
        if hm.wtd_rank(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], o) != ok { ret nan }
        ret o[usize(x[1usize])]
    }
    if str.eq(c.name, "rcs") {
        let n = usize(x[0usize])
        let nk = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, n * (nk - 2usize))
        if e != ok { ret nan }
        hm.rcspline_eval(x[4usize..4usize + n], x[4usize + n..4usize + n + nk], usize(x[2usize]), o)
        ret o[usize(x[3usize])]
    }
    if str.eq(c.name, "bc_lo") || str.eq(c.name, "bc_hi") {
        let (lo, hi) = hm.binconf(x[0usize], x[1usize], x[2usize], u8(x[3usize]))
        if str.eq(c.name, "bc_lo") { ret lo }
        ret hi
    }
    let n = usize(x[0usize])
    if str.eq(c.name, "wmean") { ret hm.wtd_mean(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n]) }
    if str.eq(c.name, "wvar") { ret hm.wtd_var(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n]) }
    let (cc, d) = hm.somers2(x[1usize..1usize + n], x[1usize + n..1usize + 2usize * n])
    if str.eq(c.name, "c") { ret cc }
    ret d
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hmisc.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let start = mem.mark(a)
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
