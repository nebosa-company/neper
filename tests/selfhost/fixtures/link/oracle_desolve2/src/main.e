// e.math.ode, second group (dede) against deSolve. tests/oracle/desolve2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R desolve2`; the layout is at the top of scripts/r_oracle/groups/desolve2.R.

use e.io
use e.math.ode as ode
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Sys = struct { id: usize, tau: f64, h0: [2]f64, hist: *ode.Hist }

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
    if c.id == 2usize { d[0usize] = 0.7f64 * y[0usize] * (1.0f64 - y[0usize] / 10.0f64) }
    if c.id == 3usize {
        d[0usize] = y[1usize]
        d[1usize] = 0.0f64 - 4.0f64 * y[0usize] - 0.2f64 * y[1usize]
    }
    if c.id == 4usize {
        d[0usize] = y[1usize]
        d[1usize] = 50.0f64 * (1.0f64 - y[0usize] * y[0usize]) * y[1usize] - y[0usize]
    }
    if c.id == 5usize || c.id == 6usize {
        d[0usize] = 0.0f64 - 0.04f64 * y[0usize] + 10000.0f64 * y[1usize] * y[2usize]
        d[1usize] = 0.04f64 * y[0usize] - 10000.0f64 * y[1usize] * y[2usize] - 30000000.0f64 * (y[1usize] * y[1usize])
        d[2usize] = 30000000.0f64 * (y[1usize] * y[1usize])
        if c.id == 6usize { d[2usize] = y[0usize] + y[1usize] + y[2usize] - 1.0f64 }
    }
    if c.id == 7usize {
        d[0usize] = 0.0f64 - y[0usize] + y[1usize] * y[1usize]
        d[1usize] = 1.0f64 - y[0usize] * y[0usize] - y[1usize]
    }
    var yt = c.h0[0usize]
    if c.id >= 10usize && t >= c.tau { yt = ode.hist_past(c.hist, t - c.tau, 0usize, false) }
    if c.id == 10usize { d[0usize] = 1.5f64 * y[0usize] * (1.0f64 - yt / 2.0f64) }
    if c.id == 11usize {
        d[0usize] = 0.2f64 * yt / (1.0f64 + ode.dd_pow(yt, 10.0f64)) - 0.1f64 * y[0usize]
    }
    if c.id == 12usize {
        var l0 = c.h0[0usize]
        var l1 = c.h0[1usize]
        var dl1 = 0.0f64
        if t >= c.tau {
            l0 = yt
            l1 = ode.hist_past(c.hist, t - c.tau, 1usize, false)
            dl1 = ode.hist_past(c.hist, t - c.tau, 1usize, true)
        }
        d[0usize] = 0.0f64 - y[0usize] + 0.5f64 * l0 - 0.2f64 * dl1
        d[1usize] = y[0usize] - 0.5f64 * y[1usize] + 0.3f64 * l1
    }
}

// radau case: args (system, rtol, atol, nt, times[nt], y0...); systems 6 and 7 carry a mass matrix.
fn answer_radau(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var sys: Sys = zero
    sys.id = usize(x[0usize])
    var n = 2usize
    if sys.id == 1usize || sys.id == 5usize || sys.id == 6usize { n = 3usize }
    if sys.id == 2usize { n = 1usize }
    let nt = usize(x[3usize])
    let times = x[4usize..4usize + nt]
    var y: [3]f64 = zero
    var i = 0usize
    while i < n {
        y[i] = x[4usize + nt + i]
        i += 1usize
    }
    var mass: [9]f64 = zero
    var nm = 0usize
    if sys.id == 6usize {
        mass[0usize] = 1.0f64
        mass[4usize] = 1.0f64
        nm = 9usize
    }
    if sys.id == 7usize {
        mass[0usize] = 1.0f64
        nm = 4usize
    }
    var out: [40]f64 = zero
    var e = ok
    if str.eq(c.name, "radau") {
        e = ode.radau_solve[Sys](a, &sys, rhs, times, y[0usize..n], x[1usize], x[2usize], 0.0f64, 0.0f64, 5000usize * nt, mass[0usize..nm], out[0usize..40usize])
    } else {
        e = ode.vode_solve[Sys](a, &sys, rhs, times, y[0usize..n], x[1usize], x[2usize], 0.0f64, 0.0f64, 0.0f64, 5000usize, str.eq(c.name, "vode10"), 0usize, out[0usize..40usize])
    }
    if e != ok { os.exit(6) }
    var r = 0.0f64
    var row = 0usize
    while row < nt {
        i = 0usize
        while i < n {
            r += f64(row + 1usize) * f64(i + 1usize) * out[row + nt * (1usize + i)]
            i += 1usize
        }
        row += 1usize
    }
    ret r
}

