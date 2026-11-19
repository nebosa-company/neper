// e.algo.stat.armextra against arm. tests/oracle/armextra.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R armextra`; the layout of every case is at the top of scripts/r_oracle/groups/armextra.R.

use e.algo.rand.r as rng
use e.algo.stat.armextra as ax
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn wsum(o: []const f64, from: usize, len: usize) -> f64 {
    var s = 0.0f64
    var t = 0usize
    while t < len {
        s += f64(t + 1usize) * o[from + t]
        t += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let x = c.args
    let k = c.name
    if str.eq(k, "dispm") {
        let n = usize(x[0usize])
        let q = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, 4usize + 4usize * q)
        if e != ok { os.exit(10) }
        if ax.display_lm(a, x[3usize + n..3usize + n + n * q], x[3usize..3usize + n], n, q, x[2usize] == 1.0f64, o) != ok { os.exit(11) }
        ret wsum(o, usize(x[3usize + n + n * q]), usize(x[4usize + n + n * q]))
    }
    if str.eq(k, "corr") {
        let n = usize(x[0usize])
        let p = usize(x[1usize])
        let (o, e) = mem.alloc[f64](a, p * p)
        if e != ok { os.exit(14) }
        if ax.cor_pairwise(a, x[3usize..3usize + n * p], n, p, x[2usize] == 1.0f64, o) != ok { os.exit(15) }
        ret wsum(o, usize(x[3usize + n * p]) * p, p)
    }
    if str.eq(k, "contrb") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, n * n)
        if e != ok { os.exit(16) }
        let kind = usize(x[1usize])
        if kind == 0usize { ax.contr_unordered(n, o) } else {
            if ax.contr_ordered(a, n, x[2usize..2usize + n], kind == 1usize, o) != ok { os.exit(17) }
        }
        ret o[usize(x[2usize + n]) * n + usize(x[3usize + n])]
    }
    if str.eq(k, "dhist") {
        let m = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, 7usize + 9usize * m)
        if e != ok { os.exit(18) }
        let b = 6usize
        if ax.discrete_hist(a, x[b..b + m], m, x[1usize] == 1.0f64, x[b + m..b + 2usize * m], x[4usize] == 1.0f64, x[b + 2usize * m..b + 3usize * m], x[5usize] == 1.0f64, x[b + 3usize * m..b + 4usize * m], x[2usize] == 1.0f64, x[3usize], o) != ok { os.exit(19) }
        ret o[usize(x[b + 4usize * m])]
    }
    if str.eq(k, "cplot") {
        let m = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, 6usize * m + 1usize)
        if e != ok { os.exit(20) }
        let b = 4usize
        ax.coefplot_numbers(x[b..b + m], x[b + m..b + 2usize * m], m, x[1usize], x[2usize] == 1.0f64, x[b + 2usize * m..b + 3usize * m], x[3usize] == 1.0f64, x[b + 3usize * m..b + 4usize * m], o)
        ret o[usize(x[b + 4usize * m])]
    }
    if str.eq(k, "mcp") {
        let nr = usize(x[0usize])
        let ind = usize(x[1usize])
        let (pv, e) = mem.alloc[f64](a, ind * ind)
        let (sg, e2) = mem.alloc[f64](a, ind * ind)
        if e != ok || e2 != ok { os.exit(21) }
        ax.mcplot_matrices(x[4usize..4usize + nr * ind], nr, ind, x[2usize], pv, sg)
        let at = usize(x[4usize + nr * ind]) * ind
        if x[3usize] == 0.0f64 { ret wsum(pv, at, ind) }
        ret wsum(sg, at, ind)
    }
    if str.eq(k, "balance") {
        let n = usize(x[0usize])
        let kk = usize(x[1usize])
        let (r1, e) = mem.alloc[f64](a, kk * 5usize)
        let (r2, e2) = mem.alloc[f64](a, kk * 5usize)
        let (r3, e3) = mem.alloc[f64](a, kk)
        if e != ok || e2 != ok || e3 != ok { os.exit(22) }
        let b = 4usize
        if ax.balance_numbers(a, x[b + 2usize * n..b + 2usize * n + n * kk], x[b..b + n], x[b + n..b + 2usize * n], n, kk, usize(x[2usize]), r1, r2, r3) != ok { os.exit(23) }
        let rr = usize(x[b + 2usize * n + n * kk])
        let cc = usize(x[b + 2usize * n + n * kk + 1usize])
        if x[3usize] == 0.0f64 { ret wsum(r1, rr * 5usize, 5usize) }
        if x[3usize] == 1.0f64 { ret wsum(r2, rr * 5usize, 5usize) }
        ret r3[rr] + 0.0f64 * f64(cc)
    }
    if str.eq(k, "matchn") {
        let n = usize(x[0usize])
        let (m1, e) = mem.alloc[f64](a, n)
        let (m2, e2) = mem.alloc[f64](a, n)
        let (m3, e3) = mem.alloc[f64](a, n)
        if e != ok || e2 != ok || e3 != ok { os.exit(24) }
        ax.matching_norep(a, x[2usize..2usize + n], x[2usize + n..2usize + 2usize * n], n, m1, m2, m3)
        var i = 0usize
        while i < n {
            if m3[i] != m3[i] { m3[i] = 0.0f64 }
            i += 1usize
        }
        if x[1usize] == 0.0f64 { ret wsum(m1, 0usize, n) }
        if x[1usize] == 1.0f64 { ret wsum(m2, 0usize, n) }
        ret wsum(m3, 0usize, n)
    }
    if str.eq(k, "matchr") {
        let n = usize(x[1usize])
        var nt = 0usize
        var i = 0usize
        while i < n {
            if x[3usize + i] == 1.0f64 { nt += 1usize }
            i += 1usize
        }
        let nc = n - nt
        let (mt, e) = mem.alloc[f64](a, nt * nc)
        let (cn, e2) = mem.alloc[f64](a, n)
        let (im, e3) = mem.alloc[f64](a, nt)
        if e != ok || e2 != ok || e3 != ok { os.exit(25) }
        var g: rng.Rng = zero
        rng.seed(&g, i64(x[0usize]))
        if ax.matching_rep(a, &g, x[3usize..3usize + n], x[3usize + n..3usize + 2usize * n], n, nt, nc, mt, cn, im) != ok { os.exit(26) }
        let b = 3usize + 2usize * n
        if x[2usize] == 0.0f64 { ret wsum(mt, usize(x[b]) * nc, nc) }
        if x[2usize] == 1.0f64 { ret cn[usize(x[b])] }
        ret im[usize(x[b])]
    }
    if str.eq(k, "bpl") {
        let n = usize(x[0usize])
        let (o, e) = mem.alloc[f64](a, 5usize)
        if e != ok { os.exit(27) }
        if ax.binnedplot_numbers(a, x[1usize + n..1usize + 2usize * n], x[1usize..1usize + n], o) != ok { os.exit(28) }
        ret o[usize(x[1usize + 2usize * n])]
    }
    os.exit(9)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/armextra.json")
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
