// e.algo.stat.kernlabgp against kernlab gausspr (regression). tests/oracle/kernlabgp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabgp`; the argument layout is at the top of scripts/r_oracle/groups/kernlabgp.R.

use e.algo.stat.kernlabgp as gp
use e.algo.stat.kernlabmmd as km
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let m = usize(z[0usize])
    let nt = usize(z[1usize])
    let p = usize(z[2usize])
    let kind = usize(z[3usize])
    let x = z[6usize..6usize + m * p]
    let y = z[6usize + m * p..6usize + m * p + m]
    let xt = z[6usize + m * p + m..6usize + m * p + m + nt * p]
    let (kk, e1) = mem.alloc[f64](a, m * m)
    let (inv, e2) = mem.alloc[f64](a, m * m)
    let (al, e3) = mem.alloc[f64](a, m)
    let (kt, e4) = mem.alloc[f64](a, nt * m)
    let (kx, e5) = mem.alloc[f64](a, m * m)
    let (pr, e6) = mem.alloc[f64](a, nt + m)
    let (ks, e7) = mem.alloc[f64](a, nt)
    let (one, e8) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret nan }
    km.cross(true, kind, x, x, m, m, p, z[4usize], 0.0f64, 0.0f64, kk)
    if gp.inverse(a, kk, m, z[5usize], inv) != ok { ret nan }
    gp.coefficients(inv, y, m, al)
    var src = al
    var n = m
    if str.eq(c.name, "fitted") {
        gp.predict(kk, al, m, m, pr)
        src = pr
    }
    if str.eq(c.name, "pred") || str.eq(c.name, "sdev") {
        km.cross(false, kind, xt, x, nt, m, p, z[4usize], 0.0f64, 0.0f64, kt)
        gp.predict(kt, al, m, nt, pr)
        src = pr
        n = nt
        if str.eq(c.name, "sdev") {
            var t = 0usize
            while t < nt {
                km.cross(true, kind, xt[t * p..(t + 1usize) * p], xt[t * p..(t + 1usize) * p], 1usize, 1usize, p, z[4usize], 0.0f64, 0.0f64, one)
                ks[t] = one[0usize]
                t += 1usize
            }
            gp.variance(kt, inv, ks, m, nt, pr)
            t = 0usize
            while t < nt {
                pr[t] = math.sqrt[f64](pr[t])
                t += 1usize
            }
        }
    }
    if str.eq(c.name, "fitted") { n = m }
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += src[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabgp.json")
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