// DAE residual y' - f(y); the algebraic rows of the index-1 systems are 0 = f.
fn dres(c: *Sys, t: f64, y: []const f64, yp: []const f64, d: []f64) {
    var f: [3]f64 = zero
    rhs(c, t, y, f[0usize..3usize])
    var n = 2usize
    if c.id == 1usize || c.id == 5usize || c.id == 6usize { n = 3usize }
    if c.id == 2usize { n = 1usize }
    var i = 0usize
    while i < n {
        d[i] = yp[i] - f[i]
        i += 1usize
    }
    if c.id == 6usize { d[2usize] = f[2usize] }
    if c.id == 7usize { d[1usize] = f[1usize] }
}

// daspk case: args (system, rtol, atol, nt, times[nt], y0[n], dy0[n]).
fn answer_daspk(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var sys: Sys = zero
    sys.id = usize(x[0usize])
    var n = 2usize
    if sys.id == 1usize || sys.id == 5usize || sys.id == 6usize { n = 3usize }
    if sys.id == 2usize { n = 1usize }
    let nt = usize(x[3usize])
    let times = x[4usize..4usize + nt]
    let y = x[4usize + nt..4usize + nt + n]
    let dy = x[4usize + nt + n..4usize + nt + 2usize * n]
    var out: [40]f64 = zero
    let e = ode.daspk_solve[Sys](a, &sys, dres, times, y, dy, x[1usize], x[2usize], 0.0f64, 0.0f64, 5usize, 5000usize, out[0usize..40usize])
    if e != ok {
        let _ = io.print(oracle.describe(a, c, 0.0f64))
        os.exit(56)
    }
    var r = 0.0f64
    var row = 0usize
    while row < nt {
        var i = 0usize
        while i < n {
            r += f64(row + 1usize) * f64(i + 1usize) * out[row + nt * (1usize + i)]
            i += 1usize
        }
        row += 1usize
    }
    ret r
}

// dede case: args (system, rtol, atol, tau, nt, times[nt], y0...).
fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "daspk") { ret answer_daspk(a, c) }
    if str.eq(c.name, "radau") || str.eq(c.name, "vode22") || str.eq(c.name, "vode10") { ret answer_radau(a, c) }
    let x = c.args
    var sys: Sys = zero
    sys.id = usize(x[0usize])
    sys.tau = x[3usize]
    var n = 1usize
    if sys.id == 12usize { n = 2usize }
    let nt = usize(x[4usize])
    let times = x[5usize..5usize + nt]
    var y: [2]f64 = zero
    var i = 0usize
    while i < n {
        y[i] = x[5usize + nt + i]
        sys.h0[i] = y[i]
        i += 1usize
    }
    var ht: [4000]f64 = zero
    var hy: [8000]f64 = zero
    var hd: [8000]f64 = zero
    var h: ode.Hist = zero
    h.cap = 4000usize
    h.t = ht[0usize..4000usize]
    h.y = hy[0usize..8000usize]
    h.dy = hd[0usize..8000usize]
    sys.hist = &h
    var out: [40]f64 = zero
    let e = ode.dede_solve[Sys](a, &sys, rhs, &h, times, y[0usize..n], x[1usize], x[2usize], 0.0f64, 0.0f64, 0.0f64, 5000usize, 12usize, 5usize, out[0usize..40usize])
    if e != ok { os.exit(7) }
    var r = 0.0f64
    var row = 0usize
    while row < nt {
        i = 0usize
        while i < n {
            r += f64(row + 1usize) * f64(i + 1usize) * out[row + nt * (1usize + i)]
            i += 1usize
        }
        row += 1usize
    }
    ret r
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/desolve2.json")
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
