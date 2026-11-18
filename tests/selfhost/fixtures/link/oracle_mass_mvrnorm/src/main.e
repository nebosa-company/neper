// e.algo.stat.mass's mvrnorm against MASS::mvrnorm under set.seed. tests/oracle/mass_mvrnorm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_mvrnorm`; the layout of every case is at the top of scripts/r_oracle/groups/mass_mvrnorm.R.

use e.algo.rand.r as rng
use e.algo.stat.mass as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn pick(v: []const f64, j: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        if j == 0usize { s += v[i] }
        if j == 1usize { s += v[i] * f64(i + 1usize) }
        if j == 2usize { s += v[i] * v[i] }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let last = usize(z[z.len - 1usize])
    let seed = i64(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let mu = z[3usize..3usize + p]
    let sigma = z[3usize + p..3usize + p + p * p]
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (o, e) = mem.alloc[f64](a, n * p)
    if e != ok { ret nan() }
    if ms.mvrnorm(a, &g, n, p, mu, sigma, o) != ok { ret nan() }
    ret pick(o[0usize..n * p], last)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_mvrnorm.json")
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
