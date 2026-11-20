// e.algo.stat.gam predict at newdata against R gam::gam s() and lo() terms. tests/oracle/gam_pred.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gam_pred`; the argument layout is at the top of scripts/r_oracle/groups/gam_pred.R.

use e.algo.stat.gam as gm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let fam = usize(z[0usize])
    let n = usize(z[1usize])
    let q = usize(z[2usize])
    let m = usize(z[3usize])
    let nn = usize(z[4usize])
    let kind = z[5usize..5usize + q]
    let p1 = z[5usize + q..5usize + 2usize * q]
    let p2 = z[5usize + 2usize * q..5usize + 3usize * q]
    let ox = 5usize + 3usize * q
    let oz = ox + q * n
    let oy = oz + m * n
    let ow = oy + n
    let oxn = ow + n
    let ozn = oxn + q * nn
    let ty = usize(z[ozn + m * nn])
    let idx = usize(z[ozn + m * nn + 1usize])
    var pl = 0usize
    var i = 0usize
    while i < q {
        pl += 1usize
        if kind[i] == 2.0f64 { pl += 1usize }
        i += 1usize
    }
    let p = 1usize + pl + m
    let (xm, e1) = mem.alloc[f64](a, n * p)
    let (xq, e0) = mem.alloc[f64](a, nn * p)
    let (wh, e2) = mem.alloc[usize](a, q + 1usize)
    let (cs, e4) = mem.alloc[usize](a, q + m + 1usize)
    let (d1, e5) = mem.alloc[f64](a, q + 1usize)
    let (sp, e7) = mem.alloc[f64](a, q + 1usize)
    let (pv, e8) = mem.alloc[f64](a, nn)
    if e0 != ok || e1 != ok || e2 != ok || e4 != ok || e5 != ok || e7 != ok || e8 != ok { ret nan }
    i = 0usize
    while i < n {
        xm[i] = 1.0f64
        i += 1usize
    }
    i = 0usize
    while i < nn {
        xq[i] = 1.0f64
        i += 1usize
    }
    // the model-matrix columns in formula order: one per smooth term, then the extras
    var col = 1usize
    var t = 0usize
    while t < q {
        cs[t] = col
        var dg = 1usize
        if kind[t] == 2.0f64 { dg = 2usize }
        var j = 0usize
        while j < dg {
            i = 0usize
            while i < n {
                var v = z[ox + t * n + i]
                if j == 1usize { v = v * v }
                xm[(col + j) * n + i] = v
                i += 1usize
            }
            i = 0usize
            while i < nn {
                var v = z[oxn + t * nn + i]
                if j == 1usize { v = v * v }
                xq[(col + j) * nn + i] = v
                i += 1usize
            }
            j += 1usize
        }
        col += dg
        t += 1usize
    }
    t = 0usize
    while t < m {
        cs[q + t] = col
        i = 0usize
        while i < n {
            xm[col * n + i] = z[oz + t * n + i]
            i += 1usize
        }
        i = 0usize
        while i < nn {
            xq[col * nn + i] = z[ozn + t * nn + i]
            i += 1usize
        }
        col += 1usize
        t += 1usize
    }
    // the smoothers run s() terms first, then lo() terms
    var k = 0usize
    var pass = 0usize
    while pass < 2usize {
        t = 0usize
        while t < q {
            var isl = false
            if kind[t] > 0.0f64 { isl = true }
            if isl == (pass == 1usize) {
                wh[k] = cs[t]
                if pass == 0usize {
                    d1[k] = p1[t]
                    sp[k] = p2[t]
                } else {
                    d1[k] = 0.0f64 - p1[t]
                    sp[k] = kind[t]
                }
                k += 1usize
            }
            t += 1usize
        }
        pass += 1usize
    }
    var f: gm.GamFit = zero
    if gm.gam_fit(a, xm, n, p, z[oy..oy + n], z[ow..ow + n], fam, q, wh, d1[0usize..q], sp[0usize..q], 1.0e-7f64, 30usize, 1.0e-7f64, 30usize, &f) != ok { ret nan }
    if gm.gam_predict(a, xm, n, p, fam, q, wh, d1[0usize..q], sp[0usize..q], &f, xq, nn, ty == 1usize, pv) != ok { ret nan }
    ret pv[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gam_pred.json")
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
