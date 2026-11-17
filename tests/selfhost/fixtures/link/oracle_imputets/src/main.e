// e.algo.stat.imputets against imputeTS. tests/oracle/imputets.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R imputets`; the layout is at the top of scripts/r_oracle/groups/imputets.R.

use e.algo.stat.imputets as it
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let k = usize(x[1usize])
    let n = usize(x[2usize])
    let (s, e) = mem.alloc[f64](a, n)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        s[i] = x[3usize + i]
        if s[i] < 0.0f64 - 999000.0f64 { s[i] = 0.0f64 / 0.0f64 }
        i += 1usize
    }
    if str.eq(c.name, "locf") {
        let (lr, le) = it.na_locf_ts(a, s, kind >= 10usize, kind % 10usize)
        if le != ok { os.exit(7) }
        ret lr[k]
    }
    if str.eq(c.name, "interp") {
        let (ir, ie) = it.na_interpolation(a, s, kind)
        if ie != ok { os.exit(7) }
        ret ir[k]
    }
    if str.eq(c.name, "mean") { ret it.na_mean_value(a, s, kind) }
    let (r, e2) = it.na_ma(a, s, k, kind)
    if e2 != ok { os.exit(6) }
    var t = 0.0f64
    i = 0usize
    while i < n {
        t += r[i] * f64(i + 1usize)
        i += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/imputets.json")
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
