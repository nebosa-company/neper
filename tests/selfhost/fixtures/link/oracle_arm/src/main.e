// e.algo.stat.arm against arm. tests/oracle/arm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R arm`; the layout is at the top of scripts/r_oracle/groups/arm.R.

use e.algo.rand.r as rng
use e.algo.stat.arm as arm
use e.algo.stat.armglm as ag
use e.algo.stat.carlmtest as ols
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn stdlm_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let q = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, q + 1usize)
    let (kd, e1) = mem.alloc[f64](a, q)
    if e != ok || e1 != ok { os.exit(20) }
    var t = 0usize
    while t < q {
        kd[t] = 0.0f64
        t += 1usize
    }
    if ag.standardize_fit(a, x[2usize + n..2usize + n + n * q], x[2usize..2usize + n], n, q, kd, kd, false, 0usize, 255usize, 0usize, o) == 0usize { os.exit(21) }
    ret o[usize(x[2usize + n + n * q])]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "logit") { ret arm.logit(x[0usize]) }
    if str.eq(k, "simlm") || str.eq(k, "simlmc") {
        let ns = usize(x[1usize])
        let n = usize(x[2usize])
        let q = usize(x[3usize])
        let (sg, e1) = mem.alloc[f64](a, ns)
        let (bt, e2) = mem.alloc[f64](a, ns * q)
        if e1 != ok || e2 != ok { os.exit(30) }
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        if arm.sim_lm(a, &g, x[4usize + n..4usize + n + n * q], x[4usize..4usize + n], n, q, ns, sg, bt) != ok { os.exit(31) }
        let at = usize(x[4usize + n + n * q + 1usize])
        if str.eq(k, "simlmc") { ret bt[at * q + usize(x[4usize + n + n * q + 2usize])] }
        if x[4usize + n + n * q] == 0.0f64 { ret sg[at] }
        let (ff, fe) = ols.ols(a, x[4usize + n..4usize + n + n * q], x[4usize..4usize + n], n, q)
        if fe != ok { os.exit(32) }
        var dev = 0.0f64
        var j = 0usize
        while j < q {
            let dj = bt[at * q + j] - ff.beta[j]
            dev += dj * dj
            j += 1usize
        }
        ret dev
    }
    if str.eq(k, "invlogit") { ret arm.invlogit(x[0usize]) }
    if str.eq(k, "stdlm") { ret stdlm_answer(a, c) }
    if str.eq(k, "stdglm") {
        let n = usize(x[0usize])
        let q = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, q + 1usize)
        let (kd, e1) = mem.alloc[f64](a, q)
        if e != ok || e1 != ok { os.exit(22) }
        var t = 0usize
        while t < q {
            kd[t] = 0.0f64
            t += 1usize
        }
        var link = 3usize
        if usize(x[2usize]) == 2usize { link = 1usize }
        if ag.standardize_fit(a, x[3usize + n..3usize + n + n * q], x[3usize..3usize + n], n, q, kd, kd, false, 0usize, usize(x[2usize]), link, o) == 0usize { os.exit(23) }
        ret o[usize(x[3usize + n + n * q])]
    }
    if str.eq(k, "bayesglm") || str.eq(k, "bayesglm2") || str.eq(k, "bayesglm3") {
        let n = usize(x[0usize])
        var pdf = 1.0f64
        var psc = 2.5f64
        if str.eq(k, "bayesglm2") {
            pdf = x[3usize + usize(x[0usize]) * usize(x[1usize]) + usize(x[0usize]) + 1usize]
            psc = x[3usize + usize(x[0usize]) * usize(x[1usize]) + usize(x[0usize]) + 2usize]
        }
        let kk = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, kk)
        let (pm, e1) = mem.alloc[f64](a, kk)
        let (pd, e2) = mem.alloc[f64](a, kk)
        let (pc, e3) = mem.alloc[f64](a, kk)
        if e != ok || e1 != ok || e2 != ok || e3 != ok { os.exit(30) }
        let base = 3usize + n * kk + n
        var jj = 0usize
        while jj < kk {
            pm[jj] = 0.0f64
            pd[jj] = pdf
            pc[jj] = psc
            if jj == 0usize {
                pd[jj] = 1.0f64
                pc[jj] = 10.0f64
                if usize(x[2usize]) == 3usize { pc[jj] = 16.0f64 }
            }
            if str.eq(k, "bayesglm3") {
                pm[jj] = x[base + 1usize + jj]
                pd[jj] = x[base + 1usize + kk + jj]
                pc[jj] = x[base + 1usize + 2usize * kk + jj]
            }
            jj += 1usize
        }
        // the older family codes: 0 gaussian, 1 binomial logit, 2 poisson log, 3 binomial probit, 4 binomial cloglog
        let code = usize(x[2usize])
        var fam = 1usize
        var link = 3usize
        if code == 0usize {
            fam = 0usize
            link = 0usize
        }
        if code == 2usize {
            fam = 2usize
            link = 1usize
        }
        if code == 3usize { link = 4usize }
        if code == 4usize { link = 6usize }
        var nowt: []const f64 = x[0usize..0usize]
        var nocov: []f64 = zero
        let (info, e4) = mem.alloc[f64](a, 4usize)
        if e4 != ok { os.exit(31) }
        if ag.bayesglm_gen(a, x[3usize..3usize + n * kk], x[3usize + n * kk..3usize + n * kk + n], n, kk, fam, link, nowt, nowt, pm, pd, pc, true, true, o, info, nocov) == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[usize(x[base])]
    }
    if str.eq(k, "rescale") {
        let n = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { os.exit(8) }
        if ag.rescale_gen(a, x[2usize..2usize + n], n, usize(x[0usize]), false, o) != ok { os.exit(9) }
        ret o[usize(x[2usize + n])]
    }
    if str.eq(k, "se") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, p)
        if e != ok { os.exit(5) }
        if arm.se_coef(a, x[2usize..2usize + n * p], x[2usize + n * p..2usize + n * p + n], n, p, o) != ok { os.exit(6) }
        ret o[usize(x[2usize + n * p + n])]
    }
    let nc = usize(x[0usize])
    let n = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, (nc + 1usize) * 6usize)
    if e != ok { os.exit(7) }
    let rows = arm.binned_resids(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], nc, o)
    if str.eq(k, "binned_rows") { ret f64(rows) }
    let cc = usize(x[2usize + 2usize * n])
    let b = usize(x[3usize + 2usize * n])
    if b >= rows { ret 0.0f64 - 1.0f64 }
    ret o[b * 6usize + cc]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/arm.json")
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
