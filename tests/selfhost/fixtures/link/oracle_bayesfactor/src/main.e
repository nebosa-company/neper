// e.algo.stat.bayesfactor against BayesFactor. tests/oracle/bayesfactor.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bayesfactor`; the layout is at the top of scripts/r_oracle/groups/bayesfactor.R.

use e.algo.stat.bayesfactor as bf
use e.algo.rand.r as rng
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn run(a: *mem.Arena, c: *const oracle.Case) -> (f64, err) {
    let x = c.args
    if str.eq(c.name, "tstat") {
        let (rv, re) = bf.ttest_tstat(a, x[0usize], x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize] != 0.0f64)
        ret (rv, re)
    }
    if str.eq(c.name, "ttest") {
        let kind = x[0usize]
        let nx = usize(x[6usize])
        let ny = usize(x[7usize])
        let xs = x[8usize..8usize + nx]
        let ys = x[8usize + nx..8usize + nx + ny]
        let compl = x[5usize] != 0.0f64
        if kind == 2.0f64 {
            let (rv, re) = bf.ttest_two(a, xs, ys, x[2usize], x[3usize], x[4usize], compl)
            ret (rv, re)
        }
        if kind == 1.0f64 {
            let (d, e) = mem.alloc[f64](a, nx)
            if e != ok { ret (0.0f64, e) }
            var i = 0usize
            while i < nx {
                d[i] = xs[i] - ys[i]
                i += 1usize
            }
            let (rv, re) = bf.ttest_one(a, d, x[1usize], x[2usize], x[3usize], x[4usize], compl)
            ret (rv, re)
        }
        let (rv, re) = bf.ttest_one(a, xs, x[1usize], x[2usize], x[3usize], x[4usize], compl)
        ret (rv, re)
    }
    if str.eq(c.name, "oneway") {
        let (rv, re) = bf.oneway_fstat(a, x[0usize], x[1usize], x[2usize], x[3usize])
        ret (rv, re)
    }
    if str.eq(c.name, "linreg") {
        let (rv, re) = bf.linreg_r2(a, x[0usize], x[1usize], x[2usize], x[3usize])
        ret (rv, re)
    }
    if str.eq(c.name, "corr") {
        let n = usize(x[4usize])
        let (rv, re) = bf.correlation_bf(a, x[5usize..5usize + n], x[5usize + n..5usize + 2usize * n], x[0usize], x[1usize], x[2usize], x[3usize] != 0.0f64)
        ret (rv, re)
    }
    if str.eq(c.name, "prop") {
        let m = usize(x[5usize])
        let (rv, re) = bf.proportion_bf(a, x[6usize..6usize + m], x[6usize + m..6usize + 2usize * m], x[0usize], x[1usize], x[2usize], x[3usize], x[4usize] != 0.0f64)
        ret (rv, re)
    }
    if str.eq(c.name, "cont") {
        let ni = usize(x[2usize])
        let nj = usize(x[3usize])
        let (rv, re) = bf.contingency_bf(a, x[4usize..4usize + ni * nj], ni, nj, usize(x[0usize]), x[1usize])
        ret (rv, re)
    }
    if str.eq(c.name, "reg") {
        let n = usize(x[1usize])
        let m = usize(x[2usize])
        let (mask, e) = mem.alloc[bool](a, m)
        if e != ok { ret (0.0f64, e) }
        var k = 0usize
        while k < m {
            mask[k] = x[3usize + k] != 0.0f64
            k += 1usize
        }
        let at = 3usize + m
        let (rv, re) = bf.regression_bf(a, x[at..at + n], x[at + n..at + n + n * m], m, mask, x[0usize])
        ret (rv, re)
    }
    if str.eq(c.name, "factor") {
        let n = usize(x[2usize])
        let (g, e) = mem.alloc[usize](a, n)
        if e != ok { ret (0.0f64, e) }
        var k = 0usize
        while k < n {
            g[k] = usize(x[3usize + n + k])
            k += 1usize
        }
        let (rv, re) = bf.factor_bf(a, x[3usize..3usize + n], g, usize(x[1usize]), x[0usize])
        ret (rv, re)
    }
    if str.eq(c.name, "post1") || str.eq(c.name, "post2") {
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        let it = usize(x[1usize])
        let iv = bf.Ivl { on: x[3usize] != 0.0f64, compl: x[4usize] != 0.0f64, lo: x[5usize], hi: x[6usize] }
        let nx = usize(x[7usize])
        let ny = usize(x[8usize])
        var ch: []f64 = zero
        if str.eq(c.name, "post1") {
            let (c1, e1) = bf.gibbs_one(a, &g, x[9usize..9usize + nx], x[2usize], iv, it)
            if e1 != ok { ret (0.0f64, e1) }
            ch = c1
        } else {
            let (c2, e2) = bf.gibbs_two(a, &g, x[9usize..9usize + nx], x[9usize + nx..9usize + nx + ny], x[2usize], iv, it)
            if e2 != ok { ret (0.0f64, e2) }
            ch = c2
        }
        let row = usize(x[x.len - 2usize])
        let col = usize(x[x.len - 1usize])
        if row > 0usize { ret (ch[col * it + row - 1usize], ok) }
        var s = 0.0f64
        var k = 0usize
        while k < it {
            s += ch[col * it + k]
            k += 1usize
        }
        ret (s, ok)
    }
    if str.eq(c.name, "ppost") || str.eq(c.name, "rpost") {
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        let it = usize(x[1usize])
        var ch: []f64 = zero
        if str.eq(c.name, "ppost") {
            let iv = bf.Ivl { on: x[4usize] != 0.0f64, compl: x[5usize] != 0.0f64, lo: x[6usize], hi: x[7usize] }
            let m = usize(x[8usize])
            let (c1, e1) = bf.proportion_post(a, &g, x[9usize..9usize + m], x[9usize + m..9usize + 2usize * m], x[2usize], x[3usize], iv, it)
            if e1 != ok { ret (0.0f64, e1) }
            ch = c1
        } else {
            let iv = bf.Ivl { on: x[3usize] != 0.0f64, compl: x[4usize] != 0.0f64, lo: x[5usize], hi: x[6usize] }
            let n = usize(x[7usize])
            let (c2, e2) = bf.correlation_post(a, &g, x[8usize..8usize + n], x[8usize + n..8usize + 2usize * n], x[2usize], iv, it)
            if e2 != ok { ret (0.0f64, e2) }
            ch = c2
        }
        let row = usize(x[x.len - 2usize])
        let col = usize(x[x.len - 1usize])
        if row > 0usize { ret (ch[col * it + row - 1usize], ok) }
        var s = 0.0f64
        var k = 0usize
        while k < it {
            s += ch[col * it + k]
            k += 1usize
        }
        ret (s, ok)
    }
    if str.eq(c.name, "lpost") {
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        let it = usize(x[1usize])
        let n = usize(x[2usize])
        let p = usize(x[3usize])
        let (ch, e) = bf.linreg_post(a, &g, x[5usize..5usize + n], x[5usize + n..5usize + n + n * p], p, x[4usize], it)
        if e != ok { ret (0.0f64, e) }
        let row = usize(x[x.len - 2usize])
        let col = usize(x[x.len - 1usize])
        if row > 0usize { ret (ch[col * it + row - 1usize], ok) }
        var s = 0.0f64
        var k = 0usize
        while k < it {
            s += ch[col * it + k]
            k += 1usize
        }
        ret (s, ok)
    }
    if str.eq(c.name, "nway") {
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        let it = usize(x[1usize])
        let n = usize(x[2usize])
        let p = usize(x[3usize])
        let ng = usize(x[4usize])
        let (gm, e0) = mem.alloc[usize](a, p)
        if e0 != ok { ret (0.0f64, e0) }
        var k = 0usize
        while k < p {
            gm[k] = usize(x[6usize + k])
            k += 1usize
        }
        let at = 6usize + p
        let (rv, re) = bf.nway_mc_bf(a, &g, x[at + ng..at + ng + n], x[at + ng + n..at + ng + n + n * p], p, gm, x[at..at + ng], usize(x[5usize]), it)
        ret (rv, re)
    }
    if str.eq(c.name, "gibbs") {
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        let it = usize(x[1usize])
        let n = usize(x[2usize])
        let q = usize(x[3usize])
        let ng = usize(x[4usize])
        let (gm, e0) = mem.alloc[usize](a, q - 1usize)
        if e0 != ok { ret (0.0f64, e0) }
        var k = 0usize
        while k + 1usize < q {
            gm[k] = usize(x[6usize + k])
            k += 1usize
        }
        let at = 5usize + q
        let (ch, e) = bf.jzs_gibbs(a, &g, x[at + ng..at + ng + n], x[at + ng + n..at + ng + n + n * q], q, gm, x[at..at + ng], usize(x[5usize]), it)
        if e != ok { ret (0.0f64, e) }
        let row = usize(x[x.len - 2usize])
        let col = usize(x[x.len - 1usize])
        if row > 0usize { ret (ch[col * it + row - 1usize], ok) }
        var s = 0.0f64
        k = 0usize
        while k < it {
            s += ch[col * it + k]
            k += 1usize
        }
        ret (s, ok)
    }
    if str.eq(c.name, "cpost") {
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        let it = usize(x[1usize])
        let ni = usize(x[4usize])
        let nj = usize(x[5usize])
        let (ch, ncol, e) = bf.contingency_post(a, &g, x[6usize..6usize + ni * nj], ni, nj, usize(x[2usize]), x[3usize], it)
        if e != ok { ret (0.0f64, e) }
        let row = usize(x[x.len - 2usize])
        let col = usize(x[x.len - 1usize])
        if col >= ncol { ret (0.0f64, mem.Invalid) }
        if row > 0usize { ret (ch[col * it + row - 1usize], ok) }
        var s = 0.0f64
        var k = 0usize
        while k < it {
            s += ch[col * it + k]
            k += 1usize
        }
        ret (s, ok)
    }
    if str.eq(c.name, "anova") || str.eq(c.name, "lmbf") || str.eq(c.name, "gtest") || str.eq(c.name, "lmpost") {
        let (rv, re) = run_lm(a, c)
        ret (rv, re)
    }
    ret (0.0f64, mem.Invalid)
}

