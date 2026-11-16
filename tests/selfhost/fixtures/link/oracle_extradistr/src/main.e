// e.algo.stat.extradistr against extraDistr. tests/oracle/extradistr.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R extradistr`; the layout is at the top of scripts/r_oracle/groups/extradistr.R.

use e.algo.stat.extradistr as ed
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(c: *const oracle.Case) -> f64 {
    let x = c.args
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
