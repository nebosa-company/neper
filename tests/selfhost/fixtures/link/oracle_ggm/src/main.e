// e.algo.stat.ggm against ggm: pcor, parcor, pcor.test, fitDag, fitConGraph and fitCovGraph.
// tests/oracle/ggm.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ggm`; the layout is at the
// top of scripts/r_oracle/groups/ggm.R.

use e.algo.stat.ggm as gg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nm = c.name
    let nan = 0.0f64 / 0.0f64
    if str.eq(nm, "pctest") {
        let (t, df, pv) = gg.pcor_test(z[0usize], z[1usize], z[2usize])
        let w = usize(z[3usize])
        if w == 0usize { ret t }
        if w == 1usize { ret df }
        ret pv
    }
    if str.eq(nm, "mp") {
        let r = usize(z[0usize])
        let (lev, e1) = mem.alloc[usize](a, r)
        let (ty, e2) = mem.alloc[u8](a, r)
        if e1 != ok || e2 != ok { ret nan }
        var i = 0usize
        while i < r {
            lev[i] = usize(z[1usize + i])
            ty[i] = u8(z[1usize + r + i])
            i += 1usize
        }
        let (mp, e3) = gg.marg_param(a, lev, ty)
        if e3 != ok { ret nan }
        let wh = usize(z[1usize + 2usize * r])
        var m = mp.c
        if wh == 1usize { m = mp.m }
        if wh == 2usize { m = mp.g }
        let qq = usize(z[2usize + 2usize * r])
        if qq == 0usize { ret f64(m.rows) }
        if qq == 1usize { ret f64(m.cols) }
        var s = 0.0f64
        var sw = 0.0f64
        i = 0usize
        while i < m.rows * m.cols {
            s += m.d[i]
            sw += f64(i + 1usize) * m.d[i]
            i += 1usize
        }
        if qq == 2usize { ret s }
        ret sw
    }
    let p = usize(z[0usize])
    if str.eq(nm, "topo") {
        let (ord, eo) = mem.alloc[usize](a, p)
        if eo != ok { ret nan }
        let et = gg.toporder(a, z[1usize..1usize + p * p], p, ord)
        if et != ok { ret nan }
        ret f64(ord[usize(z[1usize + p * p])] + 1usize)
    }
    if str.eq(nm, "icov") || str.eq(nm, "icon") {
        let am3 = z[1usize..1usize + p * p]
        var at = 1usize + p * p
        let ns = usize(z[at])
        let (ss, e1) = mem.alloc[usize](a, ns + 1usize)
        if e1 != ok { ret nan }
        var i = 0usize
        while i < ns {
            ss[i] = usize(z[at + 1usize + i]) - 1usize
            i += 1usize
        }
        at = at + 1usize + ns
        let nc = usize(z[at])
        let (cs, e2) = mem.alloc[usize](a, nc + 1usize)
        if e2 != ok { ret nan }
        i = 0usize
        while i < nc {
            cs[i] = usize(z[at + 1usize + i]) - 1usize
            i += 1usize
        }
        let qq = usize(z[at + 1usize + nc])
        let (out, e3) = mem.alloc[f64](a, ns * ns + 1usize)
        if e3 != ok { ret nan }
        var e4 = ok
        if str.eq(nm, "icov") {
            e4 = gg.inducedcovgraph(a, am3, p, ss[0usize..ns], cs[0usize..nc], out)
        } else {
            e4 = gg.inducedcongraph(a, am3, p, ss[0usize..ns], cs[0usize..nc], out)
        }
        if e4 != ok { ret nan }
        ret out[qq]
    }
    if str.eq(nm, "dsep") {
        let am2 = z[1usize..1usize + p * p]
        var at = 1usize + p * p
        let nf = usize(z[at])
        let (fs, e1) = mem.alloc[usize](a, nf + 1usize)
        if e1 != ok { ret nan }
        var i = 0usize
        while i < nf {
            fs[i] = usize(z[at + 1usize + i]) - 1usize
            i += 1usize
        }
        at = at + 1usize + nf
        let ns = usize(z[at])
        let (ss, e2) = mem.alloc[usize](a, ns + 1usize)
        if e2 != ok { ret nan }
        i = 0usize
        while i < ns {
            ss[i] = usize(z[at + 1usize + i]) - 1usize
            i += 1usize
        }
        at = at + 1usize + ns
        let nc = usize(z[at])
        let (cs, e3) = mem.alloc[usize](a, nc + 1usize)
        if e3 != ok { ret nan }
        i = 0usize
        while i < nc {
            cs[i] = usize(z[at + 1usize + i]) - 1usize
            i += 1usize
        }
        let (sep, e4) = gg.dsep(a, am2, p, fs[0usize..nf], ss[0usize..ns], cs[0usize..nc])
        if e4 != ok { ret nan }
        if sep { ret 1.0f64 }
        ret 0.0f64
    }
    if str.eq(nm, "pcor") {
        let nu = usize(z[1usize])
        let (u, e1) = mem.alloc[usize](a, nu)
        if e1 != ok { ret nan }
        var i = 0usize
        while i < nu {
            u[i] = usize(z[2usize + i]) - 1usize
            i += 1usize
        }
        let (v, e2) = gg.pcor(a, u, z[2usize + nu..2usize + nu + p * p], p)
        if e2 != ok { ret nan }
        ret v
    }
    if str.eq(nm, "parcor") {
        let (out, e1) = mem.alloc[f64](a, p * p)
        if e1 != ok { ret nan }
        let e2 = gg.parcor(a, z[1usize..1usize + p * p], p, out)
        if e2 != ok { ret nan }
        ret out[usize(z[1usize + p * p]) * p + usize(z[2usize + p * p])]
    }
    let n = z[1usize]
    let s = z[2usize..2usize + p * p]
    let am = z[2usize + p * p..2usize + 2usize * p * p]
    let q = usize(z[2usize + 2usize * p * p])
    let (sh, e1) = mem.alloc[f64](a, p * p)
    if e1 != ok { ret nan }
    if str.eq(nm, "ag") {
        let (ah, e2) = mem.alloc[f64](a, p * p)
        let (oh, e3) = mem.alloc[f64](a, p * p)
        let (lh, e4) = mem.alloc[f64](a, p * p)
        if e2 != ok || e3 != ok || e4 != ok { ret nan }
        let (r, e5) = gg.fitancestral(a, am, s, p, n, 0.000001f64, sh, ah, oh, lh)
        if e5 != ok { ret nan }
        if q < p * p { ret sh[q] }
        if q == p * p { ret r.dev }
        if q == p * p + 1usize { ret r.df }
        if q == p * p + 2usize { ret f64(r.it) }
        var tot = 0.0f64
        var i = 0usize
        while i < p * p {
            if q == p * p + 3usize { tot += ah[i] }
            if q == p * p + 4usize { tot += oh[i] }
            if q == p * p + 5usize { tot += lh[i] }
            i += 1usize
        }
        ret tot
    }
    if str.eq(nm, "dag") {
        let (ah, e2) = mem.alloc[f64](a, p * p)
        let (dh, e3) = mem.alloc[f64](a, p)
        if e2 != ok || e3 != ok { ret nan }
        let (r, e4) = gg.fitdag(a, am, s, p, n, sh, ah, dh)
        if e4 != ok { ret nan }
        if q < p * p { ret sh[q] }
        if q < p * p + p { ret dh[q - p * p] }
        if q == p * p + p { ret r.dev }
        if q == p * p + p + 1usize { ret r.df }
        ret ah[q - p * p - p - 2usize]
    }
    if str.eq(nm, "clq") {
        let at = 2usize + 2usize * p * p
        let ncl = usize(z[at])
        let (sz, e2) = mem.alloc[usize](a, ncl)
        if e2 != ok { ret nan }
        var tot = 0usize
        var i = 0usize
        while i < ncl {
            sz[i] = usize(z[at + 1usize + i])
            tot += sz[i]
            i += 1usize
        }
        let (cl, e3) = mem.alloc[usize](a, tot)
        if e3 != ok { ret nan }
        i = 0usize
        while i < tot {
            cl[i] = usize(z[at + 1usize + ncl + i]) - 1usize
            i += 1usize
        }
        let qc = usize(z[at + 1usize + ncl + tot])
        let (r, e4) = gg.fitcongraph_cli(a, am, s, p, n, cl, sz, 0.000001f64, sh)
        if e4 != ok { ret nan }
        if qc < p * p { ret sh[qc] }
        if qc == p * p { ret r.dev }
        if qc == p * p + 1usize { ret r.df }
        ret f64(r.it)
    }
    if str.eq(nm, "dual") {
        let (r, e2) = gg.fitcovgraph_dual(a, am, s, p, n, 0.000001f64, sh)
        if e2 != ok { ret nan }
        if q < p * p { ret sh[q] }
        if q == p * p { ret r.dev }
        if q == p * p + 1usize { ret r.df }
        ret f64(r.it)
    }
    if str.eq(nm, "con") {
        let (r, e2) = gg.fitcongraph(a, am, s, p, n, 0.000001f64, sh)
        if e2 != ok { ret nan }
        if q < p * p { ret sh[q] }
        if q == p * p { ret r.dev }
        if q == p * p + 1usize { ret r.df }
        ret f64(r.it)
    }
    let (r, e2) = gg.fitcovgraph(a, am, s, p, n, 0.000001f64, sh)
    if e2 != ok { ret nan }
    if q < p * p { ret sh[q] }
    if q == p * p { ret r.dev }
    if q == p * p + 1usize { ret r.df }
    ret f64(r.it)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ggm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
