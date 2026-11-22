// e.algo.stat.vimpkg.knn_impute_mixed against VIM::kNN with missing distance values. tests/oracle/vim_knn_missing.json comes from
// `Rscript scripts/r_oracle/generate.R vim_knn_missing`; the layout is at the top of
// scripts/r_oracle/groups/vim_knn_missing.R.

use e.algo.stat.vimpkg as vm
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let v = usize(z[2usize])
    let k = usize(z[3usize])
    let use_mean = z[4usize] > 0.5f64
    let (fac, e0) = mem.alloc[bool](a, p)
    let (out, e1) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok { ret nan }
    var i = 0usize
    while i < p {
        fac[i] = z[5usize + i] > 0.5f64
        i += 1usize
    }
    if vm.knn_impute_mixed(a, z[5usize + p..5usize + p + n * p], n, p, v, k, use_mean, fac, out) != ok { ret nan }
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += out[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vim_knn_missing.json")
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
