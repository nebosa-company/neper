// e.algo.stat.rspectra svds on sparse input with centre and scale against RSpectra. tests/oracle/rspectra_sp.json: layout at the top of scripts/r_oracle/groups/rspectra_sp.R.

use e.algo.stat.rspectra as rs
use e.io
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

// the column-sign-free weighted sum of the r by c column-major v
fn wsum_abs(v: []f64, r: usize, c: usize) -> f64 {
    var s = 0.0f64
    var j = 0usize
    while j < c {
        var t = 0.0f64
        var i = 0usize
        while i < r {
            t += v[j * r + i] * f64(i + 1usize)
            i += 1usize
        }
        if t < 0.0f64 { t = 0.0f64 - t }
        s += t * f64(j + 1usize)
        j += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let kind = usize(z[5usize])
    let nnz = usize(z[6usize])
    let (ti, e0) = mem.alloc[usize](a, nnz)
    let (tj, e1) = mem.alloc[usize](a, nnz)
    if e0 != ok || e1 != ok { os.exit(4) }
    var t = 0usize
    while t < nnz {
        ti[t] = usize(z[7usize + t])
        tj[t] = usize(z[7usize + nnz + t])
        t += 1usize
    }
    let (x, e4) = mem.alloc[f64](a, m * n)
    if e4 != ok { os.exit(7) }
    t = 0usize
    while t < m * n {
        x[t] = 0.0f64
        t += 1usize
    }
    t = 0usize
    while t < nnz {
        x[tj[t] * m + ti[t]] = z[7usize + 2usize * nnz + t]
        t += 1usize
    }
    let ex = 7usize + 3usize * nnz
    var ctr: []const f64 = z[ex..ex]
    var scl: []const f64 = z[ex..ex]
    if z[3usize] != 0.0f64 { ctr = z[ex..ex + n] }
    if z[4usize] != 0.0f64 { scl = z[ex + n..ex + 2usize * n] }
    var out: rs.SvdsOut = zero
    let e = rs.svds(a, x, m, n, k, k, k, 0usize, 0.0f64, 0usize, ctr, scl, &out)
    if e != ok { os.exit(6) }
    if kind == 0usize { ret wsum(out.d, out.nconv) }
    if kind == 1usize { ret wsum_abs(out.u, m, k) }
    if kind == 2usize { ret wsum_abs(out.v, n, k) }
    if kind == 3usize { ret f64(out.niter) }
    ret f64(out.nops)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rspectra_sp.json")
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
