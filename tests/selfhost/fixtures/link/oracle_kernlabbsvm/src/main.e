// e.algo.stat.kernlabbsvm and kernlabbpred against kernlab ksvm (C-bsvc, eps-bsvr, kbb-svc, spoc-svc). tests/oracle/kernlabbsvm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabbsvm`; the argument layout is at the top of scripts/r_oracle/groups/kernlabbsvm.R.

use e.algo.stat.kernlabbpred as bp
use e.algo.stat.kernlabbsvm as bs
use e.algo.stat.kernlabmmd as kmm
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

fn two(a: *mem.Arena, c: *const oracle.Case, lam: *f64) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let sv = usize(z[3usize])
    let y = z[9usize..9usize + n]
    let x = z[9usize + n..9usize + n + n * p]
    let par = ks.Param { ktype: usize(z[2usize]), svm: sv, c: z[4usize], nu: 0.1f64, p: z[5usize], gamma: z[6usize], degree: i64(z[7usize]), coef0: z[8usize], tol: 0.001f64, shrinking: true, cp: z[4usize], cn: z[4usize] }
    let (out, e1) = mem.alloc[f64](a, n)
    let (xsq, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    var obj = 0.0f64
    var e = ok
    if sv == 5usize {
        let (o, e3) = bs.bsvc(a, x, n, p, y, &par, lam, out)
        obj = o
        e = e3
    } else {
        let (o, e3) = bs.bsvr(a, x, n, p, y, &par, lam, out)
        obj = o
        e = e3
    }
    if e != ok { ret nan }
    var i = 0usize
    var sum = 0.0f64
    if sv == 5usize {
        while i < n {
            out[i] = out[i] * y[i]
            i += 1usize
        }
    }
    i = 0usize
    while i < n {
        sum += out[i]
        i += 1usize
    }
    let b = 0.0f64 - sum
    if str.eq(c.name, "obj") { ret obj }
    if str.eq(c.name, "b") { ret b }
    if str.eq(c.name, "alpha") { ret wsum(out, n) }
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
    var s = 0.0f64
    // kernelMatrix of R, which rounds the squared distances of the Bessel kernel to nine places
    let (kk, e6) = mem.alloc[f64](a, n * n)
    if e6 != ok { ret nan }
    if par.ktype == 6usize { kmm.cross(true, 7usize, x, x, n, n, p, par.gamma, f64(par.degree), par.coef0, kk) }
    i = 0usize
    while i < n {
        var d = 0.0f64 - b
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

fn multi(a: *mem.Arena, c: *const oracle.Case, lam: *f64) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let kc = usize(z[2usize])
    let sv = usize(z[4usize])
    let nt = usize(z[9usize])
    let (cls, e0) = mem.alloc[usize](a, n)
    let (cnt, e00) = mem.alloc[usize](a, kc)
    if e0 != ok || e00 != ok { ret nan }
    var i = 0usize
    while i < kc {
        cnt[i] = 0usize
        i += 1usize
    }
    i = 0usize
    while i < n {
        cls[i] = usize(z[10usize + i])
        cnt[cls[i]] += 1usize
        i += 1usize
    }
    let x = z[10usize + n..10usize + n + n * p]
    let xt = z[10usize + n + n * p..10usize + n + n * p + nt * p]
    let par = ks.Param { ktype: usize(z[3usize]), svm: 0usize, c: z[5usize], nu: 0.1f64, p: 0.1f64, gamma: z[6usize], degree: i64(z[7usize]), coef0: z[8usize], tol: 0.001f64, shrinking: true, cp: z[5usize], cn: z[5usize] }
    let (resp, e1) = mem.alloc[usize](a, nt)
    let (wc, e2) = mem.alloc[f64](a, kc)
    if e1 != ok || e2 != ok { ret nan }
    i = 0usize
    while i < kc {
        wc[i] = z[5usize]
        i += 1usize
    }
    var obj = 0.0f64
    var mainv = 0.0f64
    var bv = 0.0f64
    var e = ok
    if sv == 5usize {
        let np = kc * (kc - 1usize) / 2usize
        let (coef, e3) = mem.alloc[f64](a, np * n)
        let (bout, e4) = mem.alloc[f64](a, np)
        let (ob, e5) = mem.alloc[f64](a, np)
        if e3 != ok || e4 != ok || e5 != ok { ret nan }
        e = bp.bsvc_pairs(a, x, n, p, cls, kc, &par, lam, coef, bout, ob)
        if e != ok { ret nan }
        i = 0usize
        while i < np {
            obj += ob[i]
            i += 1usize
        }
        mainv = wsum(coef, np * n)
        bv = wsum(bout, np)
        e = bp.predict_pairs(a, &par, x, n, p, coef, bout, kc, xt, nt, resp)
    }
    if sv == 7usize {
        let (al, e3) = mem.alloc[f64](a, n * kc)
        if e3 != ok { ret nan }
        let (o, e4) = bs.spoc(a, x, n, p, cls, kc, &par, wc, al)
        obj = o
        e = e4
        mainv = wsum(al, n * kc)
        if e == ok { e = bp.predict_spoc(a, &par, x, n, p, al, kc, xt, nt, resp) }
    }
    if sv == 8usize {
        let k1 = kc - 1usize
        let (al, e3) = mem.alloc[f64](a, n * k1)
        let (rm, e4) = mem.alloc[f64](a, n * k1)
        if e3 != ok || e4 != ok { ret nan }
        let (o, e5) = bs.kbb(a, x, n, p, cls, cnt, kc, &par, wc, lam, al)
        obj = o
        e = e5
        var j = 0usize
        while j < n {
            var q = 0usize
            while q < k1 {
                rm[j * k1 + q] = al[q * n + j]
                q += 1usize
            }
            j += 1usize
        }
        mainv = wsum(rm, n * k1)
        var q = 0usize
        while q < k1 {
            var s = 0.0f64
            j = 0usize
            while j < n {
                s += al[q * n + j]
                j += 1usize
            }
            bv += (0.0f64 - s) * f64(q + 1usize)
            q += 1usize
        }
        if e == ok { e = bp.predict_kbb(a, &par, x, n, p, rm, cls, kc, xt, nt, resp) }
    }
    if e != ok { ret nan }
    if str.eq(c.name, "obj") { ret obj }
    if str.eq(c.name, "alpha") { ret mainv }
    if str.eq(c.name, "b") { ret bv }
    var s = 0.0f64
    i = 0usize
    while i < nt {
        s += f64(resp[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

// kernlab's dprecond lambda carries over from fit to fit: the state advances on the first case of a model ("alpha") and the later cases of the same model refit from the state before it
fn answer(a: *mem.Arena, c: *const oracle.Case, lam: *f64, before: *f64) -> f64 {
    // the two-class layout has 9 scalars then y; the multi-class layout has K at index 2 and its svm code at 4, svm 5 in both: tell them by the length
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    var scratch = *before
    var st = lam
    if str.eq(c.name, "alpha") {
        *before = *lam
    } else {
        st = &scratch
    }
    if z.len == 9usize + n + n * p { ret two(a, c, st) }
    ret multi(a, c, st)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabbsvm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var lam = 1.0e-3f64 / 512.0f64 / 512.0f64
    var before = lam
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c, &lam, &before)
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
