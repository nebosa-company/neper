// e.algo.stat.margeff against marginaleffects. tests/oracle/margeff.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R margeff`; the layout is at the top of scripts/r_oracle/groups/margeff.R.

use e.algo.stat.margeff as mf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if str.eq(c.name, "mtab") {
        let pt = usize(z[0usize])
        var ot: [5]f64 = zero
        mf.glm_margin(usize(z[1usize]), z[5usize + pt + pt * pt..5usize + pt + pt * pt + pt], z[5usize..5usize + pt], z[5usize + pt..5usize + pt + pt * pt], pt, z[2usize], z[3usize], ot[0usize..5usize])
        ret ot[usize(z[4usize])]
    }
    if str.eq(c.name, "mcon") {
        let nc = usize(z[0usize])
        let pc = usize(z[1usize])
        let (oc, ec) = mem.alloc[f64](a, 2usize)
        if ec != ok { ret nan }
        let hc = 5usize
        let bc = hc + 2usize * pc
        mf.glm_contrast(a, usize(z[2usize]), usize(z[3usize]), z[bc + pc + pc * pc..bc + pc + pc * pc + nc * pc], z[bc..bc + pc], z[bc + pc..bc + pc + pc * pc], nc, pc, z[hc..hc + pc], z[hc + pc..hc + 2usize * pc], oc)
        ret oc[usize(z[4usize])]
    }
    if str.eq(c.name, "mrow") {
        let nw = usize(z[0usize])
        let pw = usize(z[1usize])
        let (ow, ew) = mem.alloc[f64](a, 2usize)
        if ew != ok { ret nan }
        let bw = 7usize
        let kw = usize(z[5usize])
        if kw >= 3usize {
            mf.glm_row_ratio(a, usize(z[4usize]), kw - 3usize, z[bw + pw + pw * pw..bw + pw + pw * pw + nw * pw], z[bw..bw + pw], z[bw + pw..bw + pw + pw * pw], nw, pw, usize(z[2usize]), usize(z[6usize]), ow)
        } else {
            mf.glm_row(a, usize(z[4usize]), kw, z[bw + pw + pw * pw..bw + pw + pw * pw + nw * pw], z[bw..bw + pw], z[bw + pw..bw + pw + pw * pw], nw, pw, usize(z[2usize]), usize(z[6usize]), ow)
        }
        ret ow[usize(z[3usize])]
    }
    if str.eq(c.name, "mrat") {
        let nr = usize(z[0usize])
        let pr = usize(z[1usize])
        let (orr, er) = mem.alloc[f64](a, 2usize)
        if er != ok { ret nan }
        let b1 = 5usize
        mf.glm_avg_ratio(a, usize(z[2usize]), usize(z[3usize]), z[b1 + pr + pr * pr..b1 + pr + pr * pr + nr * pr], z[b1..b1 + pr], z[b1 + pr..b1 + pr + pr * pr], nr, pr, 1usize, orr)
        ret orr[usize(z[4usize])]
    }
    if str.eq(c.name, "mhyp") {
        let ph = usize(z[0usize])
        var oh: [4]f64 = zero
        mf.lin_hypothesis(z[2usize..2usize + ph], z[2usize + ph..2usize + ph + ph * ph], z[2usize + ph + ph * ph..2usize + ph + ph * ph + ph], z[1usize], ph, oh[0usize..4usize])
        ret oh[usize(z[2usize + ph + ph * ph + ph])]
    }
    if str.eq(c.name, "mpred") {
        let pp = usize(z[0usize])
        let (op, ep) = mem.alloc[f64](a, 2usize)
        if ep != ok { ret nan }
        mf.glm_pred(usize(z[1usize]), z[2usize + pp + pp * pp..2usize + pp + pp * pp + pp], z[2usize..2usize + pp], z[2usize + pp..2usize + pp + pp * pp], pp, op)
        ret op[usize(z[2usize + pp + pp * pp + pp])]
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let (o, e) = mem.alloc[f64](a, 2usize)
    if e != ok { ret nan }
    // args: (n, p, j, which, link, kind, beta[p], vcov[p p], X[n p])
    let b0 = 6usize
    mf.glm_avg(a, usize(z[4usize]), usize(z[5usize]), z[b0 + p + p * p..b0 + p + p * p + n * p], z[b0..b0 + p], z[b0 + p..b0 + p + p * p], n, p, usize(z[2usize]), o)
    ret o[usize(z[3usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/margeff.json")
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
