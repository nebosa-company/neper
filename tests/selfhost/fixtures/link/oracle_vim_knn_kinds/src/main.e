// e.algo.stat.vimpkg.knn_impute_kinds_full against VIM::kNN with ordered and semi-continuous distance
// columns. tests/oracle/vim_knn_kinds.json comes from `Rscript scripts/r_oracle/generate.R vim_knn_kinds`;
// the layout is at the top of scripts/r_oracle/groups/vim_knn_kinds.R.

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
    let k = usize(z[2usize])
    let use_mean = z[3usize] > 0.5f64
    let base = 4usize
    let (kind, e0) = mem.alloc[u8](a, p)
    let (nlev, e1) = mem.alloc[usize](a, p)
    let (mconst, e2) = mem.alloc[f64](a, p)
    let (out, e3) = mem.alloc[f64](a, n)
    if e0 != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var i = 0usize
    while i < p {
        kind[i] = u8(z[base + i])
        nlev[i] = usize(z[base + p + i])
        mconst[i] = z[base + 2usize * p + i]
        i += 1usize
    }
    let at = base + 3usize * p
    if vm.knn_impute_kinds_full(a, z[at..at + n * p], n, p, 0usize, k, use_mean, kind, nlev, mconst, out) != ok { ret nan }
    var s = 0.0f64
    i = 0usize
    while i < n {
        s += out[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/vim_knn_kinds.json")
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
