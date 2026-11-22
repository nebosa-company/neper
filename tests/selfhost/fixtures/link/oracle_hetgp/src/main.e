// e.algo.stat.hetgppkg against hetGP's homoskedastic models. tests/oracle/hetgp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hetgp`; the layout is at the top of scripts/r_oracle/groups/hetgp.R.

use e.algo.stat.hetgppkg as hg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nn = usize(z[0usize])
    let d = usize(z[1usize])
    let m = usize(z[2usize])
    let mp = usize(z[11usize])
    let nnew = usize(z[12usize])
    var o: hg.HomOpt = zero
    o.ctype = usize(z[3usize])
    o.has_theta = z[4usize] != 0.0f64
    o.has_g = z[5usize] != 0.0f64
    o.has_beta0 = z[6usize] != 0.0f64
    o.g = z[7usize]
    o.beta0 = z[8usize]
    let user = z[9usize] != 0.0f64
    o.auto_lo = !user
    o.auto_up = !user
    o.maxit = usize(z[10usize])
    o.gmin = 1.4901161193847656e-8f64
    o.gmax = 100.0f64
    o.factr = 10000000.0f64
    o.eps = 1.4901161193847656e-8f64
    var p = 16usize
    o.lower = z[p..p + d]
    p += d
    o.upper = z[p..p + d]
    p += d
    o.theta = z[p..p + d]
    p += d
    let x = z[p..p + nn * d]
    p += nn * d
    let y = z[p..p + nn]
    p += nn
    let xt = z[p..p + m * d]
    p += m * d
    let xp = z[p..p + mp * d]
    p += mp * d
    let xn = z[p..p + nnew * d]
    p += nnew * d
    let yn = z[p..p + nnew]
    let (x0, e1) = mem.alloc[f64](a, nn * d)
    let (z0, e2) = mem.alloc[f64](a, nn)
    let (mult, e3) = mem.alloc[f64](a, nn)
    let (zs, e4) = mem.alloc[f64](a, nn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    let (n, e5) = hg.find_reps(a, x, y, nn, d, x0, z0, mult, zs)
    if e5 != ok { ret nan }
    var f: hg.HomFit = zero
    if hg.hom_fit(a, x0, z0, zs, mult, n, d, nn, &o, &f) != ok { ret nan }
    if nnew > 0usize {
        var g: hg.HomFit = zero
        let maxit_up = usize(z[13usize])
        var eu = ok
        if maxit_up == 0usize {
            eu = hg.hom_update0(a, &f, xn, yn, nnew, &g)
        } else {
            eu = hg.hom_update_fit(a, &f, xn, yn, nnew, maxit_up, &g)
        }
        if eu != ok { ret nan }
        f = g
    }
    if str.eq(c.name, "theta") { ret wsum(f.theta, d) }
    if str.eq(c.name, "g") { ret f.g }
    if str.eq(c.name, "nu") { ret f.nu }
    if str.eq(c.name, "ll") { ret f.ll }
    if str.eq(c.name, "beta0") { ret f.beta0 }
    if str.eq(c.name, "lo") { ret wsum(f.lower, d) }
    if str.eq(c.name, "up") { ret wsum(f.upper, d) }
    let (mean, e6) = mem.alloc[f64](a, m)
    let (sd2, e7) = mem.alloc[f64](a, m)
    let (nugs, e8) = mem.alloc[f64](a, m)
    let (cv, e9) = mem.alloc[f64](a, m * mp + 1usize)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok { ret nan }
    if str.eq(c.name, "ei") || str.eq(c.name, "logei") {
        let has_cst = z[14usize] != 0.0f64
        if hg.hom_ei(a, &f, xt, m, has_cst, z[15usize], str.eq(c.name, "logei"), mean) != ok { ret nan }
        ret wsum(mean, m)
    }
    if hg.hom_predict(a, &f, xt, m, xp, mp, mean, sd2, nugs, cv) != ok { ret nan }
    if str.eq(c.name, "mean") { ret wsum(mean, m) }
    if str.eq(c.name, "sd2") { ret wsum(sd2, m) }
    if str.eq(c.name, "nugs") { ret wsum(nugs, m) }
    if str.eq(c.name, "cov") { ret wsum(cv, m * mp) }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hetgp.json")
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
