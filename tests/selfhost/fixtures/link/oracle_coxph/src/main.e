// e.algo.stat.cox against survival::coxph (Breslow and Efron ties). tests/oracle/coxph.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R coxph`; the layout is at the top of
// scripts/r_oracle/groups/coxph.R.

use e.algo.stat.cox as cx
use e.algo.stat.coxext as cs
use e.str
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
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
