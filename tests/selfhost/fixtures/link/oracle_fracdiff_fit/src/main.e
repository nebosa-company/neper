// e.algo.stat.fracdiff_fit.fracdf against fracdiff's fracdiff(). tests/oracle/fracdiff_fit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R fracdiff_fit`; the layout is at the top of scripts/r_oracle/groups/fracdiff_fit.R.

use e.algo.stat.fracdiff_fit as fd
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let q = usize(z[2usize])
    let (qp, e) = mem.alloc[f64](a, p + q + 1usize)
    if e != ok { ret nan }
    var i = 0usize
    while i < p + q + 1usize {
        qp[i] = 0.0f64
        i += 1usize
    }
    let (r, fe) = fd.fracdf(a, z[4usize..4usize + n], usize(z[3usize]), p, q, 0.0001220703125f64, 0.0f64, 0.5f64, 0.0f64, 0.0f64 - 1.0f64, qp[0usize..p + q])
    if fe != ok || r.info != 0i64 { ret nan }
    let w = usize(z[4usize + n])
    if w == 0usize { ret r.d }
    if w == 1usize { ret r.hood }
    if w == 2usize { ret r.fnorm }
    if w == 3usize { ret math.sqrt[f64](r.wnv) }
    let k1 = p + q + 1usize
    let b = 4usize + p + q
    if w < b {
        let j = w - 4usize
        if j < p { ret qp[q + j] }
        ret qp[j - p]
    }
    if w == b { ret r.h }
    if w <= b + k1 * k1 { ret r.cov[w - b - 1usize] }
    if w <= b + 2usize * k1 * k1 { ret r.hess[w - b - k1 * k1 - 1usize] }
    ret r.se[w - b - 2usize * k1 * k1 - 1usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/fracdiff_fit.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let start = mem.mark(a)
        let got = answer(a, c)
        mem.reset(a, start)
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
