// e.algo.stat.agricolae grouping letters and the Kruskal post-hoc against agricolae. tests/oracle/agricolae_groups.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R agricolae_groups`; the layout is at the top of scripts/r_oracle/groups/agricolae_groups.R.

use e.algo.stat.agricolae as ag
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let k = usize(x[2usize])
    let y = x[3usize..3usize + n]
    let (grp, e1) = mem.alloc[usize](a, n)
    let (mean, e2) = mem.alloc[f64](a, k)
    let (size, e3) = mem.alloc[f64](a, k)
    if e1 != ok || e2 != ok || e3 != ok { os.exit(5) }
    var i = 0usize
    while i < n {
        grp[i] = usize(x[3usize + n + i])
        i += 1usize
    }
    if kind == 5usize {
        let kw = ag.kruskal(a, y, grp, k, mean, size)
        if str.eq(c.name, "kh") { ret kw.h }
        if str.eq(c.name, "kp") { ret kw.pchisq }
        var s = 0.0f64
        var pos = 1usize
        var p = 0usize
        while p < k {
            var q = p + 1usize
            while q < k {
                let (d, pv, lo, hi) = ag.kruskal_pair(kw, mean, size, p, q, 0.05f64)
                var v = d
                if str.eq(c.name, "kpv") { v = pv }
                if str.eq(c.name, "kl") { v = lo }
                if str.eq(c.name, "ku") { v = hi }
                s += v * f64(pos)
                pos += 1usize
                q += 1usize
            }
            p += 1usize
        }
        ret s
    }
    let w = ag.one_way(y, grp, k, mean, size)
    let (pv, e4) = mem.alloc[f64](a, k * k)
    let (ord, e5) = mem.alloc[usize](a, k)
    let (mk, e6) = mem.alloc[u64](a, k)
    if e4 != ok || e5 != ok || e6 != ok { os.exit(6) }
    var p = 0usize
    while p < k {
        var q = 0usize
        while q < k {
            pv[p * k + q] = 1.0f64
            q += 1usize
        }
        p += 1usize
    }
    p = 0usize
    while p < k {
        var q = p + 1usize
        while q < k {
            let (d, pr, lo, hi) = ag.pairwise(w, mean, size, p, q, kind, 0.05f64)
            // the package rounds every p value to four decimals before the letters are assigned
            let rp = ag.round4(pr)
            pv[p * k + q] = rp
            pv[q * k + p] = rp
            q += 1usize
        }
        p += 1usize
    }
    ag.group_letters(mean, pv, k, 0.05f64, ord, mk)
    let idx = usize(x[3usize + 2usize * n])
    if str.eq(c.name, "gt") { ret f64(ord[idx] + 1usize) }
    ret f64(mk[idx])
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/agricolae_groups.json")
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
