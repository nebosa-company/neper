// e.algo.stat.biasedurn_rand against BiasedUrn: the random variates under set.seed.
// tests/oracle/biasedurn_rand.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R biasedurn_rand`; the
// layout of each case is at the top of scripts/r_oracle/groups/biasedurn_rand.R.

use e.algo.rand.r as rng
use e.algo.stat.biasedurn_rand as br
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    var rg: rng.Rng = zero
    rng.seed(&rg, i64(z[0usize]))
    let nran = usize(z[1usize])
    let (out, e) = mem.alloc[f64](a, nran)
    if e != ok { ret 0.0f64 / 0.0f64 }
    if str.eq(c.name, "rF") { br.r_fisher(&rg, a, nran, z[2usize], z[3usize], z[4usize], z[5usize], z[6usize], out) }
    if str.eq(c.name, "rW") { br.r_wall(&rg, a, nran, z[2usize], z[3usize], z[4usize], z[5usize], z[6usize], out) }
    if z[7usize] == 1.0f64 { ret out[nran - 1usize] }
    var s = 0.0f64
    var i = 0usize
    while i < nran {
        s += out[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/biasedurn_rand.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 30usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
