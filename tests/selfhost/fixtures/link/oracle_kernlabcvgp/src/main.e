// e.algo.stat.kernlabcvgp against kernlab gausspr(cross = k). tests/oracle/kernlabcvgp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabcvgp`; the argument layout is at the top of scripts/r_oracle/groups/kernlabcvgp.R.

use e.algo.rand.r as rr
use e.algo.stat.armld as ld
use e.algo.stat.kernlabclass as cl
use e.algo.stat.kernlabcvgp as cg
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let kc = usize(z[2usize])
    let cross = usize(z[5usize])
    let scaled = z[6usize] != 0.0f64
    var g: rr.Rng = zero
    rr.seed(&g, i64(z[7usize]))
    let (x, e1) = mem.alloc[f64](a, n * p)
    let (cen, e2) = mem.alloc[f64](a, p)
    let (scl, e3) = mem.alloc[f64](a, p)
    let (cls, e4) = mem.alloc[usize](a, n)
    let (y, e5) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
    var i = 0usize
    while i < n * p {
        x[i] = z[8usize + n + i]
        i += 1usize
    }
    if scaled {
        if cl.scale_cols(a, x, n, p, cen, scl) != ok { ret nan }
    }
    if kc > 0usize {
        i = 0usize
        while i < n {
            cls[i] = usize(z[8usize + i]) - 1usize
            i += 1usize
        }
        let (r, e) = cg.cv_class(a, &g, x, n, p, cls, kc, 0usize, z[3usize], 0.0005f64, cross)
        if e != ok { ret nan }
        ret r
    }
    i = 0usize
    while i < n {
        y[i] = z[8usize + i]
        i += 1usize
    }
    var ysc = 1.0f64
    let m = ld.colmean_ld(y[0usize..n])
    let (sq, e6) = mem.alloc[f64](a, n)
    if e6 != ok { ret nan }
    i = 0usize
    while i < n {
        sq[i] = (y[i] - m) * (y[i] - m)
        i += 1usize
    }
    ysc = math.sqrt[f64](ld.sum_ld(sq[0usize..n]) / f64(n - 1usize))
    i = 0usize
    while i < n {
        y[i] = (y[i] - m) / ysc
        i += 1usize
    }
    let (r, e) = cg.cv_reg(a, &g, x, n, p, y, 0usize, z[3usize], z[4usize], cross, ysc)
    if e != ok { ret nan }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabcvgp.json")
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
