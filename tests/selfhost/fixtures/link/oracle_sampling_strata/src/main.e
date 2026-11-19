// e.algo.stat.sampling's strata (srswor, systematic, poisson) under set.seed against sampling. tests/oracle/sampling_strata.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_strata`; the layout is at the top of scripts/r_oracle/groups/sampling_strata.R.

use e.algo.rand.r as rr
use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let method = usize(x[0usize])
    let n = usize(x[1usize])
    let k = usize(x[2usize])
    let seed = i64(x[3usize])
    let size = x[4usize..4usize + k]
    let label = x[4usize + k..4usize + k + n]
    let w = x[4usize + k + n..4usize + k + 2usize * n]
    let (ids, e1) = mem.alloc[f64](a, n)
    if e1 != ok { os.exit(4) }
    var g: rr.Rng = zero
    rr.seed(&g, seed)
    let (cnt, e) = sp.strata(a, &g, label, w, size, method, ids)
    if e != ok { os.exit(5) }
    if str.eq(c.name, "st0") { ret f64(cnt) }
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += ids[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_strata.json")
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
