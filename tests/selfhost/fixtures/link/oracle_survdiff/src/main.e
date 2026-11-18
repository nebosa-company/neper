// e.algo.stat.survival's Fleming-Harrington test against survival::survdiff. tests/oracle/survdiff.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R survdiff`; the layout is at the top of scripts/r_oracle/groups/survdiff.R.

use e.algo.stat.survival as sv
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let na = usize(x[1usize])
    let nb = usize(x[2usize])
    let ta = x[3usize..3usize + na]
    let tb = x[3usize + na..3usize + na + nb]
    let (ea, e1) = mem.alloc[u8](a, na)
    let (eb, e2) = mem.alloc[u8](a, nb)
    if e1 != ok || e2 != ok { os.exit(4) }
    var i = 0usize
    while i < na {
        ea[i] = u8(x[3usize + na + nb + i])
        i += 1usize
    }
    i = 0usize
    while i < nb {
        eb[i] = u8(x[3usize + 2usize * na + nb + i])
        i += 1usize
    }
    let (r, e) = sv.fleming_harrington(ta, ea, na, tb, eb, nb, x[0usize], 0.0f64)
    if e != ok { os.exit(5) }
    if str.eq(c.name, "sd_chisq") { ret r.statistic }
    ret r.p_value
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/survdiff.json")
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
