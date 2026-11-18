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
        if str.eq(c.name, "dcovtest_stat") || str.eq(c.name, "dcovtest_p") || str.eq(c.name, "dcortest_stat") || str.eq(c.name, "dcortest_p") {
            n = usize(z[2usize])
            let dx = usize(z[3usize])
            let dy = usize(z[4usize])
            var rng: rg.Rng = zero
            rg.seed(&rng, i64(z[0usize]))
            var st = 0.0f64
            var pv = 0.0f64
            var te = ok
            if str.eq(c.name, "dcortest_stat") || str.eq(c.name, "dcortest_p") {
                let (s1, p1, t1) = en.dcor_test(a, &rng, z[5usize..5usize + n * dx], z[5usize + n * dx..5usize + n * dx + n * dy], n, dx, dy, usize(z[1usize]))
                st = s1
                pv = p1
                te = t1
            } else {
                let (s2, p2, t2) = en.dcov_test(a, &rng, z[5usize..5usize + n * dx], z[5usize + n * dx..5usize + n * dx + n * dy], n, dx, dy, usize(z[1usize]))
                st = s2
                pv = p2
                te = t2
            }
            if te != ok { os.exit(8) }
            if str.eq(c.name, "dcovtest_stat") || str.eq(c.name, "dcortest_stat") { got = st } else { got = pv }
        } else if str.eq(c.name, "eqtest_stat") || str.eq(c.name, "eqtest_p") {
            let n1 = usize(z[2usize])
            let n2 = usize(z[3usize])
            let d = usize(z[4usize])
            var rng2: rg.Rng = zero
            rg.seed(&rng2, i64(z[0usize]))
            let (st, pv, te) = en.eqdist_etest(a, &rng2, z[5usize..5usize + (n1 + n2) * d], n1, n2, d, usize(z[1usize]))
            if te != ok { os.exit(8) }
            if str.eq(c.name, "eqtest_stat") { got = st } else { got = pv }
        } else if str.eq(c.name, "keqtest_stat") || str.eq(c.name, "keqtest_p") {
            let kk = usize(z[2usize])
            let (szs, se) = mem.alloc[usize](a, kk)
            if se != ok { os.exit(8) }
            var tot = 0usize
            var q = 0usize
            while q < kk {
                szs[q] = usize(z[3usize + q])
                tot += szs[q]
                q += 1usize
            }
            let d = usize(z[3usize + kk])
            var rng3: rg.Rng = zero
            rg.seed(&rng3, i64(z[0usize]))
            let (st, pv, te) = en.eqdist_ketest(a, &rng3, z[4usize + kk..4usize + kk + tot * d], szs, d, usize(z[1usize]))
            if te != ok { os.exit(8) }
            if str.eq(c.name, "keqtest_stat") { got = st } else { got = pv }
        } else if str.eq(c.name, "disco_b") || str.eq(c.name, "disco_w") || str.eq(c.name, "disco_f") || str.eq(c.name, "disco_p") {
            let kk = usize(z[2usize])
            let nn = usize(z[3usize])
            let d = usize(z[4usize])
            let ix = z[5usize]
            let (gp, ge) = mem.alloc[usize](a, nn)
            let (dm, de) = mem.alloc[f64](a, nn * nn)
            let (res, re) = mem.alloc[f64](a, 4usize)
            if ge != ok || de != ok || re != ok { os.exit(8) }
            var q = 0usize
            while q < nn {
                gp[q] = usize(z[6usize + q])
                q += 1usize
            }
            let xs = z[6usize + nn..6usize + nn + nn * d]
            q = 0usize
            while q < nn {
                var q2 = 0usize
                while q2 < nn {
                    dm[q * nn + q2] = en.dist_pow(xs, nn, d, q, q2, ix)
                    q2 += 1usize
                }
                q += 1usize
            }
            var rng4: rg.Rng = zero
            rg.seed(&rng4, i64(z[0usize]))
            if en.disco(a, &rng4, dm, nn, gp, kk, usize(z[1usize]), res) != ok { os.exit(8) }
            if str.eq(c.name, "disco_b") { got = res[0usize] }
            if str.eq(c.name, "disco_w") { got = res[1usize] }
            if str.eq(c.name, "disco_f") { got = res[2usize] }
            if str.eq(c.name, "disco_p") { got = res[3usize] }
        } else if str.eq(c.name, "poiss_stat") || str.eq(c.name, "poiss_p") {
            let nn = usize(z[2usize])
            var rng5: rg.Rng = zero
            rg.seed(&rng5, i64(z[0usize]))
            let (st, pv, te) = en.poisson_etest(a, &rng5, z[3usize..3usize + nn], usize(z[1usize]))
            if te != ok { os.exit(8) }
            if str.eq(c.name, "poiss_stat") { got = st } else { got = pv }
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
