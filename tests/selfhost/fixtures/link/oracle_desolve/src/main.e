// e.math.ode (euler and rk4) against deSolve. tests/oracle/desolve.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R desolve`; the layout is at the top of scripts/r_oracle/groups/desolve.R.

use e.io
use e.math.ode as ode
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Sys = struct { id: usize, ne: usize, et: [12]f64, ev: [12]usize, em: [12]usize, evl: [12]f64, ng: usize, ridx: [2]usize, rlev: [2]f64, evv: usize, eva: f64, evb: f64 }

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
    if c.id == 4usize {
        d[0usize] = y[1usize]
        d[1usize] = 50.0f64 * (1.0f64 - y[0usize] * y[0usize]) * y[1usize] - y[0usize]
    }
    if c.id == 5usize {
        d[0usize] = 0.0f64 - 0.04f64 * y[0usize] + 10000.0f64 * y[1usize] * y[2usize]
        d[1usize] = 0.04f64 * y[0usize] - 10000.0f64 * y[1usize] * y[2usize] - 30000000.0f64 * (y[1usize] * y[1usize])
        d[2usize] = 30000000.0f64 * (y[1usize] * y[1usize])
    }
    if c.id == 3usize {
        d[0usize] = y[1usize]
        d[1usize] = 0.0f64 - 4.0f64 * y[0usize] - 0.2f64 * y[1usize]
    }
}

// Data-frame events: every row whose time equals t applies (1 replace, 2 add, 3 multiply).
fn apply_events(c: *Sys, t: f64, y: []f64) {
    var k = 0usize
    while k < c.ne {
        if c.et[k] == t {
            let v = c.ev[k]
            if c.em[k] == 1usize { y[v] = c.evl[k] }
            if c.em[k] == 2usize { y[v] = y[v] + c.evl[k] }
            if c.em[k] == 3usize { y[v] = y[v] * c.evl[k] }
        }
        k += 1usize
    }
}

fn root_g(c: *Sys, t: f64, y: []const f64, d: []f64) {
    var k = 0usize
    while k < c.ng {
        d[k] = y[c.ridx[k]] - c.rlev[k]
        k += 1usize
    }
}

fn root_event(c: *Sys, t: f64, y: []f64) {
    y[c.evv] = c.eva * y[c.evv] + c.evb
}

// Root case: args (system, rtol, atol, nt, times[nt], y0[n], mode, ng, (idx, level) x ng, evvar, eva, evb);
// the case name picks the statistic: lsodar_rows, _troot, _ind, _nroot, _val.
fn answer_root(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var sys: Sys = zero
    sys.id = usize(x[0usize])
    var n = 2usize
    if sys.id == 1usize { n = 3usize }
    if sys.id == 2usize { n = 1usize }
    let nt = usize(x[3usize])
    let times = x[4usize..4usize + nt]
    var y: [3]f64 = zero
    var i = 0usize
    while i < n {
        y[i] = x[4usize + nt + i]
        i += 1usize
    }
    var at0 = 4usize + nt + n
    let mode = usize(x[at0])
    sys.ng = usize(x[at0 + 1usize])
    at0 += 2usize
    var k = 0usize
    while k < sys.ng {
        sys.ridx[k] = usize(x[at0]) - 1usize
        sys.rlev[k] = x[at0 + 1usize]
        at0 += 2usize
        k += 1usize
    }
    sys.evv = usize(x[at0]) - 1usize
    sys.eva = x[at0 + 1usize]
    sys.evb = x[at0 + 2usize]
    var rr: ode.RootRec = zero
    var out: [160]f64 = zero
    var term = 0usize
    if mode == 2usize { term = 2usize }
    let e = ode.lsodar_solve[Sys](a, &sys, rhs, root_g, sys.ng, mode > 0usize, term, root_event, times, y[0usize..n], x[1usize], x[2usize], 0.0f64, 0.0f64, 0.0f64, 5000usize, 12usize, 5usize, &rr, out[0usize..160usize])
    if e != ok { os.exit(9) }
    var r = 0.0f64
    if str.eq(c.name, "lsodar_rows") {
        var row = 0usize
        while row < rr.rows {
            i = 0usize
            while i < n {
                r += f64(row + 1usize) * f64(i + 1usize) * out[row + nt * (1usize + i)]
                i += 1usize
            }
            row += 1usize
        }
    }
    if str.eq(c.name, "lsodar_nroot") { r = f64(rr.nroot) }
    k = 0usize
    while k < rr.nroot && k < 100usize {
        if str.eq(c.name, "lsodar_troot") { r += f64(k + 1usize) * rr.troot[k] }
        if str.eq(c.name, "lsodar_ind") {
            if mode == 0usize { r = f64(rr.ind[k]) } else { r += f64(k + 1usize) * f64(rr.ind[k]) }
        }
        if str.eq(c.name, "lsodar_val") && mode > 0usize {
            i = 0usize
            while i < n {
                r += f64(k + 1usize) * f64(i + 1usize) * rr.val[k * 3usize + i]
                i += 1usize
            }
        }
        k += 1usize
    }
    ret r
}

