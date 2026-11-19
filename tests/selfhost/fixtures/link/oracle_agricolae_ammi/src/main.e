// e.algo.stat.agricolae AMMI against agricolae. tests/oracle/agricolae_ammi.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R agricolae_ammi`; the layout is at the top of scripts/r_oracle/groups/agricolae_ammi.R.

use e.algo.stat.agricolae as ag
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "ar") {
        let ne = usize(x[0usize])
        let ng = usize(x[1usize])
        let nr = usize(x[2usize])
        let w = usize(x[3usize])
        let idx = usize(x[4usize])
        let n = ne * ng * nr
        let (ev, h0) = mem.alloc[usize](a, n)
        let (gv, h1) = mem.alloc[usize](a, n)
        let (rv, h2) = mem.alloc[usize](a, n)
        if h0 != ok || h1 != ok || h2 != ok { os.exit(9) }
        var q = 0usize
        while q < n {
            ev[q] = usize(x[5usize + q])
            gv[q] = usize(x[5usize + n + q])
            rv[q] = usize(x[5usize + 2usize * n + q])
            q += 1usize
        }
        let (am, aov, ee) = ag.ammi_raw(a, x[5usize + 3usize * n..5usize + 4usize * n], ev, gv, rv, ne, ng, nr)
        if ee != ok { os.exit(10) }
        if w == 0usize { ret aov.df[idx] }
        if w == 1usize { ret aov.ss[idx] }
        if w == 2usize { ret aov.ms[idx] }
        if w == 3usize { ret aov.f[idx] }
        if w == 4usize { ret aov.p[idx] }
        if w == 5usize { ret aov.mse }
        if w == 6usize { ret am.percent[idx] }
        if w == 7usize { ret am.acum[idx] }
        if w == 8usize { ret am.df[idx] }
        if w == 9usize { ret am.f[idx] }
        if w == 10usize { ret am.scoreg[idx] }
        ret am.scoree[idx]
    }
    if str.eq(c.name, "sp") {
        let na = usize(x[0usize])
        let nmm = usize(x[1usize])
        let w = usize(x[5usize])
        let idx = usize(x[6usize])
        let (sp, spe) = ag.stability_par(a, x[7usize..7usize + na * nmm], na, nmm, x[2usize], x[3usize], x[4usize])
        if spe != ok { os.exit(8) }
        if w == 0usize { ret sp.df[idx] }
        if w == 1usize { ret sp.ss[idx] }
        if w == 2usize { ret sp.ms[idx] }
        if w == 3usize { ret sp.fv[idx] }
        if w == 4usize { ret sp.pv[idx] }
        if w == 10usize { ret sp.mean[idx] }
        if w == 11usize { ret sp.sigma2[idx] }
        if w == 12usize { ret sp.sig1[idx] }
        if w == 13usize { ret sp.s2[idx] }
        if w == 14usize { ret sp.sig2[idx] }
        if w == 15usize { ret sp.eco[idx] }
        if w == 16usize { ret sp.rank[idx] }
        if w == 17usize { ret sp.adj_rank[idx] }
        if w == 18usize { ret sp.adjusted[idx] }
        if w == 19usize { ret sp.rating[idx] }
        if w == 20usize { ret sp.ysi[idx] }
        ret sp.sel[idx]
    }
    if str.eq(c.name, "sn") {
        let k = usize(x[0usize])
        let n = usize(x[1usize])
        let w = usize(x[2usize])
        let idx = usize(x[3usize])
        let (mn, g0) = mem.alloc[f64](a, k)
        let (rk, g1) = mem.alloc[f64](a, k)
        let (s1, g2) = mem.alloc[f64](a, k)
        let (z1, g3) = mem.alloc[f64](a, k)
        let (s2, g4) = mem.alloc[f64](a, k)
        let (z2, g5) = mem.alloc[f64](a, k)
        if g0 != ok || g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok { os.exit(6) }
        let (st, se) = ag.stability_nonpar(a, x[4usize..4usize + k * n], k, n, mn, rk, s1, z1, s2, z2)
        if se != ok { os.exit(7) }
        if w == 0usize { ret mn[idx] }
        if w == 1usize { ret rk[idx] }
        if w == 2usize { ret s1[idx] }
        if w == 3usize { ret z1[idx] }
        if w == 4usize { ret s2[idx] }
        if w == 5usize { ret z2[idx] }
        if w == 6usize { ret st.es1 }
        if w == 7usize { ret st.es2 }
        if w == 8usize { ret st.vs1 }
        if w == 9usize { ret st.vs2 }
        if w == 10usize { ret st.chi_ind }
        if w == 11usize { ret st.chi_sum }
        if w == 12usize { ret st.sum_z1 }
        ret st.sum_z2
    }
    let ng = usize(x[0usize])
    let ne = usize(x[1usize])
    let what = usize(x[4usize])
    let idx = usize(x[5usize])
    let (r, e) = ag.ammi(a, x[6usize..6usize + ng * ne], ng, ne, x[2usize], x[3usize])
    if e != ok { os.exit(5) }
    if what == 0usize { ret r.percent[idx] }
    if what == 1usize { ret r.acum[idx] }
    if what == 2usize { ret r.df[idx] }
    if what == 3usize { ret r.ss[idx] }
    if what == 4usize { ret r.ms[idx] }
    if what == 5usize { ret r.f[idx] }
    if what == 6usize { ret r.p[idx] }
    if what == 7usize { ret r.scoreg[idx] }
    if what == 8usize { ret r.scoree[idx] }
    if what == 9usize { ret r.gmean[idx] }
    if what == 10usize { ret r.emean[idx] }
    ret f64(r.rows)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/agricolae_ammi.json")
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
