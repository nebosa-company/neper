// MASS arguments and helpers the other mass_* fixtures leave out, against R: ginv tol, the psi functions, bw.* and MASS::ucv / bcv / width.SJ with every argument,
// kde2d grids and defaults, the histogram helpers, mvrnorm tol and empirical, lqs and cov.rob exact / sample resampling and the cor, n.obs and fitted outputs.
// tests/oracle/mass_gap.json comes from `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mass_gap`; the layouts are at the top of scripts/r_oracle/groups/mass_gap.R.

use e.algo.rand.r as rng
use e.algo.stat.bwgen as bg
use e.algo.stat.mass as ms
use e.algo.stat.masscov as mc
use e.algo.stat.massgap as mg
use e.algo.stat.masslqs as lq
use e.algo.stat.massrlm as rl
use e.io
use e.math
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

fn wsum_i(v: []const i64, m: usize, plus: i64) -> f64 {
    var s = 0.0f64
    var i = 0usize
    while i < m {
        s += f64(i + 1usize) * f64(v[i] + plus)
        i += 1usize
    }
    ret s
}

fn answer_ginv(a: *mem.Arena, z: []const f64) -> f64 {
    let m = usize(z[0usize])
    let n = usize(z[1usize])
    let (g, e) = ms.ginv_tol(a, z[3usize..3usize + m * n], m, n, z[2usize])
    if e != ok { ret nan() }
    ret wsum(g)
}

fn answer_psi(z: []const f64) -> f64 {
    var o = rl.default_opts()
    let kind = usize(z[0usize])
    let deriv = usize(z[1usize])
    // massrlm: 0 Huber, 1 Hampel, 2 bisquare
    o.psi = kind
    o.pa = z[2usize]
    if kind == 1usize {
        o.pb = z[3usize]
        o.pc = z[4usize]
    }
    if deriv == 0usize { ret rl.psi_w(&o, z[5usize]) }
    ret rl.psi_d(&o, z[5usize])
}

fn answer_bw(a: *mem.Arena, z: []const f64) -> f64 {
    let fn_ = usize(z[0usize])
    let nb = usize(z[1usize])
    var lo = z[2usize]
    var up = z[3usize]
    var tl = z[4usize]
    let x = z[5usize..z.len]
    if lo < 0.0f64 { lo = nan() }
    if up < 0.0f64 { up = nan() }
    if tl < 0.0f64 { tl = nan() }
    if fn_ == 0usize { ret bg.bw_cv_gen(a, x, 0u8, nb, lo, up, tl) }
    if fn_ == 1usize { ret bg.bw_cv_gen(a, x, 1u8, nb, lo, up, tl) }
    if fn_ == 2usize { ret bg.bw_sj_gen(a, x, nb, lo, up, tl, false) }
    if fn_ == 3usize { ret bg.bw_sj_gen(a, x, nb, lo, up, tl, true) }
    ret bg.bw_mass(a, x, fn_ - 4usize, nb, lo, up)
}

fn answer_kde(a: *mem.Arena, z: []const f64) -> f64 {
    let mode = usize(z[0usize])
    let n = usize(z[1usize])
    let n1 = usize(z[2usize])
    let n2 = usize(z[3usize])
    let hm = usize(z[4usize])
    let lg = z[7usize] != 0.0f64
    var at = 8usize
    let (lims, e0) = mem.alloc[f64](a, 4usize)
    if e0 != ok { ret nan() }
    if lg {
        lims[0usize] = z[at]
        lims[1usize] = z[at + 1usize]
        lims[2usize] = z[at + 2usize]
        lims[3usize] = z[at + 3usize]
        at += 4usize
    }
    let x = z[at..at + n]
    let y = z[at + n..at + 2usize * n]
    if !lg {
        lims[0usize] = x[0usize]
        lims[1usize] = x[0usize]
        lims[2usize] = y[0usize]
        lims[3usize] = y[0usize]
        var k = 0usize
        while k < n {
            if x[k] < lims[0usize] { lims[0usize] = x[k] }
            if x[k] > lims[1usize] { lims[1usize] = x[k] }
            if y[k] < lims[2usize] { lims[2usize] = y[k] }
            if y[k] > lims[3usize] { lims[3usize] = y[k] }
            k += 1usize
        }
    }
    var h1 = 0.0f64
    var h2 = 0.0f64
    if hm == 1usize {
        h1 = z[5usize]
        h2 = z[5usize]
    }
    if hm == 2usize {
        h1 = z[5usize]
        h2 = z[6usize]
    }
    if mode < 2usize {
        var len = n1
        var lo = lims[0usize]
        var hi = lims[1usize]
        if mode == 1usize {
            len = n2
            lo = lims[2usize]
            hi = lims[3usize]
        }
        let (g, e1) = mem.alloc[f64](a, len)
        if e1 != ok { ret nan() }
        ms.kde2d_grid(lo, hi, g)
        ret wsum(g)
    }
    let (zz, e2) = mem.alloc[f64](a, n1 * n2)
    if e2 != ok { ret nan() }
    if ms.kde2d(a, x, y, h1, h2, n1, n2, lims, zz) != ok { ret nan() }
    ret wsum(zz)
}

