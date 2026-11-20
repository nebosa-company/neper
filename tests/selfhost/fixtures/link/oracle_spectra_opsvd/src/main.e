// e.algo.stat.spectrapkg's svds_op against RSpectra::svds with a function operator. tests/oracle/spectra_opsvd.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_opsvd`; the layout is at the top of scripts/r_oracle/groups/spectra_opsvd.R.

use e.algo.stat.spectrapkg as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

type Op = struct { d: []const f64, u: []const f64, w: []const f64, m: usize }

fn apply(c: *Op, x: []const f64, y: []f64) {
    var sw = 0.0f64
    var i = 0usize
    while i < x.len {
        sw += c.w[i] * x[i]
        i += 1usize
    }
    i = 0usize
    while i < c.m {
        var v = c.u[i] * sw
        if i < x.len { v += c.d[i] * x[i] }
        y[i] = v
        i += 1usize
    }
}

fn apply_t(c: *Op, x: []const f64, y: []f64) {
    var su = 0.0f64
    var i = 0usize
    while i < c.m {
        su += c.u[i] * x[i]
        i += 1usize
    }
    i = 0usize
    while i < y.len {
        y[i] = c.d[i] * x[i] + c.w[i] * su
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let part = usize(z[3usize])
    let (vals, e1) = mem.alloc[f64](a, k)
    let (u, e2) = mem.alloc[f64](a, m * k)
    let (v, e3) = mem.alloc[f64](a, n * k)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(4) }
    var op = Op { d: z[4usize..4usize + n], u: z[4usize + n..4usize + n + m], w: z[4usize + n + m..4usize + 2usize * n + m], m: m }
    if sp.svds_op[Op](a, &op, apply, apply_t, m, n, k, vals, u, v) != ok { os.exit(5) }
    sp.svd_sign(u, v, m, n, k)
    if part == 1usize { ret sp.wsum(u, m, k) }
    if part == 2usize { ret sp.wsum(v, n, k) }
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += vals[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra_opsvd.json")
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
