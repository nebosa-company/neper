// e.algo.stat.locfitband against locfit's crit() and scb(). tests/oracle/locfit_band.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R locfit_band`; the argument layout is at the top of
// scripts/r_oracle/groups/locfit_band.R.

use e.algo.stat.locfitband as lb
use e.algo.stat.locfitpkg as lf
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nm = c.name
    if str.eq(nm, "crit") {
        var ka = [2]f64{ z[0usize], z[1usize] }
        let k = ka[0usize..2usize]
        ret lb.critval(1.0f64 - z[3usize], k, usize(z[2usize]), 1usize, z[4usize])
    }
    let n = usize(z[0usize])
    let x = z[14usize..14usize + n]
    let (y, ey) = mem.alloc[f64](a, 2usize * n)
    if ey != ok { ret nan }
    var q0 = 0usize
    while q0 < n {
        y[q0] = z[14usize + n + q0]
        y[n + q0] = 1.0f64
        q0 += 1usize
    }
    var spa = [14]f64{ z[1usize], z[2usize], z[3usize], z[4usize], z[5usize], z[6usize], z[7usize], z[8usize], z[9usize], z[11usize], z[12usize], 0.0f64, z[13usize], 0.0f64 }
    let sp = spa[0usize..14usize]
    var (pc, e0) = lf.pcomp(a, x, y, sp)
    if e0 != ok { ret nan }
    pc.on = false
    let (k0, e1) = lb.kappa0(a, x, y, sp, &pc, usize(z[8usize]))
    if str.eq(nm, "kok") {
        if e1 != ok { ret 0.0f64 }
        ret 1.0f64
    }
    if e1 != ok { ret nan }
    if str.eq(nm, "k0") { ret k0 }
    if str.eq(nm, "k1") { ret 1.0f64 }
    var kap = [2]f64{ k0, 1.0f64 }
    let kk = kap[0usize..2usize]
    let cr = lb.critval(0.05f64, kk, 2usize, 1usize, 0.0f64)
    if str.eq(nm, "cr") { ret cr }
    let cap = 256usize
    let (vt, e2) = mem.alloc[f64](a, cap * lf.VS)
    if e2 != ok { ret nan }
    spa[5usize] = 3.0f64
    spa[7usize] = 20.0f64
    let (nv, e3) = lf.build(a, x, y, sp, &pc, vt, cap)
    if e3 != ok { ret nan }
    var sma = [4]f64{ 0.0f64, 0.0f64, 0.0f64, 0.0f64 }
    let sm = sma[0usize..4usize]
    lf.summ(x, y, sp, &pc, vt, nv, sm)
    let sig = math.sqrt[f64](sm[3usize])
    var s = 0.0f64
    var i = 0usize
    while i < nv {
        let th = vt[i * lf.VS + lf.V_C0]
        let nl = vt[i * lf.VS + lf.V_N0]
        var v = th
        if str.eq(nm, "sd") { v = nl }
        if str.eq(nm, "lo") { v = th - cr * sig * nl }
        if str.eq(nm, "up") { v = th + cr * sig * nl }
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
    while at < 13usize && at < c.args.len {
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

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/locfit_band.json")
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
            if failures <= 60usize {
                let _ = io.print(brief(a, c, got))
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
