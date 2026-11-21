// e.algo.stat.mcmcpackhreg against MCMChregress. tests/oracle/mcmcpackhreg.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpackhreg`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpackhreg.R.

use e.algo.stat.mcmcpackhreg as mh
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
    var g: ms.Sc = zero
    ms.sc_seed(&g, u64(z[0usize]))
    let n = usize(z[1usize])
    let ng = usize(z[2usize])
    let np = usize(z[3usize])
    let nq = usize(z[4usize])
    let burn = usize(z[5usize])
    let mc = usize(z[6usize])
    let thin = usize(z[7usize])
    let r = z[8usize]
    let s1 = z[9usize]
    let s2 = z[10usize]
    let sig0 = z[11usize]
    var o = 12usize
    let grp = z[o..o + n]
    o += n
    let y = z[o..o + n]
    o += n
    let x = z[o..o + n * np]
    o += n * np
    let w = z[o..o + n * nq]
    o += n * nq
    let mubeta = z[o..o + np]
    o += np
    let vbeta = z[o..o + np * np]
    o += np * np
    let rr = z[o..o + nq * nq]
    o += nq * nq
    let beta0 = z[o..o + np]
    o += np
    let vb0 = z[o..o + nq * nq]
    let ncol = np + nq * ng + nq * nq + 2usize
    let (out, e1) = mem.alloc[f64](a, (mc / thin) * ncol)
    let (yp, e2) = mem.alloc[f64](a, n)
    if e1 != ok { ret nan }
    if e2 != ok { ret nan }
    if mh.hregress(a, &g, grp, y, x, w, n, ng, np, nq, mubeta, vbeta, r, rr, s1, s2, beta0, sig0, vb0, burn, mc, thin, out, yp) != ok { ret nan }
    if str.eq(c.name, "hregpred") { ret wsum(yp) }
    ret wsum(out)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpackhreg.json")
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
