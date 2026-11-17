// e.algo.stat.cramerpkg against cramer; layout at the top of scripts/r_oracle/groups/cramer.R.

use e.algo.stat.cramerpkg as cr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    let m = usize(x[0usize])
    let n = usize(x[1usize])
    let d = usize(x[2usize])
    let kernel = usize(x[3usize])
    let reps = usize(x[4usize])
    let seed = i64(x[5usize])
    let data = x[6usize..6usize + (m + n) * d]
    if str.eq(nm, "cr_stat") {
        let (s, e) = cr.stat_only(a, data, m, n, d, kernel)
        if e != ok { os.exit(4) }
        ret s
    }
    if str.starts_with(nm, "cr_e") {
        let (s, p, q, e) = cr.eigen_test(a, data, m, n, d, kernel, 0.95f64)
        if e != ok { os.exit(5) }
        if str.eq(nm, "cr_ep") { ret p }
        ret q
    }
    let (s, p, q, e) = cr.bootstrap(a, data, m, n, d, kernel, reps, seed, str.starts_with(nm, "cr_p"), 0.95f64)
    if e != ok { os.exit(6) }
    if str.ends_with(nm, "p") { ret p }
    ret q
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
