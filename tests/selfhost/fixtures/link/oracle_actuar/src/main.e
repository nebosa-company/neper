// e.algo.stat.actuar against actuar. tests/oracle/actuar.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R actuar`;
// the layout is at the top of scripts/r_oracle/groups/actuar.R.

use e.algo.stat.actuar as ac
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "dz") {
        let nd = usize(x[1usize])
        var dv: [64]f64 = zero
        let cnt = ac.discretize_cdf(usize(x[0usize]), x[2usize..2usize + 2usize * nd + 1usize], nd, dv[0usize..64usize])
        if usize(x[3usize + 2usize * nd]) == 0usize { ret f64(cnt) }
        var sd = 0.0f64
        var k = 0usize
        while k < cnt {
            sd += dv[k] * f64(k + 1usize)
            k += 1usize
        }
        ret sd
    }
    if str.eq(c.name, "pj") {
        let m = usize(x[3usize])
        let nn = usize(x[4usize + m])
        var fs: [64]f64 = zero
        ac.panjer(usize(x[0usize]), x[1usize], x[2usize], x[4usize..4usize + m], nn, fs[0usize..64usize])
        if usize(x[5usize + m]) == 0usize {
            var tot = 0.0f64
            var i = 0usize
            while i <= nn {
                tot += fs[i]
                i += 1usize
            }
            ret tot
        }
        var run = 0.0f64
        var sm = 0.0f64
        var j = 0usize
        while j <= nn {
            run += fs[j]
            sm += run * f64(j + 1usize)
            j += 1usize
        }
        ret sm
    }
    let fam = u8(x[0usize])
    let kind = u8(x[1usize])
    let s1 = x[2usize]
    let s2 = x[3usize]
    let s3 = x[4usize]
    let sc = x[5usize]
    let v = x[6usize]
    let k = x[7usize]
    let nm = c.name
    if fam == 0u8 {
        let (a, g, t) = ac.tb_params(kind, s1, s2, s3)
        if str.eq(nm, "d") { ret ac.tb_d(v, a, g, t, sc) }
        if str.eq(nm, "p") { ret ac.tb_p(v, a, g, t, sc) }
        if str.eq(nm, "q") { ret ac.tb_q(v, a, g, t, sc) }
        if str.eq(nm, "m") { ret ac.tb_m(k, a, g, t, sc) }
        ret ac.tb_lev(v, k, a, g, t, sc)
    }
    if fam == 1u8 {
        if str.eq(nm, "d") { ret ac.tg_d(v, s1, s2, sc) }
        if str.eq(nm, "p") { ret ac.tg_p(v, s1, s2, sc) }
        if str.eq(nm, "q") { ret ac.tg_q(v, s1, s2, sc) }
        if str.eq(nm, "m") { ret ac.tg_m(k, s1, s2, sc) }
        ret ac.tg_lev(v, k, s1, s2, sc)
    }
    if fam == 2u8 {
        var a = s1
        var t = s2
        if kind == 1u8 {
            a = s1
            t = 1.0f64
        }
        if kind == 2u8 {
            a = 1.0f64
            t = s1
        }
        if kind == 3u8 {
            a = 1.0f64
            t = 1.0f64
        }
        if str.eq(nm, "d") { ret ac.itg_d(v, a, t, sc) }
        if str.eq(nm, "p") { ret ac.itg_p(v, a, t, sc) }
        if str.eq(nm, "q") { ret ac.itg_q(v, a, t, sc) }
        if str.eq(nm, "m") { ret ac.itg_m(k, a, t, sc) }
        ret ac.itg_lev(v, k, a, t, sc)
    }
    if str.eq(nm, "d") { ret ac.p1_d(v, s1, sc) }
    if str.eq(nm, "p") { ret ac.p1_p(v, s1, sc) }
    if str.eq(nm, "q") { ret ac.p1_q(v, s1, sc) }
    if str.eq(nm, "m") { ret ac.p1_m(k, s1, sc) }
    ret ac.p1_lev(v, k, s1, sc)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/actuar.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
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
