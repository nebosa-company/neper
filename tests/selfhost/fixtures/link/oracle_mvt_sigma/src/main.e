// e.algo.stat.mvt.pmvnorm_sigma against mvtnorm's pmvnorm with a mean and sigma. tests/oracle/mvt_sigma.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mvt_sigma`; the layout is at the top of scripts/r_oracle/groups/mvt_sigma.R.

use e.algo.rand.r as rng
use e.algo.stat.mvt as mvt
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, lat: *const mvt.Lat, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = i64(z[0usize])
    let n = usize(z[1usize])
    let maxpts = i64(z[2usize])
    let abseps = z[3usize]
    let releps = z[4usize]
    let q = usize(z[5usize + 3usize * n + n * n])
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    let (res, re) = mvt.pmvnorm_sigma(a, &g, lat, n, z[5usize..5usize + n], z[5usize + n..5usize + 2usize * n], z[5usize + 2usize * n..5usize + 3usize * n], z[5usize + 3usize * n..5usize + 3usize * n + n * n], maxpts, abseps, releps)
    if re != ok { ret nan }
    if q == 0usize { ret res.value }
    ret res.abserr
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mvt_sigma.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var lat: mvt.Lat = zero
    mvt.load_lattice(&lat)
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, &lat, c)
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
