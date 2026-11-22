// e.algo.stat.vimpkg.knn_impute_multi against VIM::kNN with several target variables.
// tests/oracle/vim_knn_multi.json comes from `Rscript scripts/r_oracle/generate.R vim_knn_multi`; the
// layout is at the top of scripts/r_oracle/groups/vim_knn_multi.R.

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
    let nv = usize(z[2usize])
    let base = 3usize + nv
    let k = usize(z[base])
    let use_mean = z[base + 1usize] > 0.5f64
    let (vars, e0) = mem.alloc[usize](a, nv)
    let (fac, e1) = mem.alloc[bool](a, p)
    let (out, e2) = mem.alloc[f64](a, n * p)
    if e0 != ok || e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < nv {
        vars[i] = usize(z[3usize + i])
        i += 1usize
    }
    i = 0usize
    while i < p {
        fac[i] = z[base + 2usize + i] > 0.5f64
        i += 1usize
    }
    let at = base + 2usize + p
    if vm.knn_impute_multi(a, z[at..at + n * p], n, p, vars, k, use_mean, fac, out) != ok { ret nan }
    var s = 0.0f64
    var idx = 0usize
    i = 0usize
    while i < n {
        var t = 0usize
        while t < nv {
            s += out[i * p + vars[t]] * f64(idx + 1usize)
            idx += 1usize
            t += 1usize
        }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vim_knn_multi.json")
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
