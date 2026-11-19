// e.algo.stat.irlba with the deflation form of v against irlba::irlba(x, k, v = fit). tests/oracle/irlba_defl.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R irlba_defl`; the layout is at the top of scripts/r_oracle/groups/irlba_defl.R.

use e.algo.rand.r as rr
use e.algo.stat.irlba as il
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let x = z[8usize..8usize + m * n]
    var o1 = il.default_opts(usize(z[2usize]))
    o1.smallest = z[4usize] != 0.0f64
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[5usize]))
    var f1: il.Fit = zero
    let e1 = il.irlba(a, &g, x, m, n, o1, &f1)
    if e1 != ok { os.exit(5) }
    var o2 = il.default_opts(usize(z[3usize]))
    o2.smallest = z[4usize] != 0.0f64
    o2.du = f1.u
    o2.dv = f1.v
    o2.dd = f1.d
    rr.seed(&g, i64(z[6usize]))
    var r: il.Fit = zero
    let e2 = il.irlba(a, &g, x, m, n, o2, &r)
    if e2 != ok { os.exit(6) }
    let kind = usize(z[7usize])
    if kind == 0usize { ret wsum(r.d, r.nu) }
    if kind == 1usize { ret wsum(r.u, r.ur * r.nu) }
    if kind == 2usize { ret wsum(r.v, r.vr * r.nv) }
    if kind == 3usize { ret f64(r.iter) }
    ret f64(r.mprod)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/irlba_defl.json")
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
