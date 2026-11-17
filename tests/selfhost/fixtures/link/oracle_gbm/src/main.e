// e.algo.stat.gbmpkg against gbm. tests/oracle/gbm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gbm`; the layout is at the top of scripts/r_oracle/groups/gbm.R.

use e.algo.stat.gbmpkg as gb
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    if c.name[0usize] == 100u8 {
        // prd: (n, p, ntrees, shrinkage, depth, minobs, row, nnew, y[n], X[n p], Xnew[nnew p]) the prediction of a recorded gaussian model at a new row
        let nt = usize(z[2usize])
        let dp = usize(z[4usize])
        let nnew = usize(z[7usize])
        var lossc = 0usize
        if c.name[2usize] == 98u8 { lossc = 1usize }
        if c.name[2usize] == 112u8 { lossc = 2usize }
        if c.name[2usize] == 97u8 { lossc = 3usize }
        if c.name[2usize] == 108u8 { lossc = 4usize }
        let (fi, ei) = mem.alloc[f64](a, n)
        let (rc, er) = mem.alloc[f64](a, nt * (4usize * dp + 2usize) + 1usize)
        let (po, ep) = mem.alloc[f64](a, nnew)
        if ei != ok || er != ok || ep != ok { ret nan }
        if gb.model(a, lossc, z[8usize + n..8usize + n + n * p], z[8usize..8usize + n], n, p, nt, z[3usize], dp, usize(z[5usize]), fi, rc) != ok { ret nan }
        gb.predict_model(rc, nt, dp, nt, z[8usize + n + n * p..8usize + n + n * p + nnew * p], nnew, po)
        let (po2, ep2) = mem.alloc[f64](a, nnew)
        if ep2 != ok { ret nan }
        // the same model read with the first third of the trees (slot 8 + n + n p + nnew p holds that count when present)
        if c.name.len > 3usize {
            let kk = usize(z[8usize + n + n * p + nnew * p])
            gb.predict_model(rc, nt, dp, kk, z[8usize + n + n * p..8usize + n + n * p + nnew * p], nnew, po2)
            ret po2[usize(z[6usize])]
        }
        ret po[usize(z[6usize])]
    }
    if c.name[0usize] == 105u8 {
        let (fi, ei) = mem.alloc[f64](a, n)
        let (inf, ef) = mem.alloc[f64](a, p)
        if ei != ok || ef != ok { ret nan }
        if gb.influence(a, usize(z[7usize]), z[8usize + n..8usize + n + n * p], z[8usize..8usize + n], n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), fi, inf) != ok { ret nan }
        ret inf[usize(z[6usize])]
    }
    let (f, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan }
    let xm = z[8usize + n..8usize + n + n * p]
    let y = z[8usize..8usize + n]
    var ge = ok
    if c.name[0usize] == 98u8 {
        ge = gb.bernoulli(a, xm, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), f)
    } else if c.name[0usize] == 108u8 {
        ge = gb.laplace(a, xm, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), f)
    } else if c.name[0usize] == 97u8 {
        ge = gb.adaboost(a, xm, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), f)
    } else if c.name[0usize] == 112u8 {
        ge = gb.poisson(a, xm, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), f)
    } else {
        ge = gb.gaussian(a, xm, y, n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), usize(z[5usize]), f)
    }
    if ge != ok { ret nan }
    ret f[usize(z[6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gbm.json")
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
