// e.algo.stat.rcompanion_ext against rcompanion. tests/oracle/rcompanion_ext.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R rcompanion_ext`; the layout of every case is at the top of scripts/r_oracle/groups/rcompanion_ext.R.

use e.algo.rand.r as rng
use e.algo.stat.rcompanion_ext as rx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn codes(z: []const f64, at: usize, n: usize, out: []usize) {
    var i = 0usize
    while i < n {
        out[i] = usize(z[at + i])
        i += 1usize
    }
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "pmed") {
        let k = usize(z[0usize])
        let n = usize(z[1usize])
        let digits = i64(z[2usize])
        let method = u8(z[3usize])
        let q = usize(z[4usize + 2usize * n])
        let (g, e1) = mem.alloc[usize](a, n)
        let m = k * (k - 1usize) / 2usize
        let (p, e2) = mem.alloc[f64](a, m)
        let (adj, e3) = mem.alloc[f64](a, m)
        if e1 != ok || e2 != ok || e3 != ok { ret nan() }
        codes(z, 4usize + n, n, g)
        if rx.pairwise_median_test(a, z[4usize..4usize + n], g, k, digits, method, p, adj) != ok { ret nan() }
        if q < m { ret p[q] }
        ret adj[q - m]
    }
    if str.eq(c.name, "pnom") {
        let r = usize(z[0usize])
        let cc = usize(z[1usize])
        let compare = usize(z[2usize])
        let digits = i64(z[3usize])
        let method = u8(z[4usize])
        let gc = usize(z[5usize])
        let yates = z[6usize] != 0.0f64
        let q = usize(z[7usize])
        var n = r
        if compare == 1usize { n = cc }
        let m = n * (n - 1usize) / 2usize
        let (out, e) = mem.alloc[f64](a, 10usize * m)
        if e != ok { ret nan() }
        if rx.pairwise_nominal_independence(a, z[8usize..8usize + r * cc], r, cc, compare, true, true, true, true, true, method, gc, yates, digits, out) != ok { ret nan() }
        ret out[q]
    }
    if str.eq(c.name, "gmean") {
        let k = usize(z[0usize])
        let n = usize(z[1usize])
        let trim = z[2usize]
        let conf = z[3usize]
        let nrep = usize(z[4usize])
        let flags = usize(z[5usize])
        let digits = i64(z[6usize])
        let seed = i64(z[7usize])
        let q = usize(z[8usize])
        let (g, e1) = mem.alloc[usize](a, n)
        let (out, e2) = mem.alloc[f64](a, 13usize * k)
        if e1 != ok || e2 != ok { ret nan() }
        codes(z, 9usize + n, n, g)
        var rg: rng.Rng = zero
        rng.seed(&rg, seed)
        if rx.groupwise_mean(a, &rg, z[9usize..9usize + n], g, k, trim, conf, nrep, digits, flags, out) != ok { ret nan() }
        ret out[q]
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
