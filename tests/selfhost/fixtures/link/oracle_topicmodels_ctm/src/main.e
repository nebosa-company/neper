// e.algo.stat.topicmodels_ctm's correlated topic model by variational EM against topicmodels::CTM(method = "VEM"). tests/oracle/topicmodels_ctm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R topicmodels_ctm`; the layout is at the top of scripts/r_oracle/groups/topicmodels_ctm.R.

use e.algo.stat.topicmodels as tm
use e.algo.stat.topicmodels_ctm as ct
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

fn llsum(v: *const ct.Ctm) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.nd {
        s += v.llh[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, fits: []ct.Ctm, gam: [][]f64, ntok1: f64, ntok2: f64, c: *const oracle.Case) -> f64 {
    let cfg = usize(c.args[0usize])
    let what = usize(c.args[1usize])
    let p = usize(c.args[2usize])
    let q = usize(c.args[3usize])
    let v = &fits[cfg]
    if what == 1usize { ret v.logb[(p - 1usize) * v.nv + (q - 1usize)] }
    if what == 2usize { ret gam[cfg][(p - 1usize) * v.k + (q - 1usize)] }
    if what == 3usize { ret v.mu[p - 1usize] }
    if what == 4usize { ret v.cov[(p - 1usize) * (v.k - 1usize) + (q - 1usize)] }
    if what == 5usize { ret v.nu[(p - 1usize) * v.k + (q - 1usize)] }
    if what == 6usize { ret v.llh[p - 1usize] }
    if what == 7usize { ret f64(v.iter) }
    if what == 8usize { ret llsum(v) }
    if what == 9usize {
        let kk = f64(v.k)
        ret f64(usize((kk - 1.0f64) * (kk / 2.0f64 + 1.0f64) + f64(v.k * v.nv)))
    }
    if what == 10usize {
        var n = ntok1
        if cfg == 5usize { n = ntok2 }
        ret math.exp[f64](0.0f64 - llsum(v) / n)
    }
    if what == 11usize { ret f64(v.wa[p - 1usize] + 1usize) }
    if what == 12usize { ret v.logliks[p - 1usize] }
    let (pt, e) = mem.alloc[f64](a, v.k * v.nv)
    if e != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < v.k * v.nv {
        pt[i] = math.exp[f64](v.logb[i])
        i += 1usize
    }
    if what == 15usize { ret pt[(p - 1usize) * v.nv + (q - 1usize)] }
    let (rk, e2) = mem.alloc[usize](a, q + 1usize)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    if what == 13usize {
        tm.rank_row(pt, p - 1usize, v.nv, q, rk)
        ret f64(rk[q - 1usize] + 1usize)
    }
    tm.rank_row(gam[cfg], p - 1usize, v.k, q, rk)
    ret f64(rk[q - 1usize] + 1usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/topicmodels_ctm.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    let (m1, e1) = dtm(a, 12usize, 15usize, 0usize)
    let (m2, e2) = dtm(a, 6usize, 15usize, 3usize)
    let (fits, e3) = mem.alloc[ct.Ctm](a, 6usize)
    let (gam, e4) = mem.alloc[[]f64](a, 6usize)
    let (nob, e5) = mem.alloc[f64](a, 1usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { os.exit(4) }
    if ct.ctm_vem(a, m1, 12usize, 15usize, 3usize, 0usize, 100i64, 500i64, 0.000001f64, 1000i64, 0.0001f64, 500i64, 0.00001f64, 0usize, 0.0f64, nob, nob, nob, &fits[1usize]) != ok { os.exit(5) }
    if ct.ctm_vem(a, m1, 12usize, 15usize, 4usize, 0usize, 7i64, 500i64, 0.000001f64, 1000i64, 0.0001f64, 500i64, 0.00001f64, 0usize, 0.0f64, nob, nob, nob, &fits[2usize]) != ok { os.exit(5) }
    if ct.ctm_vem(a, m1, 12usize, 15usize, 3usize, 1usize, 11i64, 500i64, 0.000001f64, 1000i64, 0.0001f64, 500i64, 0.00001f64, 0usize, 0.0f64, nob, nob, nob, &fits[3usize]) != ok { os.exit(5) }
    if ct.ctm_vem(a, m1, 12usize, 15usize, 2usize, 0usize, 5i64, 20i64, 0.000001f64, 15i64, 0.0001f64, 500i64, 0.00001f64, 1usize, 0.0f64, nob, nob, nob, &fits[4usize]) != ok { os.exit(5) }
    if ct.ctm_vem(a, m2, 6usize, 15usize, 3usize, 2usize, 1i64, 500i64, 0.000001f64, 0i64 - 1i64, 0.0001f64, 500i64, 0.00001f64, 0usize, 0.0f64, fits[1usize].logb, fits[1usize].mu, fits[1usize].cov, &fits[5usize]) != ok { os.exit(5) }
    var f = 1usize
    while f <= 5usize {
        let (g, eg) = mem.alloc[f64](a, fits[f].nd * fits[f].k)
        if eg != ok { os.exit(4) }
        ct.gamma_of(g, fits[f].lambda, fits[f].nd, fits[f].k)
        gam[f] = g
        f += 1usize
    }
    let ntok1 = total(m1)
    let ntok2 = total(m2)
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, fits, gam, ntok1, ntok2, c)
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
