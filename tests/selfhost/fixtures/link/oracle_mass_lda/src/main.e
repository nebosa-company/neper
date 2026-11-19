// e.algo.stat.masslda against MASS lda, qda, their CV and predict. tests/oracle/mass_lda.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_lda`; the layout is at the top of scripts/r_oracle/groups/mass_lda.R.

use e.algo.rand.r as rng
use e.algo.stat.masslda as ml
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret s
}

fn wsum1(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(i + 1usize) * (v[i] + 1.0f64)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let ng = usize(z[3usize])
    let method = usize(z[4usize])
    let tol = z[5usize]
    let nu = z[6usize]
    let use_prior = z[7usize] != 0.0f64
    let m = usize(z[8usize])
    let dimen = usize(z[9usize])
    let mode = usize(z[10usize])
    let pr = z[11usize..11usize + ng]
    let pr2 = z[11usize + ng..11usize + 2usize * ng]
    let off = 11usize + 2usize * ng
    let x = z[off..off + n * p]
    let grp = z[off + n * p..off + n * p + n]
    let xn = z[off + n * p + n..off + n * p + n + m * p]
    let is_lda = str.eq(c.name, "lda")
    let (cls, e1) = mem.alloc[f64](a, n + m)
    let (post, e2) = mem.alloc[f64](a, (n + m) * ng)
    let (ld, e3) = mem.alloc[f64](a, m * p + 1usize)
    if e1 != ok || e2 != ok || e3 != ok { ret nan() }
    if is_lda {
        let (d1, e) = ml.lda(a, &g, x, n, p, grp, ng, pr, use_prior, tol, method, nu)
        if e != ok { ret nan() }
        if mode == 6usize || mode == 7usize {
            let ce = ml.lda_cv(a, x, n, p, grp, &d1, method, cls, post)
            if ce != ok { ret nan() }
            if mode == 6usize { ret wsum(post[0usize..n * ng]) }
            ret wsum1(cls[0usize..n])
        }
        let (d, fe) = ml.lda_final(a, &d1, method, tol)
        if fe != ok { ret nan() }
        if mode == 0usize { ret wsum(d.scaling[0usize..p * d.rank]) }
        if mode == 1usize { ret wsum(d.svd) }
        if mode == 2usize { ret wsum(d.means) }
        if mode == 3usize { ret wsum(d.prior) }
        if mode == 4usize { ret wsum(d.counts) }
        if mode == 5usize { ret f64(d.rank) }
        let pm = (mode - 10usize) / 3usize
        let w = (mode - 10usize) % 3usize
        let pe = ml.lda_predict(a, &d, xn, m, pr2, dimen, pm, cls, post, ld)
        if pe != ok { ret nan() }
        var dm = d.rank
        if dimen < dm { dm = dimen }
        if w == 0usize { ret wsum(post[0usize..m * ng]) }
        if w == 1usize { ret wsum1(cls[0usize..m]) }
        ret wsum(ld[0usize..m * dm])
    }
    let (d, e) = ml.qda(a, &g, x, n, p, grp, ng, pr, use_prior, method, nu)
    if e != ok { ret nan() }
    var mle = false
    if method == 1usize { mle = true }
    if mode == 0usize { ret wsum(d.scaling) }
    if mode == 1usize { ret wsum(d.ldet) }
    if mode == 2usize { ret wsum(d.means) }
    if mode == 3usize { ret wsum(d.prior) }
    if mode == 4usize { ret wsum(d.counts) }
    if mode == 6usize || mode == 7usize || mode == 20usize || mode == 21usize {
        let pe = ml.qda_predict(a, &d, x, n, d.prior, 3usize, grp, mle, cls, post)
        if pe != ok { ret nan() }
        if mode == 6usize || mode == 20usize { ret wsum(post[0usize..n * ng]) }
        ret wsum1(cls[0usize..n])
    }
    let pm = (mode - 10usize) / 3usize
    let w = (mode - 10usize) % 3usize
    let pe = ml.qda_predict(a, &d, xn, m, pr2, pm, grp, mle, cls, post)
    if pe != ok { ret nan() }
    if w == 0usize { ret wsum(post[0usize..m * ng]) }
    ret wsum1(cls[0usize..m])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_lda.json")
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
