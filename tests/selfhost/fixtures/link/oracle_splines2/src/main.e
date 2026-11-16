// e.algo.stat.splines against splines2: bSpline (with derivatives), mSpline, iSpline. tests/oracle/splines2.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R splines2`; the layout is at the top of
// scripts/r_oracle/groups/splines2.R.

use e.algo.stat.splines as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let nk = usize(z[1usize])
    let degree = usize(z[2usize])
    let icp = z[3usize] != 0.0f64
    let lo = z[4usize]
    let hi = z[5usize]
    let kind = usize(z[6usize])
    let xs = z[7usize..7usize + n]
    let knots = z[7usize + n..7usize + n + nk]
    let width = nk + degree + 1usize
    let (t, e1) = mem.alloc[f64](a, nk + 2usize * (degree + 2usize))
    let (tmp, e2) = mem.alloc[f64](a, 2usize * width + 4usize)
    let (out, e3) = mem.alloc[f64](a, width)
    if e1 != ok || e2 != ok || e3 != ok { ret 0.0f64 / 0.0f64 }
    var k8 = 0u8
    var deriv = 0usize
    if kind == 1usize { k8 = 1u8 }
    if kind == 2usize { k8 = 2u8 }
    if kind == 3usize { deriv = 1usize }
    if kind == 4usize { deriv = 2usize }
    var s = 0.0f64
    var cnt = 0usize
    var i = 0usize
    while i < n {
        let m = sp.row(t, tmp, knots, lo, hi, degree, icp, k8, deriv, xs[i], out)
        var j = 0usize
        while j < m {
            cnt += 1usize
            if str.eq(c.name, "sum") { s += out[j] } else { s += f64(cnt) * out[j] }
            j += 1usize
        }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/splines2.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
