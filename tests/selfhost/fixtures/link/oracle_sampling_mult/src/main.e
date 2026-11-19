// e.algo.stat.sampling's UPmultinomial against sampling. tests/oracle/sampling_mult.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_mult`; the layout is at the top of scripts/r_oracle/groups/sampling_mult.R.

use e.algo.rand.r as rr
use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let total = usize(x[0usize])
    let n = x[1usize]
    let (pik, e1) = mem.alloc[f64](a, total)
    let (s, e2) = mem.alloc[f64](a, total)
    if e1 != ok || e2 != ok { os.exit(4) }
    sp.inclusion(x[3usize..3usize + total], n, pik)
    var g: rr.Rng = zero
    rr.seed(&g, i64(x[2usize]))
    if sp.up_multinomial(&g, a, pik, s) != ok { os.exit(5) }
    var t = 0.0f64
    var i = 0usize
    while i < total {
        t += s[i] * f64(i + 1usize)
        i += 1usize
    }
    ret t
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_mult.json")
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
