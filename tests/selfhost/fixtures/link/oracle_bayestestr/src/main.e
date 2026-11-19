// e.algo.stat.bayestestr against bayestestR. tests/oracle/bayestestr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bayestestr`; the layout is at the top of scripts/r_oracle/groups/bayestestr.R.

use e.algo.stat.bayestestr as bt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "ropeci") || str.eq(c.name, "equiv") {
        let m = usize(x[4usize])
        let (o, e) = mem.alloc[f64](a, 5usize)
        if e != ok { os.exit(4) }
        bt.rope_ci(a, x[5usize..5usize + m], x[2usize], x[3usize], x[0usize], usize(x[1usize]), o)
        if str.eq(c.name, "equiv") { ret f64(bt.equivalence_decision(o[0usize], x[0usize])) }
        ret o[usize(x[5usize + m])]
    }
    let n = usize(x[2usize])
    let s = x[3usize..3usize + n]
    if str.eq(c.name, "map") {
        // args (0, which 0 the estimate 1 its density, n, x...)
        let mn = usize(x[2usize])
        var mo: [2]f64 = zero
        if bt.map_estimate(a, x[3usize..3usize + mn], mo[0usize..2usize]) != ok { ret 0.0f64 / 0.0f64 }
        ret mo[usize(x[1usize])]
    }
    if str.eq(c.name, "pmap") { ret bt.p_map(a, s, x[0usize]) }
    if str.eq(c.name, "psig") { ret bt.p_significance(s, x[0usize]) }
    if str.eq(c.name, "hdi") { ret bt.hdi(a, s, x[0usize], usize(x[1usize])) }
    if str.eq(c.name, "eti") { ret bt.eti(a, s, x[0usize], usize(x[1usize])) }
    if str.eq(c.name, "pd") { ret bt.p_direction(s) }
    ret bt.rope_share(s, x[0usize], x[1usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bayestestr.json")
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
