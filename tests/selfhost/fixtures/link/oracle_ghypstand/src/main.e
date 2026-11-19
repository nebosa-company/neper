// e.algo.stat.ghypstand against GeneralizedHyperbolic hyperbFitStand and hyperblm. tests/oracle/ghypstand.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R ghypstand`; the layout is at the top of scripts/r_oracle/groups/ghypstand.R.

use e.algo.rand.r as rg
use e.algo.stat.ghyp as gh
use e.algo.stat.ghypstand as gs
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

type Cache = struct { key: [16]f64, out: [16]f64, valid: bool, good: bool }

fn same_key(k: []const f64, x: []const f64, skip: usize, n: usize) -> bool {
    var i = 0usize
    while i < n {
        if i != skip && k[i] != x[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case, ch: *Cache) -> f64 {
    let x = c.args
    if str.eq(c.name, "fs") {
        if !(ch.valid && same_key(ch.key[0usize..16usize], x, 5usize, 14usize)) {
            var i = 0usize
            while i < 14usize {
                ch.key[i] = x[i]
                i += 1usize
            }
            ch.valid = true
            let nn = usize(x[1usize])
            let (d, g1) = mem.alloc[f64](a, nn)
            let (xx, g2) = mem.alloc[f64](a, nn)
            if g1 != ok || g2 != ok { os.exit(7) }
            var rng: rg.Rng = zero
            rg.seed(&rng, i64(x[0usize]))
            gh.rghyp(&rng, nn, x[6usize], x[7usize], x[8usize], x[9usize], 1.0f64, d, xx)
            ch.good = gs.st_fit(a, d, usize(x[2usize]), usize(x[3usize]), usize(x[4usize]), x[10usize..14usize], ch.out[0usize..16usize])
        }
        if !ch.good { ret 0.0f64 / 0.0f64 }
        ret ch.out[usize(x[5usize])]
    }
    if !(ch.valid && same_key(ch.key[0usize..16usize], x, 5usize, 13usize)) {
        var i = 0usize
        while i < 13usize {
            ch.key[i] = x[i]
            i += 1usize
        }
        ch.valid = true
        let nn = usize(x[1usize])
        let (d, g1) = mem.alloc[f64](a, nn)
        let (xx, g2) = mem.alloc[f64](a, nn)
        let (xm, g3) = mem.alloc[f64](a, nn * 3usize)
        let (y, g4) = mem.alloc[f64](a, nn)
        if g1 != ok || g2 != ok || g3 != ok || g4 != ok { os.exit(7) }
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(x[0usize]))
        gh.rghyp(&rng, nn, x[9usize], x[10usize], x[11usize], x[12usize], 1.0f64, d, xx)
        i = 0usize
        let by = 1.0f64 / f64(nn - 1usize)
        while i < nn {
            let x1 = f64(i) * by
            let x2 = f64((7usize * (i + 1usize)) % 11usize) / 11.0f64
            xm[i] = 1.0f64
            xm[nn + i] = x1
            xm[2usize * nn + i] = x2
            y[i] = x[6usize] + x[7usize] * x1 + x[8usize] * x2 + d[i]
            i += 1usize
        }
        ch.good = gs.st_lm(a, xm, y, 3usize, usize(x[2usize]), usize(x[3usize]), usize(x[4usize]), 100usize, 0.0001f64, ch.out[0usize..16usize])
    }
    if !ch.good { ret 0.0f64 / 0.0f64 }
    ret ch.out[usize(x[5usize])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/ghypstand.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var ch: Cache = zero
    while at < golden.cases.len {
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
