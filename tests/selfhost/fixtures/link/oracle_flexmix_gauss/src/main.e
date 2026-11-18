// e.algo.stat.flexmixpkg against flexmix (the Gaussian regression mixture from a given initial clustering). tests/oracle/flexmix_gauss.json comes from
// `R_ORACLE_LIB=<dir> Rscript scripts/r_oracle/generate.R flexmix_gauss`; the layout is at the top of scripts/r_oracle/groups/flexmix_gauss.R.

use e.algo.rand.r as rg
use e.algo.stat.flexmixpkg as fx
use e.io
use e.mem
use e.os
use e.str
use e.test.oracle as oracle

fn answer_seeded(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let k = usize(z[2usize])
    let what = usize(z[3usize])
    let idx = usize(z[4usize])
    let x = z[6usize..6usize + n * p]
    let y = z[6usize + n * p..6usize + n * p + n]
    var rng: rg.Rng = zero
    rg.seed(&rng, i64(z[5usize]))
    let (f, e) = fx.gaussian_random(a, &rng, x, y, n, p, k, 200usize, 0.05f64, 0.000001f64)
    if e != ok { os.exit(5) }
    if what == 0usize { ret f.llh }
    if what == 1usize { ret f64(f.iter) }
    if what == 2usize { ret f64(f.k) }
    if what == 3usize { ret f.prior[idx] }
    if what == 4usize { ret f.coef[idx] }
    if what == 5usize { ret f.sigma[idx] }
    ret f64(f.cluster[idx] + 1usize)
}

fn answer(a: *mem.Arena, c: *const oracle.Case) -> f64 {
    if str.eq(c.name, "fs") { ret answer_seeded(a, c) }
    if str.eq(c.name, "st") {
        let zz = c.args
        let nn = usize(zz[0usize])
        let pp = usize(zz[1usize])
        let kk = usize(zz[2usize])
        let wh = usize(zz[3usize])
        let ix = usize(zz[4usize])
        let xs = zz[6usize..6usize + nn * pp]
        let ys = zz[6usize + nn * pp..6usize + nn * pp + nn]
        var rng: rg.Rng = zero
        rg.seed(&rng, i64(zz[5usize]))
        let (ll, g1) = mem.alloc[f64](a, 3usize)
        if g1 != ok { os.exit(4) }
        // k = 2 runs first from the stream, then k = 3, as stepFlexmix(k = 2:3) does
        var kc = 2usize
        var fb: fx.Fm = zero
        while kc <= kk {
            let (fbk, eb) = fx.step_gaussian(a, &rng, xs, ys, nn, pp, kc, 3usize, 200usize, 0.05f64, 0.000001f64, ll)
            if eb != ok { os.exit(5) }
            fb = fbk
            kc += 1usize
        }
        if wh == 0usize { ret fb.llh }
        if wh == 1usize { ret ll[ix] }
        if wh == 3usize { ret fb.prior[ix] }
        ret fb.coef[ix]
    }
    if str.eq(c.name, "fp") {
        let zz = c.args
        let nn = usize(zz[0usize])
        let pp = usize(zz[1usize])
        let kk = usize(zz[2usize])
        let wh = usize(zz[3usize])
        let ix = usize(zz[4usize])
        let xs = zz[5usize..5usize + nn * pp]
        let ys = zz[5usize + nn * pp..5usize + nn * pp + nn]
        let (i0, g0) = mem.alloc[f64](a, nn)
        if g0 != ok { os.exit(4) }
        var q = 0usize
        while q < nn {
            i0[q] = zz[5usize + nn * pp + nn + q] - 1.0f64
            q += 1usize
        }
        let (fp, ep) = fx.poisson(a, xs, ys, nn, pp, kk, i0, 200usize, 0.05f64, 0.000001f64)
        if ep != ok { os.exit(5) }
        if wh == 0usize { ret fp.llh }
        if wh == 1usize { ret f64(fp.iter) }
        if wh == 2usize { ret f64(fp.k) }
        if wh == 3usize { ret fp.prior[ix] }
        if wh == 4usize { ret fp.coef[ix] }
        if wh == 7usize { ret fx.aic(&fp) }
        if wh == 8usize { ret fx.bic(&fp, nn) }
        if wh == 9usize { ret fx.icl(&fp, nn) }
        ret f64(fp.cluster[ix] + 1usize)
    }
    let z = c.args
    let n = usize(z[0usize])
    let p = usize(z[1usize])
    let k = usize(z[2usize])
    let what = usize(z[3usize])
    let idx = usize(z[4usize])
    let x = z[5usize..5usize + n * p]
    let y = z[5usize + n * p..5usize + n * p + n]
    let (init1, e0) = mem.alloc[f64](a, n)
    if e0 != ok { os.exit(4) }
    var i = 0usize
    while i < n {
        init1[i] = z[5usize + n * p + n + i] - 1.0f64
        i += 1usize
    }
    // x is stored column pairs (1, x1) per row
    let (f, e) = fx.gaussian(a, x, y, n, p, k, init1, 200usize, 0.05f64, 0.000001f64)
    if e != ok { os.exit(5) }
    if what == 0usize { ret f.llh }
    if what == 1usize { ret f64(f.iter) }
    if what == 2usize { ret f64(f.k) }
    if what == 3usize { ret f.prior[idx] }
    if what == 4usize { ret f.coef[idx] }
    if what == 5usize { ret f.sigma[idx] }
    if what == 7usize { ret fx.aic(&f) }
    if what == 8usize { ret fx.bic(&f, n) }
    if what == 9usize { ret fx.icl(&f, n) }
    ret f64(f.cluster[idx] + 1usize)
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (golden, load_error) = oracle.load(a, "tests/oracle/flexmix_gauss.json")
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
