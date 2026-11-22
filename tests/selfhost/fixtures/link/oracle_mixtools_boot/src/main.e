// e.algo.stat.mixtools_boot (boot.se and the helpers perm, wquantile, wkde, ddirichlet, rnormmix) against mixtools. tests/oracle/mixtools_boot.json
// comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mixtools_boot`; the argument layouts are at the top of scripts/r_oracle/groups/mixtools_boot.R.

use e.algo.rand.r as rg
use e.algo.stat.mixtools as mt
use e.algo.stat.mixtools_boot as bt
use e.algo.stat.mixtools_mult as mm
use e.algo.stat.mixtools_mv as mv
use e.algo.stat.mixtools_reg as rgm
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn pick(b: bt.Boot, sel: usize, idx: usize) -> f64 {
    if sel == 1usize { ret b.se1[idx - 1usize] }
    if sel == 2usize { ret b.se2[idx - 1usize] }
    if sel == 3usize { ret b.se3[idx - 1usize] }
    var s = 0.0f64
    var j = 0usize
    while j < b.nb {
        if sel == 4usize { s += b.p1[(idx - 1usize) * b.nb + j] }
        if sel == 5usize { s += b.p2[(idx - 1usize) * b.nb + j] }
        if sel == 6usize { s += b.p3[(idx - 1usize) * b.nb + j] }
        j += 1usize
    }
    ret s
}

// [sel, idx, seed, k, arbvar, B, n, x(n), lambda(k), mu(k), sigma(k or 1)]
fn answer_bn(a: *mem.Arena, x: []const f64) -> f64 {
    var g: rg.Rng = zero
    let k = usize(x[3usize])
    let arbvar = x[4usize] != 0.0f64
    let n = usize(x[6usize])
    let data = x[7usize..7usize + n]
    let lam = x[7usize + n..7usize + n + k]
    let mu = x[7usize + n + k..7usize + n + 2usize * k]
    var ns = 1usize
    if arbvar { ns = k }
    let sg = x[7usize + n + 2usize * k..7usize + n + 2usize * k + ns]
    rg.seed(&g, 1i64)
    let (f, e) = mt.normal_mix_em(a, &g, data, lam, mu, sg, k, true, arbvar, 1.0e-8f64, 1000usize, 20usize)
    if e != ok { os.exit(8) }
    rg.seed(&g, i64(x[2usize]))
    let b = bt.boot_se_normal(a, &g, n, k, f.lambda, f.mu, f.sigma, arbvar, usize(x[5usize]))
    ret pick(b, usize(x[0usize]), usize(x[1usize]))
}

// [sel, idx, seed, k, arbvar, B, n, q, x(n q), y(n), lambda(k), beta(p k), sigma(k or 1)]
fn answer_br(a: *mem.Arena, x: []const f64) -> f64 {
    var g: rg.Rng = zero
    let k = usize(x[3usize])
    let arbvar = x[4usize] != 0.0f64
    let n = usize(x[6usize])
    let q = usize(x[7usize])
    let p = q + 1usize
    let xp = x[8usize..8usize + n * q]
    let y = x[8usize + n * q..8usize + n * q + n]
    let at = 8usize + n * q + n
    let lam = x[at..at + k]
    let be = x[at + k..at + k + p * k]
    var ns = 1usize
    if arbvar { ns = k }
    let sg = x[at + k + p * k..at + k + p * k + ns]
    rg.seed(&g, 1i64)
    let (f, e) = rgm.reg_mix_em(a, &g, y, xp, q, true, lam, be, sg, k, true, arbvar, 1.0e-8f64, 10000usize)
    if e != ok { os.exit(8) }
    rg.seed(&g, i64(x[2usize]))
    let b = bt.boot_se_reg(a, &g, xp, n, q, k, f.lambda, f.beta, f.sigma, arbvar, usize(x[5usize]))
    ret pick(b, usize(x[0usize]), usize(x[1usize]))
}

