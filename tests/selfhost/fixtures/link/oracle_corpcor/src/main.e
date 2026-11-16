// e.algo.stat.corpcor against corpcor: shrinkage lambdas, var.shrink, cor.shrink, cov.shrink and the
// pseudoinverse. tests/oracle/corpcor.json comes from `R_ORACLE_LIB=<dir> Rscript
// scripts/r_oracle/generate.R corpcor`; the layout is at the top of scripts/r_oracle/groups/corpcor.R.

use e.algo.stat.corpcor as cp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn values(a: *mem.Arena, c: *const oracle.Case, data: []const f64, n: usize, p: usize, lam: f64, lamv: f64) -> []f64 {
    var none: []f64 = zero
    if str.eq(c.name, "var") {
        let (v, l, e) = cp.var_shrink(a, data, n, p, lamv)
        if e != ok { os.exit(6) }
        ret v
    }
    if str.eq(c.name, "cor") {
        let (v, l, e) = cp.cor_shrink(a, data, n, p, lam)
        if e != ok { os.exit(6) }
        ret v
    }
    if str.eq(c.name, "cov") {
        let (v, e) = cp.cov_shrink(a, data, n, p, lam, lamv)
        if e != ok { os.exit(6) }
        ret v
    }
    if str.eq(c.name, "pcor") {
        let (v, e) = cp.pcor_shrink(a, data, n, p, lam)
        if e != ok { os.exit(6) }
        ret v
    }
    let (v, e) = cp.pseudoinverse(a, data, n, p)
    if e != ok { os.exit(6) }
    ret v
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let p = usize(x[1usize])
    let data = x[4usize..4usize + n * p]
    if str.eq(c.name, "lambda_cor") {
        let (l, e) = cp.lambda_cor(a, data, n, p)
        if e != ok { os.exit(6) }
        ret l
    }
    if str.eq(c.name, "lambda_var") {
        let (l, e) = cp.lambda_var(a, data, n, p)
        if e != ok { os.exit(6) }
        ret l
    }
    let v = values(a, c, data, n, p, x[2usize], x[3usize])
    let stat = u8(x[x.len - 1usize])
    if stat == 0u8 { ret f64(v.len) }
    var s = 0.0f64
    var w = 0.0f64
    var q = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i]
        w += f64(i + 1usize) * v[i]
        q += v[i] * v[i]
        i += 1usize
    }
    if stat == 1u8 { ret s }
    if stat == 2u8 { ret w }
    if stat == 3u8 { ret v[0usize] }
    if stat == 4u8 { ret v[v.len - 1usize] }
    ret q
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/corpcor.json")
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
