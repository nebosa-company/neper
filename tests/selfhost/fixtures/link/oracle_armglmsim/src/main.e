// e.algo.stat.armglm sim() on glm and bayesglm against arm. tests/oracle/armglmsim.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R armglm`; the layout of a case is in scripts/r_oracle/groups/armglm.R.

use e.algo.rand.r as rng
use e.algo.stat.armglm as ag
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "simglm2") {
        let ns = usize(x[1usize])
        let n = usize(x[2usize])
        let k = usize(x[3usize])
        var at = 8usize
        let y = x[at..at + n]
        at += n
        let xm = x[at..at + n * k]
        at += n * k
        let pm = x[at..at + k]
        let pd = x[at + k..at + 2usize * k]
        let ps = x[at + 2usize * k..at + 3usize * k]
        at += 3usize * k
        let (bt, e1) = mem.alloc[f64](a, ns * k)
        let (bh, e2) = mem.alloc[f64](a, k)
        let (sg, e3) = mem.alloc[f64](a, ns)
        if e1 != ok || e2 != ok || e3 != ok { os.exit(14) }
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        let nowt: []const f64 = x[0usize..0usize]
        if x[at] >= 3.0f64 {
            let (cu, e4) = mem.alloc[f64](a, k * k)
            let (vm, e5) = mem.alloc[f64](a, k * k)
            let (inf, e6) = mem.alloc[f64](a, 5usize)
            if e4 != ok || e5 != ok || e6 != ok { os.exit(16) }
            if x[6usize] == 1.0f64 {
                let it = ag.bayesglm_gen(a, xm, y, n, k, usize(x[4usize]), usize(x[5usize]), nowt, nowt, pm, pd, ps, true, true, bh, inf, cu)
                if it == 0usize { ret 0.0f64 / 0.0f64 }
            } else {
                let it = ag.glm_fit_gen(a, xm, y, n, k, usize(x[4usize]), usize(x[5usize]), nowt, nowt, true, bh, cu, inf)
                if it == 0usize { ret 0.0f64 / 0.0f64 }
            }
            if x[at] == 4.0f64 { ret inf[0usize] }
            if x[at] == 5.0f64 { ret cu[usize(x[at + 1usize])] }
            if x[at] == 6.0f64 { ret bh[usize(x[at + 1usize])] }
            ag.vbeta_from(cu, inf[0usize], k, vm)
            var s = 0.0f64
            var t = 0usize
            while t < k {
                s += f64(t + 1usize) * vm[usize(x[at + 1usize]) * k + t]
                t += 1usize
            }
            ret s
        }
        var r = ok
        if x[6usize] == 1.0f64 {
            r = ag.sim_bayesglm(a, &g, xm, y, n, k, usize(x[4usize]), usize(x[5usize]), nowt, nowt, pm, pd, ps, x[7usize] == 1.0f64, ns, bh, bt, sg)
        } else {
            r = ag.sim_glm_gen(a, &g, xm, y, n, k, usize(x[4usize]), usize(x[5usize]), nowt, nowt, ns, bh, bt, sg)
        }
        if r != ok { ret 0.0f64 / 0.0f64 }
        let wh = usize(x[at])
        let from = usize(x[at + 1usize])
        let len = usize(x[at + 2usize])
        var s = 0.0f64
        var t = 0usize
        while t < len {
            var v = 0.0f64
            if wh == 0usize { v = sg[t] }
            if wh == 1usize { v = bt[from * k + t] }
            if wh == 2usize { v = bh[t] }
            s += f64(t + 1usize) * v
            t += 1usize
        }
        ret s
    }
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/armglmsim.json")
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
