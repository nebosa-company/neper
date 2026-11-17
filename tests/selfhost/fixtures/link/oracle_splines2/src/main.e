// e.algo.stat.splines against splines2: bSpline (with derivatives), mSpline, iSpline. tests/oracle/splines2.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R splines2`; the layout is at the top of
// scripts/r_oracle/groups/splines2.R.

use e.algo.stat.splines as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let nk0 = usize(z[1usize])
    let degree = usize(z[2usize])
    let icp = z[3usize] != 0.0f64
    let lo = z[4usize]
    let hi = z[5usize]
    let kraw = usize(z[6usize])
    let kind = kraw % 100usize
    let xs = z[7usize..7usize + n]
    let (kbuf, ek) = mem.alloc[f64](a, nk0 + n + 4usize)
    let (xsort, ex) = mem.alloc[f64](a, n)
    if ek != ok || ex != ok { ret 0.0f64 / 0.0f64 }
    var nk = nk0
    if kraw >= 100usize {
        var q0 = 0usize
        while q0 < n {
            xsort[q0] = xs[q0]
            q0 += 1usize
        }
        nk = sp.df_knots(xsort, lo, hi, nk0, degree, icp, kbuf)
    } else {
        var q1 = 0usize
        while q1 < nk0 {
            kbuf[q1] = z[7usize + n + q1]
            q1 += 1usize
        }
    }
    let knots = kbuf[0usize..nk]
    let width = nk + degree + 1usize
    let (t, e1) = mem.alloc[f64](a, nk + 2usize * (degree + 2usize))
    let (tmp, e2) = mem.alloc[f64](a, 2usize * width + 4usize)
    let (out, e3) = mem.alloc[f64](a, width + nk + 8usize)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var k8 = 0u8
    var deriv = 0usize
    if kind == 1usize { k8 = 1u8 }
    if kind == 2usize { k8 = 2u8 }
    if kind == 14usize { k8 = 3u8 }
    if kind == 3usize { deriv = 1usize }
    if kind == 4usize { deriv = 2usize }
    if kind == 8usize { k8 = 1u8
        deriv = 1usize }
    if kind == 9usize { k8 = 1u8
        deriv = 2usize }
    if kind == 10usize { k8 = 1u8 }
    if kind == 11usize { k8 = 1u8
        deriv = 1usize }
    if kind == 8usize { k8 = 1u8 }
    if kind == 9usize { k8 = 1u8 }
    if kind == 10usize { k8 = 1u8 }
    if kind == 11usize { k8 = 1u8 }
    if kind == 8usize { deriv = 1usize }
    if kind == 9usize { deriv = 2usize }
    if kind == 11usize { deriv = 1usize }
    if kind == 40usize { deriv = 3usize }
    if kind == 41usize {
        k8 = 1u8
        deriv = 3usize
    }
    if kind == 42usize {
        k8 = 1u8
        deriv = 2usize
    }
    if kind == 30usize || kind == 32usize { deriv = 1usize }
    if kind == 31usize || kind == 33usize { deriv = 2usize }
    var s = 0.0f64
    var cnt = 0usize
    var i = 0usize
    while i < n {
        var m = 0usize
        if kind == 12usize || kind == 13usize {
            let (tp, ep1) = mem.alloc[f64](a, nk + 2usize * degree + 4usize)
            if ep1 != ok { ret 0.0f64 / 0.0f64 }
            var kp = 0u8
            if kind == 13usize { kp = 1u8 }
            m = sp.periodic_row(tp, knots, lo, hi, degree, icp, kp, 0usize, xs[i], out)
        } else if kind == 18usize || kind == 32usize || kind == 33usize {
            let (tk, ek1) = mem.alloc[f64](a, nk + 12usize)
            let (tmpk, ek2) = mem.alloc[f64](a, 2usize * (nk + 4usize) + 8usize)
            let (outk, ek3) = mem.alloc[f64](a, nk + 6usize)
            if ek1 != ok || ek2 != ok || ek3 != ok { ret 0.0f64 / 0.0f64 }
            m = sp.nsk_row(a, tk, tmpk, knots, lo, hi, icp, deriv, xs[i], outk)
            var jk = 0usize
            while jk < m {
                out[jk] = outk[jk]
                jk += 1usize
            }
        } else if kind >= 15usize && kind <= 17usize {
            m = sp.bern_row(degree, icp, lo, hi, kind - 15usize, xs[i], out)
        } else if kind == 19usize {
            m = sp.bern_row(degree, icp, lo, hi, 100usize, xs[i], out)
        } else if kind == 6usize || kind == 7usize {
            let (tn2, ec1) = mem.alloc[f64](a, nk + 2usize * (degree + 2usize))
            let (tmpn2, ec2) = mem.alloc[f64](a, 2usize * width + 4usize)
            let (outn2, ec3) = mem.alloc[f64](a, width + 2usize)
            if ec1 != ok || ec2 != ok || ec3 != ok { ret 0.0f64 / 0.0f64 }
            m = sp.crow(a, tn2, tmpn2, knots, lo, hi, degree, icp, kind == 7usize, xs[i], outn2)
            var jc = 0usize
            while jc < m {
                out[jc] = outn2[jc]
                jc += 1usize
            }
        } else if kind == 5usize || kind == 30usize || kind == 31usize {
            let (tn, en1) = mem.alloc[f64](a, nk + 12usize)
            let (tmpn, en2) = mem.alloc[f64](a, 2usize * (nk + 4usize) + 8usize)
            let (outn, en3) = mem.alloc[f64](a, nk + 6usize)
            if en1 != ok || en2 != ok || en3 != ok { ret 0.0f64 / 0.0f64 }
            m = sp.nat_row(a, tn, tmpn, knots, lo, hi, icp, deriv, xs[i], outn)
            var jn = 0usize
            while jn < m {
                out[jn] = outn[jn]
                jn += 1usize
            }
        } else {
            m = sp.row(t, tmp, knots, lo, hi, degree, icp, k8, deriv, xs[i], out)
        }
        var j = 0usize
        while j < m {
            cnt += 1usize
            if str.eq(c.name, "sum") { s += out[j] } else { s += f64(cnt) * out[j] }
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/splines2.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
