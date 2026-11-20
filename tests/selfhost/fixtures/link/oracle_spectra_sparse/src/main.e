// e.algo.stat.spectrapkg's svds and eigs_sym on sparse input against RSpectra. tests/oracle/spectra_sparse.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_sparse`; the layout is at the top of scripts/r_oracle/groups/spectra_sparse.R.

use e.algo.linalg.sparse as sparse
use e.algo.stat.spectrapkg as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let kind = usize(z[0usize])
    let m = usize(z[1usize])
    let n = usize(z[2usize])
    let k = usize(z[3usize])
    let nnz = usize(z[4usize])
    let wh = usize(z[5usize])
    let sigma = z[6usize]
    let part = usize(z[7usize])
    let (ti, e0) = mem.alloc[usize](a, nnz)
    let (tj, e1) = mem.alloc[usize](a, nnz)
    let (d, e2) = mem.alloc[f64](a, k)
    let (di, e4) = mem.alloc[f64](a, k)
    let (u, e5) = mem.alloc[f64](a, m * k)
    let (v, e6) = mem.alloc[f64](a, n * k)
    if e0 != ok || e1 != ok || e2 != ok || e4 != ok || e5 != ok || e6 != ok { os.exit(4) }
    var t = 0usize
    while t < nnz {
        ti[t] = usize(z[8usize + t])
        tj[t] = usize(z[8usize + nnz + t])
        t += 1usize
    }
    let (csc, e3) = sparse.from_triplets(a, m, n, ti, tj, z[8usize + 2usize * nnz..8usize + 3usize * nnz])
    if e3 != ok { os.exit(5) }
    if kind == 0usize {
        if sp.svds_sparse(a, csc, k, d, u, v) != ok { os.exit(6) }
        sp.svd_sign(u, v, m, n, k)
        if part == 1usize { ret sp.wsum(u, m, k) }
        if part == 2usize { ret sp.wsum(v, n, k) }
    }
    if kind == 1usize {
        if sp.eigs_sym_sparse(a, csc, k, wh, sigma, d, u) != ok { os.exit(7) }
        var q = 0usize
        while q < n * k {
            v[q] = 0.0f64
            q += 1usize
        }
        sp.rotate_phase(u, v, n, k)
        if part == 1usize { ret sp.wsum(u, n, k) }
    }
    if kind == 2usize {
        if sp.eigs_sparse(a, csc, k, wh, sigma, d, di, u, v) != ok { os.exit(8) }
        var s2 = 0.0f64
        var q2 = 0usize
        while q2 < k {
            s2 += d[q2] * f64(q2 + 1usize) + 1000.0f64 * di[q2] * f64(q2 + 1usize)
            q2 += 1usize
        }
        if part == 0usize { ret s2 }
        sp.rotate_phase(u, v, n, k)
        if part == 1usize { ret sp.wsum(u, n, k) }
        ret sp.wsum(v, n, k)
    }
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += d[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra_sparse.json")
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
