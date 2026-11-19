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

// the coefficients over the a levels of contrast `idx` of family `ty` (0 trt.vs.ctrl, 1 revpairwise in emmeans' order, 2 consec, 3 eff, 4 poly)
fn contrast_coef(ty: usize, idx: usize, a: usize, w: []f64) {
    var k = 0usize
    while k < a {
        w[k] = 0.0f64
        k += 1usize
    }
    if ty == 0usize {
        w[idx] = 1.0f64
        w[0usize] = 0.0f64 - 1.0f64
    } else if ty == 1usize {
        // emmeans' revpairwise order: (2 - 1), (3 - 1), (3 - 2), (4 - 1), ...
        var r = 0usize
        var jj = 1usize
        while jj < a {
            var ii = 0usize
            while ii < jj {
                r += 1usize
                if r == idx {
                    w[jj] = 1.0f64
                    w[ii] = 0.0f64 - 1.0f64
                }
                ii += 1usize
            }
            jj += 1usize
        }
    } else if ty == 2usize {
        w[idx] = 1.0f64
        w[idx - 1usize] = 0.0f64 - 1.0f64
    } else if ty == 3usize {
        k = 0usize
        while k < a {
            w[k] = 0.0f64 - 1.0f64 / f64(a)
            k += 1usize
        }
        w[idx] = w[idx] + 1.0f64
    } else {
        if a == 3usize {
            if idx == 1usize { w[0usize] = 0.0f64 - 1.0f64
                w[2usize] = 1.0f64 }
            if idx == 2usize { w[0usize] = 1.0f64
                w[1usize] = 0.0f64 - 2.0f64
                w[2usize] = 1.0f64 }
        } else {
            if idx == 1usize { w[0usize] = 0.0f64 - 3.0f64
                w[1usize] = 0.0f64 - 1.0f64
                w[2usize] = 1.0f64
                w[3usize] = 3.0f64 }
            if idx == 2usize { w[0usize] = 1.0f64
                w[1usize] = 0.0f64 - 1.0f64
                w[2usize] = 0.0f64 - 1.0f64
                w[3usize] = 1.0f64 }
            if idx == 3usize { w[0usize] = 0.0f64 - 1.0f64
                w[1usize] = 3.0f64
                w[2usize] = 0.0f64 - 3.0f64
                w[3usize] = 1.0f64 }
        }
    }
}

