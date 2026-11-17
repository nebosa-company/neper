// e.algo.stat.mumin against MuMIn. tests/oracle/mumin.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mumin`; the layout is at the top of scripts/r_oracle/groups/mumin.R.

use e.algo.stat.mumin as mm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "qaic") { ret mm.qaic(x[0usize], x[1usize], x[2usize], x[3usize], x[4usize] != 0.0f64) }
    let n = x[0usize]
    let m = usize(x[1usize])
    let p = usize(x[2usize])
    let (ic, e1) = mem.alloc[f64](a, m)
    if e1 != ok { os.exit(5) }
    let (w, e2) = mem.alloc[f64](a, m)
    if e2 != ok { os.exit(6) }
    let (est, e3) = mem.alloc[f64](a, m * p)
    if e3 != ok { os.exit(7) }
    let (se, e4) = mem.alloc[f64](a, m * p)
    if e4 != ok { os.exit(8) }
    var at = 3usize
    var i = 0usize
    while i < m {
        ic[i] = mm.aicc(x[at + 1usize], x[at], n)
        var j = 0usize
        while j < p {
            est[j * m + i] = x[at + 2usize + 2usize * j]
            se[j * m + i] = x[at + 3usize + 2usize * j]
            j += 1usize
        }
        at += 2usize + 2usize * p
        i += 1usize
    }
    mm.akaike_weights(ic, w)
    let k = c.name
    var s = 0.0f64
    if str.eq(k, "aicc") {
        i = 0usize
        while i < m {
            s += ic[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(k, "w") {
        i = 0usize
        while i < m {
            s += w[i] * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if str.eq(k, "cest") || str.eq(k, "cse") || str.eq(k, "imp") {
        let (pres, e5) = mem.alloc[bool](a, m)
        if e5 != ok { os.exit(9) }
        var jj = 0usize
        while jj < p {
            var q = 0usize
            while q < m {
                // a term is in a model when its estimate is not exactly zero (the intercept is in all)
                pres[q] = est[jj * m + q] != 0.0f64
                q += 1usize
            }
            let (cb, cs2, imp) = mm.average_conditional(est[jj * m..jj * m + m], se[jj * m..jj * m + m], w, pres)
            if str.eq(k, "cest") { s += cb * f64(jj + 1usize) }
            if str.eq(k, "cse") { s += cs2 * f64(jj + 1usize) }
            if str.eq(k, "imp") && jj >= 1usize { s += imp * f64(jj) }
            jj += 1usize
        }
        ret s
    }
    var j = 0usize
    while j < p {
        let (bar, sd) = mm.average_full(est[j * m..j * m + m], se[j * m..j * m + m], w)
        if str.eq(k, "est") { s += bar * f64(j + 1usize) } else { s += sd * f64(j + 1usize) }
        j += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mumin.json")
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
