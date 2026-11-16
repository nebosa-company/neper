// e.algo.stat.mvtq against mvtnorm's qmvnorm. tests/oracle/qmvnorm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R qmvnorm`; the layout is at the top of scripts/r_oracle/groups/qmvnorm.R.

use e.algo.stat.mvt as mvt
use e.algo.stat.mvtq as mq
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, lat: *const mvt.Lat, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[1usize])
    let (q, fq) = mq.qmvnorm(a, lat, z[3usize], usize(z[2usize]), n, z[6usize..6usize + n * n], i64(z[0usize]), z[4usize], usize(z[5usize]))
    if str.eq(c.name, "q") { ret q }
    ret fq
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/qmvnorm.json")
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
