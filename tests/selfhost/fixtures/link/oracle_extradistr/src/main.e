// e.algo.stat.extradistr against extraDistr. tests/oracle/extradistr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R extradistr`; the layout is at the top of scripts/r_oracle/groups/extradistr.R.

use e.algo.stat.extradistr as ed
use e.io
use e.mem
use e.os
use e.algo.rand.r as rng
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "rg") {
        var rg: rng.Rng = zero
        rng.seed(&rg, i64(x[1usize]))
        var v = 0.0f64
        var q = 0usize
        while q <= usize(x[5usize]) {
            v = ed.rgen(&rg, usize(x[0usize]), x[2usize], x[3usize], x[4usize])
            q += 1usize
        }
        ret v
    }
    if str.eq(c.name, "d2") || str.eq(c.name, "p2") || str.eq(c.name, "q2") {
        let d2 = usize(x[0usize])
        let u1 = x[1usize]
        let u2 = x[2usize]
        let u3 = x[3usize]
        let u4 = x[4usize]
        let vv = x[5usize]
        let id2 = str.eq(c.name, "d2")
        let ip2 = str.eq(c.name, "p2")
        if d2 == 0usize {
            if id2 { ret ed.maxwell_d(vv, u1) }
            if ip2 { ret ed.maxwell_p(vv, u1) }
            ret ed.maxwell_q(vv, u1)
        }
        if d2 == 1usize {
            if id2 { ret ed.bbinom_d(vv, u1, u2, u3) }
            ret ed.bbinom_p(vv, u1, u2, u3)
        }
        if d2 == 2usize {
            if id2 { ret ed.bnbinom_d(vv, u1, u2, u3) }
            ret ed.bnbinom_p(vv, u1, u2, u3)
        }
        if d2 == 3usize {
            if id2 { ret ed.dlaplace_d(vv, u1) }
            ret ed.dlaplace_p(vv, u1)
        }
        if d2 == 4usize {
            if id2 { ret ed.lgser_d(vv, u1) }
            ret ed.lgser_p(vv, u1)
        }
        if id2 { ret ed.tnorm_d(vv, u1, u2, u3, u4) }
        if ip2 { ret ed.tnorm_p(vv, u1, u2, u3, u4) }
        ret ed.tnorm_q(vv, u1, u2, u3, u4)
    }
    if str.eq(c.name, "c3") {
        let d3 = usize(x[0usize])
        let w1 = x[1usize]
        let w2 = x[2usize]
        let w3 = x[3usize]
        let vx = x[4usize]
        if d3 == 0usize { ret ed.zip_p(vx, w1, w2) }
        if d3 == 1usize { ret ed.zib_p(vx, w1, w2, w3) }
        if d3 == 2usize { ret ed.zinb_p(vx, w1, w2, w3) }
        if d3 == 3usize { ret ed.gpois_p(vx, w1, w2) }
        ret ed.tpois_p(vx, w1, w2, w3)
    }
    if str.eq(c.name, "c4") {
        let d4 = usize(x[0usize])
        let q1 = x[1usize]
        let q2 = x[2usize]
        let q3 = x[3usize]
        let q4 = x[4usize]
        let qv = x[5usize]
        if d4 == 0usize { ret ed.tbinom_p(qv, q1, q2, q3, q4) }
        if d4 == 1usize { ret ed.nsbeta_p(qv, q1, q2, q3, q4) }
        if d4 == 2usize { ret ed.ht_p(qv, q1, q2) }
        ret ed.sgomp_p(qv, q1, q2)
    }
    if str.eq(c.name, "k3") {
        let d3 = usize(x[0usize])
        let w1 = x[1usize]
        let w2 = x[2usize]
        let w3 = x[3usize]
        let vx = x[4usize]
        if d3 == 0usize { ret ed.zip_q(vx, w1, w2) }
        if d3 == 1usize { ret ed.zib_q(vx, w1, w2, w3) }
        if d3 == 2usize { ret ed.zinb_q(vx, w1, w2, w3) }
        ret ed.tpois_q(vx, w1, w2, w3)
    }
    if str.eq(c.name, "k4") {
        let d4 = usize(x[0usize])
        let q1 = x[1usize]
        let q2 = x[2usize]
        let q3 = x[3usize]
        let q4 = x[4usize]
        let qv = x[5usize]
        if d4 == 0usize { ret ed.tbinom_q(qv, q1, q2, q3, q4) }
        if d4 == 1usize { ret ed.nsbeta_q(qv, q1, q2, q3, q4) }
        ret ed.ht_q(qv, q1, q2)
    }
    if str.eq(c.name, "m4") {
        // (dist, p1, p2, p3, kind 0 d 1 p 2 q, v): 0 gev 1 gpd 2 dunif 3 bern 4 dweibull 5 lst 6 invchisq
        let d5 = usize(x[0usize])
        let r1 = x[1usize]
        let r2 = x[2usize]
        let r3 = x[3usize]
        let kd = usize(x[4usize])
        let rv = x[5usize]
        if d5 == 0usize {
            if kd == 0usize { ret ed.gev_d(rv, r1, r2, r3) }
            if kd == 1usize { ret ed.gev_p(rv, r1, r2, r3) }
            ret ed.gev_q(rv, r1, r2, r3)
        }
        if d5 == 1usize {
            if kd == 0usize { ret ed.gpd_d(rv, r1, r2, r3) }
            if kd == 1usize { ret ed.gpd_p(rv, r1, r2, r3) }
            ret ed.gpd_q(rv, r1, r2, r3)
        }
        if d5 == 2usize {
            if kd == 0usize { ret ed.dunif_d(rv, r1, r2) }
            ret ed.dunif_p(rv, r1, r2)
        }
        if d5 == 3usize { ret ed.bern_d(rv, r1) }
        if d5 == 4usize {
            if kd == 0usize { ret ed.dweib_d(rv, r1, r2) }
            ret ed.dweib_p(rv, r1, r2)
        }
        if d5 == 5usize {
            if kd == 0usize { ret ed.lst_d(rv, r1, r2, r3) }
            if kd == 1usize { ret ed.lst_p(rv, r1, r2, r3) }
            ret ed.lst_q(rv, r1, r2, r3)
        }
        if kd == 0usize { ret ed.invchisq_d(rv, r1, r2) }
        if kd == 1usize { ret ed.invchisq_p(rv, r1, r2) }
        ret ed.invchisq_q(rv, r1, r2)
    }
    if str.eq(c.name, "m6") {
        // (dist, kind 0 d 1 p, p1..p4, a1, v): 0 ddnorm 1 ddgamma 2 huber 3 mixnorm 4 mixpois
        let d6 = usize(x[0usize])
        let kd = usize(x[1usize])
        let r1 = x[2usize]
        let r2 = x[3usize]
        let r3 = x[4usize]
        let r4 = x[5usize]
        let r5 = x[6usize]
        let rv = x[7usize]
        if d6 == 0usize {
            if kd == 0usize { ret ed.ddnorm_d(rv, r1, r2) }
            ret ed.ddnorm_p(rv, r1, r2)
        }
        if d6 == 1usize {
            if kd == 0usize { ret ed.ddgamma_d(rv, r1, r2) }
            ret ed.ddgamma_p(rv, r1, r2)
        }
        if d6 == 2usize {
            if kd == 0usize { ret ed.huber_d(rv, r1, r2, r3) }
            ret ed.huber_p(rv, r1, r2, r3)
        }
        if d6 == 3usize { ret ed.mixnorm2_d(rv, r1, r2, r3, r4, r5) }
        ret ed.mixpois2_d(rv, r1, r2, r5)
    }
    if str.eq(c.name, "mv") {
        // (dist, k, size, x[k], par[k]): 0 dirichlet(par = alpha) 1 mnom(prob) 2 dirmnom(alpha) 3 mvhyper(n, size = k draws)
        let d7 = usize(x[0usize])
        let k = usize(x[1usize])
        let xs = x[3usize..3usize + k]
        let ps = x[3usize + k..3usize + k + k]
        if d7 == 0usize { ret ed.dirichlet_d(xs, ps) }
        if d7 == 1usize { ret ed.mnom_d(xs, x[2usize], ps) }
        if d7 == 2usize { ret ed.dirmnom_d(xs, x[2usize], ps) }
        ret ed.mvhyper_d(xs, ps, x[2usize])
    }
    if str.eq(c.name, "bv") {
        // (dist, v1..v7): 0 bvnorm(x, y, m1, m2, s1, s2, r) 1 bvpois(x, y, a, b, c)
        if usize(x[0usize]) == 0usize { ret ed.bvnorm_d(x[1usize], x[2usize], x[3usize], x[4usize], x[5usize], x[6usize], x[7usize]) }
        ret ed.bvpois_d(x[1usize], x[2usize], x[3usize], x[4usize], x[5usize])
    }
    if str.eq(c.name, "d3") {
        let d3 = usize(x[0usize])
        let w1 = x[1usize]
        let w2 = x[2usize]
        let w3 = x[3usize]
        let vx = x[4usize]
        if d3 == 0usize { ret ed.zip_d(vx, w1, w2) }
        if d3 == 1usize { ret ed.zib_d(vx, w1, w2, w3) }
        if d3 == 2usize { ret ed.zinb_d(vx, w1, w2, w3) }
        if d3 == 3usize { ret ed.gpois_d(vx, w1, w2) }
        if d3 == 5usize { ret ed.skellam_d(vx, w1, w2) }
        ret ed.tpois_d(vx, w1, w2, w3)
    }
    if str.eq(c.name, "d4") {
        let d4 = usize(x[0usize])
        let q1 = x[1usize]
        let q2 = x[2usize]
        let q3 = x[3usize]
        let q4 = x[4usize]
        let qv = x[5usize]
        if d4 == 0usize { ret ed.tbinom_d(qv, q1, q2, q3, q4) }
        if d4 == 1usize { ret ed.nsbeta_d(qv, q1, q2, q3, q4) }
        if d4 == 2usize { ret ed.ht_d(qv, q1, q2) }
        if d4 == 3usize { ret ed.slash_d(qv, q1, q2) }
        ret ed.sgomp_d(qv, q1, q2)
    }
    let di = usize(x[0usize])
    let a = x[1usize]
    let b = x[2usize]
    let g = x[3usize]
    let v = x[4usize]
    let k = c.name
    let isd = str.eq(k, "d")
    let isp = str.eq(k, "p")
    if di == 0usize {
        if isd { ret ed.gumbel_d(v, a, b) }
        if isp { ret ed.gumbel_p(v, a, b) }
        ret ed.gumbel_q(v, a, b)
    }
    if di == 1usize {
        if isd { ret ed.frechet_d(v, a, b, g) }
        if isp { ret ed.frechet_p(v, a, b, g) }
        ret ed.frechet_q(v, a, b, g)
    }
    if di == 2usize {
        if isd { ret ed.kumar_d(v, a, b) }
        if isp { ret ed.kumar_p(v, a, b) }
        ret ed.kumar_q(v, a, b)
    }
    if di == 3usize {
        if isd { ret ed.laplace_d(v, a, b) }
        if isp { ret ed.laplace_p(v, a, b) }
        ret ed.laplace_q(v, a, b)
    }
    if di == 4usize {
        if isd { ret ed.lomax_d(v, a, b) }
        if isp { ret ed.lomax_p(v, a, b) }
        ret ed.lomax_q(v, a, b)
    }
    if di == 5usize {
        if isd { ret ed.pareto_d(v, a, b) }
        if isp { ret ed.pareto_p(v, a, b) }
        ret ed.pareto_q(v, a, b)
    }
    if di == 6usize {
        if isd { ret ed.rayleigh_d(v, a) }
        if isp { ret ed.rayleigh_p(v, a) }
        ret ed.rayleigh_q(v, a)
    }
    if di == 7usize {
        if isd { ret ed.triang_d(v, a, b, g) }
        if isp { ret ed.triang_p(v, a, b, g) }
        ret ed.triang_q(v, a, b, g)
    }
    if di == 8usize {
        if isd { ret ed.gompertz_d(v, a, b) }
        if isp { ret ed.gompertz_p(v, a, b) }
        ret ed.gompertz_q(v, a, b)
    }
    if di == 9usize {
        if isd { ret ed.power_d(v, a, b) }
        if isp { ret ed.power_p(v, a, b) }
        ret ed.power_q(v, a, b)
    }
    if di == 10usize {
        if isd { ret ed.invgamma_d(v, a, b) }
        if isp { ret ed.invgamma_p(v, a, b) }
        ret ed.invgamma_q(v, a, b)
    }
    if di == 11usize {
        if isd { ret ed.hnorm_d(v, a) }
        if isp { ret ed.hnorm_p(v, a) }
        ret ed.hnorm_q(v, a)
    }
    if di == 12usize {
        if isd { ret ed.hcauchy_d(v, a) }
        if isp { ret ed.hcauchy_p(v, a) }
        ret ed.hcauchy_q(v, a)
    }
    if di == 13usize {
        if isd { ret ed.fatigue_d(v, a, b, g) }
        if isp { ret ed.fatigue_p(v, a, b, g) }
        ret ed.fatigue_q(v, a, b, g)
    }
    if di == 14usize {
        if isd { ret ed.wald_d(v, a, b) }
        ret ed.wald_p(v, a, b)
    }
    if isd { ret ed.betapr_d(v, a, b, g) }
    if isp { ret ed.betapr_p(v, a, b, g) }
    ret ed.betapr_q(v, a, b, g)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/extradistr.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
