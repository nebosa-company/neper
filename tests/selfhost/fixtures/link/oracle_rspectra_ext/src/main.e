// e.algo.stat.rspectra svds (nu, nv below k) and eigs_sym (retvec = FALSE) against RSpectra. tests/oracle/rspectra_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rspectra_ext`; the layout is at the top of scripts/r_oracle/groups/rspectra_ext.R.

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
    let mode = usize(z[0usize])
    if mode == 0usize {
        let n = usize(z[1usize])
        let k = usize(z[2usize])
        var out: rs.EigsOut = zero
        let e = rs.eigs_sym(a, z[7usize..7usize + n * n], n, k, usize(z[3usize]), z[4usize] != 0.0f64, z[5usize], 0usize, 0.0f64, 0usize, z[7usize..7usize], &out)
        if e != ok { os.exit(5) }
        let kind = usize(z[6usize])
        if kind == 0usize { ret wsum(out.vals, out.nconv) }
        if kind == 1usize { ret wsum_abs(out.vecs, n, out.nconv) }
        if kind == 2usize { ret f64(out.niter) }
        ret f64(out.nops)
    }
    if mode == 2usize {
        let m = usize(z[1usize])
        let n = usize(z[2usize])
        let k = usize(z[3usize])
        let nu = usize(z[4usize])
        let nv = usize(z[5usize])
        var out: rs.SvdsOut = zero
        let e = rs.svds(a, z[7usize..7usize + m * n], m, n, k, nu, nv, 0usize, 0.0f64, 0usize, z[7usize..7usize], z[7usize..7usize], &out)
        if e != ok { os.exit(7) }
        let kind = usize(z[6usize])
        if kind == 0usize { ret wsum(out.d, out.nconv) }
        if kind == 1usize { ret wsum_abs(out.u, m, nu) }
        if kind == 2usize { ret wsum_abs(out.v, n, nv) }
        if kind == 3usize { ret f64(out.niter) }
        if kind == 4usize { ret f64(out.nops) }
        if kind == 5usize { ret f64(out.u.len) }
        ret f64(out.v.len)
    }
    if mode == 3usize {
        let n = usize(z[1usize])
        let k = usize(z[2usize])
        var out: rs.EigsOut = zero
        let e = rs.eigs_sym(a, z[5usize..5usize + n * n], n, k, usize(z[3usize]), false, 0.0f64, 0usize, 0.0f64, 0usize, z[5usize..5usize], &out)
        if e != ok { os.exit(8) }
        let kind = usize(z[4usize])
        if kind == 0usize { ret wsum(out.vals, out.nconv) }
        if kind == 1usize { ret f64(out.niter) }
        ret f64(out.nops)
    }
    let m = usize(z[1usize])
    let n = usize(z[2usize])
    let k = usize(z[3usize])
    var ctr: []const f64 = z[7usize..7usize]
    var scl: []const f64 = z[7usize..7usize]
    if z[4usize] != 0.0f64 { ctr = z[7usize + m * n..7usize + m * n + n] }
    if z[5usize] != 0.0f64 { scl = z[7usize + m * n + n..7usize + m * n + 2usize * n] }
    var out: rs.SvdsOut = zero
    let e = rs.svds(a, z[7usize..7usize + m * n], m, n, k, k, k, 0usize, 0.0f64, 0usize, ctr, scl, &out)
    if e != ok { os.exit(6) }
    let kind = usize(z[6usize])
    if kind == 0usize { ret wsum(out.d, out.nconv) }
    if kind == 1usize { ret wsum_abs(out.u, m, k) }
    if kind == 2usize { ret wsum_abs(out.v, n, k) }
    if kind == 3usize { ret f64(out.niter) }
    ret f64(out.nops)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rspectra_ext.json")
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
