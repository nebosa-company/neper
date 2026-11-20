// e.algo.stat.topicmodels' collapsed Gibbs LDA against topicmodels::LDA(method = "Gibbs") under set.seed. tests/oracle/topicmodels_gibbs.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R topicmodels_gibbs`; the layout is at the top of scripts/r_oracle/groups/topicmodels_gibbs.R.

use e.algo.stat.topicmodels as tm
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn dtm(a: *mem.Arena, nd: usize, nv: usize, salt: usize) -> ([]f64, err) {
    let (m, e) = mem.alloc[f64](a, nd * nv)
    if e != ok { ret (m, e) }
    var i = 1usize
    while i <= nd {
        var j = 1usize
        while j <= nv {
            var v = (i * j + 3usize * i + 5usize * j + salt) % 7usize
            if i % 2usize == 0usize && j <= nv / 2usize { v += 3usize }
            if i % 2usize == 1usize && j > nv / 2usize { v += 2usize }
            m[(i - 1usize) * nv + (j - 1usize)] = f64(v)
            j += 1usize
        }
        i += 1usize
    }
    ret (m, ok)
}

fn answer(a: *mem.Arena, fits: []tm.Gibbs, m1: []const f64, m2: []const f64, c: *const oracle.Case) -> f64 {
    let cfg = usize(c.args[0usize])
    let what = usize(c.args[1usize])
    let p = usize(c.args[2usize])
    let q = usize(c.args[3usize])
    let v = &fits[cfg]
    if what == 14usize {
        if p == 1usize { ret tm.gibbs_perplexity(m2, 6usize, 15usize, 3usize, v.beta, v.theta, true) }
        if p == 2usize { ret tm.gibbs_perplexity(m2, 6usize, 15usize, 3usize, fits[1usize].beta, fits[1usize].theta, false) }
        ret tm.gibbs_perplexity(m1, 12usize, 15usize, 3usize, fits[1usize].beta, fits[1usize].theta, true)
    }
    if what == 1usize { ret v.beta[(p - 1usize) * v.nv + (q - 1usize)] }
    if what == 2usize { ret v.theta[(p - 1usize) * v.k + (q - 1usize)] }
    if what == 3usize { ret v.alpha }
    if what == 4usize { ret v.loglik }
    if what == 5usize { ret f64(v.k * v.nv) }
    if what == 6usize { ret f64(v.z[p - 1usize] + 1usize) }
    if what == 7usize { ret f64(v.wa[p - 1usize] + 1usize) }
    if what == 8usize { ret v.logliks[p - 1usize] }
    let (pt, e) = mem.alloc[f64](a, v.k * v.nv)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < v.k * v.nv {
        pt[i] = math.exp[f64](v.beta[i])
        i += 1usize
    }
    if what == 13usize { ret pt[(p - 1usize) * v.nv + (q - 1usize)] }
    let (rk, e2) = mem.alloc[usize](a, q + 1usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    if what == 11usize {
        tm.rank_row(pt, p - 1usize, v.nv, q, rk)
        ret f64(rk[q - 1usize] + 1usize)
    }
    tm.rank_row(v.theta, p - 1usize, v.k, q, rk)
    ret f64(rk[q - 1usize] + 1usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/topicmodels_gibbs.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (m1, e1) = dtm(a, 12usize, 15usize, 0usize)
    let (m2, e2) = dtm(a, 6usize, 15usize, 3usize)
    let (fits, e3) = mem.alloc[tm.Gibbs](a, 6usize)
    let (nophi, e4) = mem.alloc[f64](a, 1usize)
    let (noz, e5) = mem.alloc[usize](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(4) }
    let a3 = 50.0f64 / 3.0f64
    if tm.lda_gibbs(a, m1, 12usize, 15usize, 3usize, 0usize, 1i64, a3, 0.1f64, 100usize, 0usize, true, nophi, noz, &fits[1usize]) != ok { os.exit(5) }
    if tm.lda_gibbs(a, m1, 12usize, 15usize, 4usize, 0usize, 2i64, 0.5f64, 0.05f64, 60usize, 10usize, true, nophi, noz, &fits[2usize]) != ok { os.exit(5) }
    if tm.lda_gibbs(a, m1, 12usize, 15usize, 3usize, 1usize, 3i64, a3, 0.1f64, 40usize, 0usize, true, fits[1usize].beta, noz, &fits[3usize]) != ok { os.exit(5) }
    let (z1, e6) = mem.alloc[usize](a, fits[1usize].z.len)
    if e6 != ok { os.exit(4) }
    var i = 0usize
    while i < z1.len {
        z1[i] = fits[1usize].z[i] + 1usize
        i += 1usize
    }
    if tm.lda_gibbs(a, m1, 12usize, 15usize, 3usize, 2usize, 4i64, a3, 0.1f64, 30usize, 0usize, true, nophi, z1, &fits[4usize]) != ok { os.exit(5) }
    if tm.lda_gibbs(a, m2, 6usize, 15usize, 3usize, 0usize, 9i64, a3, 0.1f64, 50usize, 0usize, false, fits[1usize].beta, noz, &fits[5usize]) != ok { os.exit(5) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, fits, m1, m2, c)
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
