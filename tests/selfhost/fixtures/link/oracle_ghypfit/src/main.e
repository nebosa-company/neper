// e.algo.stat.ghypfit against GeneralizedHyperbolic hyperbFit and nigFit. tests/oracle/ghypfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ghypfit`; the layout is at the top of scripts/r_oracle/groups/ghypfit.R.

use e.algo.rand.r as rg
use e.algo.stat.ghyp as gh
use e.algo.stat.ghypfit as gf
use e.algo.stat.ghypgig as gg
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct { key: [16]f64, out: [11]f64, valid: bool, good: bool }

fn same_key(k: []const f64, x: []const f64, skip: usize, n: usize) -> bool {
    var i = 0usize
    while i < n {
        if i != skip && k[i] != x[i] { ret false }
        i += 1usize
    }
    ret true
}

fn nlm_of(v: f64) -> usize {
    if v >= 1.5f64 { ret 4usize }
    ret 0usize
}

fn gig_answer(a: *mem.Arena, x: []const f64, ch: *Cache) -> f64 {
    if !(ch.valid && same_key(ch.key[0usize..16usize], x, 4usize, 11usize)) {
        var i = 0usize
        while i < 11usize {
            ch.key[i] = x[i]
            i += 1usize
        }
        ch.valid = true
        let nn = usize(x[1usize])
        let (d, g1) = mem.alloc[f64](a, nn)
        if g1 != ok { os.exit(7) }
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(x[0usize]))
        gh.rgig(&rng, nn, x[5usize], x[6usize], x[7usize], d)
        ch.good = gg.gig_fit(a, d, usize(x[2usize]), x[8usize..11usize], x[3usize] == 1.0f64 || x[3usize] == 3.0f64, nlm_of(x[3usize]), ch.out[0usize..11usize])
    }
    if !ch.good { ret 0.0f64 / 0.0f64 }
    ret ch.out[usize(x[4usize])]
}

fn answer(a: *mem.Arena, c: *const oracle.Case, ch: *Cache) -> f64 {
    let x = c.args
    if str.eq(c.name, "gigfit") { ret gig_answer(a, x, ch) }
    if !(ch.valid && same_key(ch.key[0usize..16usize], x, 6usize, 15usize)) {
        var i = 0usize
        while i < 15usize {
            ch.key[i] = x[i]
            i += 1usize
        }
        ch.valid = true
        let nn = usize(x[1usize])
        let fam = usize(x[2usize])
        let (d, g1) = mem.alloc[f64](a, nn)
        let (xx, g2) = mem.alloc[f64](a, nn)
        if g1 != ok || g2 != ok { os.exit(7) }
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(x[0usize]))
        var lam = 1.0f64
        if fam == 1usize { lam = 0.0f64 - 0.5f64 }
        gh.rghyp(&rng, nn, x[7usize], x[8usize], x[9usize], x[10usize], lam, d, xx)
        ch.good = gf.fit_family(a, d, fam, usize(x[3usize]), usize(x[4usize]), usize(x[5usize]), x[11usize..15usize], ch.out[0usize..11usize])
    }
    if !ch.good { ret 0.0f64 / 0.0f64 }
    ret ch.out[usize(x[6usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ghypfit.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    // this golden is seconds to minutes of compute per case, so it may be run in slices: `oracle_ghypfit <first> <count>` (D7823)
    let (first, last) = oracle.slice(args, golden.cases.len)
    var at = first
    var ch: Cache = zero
    while at < last {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c, &ch)
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
