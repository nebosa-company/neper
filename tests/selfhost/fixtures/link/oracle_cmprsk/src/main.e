// e.algo.stat.cmprsk.cinc against cmprsk::cuminc for one group. tests/oracle/cmprsk.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R cmprsk`; the layout is at the top of
// scripts/r_oracle/groups/cmprsk.R.

use e.algo.stat.cmprsk as cm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "gray") {
        let n = usize(z[0usize])
        let ng = usize(z[1usize])
        let nst = usize(z[2usize])
        let rho = z[3usize]
        let cause = z[4usize]
        let (m, g1) = mem.alloc[i64](a, n)
        let (gi, g2) = mem.alloc[i64](a, n)
        let (si, g3) = mem.alloc[i64](a, n)
        let (s, g4) = mem.alloc[f64](a, ng)
        let (vs, g5) = mem.alloc[f64](a, ng * ng)
        if g1 != ok || g2 != ok || g3 != ok || g4 != ok || g5 != ok { ret nan }
        var i = 0usize
        while i < n {
            let sv = z[5usize + n + i]
            m[i] = 0i64
            if sv != 0.0f64 { m[i] = 2i64 }
            if sv == cause { m[i] = 1i64 }
            gi[i] = i64(z[5usize + 2usize * n + i]) - 1i64
            si[i] = i64(z[5usize + 3usize * n + i]) - 1i64
            i += 1usize
        }
        ret cm.crstm(a, z[5usize..5usize + n], m, gi, si, nst, ng, rho, s, vs)
    }
    let n = usize(z[0usize])
    let tm = z[1usize..1usize + n]
    let st = z[1usize + n..1usize + 2usize * n]
    let cause = z[1usize + 2usize * n]
    let q = usize(z[2usize + 2usize * n])
    let (ic, e1) = mem.alloc[i64](a, n)
    let (icc, e2) = mem.alloc[i64](a, n)
    let (x, e3) = mem.alloc[f64](a, 2usize * n + 2usize)
    let (f, e4) = mem.alloc[f64](a, 2usize * n + 2usize)
    let (v, e5) = mem.alloc[f64](a, 2usize * n + 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
    var i = 0usize
    while i < n {
        ic[i] = 0i64
        icc[i] = 0i64
        if st[i] != 0.0f64 { ic[i] = 1i64 }
        if st[i] == cause { icc[i] = 1i64 }
        i += 1usize
    }
    let k = cm.cinc(tm, ic, icc, x, f, v)
    if q == 0usize { ret f64(k) }
    var s = 0.0f64
    i = 0usize
    while i < k {
        if q == 1usize { s += x[i] }
        if q == 2usize { s += f[i] }
        if q == 3usize { s += v[i] }
        if q == 6usize { s += f64(i + 1usize) * f[i] }
        if q == 7usize { s += f64(i + 1usize) * v[i] }
        i += 1usize
    }
    if q == 4usize { ret f[k - 1usize] }
    if q == 5usize { ret v[k - 1usize] }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/cmprsk.json")
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
