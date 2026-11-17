// e.algo.stat.bayesmpkg against bayesm. tests/oracle/bayesm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R bayesm`; the layout is at the top of scripts/r_oracle/groups/bayesm.R.

use e.algo.rand.r as rng
use e.algo.stat.bayesmpkg as bz
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "mvn") {
        let k = usize(z[0usize])
        ret bz.lnd_mvn(a, z[1usize..1usize + k], z[1usize + k..1usize + 2usize * k], z[1usize + 2usize * k..1usize + 2usize * k + k * k], k)
    }
    if str.eq(c.name, "mvst") {
        let k = usize(z[0usize])
        ret bz.lnd_mvst(a, z[3usize..3usize + k], z[1usize], z[3usize + k..3usize + 2usize * k], z[3usize + 2usize * k..3usize + 2usize * k + k * k], k, z[2usize] != 0.0f64)
    }
    if str.eq(c.name, "iw") {
        let k = usize(z[0usize])
        ret bz.lnd_iwishart(a, z[1usize], z[2usize..2usize + k * k], z[2usize + k * k..2usize + 2usize * k * k], k)
    }
    if str.eq(c.name, "ic") { ret bz.lnd_ichisq(z[0usize], z[1usize], z[2usize]) }
    if str.eq(c.name, "mn") {
        let k = usize(z[0usize])
        let p = usize(z[1usize])
        let n = usize(z[2usize])
        ret bz.llmnl(z[3usize..3usize + k], z[3usize + k..3usize + k + n], z[3usize + k + n..3usize + k + n + n * p * k], k, p)
    }
    if str.eq(c.name, "mh") {
        let k = usize(z[0usize])
        let p = usize(z[1usize])
        let n = usize(z[2usize])
        let (o, oe) = mem.alloc[f64](a, k * k)
        if oe != ok { ret 0.0f64 / 0.0f64 }
        if bz.mnl_hess(a, z[4usize..4usize + k], z[4usize + k + n..4usize + k + n + n * p * k], k, p, n, o) != ok { ret 0.0f64 / 0.0f64 }
        ret o[usize(z[3usize])]
    }
    if str.eq(c.name, "ne") {
        let nn = usize(z[0usize])
        let (o, oe) = mem.alloc[f64](a, 2usize)
        if oe != ok { ret 0.0f64 / 0.0f64 }
        bz.num_eff(z[3usize..3usize + nn], usize(z[1usize]), o)
        ret o[usize(z[2usize])]
    }
    if str.eq(c.name, "mm") || str.eq(c.name, "md") {
        // (nc, k, q, x, prob[nc], mus[nc k], rootis[nc k k])
        let nc = usize(z[0usize])
        let k = usize(z[1usize])
        let pr = z[4usize..4usize + nc]
        let mus = z[4usize + nc..4usize + nc + nc * k]
        let rts = z[4usize + nc + nc * k..4usize + nc + nc * k + nc * k * k]
        if str.eq(c.name, "md") { ret bz.mix_den(a, z[3usize], pr, mus, rts, nc, k, usize(z[2usize])) }
        let (mo, e1) = mem.alloc[f64](a, k)
        let (so, e2) = mem.alloc[f64](a, k * k)
        if e1 != ok || e2 != ok { ret 0.0f64 / 0.0f64 }
        if bz.mix_mom(a, pr, mus, rts, nc, k, mo, so) != ok { ret 0.0f64 / 0.0f64 }
        let q = usize(z[2usize])
        if q < k { ret mo[q] }
        ret so[q - k]
    }
    if str.eq(c.name, "cx") {
        // (n, p, na, nd, base, q, Xa[n p na], Xd[n nd])
        let n = usize(z[0usize])
        let p = usize(z[1usize])
        let na = usize(z[2usize])
        let nd = usize(z[3usize])
        let (o, oe) = mem.alloc[f64](a, n * p * ((nd + 1usize) * (p - 1usize) + na))
        if oe != ok { ret 0.0f64 / 0.0f64 }
        bz.create_x(z[6usize..6usize + n * p * na], z[6usize + n * p * na..6usize + n * p * na + n * nd], n, p, na, nd, usize(z[4usize]), o)
        ret o[usize(z[5usize])]
    }
    if str.eq(c.name, "rmx") {
        // (seed, n, G, d, index, pvec[G], mus[G d], rootis[G d d]): element index of the n by d draw, or n d + i the component of observation i
        var rr: rng.Rng = zero
        rng.seed(&rr, i64(z[0usize]))
        let n = usize(z[1usize])
        let g = usize(z[2usize])
        let d = usize(z[3usize])
        let (o, oe) = mem.alloc[f64](a, n * d)
        let (lb, le) = mem.alloc[usize](a, n)
        if oe != ok || le != ok { ret 0.0f64 / 0.0f64 }
        if bz.rmixture(a, &rr, n, z[5usize..5usize + g], z[5usize + g..5usize + g + g * d], z[5usize + g + g * d..5usize + g + g * d + g * d * d], d, o, lb) != ok { ret 0.0f64 / 0.0f64 }
        let ix = usize(z[4usize])
        if ix < n * d { ret o[ix] }
        ret f64(lb[ix - n * d])
    }
    if str.eq(c.name, "cm") {
        let k = usize(z[1usize])
        let i = usize(z[2usize])
        let (m, v) = bz.cond_mom(z[3usize..3usize + k], z[3usize + k..3usize + 2usize * k], z[3usize + 2usize * k..3usize + 2usize * k + k * k], k, i)
        if z[0usize] == 0.0f64 { ret m }
        ret v
    }
    var r: rng.Rng = zero
    rng.seed(&r, i64(z[0usize]))
    if str.eq(c.name, "dir") {
        let m = usize(z[1usize])
        let (o, e) = mem.alloc[f64](a, m)
        if e != ok { ret nan }
        bz.rdirichlet(&r, z[2usize..2usize + m], o)
        ret o[usize(z[2usize + m])]
    }
    if str.eq(c.name, "trun") { ret bz.rtrun(&r, z[1usize], z[2usize], z[3usize], z[4usize]) }
    if str.eq(c.name, "wish") {
        let k = usize(z[1usize])
        let (w, e1) = mem.alloc[f64](a, k * k)
        let (iw, e2) = mem.alloc[f64](a, k * k)
        let (cc, e3) = mem.alloc[f64](a, k * k)
        let (ci, e4) = mem.alloc[f64](a, k * k)
        if e1 != ok || e2 != ok || e3 != ok || e4 != ok { ret nan }
        if bz.rwishart(a, &r, z[2usize], z[3usize..3usize + k * k], k, w, iw, cc, ci) != ok { ret nan }
        let id = usize(z[3usize + k * k])
        let blk = id / (k * k)
        let q = id % (k * k)
        if blk == 0usize { ret w[q] }
        if blk == 1usize { ret iw[q] }
        if blk == 2usize { ret cc[q] }
        ret ci[q]
    }
    if str.eq(c.name, "mreg") {
        let n = usize(z[1usize])
        let k = usize(z[2usize])
        let m = usize(z[3usize])
        let (ob, e1) = mem.alloc[f64](a, k * m)
        let (os2, e2) = mem.alloc[f64](a, m * m)
        if e1 != ok || e2 != ok { ret nan }
        let at = 5usize
        let ye = at + n * m
        let xe = ye + n * k
        let be = xe + k * m
        let ae = be + k * k
        let ve = ae + m * m
        if bz.rmultireg(a, &r, z[at..ye], z[ye..xe], z[xe..be], z[be..ae], z[4usize], z[ae..ve], n, k, m, ob, os2) != ok { ret nan }
        let id = usize(z[ve])
        if id < k * m { ret ob[id] }
        ret os2[id - k * m]
    }
    if str.eq(c.name, "ureg") {
        let n = usize(z[1usize])
        let k = usize(z[2usize])
        let nr = usize(z[3usize])
        let (ob, e1) = mem.alloc[f64](a, nr * k)
        let (os2, e2) = mem.alloc[f64](a, nr)
        if e1 != ok || e2 != ok { ret nan }
        let at = 6usize
        let xe = at + n + n * k
        let be = xe + k
        let ae = be + k * k
        if bz.runireg(a, &r, z[at..at + n], z[at + n..xe], z[xe..be], z[be..ae], z[4usize], z[5usize], n, k, nr, ob, os2) != ok { ret nan }
        let id = usize(z[ae])
        if id < nr * k { ret ob[id] }
        ret os2[id - nr * k]
    }
    if str.eq(c.name, "gibbs") {
        let n = usize(z[1usize])
        let k = usize(z[2usize])
        let nr = usize(z[3usize])
        let (ob, e1) = mem.alloc[f64](a, nr * k)
        let (os2, e2) = mem.alloc[f64](a, nr)
        if e1 != ok || e2 != ok { ret nan }
        let at = 7usize
        let xe = at + n + n * k
        let be = xe + k
        let ae = be + k * k
        if bz.runireg_gibbs(a, &r, z[at..at + n], z[at + n..xe], z[xe..be], z[be..ae], z[4usize], z[5usize], z[6usize], n, k, nr, ob, os2) != ok { ret nan }
        let id = usize(z[ae])
        if id < nr * k { ret ob[id] }
        ret os2[id - nr * k]
    }
    if str.eq(c.name, "breg") {
        let n = usize(z[1usize])
        let k = usize(z[2usize])
        let (o, e) = mem.alloc[f64](a, k)
        if e != ok { ret nan }
        let at = 3usize
        if bz.breg(a, &r, z[at..at + n], z[at + n..at + n + n * k], z[at + n + n * k..at + n + n * k + k], z[at + n + n * k + k..at + n + n * k + k + k * k], k, o) != ok { ret nan }
        ret o[usize(z[at + n + n * k + k + k * k])]
    }
    ret nan
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/bayesm.json")
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
