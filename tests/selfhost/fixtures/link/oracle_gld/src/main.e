// e.algo.stat.gldpkg against gld. tests/oracle/gld.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gld`; the layout is at the top of scripts/r_oracle/groups/gld.R.

use e.algo.rand.r as rng
use e.algo.stat.gldpkg as gl
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let z = c.args
    let rs = z[0usize] == 1.0f64
    if str.eq(c.name, "q") {
        if rs { ret gl.qgl_rs(z[1usize], z[2usize], z[3usize], z[4usize], z[5usize]) }
        ret gl.qgl_fkml(z[1usize], z[2usize], z[3usize], z[4usize], z[5usize])
    }
    if str.eq(c.name, "dq") {
        if rs { ret gl.dqgl_rs(z[1usize], z[2usize], z[3usize], z[4usize]) }
        ret gl.dqgl_fkml(z[1usize], z[2usize], z[3usize], z[4usize])
    }
    var r: rng.Rng = zero
    rng.seed(&r, i64(z[1usize]))
    var v = 0.0f64
    var q = 0usize
    while q <= usize(z[6usize]) {
        v = gl.rgl(&r, rs, z[2usize], z[3usize], z[4usize], z[5usize])
        q += 1usize
    }
    ret v
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gld.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
