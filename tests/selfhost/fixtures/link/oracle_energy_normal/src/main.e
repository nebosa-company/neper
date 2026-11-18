// e.algo.stat.energy's normal_e and mvnorm_e against energy. tests/oracle/energy_normal.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R energy_normal`; the layout is at the top of scripts/r_oracle/groups/energy_normal.R.

use e.algo.rand.r as rg
use e.algo.stat.energy as en
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/energy_normal.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let z = c.args
        var n = usize(z[0usize])
        var got = 0.0f64
        if str.eq(c.name, "dcovtest_stat") || str.eq(c.name, "dcovtest_p") {
            n = usize(z[2usize])
            let dx = usize(z[3usize])
            let dy = usize(z[4usize])
            var rng: rg.Rng = zero
            rg.seed(&rng, i64(z[0usize]))
            let (st, pv, te) = en.dcov_test(a, &rng, z[5usize..5usize + n * dx], z[5usize + n * dx..5usize + n * dx + n * dy], n, dx, dy, usize(z[1usize]))
            if te != ok { os.exit(8) }
            if str.eq(c.name, "dcovtest_stat") { got = st } else { got = pv }
        } else if str.eq(c.name, "pdcor") {
            let dx = usize(z[1usize])
            let dy = usize(z[2usize])
            let dz = usize(z[3usize])
            let (pv, pe) = en.pdcor(a, z[4usize..4usize + n * dx], z[4usize + n * dx..4usize + n * dx + n * dy], z[4usize + n * dx + n * dy..4usize + n * dx + n * dy + n * dz], n, dx, dy, dz)
            if pe != ok { os.exit(9) }
            got = pv
        } else {
            let d = usize(z[1usize])
            got = en.mvnorm_e(a, z[2usize..2usize + n * d], n, d)
        }
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
