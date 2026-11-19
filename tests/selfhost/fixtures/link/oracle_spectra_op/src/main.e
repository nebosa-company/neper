// e.algo.stat.spectrapkg's eigs_sym_op against RSpectra::eigs_sym with a function operator. tests/oracle/spectra_op.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R spectra_op`; the layout is at the top of scripts/r_oracle/groups/spectra_op.R.

use e.algo.stat.spectrapkg as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

type Op = struct { d: []const f64, u: []const f64, w: []const f64 }

fn apply(c: *Op, x: []const f64, y: []f64) {
    var su = 0.0f64
    var sw = 0.0f64
    var i = 0usize
    while i < x.len {
        su += c.u[i] * x[i]
        sw += c.w[i] * x[i]
        i += 1usize
    }
    i = 0usize
    while i < x.len {
        y[i] = c.d[i] * x[i] + c.u[i] * su + c.w[i] * sw
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let k = usize(z[1usize])
    let wh = usize(z[2usize])
    let (vals, e1) = mem.alloc[f64](a, k)
    if e1 != ok { os.exit(4) }
    var op = Op { d: z[3usize..3usize + n], u: z[3usize + n..3usize + 2usize * n], w: z[3usize + 2usize * n..3usize + 3usize * n] }
    if sp.eigs_sym_op[Op](a, &op, apply, n, k, wh, 0.0f64, vals) != ok { os.exit(5) }
    var s = 0.0f64
    var i = 0usize
    while i < k {
        s += vals[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/spectra_op.json")
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
