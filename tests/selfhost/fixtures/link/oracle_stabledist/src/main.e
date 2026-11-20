// e.algo.stat.stabledistpkg against stabledist::dstable. tests/oracle/stabledist.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R stabledist`; the layout is at the top of scripts/r_oracle/groups/stabledist.R.

use e.algo.rand.r as rg
use e.algo.stat.stabledistpkg as sd
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/stabledist.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let z = c.args
        var got = 0.0f64
        if str.eq(c.name, "qopt") {
            got = sd.qstable_opt(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize], true, false, z[5usize], i64(z[6usize]), z[7usize], usize(z[8usize]))
        } else if str.eq(c.name, "dopt") {
            got = sd.dstable_opt(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize], z[5usize], z[6usize], usize(z[7usize]))
        } else if str.eq(c.name, "popt") {
            got = sd.pstable_tol(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize], z[5usize], usize(z[6usize]))
        } else if str.eq(c.name, "mode") {
            got = sd.stable_mode(a, z[0usize], z[1usize])
        } else if str.eq(c.name, "qpm") {
            got = sd.qstable_pm(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize], usize(z[5usize]))
        } else if str.eq(c.name, "rpm") {
            let nn = usize(z[5usize])
            let (out, g1) = mem.alloc[f64](a, nn)
            let (th, g2) = mem.alloc[f64](a, nn)
            let (ww, g3) = mem.alloc[f64](a, nn)
            if g1 != ok || g2 != ok || g3 != ok { os.exit(7) }
            var rng: rg.Rng = zero
            rg.seed(&rng, i64(z[4usize]))
            sd.rstable_pm(a, &rng, nn, z[0usize], z[1usize], z[2usize], z[3usize], usize(z[7usize]), out, th, ww)
            got = out[usize(z[6usize])]
        } else if str.eq(c.name, "qe") {
            got = sd.qstable_ext(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize], z[5usize] > 0.5f64, z[6usize] > 0.5f64)
        } else if str.eq(c.name, "dl") {
            got = sd.dstable_log(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize])
        } else if str.eq(c.name, "dpm") {
            got = sd.dstable_pm(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize], usize(z[5usize]))
        } else if str.eq(c.name, "ppm") {
            got = sd.pstable_pm(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize], usize(z[5usize]), true, false)
        } else if str.eq(c.name, "pe") {
            got = sd.pstable_ext(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize], 64.0f64 * 2.220446049250313e-16f64, 1000usize, z[5usize] > 0.5f64, z[6usize] > 0.5f64)
        } else if str.eq(c.name, "r") {
            let nn = usize(z[5usize])
            let (out, g1) = mem.alloc[f64](a, nn)
            let (th, g2) = mem.alloc[f64](a, nn)
            let (ww, g3) = mem.alloc[f64](a, nn)
            if g1 != ok || g2 != ok || g3 != ok { os.exit(7) }
            var rng: rg.Rng = zero
            rg.seed(&rng, i64(z[4usize]))
            sd.rstable(&rng, nn, z[0usize], z[1usize], z[2usize], z[3usize], out, th, ww)
            got = out[usize(z[6usize])]
        } else if str.eq(c.name, "q") { got = sd.qstable(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize]) } else if str.eq(c.name, "p") { got = sd.pstable(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize]) } else { got = sd.dstable(a, z[4usize], z[0usize], z[1usize], z[2usize], z[3usize]) }
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
