// e.algo.stat.mediationpkg against mediation::mediate (linear models, quasi-Bayesian) under set.seed. tests/oracle/mediation.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mediation`; the layout is at the top of scripts/r_oracle/groups/mediation.R.

use e.algo.rand.r as rng
use e.algo.stat.emmeans as em
use e.algo.stat.mediationpkg as md
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let sd = i64(z[0usize])
    let sims = usize(z[1usize])
    let conf = z[2usize]
    let n = usize(z[3usize])
    let tr = z[4usize..4usize + n]
    let xv = z[4usize + n..4usize + 2usize * n]
    let mv2 = z[4usize + 2usize * n..4usize + 3usize * n]
    let yv = z[4usize + 3usize * n..4usize + 4usize * n]
    let (dm, e1) = mem.alloc[f64](a, n * 3usize)
    let (dy, e2) = mem.alloc[f64](a, n * 4usize)
    if e1 != ok || e2 != ok { ret nan }
    var i = 0usize
    while i < n {
        dm[i] = 1.0f64
        dm[n + i] = tr[i]
        dm[2usize * n + i] = xv[i]
        dy[i] = 1.0f64
        dy[n + i] = tr[i]
        dy[2usize * n + i] = mv2[i]
        dy[3usize * n + i] = xv[i]
        i += 1usize
    }
    let (fm, fe1) = em.fit(a, dm, mv2, n, 3usize)
    let (fy, fe2) = em.fit(a, dy, yv, n, 4usize)
    if fe1 != ok || fe2 != ok { ret nan }
    var g: rng.Rng = zero
    rng.seed(&g, sd)
    var out: [16]f64 = zero
    if md.mediate_lm(a, &g, fm.beta, fm.cov, 3usize, 1usize, fy.beta, fy.cov, 4usize, 1usize, 2usize, sims, conf, out[0usize..16usize]) != ok { ret nan }
    ret out[usize(z[4usize + 4usize * n])]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mediation.json")
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
