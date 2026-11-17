// e.algo.stat.rcompanion_ext against rcompanion (pairwiseMedianTest, pairwiseNominalIndependence, groupwiseMean). tests/oracle/rcompanion_ext.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rcompanion_ext`; the layout is at the top of scripts/r_oracle/groups/rcompanion_ext.R.

use e.algo.rand.r as rng
use e.algo.stat.rcompanion_ext as rx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "pmed") {
        let digits = i64(z[0usize])
        let method = u8(z[1usize])
        let k = usize(z[2usize])
        let n = usize(z[3usize])
        let q = usize(z[4usize])
        let x = z[5usize..5usize + n]
        let (g, e1) = mem.alloc[usize](a, n)
        let (p, e2) = mem.alloc[f64](a, k * k)
        let (pa, e3) = mem.alloc[f64](a, k * k)
        if e1 != ok || e2 != ok || e3 != ok { ret nan() }
        var i = 0usize
        while i < n {
            g[i] = usize(z[5usize + n + i])
            i += 1usize
        }
        if rx.pairwise_median_test(a, x, g, k, digits, method, p, pa) != ok { ret nan() }
        if q % 2usize == 0usize { ret p[q / 2usize] }
        ret pa[q / 2usize]
    }
    if str.eq(c.name, "pnom") {
        let r = usize(z[0usize])
        let cc = usize(z[1usize])
        let cmp = usize(z[2usize])
        let flags = usize(z[3usize])
        let method = u8(z[4usize])
        let gcorr = usize(z[5usize])
        let yates = z[6usize] != 0.0f64
        let digits = i64(z[7usize])
        let q = usize(z[8usize])
        let t = z[9usize..9usize + r * cc]
        var n = r
        if cmp == 1usize { n = cc }
        let (out, e) = mem.alloc[f64](a, 10usize * n * n)
        if e != ok { ret nan() }
        let ok0 = rx.pairwise_nominal_independence(a, t, r, cc, cmp, (flags & 1usize) != 0usize, (flags & 2usize) != 0usize, (flags & 4usize) != 0usize, (flags & 8usize) != 0usize, (flags & 16usize) != 0usize, method, gcorr, yates, digits, out)
        if ok0 != ok { ret nan() }
        ret out[q]
    }
    if str.eq(c.name, "gm") {
        let n = usize(z[0usize])
        let k = usize(z[1usize])
        let (g, e1) = mem.alloc[usize](a, n)
        let (out, e2) = mem.alloc[f64](a, 13usize * k)
        if e1 != ok || e2 != ok { ret nan() }
        var i = 0usize
        while i < n {
            g[i] = usize(z[9usize + n + i])
            i += 1usize
        }
        var rg: rng.Rng = zero
        rng.seed(&rg, i64(z[7usize]))
        if rx.groupwise_mean(a, &rg, z[9usize..9usize + n], g, k, z[2usize], z[3usize], usize(z[4usize]), i64(z[5usize]), usize(z[6usize]), out) != ok { ret nan() }
        ret out[usize(z[8usize])]
    }
    ret nan()
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/rcompanion_ext.json")
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
