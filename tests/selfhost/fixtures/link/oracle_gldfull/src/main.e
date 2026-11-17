// e.algo.stat.gldfull against gld: qgl, dqgl, pgl, dgl, rgl in the four parameterisations, gld.moments, gld.lmoments and
// fit.gpd.lmom.given. tests/oracle/gldfull.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gldfull`;
// the argument layouts are at the top of scripts/r_oracle/groups/gldfull.R.

use e.algo.rand.r as rng
use e.algo.stat.gldfull as gl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let eps = 2.220446049250313e-16f64
    if str.eq(c.name, "gpdfit") {
        var est: [8]f64 = zero
        var se: [8]f64 = zero
        let r = gl.fit_gpd_lmom_given(z[1usize..5usize], z[0usize], 1.0e-15f64, est[0usize..8usize], se[0usize..8usize])
        if r != 0i32 { ret nan }
        let j = usize(z[5usize])
        if j < 8usize { ret est[j] }
        ret se[j - 8usize]
    }
    if str.eq(c.name, "mom") {
        var o: [4]f64 = zero
        let np = usize(z[1usize])
        gl.fkml_moments(z[2usize..2usize + np], z[0usize] != 0.0f64, o[0usize..4usize])
        ret o[usize(z[2usize + np])]
    }
    if str.eq(c.name, "lmom") {
        ret gl.gpd_lmoment(z[4usize..8usize], usize(z[2usize]), z[0usize] != 0.0f64, z[1usize] != 0.0f64)
    }
    let param = i32(z[0usize])
    let np = usize(z[2usize])
    let lam = z[3usize..3usize + np]
    if str.eq(c.name, "q") { ret gl.qgl(param, z[1usize], lam) }
    if str.eq(c.name, "dq") { ret gl.dqgl(param, z[1usize], lam) }
    if str.eq(c.name, "p") { ret gl.pgl(param, z[1usize], lam, eps, 500usize) }
    if str.eq(c.name, "d") { ret gl.dgl(param, z[1usize], lam, eps, 500usize) }
    var r: rng.Rng = zero
    rng.seed(&r, i64(z[1usize]))
    var v = 0.0f64
    var j = 0usize
    let want = usize(z[3usize + np])
    while j <= want {
        v = gl.rgl(param, &r, lam)
        j += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gldfull.json")
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
