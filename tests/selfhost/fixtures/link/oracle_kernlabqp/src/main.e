// e.algo.stat.kernlabqp against kernlab ipop. tests/oracle/kernlabqp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R kernlabqp`; the argument layout is at the top of scripts/r_oracle/groups/kernlabqp.R.

use e.algo.stat.kernlabqp as qp
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
    let m = usize(z[1usize])
    let cc = z[6usize..6usize + n]
    let l = z[6usize + n..6usize + 2usize * n]
    let u = z[6usize + 2usize * n..6usize + 3usize * n]
    let r = z[6usize + 3usize * n..6usize + 3usize * n + m]
    let b = z[6usize + 3usize * n + m..6usize + 3usize * n + 2usize * m]
    let h = z[6usize + 3usize * n + 2usize * m..6usize + 3usize * n + 2usize * m + n * n]
    let am = z[6usize + 3usize * n + 2usize * m + n * n..6usize + 3usize * n + 2usize * m + n * n + m * n]
    let (xo, e1) = mem.alloc[f64](a, n)
    let (yo, e2) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok { ret nan }
    let (sg, it, e) = qp.ipop(a, cc, h, am, b, l, u, r, n, m, z[2usize], usize(z[3usize]), z[4usize], z[5usize], xo, yo)
    if e != ok { ret nan }
    var src = xo
    if str.eq(c.name, "dual") { src = yo }
    var s = 0.0f64
    var i = 0usize
    while i < src.len {
        s += src[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/kernlabqp.json")
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
