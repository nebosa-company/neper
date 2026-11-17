// e.algo.stat.gldfit against gld: starship, fit.fkml.moments and fit.fkml. tests/oracle/gldfit.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R gldfit`; the argument layouts are at the top of
// scripts/r_oracle/groups/gldfit.R. The fits are compared at 1e-4: they stop on Nelder-Mead's relative tolerance.

use e.algo.stat.gldfit as gf
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

// the fit of the previous case, reused while the next case differs only in which coordinate it asks for
type Cache = struct {
    name: str,
    args: []const f64,
    lam: [5]f64,
    info: [10]f64,
    good: bool,
}

fn same_fit(cache: *const Cache, c: *const oracle.Case) -> bool {
    if cache.args.len != c.args.len || !str.eq(cache.name, c.name) { ret false }
    var i = 0usize
    while i + 1usize < c.args.len {
        if cache.args[i] != c.args[i] { ret false }
        i += 1usize
    }
    ret true
}

fn answer(a: *mem.Arena, c: *const oracle.Case, cache: *Cache) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let eps = 2.220446049250313e-16f64
    let last = z[z.len - 1usize]
    if !same_fit(cache, c) {
        cache.name = c.name
        cache.args = c.args
        cache.good = false
        var ok_fit = false
        if str.eq(c.name, "star") {
            let n = usize(z[1usize])
            ok_fit = gf.starship(a, i32(z[0usize]), z[2usize..2usize + n], eps, cache.lam[0usize..5usize], cache.info[0usize..10usize]) == ok
        } else if str.eq(c.name, "fmom") {
            let n = usize(z[0usize])
            ok_fit = gf.fit_fkml_moments(a, z[1usize..1usize + n], cache.lam[0usize..5usize], cache.info[0usize..10usize]) == ok
        } else {
            let n = usize(z[3usize])
            var grid: [10]f64 = zero
            let ng = gf.grid_fill(5usize, grid[0usize..10usize])
            ok_fit = gf.fit_fkml(a, z[4usize..4usize + n], i32(z[0usize]), z[1usize], z[2usize], grid[0usize..ng], grid[0usize..ng], eps, 1.0e20f64, cache.lam[0usize..5usize], cache.info[0usize..10usize]) == ok
        }
        cache.good = ok_fit
    }
    if !cache.good { ret nan }
    let q = usize(last)
    if str.eq(c.name, "star") && q == 5usize { ret cache.info[6usize] }
    ret cache.lam[q]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/gldfit.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var cache = Cache { name: "", args: golden.cases[0usize].args, lam: zero, info: zero, good: false }
    cache.args = golden.cases[0usize].args[0usize..0usize]
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        let got = answer(a, c, &cache)
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
