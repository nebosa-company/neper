// e.algo.stat.ghypdist momIntegrated and e.algo.stat.ghypcvm against DistributionUtils and GeneralizedHyperbolic. tests/oracle/ghypmisc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ghypmisc`; the layout is at the top of scripts/r_oracle/groups/ghypmisc.R.

use e.algo.rand.r as rg
use e.algo.stat.ghyp as gh
use e.algo.stat.ghypcvm as cv
use e.algo.stat.ghypdist as gd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn sort_asc(v: []f64) {
    var i = 1usize
    while i < v.len {
        let key = v[i]
        var j = i
        while j > 0usize && v[j - 1usize] > key {
            v[j] = v[j - 1usize]
            j -= 1usize
        }
        v[j] = key
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "momint") { ret gd.mom_integrated(a, x[0usize] == 1.0f64, x[1usize], x[2usize], x[3usize] == 1.0f64, x[4usize], x[5usize], x[6usize], x[7usize], x[8usize]) }
    if str.eq(k, "cvmp") {
        let (o, e) = mem.alloc[f64](a, 3usize)
        if e != ok { os.exit(9) }
        cv.cvm_p_value(x[0usize], x[1usize], x[2usize], x[3usize], o)
        let w = usize(x[4usize])
        if w == 0usize { ret o[0usize] }
        if w == 1usize { ret o[1usize] }
        ret o[2usize]
    }
    let nn = usize(x[1usize])
    let (d, g1) = mem.alloc[f64](a, nn)
    let (xx, g2) = mem.alloc[f64](a, nn)
    if g1 != ok || g2 != ok { os.exit(7) }
    var rng: rg.Rng = zero
    rg.seed(&rng, i64(x[0usize]))
    gh.rghyp(&rng, nn, x[2usize], x[3usize], x[4usize], x[5usize], 1.0f64, d, xx)
    sort_asc(d)
    ret cv.hyperb_wsq(a, d, x[2usize], x[3usize], x[4usize], x[5usize])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ghypmisc.json")
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
