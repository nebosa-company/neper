// e.algo.stat.micepkg against mice: the chained-equations sampler for norm.nob, norm and norm.predict after set.seed.
// tests/oracle/mice.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mice`; the layout is at
// the top of scripts/r_oracle/groups/mice.R.

use e.algo.stat.micepkg as mc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn oracle_is_pool(c: *const oracle.Case) -> bool { ret str.eq(c.name, "pool") }

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    if oracle_is_pool(c) {
        let pm = usize(z[0usize])
        let (po, pe) = mem.alloc[f64](a, 7usize)
        if pe != ok { ret nan }
        mc.pool_scalar(z[2usize..2usize + pm], z[2usize + pm..2usize + 2usize * pm], z[1usize], 1.0f64, po)
        ret po[usize(z[2usize + 2usize * pm])]
    }
    if str.eq(c.name, "imp2") {
        let n2 = usize(z[0usize])
        let p2 = usize(z[1usize])
        let nv = usize(z[6usize + n2 * p2 + p2 * p2])
        let (imp2, e2) = mem.alloc[f64](a, n2 * p2 * usize(z[2usize]) + 4usize)
        if e2 != ok { ret nan }
        let b = 6usize + n2 * p2
        let me2 = mc.mice_norm(a, z[6usize..b], n2, p2, usize(z[2usize]), usize(z[3usize]), usize(z[4usize]), i64(z[5usize]), imp2, z[b..b + p2 * p2], z[b + p2 * p2 + 1usize..b + p2 * p2 + 1usize + nv])
        if me2 != ok { ret nan }
        ret imp2[usize(z[b + p2 * p2 + 1usize + nv])]
    }
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let m = usize(z[2usize])
    let maxit = usize(z[3usize])
    let method = usize(z[4usize])
    let seed = i64(z[5usize])
    let data = z[6usize..6usize + n * p]
    let idx = usize(z[6usize + n * p])
    let (imp, e) = mem.alloc[f64](a, n * p * m + 4usize)
    if e != ok { ret nan }
    let me = mc.mice_norm(a, data, n, p, m, maxit, method, seed, imp, z[0usize..0usize], z[0usize..0usize])
    if me != ok { ret nan }
    ret imp[idx]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mice.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    while at < golden.cases.len {
        let c = &golden.cases[at]
        let got = answer(a, c)
        if !oracle.agrees(got, c) {
            failures += 1usize
            if failures <= 12usize {
                let _ = io.print(oracle.describe(a, c, got))
                let _ = io.print("\n")
            }
        }
        at += 1usize
    }
    if failures > 0usize { os.exit(1) }
    ret ok
}
