// e.algo.stat.irlba's irlba against irlba::irlba. tests/oracle/irlba.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R irlba`; the layout is at the top of scripts/r_oracle/groups/irlba.R.

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
    var o = il.default_opts(usize(z[2usize]))
    o.nu = usize(z[3usize])
    o.work = usize(z[4usize])
    o.tol = z[5usize]
    o.svtol = z[5usize]
    o.smallest = z[6usize] != 0.0f64
    o.maxit = usize(z[11usize])
    let x = z[14usize..14usize + m * n]
    if z[7usize] != 0.0f64 { o.center = z[14usize + m * n..14usize + m * n + n] }
    if z[8usize] != 0.0f64 { o.scale = z[14usize + m * n + n..14usize + m * n + 2usize * n] }
    if z[9usize] != 0.0f64 {
        o.has_shift = true
        o.shift = z[10usize]
    }
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[12usize]))
    var res: il.Fit = zero
    let e = il.irlba(a, &g, x, m, n, o, &res)
    if e != ok { os.exit(5) }
    let kind = usize(z[13usize])
    if kind == 0usize { ret wsum(res.d, o.nv) }
    if kind == 1usize { ret wsum(res.u, res.ur * res.nu) }
    if kind == 2usize { ret wsum(res.v, res.vr * res.nv) }
    if kind == 3usize { ret f64(res.iter) }
    ret f64(res.mprod)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/irlba.json")
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