// H = (n, nv, kind[nv], nlev[nv], y[n], X) at x[at..]
fn lm_data(a: *mem.Arena, x: []const f64, at: usize) -> (bf.LmData, err) {
    let n = usize(x[at])
    let nv = usize(x[at + 1usize])
    let (kind, e1) = mem.alloc[usize](a, nv)
    let (nlev, e2) = mem.alloc[usize](a, nv)
    let y0 = at + 2usize + 2usize * nv
    let d = bf.LmData { y: x[y0..y0 + n], x: x[y0 + n..y0 + n + n * nv], n: n, nv: nv, kind: kind, nlev: nlev }
    if e1 != ok || e2 != ok { ret (d, mem.Full) }
    var v = 0usize
    while v < nv {
        kind[v] = usize(x[at + 2usize + v])
        nlev[v] = usize(x[at + 2usize + nv + v])
        v += 1usize
    }
    ret (d, ok)
}

fn terms_at(a: *mem.Arena, x: []const f64, at: usize, nt: usize) -> ([]u64, err) {
    let (t, e) = mem.alloc[u64](a, nt)
    if e != ok { ret (t, e) }
    var k = 0usize
    while k < nt {
        t[k] = u64(x[at + k])
        k += 1usize
    }
    ret (t, ok)
}

