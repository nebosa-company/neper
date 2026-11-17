// The fits behind mice's cart, polyreg and polr against R: rpart trees, nnet::multinom and MASS::polr, each as a checksum of the predictions on new rows.
// tests/oracle/micefit.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R micefit`; the layout is at the top of scripts/r_oracle/groups/micefit.R.

use e.algo.stat.micemodels as mm
use e.algo.stat.rpartfit as rp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let nt = usize(z[2usize])
    let k = usize(z[3usize])
    let mb = usize(z[4usize])
    let cp = z[5usize]
    let x = z[6usize..6usize + n * p]
    let y = z[6usize + n * p..6usize + n * p + n]
    let xt = z[6usize + n * p + n..6usize + n * p + n + nt * p]
    var tot = 0.0f64
    if str.eq(c.name, "rpart_anova") {
        let (t, e) = rp.rpart_fit(a, x, y, n, p, false, 0usize, 3usize * mb, mb, cp)
        if e != ok { ret nan }
        var i = 0usize
        while i < nt {
            tot += f64(i + 1usize) * t.val[rp.rpart_leaf(&t, xt, nt, i)]
            i += 1usize
        }
        ret tot
    }
    if str.eq(c.name, "rpart_class") {
        let (t, e) = rp.rpart_fit(a, x, y, n, p, true, k, 3usize * mb, mb, cp)
        if e != ok { ret nan }
        let (pr, ep) = mem.alloc[f64](a, k)
        if ep != ok { ret nan }
        var i = 0usize
        while i < nt {
            rp.rpart_leaf_probs(&t, rp.rpart_leaf(&t, xt, nt, i), pr)
            var q = 0usize
            while q < k {
                tot += f64(i * k + q + 1usize) * pr[q]
                q += 1usize
            }
            i += 1usize
        }
        ret tot
    }
    if str.eq(c.name, "multinom") || str.eq(c.name, "polr") {
        let w = z[6usize + n * p + n + nt * p..6usize + n * p + n + nt * p + n]
        let (yc, ey) = mem.alloc[usize](a, n)
        if ey != ok { ret nan }
        var i = 0usize
        while i < n {
            yc[i] = usize(y[i]) - 1usize
            i += 1usize
        }
        let (pr, ep) = mem.alloc[f64](a, k)
        if ep != ok { ret nan }
        if str.eq(c.name, "multinom") {
            let r = p + 1usize
            let (xi, ex) = mem.alloc[f64](a, n * r)
            let (xti, ext) = mem.alloc[f64](a, nt * r)
            let (wts, ew) = mem.alloc[f64](a, k * r + k)
            if ex != ok || ext != ok || ew != ok { ret nan }
            i = 0usize
            while i < n {
                xi[i] = 1.0f64
                i += 1usize
            }
            i = 0usize
            while i < nt {
                xti[i] = 1.0f64
                i += 1usize
            }
            var q = 0usize
            while q < p {
                i = 0usize
                while i < n {
                    xi[(q + 1usize) * n + i] = x[q * n + i]
                    i += 1usize
                }
                i = 0usize
                while i < nt {
                    xti[(q + 1usize) * nt + i] = xt[q * nt + i]
                    i += 1usize
                }
                q += 1usize
            }
            if mm.multinom_fit(a, xi, yc, w, n, r, k, wts) != ok { ret nan }
            i = 0usize
            while i < nt {
                mm.multinom_probs(wts, xti, nt, r, k, i, pr)
                q = 0usize
                while q < k {
                    tot += f64(i * k + q + 1usize) * pr[q]
                    q += 1usize
                }
                i += 1usize
            }
            ret tot
        }
        let (par, epar) = mem.alloc[f64](a, p + k)
        if epar != ok { ret nan }
        if mm.polr_fit(a, x, yc, w, n, p, k, par) != ok { ret nan }
        var i2 = 0usize
        while i2 < nt {
            mm.polr_probs(par, xt, nt, p, k, i2, pr)
            var q = 0usize
            while q < k {
                tot += f64(i2 * k + q + 1usize) * pr[q]
                q += 1usize
            }
            i2 += 1usize
        }
        ret tot
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/micefit.json")
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
