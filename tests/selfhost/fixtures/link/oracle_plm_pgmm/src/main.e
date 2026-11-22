// e.algo.stat.plmgmm against plm::pgmm (difference and system GMM, Sargan, Arellano-Bond m1/m2, Wald, vcovHC). tests/oracle/plm_pgmm.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R plm_pgmm`; the argument layout is at the top of scripts/r_oracle/groups/plm_pgmm.R.

use e.algo.stat.plmgmm as pg
use e.io
use e.math
use e.math.nmath as nm
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn wse(vc: []const f64, k: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += math.sqrt[f64](vc[i * k + i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let h = 16usize
    var sp = pg.Spec{ nid: usize(z[0usize]), nt: usize(z[1usize]), kx: usize(z[2usize]), p: usize(z[3usize]), xq: usize(z[4usize]), gx: usize(z[5usize]), ya: usize(z[6usize]), yb: usize(z[7usize]), xa: usize(z[8usize]), xb: usize(z[9usize]), collapse: usize(z[10usize]), twoways: usize(z[11usize]), twosteps: usize(z[12usize]), ld: usize(z[13usize]), fsm: usize(z[14usize]) }
    let which = usize(z[15usize])
    let cells = sp.nid * sp.nt
    let (y, e1) = mem.alloc[f64](a, cells)
    let (x, e2) = mem.alloc[f64](a, cells * sp.kx + 1usize)
    let (gw, e3) = mem.alloc[pg.Gmm](a, 1usize)
    let (out, e4) = mem.alloc[f64](a, 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var i = 0usize
    while i < cells {
        y[i] = z[h + i]
        if y[i] < -99998.0f64 { y[i] = nan }
        i += 1usize
    }
    i = 0usize
    while i < cells * sp.kx {
        x[i] = z[h + cells + i]
        if x[i] < -99998.0f64 { x[i] = nan }
        i += 1usize
    }
    if pg.fit(a, &sp, y, x, &gw[0usize]) != ok { ret nan }
    let g = &gw[0usize]
    let kt = g.kt
    let (vr, e5) = mem.alloc[f64](a, kt * kt)
    if e5 != ok { ret nan }
    if pg.vcov_hc(a, g, vr) != ok { ret nan }
    if which == 0usize { ret wsum(g.coef, kt) }
    if which == 1usize { ret wse(vr, kt) }
    if which == 2usize { ret wse(g.vc, kt) }
    if which == 3usize || which == 14usize {
        if pg.sargan(a, g, 0usize, out) != ok { ret nan }
        if which == 3usize { ret out[0usize] }
        ret nm.pchisq(out[0usize], out[1usize], false, false)
    }
    if which == 4usize {
        if pg.sargan(a, g, 0usize, out) != ok { ret nan }
        ret out[1usize]
    }
    if which == 5usize {
        if pg.sargan(a, g, 1usize, out) != ok { ret nan }
        ret out[0usize]
    }
    if which == 6usize { ret pg.mtest(a, g, 1usize, vr) }
    if which == 7usize { ret pg.mtest(a, g, 2usize, vr) }
    if which == 8usize { ret pg.mtest(a, g, 1usize, g.vc) }
    if which == 9usize { ret pg.mtest(a, g, 2usize, g.vc) }
    if which == 10usize || which == 15usize {
        var to = kt
        if sp.twoways == 1usize { to = kt - g.kv }
        if pg.wald(a, g, 0usize, to, vr, out) != ok { ret nan }
        if which == 10usize { ret out[0usize] }
        ret nm.pchisq(out[0usize], out[1usize], false, false)
    }
    if which == 11usize {
        var to = kt
        if sp.twoways == 1usize { to = kt - g.kv }
        if pg.wald(a, g, 0usize, to, g.vc, out) != ok { ret nan }
        ret out[0usize]
    }
    if which == 12usize {
        var from = kt - g.kv
        if sp.ld == 1usize { from += 1usize }
        if pg.wald(a, g, from, kt, vr, out) != ok { ret nan }
        ret out[0usize]
    }
    if which == 13usize { ret wsum(g.coef1, kt) }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/plm_pgmm.json")
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
