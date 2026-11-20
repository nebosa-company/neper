// e.algo.stat.mcmcpacksamp against the MCMCpack samplers. tests/oracle/mcmcpacksamp.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmcpacksamp`; the argument layout is at the top of scripts/r_oracle/groups/mcmcpacksamp.R.

use e.algo.rand.r as rng
use e.algo.stat.mcmcpackdraw as md
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
    if str.eq(c.name, "rwish") || str.eq(c.name, "riwish") {
        var r: rng.Rng = zero
        rng.seed(&r, i64(z[0usize]))
        let p = usize(z[1usize])
        let (out, e0) = mem.alloc[f64](a, p * p)
        if e0 != ok { ret nan }
        var e = ok
        if str.eq(c.name, "rwish") { e = md.rwish(a, &r, z[2usize], z[3usize..3usize + p * p], p, out) } else { e = md.riwish(a, &r, z[2usize], z[3usize..3usize + p * p], p, out) }
        if e != ok { ret nan }
        ret wsum(out)
    }
    if str.eq(c.name, "rdir") {
        var r: rng.Rng = zero
        rng.seed(&r, i64(z[0usize]))
        let cn = usize(z[1usize])
        let al = z[2usize..z.len]
        let (out, e0) = mem.alloc[f64](a, cn * al.len)
        if e0 != ok { ret nan }
        md.rdirichlet(&r, cn, al, out)
        ret wsum(out)
    }
    let seed = u64(z[0usize])
    let n = usize(z[1usize])
    let k = usize(z[2usize])
    let burn = usize(z[3usize])
    let mc = usize(z[4usize])
    let thin = usize(z[5usize])
    let nstore = mc / thin
    var g: ms.Sc = zero
    ms.sc_seed(&g, seed)
    if str.eq(c.name, "reg") || str.eq(c.name, "regsig") || str.eq(c.name, "regml") {
        let c0 = z[6usize]
        let d0 = z[7usize]
        let y = z[8usize..8usize + n]
        let xs = z[8usize + n..8usize + n + n * k]
        let o = 8usize + n + n * k
        let (out, e1) = mem.alloc[f64](a, nstore * (k + 1usize))
        if e1 != ok { ret nan }
        var ml = 0.0f64
        if ms.regress(a, &g, y, xs, n, k, z[o..o + k], z[o + k..o + 2usize * k], z[o + 2usize * k..o + 2usize * k + k * k], c0, d0, burn, mc, thin, true, out, &ml) != ok { ret nan }
        if str.eq(c.name, "regml") { ret ml }
        if str.eq(c.name, "reg") { ret wsum(out) }
        var s = 0.0f64
        var i = 0usize
        while i < nstore {
            s += f64(i + 1usize) * out[i * (k + 1usize) + k]
            i += 1usize
        }
        ret s
    }
    let y = z[6usize..6usize + n]
    let xs = z[6usize + n..6usize + n + n * k]
    let o = 6usize + n + n * k
    if str.eq(c.name, "probit") || str.eq(c.name, "probitml") {
        let (out, e3) = mem.alloc[f64](a, nstore * k)
        if e3 != ok { ret nan }
        var ml = 0.0f64
        if md.probit(a, &g, y, xs, n, k, z[o..o + k], z[o + k..o + 2usize * k], z[o + 2usize * k..o + 2usize * k + k * k], burn, mc, thin, str.eq(c.name, "probitml"), out, &ml) != ok { ret nan }
        if str.eq(c.name, "probitml") { ret ml }
        ret wsum(out)
    }
    let (out, e2) = mem.alloc[f64](a, nstore * k)
    if e2 != ok { ret nan }
    var kind = 0usize
    if str.eq(c.name, "pois") { kind = 1usize }
    if ms.metrop_glm(a, &g, kind, y, xs, n, k, z[o..o + k], z[o + k..o + 2usize * k], z[o + 2usize * k..o + 3usize * k], z[o + 3usize * k..o + 3usize * k + k * k], z[o + 3usize * k + k * k..o + 3usize * k + 2usize * k * k], burn, mc, thin, out) != ok { ret nan }
    ret wsum(out)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmcpacksamp.json")
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
