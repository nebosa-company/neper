// e.algo.stat.matchitpkg against MatchIt. tests/oracle/matchit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R matchit`; the layout is at the top of scripts/r_oracle/groups/matchit.R.

use e.algo.stat.matchitpkg as mt
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn checks(w: []const f64, n: usize, ps: []const f64, which: str) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < n {
        let k = f64(i + 1usize)
        if str.ends_with(which, "w1") { s += w[i] * k }
        if str.ends_with(which, "w2") { s += w[i] * k * k }
        if str.ends_with(which, "nmatched") && w[i] > 0.0f64 { s += 1.0f64 }
        if str.eq(which, "snsub") && w[i] > 0.0f64 { s += 1.0f64 }
        if str.eq(which, "ps") || str.eq(which, "sps") { s += ps[i] * k }
        i += 1usize
    }
    ret s
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let n = usize(z[0usize])
    let (w, e1) = mem.alloc[f64](a, n)
    let (ps, e2) = mem.alloc[f64](a, n)
    if e1 != ok || e2 != ok { ret nan }
    let nm = c.name
    if str.starts_with(nm, "x") {
        // exact: (n, est, t[n], g[n])
        if mt.exact(a, z[2usize + n..2usize + 2usize * n], z[2usize..2usize + n], n, usize(z[1usize]), w) != ok { ret nan }
        ret checks(w, n, ps, nm)
    }
    if str.starts_with(nm, "o") {
        // optimal: (n, p, t[n], x[n*p])
        let p = usize(z[1usize])
        if mt.optimal(a, z[2usize + n..2usize + n + n * p], z[2usize..2usize + n], n, p, w, ps) != ok { ret nan }
        ret checks(w, n, ps, nm)
    }
    if str.starts_with(nm, "c") {
        // cem: (n, p, kind, par, est, t[n], x[n*p])
        let p = usize(z[1usize])
        if mt.cem(a, z[5usize + n..5usize + n + n * p], z[5usize..5usize + n], n, p, usize(z[2usize]), z[3usize], usize(z[4usize]), w) != ok { ret nan }
        ret checks(w, n, ps, nm)
    }
    if str.starts_with(nm, "s") {
        // subclass: (n, p, nsub, est, min.n, t[n], x[n*p])
        let p = usize(z[1usize])
        let (sub, e3) = mem.alloc[usize](a, n)
        if e3 != ok { ret nan }
        if mt.subclass(a, z[5usize + n..5usize + n + n * p], z[5usize..5usize + n], n, p, usize(z[2usize]), usize(z[3usize]), usize(z[4usize]), sub, w, ps) != ok { ret nan }
        if str.starts_with(nm, "smd") {
            // match.data: row count, sum of weight*row, sum of subclass*row over the kept rows
            let (rows, e5) = mem.alloc[usize](a, n)
            let (mw, e6) = mem.alloc[f64](a, n)
            let (ms, e7) = mem.alloc[usize](a, n)
            if e5 != ok || e6 != ok || e7 != ok { ret nan }
            let k = mt.match_data(w, sub, n, rows, mw, ms)
            var s = 0.0f64
            var q = 0usize
            while q < k {
                let r = f64(rows[q] + 1usize)
                if str.eq(nm, "smdrows") { s += 1.0f64 }
                if str.eq(nm, "smdw") { s += mw[q] * r }
                if str.eq(nm, "smdsub") { s += f64(ms[q]) * r }
                q += 1usize
            }
            ret s
        }
        ret checks(w, n, ps, nm)
    }
    if str.eq(nm, "bal") {
        // (n, p, j, denom, k, t[n], x[n*p], w[n])
        let p = usize(z[1usize])
        let (o, e4) = mem.alloc[f64](a, 6usize)
        if e4 != ok { ret nan }
        if mt.balance(a, z[5usize + n..5usize + n + n * p], z[5usize..5usize + n], z[5usize + n + n * p..5usize + 2usize * n + n * p], n, p, usize(z[2usize]), usize(z[3usize]), o) != ok { ret nan }
        ret o[usize(z[4usize])]
    }
    // nearest: (n, p, ratio, replace, caliper, order, atc, seed, hasStrata, link, linear, mah, psdist, t[n], x[n*p], strata[n])
    let p = usize(z[1usize])
    var st: []const f64 = z[0usize..0usize]
    if z[8usize] > 0.5f64 { st = z[13usize + n + n * p..13usize + 2usize * n + n * p] }
    if mt.nearest(a, z[13usize + n..13usize + n + n * p], z[13usize..13usize + n], n, p, usize(z[2usize]), z[3usize] > 0.5f64, z[4usize], usize(z[5usize]), z[6usize] > 0.5f64, st, i64(z[7usize]), usize(z[9usize]), z[10usize] > 0.5f64, usize(z[11usize]), z[12usize] > 0.5f64, w, ps) != ok { ret nan }
    ret checks(w, n, ps, nm)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/matchit.json")
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
