// e.algo.stat.nmfpkg against NMF: nmf(x, rank, method = "brunet" or "lee", seed = integer), W, H and the iteration count.
// tests/oracle/nmf.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R nmf`.

use e.algo.stat.nmfpkg as nf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let rk = usize(z[2usize])
    if str.eq(c.name, "nmr") {
        let (w2, f1) = mem.alloc[f64](a, n * rk)
        let (h2, f2) = mem.alloc[f64](a, rk * p)
        let (o2, f3) = mem.alloc[f64](a, 4usize)
        if f1 != ok || f2 != ok || f3 != ok { ret nan }
        let re = nf.nmf_runs(a, z[6usize..6usize + n * p], n, p, rk, usize(z[3usize]), i64(z[4usize]), 2000usize, usize(z[5usize]), w2, h2, o2)
        if re != ok { ret nan }
        let ix = usize(z[6usize + n * p])
        if ix == 0usize { ret o2[0usize] }
        if ix <= n * rk { ret w2[ix - 1usize] }
        ret h2[ix - 1usize - n * rk]
    }
    let (w, e1) = mem.alloc[f64](a, n * rk)
    let (h, e2) = mem.alloc[f64](a, rk * p)
    let (out, e3) = mem.alloc[f64](a, 2usize)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    let fe = nf.nmf_fit(a, z[6usize..6usize + n * p], n, p, rk, usize(z[3usize]) % 10usize, i64(z[4usize]), 2000usize, z[5usize], usize(z[3usize]) / 10usize, 0i64 - 1i64, w, h, out)
    if fe != ok { ret nan }
    let idx = usize(z[6usize + n * p])
    if idx == 0usize { ret out[0usize] }
    if idx <= n * rk { ret w[idx - 1usize] }
    ret h[idx - 1usize - n * rk]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/nmf.json")
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
