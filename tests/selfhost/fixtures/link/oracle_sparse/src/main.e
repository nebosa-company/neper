// e.algo.linalg.sparse against R's Matrix: A %*% B, t(A) %*% B, crossprod(A) by the sparse
// product, chol(A) (natural order) and solve(A, b) for a symmetric positive-definite A.
// tests/oracle/sparse.json comes from `Rscript scripts/r_oracle/generate.R sparse`; the layout is
// at the top of scripts/r_oracle/groups/sparse.R.

use e.algo.linalg.sparse as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pick(r: []const f64, c: *const oracle.Case, wants_len: bool) -> f64 {
    if wants_len { ret f64(r.len) }
    let i = usize(c.args[c.args.len - 1usize])
    if i < r.len { ret r[i] }
    ret 0.0f64 / 0.0f64
}

fn to_usize(a: *mem.Arena, x: []const f64) -> []usize {
    let (r, e) = mem.alloc[usize](a, x.len + 1usize)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < x.len {
        r[i] = usize(x[i])
        i += 1usize
    }
    ret r[0usize..x.len]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    var name = c.name
    var wants_len = false
    if name.len > 4usize && name[0usize] == 108u8 && name[1usize] == 101u8 && name[2usize] == 110u8 && name[3usize] == 58u8 {
        name = name[4usize..name.len]
        wants_len = true
    } else if name.len > 2usize && name[1usize] == 58u8 {
        name = name[2usize..name.len]
    }
    let x = c.args
    let nr = usize(x[0usize])
    let nc = usize(x[1usize])
    let nnz = usize(x[2usize])
    let (m, me) = sp.from_triplets(a, nr, nc, to_usize(a, x[3usize..3usize + nnz]), to_usize(a, x[3usize + nnz..3usize + 2usize * nnz]), x[3usize + 2usize * nnz..3usize + 3usize * nnz])
    if me != ok { os.exit(6) }
    let k = usize(x[3usize + 3usize * nnz])
    var rows_b = nr
    if str.eq(name, "sp_mult") { rows_b = nc }
    var count_b = rows_b * k
    if str.eq(name, "sp_cross") || str.eq(name, "sp_chol") { count_b = 0usize }
    if str.eq(name, "sp_chol") { count_b = nr * k }
    let b = x[4usize + 3usize * nnz..4usize + 3usize * nnz + count_b]
    if str.eq(name, "sp_mult") {
        let (r, e) = sp.multiply_dense(a, m, b, k)
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "sp_tmult") {
        let (t, te) = sp.transpose(a, m)
        if te != ok { os.exit(7) }
        let (r, e) = sp.multiply_dense(a, t, b, k)
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    if str.eq(name, "sp_cross") {
        let (t, te) = sp.transpose(a, m)
        if te != ok { os.exit(7) }
        let (p, pe) = sp.multiply(a, t, m)
        if pe != ok { os.exit(8) }
        let (d, de) = mem.alloc[f64](a, p.nrow * p.ncol + 1usize)
        if de != ok { os.exit(5) }
        var i = 0usize
        while i < p.nrow * p.ncol {
            d[i] = 0.0f64
            i += 1usize
        }
        var col = 0usize
        while col < p.ncol {
            var q = p.colptr[col]
            while q < p.colptr[col + 1usize] {
                d[col * p.nrow + p.rowidx[q]] = p.val[q]
                q += 1usize
            }
            col += 1usize
        }
        ret pick(d[0usize..p.nrow * p.ncol], c, wants_len)
    }
    let (l, le) = sp.cholesky(a, m)
    if le != ok { os.exit(9) }
    if str.eq(name, "sp_chol") {
        let (r, e) = sp.upper_dense(a, l)
        if e != ok { os.exit(7) }
        ret pick(r, c, wants_len)
    }
    let (r, e) = sp.cholesky_solve(a, l, b, k)
    if e != ok { os.exit(7) }
    ret pick(r, c, wants_len)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sparse.json")
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
            if failures <= 20usize {
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
