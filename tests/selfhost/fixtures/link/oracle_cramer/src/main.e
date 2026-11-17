// e.algo.stat.cramerpkg against cramer.test. tests/oracle/cramer.json comes from
// `R_ORACLE_LIB=<dir with cramer first> Rscript scripts/r_oracle/generate.R cramer`; the layout is at the top of scripts/r_oracle/groups/cramer.R.

use e.algo.stat.cramerpkg as cr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let d = usize(x[0usize])
    let m = usize(x[1usize])
    let n = usize(x[2usize])
    let nn = m + n
    let data = x[3usize..3usize + nn * d]
    let at = 3usize + nn * d
    let k = usize(x[at])
    let conf = x[at + 1usize]
    let reps = usize(x[at + 2usize])
    let seed = i64(x[at + 3usize])
    let (lk, e) = mem.alloc[f64](a, nn * nn)
    if e != ok { os.exit(4) }
    cr.lookup(data, nn, d, k, lk)
    var out: [3]f64 = zero
    if str.eq(c.name, "cr_stat") {
        let (idx, e2) = mem.alloc[usize](a, nn)
        if e2 != ok { os.exit(5) }
        var i = 0usize
        while i < nn {
            idx[i] = i + 1usize
            i += 1usize
        }
        ret cr.statistic(lk, nn, idx, m, n)
    }
    if str.eq(c.name, "cr_boot_crit") || str.eq(c.name, "cr_boot_p") {
        if cr.bootstrap(a, lk, nn, m, n, conf, reps, false, seed, out[0usize..3usize]) != ok { os.exit(6) }
    } else if str.eq(c.name, "cr_perm_crit") || str.eq(c.name, "cr_perm_p") {
        if cr.bootstrap(a, lk, nn, m, n, conf, reps, true, seed, out[0usize..3usize]) != ok { os.exit(7) }
    } else {
        if cr.eigenvalue(a, lk, nn, m, n, conf, out[0usize..3usize]) != ok { os.exit(8) }
    }
    if str.ends_with(c.name, "_crit") { ret out[1usize] }
    ret out[2usize]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/cramer.json")
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