fn run_lm(a: *mem.Arena, c: *const oracle.Case) -> (f64, err) {
    let x = c.args
    var g: rng.Rng = zero
    rng.seed(&g, i64(x[0usize]))
    let it = usize(x[1usize])
    let (rows, e0) = mem.alloc[f64](a, 64usize)
    if e0 != ok { ret (0.0f64, e0) }
    if str.eq(c.name, "anova") {
        let pr = bf.LmPrior { fixed: x[2usize], random: x[3usize], cont: 0.0f64 }
        let (d, ed) = lm_data(a, x, 5usize)
        if ed != ok { ret (0.0f64, ed) }
        let (k, e) = bf.anova_bf(a, &g, &d, pr, 0usize, it, rows)
        let row = usize(x[4usize])
        if e != ok || row >= k { ret (0.0f64, mem.Invalid) }
        ret (rows[row], ok)
    }
    let pr = bf.LmPrior { fixed: x[2usize], random: x[3usize], cont: x[4usize] }
    if str.eq(c.name, "lmbf") {
        let nt = usize(x[5usize])
        let (t, et) = terms_at(a, x, 6usize, nt)
        let (d, ed) = lm_data(a, x, 6usize + nt)
        if et != ok || ed != ok { ret (0.0f64, mem.Full) }
        let (v, e) = bf.lm_bf(a, &g, &d, t, pr, 0usize, it)
        ret (v, e)
    }
    if str.eq(c.name, "gtest") {
        let nt = usize(x[5usize])
        let (t, et) = terms_at(a, x, 6usize, nt)
        let (d, ed) = lm_data(a, x, 7usize + nt)
        if et != ok || ed != ok { ret (0.0f64, mem.Full) }
        let (k, e) = bf.general_bf(a, &g, &d, t, pr, 0usize, it, rows)
        let row = usize(x[6usize + nt])
        if e != ok || row >= k { ret (0.0f64, mem.Invalid) }
        ret (rows[row], ok)
    }
    let nt = usize(x[7usize])
    let (t0, et) = terms_at(a, x, 8usize, nt)
    let (d, ed) = lm_data(a, x, 8usize + nt)
    if et != ok || ed != ok { ret (0.0f64, mem.Full) }
    var t = t0
    if x[5usize] == 0.0f64 {
        let (tm, em) = bf.anova_model(a, &d, usize(x[6usize]))
        if em != ok { ret (0.0f64, em) }
        t = tm
    }
    let (ch, ncol, e) = bf.lm_post(a, &g, &d, t, pr, it)
    if e != ok { ret (0.0f64, e) }
    let row = usize(x[x.len - 2usize])
    let col = usize(x[x.len - 1usize])
    if col >= ncol { ret (0.0f64, mem.Invalid) }
    if row > 0usize { ret (ch[col * it + row - 1usize], ok) }
    var s = 0.0f64
    var k = 0usize
    while k < it {
        s += ch[col * it + k]
        k += 1usize
    }
    ret (s, ok)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bayesfactor.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let (got, e) = run(a, c)
        if e != ok || !oracle.agrees(got, c) {
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
