// e.algo.stat.sampling's Hajekstrata and rhg against sampling. tests/oracle/sampling_hr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sampling_hr`; the layout is at the top of scripts/r_oracle/groups/sampling_hr.R.

use e.algo.stat.sampling as sp
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    if str.eq(c.name, "hs") {
        let ns = usize(z[1usize])
        ret sp.hajek_strata(z[3usize..3usize + n], z[3usize + n..3usize + 2usize * n], z[3usize + 2usize * n..3usize + 3usize * n], z[3usize + 3usize * n..3usize + 3usize * n + ns], usize(z[2usize]) == 0usize)
    }
    let cc = usize(z[1usize])
    let i = usize(z[2usize]) - 1usize
    let (prob, e) = mem.alloc[f64](a, n)
    if e != ok { ret nan }
    sp.rhg_prob(z[3usize..3usize + n], z[3usize + n..3usize + n + n * cc], cc, prob)
    ret prob[i]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sampling_hr.json")
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
