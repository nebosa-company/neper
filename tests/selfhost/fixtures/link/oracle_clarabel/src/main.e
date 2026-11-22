// e.algo.stat.clarabelpkg against clarabel's clarabel(). tests/oracle/clarabel.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clarabel`; the layout is at the top of scripts/r_oracle/groups/clarabel.R.

use e.algo.stat.clarabelpkg as cl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let m = usize(z[1usize])
    let sl = usize(z[2usize])
    var o = 3usize
    let p = z[o..o + n * n]
    o += n * n
    let q = z[o..o + n]
    o += n
    let am = z[o..o + m * n]
    o += m * n
    let b = z[o..o + m]
    o += m
    let spec = z[o..o + sl]
    let (x, e1) = mem.alloc[f64](a, n)
    let (s, e2) = mem.alloc[f64](a, m)
    let (y, e3) = mem.alloc[f64](a, m)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    let r = cl.solve(a, n, m, p, q, am, b, spec, x, s, y)
    let k = c.name
    if str.eq(k, "status") { ret f64(r.status) }
    if str.eq(k, "obj") { ret r.obj }
    var sum = 0.0f64
    var i = 0usize
    if str.eq(k, "x") {
        while i < n {
            sum += x[i] * f64(i + 1usize)
            i += 1usize
        }
    }
    if str.eq(k, "s") {
        while i < m {
            sum += s[i] * f64(i + 1usize)
            i += 1usize
        }
    }
    if str.eq(k, "z") {
        while i < m {
            sum += y[i] * f64(i + 1usize)
            i += 1usize
        }
    }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clarabel.json")
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
            if failures <= 400usize {
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