// [sel, idx, seed, k, arbvar, B, n, p, x(n p), lambda(k), mu(k p), sigma(nb p p)]
fn answer_bv(a: *mem.Arena, x: []const f64) -> f64 {
    var g: rg.Rng = zero
    let k = usize(x[3usize])
    let arbvar = x[4usize] != 0.0f64
    let n = usize(x[6usize])
    let p = usize(x[7usize])
    let data = x[8usize..8usize + n * p]
    let at = 8usize + n * p
    let lam = x[at..at + k]
    let mu = x[at + k..at + k + k * p]
    var nb = 1usize
    if arbvar { nb = k }
    let sg = x[at + k + k * p..at + k + k * p + nb * p * p]
    rg.seed(&g, 1i64)
    let (f, e) = mv.mvnormal_mix_em(a, &g, data, n, p, lam, mu, sg, k, true, arbvar, 1.0e-8f64, 10000usize)
    if e != ok { os.exit(8) }
    rg.seed(&g, i64(x[2usize]))
    let b = bt.boot_se_mvnormal(a, &g, n, p, k, f.lambda, f.mu, f.sigma, arbvar, usize(x[5usize]))
    ret pick(b, usize(x[0usize]), usize(x[1usize]))
}

// [sel, idx, seed, k, B, n, p, y(n p), lambda(k), theta(k p)]
fn answer_bm(a: *mem.Arena, x: []const f64) -> f64 {
    var g: rg.Rng = zero
    let k = usize(x[3usize])
    let n = usize(x[5usize])
    let p = usize(x[6usize])
    let y = x[7usize..7usize + n * p]
    let at = 7usize + n * p
    let lam = x[at..at + k]
    let th = x[at + k..at + k + k * p]
    rg.seed(&g, 1i64)
    let (f, e) = mm.mult_mix_em(a, &g, y, n, p, lam, th, k, 10000usize, 1.0e-8f64)
    if e != ok { os.exit(8) }
    rg.seed(&g, i64(x[2usize]))
    let b = bt.boot_se_mult(a, &g, y, n, p, k, f.lambda, f.theta, usize(x[4usize]))
    ret pick(b, usize(x[0usize]), usize(x[1usize]))
}

// [r, n, row, col, v(n)]
fn answer_perm(a: *mem.Arena, x: []const f64) -> f64 {
    let r = usize(x[0usize])
    let n = usize(x[1usize])
    var cap = 1usize
    var t = 0usize
    while t < r {
        cap = cap * (n - t)
        t += 1usize
    }
    let out = mt.buf(a, cap * r + 1usize)
    let rows = bt.perm(a, n, r, x[4usize..4usize + n], out)
    if usize(x[3usize]) == 0usize { ret f64(rows) }
    ret out[(usize(x[2usize]) - 1usize) * r + usize(x[3usize]) - 1usize]
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let kind = c.name
    let x = c.args
    if str.eq(kind, "bn") { ret answer_bn(a, x) }
    if str.eq(kind, "br") { ret answer_br(a, x) }
    if str.eq(kind, "bv") { ret answer_bv(a, x) }
    if str.eq(kind, "bm") { ret answer_bm(a, x) }
    if str.eq(kind, "perm") { ret answer_perm(a, x) }
    if str.eq(kind, "wq") {
        let n = usize(x[1usize])
        ret bt.wquantile(a, x[2usize + n..2usize + 2usize * n], x[2usize..2usize + n], x[0usize])
    }
    if str.eq(kind, "wk") {
        let n = usize(x[3usize])
        let xs = x[4usize..4usize + n]
        let w = x[4usize + n..4usize + 2usize * n]
        var v = bt.wkde(xs, x[1usize], w, x[2usize])
        if x[0usize] != 0.0f64 { v = (v + bt.wkde(xs, 0.0f64 - x[1usize], w, x[2usize])) / 2.0f64 }
        ret v
    }
    if str.eq(kind, "dd") {
        let d = usize(x[0usize])
        ret bt.ddirichlet(x[1usize..1usize + d], x[1usize + d..1usize + 2usize * d])
    }
    if str.eq(kind, "rn") {
        var g: rg.Rng = zero
        rg.seed(&g, i64(x[0usize]))
        let n = usize(x[1usize])
        let m = usize(x[2usize])
        let out = mt.buf(a, n)
        let e = bt.rnormmix(a, &g, n, x[4usize..4usize + m], x[4usize + m..4usize + 2usize * m], x[4usize + 2usize * m..4usize + 3usize * m], out)
        if e != ok { os.exit(8) }
        ret out[usize(x[3usize]) - 1usize]
    }
    os.exit(4)
    ret 0.0f64
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mixtools_boot.json")
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
