// e.algo.stat.systemfitpkg against systemfit SUR. tests/oracle/systemfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R systemfit`; the layout is at the top of scripts/r_oracle/groups/systemfit.R.

use e.algo.stat.systemfitpkg as sf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let m = usize(z[1usize])
    let passes = usize(z[2usize])
    let dfc = z[3usize] > 0.5f64
    let (ks, e1) = mem.alloc[usize](a, m)
    if e1 != ok { ret nan }
    var kt = 0usize
    var i = 0usize
    while i < m {
        ks[i] = usize(z[4usize + i])
        kt += ks[i]
        i += 1usize
    }
    var nulv: [1]f64 = zero
    let (coef, e2) = mem.alloc[f64](a, kt)
    let (se, e3) = mem.alloc[f64](a, kt)
    let (sig, e4) = mem.alloc[f64](a, m * m)
    if e2 != ok || e3 != ok || e4 != ok { ret nan }
    let y = z[4usize + m..4usize + m + m * n]
    let xs = z[4usize + m + m * n..4usize + m + m * n + n * kt]
    if c.name.len >= 4usize && c.name[0usize] == 114u8 && c.name[1usize] == 115u8 {
        let xe = 4usize + m + m * n + n * kt
        let nr = usize(z[xe])
        let (dvm2, ed) = mem.alloc[f64](a, 1usize)
        if ed != ok { ret nan }
        var dv2 = 0usize
        if dfc { dv2 = 1usize }
        if sf.surm(a, xs, ks, y, n, m, dv2, passes, z[xe + 1usize..xe + 1usize + nr * kt], z[xe + 1usize + nr * kt..xe + 1usize + nr * kt + nr], nr, coef, se, sig) != ok { ret nan }
        var s2 = 0.0f64
        var cnt2 = kt
        var src2 = coef
        if c.name[2usize] == 115u8 && c.name[3usize] == 101u8 { src2 = se }
        if c.name[2usize] == 115u8 && c.name[3usize] == 105u8 {
            src2 = sig
            cnt2 = m * m
        }
        var i3 = 0usize
        while i3 < cnt2 {
            s2 += src2[i3] * f64(i3 + 1usize)
            i3 += 1usize
        }
        let _ = dvm2
        ret s2
    }
    if c.name.len > 2usize && c.name[0usize] == 105u8 && c.name[1usize] == 116u8 {
        let (itn, eit) = sf.sur_iter(a, xs, ks, y, n, m, dfc, passes, 1.0e-5f64, coef, se, sig)
        if eit != ok { ret nan }
        if str.eq(c.name, "itn") { ret f64(itn) }
    } else {
        var dvm = 0usize
        if dfc { dvm = 1usize }
        if z[3usize] > 1.5f64 { dvm = usize(z[3usize]) }
        if sf.surm(a, xs, ks, y, n, m, dvm, passes, nulv[0usize..1usize], nulv[0usize..1usize], 0usize, coef, se, sig) != ok { ret nan }
    }
    var s = 0.0f64
    var cnt = kt
    var src = coef
    if str.eq(c.name, "se") || str.eq(c.name, "itse") || str.eq(c.name, "mxse") || str.eq(c.name, "thse") { src = se }
    if str.eq(c.name, "sig") || str.eq(c.name, "itsig") || str.eq(c.name, "mxsig") || str.eq(c.name, "thsig") {
        src = sig
        cnt = m * m
    }
    i = 0usize
    while i < cnt {
        s += src[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/systemfit.json")
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
