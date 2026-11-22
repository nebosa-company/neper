// e.algo.stat.kernlabsig against kernlab sigest and ksvm's automatic sigma. tests/oracle/kernlabsig.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabsig`; the argument layout is at the top of scripts/r_oracle/groups/kernlabsig.R.

use e.algo.rand.r as rr
use e.algo.stat.kernlabclass as cl
use e.algo.stat.kernlabsig as sg
use e.algo.stat.kernlabsvm as ks
use e.io
use e.math
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
    var g: rr.Rng = zero
    if str.eq(c.name, "sigest") {
        let m = usize(z[0usize])
        let nf = usize(z[1usize])
        rr.seed(&g, i64(z[4usize]))
        var sr: [3]f64 = zero
        let e = sg.sigest(a, &g, z[5usize..5usize + m * nf], m, nf, z[2usize], z[3usize] != 0.0f64, sr[0usize..3usize])
        if e != ok { ret nan }
        ret wsum(sr[0usize..3usize], 3usize)
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let kc = usize(z[2usize])
    rr.seed(&g, i64(z[4usize]))
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (cen, e2) = mem.alloc[f64](a, p)
    let (scl, e3) = mem.alloc[f64](a, p)
    let (cls, e4) = mem.alloc[usize](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
    var i = 0usize
    while i < n {
        cls[i] = usize(z[5usize + i]) - 1usize
        i += 1usize
    }
    i = 0usize
    while i < n * p {
        x[i] = z[5usize + n + i]
        i += 1usize
    }
    if cl.scale_cols(a, x, n, p, cen, scl) != ok { ret nan }
    let (sigma, e5) = sg.auto_sigma(a, &g, x, n, p)
    if e5 != ok { ret nan }
    if str.eq(c.name, "sigma") { ret sigma }
    let np = kc * (kc - 1usize) / 2usize
    let (coef, e6) = mem.alloc[f64](a, np * n)
    let (bout, e7) = mem.alloc[f64](a, np)
    let (ob, e8) = mem.alloc[f64](a, np)
    if e6 != ok || e7 != ok || e8 != ok { ret nan }
    let par = ks.Param { ktype: 2usize, svm: 0usize, c: z[3usize], nu: 0.2f64, p: 0.1f64, gamma: sigma, degree: 1i64, coef0: 0.0f64, tol: 0.001f64, shrinking: true, cp: z[3usize], cn: z[3usize] }
    let empty = coef[0usize..0usize]
    if cl.fit_class(a, x, n, p, cls, kc, &par, empty, coef, bout, ob) != ok { ret nan }
    if str.eq(c.name, "coef") { ret wsum(coef, np * n) }
    ret wsum(bout, np)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabsig.json")
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
