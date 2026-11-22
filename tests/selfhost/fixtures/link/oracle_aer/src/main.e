// e.algo.stat.aerpkg against AER ivreg (with diagnostics) and dispersiontest. tests/oracle/aer.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R aer`; the argument layout is at the top of scripts/r_oracle/groups/aer.R.

use e.algo.stat.aerpkg as aer
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(v: []const f64, n: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let name = c.name
    if str.eq(name, "disp") {
        let (out, e1) = mem.alloc[f64](a, 3usize)
        if e1 != ok { ret nan }
        let alt = usize(z[3usize])
        let w = usize(z[4usize])
        if aer.dispersiontest(a, z[5usize + n..5usize + n + n * p], z[5usize..5usize + n], n, p, z[2usize], alt, out) != ok { ret nan }
        ret out[w]
    }
    let q = usize(z[2usize])
    let which = usize(z[4usize])
    let h = 5usize
    let (iva, e2) = mem.alloc[aer.Iv](a, 1usize)
    if e2 != ok { ret nan }
    let iv = &iva[0usize]
    let xo = h + p + n
    if aer.ivreg(a, z[xo..xo + n * p], z[xo + n * p..xo + n * p + n * q], z[h + p..h + p + n], z[h..h + p], n, p, q, z[3usize] != 0.0f64, iv) != ok { ret nan }
    if which == 0usize { ret wsum(iv.coef, p) }
    if which == 1usize {
        var s = 0.0f64
        var i = 0usize
        while i < p {
            s += math.sqrt[f64](iv.vc[i * p + i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if which == 2usize { ret iv.sigma }
    if which == 3usize { ret iv.r2 }
    if which == 4usize { ret iv.adjr2 }
    if which == 5usize { ret iv.wald }
    if which == 6usize { ret iv.waldp }
    ret iv.diag[which - 10usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/aer.json")
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
