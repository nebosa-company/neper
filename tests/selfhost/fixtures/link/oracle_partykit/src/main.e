// e.algo.stat.partykitpkg against partykit ctree. tests/oracle/partykit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R partykit`; the argument layout is at the top of scripts/r_oracle/groups/partykit.R.

use e.algo.stat.partykitpkg as pk
use e.io
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
    let alpha = z[7usize]
    let bonf = z[8usize] > 0.5f64
    let maxdepth = usize(z[9usize])
    let stump = z[10usize] > 0.5f64
    let inter = z[11usize] > 0.5f64
    let (nl, e1) = mem.alloc[usize](a, p)
    if e1 != ok { ret 0.0f64 / 0.0f64 }
    var j = 0usize
    while j < p {
        nl[j] = usize(z[12usize + j])
        j += 1usize
    }
    let x = z[12usize + p..12usize + p + n * p]
    let y = z[12usize + p + n * p..12usize + p + n * p + n]
    let (o, e2) = pk.ctree(a, x, n, p, nl, y, yl, minsplit, minbucket, minprob, alpha, bonf, maxdepth, stump, inter)
    if e2 != ok { ret 0.0f64 / 0.0f64 }
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
        id += 1usize
    }
    if sel >= 6usize {
        var i = 0usize
        while i < n {
            if sel == 8usize {
                let (xn, e3) = mem.alloc[f64](a, n * p)
                if e3 != ok { ret 0.0f64 / 0.0f64 }
                var q = 0usize
                while q < n * p {
                    xn[q] = x[q] * 1.1f64 + 0.05f64
                    q += 1usize
                }
                s += f64(i + 1usize) * f64(pk.predict_node(&o, nl, xn, n, i))
            } else {
                let nd = pk.predict_node(&o, nl, x, n, i)
                if sel == 6usize || sel == 9usize { s += f64(i + 1usize) * f64(nd) }
                if sel == 7usize || sel == 10usize { s += o.fit[nd - 1usize] }
            }
            i += 1usize
        }
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/partykit.json")
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
