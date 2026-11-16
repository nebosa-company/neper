// e.algo.stat.minpacklm against minpack.lm::nls.lm (numerical Jacobian). tests/oracle/minpacklm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R minpacklm`; the layout is at the top of
// scripts/r_oracle/groups/minpacklm.R.

use e.algo.stat.minpacklm as ml
use e.io
use e.math
use e.mem
use e.os
use e.test.oracle as oracle

type Data = struct { id: usize, t: []const f64, y: []const f64 }

fn resid(d: *Data, p: []const f64, out: []f64) {
    var i = 0usize
    while i < d.t.len {
        var v = 0.0f64
        if d.id == 0usize { v = p[0usize] * math.exp[f64](0.0f64 - p[1usize] * d.t[i]) + p[2usize] }
        if d.id == 1usize { v = p[0usize] * d.t[i] / (p[1usize] + d.t[i]) }
        if d.id == 2usize { v = p[0usize] / (1.0f64 + math.exp[f64](0.0f64 - (d.t[i] - p[1usize]) / p[2usize])) }
        out[i] = d.y[i] - v
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let id = usize(z[0usize])
    let n = usize(z[1usize])
    let np = usize(z[2usize])
    var d = Data { id: id, t: z[3usize..3usize + n], y: z[3usize + n..3usize + 2usize * n] }
    let (x, e1) = mem.alloc[f64](a, np)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var i = 0usize
    while i < np {
        x[i] = z[3usize + 2usize * n + i]
        i += 1usize
    }
    let lo = z[3usize + 2usize * n + np..3usize + 2usize * n + 2usize * np]
    let hi = z[3usize + 2usize * n + 2usize * np..3usize + 2usize * n + 3usize * np]
    let q = usize(z[3usize + 2usize * n + 3usize * np])
    let sq = 1.4901161193847656e-8f64
    let (fit, e) = ml.nls_lm[Data](a, resid, &d, n, np, x, lo, hi, sq, sq, 0.0f64, i64(100usize * (np + 1usize)), 50i64)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if q < np { ret x[q] }
    if q == np { ret fit.deviance }
    if q == np + 1usize { ret f64(fit.info) }
    ret f64(fit.niter)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/minpacklm.json")
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
