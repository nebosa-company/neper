// e.algo.stat.mcmcpackirt against the MCMCpack item response samplers. tests/oracle/mcmcpackirt.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpackirt`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpackirt.R.

use e.algo.stat.mcmcpackirt as mi
use e.algo.stat.mcmcpackirtstart as st
use e.algo.stat.mcmcpacksamp as ms
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(m: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m.len {
        s += f64(i + 1usize) * m[i]
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = u64(z[0usize])
    var g: ms.Sc = zero
    ms.sc_seed(&g, seed)
    if str.eq(c.name, "irt1d") {
        let jn = usize(z[1usize])
        let kn = usize(z[2usize])
        let burn = usize(z[3usize])
        let mc = usize(z[4usize])
        let thin = usize(z[5usize])
        let nstore = mc / thin
        var o = 6usize
        let t0 = z[o]
        let tt0 = z[o + 1usize]
        let ab0 = z[o + 2usize..o + 4usize]
        let abb0 = z[o + 4usize..o + 8usize]
        o += 8usize
        let theta0 = z[o..o + jn]
        o += jn
        let alpha0 = z[o..o + kn]
        o += kn
        let beta0 = z[o..o + kn]
        o += kn
        let eq = z[o..o + jn]
        o += jn
        let ineq = z[o..o + jn]
        o += jn
        let x = z[o..o + jn * kn]
        let (out, e1) = mem.alloc[f64](a, nstore * (jn + 2usize * kn))
        if e1 != ok { ret nan }
        if mi.irt1d(a, &g, x, jn, kn, theta0, alpha0, beta0, t0, tt0, ab0, abb0, eq, ineq, burn, mc, thin, out) != ok { ret nan }
        ret wsum(out)
    }
    if str.eq(c.name, "irt1d_def") || str.eq(c.name, "irt1d_st") {
        let jn = usize(z[1usize])
        let kn = usize(z[2usize])
        let burn = usize(z[3usize])
        let mc = usize(z[4usize])
        let thin = usize(z[5usize])
        let nstore = mc / thin
        var o = 6usize
        let t0 = z[o]
        let tt0 = z[o + 1usize]
        let ab0 = z[o + 2usize..o + 4usize]
        let abb0 = z[o + 4usize..o + 8usize]
        o += 8usize
        let eq = z[o..o + jn]
        o += jn
        let ineq = z[o..o + jn]
        o += jn
        let x = z[o..o + jn * kn]
        let (out, e1) = mem.alloc[f64](a, nstore * (jn + 2usize * kn))
        let (theta0, e2) = mem.alloc[f64](a, jn)
        let (alpha0, e3) = mem.alloc[f64](a, kn)
        let (beta0, e4) = mem.alloc[f64](a, kn)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
        if st.irt1d_starts(a, x, jn, kn, t0, tt0, eq, ineq, theta0, alpha0, beta0) != ok { ret nan }
        if str.eq(c.name, "irt1d_st") {
            var s = 0.0f64
            var q = 0usize
            while q < jn {
                s += f64(q + 1usize) * theta0[q]
                q += 1usize
            }
            q = 0usize
            while q < kn {
                s += f64(jn + q + 1usize) * alpha0[q] + f64(jn + kn + q + 1usize) * beta0[q]
                q += 1usize
            }
            ret s
        }
        if mi.irt1d(a, &g, x, jn, kn, theta0, alpha0, beta0, t0, tt0, ab0, abb0, eq, ineq, burn, mc, thin, out) != ok { ret nan }
        ret wsum(out)
    }
    if str.eq(c.name, "glm1") {
        let maxit = usize(z[1usize])
        let eps = z[2usize]
        let m = usize(z[3usize])
        let (cf, e1) = mem.alloc[f64](a, 2usize)
        if e1 != ok { ret nan }
        if st.glm_probit1(a, z[4usize..4usize + m], z[4usize + m..4usize + 2usize * m], maxit, eps, cf) != ok { ret nan }
        ret cf[0usize] + 2.0f64 * cf[1usize]
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpackirt.json")
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
