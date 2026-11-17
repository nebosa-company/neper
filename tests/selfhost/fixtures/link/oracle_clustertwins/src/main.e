// e.algo.stat.clustertwins (agnes, diana) against cluster::agnes and cluster::diana. tests/oracle/clustertwins.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R clustertwins`; the argument layout is at the top of
// scripts/r_oracle/groups/clustertwins.R.

use e.algo.stat.clusterdiss as cd
use e.algo.stat.clustertwins as ct
use e.algo.stat.hclust as hc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum_f(v: []const f64, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn wsum_u(v: []const usize, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += f64(v[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn wsum_i(v: []const i32, cnt: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < cnt {
        s += f64(v[i]) * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let kind = usize(x[0usize])
    let n = usize(x[1usize])
    let p = usize(x[2usize])
    let method = usize(x[3usize])
    let stand = x[4usize] != 0.0f64
    let metric = usize(x[5usize])
    let diss = x[6usize] != 0.0f64
    let kcut = usize(x[7usize])
    let npar = usize(x[8usize])
    let base = 9usize + npar
    var dys: []f64 = zero
    if diss {
        let (v, e2) = cd.cdv_from_dist(a, x[base..base + n * (n - 1usize) / 2usize], n)
        if e2 != ok { os.exit(6) }
        dys = v
    } else {
        let (m, e3) = mem.alloc[f64](a, n * p)
        if e3 != ok { os.exit(7) }
        var i = 0usize
        while i < n * p {
            m[i] = x[base + i]
            if m[i] < 0.0f64 - 999000.0f64 { m[i] = 0.0f64 / 0.0f64 }
            i += 1usize
        }
        if stand {
            if cd.stand_meanabsdev(a, m, n, p) != ok { os.exit(8) }
        }
        let (v, e4) = mem.alloc[f64](a, n * (n - 1usize) / 2usize + 1usize)
        if e4 != ok { os.exit(9) }
        if cd.dysta(m, n, p, metric, v) != 0usize { os.exit(10) }
        dys = v
    }
    var alpha: [4]f64 = zero
    if kind == 1usize && (method == 6usize || method == 7usize) {
        let (al, e5) = mem.alloc[f64](a, 4usize)
        if e5 != ok { os.exit(11) }
        ct.lance_alpha(method, x[9usize..9usize + npar], npar, al)
        var q = 0usize
        while q < 4usize {
            alpha[q] = al[q]
            q += 1usize
        }
    }
    var r: ct.TwinsOut = zero
    if kind == 1usize {
        let (o, e6) = ct.agnes_core(a, dys, n, method, alpha[0usize..4usize])
        if e6 != ok { os.exit(12) }
        r = o
    } else {
        let (o, e7) = ct.diana_core(a, dys, n)
        if e7 != ok { os.exit(13) }
        r = o
    }
    let nm = c.name
    if str.eq(nm, "order") { ret wsum_u(r.ner, n) }
    if str.eq(nm, "m1") { ret wsum_i(r.merge_a, n - 1usize) }
    if str.eq(nm, "m2") { ret wsum_i(r.merge_b, n - 1usize) }
    if str.eq(nm, "height") { ret wsum_f(r.ban[1usize..n], n - 1usize) }
    if str.eq(nm, "coef") { ret r.coef }
    let (t, e8) = ct.twins_tree(a, r, n)
    if e8 != ok { os.exit(14) }
    if str.eq(nm, "hheight") { ret wsum_f(t.height, n - 1usize) }
    if str.eq(nm, "hcoef") { ret ct.coef_hclust(&t, n) }
    if str.eq(nm, "cut") {
        let (lab, e9) = mem.alloc[usize](a, n)
        if e9 != ok { os.exit(15) }
        if hc.cutree(a, &t, n, kcut, lab) != ok { os.exit(16) }
        ret wsum_u(lab, n)
    }
    os.exit(17)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/clustertwins.json")
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