// emtrends of lm(y ~ A * x): the design (intercept, A dummies, x, A dummies times x), the slope of level lv as a coefficient vector
fn trend_answer(ar: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let na = usize(z[1usize])
    let y = z[2usize..2usize + n]
    let fa = z[2usize + n..2usize + 2usize * n]
    let xv = z[2usize + 2usize * n..2usize + 3usize * n]
    let li = usize(z[2usize + 3usize * n])
    let lj = usize(z[3usize + 3usize * n])
    let p = 2usize * na
    let (d, de) = mem.alloc[f64](ar, n * p)
    let (rd, e1) = mem.alloc[f64](ar, p)
    if de != ok || e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < n {
        d[i] = 1.0f64
        var k = 1usize
        while k < na {
            if usize(fa[i]) == k { d[k * n + i] = 1.0f64 } else { d[k * n + i] = 0.0f64 }
            k += 1usize
        }
        d[na * n + i] = xv[i]
        k = 1usize
        while k < na {
            d[(na + k) * n + i] = d[k * n + i] * xv[i]
            k += 1usize
        }
        i += 1usize
    }
    let (m, fe) = em.fit(ar, d, y, n, p)
    if fe != ok { ret 0.0f64 / 0.0f64 }
    var k = 0usize
    while k < p {
        rd[k] = 0.0f64
        k += 1usize
    }
    // the slope of level l: the x coefficient plus the interaction of l (none for the reference level)
    rd[na] = 1.0f64
    if li > 0usize { rd[na + li] = 1.0f64 }
    if str.eq(c.name, "trend_est") { ret em.estimate(&m, rd) }
    if str.eq(c.name, "trend_se") { ret math.sqrt[f64](em.variance(&m, rd)) }
    
    rd[na] = 0.0f64
    k = 0usize
    while k < p {
        rd[k] = 0.0f64
        k += 1usize
    }
    if li > 0usize { rd[na + li] = 1.0f64 }
    if lj > 0usize { rd[na + lj] = 0.0f64 - 1.0f64 }
    if str.eq(c.name, "trend_pair_est") { ret em.estimate(&m, rd) }
    ret math.sqrt[f64](em.variance(&m, rd))
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.starts_with(c.name, "trend_") { ret trend_answer(a, c) }
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
    if str.eq(c.name, "jt_F") || str.eq(c.name, "jt_p") {
        // term li: 0 the factor A (differences of its adjusted means from level 0), 1 the factor B, 2 the covariate x
        var nrw = na - 1usize
        if li == 1usize { nrw = nb - 1usize }
        if li == 2usize { nrw = 1usize }
        let (lm, lme) = mem.alloc[f64](a, nrw * p)
        if lme != ok { ret 0.0f64 / 0.0f64 }
        var q0 = 0usize
        while q0 < nrw * p {
            lm[q0] = 0.0f64
            q0 += 1usize
        }
        var rw = 0usize
        while rw < nrw {
            if li == 0usize {
                grid_row(r1, na, nb, rw + 1usize, xbar)
                grid_row(r2, na, nb, 0usize, xbar)
                var k3 = 0usize
                while k3 < p {
                    lm[rw * p + k3] = r1[k3] - r2[k3]
                    k3 += 1usize
                }
            }
            if li == 1usize { lm[rw * p + na - 1usize + 1usize + rw] = 1.0f64 }
            if li == 2usize { lm[rw * p + p - 1usize] = 1.0f64 }
            rw += 1usize
        }
        var jo: [2]f64 = zero
        if !em.joint_f(a, &m, lm, nrw, jo[0usize..2usize]) { ret 0.0f64 / 0.0f64 }
        if str.eq(c.name, "jt_F") { ret jo[0usize] }
        ret jo[1usize]
    }
    if str.eq(c.name, "ctr_est") || str.eq(c.name, "ctr_se") {
        let (wv, we) = mem.alloc[f64](a, na)
        if we != ok { ret 0.0f64 / 0.0f64 }
        contrast_coef(li, lj, na, wv)
        var kk = 0usize
        while kk < p {
            rd[kk] = 0.0f64
            kk += 1usize
        }
        var lv = 0usize
        while lv < na {
            grid_row(r1, na, nb, lv, xbar)
            kk = 0usize
            while kk < p {
                rd[kk] += wv[lv] * r1[kk]
                kk += 1usize
            }
            lv += 1usize
        }
        if str.eq(c.name, "ctr_est") { ret em.estimate(&m, rd) }
        ret math.sqrt[f64](em.variance(&m, rd))
    }
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
    if str.eq(c.name, "p_scheffe") { ret em.p_scheffe(t, f64(na - 1usize), m.df) }
    if str.starts_with(c.name, "es_") {
        var rss = 0.0f64
        var oi = 0usize
        while oi < n {
            var fit = 0.0f64
            var oj = 0usize
            while oj < p {
                fit += d[oj * n + oi] * m.beta[oj]
                oj += 1usize
            }
            rss += (y[oi] - fit) * (y[oi] - fit)
            oi += 1usize
        }
        var eo: [4]f64 = zero
        em.eff_size(est, se, math.sqrt[f64](rss / m.df), m.df, 0.95f64, eo[0usize..4usize])
        if str.eq(c.name, "es_est") { ret eo[0usize] }
        if str.eq(c.name, "es_se") { ret eo[1usize] }
        if str.eq(c.name, "es_lo") { ret eo[2usize] }
        ret eo[3usize]
    }
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
