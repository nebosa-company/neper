// e.algo.stat.plmpanel against plm (unbalanced panels, every model, the tests and the vcovG family). tests/oracle/plm_panel.json comes
// from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R plm_panel`; the argument layout is at the top of scripts/r_oracle/groups/plm_panel.R.

use e.algo.stat.plmpanel as pp
use e.io
use e.math
use e.math.nmath as nm
use e.math.nmath_beta as nb
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let p1 = usize(z[2usize])
    let p2 = usize(z[3usize])
    let p3 = usize(z[4usize])
    var p4 = 0usize
    if z[5usize] >= 0.0f64 { p4 = usize(z[5usize]) }
    let p5 = usize(z[6usize])
    let h = 9usize
    var ids = z[h..h + n]
    var tms = z[h + n..h + 2usize * n]
    if z[7usize] == 1.0f64 {
        ids = z[h + n..h + 2usize * n]
        tms = z[h..h + n]
    }
    let (pa, e0) = pp.make(a, n, k, ids, tms, z[h + 2usize * n..h + 3usize * n], z[h + 3usize * n..h + 3usize * n + n * k])
    if e0 != ok { ret nan }
    let p = &pa[0usize]
    let (out, e1) = mem.alloc[f64](a, 8usize)
    let (fw, e2) = mem.alloc[pp.Fit](a, 1usize)
    if e1 != ok || e2 != ok { ret nan }
    let name = c.name
    if str.eq(name, "fit") {
        if pp.fit_model(a, p, p1, p2, &fw[0usize]) != ok { ret nan }
        let f = &fw[0usize]
        if p3 == 0usize { ret wsum(f.coef, f.kk) }
        if p3 == 1usize {
            var s = 0.0f64
            var i = 0usize
            while i < f.kk {
                s += math.sqrt[f64](f.vc[i * f.kk + i]) * f64(i + 1usize)
                i += 1usize
            }
            ret s
        }
        if p3 == 2usize { ret f.s2e }
        if p3 == 3usize { ret f.s2id }
        ret wsum(f.theta, p.nid)
    }
    if str.eq(name, "ph") {
        if pp.phtest(a, p, p1, out) != ok { ret nan }
        if p2 == 0usize { ret out[0usize] }
        if p2 == 2usize { ret out[1usize] }
        ret nm.pchisq(out[0usize], out[1usize], false, false)
    }
    if str.eq(name, "pf") {
        if pp.pftest(a, p, out) != ok { ret nan }
        if p1 == 0usize { ret out[0usize] }
        ret nb.pf(out[0usize], out[1usize], out[2usize], false, false)
    }
    if str.eq(name, "lm") {
        if pp.plmtest(a, p, p1, p2, out) != ok { ret nan }
        ret out[p3]
    }
    if str.eq(name, "bg") {
        if pp.pbgtest(a, p, p1, p2, p3, out) != ok { ret nan }
        if p4 == 0usize { ret out[0usize] }
        ret nm.pchisq(out[0usize], out[1usize], false, false)
    }
    if str.eq(name, "dw") {
        if p3 == 0usize { ret pp.pdwtest(a, p, p1, p2) }
        ret pp.pdwtest_p(a, p, p1, p2)
    }
    if pp.fit_model(a, p, p1, p2, &fw[0usize]) != ok { ret nan }
    let f = &fw[0usize]
    let (vc, e3) = mem.alloc[f64](a, f.kk * f.kk)
    if e3 != ok { ret nan }
    if str.eq(name, "vg") {
        if pp.vcov_g(a, f, p3, p4, 0usize, p5, vc) != ok { ret nan }
        ret wsum(vc, f.kk * f.kk)
    }
    if str.eq(name, "scc") {
        var ml = pp.default_maxlag(p)
        if z[5usize] >= 0.0f64 { ml = usize(z[5usize]) }
        if pp.vcov_scc(a, f, p3, p5, ml, vc) != ok { ret nan }
        ret wsum(vc, f.kk * f.kk)
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/plm_panel.json")
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
