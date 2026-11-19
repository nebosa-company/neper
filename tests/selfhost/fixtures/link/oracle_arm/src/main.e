// e.algo.stat.arm against arm. tests/oracle/arm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R arm`; the layout is at the top of scripts/r_oracle/groups/arm.R.

use e.algo.rand.r as rng
use e.algo.stat.arm as arm
use e.algo.stat.carlmtest as ols
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn stdlm_answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let n = usize(x[0usize])
    let q = usize(x[1usize])
    let (o, e) = mem.alloc[f64](a, q + 1usize)
    if e != ok { os.exit(20) }
    if arm.standardize_lm(a, x[2usize + n..2usize + n + n * q], x[2usize..2usize + n], n, q, o) != ok { os.exit(21) }
    ret o[usize(x[2usize + n + n * q])]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "logit") { ret arm.logit(x[0usize]) }
    if str.eq(k, "simglm") {
        let ns = usize(x[1usize])
        let n = usize(x[2usize])
        let q = usize(x[3usize])
        let (bt, e2) = mem.alloc[f64](a, ns * q)
        let (bh, e3) = mem.alloc[f64](a, q)
        if e2 != ok || e3 != ok { os.exit(33) }
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        let ds = 5usize + n
        if arm.sim_glm(a, &g, x[ds..ds + n * q], x[5usize..ds], n, q, usize(x[4usize]), ns, bh, bt) != ok { os.exit(34) }
        let at = usize(x[ds + n * q + 1usize])
        if x[ds + n * q] == 1.0f64 { ret bh[at] }
        var dev = 0.0f64
        var j = 0usize
        while j < q {
            let dj = bt[at * q + j] - bh[j]
            dev += dj * dj
            j += 1usize
        }
        ret dev
    }
    if str.eq(k, "simlm") {
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
        if e != ok { os.exit(22) }
        if arm.standardize_glm(a, x[3usize + n..3usize + n + n * q], x[3usize..3usize + n], n, q, usize(x[2usize]), o) != ok { os.exit(23) }
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
        if arm.bayesglm(a, x[3usize..3usize + n * kk], x[3usize + n * kk..3usize + n * kk + n], n, kk, usize(x[2usize]), pm, pd, pc, o) == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[usize(x[base])]
    }
    if str.eq(k, "rescale") {
        let n = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { os.exit(8) }
        arm.rescale(x[2usize..2usize + n], n, usize(x[0usize]), o)
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
