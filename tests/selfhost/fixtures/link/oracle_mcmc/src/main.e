// e.algo.stat.mcmcpkg against mcmc::metrop under set.seed. tests/oracle/mcmc.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mcmc`; the layout is at the top of scripts/r_oracle/groups/mcmc.R.

use e.algo.rand.r as rng
use e.algo.stat.mcmcpkg as mc
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let seed = i64(z[0usize])
    let id = usize(z[1usize])
    let d = usize(z[2usize])
    let nb = usize(z[3usize])
    let bl = usize(z[4usize])
    let ns = usize(z[5usize])
    let init = z[6usize..6usize + d]
    let sc = z[6usize + d..6usize + 2usize * d]
    let (batch, e1) = mem.alloc[f64](a, nb * d)
    let (accb, e2) = mem.alloc[f64](a, nb)
    let (fin, e3) = mem.alloc[f64](a, d)
    if e1 != ok || e2 != ok || e3 != ok { ret nan }
    var g: rng.Rng = zero
    rng.seed(&g, seed)
    if mc.metrop(a, &g, id, init, nb, bl, ns, sc, batch, accb, fin) != ok { ret nan }
    var s = 0.0f64
    var i = 0usize
    if str.eq(c.name, "batch") {
        while i < nb * d {
            s += f64(i + 1usize) * batch[i]
            i += 1usize
        }
        ret s
    }
    if str.eq(c.name, "acc") {
        while i < nb {
            s += f64(i + 1usize) * accb[i]
            i += 1usize
        }
        ret s
    }
    while i < d {
        s += f64(i + 1usize) * fin[i]
        i += 1usize
    }
    ret s
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mcmc.json")
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
