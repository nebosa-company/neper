// e.algo.stat.mlbench against mlbench: eight generators under set.seed, compared by sums of x and y.
// tests/oracle/mlbench.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mlbench`;
// the layout is at the top of scripts/r_oracle/groups/mlbench.R.

use e.algo.rand.r as rr
use e.algo.stat.mlbench as ml
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[1usize]))
    let kind = u8(x[0usize])
    let n = usize(x[2usize])
    let d = usize(x[3usize])
    var dt: ml.Data = zero
    var e = ok
    if kind == 0u8 { let (r, re) = ml.friedman1(a, &g, n, x[4usize])
        dt = r
        e = re }
    if kind == 1u8 || kind == 2u8 { let (r, re) = ml.friedman23(a, &g, n, x[4usize], kind + 1u8)
        dt = r
        e = re }
    if kind == 3u8 { let (r, re) = ml.normals2d(a, &g, n, d, x[4usize], 1.0f64)
        dt = r
        e = re }
    if kind == 4u8 { let (r, re) = ml.circle_xor(a, &g, n, d, 0u8)
        dt = r
        e = re }
    if kind == 5u8 { let (r, re) = ml.circle_xor(a, &g, n, d, 1u8)
        dt = r
        e = re }
    if kind == 6u8 { let (r, re) = ml.twonorm_ringnorm(a, &g, n, d, 0u8)
        dt = r
        e = re }
    if kind == 7u8 { let (r, re) = ml.twonorm_ringnorm(a, &g, n, d, 1u8)
        dt = r
        e = re }
    if e != ok { os.exit(6) }
    var v = dt.y
    if str.eq(c.name, "x") { v = dt.x }
    let which = u8(x[x.len - 1usize])
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if which == 0u8 { s += v[i] }
        if which == 1u8 { s += f64(i + 1usize) * v[i] }
        if which == 2u8 { s += v[i] * v[i] }
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mlbench.json")
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
