// e.algo.stat.armglm against arm's bayesglm. tests/oracle/armglm.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R armglm`; the layout of a case is at the top of scripts/r_oracle/groups/armglm.R.

use e.algo.rand.r as rng
use e.algo.stat.armglm as ag
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    if str.eq(c.name, "dispglm") {
        let n = usize(x[0usize])
        let k = usize(x[1usize])
        var at = 5usize
        let y = x[at..at + n]
        at += n
        let xm = x[at..at + n * k]
        at += n * k
        let pm = x[at..at + k]
        let pd = x[at + k..at + 2usize * k]
        let ps = x[at + 2usize * k..at + 3usize * k]
        at += 3usize * k
        let (o, e1) = mem.alloc[f64](a, 6usize + 4usize * k)
        if e1 != ok { os.exit(15) }
        let nowt: []const f64 = x[0usize..0usize]
        var r = ok
        if x[4usize] == 1.0f64 {
            r = ag.display_bayesglm(a, xm, y, n, k, usize(x[2usize]), usize(x[3usize]), nowt, nowt, pm, pd, ps, true, o)
        } else {
            r = ag.display_glm(a, xm, y, n, k, usize(x[2usize]), usize(x[3usize]), nowt, nowt, o)
        }
        if r != ok { ret 0.0f64 / 0.0f64 }
        let from = usize(x[at])
        let len = usize(x[at + 1usize])
        var s = 0.0f64
        var t = 0usize
        while t < len {
            s += f64(t + 1usize) * o[from + t]
            t += 1usize
        }
        ret s
    }
    if str.eq(c.name, "rescale2") {
        let n = usize(x[2usize])
        let (o, e) = mem.alloc[f64](a, n)
        if e != ok { os.exit(11) }
        if ag.rescale_gen(a, x[3usize..3usize + n], n, usize(x[0usize]), x[1usize] == 1.0f64, o) != ok { os.exit(12) }
        ret o[usize(x[3usize + n])]
    }
    if str.eq(c.name, "stdfit") {
        let n = usize(x[0usize])
        let nv = usize(x[1usize])
        let kinds = x[8usize..8usize + nv]
        let unch = x[8usize + nv..8usize + 2usize * nv]
        let y = x[8usize + 2usize * nv..8usize + 2usize * nv + n]
        let xm = x[8usize + 2usize * nv + n..8usize + 2usize * nv + n + n * nv]
        let (o, e) = mem.alloc[f64](a, 4usize * nv + 4usize)
        if e != ok { os.exit(13) }
        let w = ag.standardize_fit(a, xm, y, n, nv, kinds, unch, x[2usize] == 1.0f64, usize(x[3usize]), usize(x[4usize]), usize(x[5usize]), o)
        if w == 0usize { ret 0.0f64 / 0.0f64 }
        ret o[usize(x[8usize + 2usize * nv + n + n * nv])]
    }
    let n = usize(x[0usize])
    let k = usize(x[1usize])
    let fam = usize(x[2usize])
    let link = usize(x[3usize])
    var at = 8usize
    let y = x[at..at + n]
    at += n
    let xm = x[at..at + n * k]
    at += n * k
    var w: []const f64 = x[0usize..0usize]
    var off: []const f64 = x[0usize..0usize]
    if x[6usize] == 1.0f64 {
        w = x[at..at + n]
        at += n
    }
    if x[7usize] == 1.0f64 {
        off = x[at..at + n]
        at += n
    }
    let pm = x[at..at + k]
    let pd = x[at + k..at + 2usize * k]
    let ps = x[at + 2usize * k..at + 3usize * k]
    let from = usize(x[at + 3usize * k])
    let len = usize(x[at + 3usize * k + 1usize])
    var nocov: []f64 = zero
    let (coef, e) = mem.alloc[f64](a, k)
    let (info, e2) = mem.alloc[f64](a, 4usize)
    if e != ok || e2 != ok { os.exit(10) }
    let it = ag.bayesglm_gen(a, xm, y, n, k, fam, link, w, off, pm, pd, ps, x[4usize] == 1.0f64, x[5usize] == 1.0f64, coef, info, nocov)
    if it == 0usize { ret 0.0f64 / 0.0f64 }
    var s = 0.0f64
    var t = 0usize
    while t < len {
        var v = 0.0f64
        if from + t < k { v = coef[from + t] } else { v = info[from + t - k] }
        s += f64(t + 1usize) * v
        t += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/armglm.json")
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
