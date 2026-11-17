// e.algo.stat.micefull against mice 3.19 after set.seed for the numeric methods (norm.nob, norm, norm.predict, pmm, norm.boot, mean, sample), logreg and
// logreg.boot on a binary first column, a predictor matrix and a visit sequence, plus pool.scalar.
// tests/oracle/mice.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mice`; the layout is at the top of
// scripts/r_oracle/groups/mice.R.

use e.algo.stat.micefull as mf
use e.algo.stat.micepkg as mc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn oracle_is_pool(c: *const oracle.Case) -> bool { ret str.eq(c.name, "pool") }

// one imputed value: the layout is (n, p, m, maxit, method, seed, data[n p], [pred[p p], nv, visit[nv] for "imp2"], idx); with method 4 or 6 the first column is a 0/1 factor
// and the other columns use norm.nob
fn imputed(a: *mem.Arena, z: []const f64, with_setup: bool) -> f64 {
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[2usize])
    let maxit = usize(z[3usize])
    let method = usize(z[4usize])
    let seed = i64(z[5usize])
    let b = 6usize + n * p
    let (data, e1) = mem.alloc[f64](a, n * p)
    let (kind, e2) = mem.alloc[usize](a, p)
    let (meth, e3) = mem.alloc[usize](a, p)
    let (pred, e4) = mem.alloc[f64](a, p * p)
    let (lo, e5) = mem.alloc[f64](a, p)
    let (hi, e6) = mem.alloc[f64](a, p)
    let (pas, e7) = mem.alloc[f64](a, 3usize * p)
    let (imp, e8) = mem.alloc[f64](a, n * p * m + 4usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok || e6 != ok || e7 != ok || e8 != ok { ret nan }
    var j = 0usize
    var nmis0 = 0usize
    while j < p {
        kind[j] = 0usize
        meth[j] = method
        lo[j] = nan
        hi[j] = nan
        var i = 0usize
        while i < n {
            data[j * n + i] = z[6usize + j * n + i]
            if j == 0usize && data[i] != data[i] { nmis0 += 1usize }
            i += 1usize
        }
        j += 1usize
    }
    let logit = method == 4usize || method == 6usize
    if logit {
        kind[0usize] = 2usize
        var i = 0usize
        while i < n {
            data[i] += 1.0f64
            i += 1usize
        }
        j = 1usize
        while j < p {
            meth[j] = 0usize
            j += 1usize
        }
    }
    var i = 0usize
    while i < p * p {
        pred[i] = 1.0f64
        if i / p == i % p { pred[i] = 0.0f64 }
        i += 1usize
    }
    var nv = 0usize
    var idx = usize(z[b])
    var visit: []usize = zero
    if with_setup {
        i = 0usize
        while i < p * p {
            pred[i] = z[b + i]
            i += 1usize
        }
        nv = usize(z[b + p * p])
        let (vs, ev) = mem.alloc[usize](a, nv + 1usize)
        if ev != ok { ret nan }
        i = 0usize
        while i < nv {
            vs[i] = usize(z[b + p * p + 1usize + i])
            i += 1usize
        }
        visit = vs[0usize..nv]
        idx = usize(z[b + p * p + 1usize + nv])
    }
    let (tot, me) = mf.mice_run(a, data, n, p, m, maxit, kind, meth, pred, lo, hi, pas, visit, seed, imp, imp[0usize..0usize])
    if me != ok || idx >= tot { ret nan }
    var v = imp[idx]
    if logit && idx < nmis0 * m { v -= 1.0f64 }
    ret v
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if oracle_is_pool(c) {
        let pm = usize(z[0usize])
        let (po, pe) = mem.alloc[f64](a, 7usize)
        if pe != ok { ret 0.0f64 / 0.0f64 }
        mc.pool_scalar(z[2usize..2usize + pm], z[2usize + pm..2usize + 2usize * pm], z[1usize], 1.0f64, po)
        ret po[usize(z[2usize + 2usize * pm])]
    }
    ret imputed(a, z, str.eq(c.name, "imp2"))
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mice.json")
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
