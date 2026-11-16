// e.math.ode (euler and rk4) against deSolve. tests/oracle/desolve.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R desolve`; the layout is at the top of scripts/r_oracle/groups/desolve.R.

use e.io
use e.math.ode as ode
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Sys = struct { id: usize }

fn rhs(c: *Sys, t: f64, y: []const f64, d: []f64) {
    if c.id == 0usize {
        d[0usize] = 1.1f64 * y[0usize] - 0.4f64 * y[0usize] * y[1usize]
        d[1usize] = 0.1f64 * y[0usize] * y[1usize] - 0.4f64 * y[1usize]
    }
    if c.id == 1usize {
        d[0usize] = 10.0f64 * (y[1usize] - y[0usize])
        d[1usize] = y[0usize] * (28.0f64 - y[2usize]) - y[1usize]
        d[2usize] = y[0usize] * y[1usize] - 8.0f64 / 3.0f64 * y[2usize]
    }
    if c.id == 2usize {
        d[0usize] = 0.7f64 * y[0usize] * (1.0f64 - y[0usize] / 10.0f64)
    }
    if c.id == 3usize {
        d[0usize] = y[1usize]
        d[1usize] = 0.0f64 - 4.0f64 * y[0usize] - 0.2f64 * y[1usize]
    }
}

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    var sys = Sys { id: usize(x[0usize]) }
    let h = x[1usize]
    let steps = usize(x[2usize])
    var n = 2usize
    if sys.id == 1usize { n = 3usize }
    if sys.id == 2usize { n = 1usize }
    var y: [3]f64 = zero
    var i = 0usize
    while i < n {
        y[i] = x[3usize + i]
        i += 1usize
    }
    var scratch: [20]f64 = zero
    var t = 0.0f64
    var s = 0usize
    while s < steps {
        if str.eq(c.name, "euler") {
            if ode.euler[Sys](&sys, rhs, t, y[0usize..n], h, scratch[0usize..20usize]) != ok { os.exit(5) }
        } else {
            if ode.rk4[Sys](&sys, rhs, t, y[0usize..n], h, scratch[0usize..20usize]) != ok { os.exit(6) }
        }
        t = t + h
        s += 1usize
    }
    var r = 0.0f64
    i = 0usize
    while i < n {
        r += y[i] * f64(i + 1usize)
        i += 1usize
    }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/desolve.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
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
