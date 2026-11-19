// e.algo.stat.massextra against MASS cov.trob, lm.ridge, stdres / studres, contr.sdif and dose.p. tests/oracle/mass_extra.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_extra`; the layout is at the top of scripts/r_oracle/groups/mass_extra.R.

use e.algo.stat.massextra as me
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
    if str.eq(c.name, "trob") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let cm = usize(z[2usize])
        let has_wt = z[3usize] != 0.0f64
        let mode = usize(z[7usize])
        let x = z[8usize..8usize + n * p]
        var at = 8usize + n * p
        var wt = z[0usize..0usize]
        if has_wt {
            wt = z[at..at + n]
            at += n
        }
        var ctr = z[0usize..0usize]
        if cm == 2usize { ctr = z[at..at + p] }
        let (cov, e1) = mem.alloc[f64](a, p * p)
        let (loc, e2) = mem.alloc[f64](a, p)
        if e1 != ok || e2 != ok { ret nan() }
        let (it, nn, e) = me.cov_trob(a, x, n, p, wt, has_wt, cm, ctr, z[4usize], usize(z[5usize]), z[6usize], cov, loc)
        if e != ok { ret nan() }
        if mode == 0usize { ret wsum(cov) }
        if mode == 1usize { ret wsum(loc) }
        if mode == 2usize { ret f64(it) }
        ret f64(nn)
    }
    if str.eq(c.name, "ridge") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let inter = z[2usize] != 0.0f64
        let k = usize(z[3usize])
        let mode = usize(z[4usize])
        let lam = z[5usize..5usize + k]
        let x = z[5usize + k..5usize + k + n * p]
        let y = z[5usize + k + n * p..5usize + k + n * p + n]
        var nc = p
        if inter { nc = p + 1usize }
        let (cf, e1) = mem.alloc[f64](a, k * nc)
        let (gcv, e2) = mem.alloc[f64](a, k)
        let (sc, e3) = mem.alloc[f64](a, p)
        let (o2, e4) = mem.alloc[f64](a, 2usize)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan() }
        let e = me.lm_ridge(a, x, n, p, y, lam, inter, cf, gcv, sc, o2)
        if e != ok { ret nan() }
        if mode == 0usize { ret wsum(cf) }
        if mode == 1usize { ret wsum(gcv) }
        if mode == 2usize { ret o2[0usize] }
        if mode == 3usize { ret o2[1usize] }
        ret wsum(sc)
    }
    if str.eq(c.name, "stdres") {
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let inter = z[2usize] != 0.0f64
        let has_w = z[3usize] != 0.0f64
        let mode = usize(z[4usize])
        let x = z[5usize..5usize + n * p]
        let y = z[5usize + n * p..5usize + n * p + n]
        var w = z[0usize..0usize]
        if has_w { w = z[5usize + n * p + n..5usize + n * p + 2usize * n] }
        let (sr, e1) = mem.alloc[f64](a, n)
        let (st, e2) = mem.alloc[f64](a, n)
        if e1 != ok || e2 != ok { ret nan() }
        let (sd, e) = me.lm_stdres(a, x, n, p, y, w, has_w, inter, sr, st)
        if e != ok { ret nan() }
        var m = n
        if has_w {
            m = 0usize
            var i = 0usize
            while i < n {
                if w[i] != 0.0f64 { m += 1usize }
                i += 1usize
            }
        }
        if mode == 0usize { ret wsum(sr[0usize..m]) }
        if mode == 1usize { ret wsum(st[0usize..m]) }
        ret sd
    }
    if str.eq(c.name, "sdif") {
        let n = usize(z[0usize])
        let (o, e) = mem.alloc[f64](a, n * n)
        if e != ok { ret nan() }
        me.contr_sdif(n, o)
        ret wsum(o[0usize..n * (n - 1usize)])
    }
    let (xp, se) = me.dose_p(usize(z[0usize]), z[1usize], z[2usize], z[3usize], z[4usize], z[5usize], z[6usize])
    if usize(z[7usize]) == 0usize { ret xp }
    ret se
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_extra.json")
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
