// e.algo.stat.emmeans against emmeans for lm(y ~ A + B + x): EMMs of A, SEs, pairwise Tukey, Holm and
// Bonferroni. tests/oracle/emmeans.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R
// emmeans`; the layout is at the top of scripts/r_oracle/groups/emmeans.R.

use e.algo.stat.emmeans as em
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// the reference-grid row of A level i: intercept, A dummies, B dummies at their mean, x at its mean
fn grid_row(row: []f64, a: usize, b: usize, i: usize, xbar: f64) {
    let p = 1usize + (a - 1usize) + (b - 1usize) + 1usize
    var k = 0usize
    while k < p {
        row[k] = 0.0f64
        k += 1usize
    }
    row[0usize] = 1.0f64
    if i > 0usize { row[i] = 1.0f64 }
    k = 0usize
    while k < b - 1usize {
        row[a + k] = 1.0f64 / f64(b)
        k += 1usize
    }
    row[p - 1usize] = xbar
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let na = usize(z[1usize])
    let nb = usize(z[2usize])
    let y = z[3usize..3usize + n]
    let fa = z[3usize + n..3usize + 2usize * n]
    let fb = z[3usize + 2usize * n..3usize + 3usize * n]
    let xv = z[3usize + 3usize * n..3usize + 4usize * n]
    let li = usize(z[3usize + 4usize * n])
    let lj = usize(z[4usize + 4usize * n])
    let p = 1usize + (na - 1usize) + (nb - 1usize) + 1usize
    let (d, de) = mem.alloc[f64](a, n * p)
    let (r1, e1) = mem.alloc[f64](a, p)
    let (r2, e2) = mem.alloc[f64](a, p)
    let (rd, e3) = mem.alloc[f64](a, p)
    if de != ok || e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var xbar = 0.0f64
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        var k = 1usize
        while k < na {
            if usize(fa[i]) == k { d[k * n + i] = 1.0f64 } else { d[k * n + i] = 0.0f64 }
            k += 1usize
        }
        k = 1usize
        while k < nb {
            if usize(fb[i]) == k { d[(na - 1usize + k) * n + i] = 1.0f64 } else { d[(na - 1usize + k) * n + i] = 0.0f64 }
            k += 1usize
        }
        d[(p - 1usize) * n + i] = xv[i]
        xbar += xv[i]
        i += 1usize
    }
    xbar = xbar / f64(n)
    let (m, fe) = em.fit(a, d, y, n, p)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    grid_row(r1, na, nb, li, xbar)
    if str.eq(c.name, "emm") { ret em.estimate(&m, r1) }
    if str.eq(c.name, "se") { ret math.sqrt[f64](em.variance(&m, r1)) }
    if str.eq(c.name, "df") { ret m.df }
    grid_row(r2, na, nb, lj, xbar)
    var k = 0usize
    while k < p {
        rd[k] = r1[k] - r2[k]
        k += 1usize
    }
    let est = em.estimate(&m, rd)
    let se = math.sqrt[f64](em.variance(&m, rd))
    let t = est / se
    if str.eq(c.name, "pair_est") { ret est }
    if str.eq(c.name, "pair_se") { ret se }
    if str.eq(c.name, "pair_t") { ret t }
    if str.eq(c.name, "p_tukey") { ret em.p_tukey(t, f64(na), m.df) }
    let pairs = na * (na - 1usize) / 2usize
    if str.eq(c.name, "p_bonf") { ret em.p_bonferroni(em.p_t(t, m.df), f64(pairs)) }
    // holm over every pair of A in emmeans' order
    let (ps, pe) = mem.alloc[f64](a, pairs)
    if pe != ok { ret 0.0f64 / 0.0f64 }
    var r = 0usize
    var at = 0usize
    var u = 0usize
    while u < na {
        var v = u + 1usize
        while v < na {
            grid_row(r1, na, nb, u, xbar)
            grid_row(r2, na, nb, v, xbar)
            k = 0usize
            while k < p {
                rd[k] = r1[k] - r2[k]
                k += 1usize
            }
            ps[r] = em.p_t(em.estimate(&m, rd) / math.sqrt[f64](em.variance(&m, rd)), m.df)
            if u == li && v == lj { at = r }
            r += 1usize
            v += 1usize
        }
        u += 1usize
    }
    em.holm(ps)
    ret ps[at]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/emmeans.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 8usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
