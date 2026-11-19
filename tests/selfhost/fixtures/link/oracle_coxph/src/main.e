// e.algo.stat.cox against survival::coxph (Breslow and Efron ties). tests/oracle/coxph.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R coxph`; the layout is at the top of
// scripts/r_oracle/groups/coxph.R.

use e.algo.stat.cox as cx
use e.algo.stat.coxext as cs
use e.str
use e.math.special as spx
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "cres") {
        let rn = usize(x[0usize])
        let rp = usize(x[1usize])
        let (sg3, ge3) = mem.alloc[usize](a, rn)
        if ge3 != ok { ret 0.0f64 / 0.0f64 }
        var q3 = 0usize
        while q3 < rn {
            sg3[q3] = usize(x[3usize + 2usize * rn + q3])
            q3 += 1usize
        }
        ret cs.cox_resid(a, x[3usize..3usize + rn], x[3usize + rn..3usize + 2usize * rn], sg3, x[3usize + 3usize * rn..3usize + 4usize * rn], x[3usize + 4usize * rn..3usize + 4usize * rn + rn * rp], rn, rp, usize(x[2usize]), usize(x[3usize + 4usize * rn + rn * rp]))
    }
    if str.eq(c.name, "zph") {
        let zn = usize(x[0usize])
        let zp = usize(x[1usize])
        let (zo, zoe) = mem.alloc[f64](a, zp + 1usize)
        if zoe != ok { ret 0.0f64 / 0.0f64 }
        if cs.cox_zph(a, x[3usize..3usize + zn], x[3usize + zn..3usize + 2usize * zn], x[3usize + 2usize * zn..3usize + 2usize * zn + zn * zp], zn, zp, usize(x[2usize]), zo) != ok { ret 0.0f64 / 0.0f64 }
        let zq = usize(x[3usize + 2usize * zn + zn * zp])
        if zq <= zp { ret zo[zq] }
        // p values: 1 - chi-square cdf with df 1 for a term, zp for the global
        let ix = zq - zp - 1usize
        var df = 1.0f64
        if ix == zp { df = f64(zp) }
        ret 1.0f64 - spx.chi_squared_cdf(zo[ix], df)
    }
    if str.eq(c.name, "coxcp") {
        let cn = usize(x[0usize])
        let cpp = usize(x[1usize])
        let (cg, cge) = mem.alloc[usize](a, cn)
        let (ccf, cce) = mem.alloc[f64](a, cpp)
        let (cse, cse_e) = mem.alloc[f64](a, cpp)
        let (cll, cle) = mem.alloc[f64](a, 2usize)
        if cge != ok || cce != ok || cse_e != ok || cle != ok { ret 0.0f64 / 0.0f64 }
        var cq = 0usize
        while cq < cn {
            cg[cq] = usize(x[3usize + 3usize * cn + cq])
            cq += 1usize
        }
        let cfe = cs.coxph_cp(a, x[3usize..3usize + cn], x[3usize + cn..3usize + 2usize * cn], x[3usize + 2usize * cn..3usize + 3usize * cn], cg, x[3usize + 4usize * cn..3usize + 4usize * cn + cn * cpp], cn, cpp, x[2usize] != 0.0f64, ccf, cse, cll)
        if cfe != ok { ret 0.0f64 / 0.0f64 }
        let cqq = usize(x[3usize + 4usize * cn + cn * cpp])
        if cqq < cpp { ret ccf[cqq] }
        if cqq < 2usize * cpp { ret cse[cqq - cpp] }
        ret cll[cqq - 2usize * cpp]
    }
    if str.eq(c.name, "coxs") {
        let sn = usize(x[0usize])
        let sp = usize(x[1usize])
        let (sg, ge) = mem.alloc[usize](a, sn)
        let (cf2, ce) = mem.alloc[f64](a, sp)
        let (se2, se_e) = mem.alloc[f64](a, sp)
        let (ll2, le) = mem.alloc[f64](a, 2usize)
        if ge != ok || ce != ok || se_e != ok || le != ok { ret 0.0f64 / 0.0f64 }
        var qq = 0usize
        while qq < sn {
            sg[qq] = usize(x[4usize + 2usize * sn + qq])
            qq += 1usize
        }
        let fe2 = cs.coxph_s(a, x[4usize..4usize + sn], x[4usize + sn..4usize + 2usize * sn], sg, x[4usize + 3usize * sn..4usize + 4usize * sn], x[4usize + 4usize * sn..4usize + 4usize * sn + sn * sp], sn, sp, x[2usize] != 0.0f64, x[3usize] != 0.0f64, cf2, se2, ll2)
        if fe2 != ok { ret 0.0f64 / 0.0f64 }
        let q2 = usize(x[4usize + 4usize * sn + sn * sp])
        if q2 < sp { ret cf2[q2] }
        if q2 < 2usize * sp { ret se2[q2 - sp] }
        ret ll2[1usize]
    }
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let tm = x[3usize..3usize + n]
    let st = x[3usize + n..3usize + 2usize * n]
    let xm = x[3usize + 2usize * n..3usize + 2usize * n + n * p]
    let q = usize(x[3usize + 2usize * n + n * p])
    let (coef, e1) = mem.alloc[f64](a, p)
    let (se, e2) = mem.alloc[f64](a, p)
    let (ll, e3) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    let fe = cx.coxph(a, tm, st, xm, n, p, x[2usize] != 0.0f64, coef, se, ll)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    if q < p { ret coef[q] }
    if q < 2usize * p { ret se[q - p] }
    ret ll[q - 2usize * p]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/coxph.json")
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
