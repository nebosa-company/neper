// e.algo.linalg.mexp against Matrix: expm and the matrix norms. tests/oracle/matrix.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R matrix`; the layout is at the top of
// scripts/r_oracle/groups/matrix.R.

use e.algo.linalg.mexp as mx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let m = x[1usize..1usize + n * n]
    if str.eq(c.name, "norm1") { ret mx.norm_one(m, n) }
    if str.eq(c.name, "normI") { ret mx.norm_inf(m, n) }
    if str.eq(c.name, "normF") { ret mx.norm_frobenius(m, n) }
    if str.eq(c.name, "normM") { ret mx.norm_max(m, n) }
    let (e, ee) = mem.alloc[f64](a, n * n)
    if ee != ok { ret 0.0f64 / 0.0f64 }
    if mx.expm(a, m, n, e) != ok { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    var i = 0usize
    while i < n * n {
        if str.eq(c.name, "expm_sum") { s += e[i] } else if str.eq(c.name, "expm_w") { s += f64(i + 1usize) * e[i] } else if i % (n + 1usize) == 0usize { s += e[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/matrix.json")
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
