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
    if str.eq(c.name, "snm") {
        let (w3, g1) = mem.alloc[f64](a, n * rk)
        let (h3, g2) = mem.alloc[f64](a, rk * p)
        let (o3, g3) = mem.alloc[f64](a, 2usize)
        if g1 != ok || g2 != ok || g3 != ok { ret nan }
        let se = nf.snmf_fit(a, z[6usize..6usize + n * p], n, p, rk, usize(z[3usize]), i64(z[4usize]), 20000usize, 0.0f64 - 1.0f64, 0.01f64, 0.0f64, 10.0f64, 1.0e-4f64, w3, h3, o3)
        if se != ok { ret nan }
        let sx = usize(z[6usize + n * p])
        if sx == 0usize { ret o3[0usize] }
        if sx <= n * rk { ret w3[sx - 1usize] }
        ret h3[sx - 1usize - n * rk]
    }
    if str.eq(c.name, "nmr") || str.eq(c.name, "nmc") {
        let (w2, f1) = mem.alloc[f64](a, n * rk)
        let (h2, f2) = mem.alloc[f64](a, rk * p)
        let (o2, f3) = mem.alloc[f64](a, 4usize)
        let (cs2, f4) = mem.alloc[f64](a, p * p)
        if f1 != ok || f2 != ok || f3 != ok || f4 != ok { ret nan }
        let re = nf.nmf_runs(a, z[6usize..6usize + n * p], n, p, rk, usize(z[3usize]), i64(z[4usize]), 2000usize, usize(z[5usize]), w2, h2, cs2, o2)
        if re != ok { ret nan }
        let ix = usize(z[6usize + n * p])
        if str.eq(c.name, "nmc") {
            if ix == 0usize { ret nf.nmf_cophcor(a, cs2, p) }
            if ix == 1usize { ret nf.nmf_dispersion(cs2) }
            if ix == p * p + 2usize { ret nf.nmf_silhouette_consensus(a, cs2, p, rk) }
            if ix == p * p + 3usize { ret nf.nmf_silhouette_coef(a, h2, rk, p) }
            if ix == p * p + 4usize { ret nf.nmf_silhouette_basis(a, w2, n, rk) }
            if ix == p * p + 5usize { ret nf.nmf_sparseness(w2, n, rk) }
            if ix == p * p + 6usize { ret nf.nmf_sparseness(h2, rk, p) }
            if ix == p * p + 7usize { ret nf.nmf_rss_evar(a, z[6usize..6usize + n * p], w2, h2, n, p, rk, 0usize) }
            if ix == p * p + 8usize { ret nf.nmf_rss_evar(a, z[6usize..6usize + n * p], w2, h2, n, p, rk, 1usize) }
            ret cs2[ix - 2usize]
        }
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
