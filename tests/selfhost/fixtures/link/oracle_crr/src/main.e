// e.algo.stat.crr against cmprsk::crr (point estimates). tests/oracle/crr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R crr`; the layout is at the top of scripts/r_oracle/groups/crr.R.

use e.algo.stat.crr as cr
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let ncov = usize(z[1usize])
    let ncov2 = usize(z[2usize])
    let ncg = usize(z[3usize])
    let q = usize(z[4usize])
    let np = ncov + ncov2
    let t2 = z[5usize..5usize + n]
    let (ici, e1) = mem.alloc[i64](a, n)
    let (icg, e2) = mem.alloc[i64](a, n)
    let (wt, e3) = mem.alloc[f64](a, ncg * n)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var ndf = 0usize
    var i = 0usize
    while i < n {
        ici[i] = i64(z[5usize + n + i])
        icg[i] = i64(z[5usize + 2usize * n + i])
        if ici[i] == 1i64 && (i == 0usize || t2[i] != t2[i - 1usize] || ndf == 0usize) { ndf += 1usize }
        i += 1usize
    }
    // distinct cause-1 times
    let (uft, e4) = mem.alloc[f64](a, n + 1usize)
    if e4 != ok { ret nan }
    var k = 0usize
    i = 0usize
    while i < n {
        if ici[i] == 1i64 && (k == 0usize || uft[k - 1usize] != t2[i]) {
            uft[k] = t2[i]
            k += 1usize
        }
        i += 1usize
    }
    ndf = k
    let (tf, e5) = mem.alloc[f64](a, ndf * ncov2 + 1usize)
    if e5 != ok { ret nan }
    var j = 0usize
    while j < ncov2 {
        i = 0usize
        while i < ndf {
            if j == 0usize { tf[i + ndf * j] = math.log[f64](1.0f64 + uft[i]) } else { tf[i + ndf * j] = uft[i] }
            i += 1usize
        }
        j += 1usize
    }
    cr.censor_weights(a, t2, ici, icg, ncg, wt)
    let base = 5usize + 3usize * n
    let d = cr.Data{ t2: t2, ici: ici, n: n, x: z[base..base + n * ncov], ncov: ncov, x2: z[base + n * ncov..base + n * np], ncov2: ncov2, tf: tf, ndf: ndf, wt: wt, ncg: ncg, icg: icg }
    let (b, e6) = mem.alloc[f64](a, np)
    let (score, e7) = mem.alloc[f64](a, np)
    if e6 != ok || e7 != ok { ret nan }
    j = 0usize
    while j < np { b[j] = 0.0f64
        j += 1usize }
    let (fit, fe) = cr.crr(a, &d, np, 1.0e-6f64, 10usize, b, score)
    if fe != ok { ret nan }
    if q < np { ret b[q] }
    if q == np { ret fit.loglik }
    if q == np + 1usize { ret fit.loglik_null }
    let (info, e8) = mem.alloc[f64](a, np * np)
    let (vr, e9) = mem.alloc[f64](a, np * np)
    if e8 != ok || e9 != ok { ret nan }
    if cr.variance(a, &d, b, np, info, vr) != ok { ret nan }
    ret vr[q - np - 2usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/crr.json")
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
