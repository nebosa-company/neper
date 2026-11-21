// e.algo.stat.mediationpkg (mediate_qb, mediate_boot) against mediation::mediate for gaussian, probit, logit and poisson mediator models and gaussian, logit and probit outcome models, with and without the
// treatment-mediator interaction, quasi-Bayesian and bootstrap (percentile and BCa), under set.seed. tests/oracle/mediation2.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R mediation2`; the case layout and the data draws are at the top of scripts/r_oracle/groups/mediation2.R, which this fixture repeats draw for draw.

use e.algo.rand.r as rng
use e.algo.rand.rdist as rd
use e.algo.stat.mediationpkg as md
use e.io
use e.mem
use e.os
use e.test.oracle as oracle

fn answer(a: *mem.Arena, c: *const oracle.Case, out: []f64) -> f64 {
    let z = c.args
    let nan = 0.0f64 / 0.0f64
    let mtype = usize(z[0usize])
    let ytype = usize(z[1usize])
    let int = usize(z[2usize])
    let mode = usize(z[3usize])
    let s1 = i64(z[4usize])
    let n = usize(z[5usize])
    let sims = usize(z[6usize])
    let conf = z[7usize]
    let s2 = i64(z[8usize])
    let q = usize(z[9usize])
    var g: rng.Rng = zero
    rng.seed(&g, s1)
    let (x, e1) = mem.alloc[f64](a, n)
    let (tr, e2) = mem.alloc[f64](a, n)
    let (m, e3) = mem.alloc[f64](a, n)
    let (y, e4) = mem.alloc[f64](a, n)
    let (base, e5) = mem.alloc[f64](a, n * 2usize)
    if e1 != ok || e2 != ok || e3 != ok || e4 != ok || e5 != ok { ret nan }
    var i = 0usize
    while i < n {
        x[i] = rng.rnorm(&g, 0.0f64, 1.0f64)
        i += 1usize
    }
    i = 0usize
    while i < n {
        tr[i] = rd.rbinom(&g, 1.0f64, 0.5f64)
        i += 1usize
    }
    i = 0usize
    while i < n {
        var ind = 0.0f64
        if x[i] > 0.0f64 { ind = 1.0f64 }
        if mtype == 0usize { m[i] = 0.5f64 * tr[i] + 0.3f64 * x[i] + rng.rnorm(&g, 0.0f64, 1.0f64) }
        if mtype == 3usize { m[i] = rd.rpois(&g, 1.0f64 + 0.8f64 * tr[i] + 0.4f64 * ind) }
        if mtype == 1usize || mtype == 2usize { m[i] = rd.rbinom(&g, 1.0f64, 0.25f64 + 0.3f64 * tr[i] + 0.15f64 * ind) }
        i += 1usize
    }
    i = 0usize
    while i < n {
        var ind = 0.0f64
        if x[i] > 0.0f64 { ind = 1.0f64 }
        var mi = 0.0f64
        if m[i] > 0.0f64 { mi = 1.0f64 }
        if ytype == 0usize { y[i] = 0.4f64 * tr[i] + 0.6f64 * m[i] + 0.2f64 * x[i] + 0.3f64 * f64(int) * tr[i] * m[i] + rng.rnorm(&g, 0.0f64, 1.0f64) }
        if ytype != 0usize { y[i] = rd.rbinom(&g, 1.0f64, 0.3f64 + 0.2f64 * tr[i] + 0.15f64 * mi + 0.1f64 * ind) }
        base[i * 2usize] = 1.0f64
        base[i * 2usize + 1usize] = x[i]
        i += 1usize
    }
    var mcols: [6]usize = zero
    mcols[2usize] = 0usize
    mcols[3usize] = 1usize
    mcols[4usize] = 1usize
    var ycols: [15]usize = zero
    ycols[4usize] = 1usize
    ycols[8usize] = 1usize
    ycols[9usize] = 1usize
    ycols[12usize] = 0usize
    ycols[13usize] = 1usize
    ycols[14usize] = 1usize
    var mfam = 0usize
    var mlink = 0usize
    if mtype == 1usize {
        mfam = 1usize
        mlink = 4usize
    }
    if mtype == 2usize {
        mfam = 1usize
        mlink = 3usize
    }
    if mtype == 3usize {
        mfam = 2usize
        mlink = 1usize
    }
    var yfam = 0usize
    var ylink = 0usize
    if ytype == 1usize {
        yfam = 1usize
        ylink = 3usize
    }
    if ytype == 2usize {
        yfam = 1usize
        ylink = 4usize
    }
    let py = 4usize + int
    var none: []const f64 = zero
    let ms = md.Spec { base: base, n: n, q: 2usize, cols: mcols[0usize..6usize], step: 2usize, p: 3usize, fam: mfam, link: mlink, resp: m, tr: tr, mobs: none }
    let ys = md.Spec { base: base, n: n, q: 2usize, cols: ycols[0usize..3usize * py], step: 3usize, p: py, fam: yfam, link: ylink, resp: y, tr: tr, mobs: m }

    if mode == 0usize {
        let (xm, f1) = mem.alloc[f64](a, n * 3usize)
        let (xy, f2) = mem.alloc[f64](a, n * py)
        let (bm, f3) = mem.alloc[f64](a, 3usize)
        let (cm, f4) = mem.alloc[f64](a, 9usize)
        let (by, f5) = mem.alloc[f64](a, py)
        let (cy, f6) = mem.alloc[f64](a, py * py)
        if f1 != ok || f2 != ok || f3 != ok || f4 != ok || f5 != ok || f6 != ok { ret nan }
        md.design(&ms, tr, none, xm)
        md.design(&ys, tr, m, xy)
        var idn: []const i64 = zero
        let (sm, g1) = md.fit_model(a, &ms, xm, idn, bm, cm)
        let (sy, g2) = md.fit_model(a, &ys, xy, idn, by, cy)
        if g1 != ok || g2 != ok { ret nan }
        rng.seed(&g, s2)
        if md.mediate_qb(a, &g, &ms, bm, cm, sm, &ys, by, cy, 0.0f64, 1.0f64, sims, conf, out) != ok { ret nan }
    } else {
        rng.seed(&g, s2)
        if md.mediate_boot(a, &g, &ms, &ys, 0.0f64, 1.0f64, sims, conf, mode == 2usize, out) != ok { ret nan }
    }
    ret out[q]
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/mediation2.json")
    if load_error != ok { os.exit(2) }
    if golden.cases.len == 0usize { os.exit(3) }
    var failures = 0usize
    var at = 0usize
    var cache: [40]f64 = zero
    var key: [9]f64 = zero
    var have = false
    while at < golden.cases.len {
        let start = mem.mark(a)
        let c = &golden.cases[at]
        var same = have
        var k = 0usize
        while k < 9usize {
            if c.args[k] != key[k] { same = false }
            k += 1usize
        }
        var got = 0.0f64
        if same {
            got = cache[usize(c.args[9usize])]
        } else {
            got = answer(a, c, cache[0usize..40usize])
            k = 0usize
            while k < 9usize {
                key[k] = c.args[k]
                k += 1usize
            }
            have = true
        }
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
