// e.algo.stat.topicmodels' LDA by variational EM against topicmodels::LDA(method = "VEM"). tests/oracle/topicmodels_lda.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R topicmodels_lda`; the layout is at the top of scripts/r_oracle/groups/topicmodels_lda.R.

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

fn total(m: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m.len {
        s += m[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, fits: []tm.Vem, ntok1: f64, ntok2: f64, c: *const oracle.Case) -> f64 {
    let cfg = usize(c.args[0usize])
    let what = usize(c.args[1usize])
    let p = usize(c.args[2usize])
    let q = usize(c.args[3usize])
    let v = &fits[cfg]
    if what == 1usize { ret v.beta[(p - 1usize) * v.nv + (q - 1usize)] }
    if what == 2usize { ret v.gamma[(p - 1usize) * v.k + (q - 1usize)] }
    if what == 3usize { ret v.alpha }
    if what == 4usize { ret v.llh[p - 1usize] }
    if what == 5usize { ret f64(v.iter) }
    if what == 6usize { ret tm.loglik(v) }
    if what == 7usize {
        var est = true
        if cfg == 2usize { est = false }
        ret f64(tm.vem_df(v, est))
    }
    if what == 8usize {
        var n = ntok1
        if cfg == 5usize { n = ntok2 }
        ret tm.vem_perplexity(v, n)
    }
    if what == 9usize { ret f64(v.wa[p - 1usize] + 1usize) }
    if what == 10usize { ret v.logliks[p - 1usize] }
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
    tm.rank_row(v.gamma, p - 1usize, v.k, q, rk)
    ret f64(rk[q - 1usize] + 1usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/topicmodels_lda.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (m1, e1) = dtm(a, 12usize, 15usize, 0usize)
    let (m2, e2) = dtm(a, 6usize, 15usize, 3usize)
    let (fits, e3) = mem.alloc[tm.Vem](a, 6usize)
    let (nobeta, e4) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok { os.exit(4) }
    if tm.lda_vem(a, m1, 12usize, 15usize, 3usize, 0usize, 100i64, 50.0f64 / 3.0f64, true, 500i64, 0.000001f64, 1000i64, 0.0001f64, 0usize, nobeta, &fits[1usize]) != ok { os.exit(5) }
    if tm.lda_vem(a, m1, 12usize, 15usize, 4usize, 0usize, 7i64, 0.5f64, false, 500i64, 0.000001f64, 1000i64, 0.0001f64, 0usize, nobeta, &fits[2usize]) != ok { os.exit(5) }
    if tm.lda_vem(a, m1, 12usize, 15usize, 3usize, 1usize, 11i64, 50.0f64 / 3.0f64, true, 500i64, 0.000001f64, 1000i64, 0.0001f64, 0usize, nobeta, &fits[3usize]) != ok { os.exit(5) }
    if tm.lda_vem(a, m1, 12usize, 15usize, 2usize, 0usize, 5i64, 25.0f64, true, 20i64, 0.000001f64, 15i64, 0.0001f64, 1usize, nobeta, &fits[4usize]) != ok { os.exit(5) }
    if tm.lda_vem(a, m2, 6usize, 15usize, 3usize, 2usize, 1i64, fits[1usize].alpha, true, 500i64, 0.000001f64, 0i64 - 1i64, 0.0001f64, 0usize, fits[1usize].beta, &fits[5usize]) != ok { os.exit(5) }
    var f = 1usize
    while f <= 5usize {
        tm.normalize_rows(fits[f].gamma, fits[f].nd, fits[f].k)
        f += 1usize
    }
    let ntok1 = total(m1)
    let ntok2 = total(m2)
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, fits, ntok1, ntok2, c)
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
