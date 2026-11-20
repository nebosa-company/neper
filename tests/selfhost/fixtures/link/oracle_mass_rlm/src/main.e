// e.algo.stat.massrlm against MASS rlm and summary.rlm. tests/oracle/mass_rlm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_rlm`; the layout is at the top of scripts/r_oracle/groups/mass_rlm.R.

use e.algo.rand.r as rng
use e.algo.stat.massrlm as mr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    var o = mr.default_opts()
    o.psi = usize(z[3usize])
    if !(o.psi == 0usize && z[4usize] == 1.345f64) {
        o.pa = z[4usize]
    }
    o.pb = z[5usize]
    o.pc = z[6usize]
    o.scale_est = usize(z[7usize])
    o.k2 = z[8usize]
    o.mm = z[9usize] != 0.0f64
    o.wt_case = z[10usize] != 0.0f64
    o.has_weights = z[11usize] != 0.0f64
    o.init = usize(z[12usize])
    o.maxit = usize(z[13usize])
    o.acc = z[14usize]
    o.test_vec = usize(z[15usize])
    o.lq_nsamp = z[16usize]
    o.mm_c = z[17usize]
    let mode = usize(z[18usize])
    let off = 19usize
    let y = z[off..off + n]
    let x = z[off + n..off + n + n * p]
    var at = off + n + n * p
    var wts = z[off..off]
    if o.has_weights {
        wts = z[at..at + n]
        at += n
    }
    var ic = z[off..off]
    if o.init == 2usize { ic = z[at..at + p] }
    let (ones, e0) = mem.alloc[f64](a, n)
    if e0 != ok { ret nan() }
    var i = 0usize
    while i < n {
        ones[i] = 1.0f64
        if o.has_weights && o.wt_case { ones[i] = 1.0f64 }
        i += 1usize
    }
    let (f, e) = mr.rlm(a, &g, x, n, p, y, wts, ones, ic, &o)
    if e != ok { ret nan() }
    if mode == 0usize { ret wsum(f.coef) }
    if mode == 1usize { ret f.s }
    if mode == 2usize { ret f64(f.nconv) }
    if mode == 3usize {
        if f.converged { ret 1.0f64 }
        ret 0.0f64
    }
    if mode == 4usize { ret wsum(f.w) }
    if mode == 5usize { ret wsum(f.wresid) }
    if mode == 6usize { ret wsum(f.residuals) }
    if mode == 12usize {
        let (sm, se) = mr.summary(a, &f, x, n, p, wts, &o, 0usize)
        if se != ok { ret nan() }
        ret sm.rdf
    }
    if mode >= 11usize && mode != 12usize && str.eq(c.name, "rlmx") {
        let m = usize(z[at])
        let level = z[at + 1usize]
        let newx = z[at + 2usize..at + 2usize + m * p]
        let (ft, f1) = mem.alloc[f64](a, m)
        let (sf, f2) = mem.alloc[f64](a, m)
        let (lw, f3) = mem.alloc[f64](a, m)
        let (up, f4) = mem.alloc[f64](a, m)
        if f1 != ok || f2 != ok || f3 != ok || f4 != ok { ret nan() }
        var iv = 0usize
        if mode == 15usize || mode == 16usize { iv = 1usize }
        if mode == 17usize || mode == 18usize { iv = 2usize }
        if mode == 11usize {
            let (sm, se) = mr.summary(a, &f, x, n, p, wts, &o, 0usize)
            if se != ok { ret nan() }
            var tv = 0.0f64
            var q = 0usize
            while q < p {
                tv += f64(q + 1usize) * sm.coef[q] / sm.se[q]
                q += 1usize
            }
            ret tv
        }
        let pe = mr.predict(a, &f, x, n, p, wts, &o, newx, m, level, iv, ft, sf, lw, up)
        if pe != ok { ret nan() }
        if mode == 13usize { ret wsum(ft) }
        if mode == 14usize { ret wsum(sf) }
        if mode == 15usize || mode == 17usize { ret wsum(lw) }
        ret wsum(up)
    }
    var method = 0usize
    if mode == 8usize { method = 1usize }
    let (sm, se) = mr.summary(a, &f, x, n, p, wts, &o, method)
    if se != ok { ret nan() }
    if mode == 9usize { ret sm.stddev }
    if mode == 10usize { ret wsum(sm.cov) }
    ret wsum(sm.se)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_rlm.json")
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
                var shown = *c
                if shown.args.len > 20usize { shown.args = c.args[0usize..20usize] }
                let _ = io.print(oracle.describe(a, &shown, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