fn answer_hist(a: *mem.Arena, z: []const f64) -> f64 {
    let fn_ = usize(z[0usize])
    let src = usize(z[1usize])
    let x = z[3usize..z.len]
    if fn_ == 0usize { ret mg.nclass_freq(x) }
    if fn_ == 1usize { ret mg.nclass_scott(x) }
    if fn_ == 2usize { ret mg.nclass_fd(a, x) }
    var k = z[2usize]
    if src == 1usize { k = mg.nclass_freq(x) }
    if src == 2usize { k = mg.nclass_scott(x) }
    if src == 3usize { k = mg.nclass_fd(a, x) }
    let (b, cnt, e) = mg.hist_counts(a, x, k)
    if e != ok { ret nan() }
    if fn_ == 3usize { ret wsum(b) }
    if fn_ == 4usize { ret wsum(cnt) }
    if fn_ == 5usize { ret f64(b.len) }
    var s = 0.0f64
    var i = 0usize
    while i < cnt.len {
        s += f64(i + 1usize) * 0.5f64 * (b[i] + b[i + 1usize])
        i += 1usize
    }
    ret s
}

fn answer_mv(a: *mem.Arena, z: []const f64) -> f64 {
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    let mu = z[5usize..5usize + p]
    let sigma = z[5usize + p..5usize + p + p * p]
    let mode = usize(z[5usize + p + p * p])
    let (o, e) = mem.alloc[f64](a, n * p)
    if e != ok { ret nan() }
    if ms.mvrnorm_ex(a, &g, n, p, mu, sigma, z[3usize], z[4usize] != 0.0f64, o) != ok { ret nan() }
    var s = 0.0f64
    var i = 0usize
    while i < n * p {
        if mode == 0usize { s += o[i] }
        if mode == 1usize { s += o[i] * f64(i + 1usize) }
        if mode == 2usize { s += o[i] * o[i] }
        i += 1usize
    }
    ret s
}

fn answer_lqs(a: *mem.Arena, z: []const f64) -> f64 {
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    let n = usize(z[1usize])
    let p0 = usize(z[2usize])
    let off = 8usize
    let x = z[off..off + n * p0]
    let y = z[off + n * p0..off + n * p0 + n]
    let (fit, e) = lq.lqs(a, &g, x, n, p0, y, true, usize(z[3usize]), 0.0f64 - 1.0f64, 0usize, z[4usize], z[5usize] != 0.0f64, z[6usize])
    if e != ok { ret nan() }
    let mode = usize(z[7usize])
    if mode == 0usize { ret fit.crit }
    if mode == 1usize { ret wsum(fit.coef) }
    if mode == 2usize { ret fit.scale }
    if mode == 3usize { ret fit.scale2 }
    if mode == 4usize { ret wsum(fit.residuals) }
    if mode == 5usize {
        // fitted.values: y - residuals (for the S method the IWLS refinement's fit, not x %*% coefficients)
        var s = 0.0f64
        var i = 0usize
        while i < n {
            s += f64(i + 1usize) * (y[i] - fit.residuals[i])
            i += 1usize
        }
        ret s
    }
    if mode == 6usize { ret wsum_i(fit.bestone, fit.bestone.len, 0i64) }
    ret f64(fit.sing)
}

fn answer_cov(a: *mem.Arena, z: []const f64) -> f64 {
    var g: rng.Rng = zero
    rng.seed(&g, i64(z[0usize]))
    let n = usize(z[1usize])
    let p = usize(z[2usize])
    let off = 7usize
    let (fit, e) = mc.cov_rob(a, &g, z[off..off + n * p], n, p, usize(z[3usize]), 0.0f64 - 1.0f64, z[4usize])
    if e != ok { ret nan() }
    let mode = usize(z[6usize])
    if mode == 0usize { ret fit.crit }
    if mode == 1usize { ret wsum(fit.center) }
    if mode == 2usize {
        if z[5usize] == 0.0f64 { ret wsum(fit.cov) }
        var s = 0.0f64
        var i = 0usize
        while i < p * p {
            let r = i % p
            let c = i / p
            s += f64(i + 1usize) * fit.cov[i] / math.sqrt[f64](fit.cov[r + p * r] * fit.cov[c + p * c])
            i += 1usize
        }
        ret s
    }
    if mode == 3usize { ret wsum_i(fit.best, fit.nbest, 1i64) }
    if mode == 4usize { ret f64(fit.sing) }
    ret f64(n)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    if str.eq(c.name, "ginv") { ret answer_ginv(a, z) }
    if str.eq(c.name, "psi") { ret answer_psi(z) }
    if str.eq(c.name, "bw") { ret answer_bw(a, z) }
    if str.eq(c.name, "kde2d") { ret answer_kde(a, z) }
    if str.eq(c.name, "hist") { ret answer_hist(a, z) }
    if str.eq(c.name, "mv") { ret answer_mv(a, z) }
    if str.eq(c.name, "lqs") { ret answer_lqs(a, z) }
    ret answer_cov(a, z)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mass_gap.json")
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
