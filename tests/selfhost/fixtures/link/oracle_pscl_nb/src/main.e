// e.algo.stat.psclpkg's negative binomial zeroinfl against pscl. tests/oracle/pscl_nb.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pscl_nb`; the layout is at the top of scripts/r_oracle/groups/pscl_nb.R.

use e.algo.stat.psclpkg as ps
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let q = usize(z[2usize])
    let (par, e1) = mem.alloc[f64](a, p + q + 1usize)
    if e1 != ok { ret nan }
    if str.eq(c.name, "gzse") {
        let yg = z[3usize..3usize + n]
        let xg = z[3usize + n..3usize + n + n * p]
        let zg = z[3usize + n + n * p..3usize + n + n * p + n * q]
        let lg = ps.zeroinfl_geom(a, xg, zg, yg, n, p, q, par)
        if lg != lg { ret nan }
        let (se, e6) = mem.alloc[f64](a, p + q)
        if e6 != ok { ret nan }
        if ps.zeroinfl_geom_se(a, xg, zg, yg, n, p, q, par, se) != ok { ret nan }
        var t = 0.0f64
        var u = 0usize
        while u < p + q {
            t += se[u] * f64(u + 1usize)
            u += 1usize
        }
        ret t
    }
    if str.eq(c.name, "lkse") {
        let lnk = usize(z[3usize])
        let y2 = z[5usize..5usize + n]
        let x2 = z[5usize + n..5usize + n + n * p]
        let z2 = z[5usize + n + n * p..5usize + n + n * p + n * q]
        let (wv, e7) = mem.alloc[f64](a, n)
        let (ov, e8) = mem.alloc[f64](a, n)
        let (se, e9) = mem.alloc[f64](a, p + q)
        if e7 != ok || e8 != ok || e9 != ok { ret nan }
        var u = 0usize
        while u < n {
            wv[u] = 1.0f64
            ov[u] = 0.0f64
            u += 1usize
        }
        let l2 = ps.zero_link_fit(a, x2, z2, y2, wv, ov, n, p, q, lnk, false, par)
        if l2 != l2 { ret nan }
        if ps.zeroinfl_link_se(a, x2, z2, y2, wv, ov, n, p, q, lnk, par, se) != ok { ret nan }
        var t = 0.0f64
        u = 0usize
        while u < p + q {
            t += se[u] * f64(u + 1usize)
            u += 1usize
        }
        ret t
    }
    if str.eq(c.name, "lkll") || str.eq(c.name, "lkz") || str.eq(c.name, "wol") || str.eq(c.name, "woc") {
        let weighted = str.eq(c.name, "wol") || str.eq(c.name, "woc")
        let lnk = usize(z[3usize])
        let hm = usize(z[4usize]) == 1usize
        let y2 = z[5usize..5usize + n]
        let x2 = z[5usize + n..5usize + n + n * p]
        let z2 = z[5usize + n + n * p..5usize + n + n * p + n * q]
        let (wv, e7) = mem.alloc[f64](a, n)
        let (ov, e8) = mem.alloc[f64](a, n)
        if e7 != ok || e8 != ok { ret nan }
        var u = 0usize
        while u < n {
            wv[u] = 1.0f64
            ov[u] = 0.0f64
            if weighted {
                wv[u] = z[5usize + n + n * p + n * q + u]
                ov[u] = z[5usize + 2usize * n + n * p + n * q + u]
            }
            u += 1usize
        }
        let l2 = ps.zero_link_fit(a, x2, z2, y2, wv, ov, n, p, q, lnk, hm, par)
        if str.eq(c.name, "lkll") || str.eq(c.name, "wol") { ret l2 }
        if weighted { ret par[0usize] + 2.0f64 * par[1usize] }
        ret par[p] + 2.0f64 * par[p + 1usize]
    }
    let y = z[3usize..3usize + n]
    let x = z[3usize + n..3usize + n + n * p]
    let zz = z[3usize + n + n * p..3usize + n + n * p + n * q]
    if str.eq(c.name, "gzll") || str.eq(c.name, "gzc") || str.eq(c.name, "ghll") || str.eq(c.name, "ghc") {
        var lg = 0.0f64
        if str.eq(c.name, "gzll") || str.eq(c.name, "gzc") { lg = ps.zeroinfl_geom(a, x, zz, y, n, p, q, par) } else { lg = ps.hurdle_geom(a, x, zz, y, n, p, q, par) }
        if str.eq(c.name, "gzll") || str.eq(c.name, "ghll") { ret lg }
        ret par[0usize] + 2.0f64 * par[1usize]
    }
    if str.eq(c.name, "hnbll") || str.eq(c.name, "hnbtheta") {
        let lh = ps.hurdle_nb(a, x, zz, y, n, p, q, par)
        if str.eq(c.name, "hnbll") { ret lh }
        ret math.exp[f64](par[p + q])
    }
    let ll = ps.zeroinfl_nb(a, x, zz, y, n, p, q, par)
    if str.eq(c.name, "nbse") || str.eq(c.name, "nbsetheta") {
        let (se, e6) = mem.alloc[f64](a, p + q + 1usize)
        if e6 != ok { ret nan }
        if ps.zeroinfl_nb_se(a, x, zz, y, n, p, q, par, se) != ok { ret nan }
        if str.eq(c.name, "nbsetheta") { ret se[p + q] }
        var t = 0.0f64
        var u = 0usize
        while u < p + q {
            t += se[u] * f64(u + 1usize)
            u += 1usize
        }
        ret t
    }
    if str.eq(c.name, "nbll") { ret ll }
    ret math.exp[f64](par[p + q])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pscl_nb.json")
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
