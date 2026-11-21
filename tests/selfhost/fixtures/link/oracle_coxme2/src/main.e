// e.algo.stat.coxme against coxme::coxme. tests/oracle/coxme2.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R coxme2`;
// the case layout is at the top of scripts/r_oracle/groups/coxme.R. Cases of one fit differ only in the output selector (args[0]),
// so a fit is cached while consecutive cases share the rest of the arguments.

use e.algo.stat.coxme as cm
use e.io
use e.math
use e.math.nmath as nm
use e.mem
use e.os
use e.test.oracle as oracle

type Cache = struct { key: []const f64, fit: cm.CoxmeFit, good: bool }

fn fit_case(a: *mem.Arena, x: []const f64) -> (cm.CoxmeFit, err) {
    var empty: cm.CoxmeFit = zero
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let efron = x[3usize] == 1.0f64
    let hs = x[4usize] == 1.0f64
    let ho = x[5usize] == 1.0f64
    let hw = x[6usize] == 1.0f64
    let nterm = usize(x[7usize])
    var at = 8usize
    let time = x[at..at + n]
    at += n
    let status = x[at..at + n]
    at += n
    let (strata, e1) = mem.alloc[usize](a, n)
    let (offset, e2) = mem.alloc[f64](a, n)
    let (weights, e3) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok { ret (empty, e1) }
    var i = 0usize
    while i < n {
        strata[i] = 0usize
        offset[i] = 0.0f64
        weights[i] = 1.0f64
        i += 1usize
    }
    if hs {
        i = 0usize
        while i < n {
            strata[i] = usize(x[at + i])
            i += 1usize
        }
        at += n
    }
    if ho {
        i = 0usize
        while i < n {
            offset[i] = x[at + i]
            i += 1usize
        }
        at += n
    }
    if hw {
        i = 0usize
        while i < n {
            weights[i] = x[at + i]
            i += 1usize
        }
        at += n
    }
    let xm = x[at..at + n * p]
    at += n * p
    let (terms, e4) = mem.alloc[cm.CoxmeTerm](a, nterm)
    if e4 != ok { ret (empty, e4) }
    var t = 0usize
    while t < nterm {
        let icpt = x[at] == 1.0f64
        let ng = usize(x[at + 1usize])
        let nvar = usize(x[at + 2usize])
        at += 3usize
        let (codes, e5) = mem.alloc[usize](a, ng * n)
        if e5 != ok { ret (empty, e5) }
        i = 0usize
        while i < ng * n {
            codes[i] = usize(x[at + i])
            i += 1usize
        }
        at += ng * n
        let zs = x[at..at + n * nvar]
        at += n * nvar
        terms[t] = cm.CoxmeTerm { icpt: icpt, ng: ng, codes: codes, nvar: nvar, xs: zs }
        t += 1usize
    }
    let (fit, fe) = cm.coxme_fit(a, time, status, strata, weights, offset, xm, n, p, efron, terms)
    ret (fit, fe)
}

fn pick(f: *const cm.CoxmeFit, q: usize, events: f64) -> f64 {
    let kind = q / 100000usize
    let i = q % 100000usize
    if kind == 0usize { ret f.fixef[i] }
    if kind == 1usize { ret f.frail[i] }
    if kind == 2usize { ret f.vcoef[i] }
    if kind == 3usize {
        let nv = f.nfrail + f.nfixed
        ret f.vmat[(i / 100usize) * nv + i % 100usize]
    }
    if kind == 5usize {
        let k = i / 10usize
        let j = i % 10usize
        var lk = f.ll_int
        var dfk = f.df_int
        if k == 1usize {
            lk = f.ll_pen + f.penalty
            dfk = f.df_pen
        }
        let chi = 2.0f64 * (lk - f.ll_null)
        if j == 0usize { ret chi }
        if j == 1usize { ret 1.0f64 - nm.pchisq(chi, dfk, true, false) }
        if j == 2usize { ret chi - 2.0f64 * dfk }
        ret chi - math.log[f64](events) * dfk
    }
    if kind == 6usize {
        let k = i / 10usize
        let j = i % 10usize
        let nv = f.nfrail + f.nfixed
        let se = math.sqrt[f64](f.vmat[(f.nfrail + k) * nv + f.nfrail + k])
        let z = f.fixef[k] / se
        if j == 0usize { ret se }
        if j == 1usize { ret z }
        ret nm.pchisq(z * z, 1.0f64, false, false)
    }
    if i == 0usize { ret f.ll_null }
    if i == 1usize { ret f.ll_int }
    if i == 2usize { ret f.ll_pen }
    if i == 3usize { ret f.penalty }
    if i == 4usize { ret f.df_int }
    if i == 5usize { ret f.df_pen }
    if i == 6usize { ret f64(f.it_outer) }
    ret f64(f.it_inner)
}

fn answer(a: *mem.Arena, c: *const oracle.Case, ch: *Cache) -> f64 {
    let x = c.args
    var same = ch.good && ch.key.len == x.len
    if same {
        var j = 1usize
        while j < x.len {
            if ch.key[j] != x[j] {
                same = false
                break
            }
            j += 1usize
        }
    }
    if !same {
        let (f, fe) = fit_case(a, x)
        if fe != ok { ret 0.0f64 / 0.0f64 }
        ch.fit = f
        ch.key = x
        ch.good = true
    }
    var events = 0.0f64
    let n = usize(x[1usize])
    var k = 0usize
    while k < n {
        events += x[8usize + n + k]
        k += 1usize
    }
    ret pick(&ch.fit, usize(x[0usize]), events)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/coxme2.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var ch: Cache = zero
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c, &ch)
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
