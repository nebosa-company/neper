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
