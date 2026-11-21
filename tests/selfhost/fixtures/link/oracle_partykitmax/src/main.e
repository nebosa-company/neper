// e.algo.stat.partykitpkg against partykit ctree with the maximum statistic where the test has several degrees of freedom (the Genz-Bretz p value on R's stream).
// tests/oracle/partykitmax.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R partykitmax`; the argument layout is at the top of scripts/r_oracle/groups/partykitmax.R.

use e.algo.stat.partykitpkg as pk
use e.io
use e.math
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let sel = usize(z[0usize])
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let yl = usize(z[3usize])
    let minsplit = usize(z[4usize])
    let minbucket = usize(z[5usize])
    let minprob = z[6usize]
    let mincrit = z[7usize]
    let bonf = z[8usize] > 0.5f64
    let statcrit = z[9usize] > 0.5f64
    let maxst = z[10usize] > 0.5f64
    let maxdepth = usize(z[11usize])
    let stump = z[12usize] > 0.5f64
    let inter = z[13usize] > 0.5f64
    let seed = i64(z[14usize])
    let (nl, e1) = mem.alloc[usize](a, p)
    let (ord, e1b) = mem.alloc[bool](a, p)
    let (w, e1c) = mem.alloc[f64](a, n)
    if e1 != ok || e1b != ok || e1c != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < p {
        let v = z[15usize + j]
        nl[j] = 0usize
        ord[j] = false
        if v > 0.5f64 { nl[j] = usize(v) }
        if v < -0.5f64 { ord[j] = true }
        j += 1usize
    }
    var i = 0usize
    while i < n {
        w[i] = z[15usize + p + i]
        i += 1usize
    }
    let x0 = 15usize + p + n
    let (x, e2) = mem.alloc[f64](a, n * p)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
    j = 0usize
    while j < p {
        i = 0usize
        while i < n {
            x[j * n + i] = z[x0 + j * n + i]
            // an ordered factor enters as its scores 1 .. L, the linear-by-linear test and the cut points over the levels being a numeric predictor's
            if ord[j] { x[j * n + i] += 1.0f64 }
            i += 1usize
        }
        j += 1usize
    }
    let y = z[x0 + n * p..x0 + n * p + n]
    let xo = pk.Xo { statcrit: statcrit, maxst: maxst, setlog: true, logmin: math.log[f64](mincrit), ord: ord, w: w, nres: 0usize, spl: false, mtry: 0usize, maxvar: 1000000usize }
    let (o, e3) = pk.ctree_xs(a, x, n, p, nl, y, yl, minsplit, minbucket, minprob, mincrit, bonf, maxdepth, stump, inter, w, &xo, seed)
    if e3 != ok { ret 0.0f64 / 0.0f64 }
    if sel == 1usize { ret f64(o.count) }
    var s = 0.0f64
    var id = 1usize
    while id <= o.count {
        let k = id - 1usize
        let inner = o.vr[k] != 0i64
        if sel == 2usize { s += f64(id) * f64(o.vr[k]) }
        if sel == 3usize && inner {
            let v = usize(o.vr[k] - 1i64)
            if nl[v] == 0usize {
                s += f64(id) * o.brk[k]
            } else {
                var t = 0.0f64
                var l = 0usize
                while l < nl[v] {
                    let d = o.lmap[k * o.maxlev + l]
                    if d >= 0i64 { t += f64(l + 1usize) * f64(d + 1i64) }
                    l += 1usize
                }
                s += f64(id) * t
            }
        }
        if sel == 4usize { s += f64(id) * o.nobs[k] }
        if sel == 5usize && inner { s += f64(id) * o.pval[k] }
        if sel == 11usize && inner { s += f64(id) * o.stat[k] }
        id += 1usize
    }
    if sel == 6usize || sel == 7usize {
        i = 0usize
        while i < n {
            let nd = pk.predict_node(&o, nl, x, n, i)
            if sel == 6usize { s += f64(i + 1usize) * f64(nd) }
            if sel == 7usize { s += o.fit[nd - 1usize] }
            i += 1usize
        }
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/partykitmax.json")
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
