// e.algo.stat.pmcmr against PMCMRplus. tests/oracle/pmcmr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R pmcmr`; the layout is at the top of scripts/r_oracle/groups/pmcmr.R.

use e.algo.stat.pmcmr as pm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn padj_case(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let m = usize(x[1usize])
    let (p, e) = mem.alloc[f64](a, m)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < m {
        p[i] = x[3usize + i]
        i += 1usize
    }
    if pm.p_adjust(a, p, usize(x[0usize])) != ok { os.exit(6) }
    var s = 0.0f64
    i = 0usize
    while i < m {
        s += p[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "padj") { ret padj_case(a, c) }
    let x = c.args
    let n = usize(x[0usize])
    let k = usize(x[1usize])
    let y = x[2usize..2usize + n]
    let (grp, e1) = mem.alloc[usize](a, n)
    if e1 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        grp[i] = usize(x[2usize + n + i])
        i += 1usize
    }
    let (rbar, e2) = mem.alloc[f64](a, k)
    if e2 != ok { os.exit(6) }
    let (rn, e3) = mem.alloc[f64](a, k)
    if e3 != ok { os.exit(7) }
    let (q, e4) = pm.setup(a, y, grp, k, rbar, rn)
    if e4 != ok { os.exit(8) }
    let npairs = k * (k - 1usize) / 2usize
    let (vals, e5) = mem.alloc[f64](a, npairs)
    if e5 != ok { os.exit(9) }
    let kind = c.name
    var pos = 0usize
    var col = 0usize
    while col < k {
        var row = col + 1usize
        while row < k {
            if str.eq(kind, "dz") || str.eq(kind, "dp") || str.eq(kind, "dpholm") {
                let (z, p) = pm.dunn(q, rbar, rn, row, col)
                if str.eq(kind, "dz") { vals[pos] = z } else { vals[pos] = p }
            } else if str.eq(kind, "nq") || str.eq(kind, "np") {
                let (qv, p) = pm.nemenyi(q, rbar, rn, row, col)
                if str.eq(kind, "nq") { vals[pos] = qv } else { vals[pos] = p }
            } else {
                let (t, p, pt) = pm.conover(q, rbar, rn, row, col)
                if str.eq(kind, "ct") { vals[pos] = t }
                if str.eq(kind, "cp") || str.eq(kind, "cpholm") { vals[pos] = p }
                if str.eq(kind, "cptukey") { vals[pos] = pt }
            }
            pos += 1usize
            row += 1usize
        }
        col += 1usize
    }
    if str.eq(kind, "dpholm") || str.eq(kind, "cpholm") {
        if pm.holm(a, vals) != ok { os.exit(10) }
    }
    var s = 0.0f64
    i = 0usize
    while i < npairs {
        s += vals[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/pmcmr.json")
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
