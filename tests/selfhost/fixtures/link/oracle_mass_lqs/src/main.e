// e.algo.stat.masslqs and masscov against MASS lqs and cov.rob under set.seed. tests/oracle/mass_lqs.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_lqs`; the layout is at the top of scripts/r_oracle/groups/mass_lqs.R.

use e.algo.rand.r as rng
use e.algo.stat.masscov as mc
use e.algo.stat.masslqs as lq
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn nan() -> f64 { ret 0.0f64 / 0.0f64 }

fn wsum(v: []const f64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < v.len {
        s += f64(i + 1usize) * v[i]
        i += 1usize
    }
    ret s
}

fn wsum_i(v: []const i64, m: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += f64(i + 1usize) * f64(v[i] + 1i64)
        i += 1usize
    }
    ret s
}

fn wsum_i1(v: []const i64, m: usize) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += f64(i + 1usize) * f64(v[i])
        i += 1usize
    }
    ret s
}

fn answer_lqs(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    let n = usize(z[1usize])
    let p0 = usize(z[2usize])
    let off = 11usize
    let (fit, e) = lq.lqs(a, &g, z[off..off + n * p0], n, p0, z[off + n * p0..off + n * p0 + n], z[8usize] != 0.0f64, usize(z[3usize]), z[4usize], usize(z[5usize]), z[6usize], z[7usize] != 0.0f64, z[9usize])
    if e != ok { ret nan() }
    let mode = usize(z[10usize])
    if mode == 0usize { ret fit.crit }
    if mode == 1usize { ret wsum(fit.coef) }
    if mode == 2usize { ret fit.scale }
    if mode == 3usize { ret fit.scale2 }
    if mode == 4usize { ret wsum(fit.residuals) }
    if mode == 5usize { ret wsum_i1(fit.bestone, fit.bestone.len) }
    ret f64(fit.sing)
}

fn answer_cov(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let off = 7usize
    let (fit, e) = mc.cov_rob(a, &g, z[off..off + n * p], n, p, usize(z[3usize]), z[4usize], z[5usize])
    if e != ok { ret nan() }
    let mode = usize(z[6usize])
    if mode == 0usize { ret fit.crit }
    if mode == 1usize { ret wsum(fit.center) }
    if mode == 2usize { ret wsum(fit.cov) }
    if mode == 3usize { ret wsum_i(fit.best, fit.nbest) }
    if mode == 4usize { ret f64(fit.sing) }
    ret f64(fit.nbest)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "lqs") { ret answer_lqs(a, c) }
    ret answer_cov(a, c)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_lqs.json")
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
