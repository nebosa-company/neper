// e.algo.stat.quantreg nlrq and dynrq against quantreg. tests/oracle/quantreg_nl.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R quantreg_nl`; the layout is at the top of
// scripts/r_oracle/groups/quantreg_nl.R.

use e.algo.stat.quantreg as qr
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let v = c.args
    let n = usize(v[0usize])
    let kind = usize(v[1usize])
    let tau = v[2usize]
    let j = usize(v[3usize])
    if kind < 10usize {
        var np = 2usize
        if kind == 1usize { np = 3usize }
        let (pars, pe) = mem.alloc[f64](a, np)
        if pe != ok { ret 0.0f64 / 0.0f64 }
        var k = 0usize
        while k < np {
            pars[k] = v[4usize + k]
            k += 1usize
        }
        if qr.nlrq(a, i64(kind), v[7usize..7usize + n], v[7usize + n..7usize + 2usize * n], tau, pars, 100usize) != ok { ret 0.0f64 / 0.0f64 }
        ret pars[j]
    }
    let (yl, ye) = mem.alloc[usize](a, 2usize)
    let (xl, xe) = mem.alloc[usize](a, 3usize)
    if ye != ok || xe != ok { ret 0.0f64 / 0.0f64 }
    var ny = 0usize
    var nx = 0usize
    var trend = false
    if kind == 10usize {
        yl[0usize] = 1usize
        ny = 1usize
        xl[0usize] = 0usize
        xl[1usize] = 1usize
        xl[2usize] = 2usize
        nx = 3usize
        trend = true
    } else if kind == 11usize {
        yl[0usize] = 1usize
        yl[1usize] = 2usize
        ny = 2usize
        xl[0usize] = 1usize
        nx = 1usize
    } else {
        xl[0usize] = 0usize
        xl[1usize] = 1usize
        nx = 2usize
        trend = true
    }
    let (b, be) = qr.dynrq(a, v[7usize..7usize + n], v[7usize + n..7usize + 2usize * n], yl[0usize..ny], xl[0usize..nx], trend, v[4usize], tau)
    if be != ok { ret 0.0f64 / 0.0f64 }
    ret b[j]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/quantreg_nl.json")
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
