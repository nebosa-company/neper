// e.algo.stat.robustbase_reg against robustbase. tests/oracle/robustbase_reg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R robustbase_reg`; the layout is at the top of scripts/r_oracle/groups/robustbase_reg.R.

use e.algo.stat.robustbase_reg as rr
use e.algo.stat.robustbase_nl as nl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn glmrob_answer(a: *mem.Arena, x: []const f64) -> f64 {
    let fam = usize(x[0usize])
    let hat = x[1usize] != 0.0f64
    let tcc = x[2usize]
    let n = usize(x[3usize])
    let p = usize(x[4usize])
    let xm = x[5usize..5usize + n * p]
    let y = x[5usize + n * p..5usize + n * p + n]
    let ni = x[5usize + n * p + n..5usize + n * p + 2usize * n]
    let which = usize(x[5usize + n * p + 2usize * n])
    let idx = usize(x[6usize + n * p + 2usize * n])
    let (wx, e0) = mem.alloc[f64](a, n)
    let (coef, e1) = mem.alloc[f64](a, p)
    let (cov, e2) = mem.alloc[f64](a, p * p)
    let (wr, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        wx[i] = 1.0f64
        i += 1usize
    }
    if hat {
        if rr.hat_weights(a, xm, n, p, wx) != ok { os.exit(6) }
    }
    let (fit, fe) = rr.glmrob_mqle(a, xm, y, ni, wx, n, p, fam, tcc, 1.0e-4f64, 50usize, coef, cov, wr)
    if fe != ok { os.exit(7) }
    if which == 0usize { ret coef[idx] }
    if which == 1usize { ret f64(fit.iter) }
    if which == 2usize { ret cov[idx] }
    ret wr[idx]
}

fn nlrob_answer(a: *mem.Arena, x: []const f64) -> f64 {
    let m = usize(x[0usize])
    let np = usize(x[1usize])
    let cc = x[2usize]
    let n = usize(x[3usize])
    let xs = x[4usize..4usize + n]
    let ys = x[4usize + n..4usize + 2usize * n]
    let st = x[4usize + 2usize * n..4usize + 2usize * n + np]
    let which = usize(x[4usize + 2usize * n + np])
    let idx = usize(x[5usize + 2usize * n + np])
    let (par, e0) = mem.alloc[f64](a, np)
    let (cov, e1) = mem.alloc[f64](a, np * np)
    let (rw, e2) = mem.alloc[f64](a, n)
    let (res, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var i = 0usize
    while i < np {
        par[i] = st[i]
        i += 1usize
    }
    let (fit, fe) = nl.nlrob_m(a, m, par, np, xs, ys, n, cc, 20usize, 1.0e-6f64, cov, rw, res)
    if fe != ok || !fit.converged { os.exit(7) }
    if which == 0usize { ret par[idx] }
    if which == 1usize { ret fit.scale }
    if which == 2usize { ret f64(fit.iter) }
    if which == 3usize { ret cov[idx] }
    if which == 4usize { ret rw[idx] }
    ret res[idx]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "glmrob") { ret glmrob_answer(a, x) }
    if str.eq(k, "nlrob") { ret nlrob_answer(a, x) }
    os.exit(4)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/robustbase_reg.json")
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
