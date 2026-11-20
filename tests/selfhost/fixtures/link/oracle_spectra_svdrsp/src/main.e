// e.algo.stat.spectrapkg's svdr_sparse against irlba::svdr on a dgCMatrix. tests/oracle/spectra_svdrsp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_svdrsp`; the layout is at the top of scripts/r_oracle/groups/spectra_svdrsp.R.

use e.algo.linalg.sparse as sparse
use e.algo.rand.r as rr
use e.algo.stat.spectrapkg as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let ex = usize(z[3usize])
    let nnz = usize(z[6usize])
    let (d, e1) = mem.alloc[f64](a, k)
    let (ti, e2) = mem.alloc[usize](a, nnz)
    let (tj, e3) = mem.alloc[usize](a, nnz)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    var t = 0usize
    while t < nnz {
        ti[t] = usize(z[7usize + t])
        tj[t] = usize(z[7usize + nnz + t])
        t += 1usize
    }
    let (csc, e4) = sparse.from_triplets(a, m, n, ti, tj, z[7usize + 2usize * nnz..7usize + 3usize * nnz])
    if e4 != ok { os.exit(5) }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[4usize]))
    let (iters, e) = sp.svdr_sparse(a, &g, csc, k, ex, 1.0e-5f64, 100usize, d)
    let _ = iters
    if e != ok { os.exit(6) }
    ret d[usize(z[5usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra_svdrsp.json")
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
