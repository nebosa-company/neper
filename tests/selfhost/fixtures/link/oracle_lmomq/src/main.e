// e.algo.stat.lmomq against lmom::lmrq: the (trimmed) L-moments of a quantile function by quadrature. tests/oracle/lmomq.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R lmomq`; the layout is at the top of scripts/r_oracle/groups/lmomq.R.

use e.algo.stat.lmomq as lq
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let np = usize(z[1usize])
    let at = 2usize + np
    var val: [20]f64 = zero
    var errv: [20]f64 = zero
    let maxord = usize(z[at + 1usize])
    if lq.lmrq(a, i32(z[0usize]), z[2usize..at], z[at] != 0.0f64, maxord, z[at + 2usize] != 0.0f64, z[at + 3usize], z[at + 4usize], z[at + 5usize], 100usize, val[0usize..20usize], errv[0usize..20usize]) != ok { ret nan }
    ret val[usize(z[at + 6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/lmomq.json")
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
