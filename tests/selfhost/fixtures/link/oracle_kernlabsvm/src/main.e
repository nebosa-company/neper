// e.algo.stat.kernlabsvm against kernlab ksvm (C-svc, nu-svc, one-svc, eps-svr, nu-svr). tests/oracle/kernlabsvm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabsvm`; the argument layout is at the top of scripts/r_oracle/groups/kernlabsvm.R.

use e.algo.stat.kernlabmmd as kmm
use e.algo.stat.kernlabsvm as ks
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let sv = usize(z[3usize])
    let y = z[10usize..10usize + n]
    let x = z[10usize + n..10usize + n + n * p]
    let par = ks.Param { ktype: usize(z[2usize]), svm: sv, c: z[4usize], nu: z[5usize], p: z[6usize], gamma: z[7usize], degree: i64(z[8usize]), coef0: z[9usize], tol: 0.001f64, shrinking: true, cp: z[4usize], cn: z[4usize] }
    let (out, e1) = mem.alloc[f64](a, n)
    let (xsq, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    let (rho, obj, e) = ks.smo_optim(a, x, n, p, y, &par, out)
    if e != ok { ret nan }
    if str.eq(c.name, "rho") { ret rho }
    if str.eq(c.name, "obj") { ret obj }
    var i = 0usize
    if sv == 0usize {
        while i < n {
            out[i] = out[i] * y[i]
            i += 1usize
        }
    }
    var s = 0.0f64
    if str.eq(c.name, "alpha") {
        i = 0usize
        while i < n {
            s += out[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    i = 0usize
    while i < n {
        var d = 0.0f64
        var k = 0usize
        while k < p {
            d += x[i * p + k] * x[i * p + k]
            k += 1usize
        }
        xsq[i] = d
        i += 1usize
    }
    // kernelMatrix of R, which rounds the squared distances of the Bessel kernel to nine places
    let (kk, e6) = mem.alloc[f64](a, n * n)
    if e6 != ok { ret nan }
    if par.ktype == 6usize { kmm.cross(true, 7usize, x, x, n, n, p, par.gamma, f64(par.degree), par.coef0, kk) }
    i = 0usize
    while i < n {
        var d = 0.0f64 - rho
        var j = 0usize
        while j < n {
            if out[j] != 0.0f64 {
                if par.ktype == 6usize {
                    d += out[j] * kk[i * n + j]
                } else {
                    d += out[j] * ks.kval(&par, x, p, xsq, i, j)
                }
            }
            j += 1usize
        }
        s += d * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabsvm.json")
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
