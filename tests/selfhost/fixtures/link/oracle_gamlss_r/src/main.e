// e.algo.stat.gamlssr: random numbers of every gamlss.dist family under set.seed (five draws per case, as a position-weighted checksum); tests/oracle/gamlss_r.json is
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gamlss_r`; the layout of a case is at the top of scripts/r_oracle/groups/gamlss_r.R.

use e.algo.rand.r as rg
use e.algo.stat.gamlssr as gr
use e.math
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let fam = usize(z[0usize])
    var rng: rg.Rng = zero
    rg.seed(&rng, i64(z[1usize]))
    let d = gr.rfam_n(a, &rng, fam, 5usize, z[2usize], z[3usize], z[4usize], z[5usize], z[6usize])
    var sum = 0.0f64
    var i = 0usize
    while i < 5usize {
        sum += f64(i + 1usize) * gr.rvalue(fam, d.v[i])
        i += 1usize
    }
    ret sum
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gamlss_r.json")
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
