// e.algo.stat.wrs2 against WRS2: the deterministic trimmed-mean tests and robust correlations. tests/oracle/wrs2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R wrs2`; the layout of every case is at the top of scripts/r_oracle/groups/wrs2.R.

use e.algo.stat.wrs2 as wr
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn sizes_of(a: *mem.Arena, v: []const f64) -> []usize {
    let (o, e) = mem.alloc[usize](a, v.len)
    if e != ok { os.exit(5) }
    var i = 0usize
    while i < v.len {
        o[i] = usize(v[i])
        i += 1usize
    }
    ret o
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let nm = c.name
    if str.eq(nm, "med1way") {
        let k = usize(x[0usize])
        let sz = sizes_of(a, x[1usize..1usize + k])
        var tot = 0usize
        var i = 0usize
        while i < k {
            tot += sz[i]
            i += 1usize
        }
        ret wr.med1way_stat(a, x[1usize + k..1usize + k + tot], sz)
    }
    let tr = x[0usize]
    if str.eq(nm, "t1way") || str.eq(nm, "lincon") {
        let k = usize(x[1usize])
        let sz = sizes_of(a, x[2usize..2usize + k])
        var tot = 0usize
        var i = 0usize
        while i < k {
            tot += sz[i]
            i += 1usize
        }
        let data = x[2usize + k..2usize + k + tot]
        if str.eq(nm, "t1way") {
            let t = wr.t1way(a, data, sz, tr)
            let j = usize(x[x.len - 1usize])
            if j == 0usize { ret t.test }
            if j == 1usize { ret t.df1 }
            if j == 2usize { ret t.df2 }
            if j == 3usize { ret t.p }
            ret t.effsize
        }
        let (ps, pe) = wr.lincon(a, data, sz, tr)
        if pe != ok { os.exit(6) }
        let pr = usize(x[x.len - 2usize])
        let j = usize(x[x.len - 1usize])
        if j == 0usize { ret ps[pr].psihat }
        ret ps[pr].padj
    }
    if str.eq(nm, "yuen") {
        let n1 = usize(x[1usize])
        let n2 = usize(x[2usize + n1])
        let r = wr.yuen(a, x[2usize..2usize + n1], x[3usize + n1..3usize + n1 + n2], tr)
        let j = usize(x[x.len - 1usize])
        if j == 0usize { ret r.test }
        if j == 1usize { ret r.lo }
        if j == 2usize { ret r.hi }
        if j == 3usize { ret r.p }
        if j == 4usize { ret r.df }
        if j == 5usize { ret r.diff }
        ret r.effsize
    }
    if str.eq(nm, "akp") {
        let n1 = usize(x[2usize])
        let n2 = usize(x[3usize + n1])
        ret wr.akp_d(a, x[3usize..3usize + n1], x[4usize + n1..4usize + n1 + n2], tr, x[1usize] == 1.0f64)
    }
    let n = usize(x[1usize])
    if str.eq(nm, "yuend") {
        let r = wr.yuend(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], tr)
        let j = usize(x[x.len - 1usize])
        if j == 0usize { ret r.test }
        if j == 1usize { ret r.lo }
        if j == 2usize { ret r.hi }
        if j == 3usize { ret r.p }
        if j == 4usize { ret r.df }
        if j == 5usize { ret r.diff }
        if j == 6usize { ret r.effsize }
        ret r.se
    }
    if str.eq(nm, "wincor") || str.eq(nm, "pbcor") {
        var w: wr.Wc = zero
        if str.eq(nm, "wincor") { w = wr.wincor(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], tr) } else { w = wr.pbcor(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], tr) }
        let j = usize(x[x.len - 1usize])
        if str.eq(nm, "wincor") {
            if j == 0usize { ret w.cor }
            if j == 1usize { ret w.cov }
            if j == 2usize { ret w.test }
            ret w.p
        }
        if j == 0usize { ret w.cor }
        if j == 1usize { ret w.test }
        ret w.p
    }
    let s = x[2usize..2usize + n]
    if str.eq(nm, "winvar") { ret wr.winvar(a, s, tr) }
    if str.eq(nm, "winmean") { ret wr.winmean(a, s, tr) }
    if str.eq(nm, "winse") { ret wr.winse(a, s, tr) }
    if str.eq(nm, "trimse") { ret wr.trimse(a, s, tr) }
    if str.eq(nm, "tmean") { ret wr.tmean(a, s, tr) }
    if str.eq(nm, "pbos") { ret wr.pbos(a, s, tr) }
    ret wr.msmedse(a, s)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/wrs2.json")
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
