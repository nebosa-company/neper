// e.algo.stat.irlba's irlba on a sparse input against irlba::irlba. tests/oracle/spectra_irlba_sp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_irlba_sp`; the layout is at the top of scripts/r_oracle/groups/spectra_irlba_sp.R.

use e.algo.rand.r as rr
use e.algo.linalg.sparse as sparse
use e.algo.stat.irlba as il
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

fn wsum(v: []f64, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    var o = il.default_opts(usize(z[2usize]))
    o.work = usize(z[3usize])
    o.tol = 1.0e-12f64
    o.svtol = 1.0e-12f64
    o.maxit = 5000usize
    o.smallest = z[4usize] != 0.0f64
    let nnz = usize(z[7usize])
    let (ti, e0) = mem.alloc[usize](a, nnz)
    let (tj, e1) = mem.alloc[usize](a, nnz)
    let (x, e2) = mem.alloc[f64](a, m * n)
    if e0 != ok || e1 != ok || e2 != ok { os.exit(4) }
    var t = 0usize
    while t < nnz {
        ti[t] = usize(z[8usize + t])
        tj[t] = usize(z[8usize + nnz + t])
        t += 1usize
    }
    let (csc, e3) = sparse.from_triplets(a, m, n, ti, tj, z[8usize + 2usize * nnz..8usize + 3usize * nnz])
    if e3 != ok { os.exit(5) }
    t = 0usize
    while t < m * n {
        x[t] = 0.0f64
        t += 1usize
    }
    var cl = 0usize
    while cl < n {
        var p = csc.colptr[cl]
        while p < csc.colptr[cl + 1usize] {
            x[cl * m + csc.rowidx[p]] = csc.val[p]
            p += 1usize
        }
        cl += 1usize
    }
    let ex = 8usize + 3usize * nnz
    if z[ex] != 0.0f64 { o.center = z[ex + 2usize..ex + 2usize + n] }
    if z[ex + 1usize] != 0.0f64 { o.scale = z[ex + 2usize + n..ex + 2usize + 2usize * n] }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[5usize]))
    var res: il.Fit = zero
    let e = il.irlba(a, &g, x, m, n, o, &res)
    if e != ok { os.exit(6) }
    let kind = usize(z[6usize])
    if kind == 0usize { ret wsum(res.d, o.nv) }
    // the sign of each column that makes the largest component of u positive, applied to v too
    var jc = 0usize
    while jc < o.nv {
        var best = 0.0f64
        var sg = 1.0f64
        var q = 0usize
        while q < res.ur {
            let u0 = res.u[jc * res.ur + q]
            if math.abs[f64](u0) > best {
                best = math.abs[f64](u0)
                sg = 1.0f64
                if u0 < 0.0f64 { sg = -1.0f64 }
            }
            q += 1usize
        }
        q = 0usize
        while q < res.ur {
            res.u[jc * res.ur + q] = res.u[jc * res.ur + q] * sg
            q += 1usize
        }
        q = 0usize
        while q < res.vr {
            res.v[jc * res.vr + q] = res.v[jc * res.vr + q] * sg
            q += 1usize
        }
        jc += 1usize
    }
    if kind == 1usize { ret wsum(res.u, res.ur * res.nu) }
    ret wsum(res.v, res.vr * res.nv)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra_irlba_sp.json")
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
