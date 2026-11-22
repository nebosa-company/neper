// e.algo.stat.actuar against actuar, second group: ruin with phase-type waiting times, adjCoef, base-law moments and mgfs, Pareto II to Feller-Pareto, barycenter regression credibility, iterative Buhlmann-Straub. tests/oracle/actuar2.json comes from scripts/r_oracle/groups/actuar2.R.


use e.algo.stat.actuar as ac
use e.io
use e.math
use e.mem
use e.os
use e.algo.rand.r as rr
use e.str
use e.test.oracle as oracle

fn answer(ar: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "rpp") {
        let rn = usize(x[0usize])
        let rm = usize(x[1usize + rn + rn * rn])
        let ob = 2usize + rn + rn * rn
        ret ac.ruin_ph_ph(ar, x[1usize..1usize + rn], x[1usize + rn..1usize + rn + rn * rn], rn, x[ob..ob + rm], x[ob + rm..ob + rm + rm * rm], rm, x[ob + rm + rm * rm + 1usize], x[ob + rm + rm * rm])
    }
    if str.eq(c.name, "rph") {
        var gp: rr.Rng = zero
        rr.seed(&gp, i64(x[0usize]))
        let pn = usize(x[1usize])
        let pm = usize(x[2usize])
        var pt = 0.0f64
        var pi = 0usize
        while pi < pn {
            pt += ac.rphtype1(&gp, x[3usize..3usize + pm], x[3usize + pm..3usize + pm + pm * pm], pm) * f64(pi + 1usize)
            pi += 1usize
        }
        ret pt
    }
    if str.eq(c.name, "pg") {
        if x[3usize] == 0.0f64 { ret ac.pig_d(x[2usize], x[0usize], x[1usize]) }
        ret ac.pig_p(x[2usize], x[0usize], x[1usize])
    }
    if str.eq(c.name, "bm") { ret ac.bm(usize(x[0usize]), usize(x[1usize]), x[2usize], x[3usize], x[4usize], x[5usize]) }
    if str.eq(c.name, "mp") {
        let pm = usize(x[0usize])
        ret ac.ph_mgf(ar, x[1usize..1usize + pm], x[1usize + pm..1usize + pm + pm * pm], pm, x[1usize + pm + pm * pm])
    }
    if str.eq(c.name, "sh") {
        let sk = usize(x[0usize])
        var sa = x[2usize]
        var sg = 1.0f64
        var stt = 1.0f64
        if sk == 1usize { sa = 1.0f64
            sg = x[2usize] }
        if sk == 2usize { sg = x[3usize] }
        if sk == 3usize {
            sg = x[3usize]
            stt = x[4usize]
        }
        let smn = x[1usize]
        let ssc = x[5usize]
        let sst = usize(x[8usize])
        if sst == 0usize { ret ac.sh_d(x[6usize], smn, sa, sg, stt, ssc) }
        if sst == 1usize { ret ac.sh_p(x[6usize], smn, sa, sg, stt, ssc) }
        if sst == 2usize { ret ac.sh_q(x[6usize], smn, sa, sg, stt, ssc) }
        if sst == 3usize { ret ac.sh_m(x[7usize], smn, sa, sg, stt, ssc) }
        ret ac.sh_lev(x[6usize], x[7usize], smn, sa, sg, stt, ssc)
    }
    if str.eq(c.name, "shr") {
        var gs: rr.Rng = zero
        rr.seed(&gs, i64(x[0usize]))
        let sn = usize(x[7usize])
        var ts = 0.0f64
        var si = 0usize
        while si < sn {
            ts += ac.sh_rand(&gs, usize(x[1usize]), x[2usize], x[3usize], x[4usize], x[5usize], x[6usize]) * f64(si + 1usize)
            si += 1usize
        }
        ret ts
    }
    if str.eq(c.name, "adj") {
        var ctx = ac.AdjCtx { mode: usize(x[0usize]), ck: usize(x[1usize]), c1: x[2usize], c2: x[3usize], wk: usize(x[4usize]), w1: x[5usize], w2: x[6usize], pa: x[7usize], pb: x[8usize], y: x[9usize] }
        if ctx.mode == 0usize { ret ac.adj_coef(&ctx, x[10usize]) }
        ret ac.adj_coef_re(ar, &ctx, x[10usize], x[11usize], x[12usize], usize(x[13usize]), x[14usize])
    }
    if str.eq(c.name, "cmi") {
        let ci = usize(x[0usize])
        var cn = 0usize
        var cii = 0usize
        let (cns, ce1) = mem.alloc[usize](ar, ci)
        if ce1 != ok { os.exit(43) }
        while cii < ci {
            cns[cii] = usize(x[1usize + cii])
            cn += cns[cii]
            cii += 1usize
        }
        var co4: [4]f64 = zero
        if ac.cm_bs_iter(ar, cns, x[1usize + ci..1usize + ci + cn], x[1usize + ci + cn..1usize + ci + 2usize * cn], co4[0usize..4usize]) != ok { os.exit(44) }
        ret co4[usize(x[1usize + ci + 2usize * cn])]
    }
    ret 0.0f64 / 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/actuar2.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
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