// Event case: args (system, rtol, atol, hmax, nt, times[nt], y0[n], ne, (time, var, method, value) x ne).
fn answer_ev(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var sys: Sys = zero
    sys.id = usize(x[0usize])
    var n = 2usize
    if sys.id == 1usize { n = 3usize }
    if sys.id == 2usize { n = 1usize }
    let nt = usize(x[4usize])
    let times = x[5usize..5usize + nt]
    var y: [3]f64 = zero
    var i = 0usize
    while i < n {
        y[i] = x[5usize + nt + i]
        i += 1usize
    }
    let at0 = 5usize + nt + n
    sys.ne = usize(x[at0])
    var uniq: [12]f64 = zero
    var nu = 0usize
    var k = 0usize
    while k < sys.ne {
        let b = at0 + 1usize + 4usize * k
        sys.et[k] = x[b]
        sys.ev[k] = usize(x[b + 1usize]) - 1usize
        sys.em[k] = usize(x[b + 2usize])
        sys.evl[k] = x[b + 3usize]
        if nu == 0usize || uniq[nu - 1usize] != x[b] {
            uniq[nu] = x[b]
            nu += 1usize
        }
        k += 1usize
    }
    var out: [160]f64 = zero
    var e = ok
    if str.eq(c.name, "lsoda_ev") {
        e = ode.lsoda_event_solve[Sys](a, &sys, rhs, times, y[0usize..n], x[1usize], x[2usize], 0.0f64, x[3usize], 0.0f64, 5000usize, 12usize, 5usize, uniq[0usize..nu], apply_events, out[0usize..160usize])
    } else {
        if str.eq(c.name, "vode_ev") {
            e = ode.vode_event_solve[Sys](a, &sys, rhs, times, y[0usize..n], x[1usize], x[2usize], 0.0f64, x[3usize], 0.0f64, 5000usize, false, 0usize, uniq[0usize..nu], apply_events, out[0usize..160usize])
        } else {
            e = ode.lsode_event_solve[Sys](a, &sys, rhs, times, y[0usize..n], x[1usize], x[2usize], 0.0f64, x[3usize], 0.0f64, 5000usize, str.eq(c.name, "adams_ev"), uniq[0usize..nu], apply_events, out[0usize..160usize])
        }
    }
    if e != ok {
        os.exit(8)
    }
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

fn rk_method_id(name: str) -> usize {
    if str.eq(name, "ode23") { ret 0usize }
    if str.eq(name, "ode45") { ret 1usize }
    if str.eq(name, "rkf45") { ret 2usize }
    if str.eq(name, "rk45ck") { ret 3usize }
    if str.eq(name, "rk45dp6") { ret 4usize }
    if str.eq(name, "rk45e") { ret 5usize }
    if str.eq(name, "rk23") { ret 6usize }
    if str.eq(name, "rk34f") { ret 7usize }
    ret 99usize
}

// Adaptive rk case: args (system, rtol, atol, nt, times[nt], y0...).
fn answer_rk(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var sys: Sys = zero
    sys.id = usize(x[0usize])
    var n = 2usize
    if sys.id == 1usize { n = 3usize }
    if sys.id == 2usize { n = 1usize }
    if sys.id == 5usize { n = 3usize }
    let rtol = x[1usize]
    let atol = x[2usize]
    let nt = usize(x[3usize])
    var y: [3]f64 = zero
    var rt: [3]f64 = zero
    var at: [3]f64 = zero
    var i = 0usize
    while i < n {
        y[i] = x[4usize + nt + i]
        rt[i] = rtol
        at[i] = atol
        i += 1usize
    }
    var out: [64]f64 = zero
    var scratch: [160]f64 = zero
    let times = x[4usize..4usize + nt]
    var e = ok
    if str.eq(c.name, "lsoda") {
        e = ode.lsoda_solve[Sys](a, &sys, rhs, times, y[0usize..n], rtol, atol, 0.0f64, 0.0f64, 0.0f64, 5000usize, 12usize, 5usize, out[0usize..64usize])
    } else if str.eq(c.name, "lsode") || str.eq(c.name, "bdf") {
        e = ode.lsode_solve[Sys](a, &sys, rhs, times, y[0usize..n], rtol, atol, 0.0f64, 0.0f64, 0.0f64, 5000usize, false, 0usize, out[0usize..64usize])
    } else if str.eq(c.name, "adams") {
        e = ode.lsode_solve[Sys](a, &sys, rhs, times, y[0usize..n], rtol, atol, 0.0f64, 0.0f64, 0.0f64, 5000usize, true, 0usize, out[0usize..64usize])
    } else {
        e = ode.rk_solve[Sys](&sys, rhs, rk_method_id(c.name), times, y[0usize..n], rt[0usize..n], at[0usize..n], 0.0f64, 0.0f64, 0.0f64 - 1.0f64, 0.0f64 - 1.0f64, 5000usize * nt, out[0usize..64usize], scratch[0usize..160usize])
    }
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

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "lsodar_rows") || str.eq(c.name, "lsodar_troot") || str.eq(c.name, "lsodar_ind") || str.eq(c.name, "lsodar_nroot") || str.eq(c.name, "lsodar_val") { ret answer_root(a, c) }
    if str.eq(c.name, "lsoda_ev") || str.eq(c.name, "lsode_ev") || str.eq(c.name, "adams_ev") || str.eq(c.name, "vode_ev") { ret answer_ev(a, c) }
    if !str.eq(c.name, "euler") && !str.eq(c.name, "rk4") { ret answer_rk(a, c) }
    let x = c.args
    var sys: Sys = zero
    sys.id = usize(x[0usize])
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
