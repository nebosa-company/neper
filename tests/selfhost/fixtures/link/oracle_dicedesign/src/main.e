// e.algo.stat.dicedesign against DiceDesign. tests/oracle/dicedesign.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R dicedesign`; the layout is at the top of scripts/r_oracle/groups/dicedesign.R.

use e.algo.rand.r as rr
use e.algo.stat.dicedesign as dd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn gen(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    var total = 0.0f64
    if str.eq(c.name, "faureprime") {
        let (fo, fe) = mem.alloc[f64](a, 130usize * n)
        if fe != ok { os.exit(13) }
        let cnt = dd.faure_prime(a, n, d, fo)
        var q = 0usize
        while q < cnt * n {
            total += fo[q] * f64(q + 1usize)
            q += 1usize
        }
        ret total
    }
    if str.eq(c.name, "fact") {
        var lv: [5]usize = zero
        var cnt = 1usize
        var i = 0usize
        while i < d {
            lv[i] = usize(x[4usize + i])
            cnt = cnt * lv[i]
            i += 1usize
        }
        let (o, e) = mem.alloc[f64](a, cnt * d)
        if e != ok { os.exit(5) }
        dd.fact_design(lv[0usize..d], o)
        i = 0usize
        while i < cnt * d {
            total += o[i] * f64(i + 1usize)
            i += 1usize
        }
        ret total
    }
    var g: rr.Rng = zero
    let (o, e) = mem.alloc[f64](a, n * d)
    if e != ok { os.exit(6) }
    if str.eq(c.name, "dese2") {
        rr.seed(&g, i64(x[2usize]))
        if dd.lhs_from(a, &g, n, d, o) != ok { os.exit(12) }
        let t0 = 0.005f64 * dd.discrepancy(o, n, d, 2usize)
        let fi = dd.discrep_ese_l2star(a, &g, o, n, d, t0, 20usize, 5usize, usize(x[3usize]))
        let _ = fi
        var q = 0usize
        while q < n * d {
            total += o[q] * f64(q + 1usize)
            q += 1usize
        }
        ret total
    }
    if str.eq(c.name, "dese") || str.eq(c.name, "dese_c2") {
        rr.seed(&g, i64(x[2usize]))
        if dd.lhs_from(a, &g, n, d, o) != ok { os.exit(11) }
        let t0 = 0.005f64 * dd.c2_exact(o, n, d)
        let fi = dd.discrep_ese_c2(a, &g, o, n, d, t0, 20usize, 5usize, usize(x[3usize]))
        if str.eq(c.name, "dese_c2") { ret dd.c2_exact(o, n, d) }
        var q = 0usize
        while q < n * d {
            total += o[q] * f64(q + 1usize)
            q += 1usize
        }
        let _ = fi
        ret total
    }
    if str.eq(c.name, "ese") || str.eq(c.name, "ese_phi") {
        rr.seed(&g, i64(x[2usize]))
        if dd.lhs_from(a, &g, n, d, o) != ok { os.exit(10) }
        let t0 = 0.005f64 * dd.phi_p(o, n, d, 50.0f64)
        let fi = dd.maximin_ese(a, &g, o, n, d, t0, 20usize, 5usize, usize(x[3usize]), 15.0f64)
        if str.eq(c.name, "ese_phi") { ret dd.phi_p(o, n, d, 15.0f64) }
        var q = 0usize
        while q < n * d {
            total += o[q] * f64(q + 1usize)
            q += 1usize
        }
        ret total
    }
    if str.eq(c.name, "sa") || str.eq(c.name, "sa_phi") {
        rr.seed(&g, i64(x[2usize]))
        if dd.lhs_from(a, &g, n, d, o) != ok { os.exit(9) }
        var prof = 0usize
        if x[3usize] > 0.5f64 { prof = 1usize }
        let fi = dd.maximin_sa(a, &g, o, n, d, 5.0f64, 0.9f64, 60usize, 15.0f64, prof)
        if str.eq(c.name, "sa_phi") { ret fi }
        var q = 0usize
        while q < n * d {
            total += o[q] * f64(q + 1usize)
            q += 1usize
        }
        ret total
    }
    if str.eq(c.name, "dsa") || str.eq(c.name, "dsa_c2") || str.eq(c.name, "dsa_it") {
        rr.seed(&g, i64(x[2usize]))
        if dd.lhs_from(a, &g, n, d, o) != ok { os.exit(9) }
        var prof = 0usize
        if x[3usize] > 0.5f64 { prof = 1usize }
        var itn = 60usize
        if str.eq(c.name, "dsa_it") { itn = usize(x[4usize]) }
        let fi = dd.anneal(a, &g, o, n, d, 0.05f64, 0.9f64, itn, 0.0f64, prof, 0usize)
        if str.eq(c.name, "dsa_c2") || str.eq(c.name, "dsa_it") { ret fi }
        var q = 0usize
        while q < n * d {
            total += o[q] * f64(q + 1usize)
            q += 1usize
        }
        ret total
    }
    if str.eq(c.name, "wsp") || str.eq(c.name, "wsp_n") {
        rr.seed(&g, i64(x[2usize]))
        if dd.lhs_from(a, &g, n, d, o) != ok { os.exit(9) }
        let (xs, e5) = mem.alloc[usize](a, n)
        if e5 != ok { os.exit(10) }
        let cnt = dd.wsp(a, o, n, d, x[3usize], xs)
        if str.eq(c.name, "wsp_n") { ret f64(cnt) }
        var q = 0usize
        while q < cnt {
            total += f64(xs[q]) * f64(q + 1usize)
            q += 1usize
        }
        ret total
    }
    if str.eq(c.name, "lhs") {
        if dd.lhs_design(a, n, d, x[3usize] > 0.5f64, i64(x[2usize]), o) != ok { os.exit(7) }
    } else {
        if dd.faure(a, n, d, o) != ok { os.exit(8) }
    }
    var i = 0usize
    while i < n * d {
        total += o[i] * f64(i + 1usize)
        i += 1usize
    }
    ret total
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "lhs") || str.eq(c.name, "fact") || str.eq(c.name, "faure") || str.eq(c.name, "sa") || str.eq(c.name, "sa_phi") || str.eq(c.name, "dsa") || str.eq(c.name, "dsa_c2") || str.eq(c.name, "dsa_it") || str.eq(c.name, "wsp") || str.eq(c.name, "wsp_n") || str.eq(c.name, "ese") || str.eq(c.name, "ese_phi") || str.eq(c.name, "dese") || str.eq(c.name, "dese_c2") || str.eq(c.name, "dese2") || str.eq(c.name, "faureprime") { ret gen(a, c) }
    let x = c.args
    let n = usize(x[0usize])
    let d = usize(x[1usize])
    let p = x[2usize]
    let des = x[3usize..3usize + n * d]
    let k = c.name
    if str.eq(k, "mesh") { ret dd.mesh_ratio(des, n, d) }
    if str.eq(k, "C2") { ret dd.discrepancy(des, n, d, 0usize) }
    if str.eq(k, "L2") { ret dd.discrepancy(des, n, d, 1usize) }
    if str.eq(k, "L2star") { ret dd.discrepancy(des, n, d, 2usize) }
    if str.eq(k, "M2") { ret dd.discrepancy(des, n, d, 3usize) }
    if str.eq(k, "S2") { ret dd.discrepancy(des, n, d, 4usize) }
    if str.eq(k, "W2") { ret dd.discrepancy(des, n, d, 5usize) }
    if str.eq(k, "Mix2") { ret dd.discrepancy(des, n, d, 6usize) }
    if str.eq(k, "mindist") { ret dd.mindist(des, n, d) }
    if str.eq(k, "phip") { ret dd.phi_p(des, n, d, p) }
    ret dd.coverage(des, n, d)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/dicedesign.json")
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
