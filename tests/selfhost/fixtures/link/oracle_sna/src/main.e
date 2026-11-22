// e.algo.stat.snapkg against sna. tests/oracle/sna.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R sna`; the layout is at the top of scripts/r_oracle/groups/sna.R.

use e.algo.rand.r as rrand
use e.algo.stat.hclust as hl
use e.algo.stat.snapkg as sn
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn block(out: []const f64, n: usize, b: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        s += out[b * n + i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += v[i] * f64(i + 1usize)
        i += 1usize
    }
    ret s
}

fn is(c: *const oracle.Case, name: str) -> bool {
    ret str.eq(c.name, name)
}

fn clustering(a: *mem.Arena, c: *const oracle.Case, n: usize) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let base = 1usize + n * n
    let (d, e1) = mem.alloc[f64](a, n * n)
    if e1 != ok { ret nan }
    if sn.sedist(a, z[1usize..base], n, usize(z[base]), true, d) != ok { ret nan }
    let (t, e2) = hl.hclust(a, d, n, usize(z[base + 1usize]))
    if e2 != ok { ret nan }
    if is(c, "eq_height") { ret wsum(t.height) }
    var s = 0.0f64
    var i = 0usize
    if is(c, "eq_order") {
        while i < n {
            s += f64(t.order[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if is(c, "eq_merge") {
        while i < n - 1usize {
            s += f64(t.merge_a[i]) * f64(2usize * i + 1usize) + f64(t.merge_b[i]) * f64(2usize * i + 2usize)
            i += 1usize
        }
        ret s
    }
    let k = usize(z[base + 2usize])
    let content = usize(z[base + 3usize])
    let (memb, e3) = mem.alloc[usize](a, n)
    let (bm, e4) = mem.alloc[f64](a, k * k)
    if e3 != ok { ret nan }
    if e4 != ok { ret nan }
    if hl.cutree(a, &t, n, k, memb) != ok { ret nan }
    if is(c, "bm_order") {
        while i < n {
            s += f64(t.order[i]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if is(c, "bm_member") {
        while i < n {
            s += f64(memb[usize(t.order[i]) - 1usize]) * f64(i + 1usize)
            i += 1usize
        }
        ret s
    }
    if sn.blockmodel(a, z[1usize..base], n, memb, k, content, bm) != ok { ret nan }
    ret wsum(bm)
}

fn netcase(a: *mem.Arena, c: *const oracle.Case, n: usize) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nn = n * n
    let base = 1usize + nn
    let nx0 = usize(z[base])
    let hyp = usize(z[base + 1usize])
    let reps = usize(z[base + 2usize])
    let kind = usize(z[base + 3usize])
    let nx = nx0 + 1usize
    var rg: rrand.Rng = zero
    rrand.seed(&rg, i64(z[base + 4usize]))
    let (out, e1) = mem.alloc[f64](a, 5usize * nx + 3usize)
    let (dist, e2) = mem.alloc[f64](a, reps * nx)
    if e1 != ok { ret nan }
    if e2 != ok { ret nan }
    if sn.netfit(a, &rg, z[1usize..base], z[base + 5usize..base + 5usize + nx0 * nn], nx0, n, true, hyp, reps, kind, out, dist) != ok { ret nan }
    if is(c, "net_coef") { ret wsum(out[0usize..nx]) }
    if is(c, "net_stat") { ret wsum(out[nx..2usize * nx]) }
    // qapx: the intercept column's p-values are not asked (see the R group)
    var skip = 0usize
    if hyp == 2usize { skip = 1usize }
    if is(c, "net_pleeq") { ret wsum(out[2usize * nx + skip..3usize * nx]) }
    if is(c, "net_pgreq") { ret wsum(out[3usize * nx + skip..4usize * nx]) }
    if is(c, "net_pgreqabs") { ret wsum(out[4usize * nx + skip..5usize * nx]) }
    if kind <= 1usize { ret out[5usize * nx] + 100.0f64 * out[5usize * nx + 2usize] }
    ret out[5usize * nx] + 10.0f64 * out[5usize * nx + 1usize] + 100.0f64 * out[5usize * nx + 2usize]
}

fn qapcase(a: *mem.Arena, c: *const oracle.Case, n: usize) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let nn = n * n
    let base = 1usize + 2usize * nn
    let reps = usize(z[base])
    var rg: rrand.Rng = zero
    rrand.seed(&rg, i64(z[base + 2usize]))
    let (out, e1) = mem.alloc[f64](a, 3usize + reps)
    if e1 != ok { ret nan }
    if sn.qaptest(a, &rg, z[1usize..1usize + nn], z[1usize + nn..base], n, reps, usize(z[base + 1usize]), out) != ok { ret nan }
    if is(c, "qap_test") { ret out[0usize] }
    if is(c, "qap_pgreq") { ret out[1usize] }
    if is(c, "qap_pleeq") { ret out[2usize] }
    ret wsum(out[3usize..3usize + reps])
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let g = z[1usize..1usize + n * n]
    if c.name.len > 4usize && str.eq(c.name[0usize..4usize], "net_") { ret netcase(a, c, n) }
    if c.name.len > 4usize && str.eq(c.name[0usize..4usize], "qap_") { ret qapcase(a, c, n) }
    if is(c, "eq_height") || is(c, "eq_order") || is(c, "eq_merge") || is(c, "bm") || is(c, "bm_order") || is(c, "bm_member") { ret clustering(a, c, n) }
    let (out, e1) = mem.alloc[f64](a, 16usize + 8usize * n + 1usize)
    if e1 != ok { ret nan }
    if is(c, "dyad_m") || is(c, "dyad_a") || is(c, "dyad_n") || is(c, "mutuality") {
        sn.dyad_census(g, n, out)
        if is(c, "dyad_a") { ret out[1usize] }
        if is(c, "dyad_n") { ret out[2usize] }
        ret out[0usize]
    }
    if is(c, "triad") || is(c, "triad2") {
        if sn.triad_census(a, g, n, out) != ok { ret nan }
        var s = 0.0f64
        var i = 0usize
        while i < 16usize {
            var w = f64(i + 1usize)
            if is(c, "triad2") { w = w * w }
            s += out[i] * w
            i += 1usize
        }
        ret s
    }
    if is(c, "connectedness") {
        let (v, e) = sn.connectedness(a, g, n)
        if e != ok { ret nan }
        ret v
    }
    if is(c, "hier_rec") || is(c, "hier_krack") {
        var measure = 0usize
        if is(c, "hier_krack") { measure = 1usize }
        let (v, e) = sn.hierarchy(a, g, n, measure)
        if e != ok { ret nan }
        ret v
    }
    if is(c, "pr_indeg") || is(c, "pr_rownorm") || is(c, "pr_eigen") || is(c, "pr_domain") || is(c, "pr_prox") {
        var mode = 0usize
        if is(c, "pr_rownorm") { mode = 1usize }
        if is(c, "pr_eigen") { mode = 2usize }
        if is(c, "pr_domain") { mode = 3usize }
        if is(c, "pr_prox") { mode = 4usize }
        if sn.prestige(a, g, n, mode, out) != ok { ret nan }
        ret wsum(out[0usize..n])
    }
    if is(c, "infocent") {
        if sn.infocent(a, g, n, out) != ok { ret nan }
        ret wsum(out[0usize..n])
    }
    if is(c, "sedist") {
        let (d, e2) = mem.alloc[f64](a, n * n)
        if e2 != ok { ret nan }
        if sn.sedist(a, g, n, usize(z[1usize + n * n]), true, d) != ok { ret nan }
        ret wsum(d)
    }
    if sn.centrality(a, g, n, out) != ok { ret nan }
    let nf = f64(n)
    if is(c, "outdeg") { ret block(out, n, 0usize) }
    if is(c, "indeg") { ret block(out, n, 1usize) }
    if is(c, "degree") { ret block(out, n, 2usize) }
    if is(c, "between") { ret block(out, n, 3usize) }
    if is(c, "stress") { ret block(out, n, 4usize) }
    if is(c, "closeness") { ret block(out, n, 5usize) }
    if is(c, "graphcent") { ret block(out, n, 6usize) }
    if is(c, "evcent") { ret block(out, n, 7usize) }
    if is(c, "gden") { ret out[8usize * n] }
    if is(c, "cent_degree") { ret sn.centralization(out[2usize * n..3usize * n], (nf - 1.0f64) * (2.0f64 * nf - 4.0f64)) }
    if is(c, "cent_between") { ret sn.centralization(out[3usize * n..4usize * n], (nf - 1.0f64) * (nf - 1.0f64) * (nf - 2.0f64)) }
    ret sn.centralization(out[5usize * n..6usize * n], (nf - 1.0f64) * (nf - 1.0f64) / nf)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/sna.json")
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
            if failures <= 40usize {
                let d = oracle.describe(a, c, got)
                let _ = io.print(c.name)
                let _ = io.print(" ... ")
                if d.len > 90usize { let _ = io.print(d[d.len - 90usize..d.len]) }
                let _ = io.print("\n")
            }
        }
        mem.reset(a, start)
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
