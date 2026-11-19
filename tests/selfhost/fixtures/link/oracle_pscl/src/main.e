// e.algo.stat.psclpkg against pscl zeroinfl and hurdle. tests/oracle/pscl.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pscl`; the layout is at the top of scripts/r_oracle/groups/pscl.R.

use e.algo.stat.psclpkg as ps
use e.io
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
    let kind = usize(z[3usize])
    let (par, e1) = mem.alloc[f64](a, p + q)
    if e1 != ok { ret nan }
    let y = z[4usize..4usize + n]
    let x = z[4usize + n..4usize + n + n * p]
    let zz = z[4usize + n + n * p..4usize + n + n * p + n * q]
    if str.eq(c.name, "r20") || str.eq(c.name, "r21") || str.eq(c.name, "r22") || str.eq(c.name, "r23") || str.eq(c.name, "r24") || str.eq(c.name, "r25") {
        let (r2, e9) = mem.alloc[f64](a, 6usize)
        if e9 != ok { ret nan }
        var er2 = ok
        if kind == 0usize { er2 = ps.pr2_zeroinfl(a, x, zz, y, n, p, q, r2) } else { er2 = ps.pr2_hurdle(a, x, zz, y, n, p, q, r2) }
        if er2 != ok { ret nan }
        var w = 0usize
        if str.eq(c.name, "r21") { w = 1usize }
        if str.eq(c.name, "r22") { w = 2usize }
        if str.eq(c.name, "r23") { w = 3usize }
        if str.eq(c.name, "r24") { w = 4usize }
        if str.eq(c.name, "r25") { w = 5usize }
        ret r2[w]
    }
    if str.eq(c.name, "vg0") || str.eq(c.name, "vg1") || str.eq(c.name, "vg2") || str.eq(c.name, "vh0") || str.eq(c.name, "vh1") || str.eq(c.name, "vh2") {
        let (vs, e8) = mem.alloc[f64](a, 3usize)
        if e8 != ok { ret nan }
        var wv = 0usize
        if str.eq(c.name, "vh0") || str.eq(c.name, "vh1") || str.eq(c.name, "vh2") { wv = 1usize }
        if ps.vuong_pair(a, x, zz, y, n, p, q, wv, vs) != ok { ret nan }
        var u = 0usize
        if str.eq(c.name, "vg1") || str.eq(c.name, "vh1") { u = 1usize }
        if str.eq(c.name, "vg2") || str.eq(c.name, "vh2") { u = 2usize }
        ret vs[u]
    }
    var ll = 0.0f64
    if kind == 0usize { ll = ps.zeroinfl(a, x, zz, y, n, p, q, par) } else { ll = ps.hurdle(a, x, zz, y, n, p, q, par) }
    if str.eq(c.name, "ll") { ret ll }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "pred0") || str.eq(c.name, "pred1") || str.eq(c.name, "pred2") {
        let (pv, e3) = mem.alloc[f64](a, n)
        if e3 != ok { ret nan }
        var ty = 0usize
        if str.eq(c.name, "pred1") { ty = 1usize }
        if str.eq(c.name, "pred2") { ty = 2usize }
        ps.predict(kind, x, zz, n, p, q, par, ty, pv)
        while i < n {
            s += pv[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "vuong0") || str.eq(c.name, "vuong1") || str.eq(c.name, "vuong2") {
        let (vs, e4) = mem.alloc[f64](a, 3usize)
        if e4 != ok { ret nan }
        if ps.vuong_zip_poisson(a, x, zz, y, n, p, q, par, vs) != ok { ret nan }
        var which = 0usize
        if str.eq(c.name, "vuong1") { which = 1usize }
        if str.eq(c.name, "vuong2") { which = 2usize }
        ret vs[which]
    }
    if str.eq(c.name, "secount") || str.eq(c.name, "sezero") {
        let (se, e2) = mem.alloc[f64](a, p + q)
        if e2 != ok { ret nan }
        if ps.standard_errors(a, kind, x, zz, y, n, p, q, par, se) != ok { ret nan }
        if str.eq(c.name, "secount") {
            while i < p {
                s += se[i] * f64(i + 1usize)
                i += 1usize
            }
        } else {
            while i < q {
                s += se[p + i] * f64(i + 1usize)
                i += 1usize
            }
        }
        ret s
    }
    if str.eq(c.name, "count") {
        while i < p {
            s += par[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    while i < q {
        s += par[p + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pscl.json")
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
