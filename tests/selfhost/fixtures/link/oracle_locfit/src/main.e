// e.algo.stat.locfitpkg against locfit (one predictor). tests/oracle/locfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R locfit`; the argument layout is at the top of
// scripts/r_oracle/groups/locfit.R.

use e.algo.stat.locfitpkg as lf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let x = z[14usize..14usize + n]
    let (y, ey) = mem.alloc[f64](a, 2usize * n)
    if ey != ok { ret nan }
    var k0 = 0usize
    while k0 < n {
        y[k0] = z[14usize + n + k0]
        y[n + k0] = 1.0f64
        if z.len >= 14usize + 3usize * n + 1usize { y[n + k0] = z[15usize + 2usize * n + k0] }
        k0 += 1usize
    }
    var rob = 0.0f64
    if z.len >= 14usize + 3usize * n + 1usize { rob = z[14usize + 2usize * n] }
    var m = usize(z[10usize])
    if str.eq(c.name, "plotfit") || str.eq(c.name, "plotse") { m = 100usize }
    var spa = [14]f64{ z[1usize], z[2usize], z[3usize], z[4usize], z[5usize], z[6usize], z[7usize], z[8usize], z[9usize], z[11usize], z[12usize], 0.0f64, z[13usize], rob }
    let sp = spa[0usize..14usize]
    var (pc, e0) = lf.pcomp(a, x, y, sp)
    if e0 != ok { ret nan }
    let cap = 4096usize
    let (vt, e1) = mem.alloc[f64](a, cap * lf.VS)
    if e1 != ok { ret nan }
    let (nv, e2) = lf.build(a, x, y, sp, &pc, vt, cap)
    if e2 != ok { ret nan }
    let nm = c.name
    if str.eq(nm, "nv") { ret f64(nv) }
    var col = 99usize
    if str.eq(nm, "vx") { col = lf.V_X }
    if str.eq(nm, "vh") { col = lf.V_H }
    if str.eq(nm, "vc0") { col = lf.V_C0 }
    if str.eq(nm, "vc1") { col = lf.V_C1 }
    if str.eq(nm, "vn0") { col = lf.V_N0 }
    if str.eq(nm, "vn1") { col = lf.V_N1 }
    if str.eq(nm, "vt0") { col = lf.V_T0 }
    if str.eq(nm, "vt1") { col = lf.V_T1 }
    if str.eq(nm, "vl0") { col = lf.V_LIK }
    if col != 99usize {
        var s = 0.0f64
        var i = 0usize
        while i < nv {
            s += vt[i * lf.VS + col] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "vl1") {
        var s = 0.0f64
        var i = 0usize
        while i < nv {
            s += vt[i * lf.VS + lf.V_TR2] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(nm, "vl2") {
        var s = 0.0f64
        var i = 0usize
        while i < nv {
            s += (vt[i * lf.VS + lf.V_TR0] - vt[i * lf.VS + lf.V_TR2]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    let fam = lf.famcode(sp)
    if str.eq(nm, "fit") {
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += lf.trans(fam, lf.at_data(vt, nv, sp, &pc, lf.W_COEF, x, i)) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    var sma = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let sm = sma[0usize..4usize]
    lf.summ(x, y, sp, &pc, vt, nv, sm)
    let nf = f64(n)
    if str.eq(nm, "lk") { ret sm[0usize] }
    if str.eq(nm, "df0") { ret sm[1usize] }
    if str.eq(nm, "df1") { ret sm[2usize] }
    if str.eq(nm, "rv") { ret sm[3usize] }
    if str.eq(nm, "gcv") { ret (0.0f64 - 2.0f64 * nf * sm[0usize]) / ((nf - sm[1usize]) * (nf - sm[1usize])) }
    if str.eq(nm, "cp") { ret 0.0f64 - 2.0f64 * sm[0usize] - nf + 2.0f64 * sm[1usize] }
    if str.eq(nm, "aic") { ret 0.0f64 - 2.0f64 * sm[0usize] + 2.0f64 * sm[1usize] }
    var lo = x[0usize]
    var hi = x[n - 1usize]
    var kind = 9usize
    if str.eq(nm, "pred") { kind = 3usize }
    if str.eq(nm, "seg") { kind = 0usize }
    if str.eq(nm, "sel") { kind = 1usize }
    if str.eq(nm, "sep") { kind = 2usize }
    if str.eq(nm, "plotfit") { kind = 3usize }
    if str.eq(nm, "plotse") { kind = 0usize }
    var s = 0.0f64
    var i = 0usize
    while i < m {
        var x0 = lo + f64(i) * ((hi - lo) / f64(m - 1usize))
        if i == m - 1usize { x0 = hi }
        var v = 0.0f64
        if kind == 3usize {
            v = lf.trans(fam, lf.at(vt, nv, sp, &pc, lf.W_COEF, x0))
        } else {
            v = lf.se(vt, nv, sp, &pc, sm[3usize], x0, kind)
        }
        s += v * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn brief(a: *mem.Arena, c: *const oracle.Case, got: f64) -> str {
    let (initial, be) = str.builder(a, 200usize)
    if be != ok { ret c.name }
    var b = initial
    let _ = str.push(&b, c.name)
    let _ = str.push(&b, " cfg")
    var at = 0usize
    while at < 13usize {
        let _ = str.push(&b, " ")
        let _ = str.push_f64(&b, c.args[at])
        at += 1usize
    }
    let _ = str.push(&b, " got ")
    let _ = str.push_f64(&b, got)
    let _ = str.push(&b, " R ")
    let _ = str.push_f64(&b, c.want)
    ret str.done(&b)
}

fn run(a: *mem.Arena, path: str) -> usize {
    let (golden, load_error) = oracle.load(a, path)
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
            if failures <= 40usize {
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    ret failures
}

fn main(a: *mem.Arena, args: []str) -> err {
    var failures = run(a, "tests/oracle/locfit.json")
    failures += run(a, "tests/oracle/locfit_adapt.json")
    failures += run(a, "tests/oracle/locfit_family.json")
    failures += run(a, "tests/oracle/locfit_more.json")
    failures += run(a, "tests/oracle/locfit_mindex.json")
    if failures > 0usize { os.exit(1) }
    ret ok
}
