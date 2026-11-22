// e.algo.stat.hetgppkg against hetGP's mleHetGP and predict.hetGP. tests/oracle/hetgphet.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R hetgphet`; the layout is at the top of scripts/r_oracle/groups/hetgphet.R.

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
    let mp = usize(z[13usize])
    var o: hg.HetOpt = zero
    o.ctype = usize(z[3usize])
    o.has_th = z[4usize] != 0.0f64
    o.has_g = z[5usize] != 0.0f64
    o.has_kt = z[6usize] != 0.0f64
    o.has_b0 = z[7usize] != 0.0f64
    o.g = z[8usize]
    o.kt = z[9usize]
    o.b0 = z[10usize]
    let user = z[11usize] != 0.0f64
    o.auto_lo = !user
    o.auto_up = !user
    o.maxit = usize(z[12usize])
    o.factr = 1000000000.0f64
    o.eps = 1.4901161193847656e-8f64
    o.penalty = true
    o.check_hom = true
    var p = 20usize
    o.lower = z[p..p + d]
    p += d
    o.upper = z[p..p + d]
    p += d
    o.th = z[p..p + d]
    p += d
    let x = z[p..p + nn * d]
    p += nn * d
    let y = z[p..p + nn]
    p += nn
    let xt = z[p..p + m * d]
    p += m * d
    let xp = z[p..p + mp * d]
    p += mp * d
    let (x0, e1) = mem.alloc[f64](a, nn * d)
    let (z0, e2) = mem.alloc[f64](a, nn)
    let (mult, e3) = mem.alloc[f64](a, nn)
    let (zs, e4) = mem.alloc[f64](a, nn)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    let (n, e5) = hg.find_reps(a, x, y, nn, d, x0, z0, mult, zs)
    o.has_dl = z[16usize] != 0.0f64
    if o.has_dl { o.dl = z[p..p + n] }
    if e5 != ok { ret nan }
    if str.eq(c.name, "llraw") || str.eq(c.name, "llpen") || str.eq(c.name, "grad") {
        let (gr, e11) = mem.alloc[f64](a, d + n + 2usize)
        if e11 != ok { ret nan }
        let pen = !str.eq(c.name, "llraw")
        let (v, ee) = hg.het_eval(a, x0, z0, zs, mult, n, d, nn, &o, o.th, z[p..p + n], o.kt, o.g, z[17usize], pen, gr)
        if ee != ok { ret nan }
        if str.eq(c.name, "grad") { ret wsum(gr, d + n + 2usize) }
        ret v
    }
    var f: hg.HetFit = zero
    if hg.het_fit(a, x0, z0, zs, mult, n, d, nn, &o, &f) != ok { ret nan }
    let nnew = usize(z[18usize])
    var nt = n
    if nnew > 0usize {
        let xn = z[p + n..p + n + nnew * d]
        let zn = z[p + n + nnew * d..p + n + nnew * d + nnew]
        var g2: hg.HetFit = zero
        if hg.het_update0(a, &f, xn, zn, nnew, &g2) != ok { ret nan }
        f = g2
        nt = f.n
    }
    if str.eq(c.name, "ishet") {
        if f.is_hom { ret 0.0f64 }
        ret 1.0f64
    }
    if f.is_hom {
        if str.eq(c.name, "theta") { ret wsum(f.hom.theta, d) }
        if str.eq(c.name, "g") { ret f.hom.g }
        if str.eq(c.name, "nu") { ret f.hom.nu }
        if str.eq(c.name, "ll") { ret f.hom.ll }
        if str.eq(c.name, "beta0") { ret f.hom.beta0 }
    } else {
        if str.eq(c.name, "theta") { ret wsum(f.theta, d) }
        if str.eq(c.name, "g") { ret f.g }
        if str.eq(c.name, "kt") { ret f.kt }
        if str.eq(c.name, "nu") { ret f.nu }
        if str.eq(c.name, "ll") { ret f.ll }
        if str.eq(c.name, "llnp") { ret f.ll_np }
        if str.eq(c.name, "beta0") { ret f.beta0 }
        if str.eq(c.name, "delta") { ret wsum(f.dl, nt) }
        if str.eq(c.name, "lam") { ret wsum(f.lam, nt) }
    }
    let (mean, e6) = mem.alloc[f64](a, m)
    let (sd2, e7) = mem.alloc[f64](a, m)
    let (nugs, e8) = mem.alloc[f64](a, m)
    let (sdv, e10) = mem.alloc[f64](a, m)
    let (cv, e9) = mem.alloc[f64](a, m * mp + 1usize)
    if e6 != ok || e7 != ok || e8 != ok || e9 != ok || e10 != ok { ret nan }
    if str.eq(c.name, "ei") || str.eq(c.name, "logei") {
        let has_cst = z[14usize] != 0.0f64
        let lg = str.eq(c.name, "logei")
        var ee = ok
        if f.is_hom {
            ee = hg.hom_ei(a, &f.hom, xt, m, has_cst, z[15usize], lg, mean)
        } else {
            ee = hg.hom_ei(a, &f.hv, xt, m, has_cst, z[15usize], lg, mean)
        }
        if ee != ok { ret nan }
        ret wsum(mean, m)
    }
    if hg.het_predict(a, &f, xt, m, xp, mp, mean, sd2, nugs, sdv, cv) != ok { ret nan }
    if str.eq(c.name, "mean") { ret wsum(mean, m) }
    if str.eq(c.name, "sd2") { ret wsum(sd2, m) }
    if str.eq(c.name, "nugs") { ret wsum(nugs, m) }
    if str.eq(c.name, "sd2var") { ret wsum(sdv, m) }
    if str.eq(c.name, "cov") { ret wsum(cv, m * mp) }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/hetgphet.json")
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
