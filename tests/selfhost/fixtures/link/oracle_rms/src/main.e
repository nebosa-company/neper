// e.algo.stat.rmspkg against rms rcspline.eval, ols and lrm. tests/oracle/rms.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rms`; the layout is at the top of scripts/r_oracle/groups/rms.R.

use e.algo.stat.rmspkg as rm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let nk = usize(z[1usize])
    let knots = z[2usize..2usize + nk]
    let x = z[2usize + nk..2usize + nk + n]
    let zz = z[2usize + nk + n..2usize + nk + 2usize * n]
    let y = z[2usize + nk + 2usize * n..2usize + nk + 3usize * n]
    let w = nk - 1usize
    let p = w + 1usize
    let (basis, e1) = mem.alloc[f64](a, n * w)
    let (design, e2) = mem.alloc[f64](a, n * p)
    let (out, e3) = mem.alloc[f64](a, 4usize * p + 8usize)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    rm.rcs(x, knots, basis)
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "rcs") {
        while i < n * w {
            s += basis[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    i = 0usize
    while i < n {
        var j = 0usize
        while j < w {
            design[i * p + j] = basis[i * w + j]
            j += 1usize
        }
        design[i * p + w] = zz[i]
        i += 1usize
    }
    let q = p + 1usize
    if str.eq(c.name, "ols_coef") || str.eq(c.name, "ols_se") || str.eq(c.name, "ols_r2") || str.eq(c.name, "ols_sigma") {
        if rm.ols(a, design, y, n, p, out) != ok { ret nan }
        if str.eq(c.name, "ols_r2") { ret out[2usize * q] }
        if str.eq(c.name, "ols_sigma") { ret out[2usize * q + 1usize] }
        var lo = 0usize
        if str.eq(c.name, "ols_se") { lo = q }
        i = 0usize
        while i < q {
            s += out[lo + i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if rm.lrm(a, design, y, n, p, out) != ok { ret nan }
    if str.eq(c.name, "lrm_lr") { ret out[q] }
    if str.eq(c.name, "lrm_c") { ret out[q + 1usize] }
    if str.eq(c.name, "lrm_dxy") { ret out[q + 2usize] }
    if str.eq(c.name, "lrm_r2") { ret out[q + 3usize] }
    if str.eq(c.name, "lrm_brier") { ret out[q + 4usize] }
    i = 0usize
    while i < q {
        s += out[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rms.json")
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
