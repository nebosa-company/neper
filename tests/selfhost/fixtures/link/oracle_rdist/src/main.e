// e.algo.rand.rdist against R: rgamma, rchisq, rt, rbeta, rbinom, rpois, rnbinom, rgeom,
// rweibull, rlnorm, rlogis and rcauchy after set.seed. tests/oracle/rdist.json comes from
// `Rscript scripts/r_oracle/generate.R rdist`; a case is (dist, seed, p1, p2, i), the ith of 15
// draws.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn one(r: *rng.Rng, d: u8, p1: f64, p2: f64) -> f64 {
    if d == 0u8 { ret rd.rgamma(r, p1, p2) }
    if d == 1u8 { ret rd.rchisq(r, p1) }
    if d == 2u8 { ret rd.rt(r, p1) }
    if d == 3u8 { ret rd.rbeta(r, p1, p2) }
    if d == 4u8 { ret rd.rbinom(r, p1, p2) }
    if d == 5u8 { ret rd.rpois(r, p1) }
    if d == 6u8 { ret rd.rnbinom(r, p1, p2) }
    if d == 7u8 { ret rd.rnbinom_mu(r, p1, p2) }
    if d == 8u8 { ret rd.rgeom(r, p1) }
    if d == 9u8 { ret rd.rweibull(r, p1, p2) }
    if d == 10u8 { ret rd.rlnorm(r, p1, p2) }
    if d == 11u8 { ret rd.rlogis(r, p1, p2) }
    ret rd.rcauchy(r, p1, p2)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    var r: rng.Rng = zero
    rng.seed(&r, i64(x[1usize]))
    let want = usize(x[4usize])
    var i = 0usize
    var v = 0.0f64
    while i <= want {
        v = one(&r, u8(x[0usize]), x[2usize], x[3usize])
        i += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rdist.json")
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
            if failures <= 20usize {
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
